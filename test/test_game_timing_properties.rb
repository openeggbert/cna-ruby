# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 42 — Game's four timing and presentation properties.
#
# In the pinned IL every getter is one `ldfld`: these are managed fields that the host loop reads,
# not native queries. So the projection keeps managed state authoritative -- it answers on a Game
# that has never run, which is what XNA does -- and each setter pushes the new value down to CNA
# once a native host exists. The two settings `CNA_GameCreateInfo` carries are taken from that same
# state, so a value set before the first `Run` is the value the host is created with.
class GameTimingPropertiesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  NAMES = %w[IsFixedTimeStep TargetElapsedTime InactiveSleepTime IsMouseVisible].freeze

  # `TimeSpan.FromTicks(0x28b0b)`; deliberately not 1.0/60, which is a different Float.
  TARGET_DEFAULT = 166_667 / 10_000_000.0
  # `TimeSpan.FromMilliseconds(20)`.
  INACTIVE_DEFAULT = 0.02

  def with_game
    game = F::Game.new
    yield game
  ensure
    game&.Dispose
  end

  # ------------------------------------------------------------------------- the pinned contract

  def test_all_four_are_read_write_instance_properties_of_the_declared_type
    expected = {
      "IsFixedTimeStep" => "System.Boolean",
      "TargetElapsedTime" => "System.TimeSpan",
      "InactiveSleepTime" => "System.TimeSpan",
      "IsMouseVisible" => "System.Boolean"
    }
    members = REFERENCE.fetch("Microsoft.Xna.Framework.Game").fetch("members")
    expected.each do |name, type|
      member = members.find { |entry| entry.fetch("name") == name && entry.fetch("kind") == "property" }
      refute_nil member, name
      assert_equal type, member.fetch("type"), name
      assert_equal true, member.fetch("get"), name
      assert_equal true, member.fetch("set"), name
      assert_equal false, member.fetch("static"), name
      assert_equal "public", member.fetch("getAccess"), name
      assert_equal "public", member.fetch("setAccess"), name
    end
  end

  def test_every_property_is_selected_and_no_longer_missing
    selected = SIGNATURES.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                         .map { |member| member.fetch("name") }
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
    NAMES.each do |name|
      assert_includes selected, name
      refute(remainder.any? { |entry| entry.include?("::#{name} ") }, name)
    end
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
    # Unrelated and pre-existing: GraphicsDevice::Viewport, whose setter is deliberately excluded.
    assert_equal ["Microsoft.Xna.Framework.Graphics.GraphicsDevice::Viewport"],
                 STRICT.fetch("details").fetch("PROPERTY_MAPPING_MISMATCH")
  end

  # ------------------------------------------------------------------------------- the defaults

  # Exactly the values the pinned `.ctor` sets, and TargetElapsedTime is the XNA tick count rather
  # than a recomputed 1.0/60.
  def test_the_constructor_defaults_are_the_pinned_ones
    with_game do |game|
      assert_equal true, game.IsFixedTimeStep
      assert_equal false, game.IsMouseVisible
      assert_in_delta TARGET_DEFAULT, game.TargetElapsedTime, 1e-12
      assert_in_delta INACTIVE_DEFAULT, game.InactiveSleepTime, 1e-12
      refute_equal 1.0 / 60, game.TargetElapsedTime,
                   "XNA stores 166667 ticks, which is not one sixtieth of a second"
    end
  end

  # Every getter is one `ldfld`, so none of them needs a host.
  def test_every_getter_answers_without_a_native_host
    with_game do |game|
      assert_nil game.instance_variable_get(:@host)
      NAMES.each { |name| refute_nil game.public_send(name), name }
      assert_nil game.instance_variable_get(:@host), "a getter must not create a host"
    end
  end

  # ------------------------------------------------------------------------------- validation

  # `set_TargetElapsedTime` compares with op_LessThanOrEqual, so zero is refused too.
  def test_target_elapsed_time_refuses_zero_and_negative
    with_game do |game|
      [0, 0.0, -1, -0.001].each do |value|
        error = assert_raises(RangeError, value.inspect) { game.TargetElapsedTime = value }
        assert_equal "TargetElapsedTime must be greater than zero", error.message
      end
      assert_in_delta TARGET_DEFAULT, game.TargetElapsedTime, 1e-12, "a refused write changes nothing"
      assert_equal 0.5, game.TargetElapsedTime = 0.5
    end
  end

  # `set_InactiveSleepTime` compares with op_LessThan, so zero is ACCEPTED despite the CLR resource
  # being named InactiveSleepTimeCannotBeZero. Only a negative duration is refused.
  def test_inactive_sleep_time_accepts_zero_and_refuses_only_negative
    with_game do |game|
      assert_equal 0.0, game.InactiveSleepTime = 0
      assert_equal 0.0, game.InactiveSleepTime
      error = assert_raises(RangeError) { game.InactiveSleepTime = -0.001 }
      assert_equal "InactiveSleepTime must not be negative", error.message
      assert_equal 0.0, game.InactiveSleepTime
    end
  end

  # `set_IsFixedTimeStep` is a bare field write: the IL contains no validation at all.
  def test_is_fixed_time_step_and_is_mouse_visible_validate_nothing
    with_game do |game|
      assert_equal false, game.IsFixedTimeStep = false
      assert_equal false, game.IsFixedTimeStep
      assert_equal true, game.IsMouseVisible = true
      assert_equal true, game.IsMouseVisible
      # Any truthy or falsey value is coerced, as the CLR's Boolean parameter would be.
      game.IsFixedTimeStep = nil
      assert_equal false, game.IsFixedTimeStep
      game.IsMouseVisible = Object.new
      assert_equal true, game.IsMouseVisible
    end
  end

  def test_a_time_span_property_refuses_a_non_numeric
    with_game do |game|
      assert_raises(TypeError) { game.TargetElapsedTime = "1" }
      assert_raises(TypeError) { game.InactiveSleepTime = nil }
    end
  end

  # ---------------------------------------------------------------- the state really goes down

  def test_values_set_before_the_first_run_are_the_ones_the_host_is_created_with
    with_game do |game|
      game.IsFixedTimeStep = false
      game.TargetElapsedTime = 1.0 / 30
      game.InactiveSleepTime = 0.05
      game.IsMouseVisible = true
      host = game.__send__(:ensure_host)
      refute_equal 0, host.handle

      assert_equal [false, 333_333, 500_000, true], native_settings(game, host)
      # The managed side is unchanged by the round trip.
      assert_equal false, game.IsFixedTimeStep
      assert_in_delta 1.0 / 30, game.TargetElapsedTime, 1e-12
    end
  end

  def test_a_setter_forwards_immediately_once_a_host_exists
    with_game do |game|
      host = game.__send__(:ensure_host)
      assert_equal [true, 166_667, 200_000, false], native_settings(game, host)
      game.IsFixedTimeStep = false
      game.TargetElapsedTime = 1.0 / 120
      game.InactiveSleepTime = 0
      game.IsMouseVisible = true
      assert_equal [false, 83_333, 0, true], native_settings(game, host)
    end
  end

  # Seconds are rounded to the nearest whole tick rather than truncated, because a CLR TimeSpan
  # carries whole ticks.
  def test_seconds_are_rounded_to_the_nearest_tick
    with_game do |game|
      host = game.__send__(:ensure_host)
      game.TargetElapsedTime = 1.0 / 3
      assert_equal 3_333_333, native_settings(game, host)[1]
    end
  end

  # A refused write never reaches the runtime.
  def test_a_refused_write_does_not_reach_the_runtime
    with_game do |game|
      host = game.__send__(:ensure_host)
      before = native_settings(game, host)
      assert_raises(RangeError) { game.TargetElapsedTime = 0 }
      assert_raises(RangeError) { game.InactiveSleepTime = -1 }
      assert_raises(TypeError) { game.TargetElapsedTime = :nope }
      assert_equal before, native_settings(game, host)
    end
  end

  # ------------------------------------------------------------------- what this does not claim

  # Tick left this list in Foundation 44 and IsActive in Foundation 45, the latter by implementing
  # `isActive && !(GamerServicesDispatcher.IsInitialized && Guide.IsVisible)` over the three
  # canonical CNA routes that answer its three terms.
  def test_no_game_member_remains
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
                      .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    # `Content` was the last one, and the ContentManager projection closed it.
    assert_empty remainder
  end

  private

  def native_settings(game, host)
    library = CNA::Native.library
    boolean = lambda do |symbol|
      output = library.pointer_for("C", 0)
      library.call(symbol, host.handle, output)
      output[0, 1].unpack1("C") == 1
    end
    ticks = lambda do |symbol|
      output = library.pointer_for("q", 0)
      library.call(symbol, host.handle, output)
      output[0, 8].unpack1("q")
    end
    [boolean.call("cna_game_get_is_fixed_time_step"),
     ticks.call("cna_game_get_target_elapsed_time_ticks"),
     ticks.call("cna_game_get_inactive_sleep_time_ticks"),
     boolean.call("cna_game_get_is_mouse_visible")]
  end
