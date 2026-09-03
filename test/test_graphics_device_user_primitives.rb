# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `DrawUserPrimitives` and `DrawUserIndexedPrimitives` — the six overloads that take their vertices
# as an argument rather than from a bound buffer, and the last draw calls `GraphicsDevice` owed.
#
# `cna_graphics_device_draw_user_primitives` and its indexed sibling take their whole description
# by pointer, so nothing here is passed by value and the arrays stay caller-owned: the header says
# "no vertex array is retained after the call returns". The description carries a
# `CNA_UserVertexSource`, and this projection always uses `RAW_STREAM` with an explicit vertex
# declaration — the typed sources would cover only the four built-in layouts, and the raw one
# covers those *and* an explicitly declared layout, which is what the five- and eight-argument
# overloads are for.
class GraphicsDeviceUserPrimitivesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_both_families_left_the_partial_remainder_and_the_overload_register
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[DrawUserPrimitives DrawUserIndexedPrimitives].each do |member|
      refute_includes remainder, "::#{member} ", member
    end
    overloads = STRICT.fetch("details").fetch("OVERLOAD_MAPPING_MISMATCH").join(" ")
    refute_includes overloads, "GraphicsDevice::DrawUser"
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING,
                 ReviewedScoreboard.outstanding(STRICT, NAME)
  end

  def test_all_six_overloads_are_selected
    signatures = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    device = signatures.fetch("types").find { |type| type.fetch("name") == NAME }
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
                    .fetch("types").find { |type| type.fetch("name") == NAME }
    %w[DrawUserPrimitives DrawUserIndexedPrimitives].each do |member|
      selected = device.fetch("members").select { |entry| entry.fetch("name") == member }
                       .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      expected = reference.fetch("members").select { |entry| entry.fetch("name") == member }
                          .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      assert_equal expected.sort, selected.sort, member
    end
  end

  def test_the_two_routes_are_bound_and_take_their_description_by_pointer
    entries = CNA::Native::Manifest::FUNCTIONS.select do |entry|
      %w[cna_graphics_device_draw_user_primitives
         cna_graphics_device_draw_user_indexed_primitives].include?(entry.symbol)
    end
    assert_equal 2, entries.length
    entries.each do |entry|
      assert_empty entry.value_aggregates, "the description is a pointer, not a by-value aggregate"
      assert entry.const_arguments[1], "and CNA does not write through it"
    end
  end

  class UserGame < F::Game
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

    game = UserGame.new { |device| yield device }
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

  def triangle = Array.new(3) { G::VertexPositionColor.new(F::Vector3.Zero, F::Color.new(255, 255, 255, 255)) }

  # ------------------------------------------------------------------ the managed guards
  #
  # Every one is the IL's, in the IL's order, and none of them needs a renderer — which is why they
  # are asserted on every artifact.

  def test_the_vertex_array_guards
    outcomes = with_device do |device|
      {
        nil_array: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, nil, 0, 1) },
        # `ldlen; brfalse` — a zero-length array is `null` to XNA, and raises the same exception.
        empty_array: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, [], 0, 1) },
        not_an_array: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, "abc", 0, 1) },
        mixed: error_of do
          device.DrawUserPrimitives(G::PrimitiveType::TriangleList,
                                    [G::VertexPositionColor.new, G::VertexPositionTexture.new], 0, 1)
        end,
        not_a_vertex: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, [1, 2, 3], 0, 1) }
      }
    end
    assert_equal [ArgumentError, "vertexData"], outcomes.fetch(:nil_array)
    assert_equal [ArgumentError, "vertexData"], outcomes.fetch(:empty_array)
    assert_equal TypeError, outcomes.fetch(:not_an_array).fetch(0)
    assert_equal TypeError, outcomes.fetch(:mixed).fetch(0)
    assert_equal TypeError, outcomes.fetch(:not_a_vertex).fetch(0)
  end

  def test_the_count_and_offset_guards
    outcomes = with_device do |device|
      vertices = triangle
      {
        zero_count: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, 0) },
        negative_count: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, -1) },
        negative_offset: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, -1, 1) },
        offset_past_end: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 3, 1) },
        # `GetVertexCount(TriangleList, 2)` is six, and the window holds three.
        window_too_small: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, 2) },
        declaration_type: error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, 1, 5) }
      }
    end
    assert_equal [RangeError, "primitiveCount"], outcomes.fetch(:zero_count)
    assert_equal [RangeError, "primitiveCount"], outcomes.fetch(:negative_count)
    assert_equal [RangeError, "vertexOffset"], outcomes.fetch(:negative_offset)
    assert_equal [RangeError, "vertexOffset"], outcomes.fetch(:offset_past_end)
    assert_equal [RangeError, "primitiveCount"], outcomes.fetch(:window_too_small)
    assert_equal [TypeError, "vertexDeclaration must be a VertexDeclaration"],
                 outcomes.fetch(:declaration_type)
  end

  def test_the_indexed_guards
    outcomes = with_device do |device|
      vertices = triangle
      call = lambda do |*arguments|
        error_of { device.DrawUserIndexedPrimitives(::Integer, G::PrimitiveType::TriangleList, *arguments) }
      end
      {
        nil_indices: call.call(vertices, 0, 3, nil, 0, 1),
        empty_indices: call.call(vertices, 0, 3, [], 0, 1),
        not_an_array: call.call(vertices, 0, 3, "012", 0, 1),
        zero_vertices: call.call(vertices, 0, 0, [0, 1, 2], 0, 1),
        negative_index_offset: call.call(vertices, 0, 3, [0, 1, 2], -1, 1),
        index_offset_past_end: call.call(vertices, 0, 3, [0, 1, 2], 3, 1),
        # Three indices for one triangle, and the window from index 1 holds two.
        index_window_too_small: call.call(vertices, 0, 3, [0, 1, 2], 1, 1),
        vertices_past_end: call.call(vertices, 1, 3, [0, 1, 2], 0, 1),
        bad_index_type: error_of do
          device.DrawUserIndexedPrimitives(:sixteen, G::PrimitiveType::TriangleList,
                                           vertices, 0, 3, [0, 1, 2], 0, 1)
        end
      }
    end
    assert_equal [ArgumentError, "indexData"], outcomes.fetch(:nil_indices)
    assert_equal [ArgumentError, "indexData"], outcomes.fetch(:empty_indices)
    assert_equal TypeError, outcomes.fetch(:not_an_array).fetch(0)
    assert_equal [RangeError, "numVertices"], outcomes.fetch(:zero_vertices)
    assert_equal [RangeError, "indexOffset"], outcomes.fetch(:negative_index_offset)
    assert_equal [RangeError, "indexOffset"], outcomes.fetch(:index_offset_past_end)
    assert_equal [RangeError, "primitiveCount"], outcomes.fetch(:index_window_too_small)
    assert_equal [RangeError, "vertexData"], outcomes.fetch(:vertices_past_end)
    assert_equal TypeError, outcomes.fetch(:bad_index_type).fetch(0)
  end

  # `GetVertexCount` and `GetElementCountFromPrimitiveType` are the same four cases in XNA, and an
  # unknown topology answers `-1` compared **unsigned**, so it never fits any window.
  def test_the_element_count_rule_is_the_ils
    counts = with_device do |device|
      G::PrimitiveType.constants(false).sort.to_h do |name|
        topology = G::PrimitiveType.const_get(name)
        [name, device.__send__(:vertex_count_for, topology, 4)]
      end
    end
    assert_equal 12, counts.fetch(:TriangleList)
    assert_equal 6, counts.fetch(:TriangleStrip)
    assert_equal 8, counts.fetch(:LineList)
    assert_equal 5, counts.fetch(:LineStrip)
  end

  # ------------------------------------------------------------------ what the draw disturbs

  # `BeginUserPrimitives` unbinds every vertex stream and clears the instance-stream mask, and the
  # indexed draw's `finally` clears `_currentIB`. Neither is restored, so both are observable — and
  # the non-indexed draw leaves the index buffer alone, which is the half that is easy to get wrong.
  def test_a_user_draw_unbinds_the_streams_and_only_the_indexed_one_unbinds_the_indices
    outcome = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      indices = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None)
      begin
        device.SetVertexBuffer(buffer)
        device.Indices = indices
        error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
        after_plain = [device.GetVertexBuffers.length, device.Indices.equal?(indices)]

        device.SetVertexBuffer(buffer)
        error_of do
          device.DrawUserIndexedPrimitives(::Integer, G::PrimitiveType::TriangleList,
                                           triangle, 0, 3, [0, 1, 2], 0, 1)
        end
        [after_plain, [device.GetVertexBuffers.length, device.Indices.nil?]]
      ensure
        device.SetVertexBuffer(nil)
        device.Indices = nil
        buffer.Dispose
        indices.Dispose
      end
    end
    assert_equal [0, true], outcome.fetch(0), "the streams go, the indices stay"
    assert_equal [0, true], outcome.fetch(1), "and the indexed draw takes the indices too"
  end

  # `DeclarationManager` caches one native declaration per managed one, and `Reset` releases the
  # whole cache. Both are reproduced, so a per-frame draw does not build and destroy a declaration
  # every frame.
  def test_the_native_declaration_is_cached_per_managed_declaration_and_released_by_a_reset
    outcome = with_device do |device|
      error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
      first = device.__send__(:instance_variable_get, :@declaration_cache).values.dup
      error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
      second = device.__send__(:instance_variable_get, :@declaration_cache).values.dup
      error_of do
        device.DrawUserPrimitives(G::PrimitiveType::LineList,
                                  Array.new(2) { G::VertexPositionTexture.new }, 0, 1)
      end
      third = device.__send__(:instance_variable_get, :@declaration_cache).values.dup
      device.Reset
      [first, second, third, device.__send__(:instance_variable_get, :@declaration_cache)]
    end
    assert_equal 1, outcome.fetch(0).length
    assert_equal outcome.fetch(0), outcome.fetch(1), "the same declaration is not rebuilt"
    assert_equal 2, outcome.fetch(2).length, "a second layout is a second entry"
    assert_nil outcome.fetch(3), "and a reset releases them all"
  end

  # ------------------------------------------------------------------ reaching the renderer

  # Without a compiled effect there is nothing to draw *with*, and CNA says so rather than drawing
  # nothing quietly — the same answer the three device-buffer draws get.
  def test_a_user_draw_without_an_applied_effect_is_refused_by_the_renderer
    skip "this renderer has a compiled-effect runtime" if RendererEnvironment.compiled_effects?

    outcome = with_device do |device|
      error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
    end
    assert_equal CNA::NativeError, outcome.fetch(0)
    assert_includes outcome.fetch(1), "no effect has been applied"
  end

  # All four shapes, driven to the GPU: the implicit declaration, an explicit one, sixteen-bit
  # indices and thirty-two-bit ones. FNA's own `BasicEffect` is the fixture and
  # `VertexPositionColor` is a layout its vertex shader accepts.
  def test_every_shape_reaches_the_gpu_with_an_applied_effect
    skip "this renderer has no compiled-effect runtime" unless RendererEnvironment.compiled_effects?
    fixture = ENV["CNA_TEST_FX_BASIC"]
    skip "CNA_TEST_FX_BASIC not supplied" unless fixture && File.file?(fixture)

    outcomes = with_device do |device|
      effect = G::Effect.new(device, File.binread(fixture))
      begin
        effect.CurrentTechnique.Passes[0].Apply
        vertices = triangle
        [error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, 1) },
         error_of do
           device.DrawUserPrimitives(G::PrimitiveType::TriangleList, vertices, 0, 1,
                                     G::VertexPositionColor::VertexDeclaration)
         end,
         error_of do
           device.DrawUserIndexedPrimitives(G::IndexElementSize::SixteenBits,
                                            G::PrimitiveType::TriangleList, vertices, 0, 3,
                                            [0, 1, 2], 0, 1)
         end,
         error_of do
           device.DrawUserIndexedPrimitives(::Integer, G::PrimitiveType::TriangleList,
                                            vertices, 0, 3, [0, 1, 2], 0, 1)
         end]
      ensure
        effect.Dispose
      end
    end
    assert_equal %i[ok ok ok ok], outcomes
  end

  # ------------------------------------------------------------------ scope and disposal

  def test_both_members_are_callback_scoped_and_disposal_bound
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    outside = error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
    assert_equal CNA::InvalidBindingStateError, outside.fetch(0)
    game.Dispose
    disposed = error_of { device.DrawUserPrimitives(G::PrimitiveType::TriangleList, triangle, 0, 1) }
    assert_equal CNA::DisposedObjectError, disposed.fetch(0)
  end
end
