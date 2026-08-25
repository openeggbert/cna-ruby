# frozen_string_literal: true

require_relative "../framework"
require_relative "graphics/packed_vector"
require_relative "graphics/vertex_element"

module Microsoft
  module Xna
    module Framework
      module Graphics
        # The three Graphics exception types. Each declares nothing but the standard trio of
        # constructors, every one of which the pinned XNA IL shows forwarding straight to
        # System.Exception. Nothing in this binding ever raises them: device loss, device reset and
        # adapter selection all remain deferred.
        class DeviceLostException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

        class DeviceNotResetException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

        class NoSuitableGraphicsDeviceException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

        # Three XNA classes whose only constructor is internal: a consumer can never build one, and
        # the framework member that would produce one — GraphicsAdapter for DisplayMode,
        # GraphicsDevice.ResourceCreated/ResourceDestroyed for the two EventArgs types — is still
        # deferred. Each therefore projects with `new` made private, exactly as GraphicsResource and
        # Texture already do, so the public non-constructibility is part of the contract and a
        # future producer has the internal path the CLR gives it. No producer is fabricated.
        #
        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        class DisplayMode
          N = CNA::Runtime::Numeric
          private_constant :N

          attr_reader :Width, :Height, :Format

          # `assembly .ctor(int32 width, int32 height, SurfaceFormat format)`: three stores, no
          # validation. Reachable only as DisplayMode.__send__(:new, width, height, format).
          def initialize(width, height, format)
            @Width = N.int32(width, "width")
            @Height = N.int32(height, "height")
            @Format = SurfaceFormat.coerce(format)
          end
          private_class_method :new

          # `brfalse` on height then `brtrue` on width: a zero in either answers 0, and otherwise
          # both are converted to Single and divided in Single.
          def AspectRatio
            return N.f32(0.0) if @Height.zero? || @Width.zero?

            N.div32(N.f32(@Width), N.f32(@Height))
          end

          # Viewport::GetTitleSafeArea(x, y, w, h) is `new Rectangle(x, y, w, h)`, called with
          # (0, 0, width, height).
          def TitleSafeArea = Rectangle.new(0, 0, @Width, @Height)

          def ToString
            "{Width:#{@Width} Height:#{@Height} Format:#{@Format} " \
              "AspectRatio:#{N.single_string(self.AspectRatio)}}"
          end

          alias to_s ToString
        end

        # `assembly .ctor(List<DisplayMode> displayModes)`: base() then one store. The backing list
        # is private and the public surface cannot mutate it, so the CLR enumerator's version check
        # is unobservable and no version tracking is projected.
        # Like CurveKeyCollection it deliberately does not mix in Ruby Enumerable and exposes no
        # `each`: that would add a broad helper surface unrelated to XNA.
        class DisplayModeCollection
          def initialize(display_modes)
            unless display_modes.instance_of?(Array) &&
                   display_modes.all? { |mode| mode.instance_of?(DisplayMode) }
              raise TypeError, "displayModes must be an Array of DisplayMode"
            end

            @display_modes = display_modes.dup.freeze
          end
          private_class_method :new

          # IEnumerable`1 projects to a fresh Ruby Enumerator, without a fake System namespace.
          def GetEnumerator = @display_modes.each

          # `Item[format]` walks the backing list in order, collects every mode whose Format equals
          # the argument into a new list, and answers that materialised sequence.
          def [](format)
            wanted = SurfaceFormat.coerce(format)
            @display_modes.select { |mode| mode.Format == wanted }.each
          end
        end

        # `assembly .ctor(object resource)`: base() then one store.
        class ResourceCreatedEventArgs < CNA::Runtime::EventArgs
          attr_reader :Resource

          def initialize(resource)
            super()
            @Resource = resource
          end
          private_class_method :new
        end

        # `assembly .ctor(string name, object tag)`: base(), then tag, then name.
        class ResourceDestroyedEventArgs < CNA::Runtime::EventArgs
          attr_reader :Name, :Tag

          def initialize(name, tag)
            super()
            @Tag = tag
            @Name = name
          end
          private_class_method :new
        end

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…). The
        # XNA type keeps every value in a nested internal Settings struct; each public property is a
        # single field read or write with **no validation of any kind**, so the only checks here are
        # this binding's ordinary CLR-type boundary checks.
        #
        # The constructor is `base()` followed by exactly one store — `set_IsFullScreen(true)`.
        # Every other field keeps its CLR default of zero, which is BackBufferWidth 0,
        # BackBufferHeight 0, SurfaceFormat.Color, DepthFormat.None, MultiSampleCount 0,
        # DisplayOrientation.Default, PresentInterval.Default, RenderTargetUsage.DiscardContents and
        # IntPtr.Zero. **IsFullScreen therefore defaults to true**, which is what the IL says.
        #
        # This is a managed descriptor and nothing more: it creates no GraphicsDevice, looks up no
        # native window, enumerates no adapter, builds no swap chain and presents nothing.
        class PresentationParameters
          N = CNA::Runtime::Numeric
          private_constant :N

          def initialize
            @BackBufferWidth = 0
            @BackBufferHeight = 0
            @BackBufferFormat = SurfaceFormat.coerce(0)
            @DepthStencilFormat = DepthFormat.coerce(0)
            @MultiSampleCount = 0
            @DisplayOrientation = Framework::DisplayOrientation.coerce(0)
            @PresentationInterval = PresentInterval.coerce(0)
            @RenderTargetUsage = Graphics::RenderTargetUsage.coerce(0)
            @DeviceWindowHandle = 0
            self.IsFullScreen = true
          end

          attr_reader :BackBufferWidth, :BackBufferHeight, :BackBufferFormat, :DepthStencilFormat,
                      :MultiSampleCount, :DisplayOrientation, :PresentationInterval,
                      :RenderTargetUsage, :DeviceWindowHandle, :IsFullScreen

          def BackBufferWidth=(value)
            @BackBufferWidth = N.int32(value, "BackBufferWidth")
          end

          def BackBufferHeight=(value)
            @BackBufferHeight = N.int32(value, "BackBufferHeight")
          end

          def BackBufferFormat=(value)
            @BackBufferFormat = SurfaceFormat.coerce(value)
          end

          def DepthStencilFormat=(value)
            @DepthStencilFormat = DepthFormat.coerce(value)
          end

          def MultiSampleCount=(value)
            @MultiSampleCount = N.int32(value, "MultiSampleCount")
          end

          def DisplayOrientation=(value)
            @DisplayOrientation = Framework::DisplayOrientation.coerce(value)
          end

          def PresentationInterval=(value)
            @PresentationInterval = PresentInterval.coerce(value)
          end

          def RenderTargetUsage=(value)
            @RenderTargetUsage = Graphics::RenderTargetUsage.coerce(value)
          end

          # System.IntPtr projects to a signed native-pointer-width Ruby Integer, and never to a
          # Fiddle::Pointer. Nothing dereferences, owns or closes this scalar.
          def DeviceWindowHandle=(value)
            @DeviceWindowHandle = N.intptr(value, "DeviceWindowHandle")
          end

          # The CLR stores this as an int32 that the setter normalises to 0 or 1 and the getter
          # reads back as `field != 0`, so the observable value is always exactly true or false.
          def IsFullScreen=(value)
            raise TypeError, "IsFullScreen must be true or false" unless value == true || value == false

            @IsFullScreen = value
          end

          def Bounds = Rectangle.new(0, 0, @BackBufferWidth, @BackBufferHeight)

          # `newobj PresentationParameters()` then one whole-struct copy of settings, so the clone's
          # constructor default for IsFullScreen is overwritten along with everything else.
          def Clone
            copy = self.class.new
            SETTINGS.each { |name| copy.__send__(:"#{name}=", __send__(name)) }
            copy
          end

          SETTINGS = %i[BackBufferWidth BackBufferHeight BackBufferFormat DepthStencilFormat
                        MultiSampleCount DisplayOrientation PresentationInterval RenderTargetUsage
                        DeviceWindowHandle IsFullScreen].freeze
          private_constant :SETTINGS
        end

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

        class PrimitiveType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "TriangleList" => 0,
            "TriangleStrip" => 1,
            "LineList" => 2,
            "LineStrip" => 3
          })
        end

        class CubeMapFace < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "PositiveX" => 0,
            "NegativeX" => 1,
            "PositiveY" => 2,
            "NegativeY" => 3,
            "PositiveZ" => 4,
            "NegativeZ" => 5
          })
        end

        class BufferUsage < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "None" => 0,
            "WriteOnly" => 1
          }, flags: true)
        end

        class FillMode < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Solid" => 0,
            "WireFrame" => 1
          })
        end

        class IndexElementSize < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "SixteenBits" => 0,
            "ThirtyTwoBits" => 1
          })
        end

        class CullMode < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "None" => 0,
            "CullClockwiseFace" => 1,
            "CullCounterClockwiseFace" => 2
          })
        end

        class RenderTargetUsage < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "DiscardContents" => 0,
            "PreserveContents" => 1,
            "PlatformContents" => 2
          })
        end

        class SetDataOptions < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "None" => 0,
            "Discard" => 1,
            "NoOverwrite" => 2
          }, flags: true)
        end

        class TextureAddressMode < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Wrap" => 0,
            "Clamp" => 1,
            "Mirror" => 2
          })
        end

        # XNA declares One = 0 and Zero = 1; the names do not mirror the raw values.
        # Abstract effect contracts. No Effect, BasicEffect or shader type exists in this
        # foundation; these are the declared XNA interface members and nothing more.
        module IEffectMatrices
          def World = raise(NotImplementedError, "IEffectMatrices#World")
          def World=(_value)
            raise NotImplementedError, "IEffectMatrices#World="
          end
          def View = raise(NotImplementedError, "IEffectMatrices#View")
          def View=(_value)
            raise NotImplementedError, "IEffectMatrices#View="
          end
          def Projection = raise(NotImplementedError, "IEffectMatrices#Projection")
          def Projection=(_value)
            raise NotImplementedError, "IEffectMatrices#Projection="
          end
        end

        module IEffectFog
          def FogEnabled = raise(NotImplementedError, "IEffectFog#FogEnabled")
          def FogEnabled=(_value)
            raise NotImplementedError, "IEffectFog#FogEnabled="
          end
          def FogStart = raise(NotImplementedError, "IEffectFog#FogStart")
          def FogStart=(_value)
            raise NotImplementedError, "IEffectFog#FogStart="
          end
          def FogEnd = raise(NotImplementedError, "IEffectFog#FogEnd")
          def FogEnd=(_value)
            raise NotImplementedError, "IEffectFog#FogEnd="
          end
          def FogColor = raise(NotImplementedError, "IEffectFog#FogColor")
          def FogColor=(_value)
            raise NotImplementedError, "IEffectFog#FogColor="
          end
        end

        class Blend < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "One" => 0, "Zero" => 1, "SourceColor" => 2, "InverseSourceColor" => 3,
            "SourceAlpha" => 4, "InverseSourceAlpha" => 5, "DestinationColor" => 6,
            "InverseDestinationColor" => 7, "DestinationAlpha" => 8,
            "InverseDestinationAlpha" => 9, "BlendFactor" => 10,
            "InverseBlendFactor" => 11, "SourceAlphaSaturation" => 12
          })
        end

        class BlendFunction < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Add" => 0,
            "Subtract" => 1,
            "ReverseSubtract" => 2,
            "Min" => 3,
            "Max" => 4
          })
        end

        class ColorWriteChannels < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "None" => 0, "Red" => 1, "Green" => 2, "Blue" => 4, "Alpha" => 8, "All" => 15
          }, flags: true)
        end

        class CompareFunction < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Always" => 0, "Never" => 1, "Less" => 2, "LessEqual" => 3,
            "Equal" => 4, "GreaterEqual" => 5, "Greater" => 6, "NotEqual" => 7
          })
        end

        class EffectParameterClass < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Scalar" => 0,
            "Vector" => 1,
            "Matrix" => 2,
            "Object" => 3,
            "Struct" => 4
          })
        end

        class EffectParameterType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Void" => 0, "Bool" => 1, "Int32" => 2, "Single" => 3, "String" => 4,
            "Texture" => 5, "Texture1D" => 6, "Texture2D" => 7, "Texture3D" => 8,
            "TextureCube" => 9
          })
        end

        class PresentInterval < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Default" => 0,
            "One" => 1,
            "Two" => 2,
            "Immediate" => 3
          })
        end

        class StencilOperation < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Keep" => 0, "Zero" => 1, "Replace" => 2, "Increment" => 3,
            "Decrement" => 4, "IncrementSaturation" => 5,
            "DecrementSaturation" => 6, "Invert" => 7
          })
        end

        class TextureFilter < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Linear" => 0, "Point" => 1, "Anisotropic" => 2, "LinearMipPoint" => 3,
            "PointMipLinear" => 4, "MinLinearMagPointMipLinear" => 5,
            "MinLinearMagPointMipPoint" => 6, "MinPointMagLinearMipLinear" => 7,
            "MinPointMagLinearMipPoint" => 8
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
