# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 47 — `Game`'s protected remainder: `Dispose(Boolean)`, `Finalize` and
# `ShowMissingRequirementMessage(Exception)`.
#
# All three are `family` in the pinned metadata, and all three are real identities rather than CLR
# machinery: `Dispose(Boolean)` carries the whole managed teardown, `Finalize` is the finalizer path
# that deliberately does nothing, and `ShowMissingRequirementMessage` is the reason `RunGame` has two
# catch clauses at all.
class GameDisposalTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  A = Microsoft::Xna::Framework::Audio
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  def game_members = REFERENCE.fetch("Microsoft.Xna.Framework.Game").fetch("members")

  # ------------------------------------------------------------------------- the pinned contract

  def test_all_three_are_protected_instance_members
    expected = {
      "Dispose" => ["System.Void", %w[System.Boolean]],
      "Finalize" => ["System.Void", []],
      "ShowMissingRequirementMessage" => ["System.Boolean", %w[System.Exception]]
    }
    expected.each do |name, (returns, parameters)|
      member = game_members.find do |entry|
        entry.fetch("name") == name && entry.fetch("kind") == "method" &&
          entry.fetch("parameters").map { |parameter| parameter.fetch("type") } == parameters
      end
      refute_nil member, name
      assert_equal "protected", member.fetch("access"), name
      assert_equal returns, member.fetch("returnType"), name
      assert_equal false, member.fetch("static"), name
    end
    # Dispose is declared twice: the public parameterless one and the protected Boolean one.
    assert_equal 2, game_members.count { |member| member.fetch("name") == "Dispose" }
  end

  def test_the_remainder_is_empty_now_that_content_landed
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
                      .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    assert_empty remainder, "Content was the last one"
    assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Game")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    # 42 until the GraphicsDeviceManager preferences milestone closed ApplyChanges and
    # ToggleFullScreen, and 40 until the GraphicsResource disposal contract closed four more --
    # its own two plus the Texture2D and SpriteBatch overrides that inherit it, and 36 until
    # SaveAsPng and SaveAsJpeg landed.
    assert_equal 34, STRICT.fetch("OVERLOAD_MAPPING_MISMATCH")
  end

  # Ruby cannot give one name two visibilities, so the arity dispatch widens the protected overload
  # to public — the same recorded mapping limitation `GameComponent` carries.
  def test_the_two_overloads_are_one_ruby_method_dispatching_on_arity
    method = F::Game.instance_method(:Dispose)
    assert_equal(-1, method.arity)
    assert F::Game.public_method_defined?(:Dispose)
    assert_equal 1, F::Game.instance_methods.count { |name| name == :Dispose }
  end

  # ------------------------------------------------------------------------------ Dispose(false)

  # `Dispose(Boolean)` opens `ldarg.1; brfalse IL_0094` — straight to `ret`. Nothing at all happens.
  def test_dispose_false_does_nothing_and_leaves_the_game_usable
    game = F::Game.new
    begin
      raised = []
      game.Disposed.add { |sender, _args| raised << sender }
      assert_nil game.Dispose(false)
      assert_empty raised
      refute game.instance_variable_get(:@disposed)
      # Still fully usable afterwards: nothing was torn down.
      refute game.IsActive
      assert_equal 0, game.Components.Count
    ensure
      game.Dispose
    end
  end

  def test_dispose_true_and_the_parameterless_form_are_the_same_teardown
    raised = []
    game = F::Game.new
    game.Disposed.add { |sender, _args| raised << sender }
    game.Dispose(true)
    assert_equal [game], raised
    assert game.instance_variable_get(:@disposed)

    other = F::Game.new
    seen = []
    other.Disposed.add { |sender, _args| seen << sender }
    other.Dispose
    assert_equal [other], seen
  end

  # ---------------------------------------------------------------------------------- Finalize

  # `Finalize()` is `try { Dispose(false); } finally { base.Finalize(); }`, and `Dispose(false)`
  # returns immediately, so the finalizer path does nothing observable.
  def test_finalize_is_the_dispose_false_path_and_observes_nothing
    game = F::Game.new
    begin
      raised = []
      game.Disposed.add { |sender, _args| raised << sender }
      assert_nil game.__send__(:Finalize)
      assert_empty raised
      refute game.instance_variable_get(:@disposed)
    ensure
      game.Dispose
    end
  end

  # `GC.SuppressFinalize` in `Dispose()` needs no analogue because nothing here registers a Ruby
  # finalizer to suppress. The binding registers none anywhere, which is what makes that true.
  def test_no_object_space_finalizer_is_registered_anywhere
    # Comment lines are stripped: several of them name both, which is where the decision is recorded.
    code = Dir[ROOT.join("lib", "**", "*.rb")].flat_map do |path|
      File.readlines(path).reject { |line| line.strip.start_with?("#") }
    end
    refute(code.any? { |line| line.include?("define_finalizer") }, "no Ruby finalizer is registered")
    refute(code.any? { |line| line.include?("ObjectSpace") }, "nothing reaches ObjectSpace")
  end

  # ------------------------------------------------------------------------------- the lock

  # XNA's `Dispose(Boolean)` body runs under `Monitor.Enter(this)`. Foundation 41 recorded not
  # taking it as a deviation precisely because the member was missing; it is taken now.
  def test_the_disposal_body_runs_under_a_reentrant_monitor
    game = F::Game.new
    assert_instance_of ::Monitor, game.instance_variable_get(:@monitor)
    inside = nil
    game.Disposed.add do |_sender, _args|
      # A CLR `lock (this)` is reentrant, which is why `::Monitor` is its analogue and `Mutex` is
      # not: a handler re-entering the lock must not deadlock.
      inside = game.instance_variable_get(:@monitor).mon_owned?
      game.Dispose
    end
    game.Dispose
    assert_equal true, inside
  end

  # ------------------------------------------------------------- ShowMissingRequirementMessage

  # `GameHost.ShowMissingRequirementMessage` is `ldc.i4.0; ret`, and only `WindowsGameHost`
  # overrides it. CNA is not `WindowsGameHost` and the canonical C ABI exposes no such route, so
  # the base's honest `false` is what this answers.
  def test_it_answers_false_and_claims_no_message_facility
    game = F::Game.new
    begin
      refute game.__send__(:ShowMissingRequirementMessage, G::NoSuitableGraphicsDeviceException.new)
      refute game.__send__(:ShowMissingRequirementMessage, A::NoAudioHardwareException.new)
      refute game.__send__(:ShowMissingRequirementMessage, RuntimeError.new("anything"))
    ensure
      game.Dispose
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |symbol| symbol.include?("message_box") || symbol.include?("missing") })
  end

  # The two catch clauses are live: a subclass raising either exception from a lifecycle callback
  # reaches them, and the default `false` rethrows.
  def test_run_rethrows_both_requirement_exceptions_by_default
    [G::NoSuitableGraphicsDeviceException, A::NoAudioHardwareException].each do |klass|
      failing = Class.new(F::Game) do
        define_method(:Initialize) { raise klass, "missing" }
      end
      game = failing.new
      begin
        error = assert_raises(klass) { game.Run }
        assert_equal "missing", error.message
      ensure
        game.Dispose
      end
    end
  end

  # And an override that answers true really suppresses them, which is the whole point of the member.
  def test_an_override_answering_true_suppresses_them
    seen = []
    swallowing = Class.new(F::Game) do
      define_method(:Initialize) { raise G::NoSuitableGraphicsDeviceException, "missing" }
      define_method(:ShowMissingRequirementMessage) do |exception|
        seen << exception.class
        true
      end
    end
    game = swallowing.new
    begin
      assert_nil game.Run
      assert_equal [G::NoSuitableGraphicsDeviceException], seen
    ensure
      game.Dispose
    end
  end

  # An unrelated exception is not caught: only the two the IL names are.
  def test_an_unrelated_exception_is_not_swallowed
    swallowing = Class.new(F::Game) do
      define_method(:Initialize) { raise ArgumentError, "unrelated" }
      define_method(:ShowMissingRequirementMessage) { |_exception| true }
    end
    game = swallowing.new
    begin
      assert_raises(ArgumentError) { game.Run }
    ensure
      game.Dispose
    end
  end

  # `RunGame`'s `finally` clears `inRun` unless `endRunRequired`, which only `StartGameLoop` sets.
  # Keeping it in the method rather than only in the `EndRun` hook is what makes it survive a run
  # that ends by raising, where `EndRun` is never delivered.
  def test_in_run_is_cleared_even_when_the_run_ends_by_raising
    failing = Class.new(F::Game) do
      define_method(:Initialize) { raise ArgumentError, "boom" }
    end
    game = failing.new
    begin
      assert_raises(ArgumentError) { game.Run }
      assert_equal false, game.instance_variable_get(:@in_run)
    ensure
      game.Dispose
    end
  end
end
