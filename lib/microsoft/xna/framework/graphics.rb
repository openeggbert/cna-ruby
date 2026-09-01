# frozen_string_literal: true

require_relative "../framework"
require_relative "content"
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

        # The graphics-device service contract, derived from the pinned
        # Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…): one read-only property and
        # four events, every one of them `EventHandler`1<EventArgs>`. The interface declares no
        # base and no other interface, and every member is `public hidebysig newslot specialname
        # abstract virtual`, so nothing here has a body to project.
        #
        # This is an abstract contract and nothing more. It is the type `DrawableGameComponent`
        # asks `Game.Services` for, but declaring the identity registers no producer: no object in
        # this binding provides the service, `Game.Services` holds no key for it, and none of the
        # four events is ever raised. The reader raises NotImplementedError exactly as every other
        # interface member does — an interface declares an event identity and never owns an
        # invocation list.
        #
        # Its single type dependency is `GraphicsDevice`, one of the deferred partial runtime
        # types, and the member-level dependency graph records that this interface reaches *no
        # member* of it: naming a type in a return position is not a call. That is what makes the
        # contract projectable while its dependency stays partial.
        #
        # Members are declared in metadata order, which for the four events is the `.event`
        # declaration order of the pinned IL rather than alphabetical order.
        module IGraphicsDeviceService
          extend CNA::Runtime::EventOwner

          def GraphicsDevice = raise(NotImplementedError, "IGraphicsDeviceService#GraphicsDevice")
          xna_abstract_event :DeviceDisposing, "IGraphicsDeviceService#DeviceDisposing"
          xna_abstract_event :DeviceReset, "IGraphicsDeviceService#DeviceReset"
          xna_abstract_event :DeviceResetting, "IGraphicsDeviceService#DeviceResetting"
          xna_abstract_event :DeviceCreated, "IGraphicsDeviceService#DeviceCreated"
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

          # `Textures` is `new TextureCollection(this, 0, profileCapabilities.MaxSamplers)` and
          # `VertexTextures` is `new TextureCollection(this, 0x101, ...MaxVertexSamplers)`. The
          # offsets are D3D9 sampler register bases -- 0 and `D3DVERTEXTEXTURESAMPLER0` -- and the
          # CNA analogue of choosing between them is `CNA_ShaderStage`, so the two collections
          # differ here by stage rather than by register base. Both getters are one `ldfld` over a
          # field the constructor fills, so each answers the **same object** every time.
          def Textures
            @textures ||= TextureCollection.__send__(:new, self, CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_PIXEL"))
          end

          def VertexTextures
            @vertex_textures ||= TextureCollection.__send__(:new, self, CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_VERTEX"))
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

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # `.class public auto ansi sealed beforefieldinit` over three fields -- the parent device, a
        # D3D9 sampler register base and a slot count -- with one public identity: the `Item[Int32]`
        # indexer, get and set. The constructor is `assembly`, so `new` is private under Foundation
        # 25's rule and a consumer reaches one only through `GraphicsDevice.Textures` or
        # `.VertexTextures`.
        #
        # Native frontier 4 recorded this type as "the one case where NATIVE_RUNTIME was the right
        # word -- no CNA route at all". That was **wrong**, and not because the ABI moved:
        # `cna_graphics_device_get_texture` and `cna_graphics_device_set_texture` are exported by the
        # retired 0.7.0 artifact as well. It is the fourth frontier deferral this session to fail on
        # inspection, and the first that was simply mistaken rather than reasoned from a wrong
        # premise.
        #
        # ## Why the getter answers from a cache
        #
        # `cna_graphics_device_get_texture` answers a `CNA_TextureSlotInfo` whose `bound` flag says
        # whether *something* occupies the slot and whose `texture` handle is valid only when a C
        # caller created that texture. CNA's own header states why, and states the consequence for
        # exactly this projection:
        #
        # > There is deliberately no route from a native object back to a handle, here or anywhere
        # > else in this ABI. … The practical consequence, for a consumer whose own `Textures[i]`
        # > getter must return the object it set: cache what you bind and answer from the cache, and
        # > use `bound` to tell "something else owns this slot now" from "the slot is empty".
        #
        # So the getter answers the Ruby `Texture` this collection bound, and the native slot is
        # consulted for the one case a cache cannot cover.
        #
        # DEVIATION, recorded: a slot filled by canonical CNA code -- a `SpriteBatch` flush, for
        # instance -- reads back as `nil` here where XNA would answer the texture the device holds.
        # That case is **detectable** rather than silent, because `bound` is true while the cache is
        # empty, and `slot_bound?` exposes exactly that to the tests. Answering a fabricated
        # `Texture` for a native object this binding never created would be the alternative.
        #
        # DEVIATION, recorded: `Length` is CNA's 16 for both stages. XNA's is
        # `ProfileCapabilities.MaxSamplers` and `MaxVertexSamplers`, which are profile-dependent --
        # a Reach device has **no** vertex samplers at all -- and this binding has `GraphicsProfile`
        # as a managed enum with no capability table behind it, so there is nothing measured to take
        # the number from.
        class TextureCollection
          MAX_TEXTURES = CNA::Native::Manifest::CONSTANTS.fetch("CNA_TEXTURE_COLLECTION_MAX_TEXTURES")

          private_class_method :new

          def initialize(device, stage)
            @device = device
            @stage = stage
            @bound = {}
          end

          # `if (index < 0 || index >= _maxTextures) throw new ArgumentOutOfRangeException("index")`,
          # after `Helpers.CheckDisposed(_parent, ...)`. An empty slot answers `ldnull`.
          def [](index)
            slot = validated(index)
            ensure_device!
            @bound[slot]
          end

          def []=(index, value)
            slot = validated(index)
            ensure_device!
            unless value.nil?
              raise TypeError, "value must be a Texture" unless value.is_a?(Texture)
              raise CNA::DisposedObjectError, "the texture is disposed" if value.IsDisposed
            end

            handle = value.nil? ? 0 : value.__send__(:native_handle)
            CNA::Native.library.call("cna_graphics_device_set_texture",
                                     @device.__send__(:native_handle), @stage, slot, handle)
            if value.nil?
              @bound.delete(slot)
            else
              @bound[slot] = value
            end
            value
          end

          private

          # `_maxTextures` is an `assembly` field and XNA publishes no `Length`, so neither does this.
          # It is reachable for the tests that pin the deviation and for nothing else.
          def length = MAX_TEXTURES

          # True when the device reports a texture in the slot, whoever put it there. It is the one
          # thing the managed cache cannot know, which is why it is measured rather than inferred.
          def slot_bound?(index)
            slot = validated(index)
            ensure_device!
            info = CNA::Native::Layouts::TextureSlotInfo.new
            CNA::Native.library.call("cna_graphics_device_get_texture",
                                     @device.__send__(:native_handle), @stage, slot, info.pointer)
            info.read_u8(8) == 1
          end

          def validated(index)
            slot = CNA::Runtime::Numeric.int32(index, "index")
            raise ::RangeError, "index" if slot.negative? || slot >= MAX_TEXTURES

            slot
          end

          def ensure_device!
            raise CNA::DisposedObjectError, "GraphicsDevice is disposed" if @device.IsDisposed
          end
        end

        class GraphicsResource
          include CNA::Runtime::NativeResource
          extend CNA::Runtime::EventOwner
          private_class_method :new
          attr_reader :GraphicsDevice
          attr_accessor :Name, :Tag

          # `Disposing` is raised by `Dispose(true)` and by nothing else -- not by the finalizer
          # path, and not twice.
          xna_event :Disposing

          def initialize_resource(device, handle, release)
            @GraphicsDevice = device
            @Name = nil
            @Tag = nil
            initialize_native_resource(device.__send__(:game), handle, release)
          end
          private :initialize_resource

          def ToString = @Name.nil? || @Name.empty? ? self.class.name.split("::").last : @Name

          # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…),
          # which is mixed-mode C++/CLI, so the disposal contract is spread over four methods:
          #
          #     void !GraphicsResource()          { isDisposed = true; }
          #     void ~GraphicsResource()          { if (isDisposed) return;
          #                                         !GraphicsResource();
          #                                         Disposing?.Invoke(this, EventArgs.Empty); }
          #     protected virtual void Dispose(bool disposing)
          #                                       { if (disposing) ~GraphicsResource();
          #                                         else !GraphicsResource(); }
          #     public void Dispose()             { Dispose(true); GC.SuppressFinalize(this); }
          #     protected override void Finalize(){ Dispose(false); }
          #
          # Two things a paraphrase loses. `isDisposed` is set **before** `Disposing` is raised, so a
          # handler observes `IsDisposed == true` -- and that is asserted rather than assumed. And
          # the finalizer path raises **nothing**: only an explicit `Dispose()` announces itself.
          #
          # Ruby cannot give one name two visibilities, so the public `Dispose()` and the protected
          # `Dispose(Boolean)` project to one method with a default argument, the rule `Game`,
          # `ContentManager` and every XACT type already follow.
          def Dispose(disposing = true)
            return if self.IsDisposed

            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty) if disposing
            nil
          end

          private

          # `Dispose(false)`, and no Ruby finalizer is registered for it: nothing in this binding is
          # released by the garbage collector, which is why the CLR's `GC.SuppressFinalize` needs no
          # analogue either.
          def Finalize
            self.Dispose(false)
            nil
          end
        end

        class Texture < GraphicsResource
          attr_reader :LevelCount, :Format
          private_class_method :new
        end

        class Texture2D < Texture
          attr_reader :Width, :Height, :Bounds

          # The element types both XNA's `T : struct` and CNA's `CNA_TextureDataType` model, each
          # with its identity and the byte width `sizeof(T)` answers. `System.Byte[]` projects to a
          # Ruby String, so `::String` stands for `byte` here.
          TEXTURE_DATA_TYPES = {
            Microsoft::Xna::Framework::Color => [0, 4],
            PackedVector::Bgr565 => [1, 2],
            PackedVector::Bgra5551 => [2, 2],
            PackedVector::Bgra4444 => [3, 2],
            ::String => [4, 1],
            PackedVector::NormalizedByte2 => [5, 2],
            PackedVector::NormalizedByte4 => [6, 4],
            PackedVector::Rgba1010102 => [7, 4],
            PackedVector::Rg32 => [8, 4],
            PackedVector::Rgba64 => [9, 8],
            PackedVector::Alpha8 => [10, 1]
          }.freeze

          # `Texture.GetExpectedByteSizeFromFormat`, for the formats this binding projects.
          FORMAT_BYTE_SIZES = { "Color" => 4, "Bgr565" => 2, "Bgra5551" => 2, "Bgra4444" => 2,
                                "Alpha8" => 1, "NormalizedByte2" => 2, "NormalizedByte4" => 4,
                                "Rgba1010102" => 4, "Rg32" => 4, "Rgba64" => 8 }.freeze

          class << self
            # Both XNA overloads forward to the same internal constructor: the two-argument form
            # preserves the source dimensions, and the five-argument form passes a requested size
            # and a `zoom` flag -- cover-and-crop when true, fit while preserving aspect ratio when
            # false. Ruby collapses them into one method dispatching on arity, and CNA carries the
            # difference in `CNA_Texture2DDecodeInfo`, whose null pointer *is* the two-argument case.
            #
            # The constructor's validation, in the IL's order: a null device is
            # `ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`, a null
            # stream `ArgumentNullException("stream", NullNotAllowed)`, an unreadable one
            # `ArgumentException(..., "stream")`, and then `ValidateCreationParameters` refuses a
            # non-positive size exactly as the two public constructors' does.
            def FromStream(graphics_device, stream, *arguments)
              raise ArgumentError, "graphicsDevice" if graphics_device.nil?
              raise TypeError, "graphics_device must be GraphicsDevice" unless graphics_device.instance_of?(GraphicsDevice)
              raise ArgumentError, "stream" if stream.nil?
              raise TypeError, "stream must respond to read" unless stream.respond_to?(:read)
              unless arguments.empty? || arguments.length == 3
                raise ArgumentError, "FromStream takes (device, stream) or (device, stream, width, height, zoom)"
              end

              decode = nil
              unless arguments.empty?
                width = CNA::Runtime::Numeric.int32(arguments[0], "width")
                height = CNA::Runtime::Numeric.int32(arguments[1], "height")
                zoom = arguments[2]
                raise ::RangeError, "width" unless width.positive?
                raise ::RangeError, "height" unless height.positive?
                raise TypeError, "zoom" unless zoom == true || zoom == false

                decode = CNA::Native::Layouts::Texture2DDecodeInfo.new
                decode.write_u32(8, width)
                decode.write_u32(12, height)
                decode.write_u8(16, zoom ? 1 : 0)
              end

              bytes = stream.read
              raise TypeError, "stream.read must return String" unless bytes.instance_of?(String)
              raise ArgumentError, "encoded image stream is empty" if bytes.empty?

              encoded = Fiddle::Pointer[bytes.b]
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call(
                "cna_texture2d_create_from_encoded_memory",
                graphics_device.__send__(:native_handle), encoded, bytes.bytesize,
                decode ? decode.pointer : 0, output
              )
              handle = output[0, 8].unpack1("Q")
              allocate.__send__(:initialize_from_native, graphics_device, handle)
            end

          end

          # XNA declares two **public** constructors, so `new` is public here -- unlike `Texture` and
          # `GraphicsResource`, whose constructors are `assembly` and whose `new` `GraphicsResource`
          # makes private for everything that inherits from it. `FromStream` and the content manager
          # remain the other two producers.
          public_class_method :new

          # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
          #
          #   Texture2D(GraphicsDevice g, int w, int h)
          #       => CreateTexture(g, w, h, false, false, true, SurfaceFormat.Color);
          #   Texture2D(GraphicsDevice g, int w, int h, bool mipMap, SurfaceFormat format)
          #       => CreateTexture(g, w, h, mipMap, false, true, format);
          #
          # Ruby has no overloading, so the two collapse into one method with defaults -- and the
          # defaults are the shorter overload's own fixed arguments rather than invented ones.
          #
          # `CreateTexture` begins
          # `if (graphicsDevice == null) throw new ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`
          # and `ValidateCreationParameters` then refuses a non-positive size with
          # `ArgumentOutOfRangeException` naming `"width"` or `"height"` and
          # `ResourceDimensionsMustBePositive`. Everything after that is a **profile capability**
          # check -- the maximum texture size the active `GraphicsProfile` allows -- which is a
          # device fact rather than a managed rule, so it is CNA's to refuse and not this
          # projection's to guess.
          #
          # DEVIATION, recorded: CNA's create route documents that "the initial bulk-transfer slice
          # supports `CNA_SURFACE_FORMAT_COLOR`", so any other `SurfaceFormat` is refused natively
          # where XNA would accept whatever the adapter supports. The refusal surfaces as
          # `CNA::NativeError`; no managed rule is invented to anticipate it.
          def initialize(graphicsDevice, width, height, mipMap = false, format = SurfaceFormat::Color)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            pixels_wide = CNA::Runtime::Numeric.int32(width, "width")
            pixels_high = CNA::Runtime::Numeric.int32(height, "height")
            raise ::RangeError, "width" unless pixels_wide.positive?
            raise ::RangeError, "height" unless pixels_high.positive?
            raise ::TypeError, "mipMap" unless mipMap == true || mipMap == false
            raise ::TypeError, "format" unless format.instance_of?(SurfaceFormat)

            create_info = CNA::Native::Layouts::Texture2DCreateInfo.new
            create_info.write_u32(8, pixels_wide)
            create_info.write_u32(12, pixels_high)
            create_info.write_u8(16, mipMap ? 1 : 0)
            create_info.write_u32(20, format.to_i)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_texture2d_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_native(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
          #
          # Both are one call into a private `SaveAsImage(stream, format, width, height)`, with the
          # format fixed -- `ldc.i4.0` for JPEG and `ldc.i4.2` for PNG -- and `SaveAsImage` validates
          # exactly three things:
          #
          #   1. `if (stream == null) throw new ArgumentNullException("stream", NullNotAllowed)`
          #   2. `if (!stream.CanWrite) throw new ArgumentException("stream")`
          #   3. a format that is neither of those two, which the two public members cannot produce
          #
          # There is **no width or height validation at all**: whatever the encoder makes of a zero
          # or negative size is the encoder's business, and this projection does not invent a rule
          # XNA does not have. The final failure path is a bare `InvalidOperationException`.
          #
          # The stream is accepted on the same terms `FromStream` accepts a reader: the projected
          # `CNA::Runtime::Stream`, or any Ruby object answering `write`. `CanWrite` is consulted
          # when the object has it, which is what XNA's check really is.
          def SaveAsPng(stream, width, height)
            save_as_image(stream, CNA::Native::Manifest::CONSTANTS.fetch("CNA_TEXTURE_IMAGE_FORMAT_PNG"),
                          width, height)
          end

          def SaveAsJpeg(stream, width, height)
            save_as_image(stream, CNA::Native::Manifest::CONSTANTS.fetch("CNA_TEXTURE_IMAGE_FORMAT_JPEG"),
                          width, height)
          end


          # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
          #
          # XNA declares three overloads of each, and all six are thin forwards into one 549-byte
          # `CopyData`. Ruby has no overloading and cannot dispatch on parameter *type*, so the three
          # collapse into one method that dispatches on **arity**, with the generic type argument
          # leading — the rule `ContentManager.Load` established for `!!0`:
          #
          #     SetData(type, data)
          #     SetData(type, data, startIndex, elementCount)
          #     SetData(type, level, rect, data, startIndex, elementCount)
          #
          # `CopyData` raises exactly three things of its own, and delegates the rest to four
          # helpers, every one of which is reproduced here:
          #
          #   * `Helpers.ValidateCopyParameters(startIndex, elementCount, data.Length)` -- a start
          #     index outside the array, or a start plus count past its end, or a non-positive
          #     count, each `ArgumentOutOfRangeException(MustBeValidIndex)`. Note it names
          #     **`"dataIndex"`** for the first, not the public parameter's `startIndex`.
          #   * `Texture.GetAndValidateSizes<T>` -- `ArgumentException(InvalidDataSize)` unless the
          #     element size equals the format's byte size or divides it exactly.
          #   * `Texture.GetAndValidateRect` -- `ArgumentException(InvalidRectangle, "rect")` for a
          #     negative origin, a non-positive extent, or a rectangle reaching past the level.
          #   * `Texture.ValidateTotalSize` -- `ArgumentException(InvalidTotalSize)` unless the
          #     elements exactly fill the region: `width * height * formatSize` for an uncompressed
          #     format, and the DXT block formula for a compressed one.
          #
          # DEVIATION, recorded: `CopyData`'s remaining `InvalidOperationException` --
          # `CannotUseFormatTypeAsManualParameter` -- is reached by asking the **adapter** whether
          # the element type is usable with the texture's format, through
          # `GraphicsDevice.Adapter.CurrentDisplayMode`. Every adapter value is fabricated on the
          # qualified artifact, which `docs/native-abi.md` records, so that check is *not*
          # reproduced from invented data: CNA's own `cna_texture2d_set_data` refuses a mismatched
          # data type and that refusal surfaces. The other `InvalidOperationException`,
          # `MustResolveRenderTarget`, is unreachable because no render target is projected.
          def SetData(type, *arguments)
            level, rect, data, start_index, element_count = transfer_arguments(type, arguments, "SetData")
            data_type, element_size = self.class.__send__(:texture_data_type, type)
            packed = self.class.__send__(:pack_elements, type, data, start_index, element_count, element_size)
            transfer = build_transfer(level, rect, 0, element_count, element_size)
            CNA::Native.library.call("cna_texture2d_set_data", native_handle, data_type,
                                     transfer.pointer, Fiddle::Pointer[packed], element_count)
            nil
          end

          def GetData(type, *arguments)
            level, rect, data, start_index, element_count = transfer_arguments(type, arguments, "GetData")
            data_type, element_size = self.class.__send__(:texture_data_type, type)
            buffer = Fiddle::Pointer.malloc(element_size * element_count, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            transfer = build_transfer(level, rect, 0, element_count, element_size)
            CNA::Native.library.call("cna_texture2d_get_data", native_handle, data_type,
                                     transfer.pointer, buffer, element_count, required)
            self.class.__send__(:unpack_elements, type, buffer, data, start_index,
                                required[0, 8].unpack1("Q"), element_size)
            nil
          end

          private

          # The arity dispatch, and every managed check `CopyData` and its four helpers make.
          def transfer_arguments(type, arguments, member)
            raise CNA::DisposedObjectError, "Texture2D is disposed" if self.IsDisposed
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)

            case arguments.length
            when 1 then level, rect, data = 0, nil, arguments[0]
            when 3 then level, rect, data = 0, nil, arguments[0]
            when 5 then level, rect, data = arguments[0], arguments[1], arguments[2]
            else
              raise ::ArgumentError, "#{member} takes (type, data), (type, data, startIndex, " \
                                     "elementCount) or (type, level, rect, data, startIndex, elementCount)"
            end
            raise ::ArgumentError, "data" if data.nil?

            _data_type, element_size = self.class.__send__(:texture_data_type, type)
            length = self.class.__send__(:element_length, type, data)
            start_index = arguments.length == 1 ? 0 : CNA::Runtime::Numeric.int32(arguments[-2], "startIndex")
            element_count = arguments.length == 1 ? length : CNA::Runtime::Numeric.int32(arguments[-1], "elementCount")

            # Helpers.ValidateCopyParameters, in its own order and with its own parameter names.
            if start_index.negative? || start_index > length
              raise ::RangeError, "dataIndex"
            end
            raise ::RangeError, "elementCount" if start_index + element_count > length
            raise ::RangeError, "elementCount" unless element_count.positive?

            level = CNA::Runtime::Numeric.int32(level, "level")
            format_size = self.class.__send__(:format_byte_size, self.Format)
            # Texture.GetAndValidateSizes
            unless element_size == format_size || (element_size < format_size && (format_size % element_size).zero?)
              raise ::ArgumentError, "invalid data size"
            end

            level_width = [self.Width >> level, 1].max
            level_height = [self.Height >> level, 1].max
            if rect
              raise ::TypeError, "rect must be a Rectangle" unless rect.instance_of?(Rectangle)
              # Texture.GetAndValidateRect
              if rect.X.negative? || rect.Width <= 0 || rect.Y.negative? || rect.Height <= 0 ||
                 rect.Left + rect.Width > level_width || rect.Top + rect.Height > level_height
                raise ::ArgumentError, "rect"
              end

              level_width = rect.Width
              level_height = rect.Height
            end
            # Texture.ValidateTotalSize -- the uncompressed branch; no DXT format is projected.
            unless element_count * element_size == level_width * level_height * format_size
              raise ::ArgumentError, "invalid total size"
            end

            [level, rect, data, start_index, element_count]
          end

          def build_transfer(level, rect, start_index, element_count, _element_size)
            transfer = CNA::Native::Layouts::Texture2DTransfer.new
            transfer.write_i32(8, level)
            transfer.write_u8(12, rect ? 1 : 0)
            if rect
              transfer.write_i32(16, rect.X)
              transfer.write_i32(20, rect.Y)
              transfer.write_i32(24, rect.Width)
              transfer.write_i32(28, rect.Height)
            end
            transfer.write_u64(32, start_index)
            transfer.write_u64(40, element_count)
            transfer
          end

          class << self
            private

            # The element types CNA models, each with its `CNA_TEXTURE_DATA_*` identity and the byte
            # width XNA's `sizeof(T)` would answer. `System.Byte[]` projects to a Ruby String, so
            # `String` stands for `byte` -- the decision `docs/stream-projection-design.md` records.
            def texture_data_type(type)
              entry = TEXTURE_DATA_TYPES[type]
              raise ::TypeError, "#{type} is not a texture element type" if entry.nil?

              entry
            end

            def format_byte_size(format)
              FORMAT_BYTE_SIZES.fetch(format.to_s) do
                raise ::ArgumentError, "no expected byte size for SurfaceFormat.#{format}"
              end
            end

            def element_length(type, data)
              if type == ::String
                raise ::TypeError, "data must be a String of bytes" unless data.is_a?(::String)

                data.bytesize
              else
                raise ::TypeError, "data must be an Array of #{type}" unless data.is_a?(::Array)

                data.length
              end
            end

            # Every projected element type answers `PackedValue`, so one path packs them all.
            def pack_elements(type, data, start_index, element_count, element_size)
              return data.byteslice(start_index, element_count).b if type == ::String

              format = { 1 => "C", 2 => "v", 4 => "V", 8 => "Q<" }.fetch(element_size)
              slice = data[start_index, element_count]
              slice.each do |value|
                raise ::TypeError, "data must be an Array of #{type}" unless value.instance_of?(type)
              end
              slice.map { |value| [value.PackedValue].pack(format) }.join
            end

            def unpack_elements(type, buffer, data, start_index, count, element_size)
              bytes = buffer[0, element_size * count]
              if type == ::String
                raise ::ArgumentError, "data must not be frozen" if data.frozen?

                data[start_index, count] = bytes
                return data
              end

              format = { 1 => "C", 2 => "v", 4 => "V", 8 => "Q<" }.fetch(element_size)
              bytes.unpack("#{format}#{count}").each_with_index do |packed, index|
                element = type.allocate
                element.PackedValue = packed
                data[start_index + index] = element
              end
              data
            end
          end

          private

          def save_as_image(stream, image_format, width, height)
            raise CNA::DisposedObjectError, "Texture2D is disposed" if self.IsDisposed
            raise ::ArgumentError, "stream" if stream.nil?
            raise ::TypeError, "stream must respond to write" unless stream.respond_to?(:write) ||
                                                                     stream.respond_to?(:Write)
            raise ::ArgumentError, "stream" if stream.respond_to?(:CanWrite) && !stream.CanWrite

            target_width = CNA::Runtime::Numeric.int32(width, "width")
            target_height = CNA::Runtime::Numeric.int32(height, "height")
            size = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_texture2d_get_encoded_byte_count", native_handle,
                                     image_format, target_width, target_height, size)
            bytes = size[0, 8].unpack1("Q")
            encoded = "".b
            if bytes.positive?
              buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
              written = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_texture2d_copy_encoded", native_handle, image_format,
                                       target_width, target_height, buffer, bytes, written)
              encoded = buffer[0, written[0, 8].unpack1("Q")]
            end
            if stream.respond_to?(:Write)
              stream.Write(encoded, 0, encoded.bytesize)
            else
              stream.write(encoded)
            end
            nil
          end

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
        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # Six identities over four parallel `List`s XNA fills from the XNB — `glyphData`,
        # `croppingData`, `characterMap` and `kerning` — which CNA answers as one array of
        # `CNA_SpriteFontGlyph` records. The whole array is read once when a font is produced, which
        # is what XNA does too: its lists are constructed by the content reader and never re-read.
        #
        # `SpriteFont` kept a `BCL_PROJECTION` blocker until three decisions were made for it:
        # `System.Char` is an Integer code unit, `Nullable`1` is `nil`-or-value, and
        # `System.Text.StringBuilder` is a Ruby String. `CNA::Runtime::BclProjection` records why.
        # Its second blocker was `NATIVE_RUNTIME`, and its il-only dependency was `SpriteBatch`,
        # which is complete — so unlike the other native-blocked candidates, this one really was
        # unblocked by a BCL decision.
        class SpriteFont
          include CNA::Runtime::NativeResource

          CLR_IDENTITY = "Microsoft.Xna.Framework.Graphics.SpriteFont"

          # `'\r'` is skipped outright and `'\n'` starts a line; both are IL literals -- `ldc.i4.s 13`
          # and `ldc.i4.s 10` -- compared against the raw code unit rather than against a platform
          # newline.
          CARRIAGE_RETURN = 13
          LINE_FEED = 10

          private_class_method :new

          # The constructor is `assembly`: a consumer reaches a font only through
          # `ContentManager.Load(SpriteFont, name)`, which is the producer this binding registers.
          # DEVIATION, recorded, and it is about ownership rather than behaviour. XNA's `SpriteFont`
          # is **not** `IDisposable`: the `ContentManager` records the `Texture2D` its reader built
          # and disposes that on `Unload`, leaving the font object alive with a dead atlas. CNA
          # hands back two owned handles and no projected `Texture2D`, so the font owns both and
          # releases both — which the manager triggers, because it records anything answering
          # `Dispose` and `CNA::Runtime::NativeResource` gives this type one. The widening is that a
          # consumer can call `font.Dispose`, which XNA does not offer; the safety is that a font
          # whose atlas is gone reports `IsDisposed` instead of being silently unusable.
          def initialize(game, handle, texture_handle)
            @texture_handle = texture_handle
            initialize_native_resource(game, handle, lambda { |value|
              CNA::Native.library.call("cna_sprite_font_destroy", value)
              unless texture_handle.zero?
                begin
                  CNA::Native.library.call("cna_texture2d_destroy", texture_handle)
                rescue CNA::Error
                  nil
                end
              end
            })
            read_glyphs
          end

          # `get_LineSpacing`/`set_LineSpacing` and `get_Spacing`/`set_Spacing` are bare field reads
          # and writes with **no validation at all** in XNA -- four instructions each.
          def LineSpacing = info.read_i32(16)

          def LineSpacing=(value)
            ensure_live!
            CNA::Native.library.call("cna_sprite_font_set_line_spacing", native_handle,
                                     CNA::Runtime::Numeric.int32(value, "value"))
            value
          end

          def Spacing = info.read_f32(20)

          # DEVIATION, recorded: XNA stores whatever it is given, including `NaN` and infinities;
          # `cna_sprite_font_set_spacing` documents "must be finite" and answers
          # `CNA_RESULT_INVALID_ARGUMENT` for a non-finite value. The refusal is CNA's and it
          # surfaces as `CNA::NativeError` rather than being hidden or reproduced managed-side,
          # because there is no managed rule to reproduce.
          def Spacing=(value)
            ensure_live!
            CNA::Native.library.call("cna_sprite_font_set_spacing", native_handle,
                                     CNA::Runtime::Numeric.f32(value))
            value
          end

          # `char?` -- so `nil` when the font has no fallback, and an Integer code unit when it does.
          def DefaultCharacter
            snapshot = info
            return nil if snapshot.read_u8(26).zero?

            snapshot.read_u16(24)
          end

          # `if (value.HasValue && !characterMap.Contains(value.Value)) throw new ArgumentException(...)`
          # -- so clearing it is always allowed, and setting one the font does not define is not.
          def DefaultCharacter=(value)
            ensure_live!
            if value.nil?
              CNA::Native.library.call("cna_sprite_font_set_default_character", native_handle, 0, 0)
              return nil
            end

            unit = CNA::Runtime::Numeric.int32(value, "value")
            raise ::TypeError, "value must be a UTF-16 code unit" unless unit.between?(0, 0xffff)
            raise ::ArgumentError, "character not in font: #{unit}" unless @characters.include?(unit)

            CNA::Native.library.call("cna_sprite_font_set_default_character", native_handle, 1, unit)
            value
          end

          # `get_Characters` wraps `characterMap` in a `ReadOnlyCollection<char>` the **first** time
          # it is asked and caches it, so every later call answers the same object.
          def Characters = @characters_collection ||= CNA::Runtime::ReadOnlyCollection.new(@characters)

          # `MeasureString(String)` and `MeasureString(StringBuilder)` differ only in which
          # `StringProxy` they build, and both begin
          # `if (text == null) throw new ArgumentNullException("text")`. Ruby collapses them, which
          # the `StringBuilder => String` decision makes exact rather than approximate.
          #
          # The arithmetic is `InternalMeasure`, reproduced instruction for instruction below.
          def MeasureString(text)
            ensure_live!
            raise ::ArgumentError, "text" if text.nil?
            raise ::TypeError, "text must be a String" unless text.is_a?(::String)

            internal_measure(text)
          end

          private

          # `InternalMeasure(ref StringProxy text)`:
          #
          #     if (text.Length == 0) return Vector2.Zero;
          #     result = Vector2.Zero; result.Y = lineSpacing;
          #     float pendingRight = 0f; float widest = 0f; int lineBreaks = 0; bool firstOnLine = true;
          #     for each code unit c:
          #       if (c == '\r') continue;
          #       if (c == '\n') {
          #         result.X += Max(pendingRight, 0f); pendingRight = 0f;
          #         widest = Max(result.X, widest);
          #         result = Vector2.Zero; result.Y = lineSpacing;
          #         firstOnLine = true; lineBreaks++; continue;
          #       }
          #       k = kerning[GetIndexForCharacter(c)];
          #       if (firstOnLine) k.X = Max(k.X, 0f); else result.X += spacing + pendingRight;
          #       result.X += k.X + k.Y;
          #       pendingRight = k.Z;
          #       result.Y = Max(result.Y, croppingData[GetIndexForCharacter(c)].Height);
          #       firstOnLine = false;
          #     result.X += Max(pendingRight, 0f);
          #     result.Y += lineBreaks * lineSpacing;
          #     result.X = Max(result.X, widest);
          #
          # Two details a paraphrase loses. The **first glyph on a line clamps its left bearing** to
          # zero instead of paying the spacing, which is why a leading `'j'` does not hang off the
          # left. And the height comes from the **cropping** rectangle, not the glyph bounds.
          def internal_measure(text)
            units = text.encode(Encoding::UTF_16LE).unpack("v*")
            return Vector2.new(0.0, 0.0) if units.empty?

            f32 = ->(value) { CNA::Runtime::Numeric.f32(value) }
            line_spacing = f32.call(self.LineSpacing)
            spacing = f32.call(self.Spacing)
            width = 0.0
            height = line_spacing
            widest = 0.0
            pending_right = 0.0
            line_breaks = 0
            first_on_line = true

            units.each do |unit|
              next if unit == CARRIAGE_RETURN

              if unit == LINE_FEED
                width = f32.call(width + [pending_right, 0.0].max)
                pending_right = 0.0
                widest = [width, widest].max
                width = 0.0
                height = line_spacing
                first_on_line = true
                line_breaks += 1
                next
              end

              index = index_for_character(unit)
              left, advance, right = @kerning[index]
              if first_on_line
                left = [left, 0.0].max
              else
                width = f32.call(width + f32.call(spacing + pending_right))
              end
              width = f32.call(width + f32.call(left + advance))
              pending_right = right
              height = [height, f32.call(@cropping_heights[index])].max
              first_on_line = false
            end

            width = f32.call(width + [pending_right, 0.0].max)
            height = f32.call(height + f32.call(line_breaks * self.LineSpacing))
            Vector2.new([width, widest].max, height)
          end

          # `GetIndexForCharacter` is a binary search over the sorted character map. On a miss it
          # falls back to `defaultCharacter` and recurses **once**; if there is no default, or the
          # default is the character that just missed, it raises
          # `ArgumentException(CharacterNotInFont, "character")`.
          def index_for_character(unit, retried: false)
            index = @characters.bsearch_index { |value| value >= unit }
            return index if index && @characters[index] == unit

            fallback = self.DefaultCharacter
            if !retried && fallback && fallback != unit
              return index_for_character(fallback, retried: true)
            end

            raise ::ArgumentError, "character not in font: #{unit}"
          end

          def info
            ensure_live!
            output = CNA::Native::Layouts::SpriteFontInfo.new
            CNA::Native.library.call("cna_sprite_font_get_info", native_handle, output.pointer)
            output
          end

          # XNA's four parallel lists, read once. The character map is what the binary search needs
          # sorted, and CNA answers it sorted because the XNB stores it that way -- which the test
          # asserts rather than assumes.
          def read_glyphs
            count = info.read_u64(8)
            @characters = []
            @kerning = []
            @cropping_heights = []
            @glyph_bounds = []
            return if count.zero?

            size = CNA::Native::Layouts::SpriteFontGlyph.size
            buffer = Fiddle::Pointer.malloc(size * count, Fiddle::RUBY_FREE)
            count.times { |index| buffer[index * size, 8] = [size, 1].pack("LL") }
            written = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_sprite_font_copy_glyphs", native_handle, buffer, count, written)
            written[0, 8].unpack1("Q").times do |index|
              record = buffer[index * size, size]
              @glyph_bounds << record[8, 16].unpack("l4")
              @cropping_heights << record[24, 16].unpack("l4")[3]
              @characters << record[40, 2].unpack1("v")
              @kerning << record[44, 12].unpack("e3")
            end
            @characters.freeze
          end

          # The atlas texture CNA hands back beside the font. XNA's `textureValue` is a private field
          # with no public reader, so this one has none either -- it is held because the font's own
          # destruction does not release it.
          def texture_handle = @texture_handle

          def ensure_live!
            raise CNA::DisposedObjectError, "SpriteFont is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
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
          initialize_preferences
          game.__send__(:attach_graphics_manager, self)
        end

        # ------------------------------------------------------------------ the preferred settings
        #
        # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
        #
        # Nine properties, and every one of them is a plain field in XNA: the getters are one
        # `ldfld` and the setters store the value and set `isDeviceDirty`. They are **preferences**,
        # not device state — `PreferredBackBufferWidth` is what the next device creation should
        # aim for, not what the current device has — which is why reading them back never consults
        # the device.
        #
        # So this projection keeps them in managed fields too, exactly as XNA does, and pushes all
        # nine into CNA's own manager when the native manager appears and again at `ApplyChanges`.
        # That is not a copy of state CNA owns: a consumer sets these **before** `Run`, when no
        # native manager exists yet, which is the whole reason XNA buffers them as well.
        #
        # The constructor's field initialisers run before `Object::.ctor()` and are, in IL order:
        # `synchronizeWithVerticalRetrace = true`, `depthStencilFormat = 2` (`Depth24`),
        # `backBufferWidth = DefaultBackBufferWidth`, `backBufferHeight = DefaultBackBufferHeight`.
        # Everything else takes its CLR zero — `isFullScreen` and `allowMultiSampling` false,
        # `backBufferFormat` `Color`, `supportedOrientations` `Default` — and `graphicsProfile` comes
        # from `ReadDefaultGraphicsProfile`, which reads the manifest resource
        # `"Microsoft.Xna.Framework.RuntimeProfile"` out of the *game's own assembly* and returns
        # `Reach` when it is absent or unrecognised. A Ruby program has no such resource, so the
        # default is always `Reach`, by the IL's own not-found branch rather than by assumption.
        def PreferredBackBufferWidth = @back_buffer_width
        def PreferredBackBufferHeight = @back_buffer_height
        def PreferredBackBufferFormat = @back_buffer_format
        def PreferredDepthStencilFormat = @depth_stencil_format
        def IsFullScreen = @is_full_screen
        def SynchronizeWithVerticalRetrace = @synchronize_with_vertical_retrace
        def PreferMultiSampling = @prefer_multi_sampling
        def SupportedOrientations = @supported_orientations
        def GraphicsProfile = @graphics_profile

        # The two dimension setters are the only ones that validate:
        # `if (value <= 0) throw new ArgumentOutOfRangeException("value", BackBufferDimMustBePositive)`,
        # and they also clear `useResizedBackBuffer`, so an explicit size wins over one the window
        # produced by being resized.
        def PreferredBackBufferWidth=(value)
          @back_buffer_width = validated_dimension(value)
          @use_resized_back_buffer = false
          @device_dirty = true
          value
        end

        def PreferredBackBufferHeight=(value)
          @back_buffer_height = validated_dimension(value)
          @use_resized_back_buffer = false
          @device_dirty = true
          value
        end

        # The other seven store and mark dirty, with **no validation at all** — an undeclared
        # enum value is refused by this binding's enum projection rather than by XNA.
        def PreferredBackBufferFormat=(value)
          @back_buffer_format = typed(value, Graphics::SurfaceFormat, "value")
          @device_dirty = true
          value
        end

        def PreferredDepthStencilFormat=(value)
          @depth_stencil_format = typed(value, Graphics::DepthFormat, "value")
          @device_dirty = true
          value
        end

        def IsFullScreen=(value)
          @is_full_screen = boolean(value)
          @device_dirty = true
          value
        end

        def SynchronizeWithVerticalRetrace=(value)
          @synchronize_with_vertical_retrace = boolean(value)
          @device_dirty = true
          value
        end

        def PreferMultiSampling=(value)
          @prefer_multi_sampling = boolean(value)
          @device_dirty = true
          value
        end

        def SupportedOrientations=(value)
          @supported_orientations = typed(value, Microsoft::Xna::Framework::DisplayOrientation, "value")
          @device_dirty = true
          value
        end

        def GraphicsProfile=(value)
          @graphics_profile = typed(value, Graphics::GraphicsProfile, "value")
          @device_dirty = true
          value
        end

        # `if (device != null && !isDeviceDirty) return; ChangeDevice(false);`
        #
        # DEVIATION, recorded: XNA's `ChangeDevice` **creates** the device when there is none, and
        # here device creation belongs to CNA's own manager -- the finding
        # `docs/graphics-device-service-producer-audit.md` reached. So before the host is up this
        # marks the settings pending and returns; they are pushed the moment the native manager
        # exists, which is the observable effect a consumer is after when they set a resolution and
        # then call `Run`.
        def ApplyChanges
          return if !@device_dirty && !@native_handle.nil?

          push_preferences
          @device_dirty = false
          nil
        end

        # `IsFullScreen = !IsFullScreen; ChangeDevice(false);` -- the property setter, so it marks
        # the device dirty on the way through, and then the same change `ApplyChanges` makes.
        def ToggleFullScreen
          self.IsFullScreen = !@is_full_screen
          self.ApplyChanges
          nil
        end

        private

        def initialize_preferences
          @synchronize_with_vertical_retrace = true
          @depth_stencil_format = Graphics::DepthFormat::Depth24
          @back_buffer_width = DefaultBackBufferWidth
          @back_buffer_height = DefaultBackBufferHeight
          @back_buffer_format = Graphics::SurfaceFormat::Color
          @is_full_screen = false
          @prefer_multi_sampling = false
          @supported_orientations = Microsoft::Xna::Framework::DisplayOrientation::Default
          @graphics_profile = Graphics::GraphicsProfile::Reach
          @device_dirty = false
        end

        def validated_dimension(value)
          number = CNA::Runtime::Numeric.int32(value, "value")
          raise ::RangeError, "value" unless number.positive?

          number
        end

        def typed(value, type, name)
          raise ::TypeError, name unless value.instance_of?(type)

          value
        end

        def boolean(value)
          raise ::TypeError, "value" unless value == true || value == false

          value
        end

        # The flush. Every one of the nine goes to CNA's own manager, then
        # `cna_graphics_device_manager_apply_changes` does what XNA's `ChangeDevice` does.
        def push_preferences
          return if @native_handle.nil? || @disposed

          handle = @native_handle.value
          library = CNA::Native.library
          library.call("cna_graphics_device_manager_set_preferred_back_buffer_width", handle, @back_buffer_width)
          library.call("cna_graphics_device_manager_set_preferred_back_buffer_height", handle, @back_buffer_height)
          library.call("cna_graphics_device_manager_set_preferred_back_buffer_format", handle, @back_buffer_format.to_i)
          library.call("cna_graphics_device_manager_set_preferred_depth_stencil_format", handle, @depth_stencil_format.to_i)
          library.call("cna_graphics_device_manager_set_is_full_screen", handle, @is_full_screen ? 1 : 0)
          library.call("cna_graphics_device_manager_set_synchronize_with_vertical_retrace", handle,
                       @synchronize_with_vertical_retrace ? 1 : 0)
          library.call("cna_graphics_device_manager_set_prefer_multi_sampling", handle, @prefer_multi_sampling ? 1 : 0)
          library.call("cna_graphics_device_manager_set_supported_orientations", handle, @supported_orientations.to_i)
          library.call("cna_graphics_device_manager_set_graphics_profile", handle, @graphics_profile.to_i)
          library.call("cna_graphics_device_manager_apply_changes", handle)
          nil
        end

        # What CNA's own manager reports, kept reachable so a test can assert that the flush really
        # landed rather than trusting that it did.
        def native_preferences
          handle = @native_handle.value
          library = CNA::Native.library
          read = lambda do |symbol, format, size|
            output = CNA::Native.library.pointer_for(format, 0)
            library.call(symbol, handle, output)
            output[0, size].unpack1(format)
          end
          { width: read.call("cna_graphics_device_manager_get_preferred_back_buffer_width", "l", 4),
            height: read.call("cna_graphics_device_manager_get_preferred_back_buffer_height", "l", 4),
            format: read.call("cna_graphics_device_manager_get_preferred_back_buffer_format", "L", 4),
            depth: read.call("cna_graphics_device_manager_get_preferred_depth_stencil_format", "L", 4),
            full_screen: read.call("cna_graphics_device_manager_get_is_full_screen", "C", 1),
            vsync: read.call("cna_graphics_device_manager_get_synchronize_with_vertical_retrace", "C", 1),
            multi_sampling: read.call("cna_graphics_device_manager_get_prefer_multi_sampling", "C", 1),
            orientations: read.call("cna_graphics_device_manager_get_supported_orientations", "L", 4),
            profile: read.call("cna_graphics_device_manager_get_graphics_profile", "L", 4) }
        end

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
          # Whatever the consumer set before `Run` is pushed now, which is the moment XNA's own
          # `ChangeDevice` would first have run.
          push_preferences
        rescue Exception
          if handle && (!defined?(@native_handle) || !@native_handle)
            CNA::Native.library.call("cna_graphics_device_manager_dispose", handle)
            CNA::Native.library.call("cna_graphics_device_manager_destroy", handle)
          end
          raise
        end

        # A disposed manager has no device to borrow, so it attaches none.
        #
        # This is reached during disposal, not only during a run: `Game#Dispose` releases the
        # manager before it destroys the host, because `cna_graphics_device_manager_create`
        # documents "release it before the game" and the runtime keeps the object alive until the
        # game is destroyed. Destroying the game then delivers one last `unload_content` callback,
        # and that callback arrives after the manager handle is already gone. Dereferencing it
        # there raised `CNA::DisposedObjectError` out of `Dispose` on every Game that owned a
        # manager and had actually run.
        #
        # Returning early is the truthful answer rather than a guard over a broken state: the
        # device wrapper has been invalidated by the same disposal, and attaching a handle to it
        # would resurrect it. It is also the behaviour this method already had for the live case
        # where CNA answers `CNA_RESULT_INVALID_STATE` -- documented as "outside a lifecycle
        # callback **or when no device exists**" -- which is exactly the situation a disposed
        # manager is in.
        def begin_native_callback
          return if @native_handle.nil? || @native_handle.disposed?
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

