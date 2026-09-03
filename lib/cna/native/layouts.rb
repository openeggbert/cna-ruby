# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    module Layouts
      Field = Data.define(:name, :c_type, :offset, :size, :pointer_depth, :const)

      class Structure
        class << self
          attr_reader :size, :alignment, :fields

          def layout(size:, alignment:, fields:)
            @size = size
            @alignment = alignment
            @fields = fields.map { |row| Field.new(**row) }.freeze
          end
        end

        attr_reader :pointer

        def initialize
          @pointer = Fiddle::Pointer.malloc(self.class.size, Fiddle::RUBY_FREE)
          @pointer[0, self.class.size] = "\0" * self.class.size
        end

        def address = pointer.to_i

        def write_u8(offset, value) = pointer[offset, 1] = [value].pack("C")
        def read_u8(offset) = pointer[offset, 1].unpack1("C")
        def write_u32(offset, value) = pointer[offset, 4] = [value].pack("L")
        def read_u32(offset) = pointer[offset, 4].unpack1("L")
        # `CNA_Char16` is the one 16-bit field any bound layout carries.
        def read_u16(offset) = pointer[offset, 2].unpack1("S")
        def write_i32(offset, value) = pointer[offset, 4] = [value].pack("l")
        def read_i32(offset) = pointer[offset, 4].unpack1("l")
        def write_u64(offset, value) = pointer[offset, 8] = [value].pack("Q")
        def read_u64(offset) = pointer[offset, 8].unpack1("Q")
        def write_i64(offset, value) = pointer[offset, 8] = [value].pack("q")
        def read_i64(offset) = pointer[offset, 8].unpack1("q")
        def write_f32(offset, value) = pointer[offset, 4] = [value].pack("f")
        def read_f32(offset) = pointer[offset, 4].unpack1("f")
        def write_pointer(offset, value) = write_u64(offset, value.respond_to?(:to_i) ? value.to_i : value)
      end

      def self.field(name, c_type, offset, size, pointer_depth: 0, const: false)
        { name: name, c_type: c_type, offset: offset, size: size,
          pointer_depth: pointer_depth, const: const }
      end

      class StringView < Structure
        layout size: 16, alignment: 8, fields: [
          Layouts.field("data", "char", 0, 8, pointer_depth: 1, const: true),
          Layouts.field("byte_length", "uint64_t", 8, 8)
        ]

        def initialize(bytes = "")
          super()
          @bytes = String(bytes).b
          @buffer = Fiddle::Pointer[@bytes]
          write_pointer(0, @buffer)
          write_u64(8, @bytes.bytesize)
        end
      end

      # `CNA_Rectangle` is four `int32_t` in position-then-size order, which is exactly the XNA
      # Rectangle's own field order. It is the output of `cna_game_window_get_client_bounds`.
      class Rectangle < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("x", "int32_t", 0, 4),
          Layouts.field("y", "int32_t", 4, 4),
          Layouts.field("width", "int32_t", 8, 4),
          Layouts.field("height", "int32_t", 12, 4)
        ]
      end

      class ErrorInfo < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("result", "CNA_Result", 8, 4),
          Layouts.field("category", "CNA_ErrorCategory", 12, 4),
          Layouts.field("message_byte_length", "uint64_t", 16, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class GameTime < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("total_game_time_ticks", "int64_t", 0, 8),
          Layouts.field("elapsed_game_time_ticks", "int64_t", 8, 8),
          Layouts.field("is_running_slowly", "CNA_Bool", 16, 1),
          Layouts.field("reserved", "uint8_t[7]", 17, 7)
        ]
      end

      class CallbackError < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("message", "CNA_StringView", 8, 16)
        ]
      end

      class GameCallbacks < Structure
        layout size: 56, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("load_content", "CNA_GameLifecycleCallback", 8, 8, pointer_depth: 1),
          Layouts.field("update", "CNA_GameLifecycleCallback", 16, 8, pointer_depth: 1),
          Layouts.field("draw", "CNA_GameLifecycleCallback", 24, 8, pointer_depth: 1),
          Layouts.field("unload_content", "CNA_GameLifecycleCallback", 32, 8, pointer_depth: 1),
          Layouts.field("exiting", "CNA_GameLifecycleCallback", 40, 8, pointer_depth: 1),
          Layouts.field("context", "void", 48, 8, pointer_depth: 1)
        ]

        def initialize(callbacks)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          callbacks.each_with_index { |callback, index| write_pointer(8 + index * 8, callback) }
          write_pointer(48, 0)
        end
      end

      class GameFrameHooks < Structure
        layout size: 56, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("initialize", "CNA_GameLifecycleCallback", 8, 8, pointer_depth: 1),
          Layouts.field("begin_run", "CNA_GameLifecycleCallback", 16, 8, pointer_depth: 1),
          Layouts.field("end_run", "CNA_GameLifecycleCallback", 24, 8, pointer_depth: 1),
          Layouts.field("begin_draw", "CNA_GameBeginDrawCallback", 32, 8, pointer_depth: 1),
          Layouts.field("end_draw", "CNA_GameLifecycleCallback", 40, 8, pointer_depth: 1),
          Layouts.field("context", "void", 48, 8, pointer_depth: 1)
        ]

        def initialize(callbacks)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          callbacks.each_with_index { |callback, index| write_pointer(8 + index * 8, callback) }
          write_pointer(48, 0)
        end
      end

      class GameCreateInfo < Structure
        layout size: 48, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("is_fixed_time_step", "CNA_Bool", 8, 1),
          Layouts.field("reserved", "uint8_t[7]", 9, 7),
          Layouts.field("target_elapsed_time_ticks", "int64_t", 16, 8),
          Layouts.field("window_title", "CNA_StringView", 24, 16),
          Layouts.field("callbacks", "CNA_GameCallbacks", 40, 8, pointer_depth: 1, const: true)
        ]

        def initialize(fixed:, target_ticks:, title:, callbacks:)
          super()
          @title = StringView.new(title)
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u8(8, fixed ? 1 : 0)
          write_i64(16, target_ticks)
          pointer[24, 16] = @title.pointer[0, 16]
          write_pointer(40, callbacks.address)
        end
      end

      class Viewport < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("x", "int32_t", 0, 4), Layouts.field("y", "int32_t", 4, 4),
          Layouts.field("width", "int32_t", 8, 4), Layouts.field("height", "int32_t", 12, 4),
          Layouts.field("min_depth", "float", 16, 4), Layouts.field("max_depth", "float", 20, 4)
        ]
      end

      class Texture2DInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("level_count", "uint32_t", 16, 4), Layouts.field("format", "CNA_SurfaceFormat", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # `CNA_ContentManagerCreateInfo`: two versioning words, a by-value `CNA_StringView` for the
      # root directory and one reserved word. The string view is embedded rather than passed, so
      # this is an ordinary aggregate and needs none of the eightbyte expansion a by-value
      # *parameter* does; the bytes the view points at must outlive the call, which is why the
      # constructor keeps the buffer alive on the instance.
      class ContentManagerCreateInfo < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("root_directory", "CNA_StringView", 8, 16),
          Layouts.field("reserved", "uint64_t", 24, 8)
        ]

        def initialize(root_directory)
          super()
          @bytes = String(root_directory).b
          @buffer = Fiddle::Pointer[@bytes]
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_pointer(8, @buffer)
          write_u64(16, @bytes.bytesize)
        end
      end

      # The audio value structures. `CNA_AudioListener` and `CNA_AudioEmitter` carry the same four
      # `CNA_Vector3` fields; the emitter adds its own `doppler_scale` ahead of them, which is why
      # the two layouts differ by twelve bytes and not four.
      class TextureSlotInfo < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("bound", "CNA_Bool", 8, 1), Layouts.field("reserved", "uint8_t", 9, 7),
          Layouts.field("texture", "CNA_Handle", 16, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class SoundEffectCreateInfo < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("sample_rate", "uint32_t", 8, 4), Layouts.field("channels", "CNA_AudioChannels", 12, 4),
          Layouts.field("reserved", "uint64_t", 16, 8)
        ]

        def initialize(sample_rate, channels)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u32(8, sample_rate)
          write_u32(12, channels)
        end
      end

      # `CNA_CueInfo` answers all seven of XNA's cue status bits in one read, where XACT's own
      # `GetStatus` is a bitmask -- `IsCreated` 1, `IsPreparing` 2, `IsPrepared` 4, `IsPlaying` 8,
      # `IsStopping` 0x10, `IsStopped` 0x20, `IsPaused` 0x40. Each projected property reads the
      # struct once, which is what XNA does too: every one of its getters calls `GetStatus`.
      class CueInfo < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("is_created", "CNA_Bool", 8, 1), Layouts.field("is_disposed", "CNA_Bool", 9, 1),
          Layouts.field("is_paused", "CNA_Bool", 10, 1), Layouts.field("is_playing", "CNA_Bool", 11, 1),
          Layouts.field("is_prepared", "CNA_Bool", 12, 1), Layouts.field("is_preparing", "CNA_Bool", 13, 1),
          Layouts.field("is_stopped", "CNA_Bool", 14, 1), Layouts.field("is_stopping", "CNA_Bool", 15, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # `CNA_SpriteFontInfo` answers the four scalar properties XNA keeps in fields, plus the
      # character count that sizes the two copy routes.
      # `CNA_Texture2DCreateInfo` is what XNA's two public constructors reduce to once
      # `CreateTexture`'s fixed arguments are applied.
      # `CNA_Texture2DTransfer` carries what XNA's three `SetData`/`GetData` overloads differ by:
      # the mip level, an optional sub-rectangle, and the caller array's start and count.
      # `CNA_Texture2DDecodeInfo` is what XNA's five-argument `FromStream` carries: a requested
      # output size and whether to cover-and-crop rather than fit.
      class Texture2DDecodeInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("zoom", "CNA_Bool", 16, 1), Layouts.field("reserved", "uint8_t", 17, 7)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # `CNA_VertexElement` is the same four fields XNA's value type declares, in the same order,
      # and it carries no versioned header — it is a plain descriptor rather than a create-info.
      class VertexElement < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("offset", "int32_t", 0, 4),
          Layouts.field("format", "CNA_VertexElementFormat", 4, 4),
          Layouts.field("usage", "CNA_VertexElementUsage", 8, 4),
          Layouts.field("usage_index", "int32_t", 12, 4)
        ]
      end

      # The four graphics state PODs. Each is a complete, versioned value with no handle in it: the
      # `cna_*_state_init` routes fill one from a preset identity, which is what makes them usable
      # as a cross-check for values derived from the pinned XNA IL.
      class BlendState < Structure
        layout size: 56, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("alpha_blend_function", "CNA_BlendFunction", 8, 4),
          Layouts.field("alpha_destination_blend", "CNA_Blend", 12, 4),
          Layouts.field("alpha_source_blend", "CNA_Blend", 16, 4),
          Layouts.field("color_blend_function", "CNA_BlendFunction", 20, 4),
          Layouts.field("color_destination_blend", "CNA_Blend", 24, 4),
          Layouts.field("color_source_blend", "CNA_Blend", 28, 4),
          Layouts.field("color_write_channels", "CNA_ColorWriteChannels", 32, 4),
          Layouts.field("color_write_channels1", "CNA_ColorWriteChannels", 36, 4),
          Layouts.field("color_write_channels2", "CNA_ColorWriteChannels", 40, 4),
          Layouts.field("color_write_channels3", "CNA_ColorWriteChannels", 44, 4),
          Layouts.field("blend_factor", "CNA_Color", 48, 4),
          Layouts.field("multi_sample_mask", "int32_t", 52, 4)
        ]

        # CNA validates `struct_size` and `struct_version` on the way **in** as well as filling
        # them on the way out, so a descriptor handed to a `get` route must already carry them.
        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class DepthStencilState < Structure
        layout size: 64, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("depth_buffer_enable", "CNA_Bool", 8, 1),
          Layouts.field("depth_buffer_write_enable", "CNA_Bool", 9, 1),
          Layouts.field("stencil_enable", "CNA_Bool", 10, 1),
          Layouts.field("two_sided_stencil_mode", "CNA_Bool", 11, 1),
          Layouts.field("depth_buffer_function", "CNA_CompareFunction", 12, 4),
          Layouts.field("stencil_function", "CNA_CompareFunction", 16, 4),
          Layouts.field("stencil_mask", "int32_t", 20, 4),
          Layouts.field("stencil_write_mask", "int32_t", 24, 4),
          Layouts.field("reference_stencil", "int32_t", 28, 4),
          Layouts.field("stencil_fail", "CNA_StencilOperation", 32, 4),
          Layouts.field("stencil_depth_buffer_fail", "CNA_StencilOperation", 36, 4),
          Layouts.field("stencil_pass", "CNA_StencilOperation", 40, 4),
          Layouts.field("counter_clockwise_stencil_function", "CNA_CompareFunction", 44, 4),
          Layouts.field("counter_clockwise_stencil_fail", "CNA_StencilOperation", 48, 4),
          Layouts.field("counter_clockwise_stencil_depth_buffer_fail", "CNA_StencilOperation", 52, 4),
          Layouts.field("counter_clockwise_stencil_pass", "CNA_StencilOperation", 56, 4),
          Layouts.field("reserved", "uint32_t", 60, 4)
        ]

        # CNA validates `struct_size` and `struct_version` on the way **in** as well as filling
        # them on the way out, so a descriptor handed to a `get` route must already carry them.
        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class RasterizerState < Structure
        layout size: 28, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("cull_mode", "CNA_CullMode", 8, 4),
          Layouts.field("fill_mode", "CNA_FillMode", 12, 4),
          Layouts.field("depth_bias", "float", 16, 4),
          Layouts.field("slope_scale_depth_bias", "float", 20, 4),
          Layouts.field("multi_sample_anti_alias", "CNA_Bool", 24, 1),
          Layouts.field("scissor_test_enable", "CNA_Bool", 25, 1),
          Layouts.field("reserved", "uint8_t", 26, 2)
        ]

        # CNA validates `struct_size` and `struct_version` on the way **in** as well as filling
        # them on the way out, so a descriptor handed to a `get` route must already carry them.
        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class SamplerState < Structure
        layout size: 40, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("address_u", "CNA_TextureAddressMode", 8, 4),
          Layouts.field("address_v", "CNA_TextureAddressMode", 12, 4),
          Layouts.field("address_w", "CNA_TextureAddressMode", 16, 4),
          Layouts.field("filter", "CNA_TextureFilter", 20, 4),
          Layouts.field("max_anisotropy", "int32_t", 24, 4),
          Layouts.field("max_mip_level", "int32_t", 28, 4),
          Layouts.field("mip_map_level_of_detail_bias", "float", 32, 4),
          Layouts.field("reserved", "uint32_t", 36, 4)
        ]

        # CNA validates `struct_size` and `struct_version` on the way **in** as well as filling
        # them on the way out, so a descriptor handed to a `get` route must already carry them.
        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Texture2DTransfer < Structure
        layout size: 48, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("level", "int32_t", 8, 4), Layouts.field("has_rectangle", "CNA_Bool", 12, 1),
          Layouts.field("reserved", "uint8_t", 13, 3),
          Layouts.field("rectangle", "CNA_Rectangle", 16, 16),
          Layouts.field("start_index", "uint64_t", 32, 8), Layouts.field("element_count", "uint64_t", 40, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # `CNA_Texture3DCreateInfo`/`Info`/`Transfer` and the three cube-map counterparts. The volume
      # transfer carries a box -- left/top/right/bottom/front/back -- rather than a rectangle, which
      # is exactly the shape of XNA's own ten-argument `Texture3D.SetData` overload; the cube
      # transfer carries a face and a rectangle, which is the shape of `TextureCube`'s six-argument
      # one.
      # The logical back buffer, which XNA's scissor validation needs: its rule is the current
      # render target's bounds or the back buffer's, and nothing here can bind a render target.
      class BackBufferInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("format", "CNA_SurfaceFormat", 16, 4),
          Layouts.field("reserved", "uint32_t", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # `CNA_PresentationParameters`, the versioned display structure `GraphicsDevice`'s cached
      # parameters are read from. It is a *caller-initialized* output -- `display.h` says so -- so
      # it fills its size and version in the constructor, exactly as `CNA_BackBufferInfo` does.
      #
      # `CNA_DisplayMode` is deliberately absent: no bound route reads one, because the route that
      # would answers invented hardware. See `Manifest`'s note beside the display properties.
      class PresentationParameters < Structure
        layout size: 44, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("back_buffer_format", "CNA_SurfaceFormat", 8, 4),
          Layouts.field("back_buffer_width", "int32_t", 12, 4),
          Layouts.field("back_buffer_height", "int32_t", 16, 4),
          Layouts.field("depth_stencil_format", "CNA_DepthFormat", 20, 4),
          Layouts.field("multi_sample_count", "int32_t", 24, 4),
          Layouts.field("presentation_interval", "CNA_PresentInterval", 28, 4),
          Layouts.field("display_orientation", "CNA_DisplayOrientation", 32, 4),
          Layouts.field("render_target_usage", "CNA_RenderTargetUsage", 36, 4),
          Layouts.field("is_full_screen", "CNA_Bool", 40, 1),
          Layouts.field("headless_ext", "CNA_Bool", 41, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # The back-buffer readback window. One structure covers all three `GetBackBufferData`
      # overloads: `has_source_rectangle` false is the whole buffer, which is what the two
      # rectangle-free overloads pass.
      class BackBufferReadback < Structure
        layout size: 48, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("has_source_rectangle", "CNA_Bool", 8, 1),
          Layouts.field("source_rectangle", "CNA_Rectangle", 12, 16),
          Layouts.field("start_index", "uint64_t", 32, 8),
          Layouts.field("element_count", "uint64_t", 40, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # The two caller-provided descriptions a user-primitive draw takes. Both are versioned inputs
      # rather than outputs, so both fill their size and version in the constructor and the caller
      # writes the rest.
      class UserPrimitives < Structure
        layout size: 48, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("primitive_type", "CNA_PrimitiveType", 8, 4),
          Layouts.field("vertex_source", "CNA_UserVertexSource", 12, 4),
          Layouts.field("vertex_data", "void", 16, 8, pointer_depth: 1, const: true),
          Layouts.field("vertex_declaration", "CNA_VertexDeclarationHandle", 24, 8),
          Layouts.field("vertex_offset", "int32_t", 32, 4),
          Layouts.field("num_vertices", "int32_t", 36, 4),
          Layouts.field("primitive_count", "int32_t", 40, 4),
          Layouts.field("reserved", "uint32_t", 44, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class UserIndices < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("index_element_size", "CNA_IndexElementSize", 8, 4),
          Layouts.field("index_offset", "int32_t", 12, 4),
          Layouts.field("index_data", "void", 16, 8, pointer_depth: 1, const: true)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # The three render-target structures. `CNA_RenderTargetInfo` carries two more fields than the
      # retired 0.7.0 headers declare -- a two-byte `reserved` tail -- and neither is read here, so
      # the layout stops at `renderer_available` and both header roots agree on every field it does
      # declare.
      class RenderTarget2DCreateInfo < Structure
        layout size: 40, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("mip_map", "CNA_Bool", 16, 1),
          Layouts.field("format", "CNA_SurfaceFormat", 20, 4),
          Layouts.field("depth_format", "CNA_DepthFormat", 24, 4),
          Layouts.field("multi_sample_count", "int32_t", 28, 4),
          Layouts.field("usage", "CNA_RenderTargetUsage", 32, 4),
          Layouts.field("reserved1", "uint32_t", 36, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class RenderTargetCubeCreateInfo < Structure
        layout size: 32, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("size", "uint32_t", 8, 4),
          Layouts.field("mip_map", "CNA_Bool", 12, 1),
          Layouts.field("format", "CNA_SurfaceFormat", 16, 4),
          Layouts.field("depth_format", "CNA_DepthFormat", 20, 4),
          Layouts.field("multi_sample_count", "int32_t", 24, 4),
          Layouts.field("usage", "CNA_RenderTargetUsage", 28, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # What `cna_graphics_device_set_render_targets` takes. `array_slice` is a 3D/array-target
      # subresource this binding never sets: XNA's `RenderTargetBinding` carries a cube face and
      # nothing else, and a non-zero slice is refused by the route anyway.
      class RenderTargetBinding < Structure
        layout size: 24, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("render_target", "CNA_Handle", 8, 8),
          Layouts.field("array_slice", "int32_t", 16, 4),
          Layouts.field("cube_map_face", "CNA_CubeMapFace", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class RenderTargetInfo < Structure
        layout size: 44, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("kind", "CNA_RenderTargetKind", 8, 4),
          Layouts.field("width", "uint32_t", 12, 4), Layouts.field("height", "uint32_t", 16, 4),
          Layouts.field("level_count", "uint32_t", 20, 4),
          Layouts.field("format", "CNA_SurfaceFormat", 24, 4),
          Layouts.field("depth_format", "CNA_DepthFormat", 28, 4),
          Layouts.field("multi_sample_count", "int32_t", 32, 4),
          Layouts.field("usage", "CNA_RenderTargetUsage", 36, 4),
          Layouts.field("is_content_lost", "CNA_Bool", 40, 1),
          Layouts.field("renderer_available", "CNA_Bool", 41, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Texture3DCreateInfo < Structure
        layout size: 32, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("depth", "uint32_t", 16, 4),
          Layouts.field("mip_map", "CNA_Bool", 20, 1), Layouts.field("reserved0", "uint8_t", 21, 3),
          Layouts.field("format", "CNA_SurfaceFormat", 24, 4),
          Layouts.field("reserved1", "uint32_t", 28, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Texture3DInfo < Structure
        layout size: 32, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("depth", "uint32_t", 16, 4), Layouts.field("level_count", "uint32_t", 20, 4),
          Layouts.field("format", "CNA_SurfaceFormat", 24, 4),
          Layouts.field("reserved", "uint32_t", 28, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Texture3DTransfer < Structure
        layout size: 56, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("level", "int32_t", 8, 4),
          Layouts.field("left", "int32_t", 12, 4), Layouts.field("top", "int32_t", 16, 4),
          Layouts.field("right", "int32_t", 20, 4), Layouts.field("bottom", "int32_t", 24, 4),
          Layouts.field("front", "int32_t", 28, 4), Layouts.field("back", "int32_t", 32, 4),
          Layouts.field("reserved", "uint32_t", 36, 4),
          Layouts.field("start_index", "uint64_t", 40, 8), Layouts.field("element_count", "uint64_t", 48, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class TextureCubeCreateInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("size", "uint32_t", 8, 4),
          Layouts.field("mip_map", "CNA_Bool", 12, 1), Layouts.field("reserved0", "uint8_t", 13, 3),
          Layouts.field("format", "CNA_SurfaceFormat", 16, 4),
          Layouts.field("reserved1", "uint32_t", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class TextureCubeInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("size", "uint32_t", 8, 4), Layouts.field("level_count", "uint32_t", 12, 4),
          Layouts.field("format", "CNA_SurfaceFormat", 16, 4),
          Layouts.field("reserved", "uint32_t", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class TextureCubeTransfer < Structure
        layout size: 56, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("face", "CNA_CubeMapFace", 8, 4), Layouts.field("level", "int32_t", 12, 4),
          Layouts.field("has_rectangle", "CNA_Bool", 16, 1), Layouts.field("reserved0", "uint8_t", 17, 3),
          Layouts.field("rectangle", "CNA_Rectangle", 20, 16),
          Layouts.field("reserved1", "uint32_t", 36, 4),
          Layouts.field("start_index", "uint64_t", 40, 8), Layouts.field("element_count", "uint64_t", 48, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # The vertex- and index-buffer descriptors. Both `*Transfer` structures carry the element
      # identity, the streaming option and a caller-array window, which is the shape XNA's four
      # `SetData` overloads differ by.
      class VertexBufferCreateInfo < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("vertex_declaration", "CNA_VertexDeclarationHandle", 8, 8),
          Layouts.field("vertex_count", "int32_t", 16, 4),
          Layouts.field("buffer_usage", "CNA_BufferUsage", 20, 4),
          Layouts.field("dynamic", "CNA_Bool", 24, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class VertexBufferInfo < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("vertex_count", "int32_t", 8, 4),
          Layouts.field("buffer_usage", "CNA_BufferUsage", 12, 4),
          Layouts.field("dynamic", "CNA_Bool", 16, 1),
          Layouts.field("is_content_lost", "CNA_Bool", 17, 1),
          Layouts.field("has_renderer", "CNA_Bool", 18, 1),
          Layouts.field("vertex_stride", "int32_t", 20, 4),
          Layouts.field("vertex_element_count", "uint64_t", 24, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class VertexBufferTransfer < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("vertex_type", "CNA_VertexType", 8, 4),
          Layouts.field("options", "CNA_SetDataOptions", 12, 4),
          Layouts.field("start_index", "uint64_t", 16, 8),
          Layouts.field("element_count", "uint64_t", 24, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class VertexBufferBinding < Structure
        layout size: 16, alignment: 8, fields: [
          Layouts.field("vertex_buffer", "CNA_VertexBufferHandle", 0, 8),
          Layouts.field("vertex_offset", "int32_t", 8, 4),
          Layouts.field("instance_frequency", "int32_t", 12, 4)
        ]
      end

      class IndexBufferCreateInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("index_count", "int32_t", 8, 4),
          Layouts.field("index_element_size", "CNA_IndexElementSize", 12, 4),
          Layouts.field("buffer_usage", "CNA_BufferUsage", 16, 4),
          Layouts.field("dynamic", "CNA_Bool", 20, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class IndexBufferInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("index_count", "int32_t", 8, 4),
          Layouts.field("index_element_size", "CNA_IndexElementSize", 12, 4),
          Layouts.field("buffer_usage", "CNA_BufferUsage", 16, 4),
          Layouts.field("dynamic", "CNA_Bool", 20, 1),
          Layouts.field("is_content_lost", "CNA_Bool", 21, 1),
          Layouts.field("has_renderer", "CNA_Bool", 22, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class IndexBufferTransfer < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("index_element_size", "CNA_IndexElementSize", 8, 4),
          Layouts.field("options", "CNA_SetDataOptions", 12, 4),
          Layouts.field("start_index", "uint64_t", 16, 8),
          Layouts.field("element_count", "uint64_t", 24, 8)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Texture2DCreateInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("width", "uint32_t", 8, 4), Layouts.field("height", "uint32_t", 12, 4),
          Layouts.field("mip_map", "CNA_Bool", 16, 1), Layouts.field("reserved", "uint8_t", 17, 3),
          Layouts.field("format", "CNA_SurfaceFormat", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class SpriteFontInfo < Structure
        layout size: 32, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("character_count", "uint64_t", 8, 8),
          Layouts.field("line_spacing", "int32_t", 16, 4), Layouts.field("spacing", "float", 20, 4),
          Layouts.field("default_character", "CNA_Char16", 24, 2),
          Layouts.field("has_default_character", "CNA_Bool", 26, 1),
          Layouts.field("reserved", "uint8_t", 27, 5)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      # One `CNA_SpriteFontGlyph` per supported character, which is XNA's four parallel `List`s --
      # `glyphData`, `croppingData`, `characterMap` and `kerning` -- as a single array of records.
      # `MeasureString` needs the kerning triple and the cropping height, so the whole array is read
      # once when a font is produced rather than re-read per measurement.
      class SpriteFontGlyph < Structure
        layout size: 56, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("glyph_bounds", "CNA_Rectangle", 8, 16),
          Layouts.field("cropping", "CNA_Rectangle", 24, 16),
          Layouts.field("character", "CNA_Char16", 40, 2),
          Layouts.field("reserved", "uint16_t", 42, 2),
          Layouts.field("kerning", "CNA_Vector3", 44, 12)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class SoundEffectInstanceInfo < Structure
        layout size: 32, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("state", "CNA_SoundState", 8, 4), Layouts.field("is_looped", "CNA_Bool", 12, 1),
          Layouts.field("reserved0", "uint8_t", 13, 3),
          Layouts.field("volume", "float", 16, 4), Layouts.field("pitch", "float", 20, 4),
          Layouts.field("pan", "float", 24, 4), Layouts.field("reserved1", "uint32_t", 28, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class AudioListener < Structure
        layout size: 56, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("forward", "CNA_Vector3", 8, 12), Layouts.field("position", "CNA_Vector3", 20, 12),
          Layouts.field("up", "CNA_Vector3", 32, 12), Layouts.field("velocity", "CNA_Vector3", 44, 12)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class AudioEmitter < Structure
        layout size: 60, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("doppler_scale", "float", 8, 4),
          Layouts.field("forward", "CNA_Vector3", 12, 12), Layouts.field("position", "CNA_Vector3", 24, 12),
          Layouts.field("up", "CNA_Vector3", 36, 12), Layouts.field("velocity", "CNA_Vector3", 48, 12)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class SpriteBatchBeginInfo < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("sort_mode", "CNA_SpriteSortMode", 8, 4), Layouts.field("reserved", "uint32_t", 12, 4)
        ]

        def initialize(sort_mode)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u32(8, sort_mode)
        end
      end

      # `CNA_SpriteCommand` is the destination-rectangle half of XNA's `Draw`: the three overloads
      # that stretch a sprite into a rectangle rather than scaling it from a position, which is why
      # it carries no scale at all.
      class SpriteCommand < Structure
        layout size: 72, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("texture", "CNA_Handle", 8, 8), Layouts.field("destination", "CNA_Rectangle", 16, 16),
          Layouts.field("source", "CNA_Rectangle", 32, 16), Layouts.field("color", "CNA_Color", 48, 4),
          Layouts.field("rotation", "float", 52, 4), Layouts.field("origin", "CNA_Vector2", 56, 8),
          Layouts.field("effects", "CNA_SpriteEffects", 64, 4), Layouts.field("layer_depth", "float", 68, 4)
        ]

        def initialize(texture:, destination:, source:, color:, rotation:, origin:, effects:, layer_depth:)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u64(8, texture)
          write_i32(16, destination.X); write_i32(20, destination.Y)
          write_i32(24, destination.Width); write_i32(28, destination.Height)
          write_i32(32, source&.X || 0); write_i32(36, source&.Y || 0)
          write_i32(40, source&.Width || 0); write_i32(44, source&.Height || 0)
          write_u8(48, color.R); write_u8(49, color.G); write_u8(50, color.B); write_u8(51, color.A)
          write_f32(52, rotation)
          write_f32(56, origin.X); write_f32(60, origin.Y)
          write_u32(64, effects)
          write_f32(68, layer_depth)
        end
      end

      class SpriteScaledCommand < Structure
        layout size: 72, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("texture", "CNA_Handle", 8, 8), Layouts.field("position", "CNA_Vector2", 16, 8),
          Layouts.field("source", "CNA_Rectangle", 24, 16), Layouts.field("color", "CNA_Color", 40, 4),
          Layouts.field("rotation", "float", 44, 4), Layouts.field("origin", "CNA_Vector2", 48, 8),
          Layouts.field("scale", "CNA_Vector2", 56, 8), Layouts.field("effects", "CNA_SpriteEffects", 64, 4),
          Layouts.field("layer_depth", "float", 68, 4)
        ]

        def initialize(texture:, position:, source:, color:, rotation:, origin:, scale:, effects:, layer_depth:)
          super()
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u64(8, texture)
          write_f32(16, position.X); write_f32(20, position.Y)
          write_i32(24, source&.X || 0); write_i32(28, source&.Y || 0)
          write_i32(32, source&.Width || 0); write_i32(36, source&.Height || 0)
          write_u8(40, color.R); write_u8(41, color.G); write_u8(42, color.B); write_u8(43, color.A)
          write_f32(44, rotation)
          write_f32(48, origin.X); write_f32(52, origin.Y)
          write_f32(56, scale.X); write_f32(60, scale.Y)
          write_u32(64, effects)
          write_f32(68, layer_depth)
        end
      end

      # `CNA_SpriteTextCommand` is what XNA's six `DrawString` overloads reduce to once the two
      # `StringBuilder` forms collapse into their `String` twins and the uniform-scale forms widen
      # their `Single` into both components of a `Vector2`.
      class SpriteTextCommand < Structure
        layout size: 72, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("sprite_font", "CNA_Handle", 8, 8), Layouts.field("text", "CNA_StringView", 16, 16),
          Layouts.field("position", "CNA_Vector2", 32, 8), Layouts.field("color", "CNA_Color", 40, 4),
          Layouts.field("rotation", "float", 44, 4), Layouts.field("origin", "CNA_Vector2", 48, 8),
          Layouts.field("scale", "CNA_Vector2", 56, 8), Layouts.field("effects", "CNA_SpriteEffects", 64, 4),
          Layouts.field("layer_depth", "float", 68, 4)
        ]

        def initialize(sprite_font:, text:, position:, color:, rotation:, origin:, scale:, effects:, layer_depth:)
          super()
          @text = StringView.new(text)
          write_u32(0, self.class.size)
          write_u32(4, 1)
          write_u64(8, sprite_font)
          write_u64(16, @text.read_u64(0)); write_u64(24, @text.read_u64(8))
          write_f32(32, position.X); write_f32(36, position.Y)
          write_u8(40, color.R); write_u8(41, color.G); write_u8(42, color.B); write_u8(43, color.A)
          write_f32(44, rotation)
          write_f32(48, origin.X); write_f32(52, origin.Y)
          write_f32(56, scale.X); write_f32(60, scale.Y)
          write_u32(64, effects)
          write_f32(68, layer_depth)
        end
      end

      class KeyboardState < Structure
        layout size: 40, alignment: 8, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("pressed_key_words", "uint64_t[4]", 8, 32)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class MouseState < Structure
        layout size: 32, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("x", "int32_t", 8, 4),
          Layouts.field("y", "int32_t", 12, 4),
          Layouts.field("scroll_wheel", "int32_t", 16, 4),
          Layouts.field("horizontal_scroll_wheel", "int32_t", 20, 4),
          Layouts.field("pressed_buttons", "CNA_MouseButtonFlags", 24, 4),
          Layouts.field("reserved", "uint32_t", 28, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class Vector2 < Structure
        layout size: 8, alignment: 4, fields: [
          Layouts.field("x", "float", 0, 4),
          Layouts.field("y", "float", 4, 4)
        ]
      end

      # The three remaining math values the effect-parameter routes carry by pointer, and the
      # sixteen-float row-major matrix whose field order is XNA's own M11..M44.
      class Vector3 < Structure
        layout size: 12, alignment: 4, fields: [
          Layouts.field("x", "float", 0, 4),
          Layouts.field("y", "float", 4, 4),
          Layouts.field("z", "float", 8, 4)
        ]
      end

      class Vector4 < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("x", "float", 0, 4),
          Layouts.field("y", "float", 4, 4),
          Layouts.field("z", "float", 8, 4),
          Layouts.field("w", "float", 12, 4)
        ]
      end

      class Quaternion < Structure
        layout size: 16, alignment: 4, fields: [
          Layouts.field("x", "float", 0, 4),
          Layouts.field("y", "float", 4, 4),
          Layouts.field("z", "float", 8, 4),
          Layouts.field("w", "float", 12, 4)
        ]
      end

      class Matrix < Structure
        layout size: 64, alignment: 4, fields: (1..4).flat_map { |row|
          (1..4).map { |column| Layouts.field("m#{row}#{column}", "float", ((row - 1) * 4 + column - 1) * 4, 4) }
        }
      end

      class Color < Structure
        layout size: 4, alignment: 1, fields: [
          Layouts.field("r", "uint8_t", 0, 1), Layouts.field("g", "uint8_t", 1, 1),
          Layouts.field("b", "uint8_t", 2, 1), Layouts.field("a", "uint8_t", 3, 1)
        ]
      end

      # `CNA_EffectParameterInfo` and `CNA_EffectAnnotationInfo` are the immutable metadata both
      # types' properties read: a class, a storage type, and a row/column count.
      class EffectParameterInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("row_count", "int32_t", 8, 4), Layouts.field("column_count", "int32_t", 12, 4),
          Layouts.field("parameter_class", "CNA_EffectParameterClass", 16, 4),
          Layouts.field("parameter_type", "CNA_EffectParameterType", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class EffectAnnotationInfo < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4), Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("row_count", "int32_t", 8, 4), Layouts.field("column_count", "int32_t", 12, 4),
          Layouts.field("parameter_class", "CNA_EffectParameterClass", 16, 4),
          Layouts.field("parameter_type", "CNA_EffectParameterType", 20, 4)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class GamePadAnalogState < Structure
        layout size: 24, alignment: 4, fields: [
          Layouts.field("left_thumb_stick", "CNA_Vector2", 0, 8),
          Layouts.field("right_thumb_stick", "CNA_Vector2", 8, 8),
          Layouts.field("left_trigger", "float", 16, 4),
          Layouts.field("right_trigger", "float", 20, 4)
        ]
      end

      class GamePadState < Structure
        layout size: 48, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("is_connected", "CNA_Bool", 8, 1),
          Layouts.field("reserved0", "uint8_t[3]", 9, 3),
          Layouts.field("packet_number", "int32_t", 12, 4),
          Layouts.field("pressed_buttons", "CNA_GamePadButtonFlags", 16, 4),
          Layouts.field("reserved1", "uint32_t", 20, 4),
          Layouts.field("analog", "CNA_GamePadAnalogState", 24, 24)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      class GamePadCapabilities < Structure
        layout size: 48, alignment: 4, fields: [
          Layouts.field("struct_size", "uint32_t", 0, 4),
          Layouts.field("struct_version", "uint32_t", 4, 4),
          Layouts.field("gamepad_type", "CNA_GamePadType", 8, 4),
          Layouts.field("is_connected", "CNA_Bool", 12, 1),
          Layouts.field("has_a_button", "CNA_Bool", 13, 1),
          Layouts.field("has_b_button", "CNA_Bool", 14, 1),
          Layouts.field("has_x_button", "CNA_Bool", 15, 1),
          Layouts.field("has_y_button", "CNA_Bool", 16, 1),
          Layouts.field("has_back_button", "CNA_Bool", 17, 1),
          Layouts.field("has_start_button", "CNA_Bool", 18, 1),
          Layouts.field("has_big_button", "CNA_Bool", 19, 1),
          Layouts.field("has_dpad_up_button", "CNA_Bool", 20, 1),
          Layouts.field("has_dpad_down_button", "CNA_Bool", 21, 1),
          Layouts.field("has_dpad_left_button", "CNA_Bool", 22, 1),
          Layouts.field("has_dpad_right_button", "CNA_Bool", 23, 1),
          Layouts.field("has_left_shoulder_button", "CNA_Bool", 24, 1),
          Layouts.field("has_right_shoulder_button", "CNA_Bool", 25, 1),
          Layouts.field("has_left_stick_button", "CNA_Bool", 26, 1),
          Layouts.field("has_right_stick_button", "CNA_Bool", 27, 1),
          Layouts.field("has_left_x_thumb_stick", "CNA_Bool", 28, 1),
          Layouts.field("has_left_y_thumb_stick", "CNA_Bool", 29, 1),
          Layouts.field("has_right_x_thumb_stick", "CNA_Bool", 30, 1),
          Layouts.field("has_right_y_thumb_stick", "CNA_Bool", 31, 1),
          Layouts.field("has_left_trigger", "CNA_Bool", 32, 1),
          Layouts.field("has_right_trigger", "CNA_Bool", 33, 1),
          Layouts.field("has_left_vibration_motor", "CNA_Bool", 34, 1),
          Layouts.field("has_right_vibration_motor", "CNA_Bool", 35, 1),
          Layouts.field("has_voice_support", "CNA_Bool", 36, 1),
          Layouts.field("has_light_bar_ext", "CNA_Bool", 37, 1),
          Layouts.field("has_trigger_vibration_motors_ext", "CNA_Bool", 38, 1),
          Layouts.field("has_misc1_ext", "CNA_Bool", 39, 1),
          Layouts.field("has_paddle1_ext", "CNA_Bool", 40, 1),
          Layouts.field("has_paddle2_ext", "CNA_Bool", 41, 1),
          Layouts.field("has_paddle3_ext", "CNA_Bool", 42, 1),
          Layouts.field("has_paddle4_ext", "CNA_Bool", 43, 1),
          Layouts.field("has_touchpad_ext", "CNA_Bool", 44, 1),
          Layouts.field("has_gyro_ext", "CNA_Bool", 45, 1),
          Layouts.field("has_accelerometer_ext", "CNA_Bool", 46, 1),
          Layouts.field("reserved", "uint8_t[1]", 47, 1)
        ]

        def initialize
          super
          write_u32(0, self.class.size)
          write_u32(4, 1)
        end
      end

      STRUCTURES = constants(false).filter_map do |name|
        value = const_get(name)
        value if value.is_a?(Class) && value < Structure
      end.freeze

      def self.verify_host!
        raise CNA::NativeLoadError, "Foundation 1 requires a 64-bit Fiddle host" unless Fiddle::SIZEOF_VOIDP == 8
      end
    end
  end
end
