# frozen_string_literal: true

require_relative "../framework"
require_relative "graphics/packed_vector"
require_relative "graphics/vertex_element"

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

        class ClearOptions < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Target" => 1,
            "DepthBuffer" => 2,
            "Stencil" => 4
          }, flags: true)
        end

        class DepthFormat < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "None" => 0,
            "Depth16" => 1,
            "Depth24" => 2,
            "Depth24Stencil8" => 3
          })
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

        class GraphicsDeviceStatus < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Normal" => 0,
            "Lost" => 1,
            "NotReset" => 2
          })
        end

        class GraphicsProfile < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Reach" => 0,
            "HiDef" => 1
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

          def Project(source, projection, view, world)
            require_projection_inputs(source, projection, view, world)
            matrix = viewport_matrix_multiply(world, view)
            matrix = viewport_matrix_multiply(matrix, projection)
            result = viewport_transform(source, matrix)
            w = homogeneous_w(source, matrix)
            result = viewport_divide(result, w) unless within_epsilon?(w, 1.0)
            result.X = stack32(:+, stack(:*, stack(:*, stack(:+, result.X, 1.0), 0.5), N.f32(@Width)), N.f32(@X))
            result.Y = stack32(:+, stack(:*, stack(:*, stack(:+, stack_neg(result.Y), 1.0), 0.5), N.f32(@Height)), N.f32(@Y))
            result.Z = stack32(:+, stack(:*, result.Z, stack(:-, @MaxDepth, @MinDepth)), @MinDepth)
            result
          end

          def Unproject(source, projection, view, world)
            require_projection_inputs(source, projection, view, world)
            matrix = viewport_matrix_multiply(world, view)
            matrix = viewport_matrix_multiply(matrix, projection)
            matrix = viewport_matrix_invert(matrix)

            normalized = Vector3.new(source.X, source.Y, source.Z)
            normalized.X = stack32(:-, stack(:*, stack(:/, stack(:-, normalized.X, N.f32(@X)), N.f32(@Width)), 2.0), 1.0)
            normalized.Y = stack32(stack_neg(stack(:-, stack(:*, stack(:/, stack(:-, normalized.Y, N.f32(@Y)), N.f32(@Height)), 2.0), 1.0)))
            normalized.Z = stack32(:/, stack(:-, normalized.Z, @MinDepth), stack(:-, @MaxDepth, @MinDepth))

            result = viewport_transform(normalized, matrix)
            w = homogeneous_w(normalized, matrix)
            within_epsilon?(w, 1.0) ? result : viewport_divide(result, w)
          end

          def TitleSafeArea = Rectangle.new(@X, @Y, @Width, @Height)

          def ToString = "{X:#{@X} Y:#{@Y} Width:#{@Width} Height:#{@Height} MinDepth:#{format("%g", @MinDepth)} MaxDepth:#{format("%g", @MaxDepth)}}"
          alias to_s ToString

          def self.from_native(value)
            result = new(value.read_i32(0), value.read_i32(4), value.read_i32(8), value.read_i32(12))
            result.MinDepth = value.read_f32(16); result.MaxDepth = value.read_f32(20)
            result
          end

          private

          def require_projection_inputs(source, projection, view, world)
            CNA::Runtime::GeometrySupport.require_type(source, Vector3, "source")
            CNA::Runtime::GeometrySupport.require_type(projection, Matrix, "projection")
            CNA::Runtime::GeometrySupport.require_type(view, Matrix, "view")
            CNA::Runtime::GeometrySupport.require_type(world, Matrix, "world")
          end

          def homogeneous_w(source, matrix)
            stack_sum(stack(:*, source.X, matrix.M14), stack(:*, source.Y, matrix.M24),
                      stack(:*, source.Z, matrix.M34), matrix.M44)
          end

          def within_epsilon?(a, b)
            difference = N.sub32(stack32(a), b)
            epsilon = N.f32_from_bits(1)
            difference >= N.neg32(epsilon) && difference <= epsilon
          end

          # XNA's x86 CLR keeps evaluation-stack values at its native floating
          # precision and narrows these chains only when the IL stores a
          # Matrix/Vector3 field. The qualified public Matrix/Vector3 methods
          # intentionally retain the binding's established strict Single
          # projection, so Viewport uses its exact IL storage grouping here.
          def viewport_matrix_multiply(left, right)
            Matrix.new(*(1..4).flat_map do |row|
              (1..4).map do |column|
                stack32(stack_sum(*(1..4).map do |index|
                  stack(:*, left.public_send("M#{row}#{index}"), right.public_send("M#{index}#{column}"))
                end))
              end
            end)
          end

          def viewport_transform(value, matrix)
            Vector3.new(
              stack32(stack_sum(stack(:*, value.X, matrix.M11), stack(:*, value.Y, matrix.M21),
                                stack(:*, value.Z, matrix.M31), matrix.M41)),
              stack32(stack_sum(stack(:*, value.X, matrix.M12), stack(:*, value.Y, matrix.M22),
                                stack(:*, value.Z, matrix.M32), matrix.M42)),
              stack32(stack_sum(stack(:*, value.X, matrix.M13), stack(:*, value.Y, matrix.M23),
                                stack(:*, value.Z, matrix.M33), matrix.M43))
            )
          end

          def viewport_divide(value, divider)
            reciprocal = stack(:/, 1.0, divider)
            Vector3.new(stack32(:*, value.X, reciprocal), stack32(:*, value.Y, reciprocal),
                        stack32(:*, value.Z, reciprocal))
          end

          def viewport_matrix_invert(matrix)
            n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14, n15, n16 =
              (1..4).flat_map { |row| (1..4).map { |column| matrix.public_send("M#{row}#{column}") } }
            n17 = N.f32(n11 * n16 - n12 * n15); n18 = N.f32(n10 * n16 - n12 * n14)
            n19 = N.f32(n10 * n15 - n11 * n14); n20 = N.f32(n9 * n16 - n12 * n13)
            n21 = N.f32(n9 * n15 - n11 * n13); n22 = N.f32(n9 * n14 - n10 * n13)
            n23 = N.f32(n6 * n17 - n7 * n18 + n8 * n19)
            n24 = N.f32(-(n5 * n17 - n7 * n20 + n8 * n21))
            n25 = N.f32(n5 * n18 - n6 * n20 + n8 * n22)
            n26 = N.f32(-(n5 * n19 - n6 * n21 + n7 * n22))
            n27 = stack(:/, 1.0, stack_sum(stack(:*, n1, n23), stack(:*, n2, n24),
                                           stack(:*, n3, n25), stack(:*, n4, n26)))
            result = Array.new(16, 0.0)
            result[0] = stack32(:*, n23, n27); result[4] = stack32(:*, n24, n27)
            result[8] = stack32(:*, n25, n27); result[12] = stack32(:*, n26, n27)
            result[1] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n2, n17), stack(:*, n3, n18)), stack(:*, n4, n19))), n27)
            result[5] = stack32(:*, stack(:+, stack(:-, stack(:*, n1, n17), stack(:*, n3, n20)), stack(:*, n4, n21)), n27)
            result[9] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n1, n18), stack(:*, n2, n20)), stack(:*, n4, n22))), n27)
            result[13] = stack32(:*, stack(:+, stack(:-, stack(:*, n1, n19), stack(:*, n2, n21)), stack(:*, n3, n22)), n27)
            n28 = N.f32(n7 * n16 - n8 * n15); n29 = N.f32(n6 * n16 - n8 * n14)
            n30 = N.f32(n6 * n15 - n7 * n14); n31 = N.f32(n5 * n16 - n8 * n13)
            n32 = N.f32(n5 * n15 - n7 * n13); n33 = N.f32(n5 * n14 - n6 * n13)
            result[2] = stack32(:*, stack(:+, stack(:-, stack(:*, n2, n28), stack(:*, n3, n29)), stack(:*, n4, n30)), n27)
            result[6] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n1, n28), stack(:*, n3, n31)), stack(:*, n4, n32))), n27)
            result[10] = stack32(:*, stack(:+, stack(:-, stack(:*, n1, n29), stack(:*, n2, n31)), stack(:*, n4, n33)), n27)
            result[14] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n1, n30), stack(:*, n2, n32)), stack(:*, n3, n33))), n27)
            n34 = N.f32(n7 * n12 - n8 * n11); n35 = N.f32(n6 * n12 - n8 * n10)
            n36 = N.f32(n6 * n11 - n7 * n10); n37 = N.f32(n5 * n12 - n8 * n9)
            n38 = N.f32(n5 * n11 - n7 * n9); n39 = N.f32(n5 * n10 - n6 * n9)
            result[3] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n2, n34), stack(:*, n3, n35)), stack(:*, n4, n36))), n27)
            result[7] = stack32(:*, stack(:+, stack(:-, stack(:*, n1, n34), stack(:*, n3, n37)), stack(:*, n4, n38)), n27)
            result[11] = stack32(:*, stack_neg(stack(:+, stack(:-, stack(:*, n1, n35), stack(:*, n2, n37)), stack(:*, n4, n39))), n27)
            result[15] = stack32(:*, stack(:+, stack(:-, stack(:*, n1, n36), stack(:*, n2, n38)), stack(:*, n3, n39)), n27)
            Matrix.new(*result)
          end

          def stack(*arguments)
            return extended_value(arguments[0]) if arguments.length == 1

            operation, left, right = arguments
            left = extended_value(left); right = extended_value(right)
            if left.instance_of?(Rational) && right.instance_of?(Rational) && !(operation == :/ && right.zero?)
              value = case operation
                      when :+ then left + right
                      when :- then left - right
                      when :* then left * right
                      when :/ then left / right
                      else raise ArgumentError, "unknown floating-stack operation"
                      end
              return round_extended(value)
            end

            left = left.to_f; right = right.to_f
            case operation
            when :+ then left + right
            when :- then left - right
            when :* then left * right
            when :/ then left / right
            else raise ArgumentError, "unknown floating-stack operation"
            end
          end

          def stack_sum(*values)
            values.drop(1).reduce(extended_value(values.first)) { |sum, value| stack(:+, sum, value) }
          end

          def stack_neg(value)
            value = extended_value(value)
            value.instance_of?(Rational) ? -value : -value.to_f
          end

          def stack32(*arguments)
            value = arguments.length == 1 ? extended_value(arguments[0]) : stack(*arguments)
            N.f32(value.to_f)
          end

          def extended_value(value)
            return value if value.instance_of?(Rational)

            number = N.f32(value)
            number.finite? ? number.to_r : number
          end

          def round_extended(value)
            return value if value.zero?

            negative = value.negative?
            magnitude = value.abs
            numerator = magnitude.numerator
            denominator = magnitude.denominator
            exponent = numerator.bit_length - denominator.bit_length
            exponent -= 1 if exponent >= 0 ? numerator < (denominator << exponent) : (numerator << -exponent) < denominator
            shift = 63 - exponent
            scaled_numerator = shift >= 0 ? numerator << shift : numerator
            scaled_denominator = shift >= 0 ? denominator : denominator << -shift
            significand, remainder = scaled_numerator.divmod(scaled_denominator)
            comparison = remainder * 2 <=> scaled_denominator
            significand += 1 if comparison.positive? || (comparison.zero? && significand.odd?)
            if significand == (1 << 64)
              significand >>= 1
              exponent += 1
            end
            result = if exponent >= 63
                       Rational(significand << (exponent - 63), 1)
                     else
                       Rational(significand, 1 << (63 - exponent))
                     end
            negative ? -result : result
          end

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
