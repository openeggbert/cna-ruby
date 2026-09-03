# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `GraphicsDeviceManager`'s nine preferred settings, `ApplyChanges` and `ToggleFullScreen` — eleven
# of the twenty-six members the largest partial type owed.
#
# They are **preferences**, not device state: `PreferredBackBufferWidth` is what the next device
# creation should aim for, not what the current device has, which is why XNA's getters are one
# `ldfld` and never consult the device. This projection keeps them in managed fields for the same
# reason XNA does — a consumer sets them *before* `Run`, when no native manager exists yet — and
# pushes all nine into CNA's own manager when it appears and again at `ApplyChanges`.
#
# The fifteen members still outstanding are exactly the ones
# `docs/graphics-device-service-producer-audit.md` defers (the four device events, their raisers,
# `PreparingDeviceSettings` and `Dispose(Boolean)`) plus the three that need
# `GraphicsDeviceInformation`. This milestone deliberately adds none of them.
class GraphicsDeviceManagerPreferencesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.GraphicsDeviceManager"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_eleven_members_closed_and_the_remainder_is_what_the_audit_defers
    remainder = ReviewedScoreboard.outstanding(STRICT, NAME)
    %w[PreferredBackBufferWidth PreferredBackBufferHeight PreferredBackBufferFormat
       PreferredDepthStencilFormat IsFullScreen SynchronizeWithVerticalRetrace PreferMultiSampling
       SupportedOrientations GraphicsProfile ApplyChanges ToggleFullScreen].each do |closed|
      refute_includes remainder, closed
      assert F::GraphicsDeviceManager.public_method_defined?(closed), closed
    end
    # The four device events, their raisers and `Dispose(Boolean)` were closed by Foundation 96,
    # which is what re-measuring the producer audit against current CNA found: four of the five
    # events are **relays of the device's own**, so the manager needed no producer and no route.
    %w[DeviceCreated DeviceResetting DeviceReset DeviceDisposing Disposed].each do |closed|
      refute_includes remainder, closed
      assert F::GraphicsDeviceManager.public_method_defined?(closed), closed
    end
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_MANAGER_OUTSTANDING, remainder
    # What is left names `GraphicsDeviceInformation`, or the event args that carry one.
    %w[FindBestDevice CanResetDevice RankDevices
       OnPreparingDeviceSettings PreparingDeviceSettings].each do |deferred|
      assert_includes remainder, deferred
      refute F::GraphicsDeviceManager.public_method_defined?(deferred), deferred
    end
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
  end

  # `GraphicsDeviceInformation` really is missing, so the three that name it are blocked by a type
  # rather than by the audit — measured rather than asserted.
  def test_the_three_that_are_not_the_audits_name_a_missing_type
    %w[FindBestDevice CanResetDevice RankDevices].each do |name|
      member = REFERENCE.fetch(NAME).fetch("members").find { |m| m.fetch("name") == name }
      signature = [member["returnType"], *member.fetch("parameters", []).map { |p| p.fetch("type") }].join(" ")
      assert_includes signature, "GraphicsDeviceInformation", name
    end
    assert_includes STRICT.fetch("missingTypeNames"), "Microsoft.Xna.Framework.GraphicsDeviceInformation"
  end

  # ------------------------------------------------------------------------------ live behaviour

  class Host < F::Game
    attr_reader :manager, :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      @manager = F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call(@manager)
    ensure
      self.Exit
    end
  end

  def with_manager
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { |manager| yield manager }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # The constructor's field initialisers run before `Object::.ctor()`, in IL order, and everything
  # they do not name takes its CLR zero. `graphicsProfile` comes from `ReadDefaultGraphicsProfile`,
  # which reads the manifest resource `"Microsoft.Xna.Framework.RuntimeProfile"` out of the game's
  # own assembly and returns `Reach` when it is absent — which, in a Ruby program, it always is.
  def test_the_defaults_are_the_ils_own
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { nil }
    manager = game.manager
    begin
      assert_equal 800, manager.PreferredBackBufferWidth
      assert_equal 480, manager.PreferredBackBufferHeight
      assert_equal 800, F::GraphicsDeviceManager::DefaultBackBufferWidth
      assert_equal 480, F::GraphicsDeviceManager::DefaultBackBufferHeight
      assert_equal G::SurfaceFormat::Color, manager.PreferredBackBufferFormat
      assert_equal G::DepthFormat::Depth24, manager.PreferredDepthStencilFormat
      assert_equal false, manager.IsFullScreen
      assert_equal true, manager.SynchronizeWithVerticalRetrace, "the one non-zero boolean default"
      assert_equal false, manager.PreferMultiSampling
      assert_equal F::DisplayOrientation::Default, manager.SupportedOrientations
      assert_equal G::GraphicsProfile::Reach, manager.GraphicsProfile
    ensure
      game.Dispose
    end
  end

  # Only the two dimension setters validate:
  # `if (value <= 0) throw new ArgumentOutOfRangeException("value", BackBufferDimMustBePositive)`.
  # The other seven store and mark dirty with no validation of their own, so what refuses a wrong
  # value there is this binding's typing rather than XNA's.
  def test_only_the_dimensions_validate_and_the_rest_are_typed
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { nil }
    manager = game.manager
    err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
    begin
      assert_equal RangeError, err.call { manager.PreferredBackBufferWidth = 0 }
      assert_equal RangeError, err.call { manager.PreferredBackBufferWidth = -1 }
      assert_equal RangeError, err.call { manager.PreferredBackBufferHeight = 0 }
      assert_equal :ok, err.call { manager.PreferredBackBufferWidth = 1 }
      assert_equal TypeError, err.call { manager.PreferredBackBufferWidth = "800" }
      assert_equal TypeError, err.call { manager.IsFullScreen = 1 }
      assert_equal TypeError, err.call { manager.PreferMultiSampling = nil }
      assert_equal TypeError, err.call { manager.GraphicsProfile = 0 }
      assert_equal TypeError, err.call { manager.PreferredBackBufferFormat = G::DepthFormat::Depth24 },
                   "an enum of the wrong type is refused, not silently coerced"
      assert_equal :ok, err.call { manager.SupportedOrientations = F::DisplayOrientation::LandscapeLeft }
    ensure
      game.Dispose
    end
  end

  # The whole point of buffering: a consumer sets a resolution before `Run`, and it takes effect.
  def test_settings_made_before_run_reach_cnas_manager_when_it_appears
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { |manager| manager.__send__(:native_preferences) }
    game.manager.PreferredBackBufferWidth = 1280
    game.manager.PreferredBackBufferHeight = 720
    game.manager.PreferMultiSampling = true
    game.manager.SynchronizeWithVerticalRetrace = false
    game.manager.PreferredDepthStencilFormat = G::DepthFormat::Depth16
    begin
      game.Run
      native = game.result
    ensure
      game.Dispose
    end

    assert_equal 1280, native.fetch(:width)
    assert_equal 720, native.fetch(:height)
    assert_equal 1, native.fetch(:multi_sampling)
    assert_equal 0, native.fetch(:vsync)
    assert_equal G::DepthFormat::Depth16.to_i, native.fetch(:depth)
    assert_equal G::GraphicsProfile::Reach.to_i, native.fetch(:profile)
  end

  # `if (device != null && !isDeviceDirty) return; ChangeDevice(false);`
  def test_apply_changes_pushes_and_clears_the_dirty_flag
    values = with_manager do |manager|
      manager.PreferredBackBufferWidth = 640
      dirty = manager.instance_variable_get(:@device_dirty)
      manager.ApplyChanges
      [dirty, manager.instance_variable_get(:@device_dirty),
       manager.__send__(:native_preferences).fetch(:width),
       manager.PreferredBackBufferWidth]
    end
    assert_equal [true, false], values[0..1], "a setter marks it dirty and ApplyChanges clears it"
    assert_equal 640, values[2], "and the value really reached CNA's manager"
    assert_equal 640, values[3], "while the property still answers the preference, as ldfld does"
  end

  # `IsFullScreen = !IsFullScreen; ChangeDevice(false);` — the setter, so it marks dirty on the way.
  def test_toggle_full_screen_flips_the_property_and_pushes_it
    values = with_manager do |manager|
      before = manager.IsFullScreen
      manager.ToggleFullScreen
      after = [manager.IsFullScreen, manager.__send__(:native_preferences).fetch(:full_screen)]
      manager.ToggleFullScreen
      [before, after, manager.IsFullScreen, manager.__send__(:native_preferences).fetch(:full_screen)]
    end
    assert_equal false, values[0]
    assert_equal [true, 1], values[1]
    assert_equal false, values[2], "and it really toggles rather than only setting"
    assert_equal 0, values[3]
  end

  # ------------------------------------------------------------------- and exactly what it does not

  # DEVIATION, recorded: XNA's `ChangeDevice` creates the device when there is none. Here device
  # creation belongs to CNA's own manager, which is what the producer audit found, so a pre-run
  # `ApplyChanges` marks the settings pending instead of standing up a device.
  def test_apply_changes_before_the_host_is_up_does_not_create_a_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { nil }
    manager = game.manager
    begin
      assert_nil manager.instance_variable_get(:@native_handle)
      manager.PreferredBackBufferWidth = 1024
      manager.ApplyChanges
      assert_nil manager.instance_variable_get(:@native_handle),
                 "no device is created, because that is CNA's manager's job here"
      assert_equal 1024, manager.PreferredBackBufferWidth
    ensure
      game.Dispose
    end
  end

  def test_the_producer_audits_outcome_is_untouched
    manager_class = F::GraphicsDeviceManager
    refute manager_class.include?(G::IGraphicsDeviceService)
    refute manager_class.include?(F::IGraphicsDeviceManager)
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new { nil }
    begin
      assert_nil game.Services.GetService(G::IGraphicsDeviceService),
                 "nothing registers the manager, which is outcome B of the producer audit"
      assert_nil game.Services.GetService(F::IGraphicsDeviceManager)
    ensure
      game.Dispose
    end
  end
end