end

# Foundation 43 — the two loop-state operations.
class GameLoopStateTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  def test_both_are_public_parameterless_void_instance_methods
    members = REFERENCE.fetch("Microsoft.Xna.Framework.Game").fetch("members")
    %w[SuppressDraw ResetElapsedTime].each do |name|
      member = members.find { |entry| entry.fetch("name") == name && entry.fetch("kind") == "method" }
      refute_nil member, name
      assert_equal "public", member.fetch("access"), name
      assert_equal "System.Void", member.fetch("returnType"), name
      assert_empty member.fetch("parameters"), name
      assert_equal false, member.fetch("static"), name
      assert_equal 0, F::Game.instance_method(name).arity, name
    end
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
    %w[SuppressDraw ResetElapsedTime].each do |name|
      refute(remainder.any? { |entry| entry.include?("::#{name} ") }, name)
    end
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
  end

  # Neither creates a host: ResetElapsedTime on a Game with no loop has no accumulated time to
  # forget, and SuppressDraw remembers the request instead of forcing a host into existence.
  def test_neither_creates_a_native_host
    game = F::Game.new
    begin
      assert_nil game.SuppressDraw
      assert_nil game.ResetElapsedTime
      assert_nil game.instance_variable_get(:@host)
      assert_equal true, game.instance_variable_get(:@suppress_draw_pending)
    ensure
      game.Dispose
    end
  end

  # The pending request is delivered exactly once, when the host is created, and then cleared.
  def test_a_pending_suppress_draw_is_delivered_at_host_creation_and_cleared
    game = F::Game.new
    begin
      game.SuppressDraw
      game.__send__(:ensure_host)
      assert_equal false, game.instance_variable_get(:@suppress_draw_pending)
    ensure
      game.Dispose
    end
  end

  # SuppressDraw before the first frame really does skip that frame's draw, and the loop consumes
  # the request rather than staying suppressed.
  def test_suppress_draw_skips_exactly_one_draw
    klass = Class.new(F::Game) do
      define_method(:initialize) { super(); @draws = 0; @updates = 0 }
      define_method(:draws) { @draws }
      define_method(:updates) { @updates }
      define_method(:Update) { |t| super(t); @updates += 1 }
      define_method(:Draw) { |t| super(t); @draws += 1 }
    end
    suppressed = klass.new
    begin
      suppressed.SuppressDraw
      3.times { suppressed.RunOneFrame }
    ensure
      suppressed.Dispose
    end
    plain = klass.new
    begin
      3.times { plain.RunOneFrame }
    ensure
      plain.Dispose
    end
    assert_equal plain.updates, suppressed.updates, "an update is never skipped"
    assert_equal plain.draws - 1, suppressed.draws, "exactly one draw is skipped"
  end

  def test_both_run_against_a_live_host_and_a_disposed_game_refuses
    game = F::Game.new
    game.RunOneFrame
    assert_nil game.SuppressDraw
    assert_nil game.ResetElapsedTime
    game.Dispose
    assert_raises(CNA::DisposedObjectError) { game.SuppressDraw }
    assert_raises(CNA::DisposedObjectError) { game.ResetElapsedTime }
  end
end