# The one supported `ContentManager.Load<T>` materializer.
#
# It lives here rather than in `content.rb` because `Texture2D` is declared here and `content.rb`
# is loaded first; registering from the owning type keeps the registry one entry per asset type
# with no forward reference. `Graphics::Texture2D` is the only `T` this binding supports because it
# is the only XNA asset type this binding projects at all.
#
# `cna_content_manager_load_texture2d` hands back a **new independently owned** Texture2D per call,
# documented to survive `cna_content_manager_unload` and to be destroyed before the parent game. So
# the wrapper takes ordinary OWNED ownership, and `ContentManager.Unload` disposing its cache is
# what releases it -- which is exactly what XNA's `disposableAssets` list does.
Microsoft::Xna::Framework::Content::ContentManager.__send__(
  :register_materializer, Microsoft::Xna::Framework::Graphics::Texture2D
) do |manager, asset_name|
  handle = manager.__send__(:native_handle)
  device = manager.__send__(:graphics_device)
  view = CNA::Native::Layouts::StringView.new(asset_name.b)
  output = CNA::Native.library.pointer_for("Q", 0)
  begin
    CNA::Native.library.call("cna_content_manager_load_texture2d", handle,
                             view.read_u64(0), view.read_u64(8), output)
  rescue CNA::NativeError => error
    # CNA answers CNA_RESULT_IO for a missing or malformed asset and CNA_RESULT_NOT_SUPPORTED when
    # the active renderer cannot represent the loaded format. XNA reports both as
    # ContentLoadException, which is the identity a consumer catches.
    raise Microsoft::Xna::Framework::Content::ContentLoadException,
          "#{asset_name} could not be loaded as Texture2D: #{error.message}"
  end
  texture_handle = output[0, 8].unpack1("Q")
  if texture_handle.zero?
    raise Microsoft::Xna::Framework::Content::ContentLoadException,
          "#{asset_name} reported a successful load with no texture"
  end
  Microsoft::Xna::Framework::Graphics::Texture2D.allocate
                                                .__send__(:initialize_from_native, device, texture_handle)
