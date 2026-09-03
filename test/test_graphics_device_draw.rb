# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s three device-buffer draw calls — and the first time anything in this binding
# has actually drawn.
class GraphicsDeviceDrawTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_the_slice_left_the_partial_remainder
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[DrawPrimitives DrawIndexedPrimitives DrawInstancedPrimitives]
      .each { |member| refute_includes remainder, "::#{member} ", member }
    # And the whole remainder, from `ReviewedScoreboard`, rather than a sample of it: the
    # user-primitive families are the draw calls that remain.
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING,
                 ReviewedScoreboard.outstanding(STRICT, NAME)
  end

  class DrawGame < F::Game
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

    game = DrawGame.new { |device| yield device }
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

  def with_geometry(device)
    vertices = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
    vertices.SetData(G::VertexPositionColor, Array.new(3) { G::VertexPositionColor.new })
    indices = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None)
    indices.SetData(::Integer, [0, 1, 2])
    device.SetVertexBuffer(vertices)
    device.Indices = indices
    yield
  ensure
    device.SetVertexBuffer(nil)
    device.Indices = nil
    vertices&.Dispose
    indices&.Dispose
  end

  # The managed validation, which is the same shape in all three and needs no renderer at all.
  def test_the_counts_must_draw_something
    values = with_device do |device|
      with_geometry(device) do
        [error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 0) },
         error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, -1) },
         error_of { device.DrawIndexedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 0, 0, 1) },
         error_of { device.DrawIndexedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 0) },
         error_of { device.DrawInstancedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 1, 0) },
         error_of { device.DrawInstancedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 0, 0, 1, 1) },
         error_of { device.DrawPrimitives(99, 0, 1) },
         error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, "0", 1) }]
      end
    end
    assert_equal [[RangeError, "primitiveCount"]] * 2, values[0, 2]
    assert_equal [RangeError, "numVertices"], values[2]
    assert_equal [RangeError, "primitiveCount"], values[3]
    assert_equal [RangeError, "instanceCount"], values[4]
    assert_equal [RangeError, "numVertices"], values[5]
    assert_equal RangeError, values[6].first, "an undeclared PrimitiveType value"
    assert_equal TypeError, values[7].first
  end

  # `instanceStreamMask`: the two non-instanced calls refuse while any bound stream carries a
  # non-zero InstanceFrequency, and the instanced one is what that frequency is *for*.
  def test_a_stream_with_an_instance_frequency_refuses_the_non_instanced_draws
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      indices = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None)
      indices.SetData(::Integer, [0, 1, 2])
      device.Indices = indices
      device.SetVertexBuffers([G::VertexBufferBinding.new(buffer, 0, 1)])
      refusals = [error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 1) },
                  error_of { device.DrawIndexedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 1) }]
      # ...and with the frequency back to zero the guard is gone, whatever the renderer then says.
      # ...and the instanced call is what a non-zero frequency is *for*, so it carries no such
      # guard: whatever the renderer then says, it is not NonZeroInstanceFrequency.
      instanced = error_of { device.DrawInstancedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 1, 2) }
      device.SetVertexBuffers([G::VertexBufferBinding.new(buffer, 0, 0)])
      allowed = error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 1) }
      device.SetVertexBuffer(nil)
      device.Indices = nil
      buffer.Dispose
      indices.Dispose
      [refusals, allowed, instanced]
    end
    assert_equal [[RuntimeError, "NonZeroInstanceFrequency"]] * 2, values[0]
    refute_equal "NonZeroInstanceFrequency", values[1].is_a?(Array) ? values[1].last : nil
    refute_equal "NonZeroInstanceFrequency", values[2].is_a?(Array) ? values[2].last : nil
  end

  # Without a compiled effect there is nothing to draw *with*, and CNA says so rather than drawing
  # nothing quietly: "no effect has been applied".
  def test_a_draw_without_an_applied_effect_is_refused_by_the_renderer
    skip "this renderer has a compiled-effect runtime" if RendererEnvironment.compiled_effects?

    values = with_device do |device|
      with_geometry(device) { error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 1) } }
    end
    assert_equal CNA::NativeError, values.first
    assert_includes values.last, "no effect has been applied"
  end

  # The first real draw this binding has ever performed. FNA's own BasicEffect is the fixture,
  # referenced by path through CNA_TEST_FX_BASIC, and `VertexPositionColor` is a layout its vertex
  # shader accepts -- the conformance effect wants a Tangent attribute no projected struct declares,
  # which is measured in the evidence rather than worked around.
  def test_all_three_draw_calls_reach_the_gpu_with_an_applied_effect
    skip "this renderer has no compiled-effect runtime" unless RendererEnvironment.compiled_effects?
    fixture = ENV["CNA_TEST_FX_BASIC"]
    skip "CNA_TEST_FX_BASIC not supplied" unless fixture && File.file?(fixture)

    values = with_device do |device|
      effect = G::Effect.new(device, File.binread(fixture))
      begin
        with_geometry(device) do
          effect.CurrentTechnique.Passes[0].Apply
          [error_of { device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 1) },
           error_of { device.DrawIndexedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 1) },
           error_of { device.DrawInstancedPrimitives(G::PrimitiveType::TriangleList, 0, 0, 3, 0, 1, 2) },
           # A second pass over the same geometry is the ordinary multi-pass shape.
           error_of do
             effect.CurrentTechnique.Passes[1]&.Apply
             device.DrawPrimitives(G::PrimitiveType::TriangleList, 0, 1)
           end]
        end
      ensure
        effect.Dispose
      end
    end
    assert_equal [:ok, :ok, :ok, :ok], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_user_primitive_route
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # `cna_graphics_device_present` and `cna_graphics_device_reset` left this list when Foundation 92
    # bound them and the user-primitive pair when Foundation 94 did. The indirect extension has not:
    # XNA declares no member that would call it.
    %w[cna_graphics_device_draw_primitives_indirect_ext
       cna_graphics_device_draw_indexed_primitives_indirect_ext]
      .each { |absent| refute_includes symbols, absent }
    %w[cna_graphics_device_draw_primitives cna_graphics_device_draw_indexed_primitives
       cna_graphics_device_draw_instanced_primitives].each { |present| assert_includes symbols, present }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
