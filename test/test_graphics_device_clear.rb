# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice.Clear`'s three overloads, and the route swap that came with them.
#
# The projection carried one `Clear` — the `Color` overload — bound to
# `cna_graphics_device_clear_rgba`, a route that takes four normalised floats. That was honest while
# `ClearOptions` was not projected and the device had no render targets, and it stopped being XNA's
# `Clear` once both existed: XNA's `Clear(color)` is literally
# `Clear(DefaultClearOptions, color, 1f, 0)`, a packed D3DCOLOR, a depth and a stencil.
# `cna_graphics_device_clear_options` is that shape exactly, so all three overloads reach it and
# `clear_rgba` leaves the manifest — a bound route without a production call site does not stay.
class GraphicsDeviceClearTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_the_member_left_the_partial_remainder_and_the_overload_register
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    refute_includes remainder, "::Clear "
    refute(STRICT.fetch("details").fetch("OVERLOAD_MAPPING_MISMATCH")
                 .any? { |entry| entry.include?("GraphicsDevice::Clear") })
    %w[Present Reset DrawUserPrimitives].each { |member| assert_includes remainder, "::#{member} ", member }
  end

  def test_all_three_overloads_are_selected
    signatures = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    device = signatures.fetch("types").find { |type| type.fetch("name") == NAME }
    shapes = device.fetch("members").select { |member| member.fetch("name") == "Clear" }
                   .map { |member| member.fetch("parameters").map { |p| p.fetch("type") } }
    assert_equal 3, shapes.length
    assert_includes shapes, ["Microsoft.Xna.Framework.Color"]
    assert_includes shapes, ["Microsoft.Xna.Framework.Graphics.ClearOptions",
                             "Microsoft.Xna.Framework.Color", "System.Single", "System.Int32"]
    assert_includes shapes, ["Microsoft.Xna.Framework.Graphics.ClearOptions",
                             "Microsoft.Xna.Framework.Vector4", "System.Single", "System.Int32"]
  end

  # Ruby cannot overload by parameter type, so three XNA identities are one Ruby method with a
  # variable arity. That is a language mapping and it is asserted rather than implied.
  def test_the_three_identities_are_one_ruby_method
    assert_equal(-1, G::GraphicsDevice.instance_method(:Clear).arity)
  end

  def test_the_retired_route_is_gone_and_the_new_one_is_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_graphics_device_clear_options"
    refute_includes symbols, "cna_graphics_device_clear_rgba"
  end

  class ClearGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = ClearGame.new { |device| yield device }
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

  # ------------------------------------------------------------------ DefaultClearOptions

  # `Target`, plus `DepthBuffer` when the depth format is not `None`, plus `Stencil` when it is
  # exactly `Depth24Stencil8`. The format is the first bound render target's when one is bound and
  # the device's own otherwise — the same choice the viewport bounds and the scissor rule make.
  def test_the_default_options_follow_the_depth_format
    outcome = with_device do |device|
      device_format = device.__send__(:internal_presentation_parameters).DepthStencilFormat
      without = device.__send__(:default_clear_options)
      target = G::RenderTarget2D.new(device, 16, 16)
      begin
        device.SetRenderTarget(target)
        [device_format, without, target.DepthStencilFormat, device.__send__(:default_clear_options)]
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    device_format, without, target_format, with_target = outcome
    assert_equal expected_default_options(device_format), without.to_i
    assert_equal expected_default_options(target_format), with_target.to_i
    assert_instance_of G::ClearOptions, without
  end

  def expected_default_options(format)
    return 1 if format.to_i.zero?

    format.to_i == G::DepthFormat::Depth24Stencil8.to_i ? 7 : 3
  end

  # The rule stated as a truth table over every declared depth format, so it is checked for the
  # three this host never produces as well as the one it does.
  def test_the_default_options_rule_covers_every_depth_format
    {
      G::DepthFormat::None => 1,
      G::DepthFormat::Depth16 => 3,
      G::DepthFormat::Depth24 => 3,
      G::DepthFormat::Depth24Stencil8 => 7
    }.each { |format, expected| assert_equal expected, expected_default_options(format), format.to_s }
  end

  # ------------------------------------------------------------------ the two forwarding overloads

  # `Clear(color)` is `Clear(DefaultClearOptions, color, 1f, 0)`, and the only way to see the
  # forwarding from outside is that it uses the *same* options the four-argument form computes.
  def test_the_colour_only_overload_forwards_with_the_default_options
    calls = []
    outcome = with_device do |device|
      device.singleton_class.define_method(:record) { |*arguments| calls << arguments }
      original = CNA::Native.library.method(:call)
      CNA::Native.library.singleton_class.define_method(:call) do |name, *arguments|
        calls << [name, *arguments] if name == "cna_graphics_device_clear_options"
        original.call(name, *arguments)
      end
      begin
        expected = device.__send__(:default_clear_options).to_i
        device.Clear(F::Color.new(10, 20, 30, 40))
        [expected, calls.dup]
      ensure
        CNA::Native.library.singleton_class.remove_method(:call)
      end
    end
    expected, recorded = outcome
    assert_equal 1, recorded.length
    _, _handle, options, packed, depth, stencil = recorded.fetch(0)
    assert_equal expected, options
    assert_equal F::Color.new(10, 20, 30, 40).PackedValue, packed
    assert_in_delta 1.0, depth
    assert_equal 0, stencil
  end

  # The `Vector4` overload is `new Color(vector)` and then the `Color` one, so its packed value must
  # be the value that constructor produces — 0.25/0.5/0.75/1.0 is (64, 128, 191, 255).
  def test_the_vector4_overload_converts_through_the_colour_constructor
    calls = []
    with_device do |device|
      original = CNA::Native.library.method(:call)
      CNA::Native.library.singleton_class.define_method(:call) do |name, *arguments|
        calls << arguments if name == "cna_graphics_device_clear_options"
        original.call(name, *arguments)
      end
      begin
        device.Clear(G::ClearOptions::Target, F::Vector4.new(0.25, 0.5, 0.75, 1.0), 1.0, 0)
      ensure
        CNA::Native.library.singleton_class.remove_method(:call)
      end
    end
    assert_equal 1, calls.length
    assert_equal F::Color.new(F::Vector4.new(0.25, 0.5, 0.75, 1.0)).PackedValue, calls.fetch(0).fetch(2)
    assert_equal [64, 128, 191, 255],
                 [F::Color.new(F::Vector4.new(0.25, 0.5, 0.75, 1.0))].flat_map { |c| [c.R, c.G, c.B, c.A] }
  end

  # ------------------------------------------------------------------ live behaviour

  def test_every_overload_reaches_the_device
    outcomes = with_device do |device|
      {
        colour: error_of { device.Clear(F::Color.new(10, 20, 30, 40)) },
        four_colour: error_of { device.Clear(G::ClearOptions::Target, F::Color.new(1, 2, 3, 4), 1.0, 0) },
        four_vector: error_of { device.Clear(G::ClearOptions::Target, F::Vector4.new(0.0, 0.0, 0.0, 1.0), 1.0, 0) },
        combined: error_of { device.Clear(G::ClearOptions.coerce(3), F::Color.new(0, 0, 0, 255), 0.5, 0) },
        depth_only: error_of { device.Clear(G::ClearOptions::DepthBuffer, F::Color.new(0, 0, 0, 255), 0.25, 7) }
      }
    end
    outcomes.each { |name, outcome| assert_equal :ok, outcome, name }
  end

  # The clear really lands, on an artifact that can read a target back.
  def test_a_cleared_render_target_reads_back_the_colour
    skip "this artifact has no honest render-target readback" unless RendererEnvironment.render_target_readback?

    pixels = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 2)
      begin
        device.SetRenderTarget(target)
        device.Clear(G::ClearOptions::Target, F::Color.new(64, 128, 191, 255), 1.0, 0)
        device.SetRenderTarget(nil)
        data = Array.new(8) { F::Color.new(0, 0, 0, 0) }
        target.GetData(F::Color, data)
        data.map { |colour| [colour.R, colour.G, colour.B, colour.A] }
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal Array.new(8) { [64, 128, 191, 255] }, pixels
  end

  # ------------------------------------------------------------------ argument guards

  def test_the_arity_and_type_guards
    outcomes = with_device do |device|
      {
        two: error_of { device.Clear(G::ClearOptions::Target, F::Color.new(0, 0, 0, 0)) },
        three: error_of { device.Clear(G::ClearOptions::Target, F::Color.new(0, 0, 0, 0), 1.0) },
        none: error_of { device.Clear },
        colour: error_of { device.Clear(G::ClearOptions::Target, 5, 1.0, 0) },
        colour_only: error_of { device.Clear(5) },
        options: error_of { device.Clear(99, F::Color.new(0, 0, 0, 0), 1.0, 0) },
        stencil: error_of { device.Clear(G::ClearOptions::Target, F::Color.new(0, 0, 0, 0), 1.0, "0") }
      }
    end
    %i[two three none].each do |name|
      assert_equal ArgumentError, outcomes.fetch(name).fetch(0), name
    end
    assert_equal [TypeError, "color must be a Color or a Vector4"], outcomes.fetch(:colour)
    assert_equal [TypeError, "color must be a Color or a Vector4"], outcomes.fetch(:colour_only)
    assert_equal RangeError, outcomes.fetch(:options).fetch(0)
    assert_equal TypeError, outcomes.fetch(:stencil).fetch(0)
  end

  # ------------------------------------------------------------------ CannotClearNullDepth

  # XNA's one managed failure rule, and this artifact cannot exercise it: **CNA's clear never
  # fails**, not even asking for `Stencil` on a `Depth24` device or for `DepthBuffer` on a render
  # target whose depth format is `None` — both measured, both `CNA_RESULT_SUCCESS`. So the rule is
  # proved by a truth table and one stub, the way `Game.IsActive`'s guide term is, rather than by an
  # exercise this host cannot produce.
  def test_the_managed_rule_is_the_ils
    outcome = with_device do |device|
      target = G::RenderTarget2D.new(device, 8, 8)
      begin
        device.SetRenderTarget(target)
        # `DefaultClearOptions` is `Target` alone while a depth-less target is bound.
        [device.__send__(:default_clear_options).to_i,
         device.__send__(:requested_buffers_exist?, G::ClearOptions::Target),
         device.__send__(:requested_buffers_exist?, G::ClearOptions::DepthBuffer),
         device.__send__(:requested_buffers_exist?, G::ClearOptions.coerce(7)),
         error_of { device.Clear(G::ClearOptions::DepthBuffer, F::Color.new(0, 0, 0, 255), 1.0, 0) }]
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal 1, outcome.fetch(0)
    assert_equal true, outcome.fetch(1), "the colour bit is never a depth bit"
    assert_equal false, outcome.fetch(2)
    assert_equal false, outcome.fetch(3)
    assert_equal :ok, outcome.fetch(4),
                 "MEASURED: CNA clears a buffer the target does not have rather than refusing"
  end

  # The branch is wired, which is the half a truth table cannot show: with the native call made to
  # answer what CNA documents for this case — `CNA_RESULT_NOT_SUPPORTED`, "when the backend cannot
  # clear a selected buffer" — the requested-buffer rule decides which exception comes out.
  def test_a_refusing_clear_raises_cannot_clear_null_depth_only_when_the_buffers_are_absent
    outcome = with_device do |device|
      original = CNA::Native.library.method(:call)
      CNA::Native.library.singleton_class.define_method(:call) do |name, *arguments|
        if name == "cna_graphics_device_clear_options"
          # Exactly what the library raises for `CNA_RESULT_NOT_SUPPORTED`, which is what CNA
          # documents for "the backend cannot clear a selected buffer".
          raise CNA::CapabilityError.new(name, CNA::Native::Library::RESULT_NOT_SUPPORTED)
        end

        original.call(name, *arguments)
      end
      target = G::RenderTarget2D.new(device, 8, 8)
      begin
        device.SetRenderTarget(target)
        absent = error_of { device.Clear(G::ClearOptions::DepthBuffer, F::Color.new(0, 0, 0, 255), 1.0, 0) }
        present = error_of { device.Clear(G::ClearOptions::Target, F::Color.new(0, 0, 0, 255), 1.0, 0) }
        [absent, present]
      ensure
        CNA::Native.library.singleton_class.remove_method(:call)
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal [RuntimeError, "CannotClearNullDepth"], outcome.fetch(0)
    assert_equal CNA::CapabilityError, outcome.fetch(1).fetch(0),
                 "a failure the rule does not explain is re-raised as CNA's own"
  end

  # ------------------------------------------------------------------ scope and disposal

  def test_clear_is_callback_scoped_and_disposal_bound
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    assert_equal CNA::InvalidBindingStateError,
                 error_of { device.Clear(F::Color.new(0, 0, 0, 0)) }.fetch(0)
    game.Dispose
    assert_equal CNA::DisposedObjectError,
                 error_of { device.Clear(F::Color.new(0, 0, 0, 0)) }.fetch(0)
  end
end
