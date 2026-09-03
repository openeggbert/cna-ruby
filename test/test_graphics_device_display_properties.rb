# frozen_string_literal: true

require "minitest/autorun"
require "fiddle"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s five simple properties — three projected, two blocked by the same upstream
# defect, and the measurement that moved one of them from the first group to the second.
#
# `docs/graphics-runtime-member-audit.md` classified `DisplayMode` as buildable on the strength of
# `cna_graphics_device_get_display_mode` existing. It exists, it answers `CNA_RESULT_SUCCESS`, and
# what it answers is invented: on a game whose back buffer is 320x200, running against a real
# 1280x800 X display, it says **800x480** — byte-for-byte what
# `cna_graphics_adapter_get_current_display_mode` says, which is the no-display fallback
# `docs/graphics-adapter-ordering-upstream-defect.md` already records. So the member is not
# projected, for the same reason `GraphicsAdapter` is not, and this file measures that rather than
# asserting it.
#
# `PresentationParameters` is the control that makes the comparison mean anything: measured in the
# same run on the same device, it answers the real 320x200.
class GraphicsDeviceDisplayPropertiesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_the_slice_left_the_partial_remainder
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[GraphicsProfile GraphicsDeviceStatus PresentationParameters]
      .each { |member| refute_includes remainder, "::#{member} ", member }
    # The two the invented display data still blocks, and the families still to come.
    %w[DisplayMode Adapter Present Reset].each { |member| assert_includes remainder, "::#{member} ", member }
  end

  class PropertyGame < F::Game
    attr_reader :result

    def initialize(width = nil, height = nil, &body)
      @body = body
      super()
      manager = F::GraphicsDeviceManager.new(self)
      return if width.nil?

      manager.PreferredBackBufferWidth = width
      manager.PreferredBackBufferHeight = height
      manager.ApplyChanges
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device(width = nil, height = nil, &body)
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = PropertyGame.new(width, height, &body)
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def error_of
    yield
    :ok
  rescue StandardError => error
    [error.class, error.message]
  end

  # ------------------------------------------------------------------ GraphicsProfile

  # `ldfld _graphicsProfile` in XNA, asked here. Whatever it answers must be one of the two
  # identities the enum declares, and it must not change over the device's life.
  def test_the_profile_is_a_declared_identity_and_is_stable
    values = with_device { |device| [device.GraphicsProfile, device.GraphicsProfile] }
    assert_instance_of G::GraphicsProfile, values.fetch(0)
    assert_includes [G::GraphicsProfile::Reach, G::GraphicsProfile::HiDef], values.fetch(0)
    assert_equal values.fetch(0), values.fetch(1)
    # An enum value is interned, so a stable answer is the same object.
    assert values.fetch(0).equal?(values.fetch(1))
  end

  def test_the_profile_agrees_with_the_manager
    both = with_device { |device| [device.GraphicsProfile.to_i, nil] }
    refute_nil both.fetch(0)
    manager_profile = nil
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    manager_profile = manager.GraphicsProfile.to_i
    game.Dispose
    assert_equal manager_profile, both.fetch(0),
                 "the device reports the profile the manager was created with"
  end

  # ------------------------------------------------------------------ GraphicsDeviceStatus

  # A live query in XNA and a live query here. CNA's three `CNA_GRAPHICS_DEVICE_STATUS_*` identities
  # are numerically XNA's three, which is checked rather than assumed.
  def test_the_status_is_normal_on_a_live_device
    status = with_device { |device| device.GraphicsDeviceStatus }
    assert_instance_of G::GraphicsDeviceStatus, status
    assert_equal G::GraphicsDeviceStatus::Normal, status
  end

  def test_the_status_identities_match_cna
    {
      "CNA_GRAPHICS_DEVICE_STATUS_NORMAL" => G::GraphicsDeviceStatus::Normal,
      "CNA_GRAPHICS_DEVICE_STATUS_LOST" => G::GraphicsDeviceStatus::Lost,
      "CNA_GRAPHICS_DEVICE_STATUS_NOT_RESET" => G::GraphicsDeviceStatus::NotReset
    }.each do |symbol, value|
      header = header_constant(symbol)
      next if header.nil?

      assert_equal header, value.to_i, symbol
    end
  end

  # Read out of the canonical headers rather than restated, so a renumbering upstream fails here.
  def header_constant(name)
    root = ENV["CNA_HEADERS"]
    return nil if root.nil?

    Dir.glob(File.join(root, "CNA", "C", "*.h")).each do |path|
      match = File.read(path)[/^#define\s+#{Regexp.escape(name)}\s+UINT32_C\((\d+)\)/, 1]
      return Integer(match) if match
    end
    nil
  end

  # ------------------------------------------------------------------ PresentationParameters

  # `ldfld pPublicCachedParams`: the **same object** every call, so a consumer that mutates what it
  # gets back sees the mutation next time. That is XNA's behaviour, not a convenience.
  def test_the_parameters_are_one_cached_object
    outcome = with_device do |device|
      first = device.PresentationParameters
      second = device.PresentationParameters
      first.MultiSampleCount = 4
      [first.equal?(second), device.PresentationParameters.MultiSampleCount,
       device.PresentationParameters.equal?(first)]
    end
    assert_equal [true, 4, true], outcome
  end

  def test_the_parameters_report_the_applied_configuration
    outcome = with_device(320, 200) do |device|
      parameters = device.PresentationParameters
      [parameters.BackBufferWidth, parameters.BackBufferHeight,
       [parameters.Bounds.X, parameters.Bounds.Y, parameters.Bounds.Width, parameters.Bounds.Height],
       device.__send__(:back_buffer_bounds)]
    end
    assert_equal 320, outcome.fetch(0)
    assert_equal 200, outcome.fetch(1)
    assert_equal [0, 0, 320, 200], outcome.fetch(2)
    assert_equal [320, 200], outcome.fetch(3), "and it agrees with the logical back buffer"
  end

  # Every field CNA supplies is a declared XNA identity of the right type; nothing is fabricated and
  # nothing is coerced out of range.
  def test_every_field_is_a_declared_identity
    values = with_device do |device|
      parameters = device.PresentationParameters
      {
        format: parameters.BackBufferFormat, depth: parameters.DepthStencilFormat,
        interval: parameters.PresentationInterval, orientation: parameters.DisplayOrientation,
        usage: parameters.RenderTargetUsage, full_screen: parameters.IsFullScreen,
        samples: parameters.MultiSampleCount, handle: parameters.DeviceWindowHandle
      }
    end
    assert_instance_of G::SurfaceFormat, values.fetch(:format)
    assert_instance_of G::DepthFormat, values.fetch(:depth)
    assert_instance_of G::PresentInterval, values.fetch(:interval)
    assert_instance_of F::DisplayOrientation, values.fetch(:orientation)
    assert_instance_of G::RenderTargetUsage, values.fetch(:usage)
    assert_includes [true, false], values.fetch(:full_screen)
    assert_kind_of Integer, values.fetch(:samples)
    # DEVIATION, recorded: CNA's structure carries no window handle and the device route that would
    # answer one refuses by design, so this stays the constructor's zero.
    assert_equal 0, values.fetch(:handle)
  end

  # ------------------------------------------------------------------ the two that are blocked

  def test_neither_blocked_property_is_projected
    refute G::GraphicsDevice.public_method_defined?(:DisplayMode)
    refute G::GraphicsDevice.public_method_defined?(:Adapter)
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    assert_includes remainder, "::DisplayMode "
    assert_includes remainder, "::Adapter "
  end

  # No production call site, so no manifest entry: the route that would answer `DisplayMode` is
  # deliberately unbound, and this is what stops it drifting back in.
  def test_the_display_mode_route_is_not_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute_includes symbols, "cna_graphics_device_get_display_mode"
    refute_includes symbols, "cna_graphics_adapter_get_current_display_mode"
    refute CNA::Native::Layouts.const_defined?(:DisplayMode, false)
  end

  # **The measurement itself.** Both routes are called through raw Fiddle — the tool the native
  # evidence tools use, and the reason the manifest stays free of unbound surface — on a device
  # whose back buffer this test set to 320x200. The device route must answer neither the back
  # buffer nor anything different from the adapter route.
  def test_the_display_mode_route_answers_the_adapter_fallback_rather_than_this_device
    outcome = with_device(320, 200) do |device|
      handle = CNA::Native.library.instance_variable_get(:@handle)
      device_mode = Fiddle::Pointer.malloc(24, Fiddle::RUBY_FREE)
      adapter_mode = Fiddle::Pointer.malloc(24, Fiddle::RUBY_FREE)
      [device_mode, adapter_mode].each do |buffer|
        buffer[0, 24] = "\0" * 24
        buffer[0, 8] = [24, 1].pack("L2")
      end
      raw = device.__send__(:native_handle)
      device_call = Fiddle::Function.new(handle["cna_graphics_device_get_display_mode"],
                                         [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT32_T)
      adapter_call = Fiddle::Function.new(handle["cna_graphics_adapter_get_current_display_mode"],
                                          [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_VOIDP],
                                          Fiddle::TYPE_UINT32_T)
      device_code = device_call.call(raw, device_mode)
      adapter_code = adapter_call.call(raw, 0, adapter_mode)
      parameters = device.PresentationParameters
      {
        device_code: device_code, adapter_code: adapter_code,
        device: device_mode[8, 16].unpack("l2fL"),
        adapter: adapter_mode[8, 16].unpack("l2fL"),
        back_buffer: [parameters.BackBufferWidth, parameters.BackBufferHeight]
      }
    end

    assert_equal 0, outcome.fetch(:device_code), "the route succeeds, which is the trap"
    assert_equal 0, outcome.fetch(:adapter_code)
    assert_equal [320, 200], outcome.fetch(:back_buffer)
    assert_equal outcome.fetch(:adapter), outcome.fetch(:device),
                 "the device route is the adapter route's answer, field for field"
    refute_equal outcome.fetch(:back_buffer), outcome.fetch(:device).first(2),
                 "and it is not this device's back buffer"

    # On an artifact with a real window, it is not the display either — which is the half of the
    # measurement `HEADLESS` cannot make, so it is asserted only where it can be.
    return unless RendererEnvironment.windowed?

    refute_equal [1280, 800], outcome.fetch(:device).first(2),
                 "nor the qualification display this artifact really has"
  end

  # ------------------------------------------------------------------ scope and disposal

  def test_the_three_properties_are_callback_scoped_and_disposal_bound
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    %i[GraphicsProfile GraphicsDeviceStatus PresentationParameters].each do |name|
      assert_equal CNA::InvalidBindingStateError, error_of { device.__send__(name) }.fetch(0), name
    end
    game.Dispose
    %i[GraphicsProfile GraphicsDeviceStatus PresentationParameters].each do |name|
      assert_equal CNA::DisposedObjectError, error_of { device.__send__(name) }.fetch(0), name
    end
  end
end
