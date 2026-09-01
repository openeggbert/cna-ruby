# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `VertexBuffer`, `DynamicVertexBuffer`, `IndexBuffer`, `DynamicIndexBuffer` and the
# `VertexBufferBinding` that names one — the resources every `GraphicsDevice` draw call takes.
class VertexIndexBufferTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAMES = %w[VertexBuffer DynamicVertexBuffer IndexBuffer DynamicIndexBuffer VertexBufferBinding].freeze

  # ------------------------------------------------------------------------------- the contract

  def test_all_five_are_complete_and_carry_the_declared_hierarchy
    NAMES.each do |short|
      name = "Microsoft.Xna.Framework.Graphics.#{short}"
      assert_includes STRICT.fetch("completeTypeNames"), name, short
      assert_empty ReviewedScoreboard.partial_remainder(STRICT, name), short
    end
    assert_equal G::GraphicsResource, G::VertexBuffer.superclass
    assert_equal G::GraphicsResource, G::IndexBuffer.superclass
    assert_equal G::VertexBuffer, G::DynamicVertexBuffer.superclass
    assert_equal G::IndexBuffer, G::DynamicIndexBuffer.superclass
    # The two static buffers are not sealed precisely because the dynamic ones derive from them.
    %w[VertexBuffer IndexBuffer].each do |short|
      refute REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.#{short}").fetch("sealed"), short
    end
    assert REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.VertexBufferBinding").fetch("sealed")
    assert_equal "struct", REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.VertexBufferBinding").fetch("kind")
  end

  # The route choice this milestone had to make, stated where it can be checked.
  def test_the_two_version_admission_chose_the_dynamic_route
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
    # The static path is the raw family: any element layout, no options.
    assert_includes symbols, "cna_vertex_buffer_set_data_raw_at"
    assert_includes symbols, "cna_vertex_buffer_get_data_raw"
    # The dynamic path is the typed one, because the raw route that carries SetDataOptions exists
    # only in 0.21.0 and binding it would end the retired 0.7.0 headers' admission.
    assert_includes symbols, "cna_vertex_buffer_set_data"
    refute_includes symbols, "cna_vertex_buffer_set_data_raw_at_with_options"
    refute_includes symbols, "cna_vertex_buffer_set_data_raw_with_options"
    # Both index routes are declared by both versions, so the index path needed no such choice.
    assert_includes symbols, "cna_index_buffer_set_data"
    assert_includes symbols, "cna_index_buffer_set_data_at"
    assert_equal 2, CNA::Native::Manifest::ADMITTED_ABI_VERSIONS.length
  end

  # ------------------------------------------------------------------------------ live behaviour

  class BufferGame < F::Game
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

    game = BufferGame.new { |device| yield device }
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

  TRIANGLE = [[1.0, 2.0, 3.0, 10, 20, 30, 40], [4.0, 5.0, 6.0, 50, 60, 70, 80],
              [7.0, 8.0, 9.0, 90, 100, 110, 120]].freeze

  def vertices
    TRIANGLE.map do |x, y, z, r, g, b, a|
      G::VertexPositionColor.new(F::Vector3.new(x, y, z), F::Color.new(r, g, b, a))
    end
  end

  def test_the_constructor_refusals_are_the_ils_own
    values = with_device do |device|
      [error_of { G::VertexBuffer.new(nil, G::VertexPositionColor, 3, G::BufferUsage::None) },
       error_of { G::VertexBuffer.new(device, nil, 3, G::BufferUsage::None) },
       error_of { G::VertexBuffer.new(device, G::VertexPositionColor, 0, G::BufferUsage::None) },
       error_of { G::VertexBuffer.new(device, G::VertexPositionColor, -1, G::BufferUsage::None) },
       error_of { G::VertexBuffer.new(device, G::VertexPositionColor, 3, 0) },
       error_of { G::VertexBuffer.new(device, ::String, 3, G::BufferUsage::None) },
       error_of { G::IndexBuffer.new(nil, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None) },
       error_of { G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 0, G::BufferUsage::None) },
       error_of { G::IndexBuffer.new(device, ::Float, 3, G::BufferUsage::None) }]
    end
    assert_equal [ArgumentError, "graphicsDevice"], values[0]
    assert_equal [ArgumentError, "vertexDeclaration"], values[1]
    assert_equal [[RangeError, "vertexCount"]] * 2, values[2..3]
    assert_equal TypeError, values[4].first
    assert_equal TypeError, values[5].first, "a type that declares no VertexDeclaration"
    assert_equal [ArgumentError, "graphicsDevice"], values[6]
    assert_equal [RangeError, "indexCount"], values[7]
    assert_equal TypeError, values[8].first
  end

  # A `Type` argument means `VertexDeclaration.FromType`, which is what the vertex structs' own
  # `VertexDeclaration` constant is, so both constructors reach the same declaration.
  def test_a_type_and_a_declaration_reach_the_same_layout
    values = with_device do |device|
      from_type = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      from_declaration = G::VertexBuffer.new(device, G::VertexPositionColor::VertexDeclaration, 3,
                                             G::BufferUsage::WriteOnly)
      result = [from_type.VertexDeclaration.equal?(G::VertexPositionColor::VertexDeclaration),
                from_declaration.VertexDeclaration.equal?(G::VertexPositionColor::VertexDeclaration),
                [from_type.VertexCount, from_type.BufferUsage.to_s],
                [from_declaration.VertexCount, from_declaration.BufferUsage.to_s],
                from_type.GraphicsDevice.equal?(device)]
      from_type.Dispose
      from_declaration.Dispose
      result << from_type.IsDisposed
    end
    assert_equal [true, true, [3, "None"], [3, "WriteOnly"], true, true], values
  end

  def test_vertices_round_trip_exactly_through_the_raw_route
    expected = vertices
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      buffer.SetData(G::VertexPositionColor, expected)
      whole = ::Array.new(3) { G::VertexPositionColor.new }
      buffer.GetData(G::VertexPositionColor, whole)
      # The five-argument form addresses a byte window: the second and third vertices only.
      window = ::Array.new(2) { G::VertexPositionColor.new }
      buffer.GetData(G::VertexPositionColor, 16, window, 0, 2, 16)
      # And a String element type is the raw bytes of the same three vertices.
      raw = +("\0" * 48)
      buffer.GetData(::String, raw)
      result = [whole, window, raw.bytesize, raw[0, 12].unpack("f3")]
      buffer.Dispose
      result
    end
    assert_equal expected, values[0], "every field of every vertex"
    assert_equal expected[1, 2], values[1]
    assert_equal 48, values[2]
    assert_equal [1.0, 2.0, 3.0], values[3]
  end

  def test_indices_round_trip_at_both_widths
    values = with_device do |device|
      small = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 6, G::BufferUsage::None)
      small.SetData(::Integer, [0, 1, 2, 2, 1, 3])
      short_back = ::Array.new(6, 0)
      small.GetData(::Integer, short_back)
      wide = G::IndexBuffer.new(device, ::Integer, 4, G::BufferUsage::None)
      wide.SetData(::Integer, [70_000, 1, 2, 3])
      wide_back = ::Array.new(4, 0)
      wide.GetData(::Integer, wide_back)
      result = [short_back, wide_back, small.IndexElementSize.to_s, wide.IndexElementSize.to_s,
                error_of { small.SetData(::Integer, [70_000]) },
                error_of { small.SetData(::Float, [1.0]) }]
      small.Dispose
      wide.Dispose
      result
    end
    assert_equal [0, 1, 2, 2, 1, 3], values[0]
    assert_equal [70_000, 1, 2, 3], values[1], "a thirty-two-bit buffer really holds a wide index"
    assert_equal "SixteenBits", values[2]
    assert_equal "ThirtyTwoBits", values[3], "Integer is XNA's int overload, which is thirty-two bits"
    assert_equal [RangeError, "value"], values[4], "70000 does not fit sixteen bits"
    assert_equal TypeError, values[5].first
  end

  # A windowed **upload** is the half the read test does not cover: the five-argument form writes at
  # a byte offset and leaves the rest of the buffer where it was.
  def test_a_windowed_upload_changes_only_the_vertices_it_names
    replacement = G::VertexPositionColor.new(F::Vector3.new(-1.0, -2.0, -3.0), F::Color.new(1, 2, 3, 4))
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      buffer.SetData(G::VertexPositionColor, vertices)
      # 16 bytes in is the second vertex, and one vertex is what is written.
      buffer.SetData(G::VertexPositionColor, 16, [replacement], 0, 1, 16)
      back = ::Array.new(3) { G::VertexPositionColor.new }
      buffer.GetData(G::VertexPositionColor, back)
      buffer.Dispose
      back
    end
    assert_equal vertices[0], values[0], "the vertex before the window is untouched"
    assert_equal replacement, values[1]
    assert_equal vertices[2], values[2], "and so is the one after it"
  end

  # `element_size` and the pack/unpack pair carry four element types besides a vertex struct, and
  # every one of them is a real XNA `SetData<T>` instantiation over a buffer's bytes. The window's
  # total size has to fill whole strides, which is why each of these addresses the buffer at the
  # element's own size rather than the declaration's.
  def test_every_projected_element_type_round_trips_at_its_own_size
    colours = ::Array.new(8) { |index| F::Color.new(index, index + 1, index + 2, 255) }
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 2, G::BufferUsage::None)
      # Two VertexPositionColor vertices are 32 bytes, which is 8 Colors, 8 Singles, 8 Int32s or
      # 32 String bytes -- one buffer, four ways of addressing the same storage.
      buffer.SetData(F::Color, 0, colours, 0, 8, 4)
      back_colours = ::Array.new(8) { F::Color.new(0, 0, 0, 0) }
      buffer.GetData(F::Color, 0, back_colours, 0, 8, 4)

      buffer.SetData(::Float, 0, [1.5, -2.5, 0.25, 8.0], 0, 4, 4)
      back_floats = ::Array.new(4, 0.0)
      buffer.GetData(::Float, 0, back_floats, 0, 4, 4)

      buffer.SetData(::Integer, 0, [7, -9, 11, 13], 0, 4, 4)
      back_integers = ::Array.new(4, 0)
      buffer.GetData(::Integer, 0, back_integers, 0, 4, 4)

      raw = +("\0" * 16)
      # A zero stride is XNA's tightly-packed reading, which is what a byte window is.
      buffer.GetData(::String, 0, raw, 0, 16, 0)
      result = [back_colours.map(&:PackedValue), back_floats, back_integers,
                raw[0, 8].unpack("l2"),
                error_of { buffer.SetData(::Symbol, [:x]) },
                error_of { buffer.SetData(F::Color, 0, [1, 2, 3, 4], 0, 4, 4) }]
      buffer.Dispose
      result
    end
    assert_equal colours.map(&:PackedValue), values[0], "a packed colour survives the round trip"
    assert_equal [1.5, -2.5, 0.25, 8.0], values[1]
    assert_equal [7, -9, 11, 13], values[2]
    assert_equal [7, -9], values[3], "and the String view sees the same bytes the Int32 view wrote"
    assert_equal TypeError, values[4].first, "Symbol is not a buffer element type"
    assert_equal TypeError, values[5].first, "and an Integer is not a Color"
  end

  def test_the_copy_parameter_rules_are_the_shared_helpers
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      data = vertices
      result = [error_of { buffer.SetData(G::VertexPositionColor, data, -1, 1) },
                error_of { buffer.SetData(G::VertexPositionColor, data, 0, 0) },
                error_of { buffer.SetData(G::VertexPositionColor, data, 2, 2) },
                error_of { buffer.SetData(G::VertexPositionColor, nil) },
                error_of { buffer.SetData(G::VertexPositionColor, data, 0, 1, 2) },
                error_of { buffer.SetData(G::VertexPositionColor, -16, data, 0, 1, 16) }]
      buffer.Dispose
      result
    end
    assert_equal [RangeError, "dataIndex"], values[0]
    assert_equal [RangeError, "elementCount"], values[1]
    assert_equal [RangeError, "elementCount"], values[2]
    assert_equal [ArgumentError, "data"], values[3]
    assert_equal ArgumentError, values[4].first, "five arguments is not an overload"
    assert_equal [RangeError, "offsetInBytes"], values[5]
  end

  # `CopyData`'s two size rules, read out of the IL rather than invented: a non-zero stride must be
  # at least `sizeof(T)`, and the span the copy touches -- `sizeof(T) + (elementCount - 1) * stride`
  # -- must fit inside the buffer from `offsetInBytes`.
  def test_the_size_rules_are_the_ils_own_and_the_strided_window_has_no_route
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      indices = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 4, G::BufferUsage::None)
      result = [
        # VertexStrideTooSmall: a 16-byte vertex cannot be written at a stride of 8.
        error_of { buffer.SetData(G::VertexPositionColor, 0, vertices, 0, 1, 8) },
        # ResourceDataMustBeCorrectSize: 16 + 2 * 16 = 48 bytes, 16 in, off the end of a 48-byte
        # buffer by exactly one stride.
        error_of { buffer.SetData(G::VertexPositionColor, 16, vertices, 0, 3, 16) },
        # ...and the same rule from the last byte that does fit.
        error_of { buffer.SetData(G::VertexPositionColor, 16, vertices, 0, 2, 16) },
        # A strided window -- one Color per vertex, XNA's way of rewriting one component -- is
        # inside every IL rule and has no CNA route.
        error_of { buffer.SetData(F::Color, 0, [F::Color.new(1, 2, 3, 4)] * 3, 0, 3, 16) },
        # Nor has a window that starts inside a vertex.
        error_of { buffer.SetData(::String, 4, "\0" * 16, 0, 16, 0) },
        # The gap term is what makes a strided window overrun: three Colors at a stride of 16 touch
        # 4 + 2 * 16 = 36 bytes, so from 16 in they run off the end of a 48-byte buffer -- and the
        # IL's size rule is checked before anything else can refuse them.
        error_of { buffer.SetData(F::Color, 16, [F::Color.new(1, 2, 3, 4)] * 3, 0, 3, 16) },
        # The index buffer's one size rule, from its own CopyData.
        error_of { indices.SetData(::Integer, [1, 2, 3, 4, 5]) },
        error_of { indices.SetData(::Integer, 2, [1, 2, 3, 4], 0, 4) },
        error_of { indices.SetData(::Integer, 2, [1, 2, 3], 0, 3) }
      ]
      buffer.Dispose
      indices.Dispose
      result
    end
    assert_equal [RangeError, "vertexStride"], values[0]
    assert_equal [RuntimeError, "ResourceDataMustBeCorrectSize"], values[1]
    assert_equal :ok, values[2], "two vertices at 16 bytes in is the last window that fits"
    assert_equal CNA::Runtime::NotSupportedError, values[3].first
    assert_includes values[3].last, "declaration stride (16)"
    assert_equal CNA::Runtime::NotSupportedError, values[4].first
    assert_equal [RuntimeError, "ResourceDataMustBeCorrectSize"], values[5],
                 "the span a strided copy touches counts the gaps between its elements"
    assert_equal [RuntimeError, "ResourceDataMustBeCorrectSize"], values[6],
                 "five indices do not fit a four-index buffer, and the array they came from is fine"
    assert_equal [RuntimeError, "ResourceDataMustBeCorrectSize"], values[7]
    assert_equal :ok, values[8]
  end

  # UPSTREAM, reproduced at the C ABI with no Ruby in the path: the raw route documents a
  # "positive byte size of one source vertex" and accepts only the buffer's declaration stride.
  # If CNA ever widens it, this assertion is what notices.
  def test_the_raw_route_itself_refuses_a_stride_that_is_not_the_declarations
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 2, G::BufferUsage::None)
      handle = buffer.__send__(:native_handle)
      payload = Fiddle::Pointer[("\0" * 32)]
      result = [error_of do
                  CNA::Native.library.call("cna_vertex_buffer_set_data_raw_at", handle, 0, payload,
                                           32, 8, 4)
                end,
                error_of do
                  CNA::Native.library.call("cna_vertex_buffer_set_data_raw_at", handle, 0, payload,
                                           32, 2, 16)
                end]
      buffer.Dispose
      result
    end
    assert_equal CNA::NativeError, values[0].first
    assert_includes values[0].last, "vertex stride does not match"
    assert_equal :ok, values[1], "and the declaration's own stride is accepted"
  end

  # DEVIATION, recorded: the option-bearing route is CNA's typed one, so its element type must be
  # one of the built-in layouts. XNA accepts any struct there.
  def test_the_dynamic_buffers_take_options_and_the_typed_route_limits_the_element_type
    values = with_device do |device|
      buffer = G::DynamicVertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::WriteOnly)
      indices = G::DynamicIndexBuffer.new(device, G::IndexElementSize::ThirtyTwoBits, 4,
                                          G::BufferUsage::WriteOnly)
      result = { content_lost: buffer.IsContentLost,
                 index_content_lost: indices.IsContentLost,
                 vertex_options: error_of { buffer.SetData(G::VertexPositionColor, vertices, 0, 3, G::SetDataOptions::Discard) },
                 index_options: error_of { indices.SetData(::Integer, [1, 2, 3, 4], 0, 4, G::SetDataOptions::Discard) },
                 refused: error_of { buffer.SetData(F::Color, [F::Color.new(1, 2, 3, 4)], 0, 1, G::SetDataOptions::Discard) },
                 # The two option-bearing shapes are the dynamic buffer's own; the static one has
                 # neither, and its four-argument list is the offset form.
                 static_refuses: begin
                   static = G::IndexBuffer.new(device, G::IndexElementSize::ThirtyTwoBits, 4,
                                               G::BufferUsage::None)
                   error_of { static.SetData(::Integer, [1, 2, 3, 4], 0, 4, G::SetDataOptions::Discard) }
                     .tap { static.Dispose }
                 end,
                 # The inherited option-free overloads still take any element type.
                 inherited: error_of { buffer.SetData(G::VertexPositionColor, vertices) },
                 event: buffer.ContentLost.respond_to?(:add) }
      buffer.Dispose
      indices.Dispose
      result
    end
    refute values.fetch(:content_lost), "no qualified renderer loses a device"
    refute values.fetch(:index_content_lost)
    assert_equal :ok, values.fetch(:vertex_options)
    assert_equal :ok, values.fetch(:index_options)
    assert_equal CNA::Runtime::NotSupportedError, values.fetch(:refused).first
    assert_equal ::ArgumentError, values.fetch(:static_refuses).first
    assert_equal :ok, values.fetch(:inherited)
    assert values.fetch(:event), "ContentLost is subscribable, and never fires here"
  end

  # `VertexBufferBinding`'s three values are read back from the structure CNA fills, not assembled
  # in Ruby, so what a consumer sees is what the C ABI really holds.
  def test_the_binding_is_cnas_own_and_op_implicit_is_the_one_argument_form
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 4, G::BufferUsage::None)
      explicit = G::VertexBufferBinding.new(buffer, 2, 3)
      defaulted = G::VertexBufferBinding.new(buffer)
      implicit = G::VertexBufferBinding.op_Implicit(buffer)
      result = [[explicit.VertexOffset, explicit.InstanceFrequency],
                [defaulted.VertexOffset, defaulted.InstanceFrequency],
                [implicit.VertexOffset, implicit.InstanceFrequency],
                explicit.VertexBuffer.equal?(buffer),
                defaulted == implicit,
                # XNA declares no Equals and no GetHashCode here, so equality is ValueType's --
                # field-wise, with a hash the CLR leaves unspecified. Ruby needs a working `hash`
                # for `eql?` to be usable, and this one is answered over the same three components
                # rather than through a GetHashCode identity the contract never selects.
                defaulted.hash == implicit.hash,
                explicit.hash == defaulted.hash,
                G::VertexBufferBinding.public_method_defined?(:GetHashCode),
                { defaulted => :seen }.fetch(implicit, :absent),
                error_of { G::VertexBufferBinding.new(nil) },
                error_of { G::VertexBufferBinding.new(buffer, -1) },
                error_of { G::VertexBufferBinding.new(buffer, 0, -1) },
                error_of { G::VertexBufferBinding.new("buffer") }]
      buffer.Dispose
      result
    end
    assert_equal [2, 3], values[0]
    assert_equal [0, 0], values[1]
    assert_equal [0, 0], values[2], "op_Implicit is the one-argument constructor"
    assert values[3]
    assert values[4], "two bindings over the same buffer with the same values are equal"
    assert values[5], "and hash agrees with equality"
    refute values[6], "while a binding with different values does not have to"
    refute values[7], "no GetHashCode identity is published, because XNA declares none"
    assert_equal :seen, values[8], "so a binding is usable as a Hash key"
    assert_equal [ArgumentError, "vertexBuffer"], values[9]
    assert_equal [RangeError, "vertexOffset"], values[10]
    assert_equal [RangeError, "instanceFrequency"], values[11]
    assert_equal TypeError, values[12].first
  end

  # The buffer owns the native declaration it built, so disposing it releases both.
  def test_disposal_releases_the_buffer_and_the_declaration_it_built
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None)
      declaration = buffer.instance_variable_get(:@native_declaration)
      buffer.Dispose
      [buffer.IsDisposed,
       error_of { buffer.Dispose },
       error_of { buffer.SetData(G::VertexPositionColor, vertices) },
       # The declaration the buffer built went with it: destroying that handle a second time is
       # refused, which is only true because the first destruction happened.
       declaration.positive?,
       error_of { CNA::Native.library.call("cna_vertex_declaration_destroy", declaration) }]
    end
    assert values[0]
    assert_equal :ok, values[1], "Dispose is idempotent"
    assert_equal CNA::DisposedObjectError, values[2].first
    assert values[3], "the buffer really owns a native declaration handle"
    assert_equal CNA::NativeError, values[4].first, "and Dispose already destroyed it"
  end
end
