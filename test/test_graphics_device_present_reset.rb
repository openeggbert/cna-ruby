# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice.Present` and `GraphicsDevice.Reset` — five overloads, three of which are exact,
# one of which refuses an argument CNA has no route for, and one of which refuses a type this
# binding does not project.
#
# The interesting half is what `Reset` **does not** do. XNA's third overload is a long sequence:
# two null guards, the `DeviceResetting` event, a `SavedDeviceState`, releasing and re-creating the
# device, two fresh `Clone()`s into the internal and public parameter caches, `InitializeDeviceState`,
# `SavedDeviceState.Restore()`, and the `DeviceReset` event. Most of that is CNA's, and this
# milestone measured it rather than assuming it either way: across both reset routes and both
# artifacts, the blend state, blend factor, multi-sample mask, reference stencil and a bound texture
# slot all survive, and the viewport and scissor survive a same-size reset while a resizing one
# resets them to the new full target — which is exactly the rule XNA's `SavedDeviceState` implements
# by taking those two as `Nullable`.
#
# Re-applying any of it here would perform a step CNA already performs, which is the rule
# `docs/graphics-device-service-producer-audit.md` established.
class GraphicsDevicePresentResetTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_both_members_left_the_partial_remainder_and_the_overload_register
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[Present Reset].each { |member| refute_includes remainder, "::#{member} ", member }
    overloads = STRICT.fetch("details").fetch("OVERLOAD_MAPPING_MISMATCH").join(" ")
    %w[Present Reset].each { |member| refute_includes overloads, "GraphicsDevice::#{member} ", member }
    %w[GetBackBufferData Dispose Finalize].each do |member|
      assert_includes remainder, "::#{member} ", member
    end
  end

  def test_the_five_overloads_are_selected
    signatures = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    device = signatures.fetch("types").find { |type| type.fetch("name") == NAME }
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
                    .fetch("types").find { |type| type.fetch("name") == NAME }
    %w[Present Reset].each do |member|
      selected = device.fetch("members").select { |entry| entry.fetch("name") == member }
                       .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      expected = reference.fetch("members").select { |entry| entry.fetch("name") == member }
                          .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      assert_equal expected.sort, selected.sort, member
    end
  end

  def test_the_three_routes_are_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[cna_graphics_device_present cna_graphics_device_reset
       cna_graphics_device_reset_with_parameters].each { |name| assert_includes symbols, name }
  end

  class ResetGame < F::Game
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

    game = ResetGame.new { |device| yield device }
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

  # ------------------------------------------------------------------ Present

  def test_present_and_the_all_null_three_argument_form_are_the_same_call
    outcome = with_device do |device|
      [error_of { device.Present }, error_of { device.Present(nil, nil, 0) },
       error_of { device.Present(nil, nil, nil) }]
    end
    outcome.each { |result| assert_equal :ok, result }
  end

  # The `VideoPlayer.Play(Video)` precedent: an argument this ABI has no route to honour is refused
  # explicitly, naming what is missing, rather than ignored.
  def test_present_refuses_each_argument_cna_has_no_route_for
    outcomes = with_device do |device|
      {
        source: error_of { device.Present(F::Rectangle.new(0, 0, 4, 4), nil, 0) },
        destination: error_of { device.Present(nil, F::Rectangle.new(0, 0, 4, 4), 0) },
        window: error_of { device.Present(nil, nil, 12_345) },
        both: error_of { device.Present(F::Rectangle.new(0, 0, 1, 1), F::Rectangle.new(0, 0, 1, 1), 7) }
      }
    end
    outcomes.each_value { |outcome| assert_equal CNA::CapabilityError, outcome.fetch(0) }
    assert_includes outcomes.fetch(:source).fetch(1), "sourceRectangle"
    assert_includes outcomes.fetch(:destination).fetch(1), "destinationRectangle"
    assert_includes outcomes.fetch(:window).fetch(1), "overrideWindowHandle"
    # The source rectangle is checked first, exactly as the IL converts it first.
    assert_includes outcomes.fetch(:both).fetch(1), "sourceRectangle"
  end

  def test_present_argument_guards
    outcomes = with_device do |device|
      {
        one: error_of { device.Present(nil) },
        two: error_of { device.Present(nil, nil) },
        four: error_of { device.Present(nil, nil, 0, 0) },
        type: error_of { device.Present(5, nil, 0) },
        window_type: error_of { device.Present(nil, nil, "0") }
      }
    end
    %i[one two four].each { |name| assert_equal ArgumentError, outcomes.fetch(name).fetch(0), name }
    assert_equal [TypeError, "sourceRectangle must be a Rectangle or nil"], outcomes.fetch(:type)
    assert_equal TypeError, outcomes.fetch(:window_type).fetch(0)
  end

  # ------------------------------------------------------------------ Reset

  # `Reset()` is `Reset(pInternalCachedParams, pCurrentAdapter)`, so it must not change the size,
  # and — measured — it must not change the viewport either, because the size is unchanged.
  def test_the_no_argument_reset_keeps_the_configuration_and_the_viewport
    outcome = with_device do |device|
      device.Viewport = G::Viewport.new(4, 6, 100, 80)
      before = [device.PresentationParameters.BackBufferWidth,
                device.PresentationParameters.BackBufferHeight,
                [device.Viewport.X, device.Viewport.Y, device.Viewport.Width, device.Viewport.Height]]
      code = error_of { device.Reset }
      after = [device.PresentationParameters.BackBufferWidth,
               device.PresentationParameters.BackBufferHeight,
               [device.Viewport.X, device.Viewport.Y, device.Viewport.Width, device.Viewport.Height]]
      [code, before, after]
    end
    assert_equal :ok, outcome.fetch(0)
    assert_equal outcome.fetch(1), outcome.fetch(2)
    assert_equal [4, 6, 100, 80], outcome.fetch(2).fetch(2)
  end

  # A resizing reset applies the new back buffer, and — measured, on both artifacts — CNA resets the
  # viewport and the scissor to the new full target, which is exactly what XNA's `SavedDeviceState`
  # does by declining to save either when the size changes.
  def test_a_resizing_reset_applies_the_size_and_resets_the_viewport
    outcome = with_device do |device|
      device.Viewport = G::Viewport.new(4, 6, 100, 80)
      parameters = device.PresentationParameters.Clone
      parameters.BackBufferWidth = 256
      parameters.BackBufferHeight = 128
      code = error_of { device.Reset(parameters) }
      [code, device.__send__(:back_buffer_bounds),
       [device.Viewport.X, device.Viewport.Y, device.Viewport.Width, device.Viewport.Height],
       [device.PresentationParameters.BackBufferWidth, device.PresentationParameters.BackBufferHeight]]
    end
    assert_equal :ok, outcome.fetch(0)
    assert_equal [256, 128], outcome.fetch(1)
    assert_equal [0, 0, 256, 128], outcome.fetch(2)
    assert_equal [256, 128], outcome.fetch(3)
  end

  # `pInternalCachedParams = presentationParameters.Clone()` and
  # `pPublicCachedParams = presentationParameters.Clone()`: two fresh objects, neither of them the
  # argument, so a consumer holding the argument cannot reach into the device afterwards.
  def test_both_parameter_caches_become_clones_of_the_argument
    outcome = with_device do |device|
      parameters = device.PresentationParameters.Clone
      parameters.BackBufferWidth = 320
      parameters.BackBufferHeight = 200
      device.Reset(parameters)
      public_cache = device.PresentationParameters
      internal_cache = device.__send__(:internal_presentation_parameters)
      parameters.MultiSampleCount = 8
      [public_cache.equal?(parameters), internal_cache.equal?(parameters),
       public_cache.equal?(internal_cache),
       [public_cache.BackBufferWidth, public_cache.BackBufferHeight],
       [internal_cache.BackBufferWidth, internal_cache.BackBufferHeight],
       public_cache.MultiSampleCount, internal_cache.MultiSampleCount, parameters.MultiSampleCount]
    end
    refute outcome.fetch(0), "the public cache is a clone, not the argument"
    refute outcome.fetch(1), "the internal cache is a clone, not the argument"
    refute outcome.fetch(2), "and the two caches are two objects, as XNA's two fields are"
    assert_equal [320, 200], outcome.fetch(3)
    assert_equal [320, 200], outcome.fetch(4)
    assert_equal 8, outcome.fetch(7)
    assert_equal 0, outcome.fetch(5), "mutating the argument afterwards reaches neither cache"
    assert_equal 0, outcome.fetch(6)
  end

  # `SavedDeviceState` saves ten things and restores them; render targets are not among them, so a
  # reset leaves the back buffer current. That is the one piece of the sequence CNA does not do for
  # us, because it is this projection that caches the bindings.
  def test_a_reset_unbinds_every_render_target_and_does_not_restore_it
    outcome = with_device do |device|
      target = G::RenderTarget2D.new(device, 8, 8)
      begin
        device.SetRenderTarget(target)
        before = device.GetRenderTargets.length
        device.Reset
        [before, device.GetRenderTargets.length]
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal [1, 0], outcome
  end

  # The measurement this milestone rests on, asserted rather than merely recorded: what CNA keeps
  # across a reset is what XNA's `SavedDeviceState.Restore()` would have put back.
  def test_the_device_state_survives_a_reset_without_this_binding_re_applying_it
    outcome = with_device do |device|
      device.BlendState = G::BlendState::Additive
      device.BlendFactor = F::Color.new(9, 8, 7, 6)
      device.MultiSampleMask = 0x0F0F
      device.ReferenceStencil = 5
      device.ScissorRectangle = F::Rectangle.new(2, 3, 50, 40)
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      indices = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None)
      begin
        device.SetVertexBuffer(buffer)
        device.Indices = indices
        device.Reset
        [device.BlendState.equal?(G::BlendState::Additive), device.BlendFactor.PackedValue,
         device.MultiSampleMask, device.ReferenceStencil,
         [device.ScissorRectangle.X, device.ScissorRectangle.Y,
          device.ScissorRectangle.Width, device.ScissorRectangle.Height],
         device.GetVertexBuffers.length, device.Indices.equal?(indices)]
      ensure
        device.SetVertexBuffer(nil)
        device.Indices = nil
        buffer.Dispose
        indices.Dispose
      end
    end
    assert outcome.fetch(0)
    assert_equal F::Color.new(9, 8, 7, 6).PackedValue, outcome.fetch(1)
    assert_equal 0x0F0F, outcome.fetch(2)
    assert_equal 5, outcome.fetch(3)
    assert_equal [2, 3, 50, 40], outcome.fetch(4)
    assert_equal 1, outcome.fetch(5)
    assert outcome.fetch(6)
  end

  def test_reset_argument_guards
    outcomes = with_device do |device|
      parameters = device.PresentationParameters.Clone
      {
        null_parameters: error_of { device.Reset(nil) },
        wrong_parameters: error_of { device.Reset(5) },
        null_adapter: error_of { device.Reset(parameters, nil) },
        three: error_of { device.Reset(parameters, nil, nil) }
      }
    end
    assert_equal [ArgumentError, "presentationParameters"], outcomes.fetch(:null_parameters)
    assert_equal [TypeError, "presentationParameters must be a PresentationParameters"],
                 outcomes.fetch(:wrong_parameters)
    # XNA checks `presentationParameters` first and `graphicsAdapter` second, and both are
    # `ArgumentNullException`. The adapter guard therefore fires *before* the refusal below.
    assert_equal [ArgumentError, "graphicsAdapter"], outcomes.fetch(:null_adapter)
    assert_equal ArgumentError, outcomes.fetch(:three).fetch(0)
  end

  # The blocker's fourth appearance, and it is named rather than implied.
  def test_the_adapter_overload_refuses_and_says_why
    outcome = with_device do |device|
      error_of { device.Reset(device.PresentationParameters.Clone, Object.new) }
    end
    assert_equal CNA::CapabilityError, outcome.fetch(0)
    assert_includes outcome.fetch(1), "Graphics.GraphicsAdapter is not projected"
    assert_includes outcome.fetch(1), "graphics-adapter-ordering-upstream-defect"
    refute Microsoft::Xna::Framework::Graphics.const_defined?(:GraphicsAdapter, false)
  end

  # ------------------------------------------------------------------ scope and disposal

  def test_both_members_are_callback_scoped_and_disposal_bound
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    assert_equal CNA::InvalidBindingStateError, error_of { device.Present }.fetch(0)
    assert_equal CNA::InvalidBindingStateError, error_of { device.Reset }.fetch(0)
    game.Dispose
    assert_equal CNA::DisposedObjectError, error_of { device.Present }.fetch(0)
    assert_equal CNA::DisposedObjectError, error_of { device.Reset }.fetch(0)
  end
end
