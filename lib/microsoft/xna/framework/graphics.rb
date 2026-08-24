# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      module Graphics
        class SpriteSortMode < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({ "Deferred" => 0, "Immediate" => 1, "Texture" => 2, "BackToFront" => 3, "FrontToBack" => 4 })
        end

        class SpriteEffects < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({ "None" => 0, "FlipHorizontally" => 1, "FlipVertically" => 2 }, flags: true)
        end

        class SurfaceFormat < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Color" => 0, "Bgr565" => 1, "Bgra5551" => 2, "Bgra4444" => 3,
            "Dxt1" => 4, "Dxt3" => 5, "Dxt5" => 6, "NormalizedByte2" => 7,
            "NormalizedByte4" => 8, "Rgba1010102" => 9, "Rg32" => 10,
            "Rgba64" => 11, "Alpha8" => 12, "Single" => 13, "Vector2" => 14,
            "Vector4" => 15, "HalfSingle" => 16, "HalfVector2" => 17,
            "HalfVector4" => 18, "HdrBlendable" => 19
          })
        end

        class Viewport
          include CNA::Runtime::ValueSemantics
          N = CNA::Runtime::Numeric
          private_constant :N
          attr_reader :X, :Y, :Width, :Height, :MinDepth, :MaxDepth

          def initialize(*arguments)
            values = if arguments.length == 1 && arguments[0].instance_of?(Rectangle)
                       [arguments[0].X, arguments[0].Y, arguments[0].Width, arguments[0].Height]
                     elsif arguments.length == 4
                       arguments
                     else
                       raise ArgumentError, "Viewport.new expects Rectangle or (x, y, width, height)"
                     end
            self.X, self.Y, self.Width, self.Height = values
            self.MinDepth = 0.0; self.MaxDepth = 1.0
          end

          def X=(value)
            @X = N.int32(value, "X")
          end

          def Y=(value)
            @Y = N.int32(value, "Y")
          end

          def Width=(value)
            @Width = N.int32(value, "Width")
          end

          def Height=(value)
            @Height = N.int32(value, "Height")
          end

          def MinDepth=(value)
            @MinDepth = N.f32(value)
          end

          def MaxDepth=(value)
            @MaxDepth = N.f32(value)
          end
          def Bounds = Rectangle.new(@X, @Y, @Width, @Height)

          def Bounds=(value)
            raise TypeError, "Bounds expects Rectangle" unless value.instance_of?(Rectangle)
            self.X = value.X; self.Y = value.Y; self.Width = value.Width; self.Height = value.Height
          end

          def AspectRatio = @Width.zero? || @Height.zero? ? 0.0 : N.f32(@Width.fdiv(@Height))

          def ToString = "{X:#{@X} Y:#{@Y} Width:#{@Width} Height:#{@Height} MinDepth:#{format("%g", @MinDepth)} MaxDepth:#{format("%g", @MaxDepth)}}"
          alias to_s ToString

          def self.from_native(value)
            result = new(value.read_i32(0), value.read_i32(4), value.read_i32(8), value.read_i32(12))
            result.MinDepth = value.read_f32(16); result.MaxDepth = value.read_f32(20)
            result
          end

          private

          def value_components = [@X, @Y, @Width, @Height, @MinDepth, @MaxDepth]
        end

        class GraphicsDevice
          private_class_method :new

          def initialize(game)
            @game = game
            @callback_handle = 0
            @invalidated = false
          end

          def IsDisposed = @invalidated || @game.__send__(:disposed?)

          def Viewport
            output = CNA::Native::Layouts::Viewport.new
            CNA::Native.library.call("cna_graphics_device_get_viewport", native_handle, output.pointer)
            Viewport.from_native(output)
          end

          def Clear(color)
            raise TypeError, "GraphicsDevice.Clear foundation overload expects Color" unless color.instance_of?(Color)
            divisor = 255.0
            CNA::Native.library.call(
              "cna_graphics_device_clear_rgba", native_handle,
              color.R.fdiv(divisor), color.G.fdiv(divisor), color.B.fdiv(divisor), color.A.fdiv(divisor)
            )
            nil
          end

          private

          def invalidate
            @invalidated = true
            @callback_handle = 0
            nil
          end

          def enter_callback(handle) = @callback_handle = handle
          def leave_callback = @callback_handle = 0

          def native_handle
            raise CNA::DisposedObjectError, "GraphicsDevice is disposed" if self.IsDisposed
            raise CNA::InvalidBindingStateError, "GraphicsDevice native access is valid only inside a CNA lifecycle callback" if @callback_handle.zero?
            @callback_handle
          end
        end

        class GraphicsResource
          include CNA::Runtime::NativeResource
          private_class_method :new
          attr_reader :GraphicsDevice
          attr_accessor :Name, :Tag

          def initialize_resource(device, handle, release)
            @GraphicsDevice = device
            @Name = nil
            @Tag = nil
            initialize_native_resource(device.__send__(:game), handle, release)
          end
          private :initialize_resource

          def ToString = @Name.nil? || @Name.empty? ? self.class.name.split("::").last : @Name
        end

        class Texture < GraphicsResource
          attr_reader :LevelCount, :Format
          private_class_method :new
        end

        class Texture2D < Texture
          attr_reader :Width, :Height, :Bounds

          class << self
            def FromStream(graphics_device, stream, *arguments)
              raise TypeError, "graphics_device must be GraphicsDevice" unless graphics_device.instance_of?(GraphicsDevice)
              raise TypeError, "stream must respond to read" unless stream.respond_to?(:read)
              raise ArgumentError, "Foundation FromStream supports the XNA two-argument overload" unless arguments.empty?
              bytes = stream.read
              raise TypeError, "stream.read must return String" unless bytes.instance_of?(String)
              raise ArgumentError, "encoded image stream is empty" if bytes.empty?

              encoded = Fiddle::Pointer[bytes.b]
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call(
                "cna_texture2d_create_from_encoded_memory",
                graphics_device.__send__(:native_handle), encoded, bytes.bytesize, 0, output
              )
              handle = output[0, 8].unpack1("Q")
              allocate.__send__(:initialize_from_native, graphics_device, handle)
            end

            private :new
          end

          private

          def initialize_from_native(device, handle)
            release = lambda { |value| CNA::Native.library.call("cna_texture2d_destroy", value) }
            initialize_resource(device, handle, release)
            info = CNA::Native::Layouts::Texture2DInfo.new
            CNA::Native.library.call("cna_texture2d_get_info", native_handle, info.pointer)
            @Width = info.read_u32(8)
            @Height = info.read_u32(12)
            @LevelCount = info.read_u32(16)
            @Format = info.read_u32(20)
            @Format = SurfaceFormat.coerce(@Format)
            @Bounds = Rectangle.new(0, 0, @Width, @Height)
            self
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            else
              release&.call(handle)
            end
            raise
          end
        end

        class SpriteBatch < GraphicsResource
          public_class_method :new

          def initialize(graphics_device)
            raise TypeError, "SpriteBatch.new expects GraphicsDevice" unless graphics_device.instance_of?(GraphicsDevice)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_sprite_batch_create", graphics_device.__send__(:native_handle), output)
            release = lambda { |value| CNA::Native.library.call("cna_sprite_batch_destroy", value) }
            initialize_resource(graphics_device, output[0, 8].unpack1("Q"), release)
            @begun = false
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            else
              release&.call(output[0, 8].unpack1("Q"))
            end
            raise
          end

          def Begin(*arguments)
            raise CNA::InvalidBindingStateError, "SpriteBatch.Begin cannot be nested" if @begun
            sort_mode = arguments.empty? ? SpriteSortMode::Deferred : nil
            raise ArgumentError, "Foundation SpriteBatch.Begin exposes only the real zero-argument overload" unless sort_mode
            info = CNA::Native::Layouts::SpriteBatchBeginInfo.new(sort_mode.to_i)
            CNA::Native.library.call("cna_sprite_batch_begin", native_handle, info.pointer)
            @begun = true
            nil
          end

          def Draw(*arguments)
            raise CNA::InvalidBindingStateError, "SpriteBatch.Draw requires Begin" unless @begun
            raise ArgumentError, "no implemented Foundation SpriteBatch.Draw overload matches" unless [3, 4, 9].include?(arguments.length)
            texture, position = arguments[0], arguments[1]
            raise TypeError, "texture must be Texture2D" unless texture.instance_of?(Texture2D)
            raise TypeError, "position must be Vector2" unless position.instance_of?(Vector2)

            if arguments.length == 3
              source = nil; color = arguments[2]; rotation = 0.0; origin = Vector2.Zero
              scale = Vector2.One; effects = SpriteEffects::None; depth = 0.0
            elsif arguments.length == 4
              source, color = arguments[2], arguments[3]; rotation = 0.0; origin = Vector2.Zero
              scale = Vector2.One; effects = SpriteEffects::None; depth = 0.0
            else
              source, color, rotation, origin, scale, effects, depth = arguments[2..]
              scale = Vector2.new(scale) if scale.instance_of?(Integer) || scale.instance_of?(Float)
            end
            raise TypeError, "sourceRectangle must be Rectangle or nil" unless source.nil? || source.instance_of?(Rectangle)
            raise TypeError, "color must be Color" unless color.instance_of?(Color)
            raise TypeError, "origin and scale must be Vector2" unless origin.instance_of?(Vector2) && scale.instance_of?(Vector2)
            effect_value = SpriteEffects.coerce(effects).to_i
            numeric = [position.X, position.Y, rotation, origin.X, origin.Y, scale.X, scale.Y, depth]
            raise RangeError, "SpriteBatch transforms must be finite" unless numeric.all? { |value| Float(value).finite? }

            command = CNA::Native::Layouts::SpriteScaledCommand.new(
              texture: texture.__send__(:native_handle), position: position, source: source, color: color,
              rotation: CNA::Runtime::Numeric.f32(rotation), origin: origin, scale: scale,
              effects: effect_value, layer_depth: CNA::Runtime::Numeric.f32(depth)
            )
            CNA::Native.library.call("cna_sprite_batch_submit_scaled_many", native_handle, command.pointer, 1)
            nil
          end

          def End
            raise CNA::InvalidBindingStateError, "SpriteBatch.End requires Begin" unless @begun
            CNA::Native.library.call("cna_sprite_batch_end", native_handle)
            @begun = false
            nil
          ensure
            @begun = false
          end

          private

          def prepare_native_dispose
            @begun = false
            nil
          end
        end
      end

      class GraphicsDeviceManager
        DefaultBackBufferWidth = 800
        DefaultBackBufferHeight = 480
        attr_reader :GraphicsDevice

        def initialize(game)
          raise TypeError, "GraphicsDeviceManager.new expects Game" unless game.is_a?(Game)
          @game = game
          @GraphicsDevice = Graphics::GraphicsDevice.__send__(:new, game)
          @native_handle = nil
          @disposed = false
          game.__send__(:attach_graphics_manager, self)
        end

        private

        def create_native(game_handle)
          output = CNA::Native.library.pointer_for("Q", 0)
          CNA::Native.library.call("cna_graphics_device_manager_create", game_handle, output)
          handle = output[0, 8].unpack1("Q")
          @native_handle = CNA::Runtime::NativeHandle.new(
            handle: handle, ownership: CNA::Runtime::Ownership::OWNED,
            generation: @game.__send__(:generation), parent: @game,
            release: lambda do |value|
              CNA::Native.library.call("cna_graphics_device_manager_dispose", value)
              CNA::Native.library.call("cna_graphics_device_manager_destroy", value)
            end
          )
        rescue Exception
          if handle && (!defined?(@native_handle) || !@native_handle)
            CNA::Native.library.call("cna_graphics_device_manager_dispose", handle)
            CNA::Native.library.call("cna_graphics_device_manager_destroy", handle)
          end
          raise
        end

        def begin_native_callback
          return unless @native_handle
          output = CNA::Native.library.pointer_for("Q", 0)
          result = CNA::Native.library.function("cna_graphics_device_manager_get_graphics_device").call(@native_handle.value, output)
          if result.zero?
            @GraphicsDevice.__send__(:enter_callback, output[0, 8].unpack1("Q"))
          elsif result != 3
            CNA::Native.library.check(result, "cna_graphics_device_manager_get_graphics_device")
          end
        end

        def end_native_callback = @GraphicsDevice.__send__(:leave_callback)

        def dispose_native
          return if @disposed
          @native_handle&.dispose
          @GraphicsDevice.__send__(:invalidate)
          @disposed = true
        end
      end
    end
  end
end

class Microsoft::Xna::Framework::Graphics::GraphicsDevice
  private
  attr_reader :game
end