end

# `ContentManager.Load(SpriteFont, name)` is the one producer XNA gives a consumer, and
# `cna_content_manager_load_sprite_font` is its canonical route. It answers **two** owned handles:
# the font, and the atlas texture behind it — the font's own destruction does not release the
# texture, so the font holds it. XNA's `textureValue` is a private field with no public reader, so
# nothing here exposes one either.
Microsoft::Xna::Framework::Content::ContentManager.__send__(
  :register_materializer, Microsoft::Xna::Framework::Graphics::SpriteFont
) do |manager, asset_name|
  handle = manager.__send__(:native_handle)
  view = CNA::Native::Layouts::StringView.new(asset_name.b)
  font = CNA::Native.library.pointer_for("Q", 0)
  texture = CNA::Native.library.pointer_for("Q", 0)
  begin
    CNA::Native.library.call("cna_content_manager_load_sprite_font", handle,
                             view.read_u64(0), view.read_u64(8), font, texture)
  rescue CNA::NativeError => error
    raise Microsoft::Xna::Framework::Content::ContentLoadException,
          "#{asset_name} could not be loaded as SpriteFont: #{error.message}"
  end
  font_handle = font[0, 8].unpack1("Q")
  if font_handle.zero?
    raise Microsoft::Xna::Framework::Content::ContentLoadException,
          "#{asset_name} reported a successful load with no font"
  end
  Microsoft::Xna::Framework::Graphics::SpriteFont.__send__(
    :new, CNA::Runtime::Context.__send__(:current_game, "SpriteFont"),
    font_handle, texture[0, 8].unpack1("Q")
  )
end
