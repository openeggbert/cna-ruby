# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 44 — `Game.Tick`.
#
# `Tick` and `RunOneFrame` are two different XNA operations, and the pinned Game.dll IL settles it
# in one line each: `Game.RunOneFrame` is `host?.RunOneFrame()`, and `WindowsGameHost.RunOneFrame`
# is `gameWindow.Tick()` (rethrow the pump's captured exception), `GameHost.OnIdle()` — whose only
# subscriber is `Game.HostIdle`, whose whole body is `this.Tick()` — and the `Guide.IsVisible` relay.
# So `RunOneFrame` is host-event processing wrapped around `Tick`, which is exactly the split the
# canonical C ABI already documents. The difference is XNA's own and is preserved, never aliased.
class GameTickTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  # A Game that records exactly which overridable members the host delivered, in order.
  class Recorder < F::Game
    attr_reader :log

    def initialize
      @log = []
      super
    end

    def Initialize
      @log << :initialize
      super
    end

    def LoadContent = @log << :load_content
    def UnloadContent = @log << :unload_content
    def BeginRun = @log << :begin_run
    def EndRun = @log << :end_run

    def Update(gameTime)
      @log << [:update, gameTime.TotalGameTime, gameTime.ElapsedGameTime]
      super
    end

    def Draw(gameTime)
      @log << :draw
      super
    end

    def BeginDraw
      @log << :begin_draw
      true
    end

    def EndDraw = @log << :end_draw
  end

  def with_game(klass = Recorder)
    game = klass.new
    yield game
  ensure
    game&.Dispose
  end

  def names(log) = log.map { |entry| entry.is_a?(Array) ? entry.first : entry }

  # ------------------------------------------------------------------------- the pinned contract

  def test_tick_is_a_public_parameterless_void_instance_method
    member = REFERENCE.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                      .find { |entry| entry.fetch("name") == "Tick" }
    refute_nil member
    assert_equal "method", member.fetch("kind")
    assert_equal "public", member.fetch("access")
    assert_equal "System.Void", member.fetch("returnType")
    assert_empty member.fetch("parameters")
    assert_empty member.fetch("genericParameters")
    assert_equal false, member.fetch("static")
  end

  # `Tick` and `RunOneFrame` have the same signature in the metadata, which is exactly why they
  # could be confused for each other. They are separate identities and both are selected.
  def test_tick_and_run_one_frame_are_two_separate_selected_identities
    selected = SIGNATURES.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                         .select { |member| member.fetch("kind") == "method" }
                         .map { |member| member.fetch("name") }
    assert_includes selected, "Tick"
    assert_includes selected, "RunOneFrame"
    refute_equal F::Game.instance_method(:Tick), F::Game.instance_method(:RunOneFrame)
  end

  def test_tick_is_no_longer_missing_and_the_remainder_shrank_by_one
    remainder = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
    refute(remainder.any? { |entry| entry.include?("::Tick ") }, remainder.inspect)
    assert_equal 115, STRICT.fetch("MISSING_MEMBER")
  end

  # ---------------------------------------------------------------- the two are never the same call

  # The regression this milestone exists to prevent: a later "simplification" that makes one of
  # these forward to the other. They are separately bound native symbols, and neither Ruby method
  # calls the other.
  def test_tick_and_run_one_frame_bind_different_native_symbols
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_game_tick"
    assert_includes symbols, "cna_game_run_one_frame"
    source = ROOT.join("lib", "cna", "runtime", "game_host.rb").read
    assert_match(/def tick\b.*?cna_game_tick/m, source)
    assert_match(/def run_one_frame\b.*?cna_game_run_one_frame/m, source)
  end

  def test_tick_delivers_no_host_frame_and_run_one_frame_does
    with_game do |game|
      game.Tick
      assert_equal %i[update begin_draw draw end_draw], names(game.log)
    end
    with_game do |game|
      game.RunOneFrame
      assert_equal %i[initialize load_content update begin_draw draw end_draw], names(game.log)
    end
  end

  # ---------------------------------------------------------------------------- the ShouldExit latch

  # `Tick`'s first instruction is `if (ShouldExit) return`, `get_ShouldExit` is one
  # `ldfld exitRequested`, and `exitRequested` is written exactly once in the whole assembly — by
  # `Game.Exit()` — and never cleared. So `Exit` disables `Tick` permanently.
  def test_exit_makes_tick_a_permanent_no_op
    with_game do |game|
      game.Tick
      refute_empty game.log
      game.Exit
      game.log.clear
      5.times { game.Tick }
      assert_empty game.log
    end
  end

  # The latch is managed state, so it works on a Game that has never had a native host: no host is
  # created either.
  def test_exit_before_the_first_tick_leaves_the_game_hostless
    with_game do |game|
      game.Exit
      game.Tick
      assert_empty game.log
      assert_nil game.instance_variable_get(:@host)
    end
  end

  # The measured reason the latch is projected rather than delegated: CNA's own step, after
  # `cna_game_request_exit`, still delivers one Update and skips only the Draw. That is one callback
  # more than XNA delivers, so the guard has to be on this side.
  def test_the_native_step_alone_would_deliver_one_more_update_than_xna
    with_game do |game|
      game.Tick
      host = game.instance_variable_get(:@host)
      host.request_exit
      game.log.clear
      host.tick
      assert_equal [:update], names(game.log)
    end
  end

  # ------------------------------------------------------------------------------ what Tick delivers

  # `Tick` initialises nothing: XNA's `Initialize`/`BeginRun` live in `RunGame`, not here. A Game
  # driven only by `Tick` therefore never sees them, and `Run` afterwards still delivers both.
  def test_tick_never_delivers_initialize_or_begin_run_and_run_still_does
    with_game do |game|
      3.times { game.Tick }
      refute_includes names(game.log), :initialize
      refute_includes names(game.log), :begin_run
      refute_includes names(game.log), :load_content
    end
  end

  # Fixed time step is the constructor default, so every tick advances TotalGameTime by exactly one
  # TargetElapsedTime and reports that same span as ElapsedGameTime.
  def test_the_fixed_step_advances_total_game_time_by_exactly_one_target_step
    with_game do |game|
      step = game.TargetElapsedTime
      5.times { game.Tick }
      updates = game.log.select { |entry| entry.is_a?(Array) }
      assert_equal 5, updates.length
      updates.each_with_index do |(_, total, elapsed), index|
        assert_in_delta step, elapsed, 1e-9
        assert_in_delta step * (index + 1), total, 1e-9
      end
    end
  end

  # `V_0` starts true and is ANDed with `suppressDraw` after each Update; the field is cleared in
  # the same breath, so exactly one frame's draw is skipped.
  def test_suppress_draw_skips_exactly_the_next_tick_s_draw
    with_game do |game|
      game.Tick
      game.log.clear
      game.SuppressDraw
      game.Tick
      assert_equal [:update], names(game.log)
      game.log.clear
      game.Tick
      assert_equal %i[update begin_draw draw end_draw], names(game.log)
    end
  end

  # ------------------------------------------------------------------------------ refused states

  def test_tick_on_a_disposed_game_raises
    game = F::Game.new
    game.Dispose
    assert_raises(CNA::DisposedObjectError) { game.Tick }
  end

  def test_tick_off_the_owner_thread_raises
    with_game do |game|
      game.Tick
      error = nil
      Thread.new do
        Thread.current.report_on_exception = false
        begin
          game.Tick
        rescue Exception => exception
          error = exception
        end
      end.join
      assert_instance_of CNA::OwnerThreadError, error
    end
  end

  # Recorded deviation. CNA refuses a frame step from inside a lifecycle callback, "because a frame
  # step called from within a frame would re-enter the loop it is part of". XNA has no such guard,
  # but it also has no usable behaviour there: the recursive frame re-enters with
  # `accumulatedElapsedGameTime` not yet decremented by the loop's `finally`, so its `num` is again
  # at least one and the recursion is unbounded. The refusal is surfaced as CNA's own translated
  # error rather than pre-empted, so the message a consumer sees is the native contract's.
  def test_tick_from_inside_a_lifecycle_callback_is_refused_by_cna
    reentrant = Class.new(F::Game) do
      def Update(gameTime)
        self.Tick
      end
    end
    with_game(reentrant) do |game|
      error = assert_raises(CNA::NativeError) { game.Tick }
      assert_equal "cna_game_tick", error.operation
      assert_match(/lifecycle callback/, error.message)
    end
  end

  # ------------------------------------------------------------------------------- nothing invented

  # Tick claims no host-event processing, no Guide relay and no window pump: those are the three
  # steps `RunOneFrame` has and it does not, and none of them is fabricated here. `IsActive` is a
  # separate identity that Foundation 45 completed from its own IL, not from anything Tick implies.
  def test_tick_adds_no_guide_or_window_surface
    refute F::Game.public_method_defined?(:Window)
    refute F::Game.const_defined?(:Guide, false)
    refute Object.const_defined?(:System)
  end
end
