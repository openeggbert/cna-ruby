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

          private

          # `GraphicsDevice.FireCreatedEvent` keeps **one** args object per device and writes the
          # new resource into `_resource` on it, then nulls that field once the handlers return. So
          # the field really is written from outside the constructor, and this is the only writer.
          def resource=(value)
            @Resource = value
          end
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

          private

          # `FireDestroyedEvent`'s reuse path, in its order: `_name` first, then `_tag`. Unlike the
          # created event it does **not** clear either afterwards.
          def assign(name, tag)
            @Name = name
            @Tag = tag
            self
          end
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

        # The interface `VertexDeclaration`'s `INTERFACE_PRODUCER_MISSING` blocker named, and the
        # second type this frontier ever *selected* rather than listed: building the declaration
        # uncovered it with no blocker at all. One member, one `ldnull`-free contract -- XNA's own
        # implementers are the vertex structs (`VertexPositionColor` and its family), none of which
        # is projected, so this is an abstract contract and **nothing conforms to it**. That is
        # deliberate and is what keeps the producer rule honest: a completed interface is not a
        # provider, which `test_member_level_dependencies.rb` measures.
        module IVertexType
          def VertexDeclaration = raise(NotImplementedError, "IVertexType#VertexDeclaration")
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

        # The lighting contract, and the one of the three effect interfaces that could not be
        # projected until something produced a `DirectionalLight`. Six members: `EnableDefaultLighting`
        # and five properties, three of which are read-only because a light is handed out rather
        # than assigned. Like every interface here it is an abstract contract -- `BasicEffect`,
        # `SkinnedEffect` and `EnvironmentMapEffect` are XNA's implementers and none of them is
        # projected yet, so nothing conforms to it.
        module IEffectLights
          def EnableDefaultLighting = raise(NotImplementedError, "IEffectLights#EnableDefaultLighting")
          def DirectionalLight0 = raise(NotImplementedError, "IEffectLights#DirectionalLight0")
          def DirectionalLight1 = raise(NotImplementedError, "IEffectLights#DirectionalLight1")
          def DirectionalLight2 = raise(NotImplementedError, "IEffectLights#DirectionalLight2")
          def AmbientLightColor = raise(NotImplementedError, "IEffectLights#AmbientLightColor")
          def AmbientLightColor=(_value)
            raise NotImplementedError, "IEffectLights#AmbientLightColor="
          end
          def LightingEnabled = raise(NotImplementedError, "IEffectLights#LightingEnabled")
          def LightingEnabled=(_value)
            raise NotImplementedError, "IEffectLights#LightingEnabled="
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
          extend CNA::Runtime::EventOwner
          private_class_method :new

          # The device's six events. Four are CNA's to raise and two are this projection's, and
          # which is which was measured rather than chosen -- see `subscribe_device_events` and
          # `fire_created_event` below.
          xna_event :Disposing
          xna_event :DeviceLost
          xna_event :DeviceReset
          xna_event :DeviceResetting
          xna_event :ResourceCreated
          xna_event :ResourceDestroyed

          # The three data-free identities CNA can actually deliver, paired with the private raiser
          # each one reaches. XNA's raisers are `raise_*` and `private`, so these are private too:
          # an event's whole public surface is add/remove.
          #
          # `CNA_GRAPHICS_DEVICE_EVENT_DISPOSING` is the fourth and is **not** subscribed, for a
          # measured reason. CNA raises it inside `cna_game_destroy`, and by then the graphics
          # device manager handle — and with it every registration made through this device — has
          # already been released, because `cna_graphics_device_manager_create` documents "release
          # it before the game". Measured both ways: a *leaked* native subscription does receive it
          # during `Game#Dispose`, and a correctly released one never can. So `Disposing` is raised
          # managed from the device's own invalidation, which is where XNA raises it — from
          # `~GraphicsDevice()`. It is the same shape as `Game.Disposed`, which is raised managed
          # for the same kind of measured reason rather than relayed from
          # `CNA_GAME_EVENT_DISPOSED`.
          NATIVE_EVENTS = {
            "CNA_GRAPHICS_DEVICE_EVENT_DEVICE_LOST" => :raise_DeviceLost,
            "CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESET" => :raise_DeviceReset,
            "CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESETTING" => :raise_DeviceResetting
          }.freeze
          private_constant :NATIVE_EVENTS

          # `CNA_RESULT_NOT_SUPPORTED`, which is what the two members below raise for an argument
          # this ABI has no route to honour.
          NOT_SUPPORTED = CNA::Native::Library::RESULT_NOT_SUPPORTED
          private_constant :NOT_SUPPORTED

          def initialize(game)
            @game = game
            @callback_handle = 0
            @invalidated = false
            @index_buffer = nil
            @vertex_buffer_bindings = []
            @render_target_bindings = []
            @event_registrations = nil
            @event_callbacks = []
            @pending_event_exception = nil
          end

          def IsDisposed = @invalidated || @game.__send__(:disposed?)

          # DEVIATION, recorded and measured: XNA's `get_Viewport` is `ldfld currentViewport`, a
          # managed cache that `set_Viewport`, the internal `SetRenderTargets` and
          # `InitializeDeviceState` are the only three writers of. This asks the device instead.
          #
          # The two are observationally equal for everything the managed contract can distinguish —
          # a viewport written through the setter below reads back **exactly**, all six fields,
          # fractional depths included — and asking is strictly better in the one case they differ:
          # canonical CNA code that moves the viewport itself, which a managed cache would answer
          # staleley and this answers correctly.
          def Viewport
            output = CNA::Native::Layouts::Viewport.new
            CNA::Native.library.call("cna_graphics_device_get_viewport", native_handle, output.pointer)
            Viewport.from_native(output)
          end

          # `set_Viewport`, whose eleven guards all raise the same
          # `ArgumentException(ViewportInvalid, "value")` and are reproduced in the IL's order:
          #
          #     X < 0 | Y < 0 | Width <= 0 | Height <= 0
          #     X + Width  > bounds width          -- the current render target's, or the back
          #     Y + Height > bounds height            buffer's when none is bound
          #     MinDepth < 0 | MinDepth > 1 | MaxDepth < 0 | MaxDepth > 1
          #     !(MaxDepth >= MinDepth)
          #
          # The last is `bge.un.s`, so it is **unordered-true**: a NaN depth passes every one of
          # these — the four range guards are ordered comparisons a NaN fails — and reaches the
          # device, where CNA refuses it with `CNA_RESULT_INVALID_ARGUMENT` because
          # `cna_graphics_device_set_viewport` documents that both depths must be finite. That is
          # the one place this projection's answer comes from CNA rather than from XNA, and it is
          # a refusal either way.
          #
          # `CNA_Viewport` is a 24-byte aggregate passed **by value**, which the System V x86-64
          # classification puts in MEMORY rather than in registers. `Manifest.by_value_memory`
          # records the measured expansion — five register fillers, then the three eightbytes that
          # overflow onto the stack where the callee reads them — and the ABI gate re-derives both
          # numbers from the struct's own `sizeof`.
          def Viewport=(value)
            raise ::TypeError, "value must be a Viewport" unless value.instance_of?(Viewport)

            width, height = viewport_bounds
            valid = value.X >= 0 && value.Y >= 0 && value.Width.positive? && value.Height.positive? &&
                    value.X + value.Width <= width && value.Y + value.Height <= height &&
                    !(value.MinDepth < 0.0) && !(value.MinDepth > 1.0) &&
                    !(value.MaxDepth < 0.0) && !(value.MaxDepth > 1.0) &&
                    !(value.MaxDepth < value.MinDepth)
            raise ::ArgumentError, "ViewportInvalid" unless valid

            eightbytes = [value.X, value.Y, value.Width, value.Height].pack("l4")
                         .+([value.MinDepth, value.MaxDepth].pack("e2")).unpack("Q3")
            CNA::Native.library.call("cna_graphics_device_set_viewport", native_handle,
                                     0, 0, 0, 0, 0, *eightbytes)
            value
          end

          # ------------------------------------------------------------ presenting and resetting

          #     Present()
          #     Present(Nullable<Rectangle> source, Nullable<Rectangle> destination, IntPtr window)
          #
          # `Present()` is `Present(null, null, null)` on the private three-pointer native form, so
          # the no-argument overload is exact. The three-argument one converts each present
          # rectangle into a `tagRECT` **in a local copy** -- `right = width + x`,
          # `bottom = height + y`, so the caller's rectangle is not mutated -- and passes the
          # override window handle through `IntPtr::ToPointer`.
          #
          # `cna_graphics_device_present` takes neither. So the all-null call is exact and anything
          # else is refused, naming what CNA does not accept rather than ignoring it: the
          # `VideoPlayer.Play(Video)` precedent, where a member whose argument cannot be honoured
          # refuses explicitly instead of being deferred or quietly reinterpreted.
          def Present(*arguments)
            unless arguments.empty? || arguments.length == 3
              raise ::ArgumentError, "Present takes no arguments or (sourceRectangle, destinationRectangle, overrideWindowHandle)"
            end

            unless arguments.empty?
              source, destination, window = arguments
              [["sourceRectangle", source], ["destinationRectangle", destination]].each do |name, value|
                next if value.nil?
                raise ::TypeError, "#{name} must be a Rectangle or nil" unless value.instance_of?(Rectangle)

                raise CNA::CapabilityError.new("cna_graphics_device_present", NOT_SUPPORTED),
                      "#{name} is not supported: cna_graphics_device_present presents the whole frame " \
                      "and this ABI has no route that takes a present rectangle"
              end
              unless window.nil? || (window.is_a?(::Integer) && window.zero?)
                CNA::Runtime::Numeric.intptr(window, "overrideWindowHandle")
                raise CNA::CapabilityError.new("cna_graphics_device_present", NOT_SUPPORTED),
                      "overrideWindowHandle is not supported: cna_graphics_device_present presents to " \
                      "the device's own window and this ABI has no route that takes another"
              end
            end

            CNA::Native.library.call("cna_graphics_device_present", native_handle)
            nil
          end

          #     Reset()
          #     Reset(PresentationParameters presentationParameters)
          #     Reset(PresentationParameters presentationParameters, GraphicsAdapter graphicsAdapter)
          #
          # The first two forward to the third with `pInternalCachedParams` and `pCurrentAdapter`
          # filled in, and the third is where the whole sequence lives: two null guards, the
          # `DeviceResetting` event, a `SavedDeviceState`, the device re-creation, two fresh
          # `Clone()`s of the argument into the internal and public caches, `InitializeDeviceState`,
          # `SavedDeviceState.Restore()` and the `DeviceReset` event.
          #
          # **Most of that is CNA's, and it was measured rather than assumed.** Across
          # `cna_graphics_device_reset` and `cna_graphics_device_reset_with_parameters`, on the
          # `HEADLESS` and the `OPENGL33` artifact alike: the blend state, the blend factor, the
          # multi-sample mask, the reference stencil and a bound texture slot all survive, and the
          # viewport and the scissor rectangle survive a same-size reset and are reset to the new
          # full target by a resizing one -- which is exactly the rule XNA's `SavedDeviceState`
          # implements by taking its viewport and scissor as `Nullable`. Re-applying any of it here
          # would perform a step CNA already performs.
          #
          # What is left managed is the part CNA cannot know about: the two guards, the render-target
          # unbind that `SavedDeviceState` deliberately does *not* restore, and the two cached
          # parameter objects.
          #
          # The third overload's second argument is a `GraphicsAdapter`, which this binding does not
          # project, so it refuses -- the blocker's fourth appearance, and named as such.
          def Reset(*arguments)
            case arguments.length
            when 0 then parameters = internal_presentation_parameters
            when 1, 2 then parameters = arguments[0]
            else raise ::ArgumentError, "Reset takes at most (presentationParameters, graphicsAdapter)"
            end
            raise ::ArgumentError, "presentationParameters" if parameters.nil?
            unless parameters.instance_of?(PresentationParameters)
              raise ::TypeError, "presentationParameters must be a PresentationParameters"
            end

            if arguments.length == 2
              raise ::ArgumentError, "graphicsAdapter" if arguments[1].nil?

              raise CNA::CapabilityError.new("cna_graphics_device_reset_with_parameters", NOT_SUPPORTED),
                    "Reset(presentationParameters, graphicsAdapter) is not supported: " \
                    "Graphics.GraphicsAdapter is not projected, because every cna_graphics_adapter_* " \
                    "route answers invented display data -- see " \
                    "docs/graphics-adapter-ordering-upstream-defect.md"
            end

            set_render_target_bindings([])
            # `vertexDeclarationManager.ReleaseAllDeclarations()`, which XNA performs between
            # releasing the default-pool resources and re-creating the device.
            release_declarations
            if arguments.empty?
              CNA::Native.library.call("cna_graphics_device_reset", native_handle)
            else
              CNA::Native.library.call("cna_graphics_device_reset_with_parameters", native_handle,
                                       to_native_presentation_parameters(parameters).pointer, 0)
            end
            @internal_presentation_parameters = parameters.Clone
            @presentation_parameters = parameters.Clone
            # CNA raises the device's resetting and reset events inside the call above, in that
            # order, so a handler's exception belongs to this frame.
            drain_event_exception
            nil
          end

          # ------------------------------------------------------------ the four simple properties
          #
          # `docs/graphics-runtime-member-audit.md` measured these five as a family. Four are here;
          # the fifth, `Adapter`, is one `ldfld` whose *type* is `Graphics.GraphicsAdapter`, and
          # that type is the single blocker the whole audit found —
          # `docs/graphics-adapter-ordering-upstream-defect.md`.

          # `ldfld _graphicsProfile`, a field the constructor fills and nothing else writes.
          #
          # DEVIATION, recorded: asked rather than cached. The device is CNA's, so CNA is what knows
          # which profile it was created with; the value cannot change over a device's life, so the
          # two are observationally identical.
          def GraphicsProfile
            output = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_graphics_device_get_graphics_profile", native_handle, output)
            Graphics::GraphicsProfile.coerce(output[0, 4].unpack1("L"))
          end

          # `TestCooperativeLevel`, mapped: `D3DERR_DEVICELOST` (0x88760868) is `Lost`,
          # `D3DERR_DEVICENOTRESET` (0x88760869) is `NotReset`, any other failure is thrown, and
          # success is `Normal`. A live query in XNA and a live query here; CNA's three
          # `CNA_GRAPHICS_DEVICE_STATUS_*` identities are the same three values in the same order.
          def GraphicsDeviceStatus
            output = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_graphics_device_get_status", native_handle, output)
            Graphics::GraphicsDeviceStatus.coerce(output[0, 4].unpack1("L"))
          end

          # `DisplayMode` is **not** here, and the audit that put it in this family had it wrong.
          # `docs/graphics-runtime-member-audit.md` first classified it buildable on the strength of
          # `cna_graphics_device_get_display_mode` existing. Measuring it is what settled it: with a
          # 320x200 back buffer on a real 1280x800 X display, that route answers **800x480** — which
          # is neither — and it answers byte-for-byte what
          # `cna_graphics_adapter_get_current_display_mode` answers, on the `HEADLESS` artifact and
          # on the `OPENGL33` one alike. It is the same fabricated no-display fallback
          # `docs/graphics-adapter-ordering-upstream-defect.md` records, so projecting this getter
          # would report invented hardware — the exact reason `GraphicsAdapter` itself is not
          # projected. `BLOCKED_UPSTREAM_CNA`, and the second member that blocker takes.

          # `ldfld pPublicCachedParams`: one field read, so the **same object** every call, and a
          # consumer that mutates what it gets back sees the mutation next time. Only device
          # creation and `Reset` replace it, which is why this seeds once rather than re-reading.
          #
          # The earliest moment this projection can reach the device is the first touch inside a
          # lifecycle callback — the same argument `ensure_initial_device_state` records — and no
          # observer can tell that from creation time, because the first read is what would notice.
          #
          # DEVIATION, recorded: `DeviceWindowHandle` stays the constructor's zero.
          # `CNA_PresentationParameters` carries no window handle, and
          # `cna_graphics_device_get_native_window_handle` **deliberately refuses**: CNA's own header
          # says "a device may outlive or precede the window it presents to and answering here would
          # invent an ownership relationship the canonical layer does not have". Every other field is
          # CNA's real applied value.
          def PresentationParameters
            @presentation_parameters ||= read_presentation_parameters
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

          # `SamplerStates` is `new SamplerStateCollection(this, 0, MaxSamplers)` and
          # `VertexSamplerStates` is `new SamplerStateCollection(this, D3DVERTEXTEXTURESAMPLER0, …)`.
          # Both getters are one `ldfld`, so each answers the same object every time, and the two
          # differ by CNA shader stage for the same reason the texture collections do.
          def SamplerStates
            @sampler_states ||= SamplerStateCollection.__send__(
              :new, self, CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_PIXEL")
            )
          end

          def VertexSamplerStates
            @vertex_sampler_states ||= SamplerStateCollection.__send__(
              :new, self, CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_VERTEX")
            )
          end

          # ------------------------------------------------------------------ the device's own state
          #
          # `InitializeDeviceState` nulls the three cached fields and then assigns
          # `BlendState.Opaque`, `DepthStencilState.Default` and
          # `RasterizerState.CullCounterClockwise` **through the setters**, so a fresh XNA device
          # answers those three preset objects by identity. It runs during device creation; the
          # earliest reachable moment here is the first touch inside a lifecycle callback, because
          # nothing can reach the device outside one -- and no observer can tell the two apart, since
          # the first read or write is what would notice.
          #
          # Each getter answers the **object that was assigned**, exactly as `ldfld` does. A state
          # read back from CNA would be a different object with the same values, and XNA's reference
          # identity here is observable.
          def BlendState
            ensure_initial_device_state
            @blend_state
          end

          # `set_BlendState`, in the IL's order: a null is `ArgumentNullException("value")`; the same
          # object with a clean dirty flag returns untouched; otherwise the state is applied and the
          # device **takes the state's own `BlendFactor` and `MultiSampleMask` with it**, which is
          # why writing either of those scalars afterwards marks the blend state dirty -- so that
          # assigning the same object again really does re-apply it.
          def BlendState=(value)
            raise ::ArgumentError, "value" if value.nil?
            raise ::TypeError, "value must be a BlendState" unless value.instance_of?(BlendState)

            ensure_initial_device_state
            return value if value.equal?(@blend_state) && !@blend_state_dirty

            apply_blend_state(value)
            value
          end

          def DepthStencilState
            ensure_initial_device_state
            @depth_stencil_state
          end

          # The same shape, and it carries `ReferenceStencil` across in place of the blend pair.
          def DepthStencilState=(value)
            raise ::ArgumentError, "value" if value.nil?
            raise ::TypeError, "value must be a DepthStencilState" unless value.instance_of?(DepthStencilState)

            ensure_initial_device_state
            return value if value.equal?(@depth_stencil_state) && !@depth_stencil_state_dirty

            apply_depth_stencil_state(value)
            value
          end

          def RasterizerState
            ensure_initial_device_state
            @rasterizer_state
          end

          # The odd one out: its guard is `beq` on the object alone, with **no dirty flag** -- there
          # is no scalar property that shadows part of a rasterizer state, so nothing can make an
          # already-assigned one stale.
          def RasterizerState=(value)
            raise ::ArgumentError, "value" if value.nil?
            raise ::TypeError, "value must be a RasterizerState" unless value.instance_of?(RasterizerState)

            ensure_initial_device_state
            return value if value.equal?(@rasterizer_state)

            apply_rasterizer_state(value)
            value
          end

          def BlendFactor
            ensure_initial_device_state
            @blend_factor
          end

          def BlendFactor=(value)
            raise ::TypeError, "value must be a Color" unless value.instance_of?(Color)

            ensure_initial_device_state
            CNA::Native.library.call("cna_graphics_device_set_blend_factor", native_handle,
                                     value.PackedValue)
            @blend_factor = value.dup
            @blend_state_dirty = true
            value
          end

          def MultiSampleMask
            ensure_initial_device_state
            @multi_sample_mask
          end

          def MultiSampleMask=(value)
            mask = CNA::Runtime::Numeric.int32(value, "value")
            ensure_initial_device_state
            CNA::Native.library.call("cna_graphics_device_set_multi_sample_mask", native_handle, mask)
            @multi_sample_mask = mask
            @blend_state_dirty = true
            value
          end

          def ReferenceStencil
            ensure_initial_device_state
            @reference_stencil
          end

          def ReferenceStencil=(value)
            reference = CNA::Runtime::Numeric.int32(value, "value")
            ensure_initial_device_state
            CNA::Native.library.call("cna_graphics_device_set_reference_stencil", native_handle, reference)
            @reference_stencil = reference
            @depth_stencil_state_dirty = true
            value
          end

          # `get_ScissorRectangle` asks the device rather than a cache, and so does this.
          def ScissorRectangle
            output = CNA::Native::Layouts::Rectangle.new
            CNA::Native.library.call("cna_graphics_device_get_scissor_rectangle", native_handle,
                                     output.pointer)
            Rectangle.new(output.read_i32(0), output.read_i32(4), output.read_i32(8), output.read_i32(12))
          end

          # The setter validates before it writes: the rectangle must lie inside the current render
          # target's bounds, or the back buffer's when none is bound, and an
          # `ArgumentException(ScissorInvalid, "value")` is what a rectangle outside them gets.
          #
          # Only the back-buffer branch is reachable here, and that is not a partial implementation:
          # binding a render target is `GraphicsDevice.SetRenderTarget`, which this binding does not
          # project, so no other bounds exist to check against.
          #
          # The rectangle is a sixteen-byte aggregate passed **by value**; the manifest records the
          # measured two-eightbyte expansion, and this packs the two integers it names.
          def ScissorRectangle=(value)
            raise ::TypeError, "value must be a Rectangle" unless value.instance_of?(Rectangle)

            width, height = back_buffer_bounds
            unless value.X >= 0 && value.Y >= 0 && value.Width >= 0 && value.Height >= 0 &&
                   value.X + value.Width <= width && value.Y + value.Height <= height
              raise ::ArgumentError, "ScissorInvalid"
            end

            low = (value.X & 0xFFFFFFFF) | (value.Y << 32)
            high = (value.Width & 0xFFFFFFFF) | (value.Height << 32)
            CNA::Native.library.call("cna_graphics_device_set_scissor_rectangle", native_handle, low, high)
            value
          end

          # ------------------------------------------------------------------ what the device binds
          #
          # CNA hands back **handles** for what is bound, and this ABI has no route from a native
          # object back to a handle -- the rule `TextureCollection` already records. So each getter
          # answers the Ruby object this device bound, which is what XNA's `ldfld` answers too.

          # `ldfld _currentIB`.
          def Indices = @index_buffer

          # `set_Indices` checks the device, then binds or clears: a null is
          # `SetIndices(null)` rather than a refusal.
          def Indices=(value)
            unless value.nil? || value.is_a?(IndexBuffer)
              raise ::TypeError, "value must be an IndexBuffer"
            end

            require_same_device(value) unless value.nil?
            CNA::Native.library.call("cna_graphics_device_set_index_buffer", native_handle,
                                     value.nil? ? 0 : value.__send__(:native_handle))
            @index_buffer = value
          end

          #     SetVertexBuffer(vertexBuffer)
          #     SetVertexBuffer(vertexBuffer, vertexOffset)
          #
          # Both build a `VertexBufferBinding` and forward to the internal array form, and a null
          # buffer forwards `(null, 0)` -- which unbinds every stream rather than raising.
          def SetVertexBuffer(vertexBuffer, vertexOffset = nil)
            if vertexBuffer.nil?
              raise ::ArgumentError, "SetVertexBuffer(nil) takes no vertexOffset" unless vertexOffset.nil?

              return set_vertex_buffer_bindings([])
            end

            binding = vertexOffset.nil? ? RenderTargetBindingSupport.vertex_binding(vertexBuffer)
                                        : RenderTargetBindingSupport.vertex_binding(vertexBuffer, vertexOffset)
            set_vertex_buffer_bindings([binding])
          end

          # The public array overload: `null` or an empty array is the same unbind the null buffer
          # performs, and anything else is validated binding by binding **before** any is applied.
          def SetVertexBuffers(vertexBuffers = nil)
            return set_vertex_buffer_bindings([]) if vertexBuffers.nil?
            raise ::TypeError, "vertexBuffers must be an Array" unless vertexBuffers.is_a?(::Array)

            vertexBuffers.each do |binding|
              raise ::ArgumentError, "NullNotAllowed" if binding.nil?
              unless binding.instance_of?(VertexBufferBinding)
                raise ::TypeError, "every entry must be a VertexBufferBinding"
              end

              require_same_device(binding.VertexBuffer)
            end
            set_vertex_buffer_bindings(vertexBuffers.dup)
          end

          # `newarr` + `Array.Copy`: a fresh array over the same bindings, every call.
          def GetVertexBuffers = @vertex_buffer_bindings.dup

          #     SetRenderTarget(renderTarget)                  -- a RenderTarget2D or null
          #     SetRenderTarget(renderTarget, cubeMapFace)     -- a RenderTargetCube and a face
          #
          # Both forward to the array form, and a null target forwards `(null, 0)`: the back buffer
          # comes back rather than an exception.
          def SetRenderTarget(renderTarget, cubeMapFace = nil)
            if renderTarget.nil?
              raise ::ArgumentError, "SetRenderTarget(nil) takes no cubeMapFace" unless cubeMapFace.nil?

              return set_render_target_bindings([])
            end

            binding = cubeMapFace.nil? ? RenderTargetBinding.new(renderTarget)
                                       : RenderTargetBinding.new(renderTarget, cubeMapFace)
            set_render_target_bindings([binding])
          end

          # `params RenderTargetBinding[]`: no argument at all, `nil` and an empty array are the same
          # restore, and anything else is validated before any of it is applied.
          def SetRenderTargets(*renderTargets)
            bindings = renderTargets.length == 1 && (renderTargets[0].nil? || renderTargets[0].is_a?(::Array)) ?
                         renderTargets[0] : renderTargets
            return set_render_target_bindings([]) if bindings.nil? || bindings.empty?

            bindings.each_with_index do |binding, index|
              raise ::ArgumentError, "NullNotAllowed" if binding.nil?
              unless binding.instance_of?(RenderTargetBinding)
                raise ::TypeError, "every entry must be a RenderTargetBinding"
              end

              require_same_device(binding.RenderTarget)
              if bindings[0...index].any? { |earlier| earlier.RenderTarget.equal?(binding.RenderTarget) }
                raise ::ArgumentError, "CannotSetAlreadyUsedRenderTarget"
              end
              unless same_target_shape?(bindings[0].RenderTarget, binding.RenderTarget)
                raise ::ArgumentError, "RenderTargetsMustMatch"
              end
            end
            set_render_target_bindings(bindings.dup)
          end

          def GetRenderTargets = @render_target_bindings.dup

          # ------------------------------------------------------------------ what the device draws
          #
          # The three draw calls that read the device's **own** bound buffers. Their managed
          # validation is short and identical in shape:
          #
          #   primitiveCount <= 0        -> ArgumentOutOfRangeException("primitiveCount", MustDrawSomething)
          #   numVertices <= 0           -> ArgumentOutOfRangeException("numVertices", NumberVerticesMustBeGreaterZero)
          #   instanceCount <= 0         -> ArgumentOutOfRangeException("instanceCount", MustDrawSomething)
          #   a stream with a non-zero InstanceFrequency, on the two non-instanced calls
          #                              -> InvalidOperationException(NonZeroInstanceFrequency)
          #   primitiveCount > the profile's maximum -> ProfileMaxPrimitiveCount
          #
          # The last of those is a profile capability rather than a managed rule, so it is CNA's to
          # refuse -- the same decision the occlusion query's profile check records. What is a
          # managed rule is the instance-frequency guard, and this projection has the fact it needs:
          # the bindings it cached when they were set.
          def DrawPrimitives(primitiveType, startVertex, primitiveCount)
            topology = PrimitiveType.coerce(primitiveType)
            first = CNA::Runtime::Numeric.int32(startVertex, "startVertex")
            count = require_primitive_count(primitiveCount)
            require_no_instance_frequency
            CNA::Native.library.call("cna_graphics_device_draw_primitives", native_handle,
                                     topology.to_i, first, count)
            nil
          end

          def DrawIndexedPrimitives(primitiveType, baseVertex, minVertexIndex, numVertices,
                                    startIndex, primitiveCount)
            topology = PrimitiveType.coerce(primitiveType)
            base = CNA::Runtime::Numeric.int32(baseVertex, "baseVertex")
            minimum = CNA::Runtime::Numeric.int32(minVertexIndex, "minVertexIndex")
            vertices = CNA::Runtime::Numeric.int32(numVertices, "numVertices")
            raise ::RangeError, "numVertices" unless vertices.positive?

            start = CNA::Runtime::Numeric.int32(startIndex, "startIndex")
            count = require_primitive_count(primitiveCount)
            require_no_instance_frequency
            CNA::Native.library.call("cna_graphics_device_draw_indexed_primitives", native_handle,
                                     topology.to_i, base, minimum, vertices, start, count)
            nil
          end

          # The instanced call has no instance-frequency guard -- a non-zero frequency is what it is
          # **for** -- and one extra count of its own.
          def DrawInstancedPrimitives(primitiveType, baseVertex, minVertexIndex, numVertices,
                                      startIndex, primitiveCount, instanceCount)
            topology = PrimitiveType.coerce(primitiveType)
            base = CNA::Runtime::Numeric.int32(baseVertex, "baseVertex")
            minimum = CNA::Runtime::Numeric.int32(minVertexIndex, "minVertexIndex")
            vertices = CNA::Runtime::Numeric.int32(numVertices, "numVertices")
            raise ::RangeError, "numVertices" unless vertices.positive?

            start = CNA::Runtime::Numeric.int32(startIndex, "startIndex")
            count = require_primitive_count(primitiveCount)
            instances = CNA::Runtime::Numeric.int32(instanceCount, "instanceCount")
            raise ::RangeError, "instanceCount" unless instances.positive?

            CNA::Native.library.call("cna_graphics_device_draw_instanced_primitives", native_handle,
                                     topology.to_i, base, minimum, vertices, start, count, instances)
            nil
          end

          # All three `Clear` overloads, which Ruby reaches through one method because it cannot
          # overload by parameter type:
          #
          #     Clear(color)                              -> Clear(DefaultClearOptions, color, 1f, 0)
          #     Clear(options, Vector4 color, depth, stencil) -> Clear(options, new Color(color), …)
          #     Clear(options, Color   color, depth, stencil) -> the real one
          #
          # The two forwarding overloads are three IL instructions each and are reproduced exactly,
          # including `Clear(color)`'s `1f` depth and `0` stencil.
          #
          # Everything the real overload does around its native `Clear` is a D3D9 workaround with no
          # managed observable: it zeroes `D3DRS_COLORWRITEENABLE` and restores it, and it installs a
          # full-target viewport and restores that, because D3D9's `Clear` respects both and XNA's
          # must not. CNA's `cna_graphics_device_clear_options` owns its backend's equivalent, so
          # re-implementing either here would perform a step CNA already performs -- the rule the
          # `GraphicsDeviceManager` producer audit established.
          #
          # What **is** managed is the failure rule, and it is reproduced: when the native clear
          # fails, XNA asks whether the depth and stencil bits the caller requested are ones the
          # current target actually has, and answers `InvalidOperationException(CannotClearNullDepth)`
          # when they are not. CNA reports exactly that case as `CNA_RESULT_NOT_SUPPORTED`, "when the
          # backend cannot clear a selected buffer".
          # ------------------------------------------------------------ the user-primitive draws
          #
          #     DrawUserPrimitives<T>(type, data, offset, count)                     T : IVertexType
          #     DrawUserPrimitives<T>(type, data, offset, count, declaration)
          #
          # The four-argument overload is the five-argument one with
          # `VertexDeclarationFactory.GetVertexDeclaration<T>()` filled in, and this projection reads
          # the same declaration off the element type. The guards are the IL's, in the IL's order,
          # and each carries the resource string XNA raises with:
          #
          #     vertexData null or empty          -> ArgumentNullException("vertexData", NullNotAllowed)
          #     vertexDeclaration null            -> ArgumentNullException("vertexDeclaration", NullNotAllowed)
          #     primitiveCount <= 0               -> ArgumentOutOfRangeException("primitiveCount", MustDrawSomething)
          #     primitiveCount > profile maximum  -> ProfileMaxPrimitiveCount, which is CNA's to refuse
          #     vertexOffset outside the array    -> ArgumentOutOfRangeException("vertexOffset", OffsetNotValid)
          #     the topology needs more vertices than the window holds
          #                                       -> ArgumentOutOfRangeException("primitiveCount", MustBeValidIndex)
          #
          # LANGUAGE MAPPING, recorded: Ruby has no type argument at a call site, so `T` is read from
          # the array's own elements — which is unambiguous, because `pack_elements` already requires
          # every element to be the same type. `DrawUserIndexedPrimitives` below needs one anyway,
          # for a reason that is not `T`.
          def DrawUserPrimitives(primitiveType, vertexData, vertexOffset, primitiveCount,
                                 vertexDeclaration = nil)
            topology = PrimitiveType.coerce(primitiveType)
            element_type = require_user_vertices(vertexData)
            declaration = user_vertex_declaration(vertexDeclaration, element_type)
            offset = CNA::Runtime::Numeric.int32(vertexOffset, "vertexOffset")
            count = CNA::Runtime::Numeric.int32(primitiveCount, "primitiveCount")
            raise ::RangeError, "primitiveCount" unless count.positive?
            raise ::RangeError, "vertexOffset" if offset.negative? || offset >= vertexData.length
            unless vertex_count_for(topology, count) <= vertexData.length - offset
              raise ::RangeError, "primitiveCount"
            end

            bytes = pack_user_vertices(element_type, vertexData)
            description = user_primitives(topology, bytes, declaration, offset, 0, count)
            begin_user_primitives
            CNA::Native.library.call("cna_graphics_device_draw_user_primitives", native_handle,
                                     description.pointer)
            nil
          end

          #     DrawUserIndexedPrimitives<T>(indexType, type, data, offset, numVertices,
          #                                  indexData, indexOffset, count[, declaration])
          #
          # Four XNA overloads: `Int32[]` and `Int16[]` indices, each with and without an explicit
          # declaration. LANGUAGE MAPPING, recorded: a Ruby `Array` of integers is neither, so the
          # index element size is passed the way every other generic in this binding is passed —
          # a leading type argument, resolved by the same rule `IndexBuffer`'s constructor and
          # `SetData` use, where `IndexElementSize` is itself and `::Integer` means `ThirtyTwoBits`.
          # `T` still comes from the array, because nothing about it is ambiguous.
          #
          # Two guards this one adds, both in the IL's order:
          #
          #     indexData null or empty       -> ArgumentNullException("indexData", NullNotAllowed)
          #     numVertices <= 0              -> ArgumentOutOfRangeException("numVertices", NumberVerticesMustBeGreaterZero)
          #     indexOffset outside the array -> ArgumentOutOfRangeException("indexOffset", OffsetNotValid)
          #     the topology needs more indices than the window holds
          #                                   -> ArgumentOutOfRangeException("primitiveCount", MustBeValidIndex)
          #     vertexOffset + numVertices past the array
          #                                   -> ArgumentOutOfRangeException("vertexData", MustBeValidIndex)
          def DrawUserIndexedPrimitives(indexType, primitiveType, vertexData, vertexOffset, numVertices,
                                        indexData, indexOffset, primitiveCount, vertexDeclaration = nil)
            element_size = IndexBuffer.__send__(:resolve_element_size, indexType)
            topology = PrimitiveType.coerce(primitiveType)
            element_type = require_user_vertices(vertexData)
            raise ::ArgumentError, "indexData" if indexData.nil?
            raise ::TypeError, "indexData must be an Array" unless indexData.is_a?(::Array)
            raise ::ArgumentError, "indexData" if indexData.empty?

            declaration = user_vertex_declaration(vertexDeclaration, element_type)
            vertices = CNA::Runtime::Numeric.int32(numVertices, "numVertices")
            raise ::RangeError, "numVertices" unless vertices.positive?

            offset = CNA::Runtime::Numeric.int32(vertexOffset, "vertexOffset")
            index_offset = CNA::Runtime::Numeric.int32(indexOffset, "indexOffset")
            count = CNA::Runtime::Numeric.int32(primitiveCount, "primitiveCount")
            raise ::RangeError, "primitiveCount" unless count.positive?
            raise ::RangeError, "vertexOffset" if offset.negative? || offset >= vertexData.length
            raise ::RangeError, "indexOffset" if index_offset.negative? || index_offset >= indexData.length
            unless element_count_for(topology, count) + index_offset <= indexData.length
              raise ::RangeError, "primitiveCount"
            end
            raise ::RangeError, "vertexData" if offset + vertices > vertexData.length

            width = element_size.to_i.zero? ? 2 : 4
            bytes = pack_user_vertices(element_type, vertexData)
            indices = IndexBuffer.__send__(:pack_indices, indexData, 0, indexData.length, width)
            description = user_primitives(topology, bytes, declaration, offset, vertices, count)
            window = CNA::Native::Layouts::UserIndices.new
            window.write_u32(8, element_size.to_i)
            window.write_i32(12, index_offset)
            window.write_pointer(16, Fiddle::Pointer[indices])
            begin_user_primitives
            begin
              CNA::Native.library.call("cna_graphics_device_draw_user_indexed_primitives", native_handle,
                                       description.pointer, window.pointer)
            ensure
              # `_currentIB = null` lives in the indexed draw's `finally`, so it happens whether the
              # draw succeeded or not.
              @index_buffer = nil
            end
            nil
          end

          def Clear(*arguments)
            case arguments.length
            when 1
              options = default_clear_options
              color = arguments[0]
              depth = 1.0
              stencil = 0
            when 4
              options = ClearOptions.coerce(arguments[0])
              color = arguments[1]
              color = Color.new(color) if color.instance_of?(Vector4)
              depth = CNA::Runtime::Numeric.f32(arguments[2])
              stencil = CNA::Runtime::Numeric.int32(arguments[3], "stencil")
            else
              raise ::ArgumentError, "Clear takes (color) or (options, color, depth, stencil)"
            end
            raise ::TypeError, "color must be a Color or a Vector4" unless color.instance_of?(Color)

            begin
              CNA::Native.library.call("cna_graphics_device_clear_options", native_handle,
                                       options.to_i, color.PackedValue, depth, stencil)
            rescue CNA::CapabilityError
              raise ::RuntimeError, "CannotClearNullDepth" unless requested_buffers_exist?(options)

              raise
            end
            nil
          end

          private

          # `InitializeDeviceState`'s three assignments, at the first moment this projection can
          # reach the device. The nulls it writes first are what the three instance variables
          # already are.
          def ensure_initial_device_state
            return if @device_state_initialized

            @device_state_initialized = true
            @blend_state_dirty = true
            @depth_stencil_state_dirty = true
            apply_blend_state(BlendState::Opaque)
            apply_depth_stencil_state(DepthStencilState::Default)
            apply_rasterizer_state(RasterizerState::CullCounterClockwise)
            nil
          end

          def apply_blend_state(value)
            CNA::Native.library.call("cna_graphics_device_set_blend_state", native_handle,
                                     value.__send__(:to_native_descriptor).pointer)
            @blend_state = value
            @blend_factor = value.BlendFactor
            @multi_sample_mask = value.MultiSampleMask
            @blend_state_dirty = false
            nil
          end

          def apply_depth_stencil_state(value)
            CNA::Native.library.call("cna_graphics_device_set_depth_stencil_state", native_handle,
                                     value.__send__(:to_native_descriptor).pointer)
            @depth_stencil_state = value
            @reference_stencil = value.ReferenceStencil
            @depth_stencil_state_dirty = false
            nil
          end

          def apply_rasterizer_state(value)
            CNA::Native.library.call("cna_graphics_device_set_rasterizer_state", native_handle,
                                     value.__send__(:to_native_descriptor).pointer)
            @rasterizer_state = value
            nil
          end

          # `get_DefaultClearOptions`, which is `private` in XNA and reachable only through the two
          # forwarding `Clear` overloads and the failure rule:
          #
          #     Target
          #     | DepthBuffer                   when the depth format is not None
          #     | DepthBuffer | Stencil         when it is exactly Depth24Stencil8
          #
          # and the depth format is the **first bound render target's** when one is bound, the
          # device's own otherwise -- the same `currentRenderTargets[0]`-or-back-buffer choice the
          # viewport bounds and the scissor rule make.
          def default_clear_options
            binding = @render_target_bindings.first
            format = binding.nil? ? internal_presentation_parameters.DepthStencilFormat
                                  : binding.RenderTarget.DepthStencilFormat
            return ClearOptions::Target if format.to_i.zero?

            format.to_i == DepthFormat::Depth24Stencil8.to_i ? ClearOptions.coerce(7) : ClearOptions.coerce(3)
          end

          # `CannotClearNullDepth`: the depth and stencil bits the caller asked for must be bits the
          # current target has. `options & 6` is XNA's own mask -- `DepthBuffer | Stencil` -- and the
          # comparison is with `DefaultClearOptions`, which is what says which of them exist.
          def requested_buffers_exist?(options)
            requested = options.to_i & 6
            (default_clear_options.to_i & requested) == requested
          end

          # XNA keeps **two** presentation-parameter objects: `pPublicCachedParams`, which the public
          # getter hands out and a consumer may mutate, and `pInternalCachedParams`, which the device
          # reads its own rules from. Both are seeded from the same device state and they are
          # distinct objects, so a consumer that mutates what the getter returned cannot change what
          # `DefaultClearOptions` or the viewport bounds decide. That distinction is reproduced here
          # rather than collapsed.
          def internal_presentation_parameters
            @internal_presentation_parameters ||= read_presentation_parameters
          end

          # The reverse of `read_presentation_parameters`, and it starts from CNA's **current**
          # structure rather than from a zeroed one. `CNA_PresentationParameters` carries one field
          # XNA has no analogue for -- `headless_ext`, the extension that asks for off-screen
          # operation -- and overwriting it with a zero would ask a headless device for a window.
          # Preserving what CNA already has there is the only correct choice, and the ten fields XNA
          # does declare are written over it.
          #
          # `DeviceWindowHandle` has no field to write: the structure carries none, which is the
          # other half of the deviation `PresentationParameters` records.
          def to_native_presentation_parameters(parameters)
            output = CNA::Native::Layouts::PresentationParameters.new
            CNA::Native.library.call("cna_graphics_device_get_presentation_parameters",
                                     native_handle, output.pointer)
            output.write_u32(8, parameters.BackBufferFormat.to_i)
            output.write_i32(12, parameters.BackBufferWidth)
            output.write_i32(16, parameters.BackBufferHeight)
            output.write_u32(20, parameters.DepthStencilFormat.to_i)
            output.write_i32(24, parameters.MultiSampleCount)
            output.write_u32(28, parameters.PresentationInterval.to_i)
            output.write_u32(32, parameters.DisplayOrientation.to_i)
            output.write_u32(36, parameters.RenderTargetUsage.to_i)
            output.write_u8(40, parameters.IsFullScreen ? 1 : 0)
            output
          end

          # The ten settings CNA's applied `CNA_PresentationParameters` carries, in the order the
          # struct declares them. Every enum identity is checked against XNA's: `SurfaceFormat`,
          # `DepthFormat`, `PresentInterval`, `DisplayOrientation` and `RenderTargetUsage` all agree
          # value for value over XNA's range, and CNA's `_EXT` formats above it have no XNA identity
          # and so raise rather than being invented.
          def read_presentation_parameters
            output = CNA::Native::Layouts::PresentationParameters.new
            CNA::Native.library.call("cna_graphics_device_get_presentation_parameters",
                                     native_handle, output.pointer)
            parameters = Graphics::PresentationParameters.new
            parameters.BackBufferFormat = output.read_u32(8)
            parameters.BackBufferWidth = output.read_i32(12)
            parameters.BackBufferHeight = output.read_i32(16)
            parameters.DepthStencilFormat = output.read_u32(20)
            parameters.MultiSampleCount = output.read_i32(24)
            parameters.PresentationInterval = output.read_u32(28)
            parameters.DisplayOrientation = output.read_u32(32)
            parameters.RenderTargetUsage = output.read_u32(36)
            parameters.IsFullScreen = !output.read_u8(40).zero?
            parameters
          end

          # `set_Viewport`'s bounds: the first bound render target's, or the back buffer's when none
          # is bound. XNA reads `currentRenderTargets[0]`'s `width`/`height` and falls back to
          # `pInternalCachedParams`, and the cached bindings are that record here — the same cache
          # `require_no_instance_frequency` reads for the draw calls.
          def viewport_bounds
            binding = @render_target_bindings.first
            return back_buffer_bounds if binding.nil?

            shape = target_shape(binding.RenderTarget)
            [shape[0], shape[1]]
          end

          # The logical back buffer, which is what the scissor rule measures against while no render
          # target can be bound.
          def back_buffer_bounds
            info = CNA::Native::Layouts::BackBufferInfo.new
            CNA::Native.library.call("cna_graphics_device_get_backbuffer_info", native_handle, info.pointer)
            [info.read_u32(8), info.read_u32(12)]
          end

          # Every binding is applied in one call, because `cna_graphics_device_set_vertex_buffers`
          # validates the whole array before applying any of it -- which is what XNA's internal
          # overload does too.
          def set_vertex_buffer_bindings(bindings)
            if bindings.empty?
              CNA::Native.library.call("cna_graphics_device_set_vertex_buffers", native_handle, 0, 0)
            else
              buffer = Fiddle::Pointer.malloc(16 * bindings.length, Fiddle::RUBY_FREE)
              bindings.each_with_index do |binding, index|
                buffer[16 * index, 8] = [binding.VertexBuffer.__send__(:native_handle)].pack("Q")
                buffer[(16 * index) + 8, 8] = [binding.VertexOffset, binding.InstanceFrequency].pack("l2")
              end
              CNA::Native.library.call("cna_graphics_device_set_vertex_buffers", native_handle,
                                       buffer, bindings.length)
            end
            @vertex_buffer_bindings = bindings
            nil
          end

          # Every binding in one call, because `cna_graphics_device_set_render_targets` validates the
          # whole array before applying any of it -- and an array identical to the one already bound
          # returns untouched, which is the early-out the IL performs before anything else. That
          # matters rather than being an optimisation: re-binding a `DiscardContents` target is what
          # discards its contents.
          def set_render_target_bindings(bindings)
            return nil if same_render_target_bindings?(bindings)

            if bindings.empty?
              CNA::Native.library.call("cna_graphics_device_set_render_targets", native_handle, 0, 0)
            else
              buffer = Fiddle::Pointer.malloc(24 * bindings.length, Fiddle::RUBY_FREE)
              bindings.each_with_index do |binding, index|
                record = CNA::Native::Layouts::RenderTargetBinding.new
                record.write_u64(8, binding.RenderTarget.__send__(:native_handle))
                record.write_i32(16, 0)
                record.write_u32(20, binding.CubeMapFace.to_i)
                buffer[24 * index, 24] = record.pointer[0, 24]
              end
              CNA::Native.library.call("cna_graphics_device_set_render_targets", native_handle,
                                       buffer, bindings.length)
            end
            @render_target_bindings = bindings
            nil
          end

          def same_render_target_bindings?(bindings)
            return false unless bindings.length == @render_target_bindings.length

            bindings.each_with_index.all? do |binding, index|
              current = @render_target_bindings[index]
              current.RenderTarget.equal?(binding.RenderTarget) &&
                current.CubeMapFace.to_i == binding.CubeMapFace.to_i
            end
          end

          # `RenderTargetsMustMatch`: every target in one binding array is the same size and sample
          # count. A cube's edge is both its dimensions.
          def same_target_shape?(first, other)
            target_shape(first) == target_shape(other)
          end

          def target_shape(target)
            if target.is_a?(RenderTargetCube)
              [target.Size, target.Size, target.MultiSampleCount]
            else
              [target.Width, target.Height, target.MultiSampleCount]
            end
          end

          # ------------------------------------------------------------ the user-primitive helpers

          # `T`, read off the array. A zero-length array is `null` to XNA — the guard is
          # `ldlen; brfalse` — so it raises the same `ArgumentNullException`, and every element must
          # be one type, which is `pack_elements`'s rule already.
          #
          # DEVIATION, recorded: XNA's five-argument overloads constrain `T` to `.ctor` alone, so any
          # struct is legal there. This accepts the four projected vertex structs, because they are
          # the only element types this binding can serialise — the same limit
          # `DynamicVertexBuffer.SetData` records.
          def require_user_vertices(data)
            raise ::ArgumentError, "vertexData" if data.nil?
            raise ::TypeError, "vertexData must be an Array" unless data.is_a?(::Array)
            raise ::ArgumentError, "vertexData" if data.empty?

            type = data.first.class
            unless type.include?(CNA::Runtime::VertexStruct)
              raise ::TypeError, "vertexData must be an Array of a projected vertex struct"
            end
            data.each do |value|
              raise ::TypeError, "vertexData must be an Array of #{type}" unless value.instance_of?(type)
            end
            type
          end

          def pack_user_vertices(type, data)
            VertexBuffer.__send__(:pack_elements, type, data, 0, data.length,
                                  type.const_get(:VertexDeclaration).VertexStride)
          end

          # The declaration the draw uses: the explicit one when given, the element type's own
          # otherwise — `VertexDeclarationFactory.GetVertexDeclaration<T>()`'s analogue.
          def user_vertex_declaration(explicit, element_type)
            return element_type.const_get(:VertexDeclaration) if explicit.nil?
            raise ::TypeError, "vertexDeclaration must be a VertexDeclaration" unless explicit.instance_of?(VertexDeclaration)

            explicit
          end

          # `DeclarationManager` in one line. XNA caches a native declaration per managed one and
          # `Reset` releases the whole cache (`ReleaseAllDeclarations`); this does the same, keyed by
          # object identity, so a draw does not build and destroy one per frame.
          def native_declaration_for(declaration)
            @declaration_cache ||= {}.compare_by_identity
            @declaration_cache[declaration] ||=
              VertexBuffer.__send__(:create_native_declaration, declaration)
          end

          def release_declarations
            cache = @declaration_cache
            @declaration_cache = nil
            return if cache.nil?

            cache.each_value do |handle|
              CNA::Native.library.call("cna_vertex_declaration_destroy", handle)
            rescue CNA::NativeError
              nil
            end
            nil
          end

          def user_primitives(topology, bytes, declaration, offset, vertices, count)
            description = CNA::Native::Layouts::UserPrimitives.new
            description.write_u32(8, topology.to_i)
            description.write_u32(12, CNA::Native::Manifest::CONSTANTS.fetch("CNA_USER_VERTEX_SOURCE_RAW_STREAM"))
            description.write_pointer(16, Fiddle::Pointer[bytes])
            description.write_u64(24, native_declaration_for(declaration))
            description.write_i32(32, offset)
            description.write_i32(36, vertices)
            description.write_i32(40, count)
            description
          end

          # `BeginUserPrimitives` unbinds every vertex stream and clears the instance-stream mask,
          # and it runs **before** the draw — so the streams go whether the draw succeeds or not.
          # Neither is restored, so it is observable through `GetVertexBuffers`, and it is this
          # projection's cache to clear because that cache is what the getter answers.
          def begin_user_primitives
            @vertex_buffer_bindings = []
            nil
          end

          # `GetVertexCount`: the vertices one topology needs for a primitive count.
          def vertex_count_for(topology, count)
            case topology.to_i
            when 0 then count * 3      # TriangleList
            when 1 then count + 2      # TriangleStrip
            when 2 then count * 2      # LineList
            when 3 then count + 1      # LineStrip
            else 0xFFFFFFFF            # ldc.i4.m1, compared unsigned, so an unknown topology never fits
            end
          end

          # `GetElementCountFromPrimitiveType`, which is the same four cases — XNA has two helpers
          # with identical bodies, one for vertices and one for indices, and both are reproduced
          # under their own names because the two draws call different ones.
          def element_count_for(topology, count) = vertex_count_for(topology, count)

          def require_primitive_count(value)
            count = CNA::Runtime::Numeric.int32(value, "primitiveCount")
            raise ::RangeError, "primitiveCount" unless count.positive?

            count
          end

          # `instanceStreamMask`: XNA records whether any bound stream carries a non-zero
          # `InstanceFrequency`, and the two non-instanced draw calls refuse while one does. The
          # cached bindings are that record here.
          def require_no_instance_frequency
            return unless @vertex_buffer_bindings.any? { |binding| binding.InstanceFrequency.positive? }

            raise ::RuntimeError, "NonZeroInstanceFrequency"
          end

          # `InvalidDevice`: a resource belongs to the device that made it.
          def require_same_device(resource)
            return if resource.GraphicsDevice.equal?(self)

            raise ::RuntimeError, "InvalidDevice"
          end

          # ------------------------------------------------------------ raising the six events
          #
          # XNA's raisers are `raise_*` and private; an event's whole public surface is add/remove,
          # which is why none of these is reachable from a consumer.

          def raise_Disposing = self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          def raise_DeviceLost = self.DeviceLost.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          def raise_DeviceReset = self.DeviceReset.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          def raise_DeviceResetting = self.DeviceResetting.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)

          # `FireCreatedEvent(object resource)`, and the two details a paraphrase loses. XNA keeps
          # **one** `ResourceCreatedEventArgs` per device, constructs it on the first raise and
          # afterwards writes the new resource into `_resource` on the same object -- so every
          # handler of every raise sees the same args instance. And it **nulls `_resource` after
          # the handlers return**, so a handler that stashes the args and reads `Resource` later
          # gets null. Both are reproduced.
          def fire_created_event(resource)
            args = (@created_event_args ||= ResourceCreatedEventArgs.__send__(:new, resource))
            args.__send__(:resource=, resource)
            begin
              self.ResourceCreated.__send__(:dispatch, self, args)
            ensure
              args.__send__(:resource=, nil)
            end
            nil
          end

          # `FireDestroyedEvent(string name, object tag)`, the same cached-args shape -- and
          # deliberately **without** the trailing null: the IL ends at `ret` immediately after
          # `Invoke`, so a destroyed resource's name and tag stay readable on the args afterwards
          # where a created resource does not.
          def fire_destroyed_event(name, tag)
            args = (@destroyed_event_args ||= ResourceDestroyedEventArgs.__send__(:new, name, tag))
            args.__send__(:assign, name, tag)
            self.ResourceDestroyed.__send__(:dispatch, self, args)
            nil
          end

          # ------------------------------------------------------------ the native subscriptions
          #
          # One subscription per data-free identity, made at the **first moment a device handle
          # exists** -- the same "earliest reachable moment" argument `ensure_initial_device_state`
          # records -- and released when the device is invalidated. The header states that a
          # registration "keeps the game alive in the same way an owned graphics resource does",
          # so leaving one behind would hold the game open.
          #
          # The two resource events are **not** subscribed. They fire -- measured, for a `Texture2D`
          # this binding creates -- and CNA carries presence only, deliberately: "no native object
          # pointer crosses the ABI", because the canonical event is raised while the resource is
          # still under construction. XNA's args carry the resource, its name and its tag, and this
          # projection has all three, because the resource is a Ruby object it constructed and
          # `Name`/`Tag` are managed properties CNA never sees. Raising them from
          # `GraphicsResource` -- which is where `DeviceResourceManager.AddTrackedObject` and
          # `ReleaseAllReferences` raise them in XNA -- is both more faithful and the only way to
          # fill the args at all.
          def subscribe_device_events(handle)
            return unless @event_registrations.nil?

            @event_registrations = []
            library = CNA::Native.library
            NATIVE_EVENTS.each do |constant, raiser|
              callback = device_event_callback(raiser)
              @event_callbacks << callback
              output = library.pointer_for("Q", 0)
              library.call("cna_graphics_device_subscribe_event", handle,
                           CNA::Native::Manifest::CONSTANTS.fetch(constant), callback, 0, output)
              @event_registrations << output[0, 8].unpack1("Q")
            end
            nil
          end

          def unsubscribe_device_events
            registrations = @event_registrations
            @event_registrations = []
            @event_callbacks = []
            return if registrations.nil?

            registrations.each do |registration|
              CNA::Native.library.function("cna_graphics_device_unsubscribe").call(registration)
            end
            nil
          end

          # The callback returns `void`, so a failure has nowhere to travel back through and
          # **nothing may escape into C**. A handler's exception is captured and re-raised by the
          # Ruby frame that caused the event -- `Reset` drains it directly, and anything raised
          # outside a Ruby-initiated call is handed to the Game host's pending channel when the
          # callback ends, which is exactly the discipline `Game`'s own events follow.
          def device_event_callback(raiser)
            Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID,
                                             [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP]) do |_device, _context|
              begin
                __send__(raiser) if @pending_event_exception.nil?
              rescue Exception => exception # rubocop:disable Lint/RescueException
                @pending_event_exception ||= exception
              end
              nil
            end
          end

          # Drains whatever a handler raised, so the caller that provoked it sees it.
          def drain_event_exception
            exception = @pending_event_exception
            @pending_event_exception = nil
            raise exception if exception

            nil
          end

          # The device's own disposal, and where `Disposing` is raised — `~GraphicsResource()`'s
          # analogue for the device itself. It is raised **before** the flag is set, so a handler
          # still sees a live device, and exactly once, because this method returns early on a
          # second call. Handler exceptions are not swallowed and are not captured either: this is
          # a Ruby frame, so an exception propagates to `Game#Dispose`, which already collects the
          # first error from each teardown step.
          def invalidate
            return nil if @invalidated

            unsubscribe_device_events
            release_declarations
            begin
              raise_Disposing
            ensure
              @invalidated = true
              @callback_handle = 0
            end
            nil
          end

          # The two cached property objects, cleared when the device is reset. XNA replaces
          # `pPublicCachedParams` on reset and `_displayMode` survives it, so only the first is
          # dropped here; both are seeded lazily on the next read.
          def invalidate_presentation_parameters
            @presentation_parameters = nil
            @internal_presentation_parameters = nil
          end

          def enter_callback(handle)
            @callback_handle = handle
            subscribe_device_events(handle) unless handle.zero?
            handle
          end

          # An event raised outside a Ruby-initiated call has no frame to surface in, so it is
          # handed to the Game host's pending channel as the callback ends -- the next lifecycle
          # boundary refuses and `finish` raises it, which is what `Game`'s own event exceptions do.
          def leave_callback
            exception = @pending_event_exception
            @pending_event_exception = nil
            @game.__send__(:record_callback_exception, exception) if exception
            @callback_handle = 0
          end

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
        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        #     SamplerState get_Item(int index) {
        #         if (index < 0 || index >= pSamplerList.Length)
        #             throw new ArgumentOutOfRangeException("index");
        #         return pSamplerList[index];
        #     }
        #
        #     void set_Item(int index, SamplerState value) {
        #         if (index < 0 || index >= pSamplerList.Length)
        #             throw new ArgumentOutOfRangeException("index");
        #         if (value == null)
        #             throw new ArgumentNullException("value", FrameworkResources.NullNotAllowed);
        #         if (value == pSamplerList[index]) return;          // reference equality
        #         value.Apply(pDevice, samplerOffset + index);
        #         pSamplerList[index] = value;
        #     }
        #
        # Three details a paraphrase loses, and each is measured rather than described. The getter
        # answers the **cache**, not the device, so it is one array read and asks CNA nothing. The
        # setter refuses `null` where `TextureCollection`'s accepts it — the two collections really
        # do differ there. And the short-circuit is **reference** equality, so assigning a
        # value-identical but distinct state does reach the device while re-assigning the same
        # object does not.
        class SamplerStateCollection
          MAX_SAMPLERS = CNA::Native::Manifest::CONSTANTS.fetch("CNA_MAX_SAMPLERS")

          private_class_method :new

          # DEVIATION, recorded: XNA's `InitializeDeviceState` — `assembly`, called when the device
          # is created or reset — nulls every slot and then applies `SamplerState.LinearWrap` to
          # each, leaving the cache holding that object. This binding does not own device creation
          # (`docs/graphics-device-service-producer-audit.md` is why), so there is no hook at which
          # to apply it, and applying sixteen states from a property getter would be a write XNA
          # performs somewhere else. Instead the cache is seeded with the same object, and that the
          # device really is in that state is **measured** through
          # `cna_graphics_device_get_sampler_state` rather than assumed.
          def initialize(device, stage)
            @device = device
            @stage = stage
            @slots = Array.new(MAX_SAMPLERS) { SamplerState::LinearWrap }
          end

          def [](index) = @slots[validated(index)]

          def []=(index, value)
            slot = validated(index)
            raise ArgumentError, "value" if value.nil?
            raise TypeError, "value must be a SamplerState" unless value.instance_of?(SamplerState)
            return value if value.equal?(@slots[slot])

            apply(value, slot)
            @slots[slot] = value
            value
          end

          private

          # `SamplerState.Apply(device, index)` is `assembly` in XNA and is not a projected identity;
          # what it does is push the whole descriptor into one sampler slot, which is exactly
          # `cna_graphics_device_set_sampler_state`.
          def apply(state, slot)
            descriptor = state.__send__(:to_native_descriptor)
            CNA::Native.library.call("cna_graphics_device_set_sampler_state",
                                     @device.__send__(:native_handle), @stage, slot, descriptor.pointer)
          end

          # What the device itself reports for one slot. XNA has no such member — its getter answers
          # the cache — so this is reachable for the tests that measure the cache against the device
          # and for nothing else.
          def device_state(index)
            slot = validated(index)
            descriptor = CNA::Native::Layouts::SamplerState.new
            CNA::Native.library.call("cna_graphics_device_get_sampler_state",
                                     @device.__send__(:native_handle), @stage, slot, descriptor.pointer)
            descriptor
          end

          def validated(index)
            slot = CNA::Runtime::Numeric.int32(index, "index")
            raise ::RangeError, "index" if slot.negative? || slot >= MAX_SAMPLERS

            slot
          end
        end

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

          # `DeviceResourceManager.AddTrackedObject(this, …)` is what every concrete XNA resource
          # calls once its native object exists, and `AddTrackedObject` is what calls
          # `GraphicsDevice.FireCreatedEvent(resource)`. This is the same moment: the handle is
          # live, `GraphicsDevice` is set, and the Ruby object is still inside its own constructor —
          # which is exactly the "still under construction" caveat CNA's own header records as its
          # reason for reporting presence only.
          def initialize_resource(device, handle, release)
            @GraphicsDevice = device
            @Name = nil
            @Tag = nil
            initialize_native_resource(device.__send__(:game), handle, release)
            device.__send__(:fire_created_event, self)
          end
          private :initialize_resource

          # The four graphics state objects are `GraphicsResource` subclasses that own **no native
          # handle and no device**: their constructors call `Object::.ctor()` and then `SetDefaults`,
          # so `GraphicsDevice` really is null on a freshly built one and stays null until the
          # `assembly`-visible `Apply` binds it -- which is not a projected identity. So they need a
          # managed disposal flag rather than a handle's, and `IsDisposed` consults whichever the
          # instance actually has.
          def initialize_managed_resource
            @GraphicsDevice = nil
            @Name = nil
            @Tag = nil
            @managed_disposed = false
          end
          private :initialize_managed_resource

          def IsDisposed = @native_handle.nil? ? @managed_disposed == true : @native_handle.disposed?

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

            device = @GraphicsDevice
            if @native_handle.nil?
              @managed_disposed = true
            else
              @native_handle.dispose
              @native_game.__send__(:unregister_native_child, self)
            end
            # `DeviceResourceManager.ReleaseAllReferences` is what raises the device's
            # `ResourceDestroyed`, and each concrete type calls it from `ReleaseNativeObject` —
            # the native release, which runs before `~GraphicsResource()` raises `Disposing`. So the
            # order is release, then the device's event, then this resource's own. A state object
            # has no device and XNA's never reach `AddTrackedObject`, so neither raises anything.
            # `GraphicsDevice` is what XNA's field is typed as, and `DeviceResourceManager` is that
            # device's. A state object has none, and a test double that stands in for one is not a
            # device either — neither has a resource manager to raise from.
            device.__send__(:fire_destroyed_event, @Name, @Tag) if device.instance_of?(GraphicsDevice)
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

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        #     private void SetDefaults() {
        #         ColorSourceBlend = Blend.One;   ColorDestinationBlend = Blend.Zero;
        #         ColorBlendFunction = BlendFunction.Add;
        #         AlphaSourceBlend = Blend.One;   AlphaDestinationBlend = Blend.Zero;
        #         AlphaBlendFunction = BlendFunction.Add;
        #         ColorWriteChannels = ColorWriteChannels1 = ColorWriteChannels2 =
        #             ColorWriteChannels3 = ColorWriteChannels.All;
        #         BlendFactor = Color.White;      MultiSampleMask = -1;
        #     }
        #
        # The four presets are one private constructor `(sourceBlend, destinationBlend, name)` that
        # runs `SetDefaults`, assigns the pair to **both** the colour and the alpha channels, sets
        # `Name`, and sets `isBound` -- so `BlendState.Opaque.ColorSourceBlend = …` raises where the
        # same assignment on `new BlendState` succeeds, and both directions are measured.
        class BlendState < GraphicsResource
          include CNA::Runtime::GraphicsState
          public_class_method :new

          state_property :ColorSourceBlend, Blend
          state_property :ColorDestinationBlend, Blend
          state_property :ColorBlendFunction, BlendFunction
          state_property :AlphaSourceBlend, Blend
          state_property :AlphaDestinationBlend, Blend
          state_property :AlphaBlendFunction, BlendFunction
          state_property :ColorWriteChannels, ColorWriteChannels
          state_property :ColorWriteChannels1, ColorWriteChannels
          state_property :ColorWriteChannels2, ColorWriteChannels
          state_property :ColorWriteChannels3, ColorWriteChannels
          state_property :BlendFactor, Microsoft::Xna::Framework::Color
          state_property :MultiSampleMask, :int32

          def initialize
            initialize_managed_resource
            @is_bound = false
            set_defaults
          end

          private

          def set_defaults
            self.ColorSourceBlend = Blend::One
            self.ColorDestinationBlend = Blend::Zero
            self.ColorBlendFunction = BlendFunction::Add
            self.AlphaSourceBlend = Blend::One
            self.AlphaDestinationBlend = Blend::Zero
            self.AlphaBlendFunction = BlendFunction::Add
            self.ColorWriteChannels = ColorWriteChannels::All
            self.ColorWriteChannels1 = ColorWriteChannels::All
            self.ColorWriteChannels2 = ColorWriteChannels::All
            self.ColorWriteChannels3 = ColorWriteChannels::All
            self.BlendFactor = Microsoft::Xna::Framework::Color.White
            self.MultiSampleMask = -1
          end

          # The `CNA_BlendState` POD, filled from this object's own values.
          def to_native_descriptor
            descriptor = CNA::Native::Layouts::BlendState.new
            descriptor.write_u32(8, @AlphaBlendFunction.to_i)
            descriptor.write_u32(12, @AlphaDestinationBlend.to_i)
            descriptor.write_u32(16, @AlphaSourceBlend.to_i)
            descriptor.write_u32(20, @ColorBlendFunction.to_i)
            descriptor.write_u32(24, @ColorDestinationBlend.to_i)
            descriptor.write_u32(28, @ColorSourceBlend.to_i)
            descriptor.write_u32(32, @ColorWriteChannels.to_i)
            descriptor.write_u32(36, @ColorWriteChannels1.to_i)
            descriptor.write_u32(40, @ColorWriteChannels2.to_i)
            descriptor.write_u32(44, @ColorWriteChannels3.to_i)
            descriptor.write_u8(48, @BlendFactor.R); descriptor.write_u8(49, @BlendFactor.G)
            descriptor.write_u8(50, @BlendFactor.B); descriptor.write_u8(51, @BlendFactor.A)
            descriptor.write_i32(52, @MultiSampleMask)
            descriptor
          end

          def self.preset(source, destination, name)
            state = new
            state.ColorSourceBlend = source
            state.ColorDestinationBlend = destination
            state.AlphaSourceBlend = source
            state.AlphaDestinationBlend = destination
            state.__send__(:bind_as_preset!, name)
            state
          end
          private_class_method :preset

          Opaque = preset(Blend::One, Blend::Zero, "BlendState.Opaque")
          AlphaBlend = preset(Blend::One, Blend::InverseSourceAlpha, "BlendState.AlphaBlend")
          Additive = preset(Blend::SourceAlpha, Blend::One, "BlendState.Additive")
          NonPremultiplied = preset(Blend::SourceAlpha, Blend::InverseSourceAlpha,
                                    "BlendState.NonPremultiplied")
        end

        # Derived from the same IL.
        #
        #     private void SetDefaults() {
        #         DepthBufferEnable = true; DepthBufferWriteEnable = true;
        #         DepthBufferFunction = CompareFunction.LessEqual;
        #         StencilEnable = false; StencilFunction = CompareFunction.Always;
        #         StencilPass = StencilFail = StencilDepthBufferFail = StencilOperation.Keep;
        #         TwoSidedStencilMode = false;
        #         CounterClockwiseStencilFunction = CompareFunction.Always;
        #         CounterClockwiseStencilPass = CounterClockwiseStencilFail =
        #             CounterClockwiseStencilDepthBufferFail = StencilOperation.Keep;
        #         StencilMask = StencilWriteMask = -1; ReferenceStencil = 0;
        #     }
        #
        # The three presets are one private constructor `(depthEnable, depthWriteEnable, name)`, so
        # `DepthStencilState.DepthRead` differs from `Default` in the write flag alone and `None`
        # turns both off. Everything else in all three is the defaults'.
        class DepthStencilState < GraphicsResource
          include CNA::Runtime::GraphicsState
          public_class_method :new

          state_property :DepthBufferEnable, :boolean
          state_property :DepthBufferWriteEnable, :boolean
          state_property :DepthBufferFunction, CompareFunction
          state_property :StencilEnable, :boolean
          state_property :StencilFunction, CompareFunction
          state_property :StencilPass, StencilOperation
          state_property :StencilFail, StencilOperation
          state_property :StencilDepthBufferFail, StencilOperation
          state_property :TwoSidedStencilMode, :boolean
          state_property :CounterClockwiseStencilFunction, CompareFunction
          state_property :CounterClockwiseStencilPass, StencilOperation
          state_property :CounterClockwiseStencilFail, StencilOperation
          state_property :CounterClockwiseStencilDepthBufferFail, StencilOperation
          state_property :StencilMask, :int32
          state_property :StencilWriteMask, :int32
          state_property :ReferenceStencil, :int32

          def initialize
            initialize_managed_resource
            @is_bound = false
            set_defaults
          end

          private

          def set_defaults
            self.DepthBufferEnable = true
            self.DepthBufferWriteEnable = true
            self.DepthBufferFunction = CompareFunction::LessEqual
            self.StencilEnable = false
            self.StencilFunction = CompareFunction::Always
            self.StencilPass = StencilOperation::Keep
            self.StencilFail = StencilOperation::Keep
            self.StencilDepthBufferFail = StencilOperation::Keep
            self.TwoSidedStencilMode = false
            self.CounterClockwiseStencilFunction = CompareFunction::Always
            self.CounterClockwiseStencilPass = StencilOperation::Keep
            self.CounterClockwiseStencilFail = StencilOperation::Keep
            self.CounterClockwiseStencilDepthBufferFail = StencilOperation::Keep
            self.StencilMask = -1
            self.StencilWriteMask = -1
            self.ReferenceStencil = 0
          end

          def to_native_descriptor
            descriptor = CNA::Native::Layouts::DepthStencilState.new
            descriptor.write_u8(8, @DepthBufferEnable ? 1 : 0)
            descriptor.write_u8(9, @DepthBufferWriteEnable ? 1 : 0)
            descriptor.write_u8(10, @StencilEnable ? 1 : 0)
            descriptor.write_u8(11, @TwoSidedStencilMode ? 1 : 0)
            descriptor.write_u32(12, @DepthBufferFunction.to_i)
            descriptor.write_u32(16, @StencilFunction.to_i)
            descriptor.write_i32(20, @StencilMask)
            descriptor.write_i32(24, @StencilWriteMask)
            descriptor.write_i32(28, @ReferenceStencil)
            descriptor.write_u32(32, @StencilFail.to_i)
            descriptor.write_u32(36, @StencilDepthBufferFail.to_i)
            descriptor.write_u32(40, @StencilPass.to_i)
            descriptor.write_u32(44, @CounterClockwiseStencilFunction.to_i)
            descriptor.write_u32(48, @CounterClockwiseStencilFail.to_i)
            descriptor.write_u32(52, @CounterClockwiseStencilDepthBufferFail.to_i)
            descriptor.write_u32(56, @CounterClockwiseStencilPass.to_i)
            descriptor
          end

          def self.preset(depth_enable, depth_write_enable, name)
            state = new
            state.DepthBufferEnable = depth_enable
            state.DepthBufferWriteEnable = depth_write_enable
            state.__send__(:bind_as_preset!, name)
            state
          end
          private_class_method :preset

          None = preset(false, false, "DepthStencilState.None")
          Default = preset(true, true, "DepthStencilState.Default")
          DepthRead = preset(true, false, "DepthStencilState.DepthRead")
        end

        # Derived from the same IL.
        #
        #     private void SetDefaults() {
        #         CullMode = CullMode.CullCounterClockwiseFace; FillMode = FillMode.Solid;
        #         ScissorTestEnable = false; MultiSampleAntiAlias = true;
        #         DepthBias = 0f; SlopeScaleDepthBias = 0f;
        #     }
        #
        # The three presets are one private constructor `(cullMode, name)`, so they differ from the
        # default state and from each other in the cull mode alone -- `CullCounterClockwise` is
        # value-identical to `new RasterizerState()` and is asserted to be.
        class RasterizerState < GraphicsResource
          include CNA::Runtime::GraphicsState
          public_class_method :new

          state_property :CullMode, CullMode
          state_property :FillMode, FillMode
          state_property :ScissorTestEnable, :boolean
          state_property :MultiSampleAntiAlias, :boolean
          state_property :DepthBias, :single
          state_property :SlopeScaleDepthBias, :single

          def initialize
            initialize_managed_resource
            @is_bound = false
            set_defaults
          end

          private

          def set_defaults
            self.CullMode = CullMode::CullCounterClockwiseFace
            self.FillMode = FillMode::Solid
            self.ScissorTestEnable = false
            self.MultiSampleAntiAlias = true
            self.DepthBias = 0.0
            self.SlopeScaleDepthBias = 0.0
          end

          def to_native_descriptor
            descriptor = CNA::Native::Layouts::RasterizerState.new
            descriptor.write_u32(8, @CullMode.to_i)
            descriptor.write_u32(12, @FillMode.to_i)
            descriptor.write_f32(16, @DepthBias)
            descriptor.write_f32(20, @SlopeScaleDepthBias)
            descriptor.write_u8(24, @MultiSampleAntiAlias ? 1 : 0)
            descriptor.write_u8(25, @ScissorTestEnable ? 1 : 0)
            descriptor
          end

          def self.preset(cull_mode, name)
            state = new
            state.CullMode = cull_mode
            state.__send__(:bind_as_preset!, name)
            state
          end
          private_class_method :preset

          CullNone = preset(CullMode::None, "RasterizerState.CullNone")
          CullClockwise = preset(CullMode::CullClockwiseFace, "RasterizerState.CullClockwise")
          CullCounterClockwise = preset(CullMode::CullCounterClockwiseFace,
                                        "RasterizerState.CullCounterClockwise")
        end

        # Derived from the same IL.
        #
        #     private void SetDefaults() {
        #         Filter = TextureFilter.Linear;
        #         AddressU = AddressV = AddressW = TextureAddressMode.Wrap;
        #         MaxAnisotropy = 4; MaxMipLevel = 0; MipMapLevelOfDetailBias = 0f;
        #     }
        #
        # The six presets are one private constructor `(filter, address, name)` that assigns the one
        # address mode to **all three** coordinates, which is why there is no `PointMirror` or
        # per-axis preset: the pair is the whole vocabulary.
        class SamplerState < GraphicsResource
          include CNA::Runtime::GraphicsState
          public_class_method :new

          state_property :Filter, TextureFilter
          state_property :AddressU, TextureAddressMode
          state_property :AddressV, TextureAddressMode
          state_property :AddressW, TextureAddressMode
          state_property :MaxAnisotropy, :int32
          state_property :MaxMipLevel, :int32
          state_property :MipMapLevelOfDetailBias, :single

          def initialize
            initialize_managed_resource
            @is_bound = false
            set_defaults
          end

          private

          def set_defaults
            self.Filter = TextureFilter::Linear
            self.AddressU = TextureAddressMode::Wrap
            self.AddressV = TextureAddressMode::Wrap
            self.AddressW = TextureAddressMode::Wrap
            self.MaxAnisotropy = 4
            self.MaxMipLevel = 0
            self.MipMapLevelOfDetailBias = 0.0
          end

          def to_native_descriptor
            descriptor = CNA::Native::Layouts::SamplerState.new
            descriptor.write_u32(8, @AddressU.to_i)
            descriptor.write_u32(12, @AddressV.to_i)
            descriptor.write_u32(16, @AddressW.to_i)
            descriptor.write_u32(20, @Filter.to_i)
            descriptor.write_i32(24, @MaxAnisotropy)
            descriptor.write_i32(28, @MaxMipLevel)
            descriptor.write_f32(32, @MipMapLevelOfDetailBias)
            descriptor
          end

          def self.preset(filter, address, name)
            state = new
            state.Filter = filter
            state.AddressU = address
            state.AddressV = address
            state.AddressW = address
            state.__send__(:bind_as_preset!, name)
            state
          end
          private_class_method :preset

          PointWrap = preset(TextureFilter::Point, TextureAddressMode::Wrap, "SamplerState.PointWrap")
          PointClamp = preset(TextureFilter::Point, TextureAddressMode::Clamp, "SamplerState.PointClamp")
          LinearWrap = preset(TextureFilter::Linear, TextureAddressMode::Wrap, "SamplerState.LinearWrap")
          LinearClamp = preset(TextureFilter::Linear, TextureAddressMode::Clamp, "SamplerState.LinearClamp")
          AnisotropicWrap = preset(TextureFilter::Anisotropic, TextureAddressMode::Wrap,
                                   "SamplerState.AnisotropicWrap")
          AnisotropicClamp = preset(TextureFilter::Anisotropic, TextureAddressMode::Clamp,
                                    "SamplerState.AnisotropicClamp")
        end

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # It reached the frontier carrying **two** blockers, `NATIVE_RUNTIME` and
        # `INTERFACE_PRODUCER_MISSING`, and both name members the pinned contract never selects:
        # `Bind`/`Unbind` are `assembly` and reach `DeclarationManager`, and the only caller of
        # `IVertexType::get_VertexDeclaration` is the `assembly` static `FromType`. The public
        # surface is two constructors, `VertexStride`, `GetVertexElements` and the inherited
        # `Dispose` -- managed to the last member, exactly as the four state objects were.
        #
        #     public VertexDeclaration(params VertexElement[] elements) {
        #         if (elements == null || elements.Length == 0)
        #             throw new ArgumentNullException("elements", FrameworkResources.NullNotAllowed);
        #         _elements = (VertexElement[])elements.Clone();
        #         _vertexStride = VertexElementValidator.GetVertexStride(_elements);
        #         VertexElementValidator.Validate(_vertexStride, _elements);
        #     }
        #
        # The two-argument form is the same with the stride supplied instead of computed. Two
        # details a paraphrase loses: an **empty** array raises `ArgumentNullException`, not
        # `ArgumentException`, and the elements are cloned on the way in *and* on the way out, so
        # neither the caller's array nor the one `GetVertexElements` returns is the declaration's.
        class VertexDeclaration < GraphicsResource
          public_class_method :new

          # `VertexElementValidator.GetTypeSize`, which is one `switch` over the twelve declared
          # formats and `0` for anything else. Ruby's enum projection makes "anything else"
          # unreachable, so the default is not carried.
          FORMAT_SIZES = { "Single" => 4, "Vector2" => 8, "Vector3" => 12, "Vector4" => 16,
                           "Color" => 4, "Byte4" => 4, "Short2" => 4, "Short4" => 8,
                           "NormalizedShort2" => 4, "NormalizedShort4" => 8,
                           "HalfVector2" => 4, "HalfVector4" => 8 }.freeze

          attr_reader :VertexStride

          def initialize(*arguments)
            stride = arguments.first.instance_of?(::Integer) ? arguments.shift : nil
            elements = arguments.length == 1 && arguments.first.instance_of?(::Array) ? arguments.first : arguments
            raise ArgumentError, "elements" if elements.nil? || elements.empty?
            unless elements.all? { |element| element.instance_of?(VertexElement) }
              raise TypeError, "elements must be VertexElement"
            end

            initialize_managed_resource
            # `Array.Clone` on a `VertexElement[]` copies the structs, so the declaration owns its
            # own values; Ruby's `VertexElement` is an object, so the copy has to be element-wise.
            @elements = elements.map(&:dup).freeze
            @VertexStride = stride.nil? ? self.class.__send__(:vertex_stride_of, @elements) : CNA::Runtime::Numeric.int32(stride, "vertexStride")
            self.class.__send__(:validate!, @VertexStride, @elements)
          end

          # `(VertexElement[])_elements.Clone()` — a fresh array every call, and mutating what it
          # answers changes nothing.
          def GetVertexElements = @elements.map(&:dup)

          class << self
            # `max over the elements of (Offset + GetTypeSize(Format))`, starting at zero. It is a
            # maximum rather than a sum, so elements may be declared in any order and gaps are kept.
            def vertex_stride_of(elements)
              elements.reduce(0) do |stride, element|
                extent = element.Offset + FORMAT_SIZES.fetch(element.VertexElementFormat.to_s)
                extent > stride ? extent : stride
              end
            end
            private :vertex_stride_of

            # `VertexElementValidator.Validate`, in the IL's order. The usage-range check it opens
            # with is unreachable from Ruby -- `VertexElementUsage` is a projected enum, so an
            # out-of-range usage cannot be constructed -- and is therefore not reproduced.
            def validate!(stride, elements)
              raise ::RangeError, "vertexStride" unless stride.positive?
              raise ArgumentError, "vertex element offset is not a multiple of four" unless (stride & 3).zero?

              occupied = Array.new(stride)
              elements.each_with_index do |element, index|
                size = FORMAT_SIZES.fetch(element.VertexElementFormat.to_s)
                if element.Offset.negative? || element.Offset + size > stride
                  raise ArgumentError,
                        "vertex element #{element.VertexElementUsage}#{element.UsageIndex} lies outside the vertex stride"
                end
                raise ArgumentError, "vertex element offset is not a multiple of four" unless (element.Offset & 3).zero?

                elements[0, index].each do |earlier|
                  next unless earlier.VertexElementUsage == element.VertexElementUsage &&
                              earlier.UsageIndex == element.UsageIndex

                  raise ArgumentError,
                        "duplicate vertex element #{element.VertexElementUsage}#{element.UsageIndex}"
                end

                (element.Offset...(element.Offset + size)).each do |byte|
                  unless occupied[byte].nil?
                    other = elements[occupied[byte]]
                    raise ArgumentError,
                          "vertex elements #{other.VertexElementUsage}#{other.UsageIndex} and " \
                          "#{element.VertexElementUsage}#{element.UsageIndex} overlap"
                  end
                  occupied[byte] = index
                end
              end
              nil
            end
            private :validate!
          end
        end

        class Texture < GraphicsResource
          attr_reader :LevelCount, :Format
          private_class_method :new

          # XNA's own transfer helpers are `static` members of **`Texture`** — `GetAndValidateSizes`,
          # `GetAndValidateRect` and `ValidateTotalSize` — with `Helpers.ValidateCopyParameters`
          # beside them, and `Texture2D`, `Texture3D` and `TextureCube` each call the same four from
          # their own `CopyData`. They live here for the same reason.
          #
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
            private

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

            # `Helpers.ValidateCopyParameters(startIndex, elementCount, data.Length)`, in its own
            # order and with its own parameter names: the first check names **`"dataIndex"`**, not
            # the public parameter's `startIndex`.
            def validate_copy_parameters(start_index, element_count, length)
              raise ::RangeError, "dataIndex" if start_index.negative? || start_index > length
              raise ::RangeError, "elementCount" if start_index + element_count > length
              raise ::RangeError, "elementCount" unless element_count.positive?

              nil
            end

            # `Texture.GetAndValidateSizes<T>` — `ArgumentException(InvalidDataSize)` unless the
            # element size equals the format's byte size or divides it exactly.
            def validate_sizes(element_size, format_size)
              return if element_size == format_size ||
                        (element_size < format_size && (format_size % element_size).zero?)

              raise ::ArgumentError, "invalid data size"
            end

            # `Texture.ValidateTotalSize` — the uncompressed branch; no DXT format is projected.
            def validate_total_size(element_count, element_size, texels, format_size)
              return if element_count * element_size == texels * format_size

              raise ::ArgumentError, "invalid total size"
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
        end

        class Texture2D < Texture
          attr_reader :Width, :Height, :Bounds

          # The two tables and the four validation helpers are `Texture`'s now, because XNA's own
          # are: `GetAndValidateSizes`, `GetAndValidateRect` and `ValidateTotalSize` are `static`
          # members of `Texture` that all three texture types call. These names are kept so a
          # consumer that reads them keeps reading them.
          TEXTURE_DATA_TYPES = Texture::TEXTURE_DATA_TYPES
          FORMAT_BYTE_SIZES = Texture::FORMAT_BYTE_SIZES

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
            data_type, element_size = Texture.__send__(:texture_data_type, type)
            packed = Texture.__send__(:pack_elements, type, data, start_index, element_count, element_size)
            transfer = build_transfer(level, rect, 0, element_count, element_size)
            CNA::Native.library.call("cna_texture2d_set_data", native_handle, data_type,
                                     transfer.pointer, Fiddle::Pointer[packed], element_count)
            nil
          end

          def GetData(type, *arguments)
            level, rect, data, start_index, element_count = transfer_arguments(type, arguments, "GetData")
            data_type, element_size = Texture.__send__(:texture_data_type, type)
            buffer = Fiddle::Pointer.malloc(element_size * element_count, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            transfer = build_transfer(level, rect, 0, element_count, element_size)
            CNA::Native.library.call("cna_texture2d_get_data", native_handle, data_type,
                                     transfer.pointer, buffer, element_count, required)
            Texture.__send__(:unpack_elements, type, buffer, data, start_index,
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
            _data_type, element_size = Texture.__send__(:texture_data_type, type)
            # `CopyData` opens `if (data == null || data.Length == 0) throw
            # ArgumentNullException("data", NullNotAllowed)`, so an **empty** array is the same
            # refusal as a null one. This used to answer `RangeError("elementCount")` for the empty
            # case, which is `ValidateCopyParameters`'s answer to a *different* question.
            raise ::ArgumentError, "data" if data.nil? || Texture.__send__(:element_length, type, data).zero?

            length = Texture.__send__(:element_length, type, data)
            start_index = arguments.length == 1 ? 0 : CNA::Runtime::Numeric.int32(arguments[-2], "startIndex")
            element_count = arguments.length == 1 ? length : CNA::Runtime::Numeric.int32(arguments[-1], "elementCount")
            Texture.__send__(:validate_copy_parameters, start_index, element_count, length)

            level = CNA::Runtime::Numeric.int32(level, "level")
            format_size = Texture.__send__(:format_byte_size, self.Format)
            Texture.__send__(:validate_sizes, element_size, format_size)

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
            Texture.__send__(:validate_total_size, element_count, element_size,
                             level_width * level_height, format_size)

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

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # `Texture3D` is `public auto ansi beforefieldinit` over `Texture`, **not sealed**, with one
        # public constructor, three read-only dimension properties, three `SetData<T>` overloads,
        # three `GetData<T>` and a `family` `Dispose(bool)` it inherits the contract of. The
        # `GraphicsDevice`-taking constructor forwards to a private `CreateTexture` whose validation
        # is, in order: a null device is
        # `ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`, then each of
        # `width`, `height` and `depth` in turn is
        # `ArgumentOutOfRangeException(name, ResourcesMustBeGreaterThanZeroSize)` when not positive.
        # Everything after that reads `GraphicsDevice._profileCapabilities` — `ValidVolumeFormats`,
        # `MaxVolumeExtent` — which is a **device** fact rather than a managed rule, so it is CNA's
        # to refuse, exactly as `Texture2D`'s is.
        #
        # DEVIATION, recorded: `cna_texture3d_set_data` and `cna_texture3d_get_data` take
        # `const CNA_Color*`, not the tagged `CNA_TextureDataType` the 2D routes take. XNA's
        # `SetData<T>` accepts any `T : struct` whose size divides the format's, so a
        # `Bgra4444[]` upload into a `Color` volume is legal there and has no C route here. The
        # managed validation still runs in XNA's order and the refusal is
        # `CNA::Runtime::NotSupportedError` — the projection of `System.NotSupportedException`,
        # which is what XNA itself raises when a profile cannot carry a request.
        class Texture3D < Texture
          public_class_method :new

          attr_reader :Width, :Height, :Depth

          def initialize(graphicsDevice, width, height, depth, mipMap, format)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            texels_wide = CNA::Runtime::Numeric.int32(width, "width")
            texels_high = CNA::Runtime::Numeric.int32(height, "height")
            texels_deep = CNA::Runtime::Numeric.int32(depth, "depth")
            raise ::RangeError, "width" unless texels_wide.positive?
            raise ::RangeError, "height" unless texels_high.positive?
            raise ::RangeError, "depth" unless texels_deep.positive?
            raise ::TypeError, "mipMap" unless mipMap == true || mipMap == false
            raise ::TypeError, "format" unless format.instance_of?(SurfaceFormat)

            create_info = CNA::Native::Layouts::Texture3DCreateInfo.new
            create_info.write_u32(8, texels_wide)
            create_info.write_u32(12, texels_high)
            create_info.write_u32(16, texels_deep)
            create_info.write_u8(20, mipMap ? 1 : 0)
            create_info.write_u32(24, format.to_i)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_texture3d_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_native(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          # Three overloads each, collapsed onto arity with the generic type argument leading — the
          # rule `ContentManager.Load` established for `!!0` and `Texture2D` follows:
          #
          #     SetData(type, data)
          #     SetData(type, data, startIndex, elementCount)
          #     SetData(type, level, left, top, right, bottom, front, back, data, startIndex, elementCount)
          #
          # The first two forward with the **level-zero** box `(0, 0, 0, Width, Height, 0, Depth)`,
          # which is what the IL passes: `_width`, `_height` and `_depth` rather than the level's.
          def SetData(type, *arguments)
            level, box, data, start_index, element_count = transfer_arguments(type, arguments, "SetData")
            colors = self.class.__send__(:require_color_elements, type, "cna_texture3d_set_data")
            packed = Texture.__send__(:pack_elements, type, data, start_index, element_count, colors)
            transfer = build_transfer(level, box, 0, element_count)
            CNA::Native.library.call("cna_texture3d_set_data", native_handle, transfer.pointer,
                                     Fiddle::Pointer[packed], element_count)
            nil
          end

          def GetData(type, *arguments)
            level, box, data, start_index, element_count = transfer_arguments(type, arguments, "GetData")
            colors = self.class.__send__(:require_color_elements, type, "cna_texture3d_get_data")
            buffer = Fiddle::Pointer.malloc(colors * element_count, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            transfer = build_transfer(level, box, 0, element_count)
            CNA::Native.library.call("cna_texture3d_get_data", native_handle, transfer.pointer,
                                     buffer, element_count, required)
            Texture.__send__(:unpack_elements, type, buffer, data, start_index,
                             required[0, 8].unpack1("Q"), colors)
            nil
          end

          private

          def transfer_arguments(type, arguments, member)
            raise CNA::DisposedObjectError, "Texture3D is disposed" if self.IsDisposed
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)

            case arguments.length
            when 1, 3
              level = 0
              box = [0, 0, self.Width, self.Height, 0, self.Depth]
              data = arguments[0]
            when 10
              level = arguments[0]
              box = arguments[1, 6]
              data = arguments[7]
            else
              raise ::ArgumentError, "#{member} takes (type, data), (type, data, startIndex, " \
                                     "elementCount) or (type, level, left, top, right, bottom, " \
                                     "front, back, data, startIndex, elementCount)"
            end

            _identity, element_size = Texture.__send__(:texture_data_type, type)
            raise ::ArgumentError, "data" if data.nil? || Texture.__send__(:element_length, type, data).zero?

            length = Texture.__send__(:element_length, type, data)
            start_index = arguments.length == 1 ? 0 : CNA::Runtime::Numeric.int32(arguments[-2], "startIndex")
            element_count = arguments.length == 1 ? length : CNA::Runtime::Numeric.int32(arguments[-1], "elementCount")
            Texture.__send__(:validate_copy_parameters, start_index, element_count, length)

            level = CNA::Runtime::Numeric.int32(level, "level")
            box = box.each_with_index.map { |value, index| CNA::Runtime::Numeric.int32(value, BOX_NAMES[index]) }
            format_size = Texture.__send__(:format_byte_size, self.Format)
            Texture.__send__(:validate_sizes, element_size, format_size)

            extent = self.class.__send__(:validate_box, box, level_extent(level))
            Texture.__send__(:validate_total_size, element_count, element_size,
                             extent.reduce(:*), format_size)
            [level, box, data, start_index, element_count]
          end

          BOX_NAMES = %w[left top right bottom front back].freeze
          private_constant :BOX_NAMES

          def level_extent(level)
            [[self.Width >> level, 1].max, [self.Height >> level, 1].max, [self.Depth >> level, 1].max]
          end

          def build_transfer(level, box, start_index, element_count)
            transfer = CNA::Native::Layouts::Texture3DTransfer.new
            transfer.write_i32(8, level)
            transfer.write_i32(12, box[0])
            transfer.write_i32(16, box[1])
            transfer.write_i32(20, box[2])
            transfer.write_i32(24, box[3])
            transfer.write_i32(28, box[4])
            transfer.write_i32(32, box[5])
            transfer.write_u64(40, start_index)
            transfer.write_u64(48, element_count)
            transfer
          end

          def initialize_from_native(device, handle)
            release = lambda { |value| CNA::Native.library.call("cna_texture3d_destroy", value) }
            initialize_resource(device, handle, release)
            info = CNA::Native::Layouts::Texture3DInfo.new
            CNA::Native.library.call("cna_texture3d_get_info", native_handle, info.pointer)
            @Width = info.read_u32(8)
            @Height = info.read_u32(12)
            @Depth = info.read_u32(16)
            @LevelCount = info.read_u32(20)
            @Format = SurfaceFormat.coerce(info.read_u32(24))
            self
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            else
              release&.call(handle)
            end
            raise
          end

          class << self
            private

            # `Texture3D.GetAndValidateBox`, whose comparisons are **unsigned** — `bgt.un`/`bge.un` —
            # so a negative coordinate wraps to a huge value and is refused by the same test. The
            # failure is `ArgumentException(InvalidRectangle, "box")`.
            def validate_box(box, extent)
              left, top, right, bottom, front, back = box
              width, height, depth = extent
              unsigned = ->(value) { value.negative? ? value + (1 << 32) : value }
              invalid = unsigned.call(right) > width || unsigned.call(left) >= unsigned.call(right) ||
                        unsigned.call(bottom) > height || unsigned.call(top) >= unsigned.call(bottom) ||
                        unsigned.call(back) > depth || unsigned.call(front) >= unsigned.call(back)
              raise ::ArgumentError, "box" if invalid

              [right - left, bottom - top, back - front]
            end

            def require_color_elements(type, route)
              return 4 if type == Microsoft::Xna::Framework::Color

              raise CNA::Runtime::NotSupportedError,
                    "#{route} carries only Color elements; XNA accepts any element type whose size " \
                    "divides the format's, and the canonical C ABI has no route for one here"
            end
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # `TextureCube` has the same shape as `Texture3D` with a face in place of a depth: one
        # public constructor, one `Size` property, three `SetData<T>`/`GetData<T>` overloads each
        # taking a `CubeMapFace` first, and a `family` `Dispose(bool)`. Its `CreateTexture` refuses a
        # null device the same way, and its `ValidateCreationParameters` refuses a non-positive
        # `size` with `ArgumentOutOfRangeException("size", ResourcesMustBeGreaterThanZeroSize)`
        # before the `ValidCubeFormats`/`MaxCubeSize` profile checks that are the device's.
        #
        # The same recorded deviation applies: `cna_texturecube_set_data`/`get_data` carry only
        # `CNA_Color`.
        class TextureCube < Texture
          public_class_method :new

          attr_reader :Size

          def initialize(graphicsDevice, size, mipMap, format)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            edge = CNA::Runtime::Numeric.int32(size, "size")
            raise ::RangeError, "size" unless edge.positive?
            raise ::TypeError, "mipMap" unless mipMap == true || mipMap == false
            raise ::TypeError, "format" unless format.instance_of?(SurfaceFormat)

            create_info = CNA::Native::Layouts::TextureCubeCreateInfo.new
            create_info.write_u32(8, edge)
            create_info.write_u8(12, mipMap ? 1 : 0)
            create_info.write_u32(16, format.to_i)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_texturecube_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_native(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          #     SetData(type, face, data)
          #     SetData(type, face, data, startIndex, elementCount)
          #     SetData(type, face, level, rect, data, startIndex, elementCount)
          def SetData(type, *arguments)
            face, level, rect, data, start_index, element_count = transfer_arguments(type, arguments, "SetData")
            colors = Texture3D.__send__(:require_color_elements, type, "cna_texturecube_set_data")
            packed = Texture.__send__(:pack_elements, type, data, start_index, element_count, colors)
            transfer = build_transfer(face, level, rect, 0, element_count)
            CNA::Native.library.call("cna_texturecube_set_data", native_handle, transfer.pointer,
                                     Fiddle::Pointer[packed], element_count)
            nil
          end

          def GetData(type, *arguments)
            face, level, rect, data, start_index, element_count = transfer_arguments(type, arguments, "GetData")
            colors = Texture3D.__send__(:require_color_elements, type, "cna_texturecube_get_data")
            buffer = Fiddle::Pointer.malloc(colors * element_count, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            transfer = build_transfer(face, level, rect, 0, element_count)
            CNA::Native.library.call("cna_texturecube_get_data", native_handle, transfer.pointer,
                                     buffer, element_count, required)
            Texture.__send__(:unpack_elements, type, buffer, data, start_index,
                             required[0, 8].unpack1("Q"), colors)
            nil
          end

          private

          def transfer_arguments(type, arguments, member)
            raise CNA::DisposedObjectError, "TextureCube is disposed" if self.IsDisposed
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)

            case arguments.length
            when 2, 4 then face, level, rect, data = arguments[0], 0, nil, arguments[1]
            when 6 then face, level, rect, data = arguments[0], arguments[1], arguments[2], arguments[3]
            else
              raise ::ArgumentError, "#{member} takes (type, face, data), (type, face, data, " \
                                     "startIndex, elementCount) or (type, face, level, rect, data, " \
                                     "startIndex, elementCount)"
            end
            face = CubeMapFace.coerce(face)

            _identity, element_size = Texture.__send__(:texture_data_type, type)
            raise ::ArgumentError, "data" if data.nil? || Texture.__send__(:element_length, type, data).zero?

            length = Texture.__send__(:element_length, type, data)
            start_index = arguments.length == 2 ? 0 : CNA::Runtime::Numeric.int32(arguments[-2], "startIndex")
            element_count = arguments.length == 2 ? length : CNA::Runtime::Numeric.int32(arguments[-1], "elementCount")
            Texture.__send__(:validate_copy_parameters, start_index, element_count, length)

            level = CNA::Runtime::Numeric.int32(level, "level")
            format_size = Texture.__send__(:format_byte_size, self.Format)
            Texture.__send__(:validate_sizes, element_size, format_size)

            edge = [self.Size >> level, 1].max
            width, height = edge, edge
            if rect
              raise ::TypeError, "rect must be a Rectangle" unless rect.instance_of?(Rectangle)
              # Texture.GetAndValidateRect, the same helper Texture2D uses.
              if rect.X.negative? || rect.Width <= 0 || rect.Y.negative? || rect.Height <= 0 ||
                 rect.Left + rect.Width > edge || rect.Top + rect.Height > edge
                raise ::ArgumentError, "rect"
              end

              width, height = rect.Width, rect.Height
            end
            Texture.__send__(:validate_total_size, element_count, element_size, width * height, format_size)
            [face, level, rect, data, start_index, element_count]
          end

          def build_transfer(face, level, rect, start_index, element_count)
            transfer = CNA::Native::Layouts::TextureCubeTransfer.new
            transfer.write_u32(8, face.to_i)
            transfer.write_i32(12, level)
            transfer.write_u8(16, rect ? 1 : 0)
            if rect
              transfer.write_i32(20, rect.X)
              transfer.write_i32(24, rect.Y)
              transfer.write_i32(28, rect.Width)
              transfer.write_i32(32, rect.Height)
            end
            transfer.write_u64(40, start_index)
            transfer.write_u64(48, element_count)
            transfer
          end

          def initialize_from_native(device, handle)
            release = lambda { |value| CNA::Native.library.call("cna_texturecube_destroy", value) }
            initialize_resource(device, handle, release)
            info = CNA::Native::Layouts::TextureCubeInfo.new
            CNA::Native.library.call("cna_texturecube_get_info", native_handle, info.pointer)
            @Size = info.read_u32(8)
            @LevelCount = info.read_u32(12)
            @Format = SurfaceFormat.coerce(info.read_u32(16))
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

        # ----------------------------------------------------------------- the vertex/index buffers
        #
        # Derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # Four classes and one struct. `VertexBuffer` and `IndexBuffer` derive from
        # `GraphicsResource` and are **not** sealed -- the dynamic forms derive from them -- and each
        # declares two public constructors that differ only in how the element layout is given: a
        # `System.Type` that XNA resolves through `VertexDeclaration.FromType`, or the layout itself.
        #
        # ## Which CNA route carries which overload, and why
        #
        # XNA's `SetData<T>` is generic over any struct. CNA's **typed** vertex transfer carries only
        # its seven built-in `CNA_VertexType` layouts, so the static overloads use the `_raw` family,
        # which takes bytes, a vertex count and a stride and accepts any layout. The dynamic
        # overloads need `SetDataOptions`, which the raw family carries only in a route 0.21.0 added
        # and the retired 0.7.0 headers do not declare -- so they use the typed route, whose transfer
        # has carried the options in both versions. The cost is recorded rather than hidden: a
        # dynamic `SetData` accepts the four projected vertex structs and refuses another element
        # type, where XNA accepts any.
        class VertexBuffer < GraphicsResource
          public_class_method :new
          attr_reader :VertexDeclaration, :VertexCount, :BufferUsage

          # CNA's seven built-in vertex identities, and the four this binding projects a type for.
          # A dynamic `SetData` needs one of these because it is the typed route that carries the
          # streaming option.
          NATIVE_VERTEX_TYPES = {
            "VertexPositionColor" => "CNA_VERTEX_TYPE_POSITION_COLOR",
            "VertexPositionColorTexture" => "CNA_VERTEX_TYPE_POSITION_COLOR_TEXTURE",
            "VertexPositionNormalTexture" => "CNA_VERTEX_TYPE_POSITION_NORMAL_TEXTURE",
            "VertexPositionTexture" => "CNA_VERTEX_TYPE_POSITION_TEXTURE"
          }.freeze

          # `VertexBuffer(GraphicsDevice, Type, int, BufferUsage)` resolves the type through
          # `VertexDeclaration.FromType`, which is `assembly`-visible in XNA and therefore not a
          # projected identity -- but it is exactly what a `Type` argument means here, so the
          # constructor does what it does: take the type's own `VertexDeclaration`.
          #
          # The validation, in the IL's order: a null device is
          # `ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`, a null
          # declaration or type is `ArgumentNullException`, and a non-positive count is
          # `ArgumentOutOfRangeException("vertexCount", ResourcesMustBeGreaterThanZeroSize)`.
          def initialize(graphicsDevice, vertexDeclarationOrType, vertexCount, bufferUsage)
            declaration = self.class.__send__(:resolve_declaration, vertexDeclarationOrType)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            count = CNA::Runtime::Numeric.int32(vertexCount, "vertexCount")
            raise ::RangeError, "vertexCount" unless count.positive?
            raise ::TypeError, "bufferUsage" unless bufferUsage.instance_of?(BufferUsage)

            # XNA's `VertexDeclaration` is a `GraphicsResource` with **no native handle** here: its
            # whole projected surface is managed, so the buffer builds the native declaration CNA
            # needs from the managed one's elements and its own stride, owns it, and destroys it
            # with itself.
            @native_declaration = self.class.__send__(:create_native_declaration, declaration)
            create_info = CNA::Native::Layouts::VertexBufferCreateInfo.new
            create_info.write_u64(8, @native_declaration)
            create_info.write_i32(16, count)
            create_info.write_u32(20, bufferUsage.to_i)
            create_info.write_u8(24, dynamic? ? 1 : 0)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_vertex_buffer_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            @VertexDeclaration = declaration
            initialize_from_native(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          #     SetData(type, data)
          #     SetData(type, data, startIndex, elementCount)
          #     SetData(type, offsetInBytes, data, startIndex, elementCount, vertexStride)
          def SetData(type, *arguments)
            window = transfer_arguments(type, arguments, "SetData")
            bytes = self.class.__send__(:pack_elements, type, window.fetch(:data),
                                        window.fetch(:start_index), window.fetch(:element_count),
                                        window.fetch(:element_size))
            CNA::Native.library.call("cna_vertex_buffer_set_data_raw_at", native_handle,
                                     window.fetch(:offset), Fiddle::Pointer[bytes], bytes.bytesize,
                                     window.fetch(:vertex_count), window.fetch(:stride))
            nil
          end

          def GetData(type, *arguments)
            window = transfer_arguments(type, arguments, "GetData")
            bytes = window.fetch(:span)
            buffer = Fiddle::Pointer.malloc([bytes, 1].max, Fiddle::RUBY_FREE)
            buffer[0, [bytes, 1].max] = "\0" * [bytes, 1].max
            CNA::Native.library.call("cna_vertex_buffer_get_data_raw", native_handle,
                                     window.fetch(:offset), buffer, bytes,
                                     window.fetch(:vertex_count), window.fetch(:stride))
            self.class.__send__(:unpack_elements, type, buffer, window.fetch(:data),
                                window.fetch(:start_index), window.fetch(:element_count),
                                window.fetch(:element_size))
            nil
          end

          private

          # `false` here and overridden by `DynamicVertexBuffer`; XNA carries the same distinction in
          # the `BufferUsage`/pool it passes to `CreateBuffer`.
          def dynamic? = false

          # `SetData(data)` and `SetData(data, startIndex, elementCount)` both forward to the
          # five-argument form with `vertexStride = 0`, and `CopyData`'s IL reads a zero stride as
          # "tightly packed": the gap it adds between elements is zero, so the bytes touched are
          # `elementCount * sizeof(T)`. A non-zero stride must be **at least** `sizeof(T)` --
          # `ArgumentOutOfRangeException("vertexStride", VertexStrideTooSmall)` otherwise -- and the
          # span the copy touches is then `sizeof(T) + (elementCount - 1) * vertexStride`, which
          # must fit inside the buffer from `offsetInBytes` or the IL throws
          # `InvalidOperationException(ResourceDataMustBeCorrectSize)`.
          def transfer_arguments(type, arguments, member)
            raise CNA::DisposedObjectError, "VertexBuffer is disposed" if self.IsDisposed
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)

            case arguments.length
            when 1 then offset, data, rest, given_stride = 0, arguments[0], [], 0
            when 3 then offset, data, rest, given_stride = 0, arguments[0], arguments[1, 2], 0
            when 5 then offset, data, rest, given_stride = arguments[0], arguments[1], arguments[2, 2], arguments[4]
            else
              raise ::ArgumentError, "#{member} takes (type, data), (type, data, startIndex, " \
                                     "elementCount) or (type, offsetInBytes, data, startIndex, " \
                                     "elementCount, vertexStride)"
            end
            raise ::ArgumentError, "data" if data.nil?

            element_size = self.class.__send__(:element_size, type)
            length = self.class.__send__(:element_length, type, data)
            start_index = rest.empty? ? 0 : CNA::Runtime::Numeric.int32(rest[0], "startIndex")
            element_count = rest.empty? ? length : CNA::Runtime::Numeric.int32(rest[1], "elementCount")
            Texture.__send__(:validate_copy_parameters, start_index, element_count, length)

            stride = CNA::Runtime::Numeric.int32(given_stride, "vertexStride")
            raise ::RangeError, "vertexStride" if stride.negative?

            gap = stride.zero? ? 0 : stride - element_size
            raise ::RangeError, "vertexStride" if gap.negative?

            offset = CNA::Runtime::Numeric.int32(offset, "offsetInBytes")
            raise ::RangeError, "offsetInBytes" if offset.negative?

            span = (element_count * element_size) + ([element_count - 1, 0].max * gap)
            declaration_stride = self.VertexDeclaration.VertexStride
            unless offset + span <= self.VertexCount * declaration_stride
              raise ::RuntimeError, "ResourceDataMustBeCorrectSize"
            end

            # MAPPING LIMITATION, measured: CNA's raw routes take a stride and refuse any value but
            # the buffer's own declaration stride -- "The vertex stride does not match this
            # VertexBuffer's VertexDeclaration" -- and they address whole vertices. A tightly packed
            # window that starts on a vertex boundary and covers whole vertices is exactly that
            # transfer under a different name, and is passed through as one. A strided window --
            # XNA's way of rewriting one component of every vertex -- has no route here.
            unless gap.zero? && (offset % declaration_stride).zero? && (span % declaration_stride).zero?
              raise CNA::Runtime::NotSupportedError,
                    "CNA's raw vertex routes address whole vertices at the buffer's own " \
                    "declaration stride (#{declaration_stride}); XNA's strided and partial-vertex " \
                    "windows have no route"
            end

            { offset: offset, data: data, start_index: start_index, element_count: element_count,
              element_size: element_size, span: span, stride: declaration_stride,
              vertex_count: span / declaration_stride }
          end

          # The native declaration is this buffer's, so it goes when the buffer does.
          public

          def Dispose(disposing = true)
            return if self.IsDisposed

            handle = @native_declaration
            super
            if handle
              begin
                CNA::Native.library.call("cna_vertex_declaration_destroy", handle)
              rescue CNA::NativeError
                nil
              end
              @native_declaration = nil
            end
            nil
          end

          class << self
            private

            def create_native_declaration(declaration)
              elements = declaration.GetVertexElements
              buffer = Fiddle::Pointer.malloc([16 * elements.length, 1].max, Fiddle::RUBY_FREE)
              buffer[0, [16 * elements.length, 1].max] = "\0" * [16 * elements.length, 1].max
              elements.each_with_index do |element, index|
                buffer[16 * index, 16] = [element.Offset, element.VertexElementFormat.to_i,
                                          element.VertexElementUsage.to_i, element.UsageIndex].pack("l4")
              end
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_vertex_declaration_create_with_stride",
                                       declaration.VertexStride, buffer, elements.length, output)
              output[0, 8].unpack1("Q")
            end

            # `VertexDeclaration.FromType` for a `Type`, the value itself for a declaration.
            def resolve_declaration(value)
              raise ::ArgumentError, "vertexDeclaration" if value.nil?
              return value if value.instance_of?(Graphics.const_get(:VertexDeclaration))
              unless value.is_a?(::Module) && value.const_defined?(:VertexDeclaration, false)
                raise ::TypeError, "expected a VertexDeclaration or a type declaring one"
              end

              value.const_get(:VertexDeclaration, false)
            end

            def element_length(type, data)
              return data.bytesize if type == ::String && data.is_a?(::String)
              raise ::TypeError, "data must be an Array of #{type}" unless data.is_a?(::Array)

              data.length
            end

            # `sizeof(T)`, for every element type this binding can lay out in a buffer: a vertex
            # struct is its declaration's stride, `Color`, `Single` and `Int32` are four bytes, and
            # a Ruby String -- XNA's `byte[]` -- is one.
            def element_size(type)
              return 1 if type == ::String
              return type.const_get(:VertexDeclaration, false).VertexStride if type.is_a?(::Module) &&
                                                                              type.include?(CNA::Runtime::VertexStruct)
              return 4 if [Microsoft::Xna::Framework::Color, ::Float, ::Integer].include?(type)

              raise ::TypeError, "#{type} is not a buffer element type"
            end

            def pack_elements(type, data, start_index, element_count, element_size)
              return data.byteslice(start_index, element_count).b if type == ::String

              slice = data[start_index, element_count]
              slice.each { |value| raise ::TypeError, "data must be an Array of #{type}" unless value.instance_of?(type) }
              if type.include?(CNA::Runtime::VertexStruct)
                slice.map { |value| value.__send__(:vertex_words).pack("V*") }.join
              elsif type == Microsoft::Xna::Framework::Color
                slice.map { |value| [value.PackedValue].pack("V") }.join
              elsif type == ::Float
                slice.pack("f*")
              elsif type == ::Integer
                slice.map { |value| [CNA::Runtime::Numeric.int32(value, "value")].pack("l") }.join
              else
                raise ::TypeError, "#{type} is not a buffer element type"
              end
            end

            def unpack_elements(type, buffer, data, start_index, element_count, element_size)
              bytes = buffer[0, element_size * element_count]
              if type == ::String
                raise ::ArgumentError, "data must not be frozen" if data.frozen?

                data[start_index, element_count] = bytes
                return data
              end
              if type.include?(CNA::Runtime::VertexStruct)
                declaration = type.const_get(:VertexDeclaration, false)
                element_count.times do |index|
                  data[start_index + index] = decode_vertex(type, declaration, bytes[index * element_size, element_size])
                end
              elsif type == Microsoft::Xna::Framework::Color
                bytes.unpack("V#{element_count}").each_with_index do |packed, index|
                  colour = Microsoft::Xna::Framework::Color.new(0, 0, 0, 0)
                  colour.PackedValue = packed
                  data[start_index + index] = colour
                end
              elsif type == ::Float
                bytes.unpack("f#{element_count}").each_with_index { |value, index| data[start_index + index] = value }
              elsif type == ::Integer
                bytes.unpack("l#{element_count}").each_with_index { |value, index| data[start_index + index] = value }
              else
                raise ::TypeError, "#{type} is not a buffer element type"
              end
              data
            end

            # A vertex struct's constructor takes its components in **declaration order**, which is
            # true of all four, so the declaration is enough to rebuild one.
            def decode_vertex(type, declaration, bytes)
              components = declaration.GetVertexElements.map do |element|
                offset = element.Offset
                case element.VertexElementFormat.to_s
                when "Vector3" then Vector3.new(*bytes[offset, 12].unpack("f3"))
                when "Vector2" then Vector2.new(*bytes[offset, 8].unpack("f2"))
                when "Color"
                  colour = Microsoft::Xna::Framework::Color.new(0, 0, 0, 0)
                  colour.PackedValue = bytes[offset, 4].unpack1("V")
                  colour
                else raise ::TypeError, "no decoder for VertexElementFormat.#{element.VertexElementFormat}"
                end
              end
              type.new(*components)
            end
          end

          private

          def initialize_from_native(device, handle)
            release = lambda { |value| CNA::Native.library.call("cna_vertex_buffer_destroy", value) }
            initialize_resource(device, handle, release)
            info = CNA::Native::Layouts::VertexBufferInfo.new
            CNA::Native.library.call("cna_vertex_buffer_get_info", native_handle, info.pointer)
            @VertexCount = info.read_i32(8)
            @BufferUsage = BufferUsage.coerce(info.read_u32(12))
            self
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            else
              release&.call(handle)
            end
            raise
          end

          def content_lost?
            info = CNA::Native::Layouts::VertexBufferInfo.new
            CNA::Native.library.call("cna_vertex_buffer_get_info", native_handle, info.pointer)
            info.read_u8(17) == 1
          end
        end

        # `DynamicVertexBuffer` adds the two option-bearing `SetData` overloads, `IsContentLost` and
        # the `ContentLost` event.
        #
        # DEVIATION, recorded: the option-bearing route is CNA's **typed** one, so its element type
        # must be one of the four vertex structs this binding projects. XNA accepts any struct there.
        # The static overloads it inherits keep the raw route and accept every element type.
        #
        # DEVIATION, recorded: `ContentLost` is projected as a subscribable event and **never
        # fires**. CNA exposes `cna_vertex_buffer_subscribe_content_lost`, and it is deliberately
        # unbound: `CNA_VertexBufferInfo::is_content_lost` is documented false on every renderer
        # family that cannot lose a device, which is all three qualified artifacts, so a bound
        # callback would be native surface with nothing to deliver.
        class DynamicVertexBuffer < VertexBuffer
          public_class_method :new
          extend CNA::Runtime::EventOwner
          xna_event :ContentLost

          def IsContentLost = content_lost?

          #     SetData(type, data, startIndex, elementCount, options)
          #     SetData(type, offsetInBytes, data, startIndex, elementCount, vertexStride, options)
          def SetData(type, *arguments)
            return super unless [4, 6].include?(arguments.length)

            options = SetDataOptions.coerce(arguments.last)
            identity = VertexBuffer::NATIVE_VERTEX_TYPES[type.to_s.split("::").last]
            if identity.nil?
              raise CNA::Runtime::NotSupportedError,
                    "the option-bearing route is CNA's typed one and carries only its built-in " \
                    "vertex layouts; XNA accepts any element type here"
            end

            window = transfer_arguments(type, arguments[0...-1], "SetData")
            transfer = CNA::Native::Layouts::VertexBufferTransfer.new
            transfer.write_u32(8, CNA::Native::Manifest::CONSTANTS.fetch(identity))
            transfer.write_u32(12, options.to_i)
            transfer.write_u64(16, 0)
            transfer.write_u64(24, window.fetch(:element_count))
            # The typed route replaces the whole contents, so it takes no byte offset; XNA's
            # option-bearing overload that does is refused rather than silently ignoring it.
            unless window.fetch(:offset).zero?
              raise CNA::Runtime::NotSupportedError,
                    "the typed route that carries SetDataOptions replaces the whole buffer and " \
                    "takes no byte offset"
            end

            bytes = self.class.__send__(:pack_elements, type, window.fetch(:data),
                                        window.fetch(:start_index), window.fetch(:element_count),
                                        window.fetch(:element_size))
            CNA::Native.library.call("cna_vertex_buffer_set_data", native_handle, transfer.pointer,
                                     Fiddle::Pointer[bytes], window.fetch(:element_count))
            nil
          end

          private

          def dynamic? = true
        end

        # `IndexBuffer`'s second constructor takes an `IndexElementSize` where the vertex buffer's
        # takes a declaration, and its `Type` form resolves `short` to sixteen bits and `int` to
        # thirty-two. Ruby has one `Integer`, so the type form accepts the projected enum's own two
        # identities and `Integer`, which is thirty-two bits -- the width XNA's `int` overload picks.
        class IndexBuffer < GraphicsResource
          public_class_method :new
          attr_reader :IndexCount, :IndexElementSize, :BufferUsage

          def initialize(graphicsDevice, indexElementSizeOrType, indexCount, bufferUsage)
            size = self.class.__send__(:resolve_element_size, indexElementSizeOrType)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            count = CNA::Runtime::Numeric.int32(indexCount, "indexCount")
            raise ::RangeError, "indexCount" unless count.positive?
            raise ::TypeError, "bufferUsage" unless bufferUsage.instance_of?(BufferUsage)

            create_info = CNA::Native::Layouts::IndexBufferCreateInfo.new
            create_info.write_i32(8, count)
            create_info.write_u32(12, size.to_i)
            create_info.write_u32(16, bufferUsage.to_i)
            create_info.write_u8(20, dynamic? ? 1 : 0)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_index_buffer_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_native(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          #     SetData(type, data)
          #     SetData(type, data, startIndex, elementCount)
          #     SetData(type, offsetInBytes, data, startIndex, elementCount)
          def SetData(type, *arguments)
            offset, data, start_index, element_count, options = index_arguments(type, arguments, "SetData")
            bytes = self.class.__send__(:pack_indices, data, start_index, element_count, index_width)
            transfer = index_transfer(element_count, options)
            # A zero offset is the whole-contents replacement `cna_index_buffer_set_data` performs,
            # which is what XNA's three-argument `SetData` does; the windowed route composes on the
            # CPU and re-uploads, and documents that it refuses a `SetDataOptions` that contradicts
            # keeping the rest.
            if offset.zero?
              CNA::Native.library.call("cna_index_buffer_set_data", native_handle,
                                       transfer.pointer, Fiddle::Pointer[bytes], element_count)
            else
              CNA::Native.library.call("cna_index_buffer_set_data_at", native_handle, offset,
                                       transfer.pointer, Fiddle::Pointer[bytes], element_count)
            end
            nil
          end

          def GetData(type, *arguments)
            _offset, data, start_index, element_count, options = index_arguments(type, arguments, "GetData")
            width = index_width
            buffer = Fiddle::Pointer.malloc(width * element_count, Fiddle::RUBY_FREE)
            buffer[0, width * element_count] = "\0" * (width * element_count)
            written = CNA::Native.library.pointer_for("Q", 0)
            transfer = index_transfer(element_count, options)
            CNA::Native.library.call("cna_index_buffer_get_data", native_handle, transfer.pointer,
                                     buffer, element_count, written)
            self.class.__send__(:unpack_indices, buffer, data, start_index,
                                written[0, 8].unpack1("Q"), width)
            nil
          end

          private

          def dynamic? = false

          def index_width = self.IndexElementSize.to_s == "SixteenBits" ? 2 : 4

          def index_transfer(element_count, options)
            transfer = CNA::Native::Layouts::IndexBufferTransfer.new
            transfer.write_u32(8, self.IndexElementSize.to_i)
            transfer.write_u32(12, options)
            transfer.write_u64(16, 0)
            transfer.write_u64(24, element_count)
            transfer
          end

          def index_arguments(type, arguments, member)
            raise CNA::DisposedObjectError, "IndexBuffer is disposed" if self.IsDisposed
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)
            raise ::TypeError, "index elements are Integer" unless type == ::Integer

            # The overloads are told apart the way the CLR tells them apart: by the **first**
            # parameter. `(data, …)` and `(offsetInBytes, data, …)` are otherwise the same shapes,
            # and a four-argument list is `(data, startIndex, elementCount, options)` when it starts
            # with the array and `(offsetInBytes, data, startIndex, elementCount)` when it does not.
            # Counting arguments -- or their parity -- reads the elementCount of one as the options
            # of the other.
            options = 0
            if arguments[0].is_a?(::Array) || arguments[0].nil?
              offset = 0
              case arguments.length
              when 1 then data, rest = arguments[0], []
              when 3 then data, rest = arguments[0], arguments[1, 2]
              when 4
                raise ::ArgumentError, "#{member} takes no SetDataOptions on a static buffer" unless dynamic?

                data, rest = arguments[0], arguments[1, 2]
                options = SetDataOptions.coerce(arguments[3]).to_i
              else
                raise ::ArgumentError, "#{member} takes (type, data) or (type, data, startIndex, elementCount)"
              end
            else
              case arguments.length
              when 4 then offset, data, rest = arguments[0], arguments[1], arguments[2, 2]
              when 5
                raise ::ArgumentError, "#{member} takes no SetDataOptions on a static buffer" unless dynamic?

                offset, data, rest = arguments[0], arguments[1], arguments[2, 2]
                options = SetDataOptions.coerce(arguments[4]).to_i
              else
                raise ::ArgumentError, "#{member} takes (type, offsetInBytes, data, startIndex, elementCount)"
              end
            end
            raise ::ArgumentError, "data" if data.nil?
            raise ::TypeError, "data must be an Array of Integer" unless data.is_a?(::Array)

            start_index = rest.empty? ? 0 : CNA::Runtime::Numeric.int32(rest[0], "startIndex")
            element_count = rest.empty? ? data.length : CNA::Runtime::Numeric.int32(rest[1], "elementCount")
            Texture.__send__(:validate_copy_parameters, start_index, element_count, data.length)
            offset = CNA::Runtime::Numeric.int32(offset, "offsetInBytes")
            raise ::RangeError, "offsetInBytes" if offset.negative?

            # `CopyData`'s one size rule, and it is simpler than the vertex buffer's because an
            # index buffer has no stride: `sizeof(T) * elementCount + offsetInBytes` must fit, or
            # the IL throws `InvalidOperationException(ResourceDataMustBeCorrectSize)`. XNA reads
            # `sizeof(T)` from the caller's `short`/`int`; Ruby has one `Integer`, so the width is
            # the buffer's own -- which is the width the elements are packed at either way.
            width = index_width
            unless offset + (element_count * width) <= self.IndexCount * width
              raise ::RuntimeError, "ResourceDataMustBeCorrectSize"
            end

            [offset, data, start_index, element_count, options]
          end

          def initialize_from_native(device, handle)
            release = lambda { |value| CNA::Native.library.call("cna_index_buffer_destroy", value) }
            initialize_resource(device, handle, release)
            info = CNA::Native::Layouts::IndexBufferInfo.new
            CNA::Native.library.call("cna_index_buffer_get_info", native_handle, info.pointer)
            @IndexCount = info.read_i32(8)
            @IndexElementSize = Graphics.const_get(:IndexElementSize).coerce(info.read_u32(12))
            @BufferUsage = BufferUsage.coerce(info.read_u32(16))
            self
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            else
              release&.call(handle)
            end
            raise
          end

          def content_lost?
            info = CNA::Native::Layouts::IndexBufferInfo.new
            CNA::Native.library.call("cna_index_buffer_get_info", native_handle, info.pointer)
            info.read_u8(21) == 1
          end

          class << self
            private

            # `IndexBuffer(GraphicsDevice, Type, …)` accepts `short` and `int` in XNA; Ruby has one
            # `Integer`, which is the thirty-two-bit form, and the enum identities themselves.
            def resolve_element_size(value)
              raise ::ArgumentError, "indexElementSize" if value.nil?
              return value if value.instance_of?(Graphics.const_get(:IndexElementSize))
              return Graphics.const_get(:IndexElementSize)::ThirtyTwoBits if value == ::Integer

              raise ::TypeError, "expected an IndexElementSize or Integer"
            end

            def pack_indices(data, start_index, element_count, width)
              slice = data[start_index, element_count]
              format = width == 2 ? "v" : "V"
              slice.map do |value|
                number = CNA::Runtime::Numeric.int32(value, "value")
                raise ::RangeError, "value" if number.negative? || (width == 2 && number > 0xFFFF)

                [number].pack(format)
              end.join
            end

            def unpack_indices(buffer, data, start_index, count, width)
              format = width == 2 ? "v" : "V"
              buffer[0, width * count].unpack("#{format}#{count}").each_with_index do |value, index|
                data[start_index + index] = value
              end
              data
            end
          end
        end

        # The same two additions the dynamic vertex buffer makes, and the same recorded reason for
        # the event. Its option-bearing overloads carry no element-type restriction, because
        # `cna_index_buffer_set_data_at`'s transfer has always carried the options.
        class DynamicIndexBuffer < IndexBuffer
          public_class_method :new
          extend CNA::Runtime::EventOwner
          xna_event :ContentLost

          def IsContentLost = content_lost?

          private

          def dynamic? = true
        end

        # `VertexBufferBinding` is a `sealed` value type over three fields with three constructors
        # and an implicit conversion from a bare `VertexBuffer`. Ruby has no implicit conversion, so
        # `op_Implicit` projects as a class method the way every other XNA operator does.
        class VertexBufferBinding
          include CNA::Runtime::ValueSemantics
          attr_reader :VertexBuffer, :VertexOffset, :InstanceFrequency

          # `.ctor(VertexBuffer)` is `(buffer, 0, 0)` and `.ctor(VertexBuffer, int)` is
          # `(buffer, offset, 0)`; the three-argument form validates. A null buffer is
          # `ArgumentNullException("vertexBuffer")`, a negative offset or frequency is
          # `ArgumentOutOfRangeException`.
          def initialize(vertexBuffer, vertexOffset = 0, instanceFrequency = 0)
            raise ::ArgumentError, "vertexBuffer" if vertexBuffer.nil?
            unless vertexBuffer.is_a?(Graphics.const_get(:VertexBuffer))
              raise ::TypeError, "vertexBuffer must be a VertexBuffer"
            end

            offset = CNA::Runtime::Numeric.int32(vertexOffset, "vertexOffset")
            frequency = CNA::Runtime::Numeric.int32(instanceFrequency, "instanceFrequency")
            raise ::RangeError, "vertexOffset" if offset.negative?
            raise ::RangeError, "instanceFrequency" if frequency.negative?

            # The binding is built by CNA rather than assembled here, so the three values a consumer
            # reads are the ones the C ABI really holds.
            binding = CNA::Native::Layouts::VertexBufferBinding.new
            CNA::Native.library.call("cna_vertex_buffer_binding_init",
                                     vertexBuffer.__send__(:native_handle), offset, frequency,
                                     binding.pointer)
            @VertexBuffer = vertexBuffer
            @VertexOffset = binding.read_i32(8)
            @InstanceFrequency = binding.read_i32(12)
          end

          def self.op_Implicit(vertexBuffer) = new(vertexBuffer)

          # Every other value type in this projection overrides `GetHashCode` in its own IL, and
          # `ValueSemantics#hash` forwards to it. This one does not: `VertexBufferBinding` declares
          # no `Equals` and no `GetHashCode`, so what XNA has is `ValueType`'s -- field-wise
          # equality with a hash the CLR documents as unspecified. Publishing a `GetHashCode`
          # identity the pinned contract never selects would be inventing one, so `hash` is
          # answered over the same three components equality uses and nothing is claimed about its
          # value.
          def hash = value_components.hash

          private

          def value_components = [@VertexBuffer, @VertexOffset, @InstanceFrequency]
        end

        # `OcclusionQuery`, derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL
        # (SHA-256 560080fc…). Five fields, and the whole type is the state machine they make:
        #
        #   Begin()          _isInBeginEndPair          -> InvalidOperationException(EndMustBeCalledBeforeBegin)
        #                    !_hasIsCompleteBeenQueried -> InvalidOperationException(IsCompleteMustBeCalled)
        #                    then native begin, and _isAvailable false, _isInBeginEndPair true,
        #                    _hasCalledBegin true, _hasIsCompleteBeenQueried **false**
        #   End()            !_isInBeginEndPair         -> InvalidOperationException(BeginMustBeCalledBeforeEnd)
        #                    then native end, and _isInBeginEndPair false
        #   IsComplete       sets _hasIsCompleteBeenQueried true **first**, then answers false with
        #                    no native object or before any Begin, and otherwise asks the device and
        #                    records the pixel count when the answer is yes
        #   PixelCount       !IsComplete                -> InvalidOperationException(DataNotAvailable)
        #
        # The constructor sets `_hasIsCompleteBeenQueried` true, which is what lets the **first**
        # `Begin` through: every later one has to be preceded by an `IsComplete` read. That is the
        # rule a reader would not guess, and it is why `IsComplete` is not a pure query.
        #
        # DEVIATION, recorded: XNA refuses construction on a `GraphicsProfile` whose
        # `ProfileCapabilities.OcclusionQuery` is false -- `Reach` -- with `NotSupportedException`.
        # That is a device capability rather than a managed rule, and CNA answers the same question
        # from the backend: `cna_occlusion_query_create` reports `CNA_RESULT_NOT_SUPPORTED` where the
        # renderer has no query object, which surfaces as `CNA::CapabilityError`. No profile table is
        # invented here.
        class OcclusionQuery < GraphicsResource
          public_class_method :new

          def initialize(graphicsDevice)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_occlusion_query_create",
                                     graphicsDevice.__send__(:native_handle), output)
            handle = output[0, 8].unpack1("Q")
            release = lambda { |value| CNA::Native.library.call("cna_occlusion_query_destroy", value) }
            @pixel_count = 0
            @is_available = false
            @in_begin_end_pair = false
            @has_called_begin = false
            @has_is_complete_been_queried = true
            initialize_resource(graphicsDevice, handle, release)
          rescue Exception
            if defined?(@native_handle) && @native_handle
              self.Dispose
            elsif handle
              release&.call(handle)
            end
            raise
          end

          def Begin
            raise ::RuntimeError, "EndMustBeCalledBeforeBegin" if @in_begin_end_pair
            raise ::RuntimeError, "IsCompleteMustBeCalled" unless @has_is_complete_been_queried

            CNA::Native.library.call("cna_occlusion_query_begin", native_handle)
            @is_available = false
            @in_begin_end_pair = true
            @has_called_begin = true
            @has_is_complete_been_queried = false
            nil
          end

          def End
            raise ::RuntimeError, "BeginMustBeCalledBeforeEnd" unless @in_begin_end_pair

            CNA::Native.library.call("cna_occlusion_query_end", native_handle)
            @in_begin_end_pair = false
            nil
          end

          # The store happens before every early return, which is what makes a bare `IsComplete`
          # read enough to unblock the next `Begin` even when it answers false.
          def IsComplete
            @has_is_complete_been_queried = true
            return @is_available unless has_renderer?
            return @is_available unless @has_called_begin

            available = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_occlusion_query_get_is_complete", native_handle, available)
            @is_available = available[0, 4].unpack1("L") == 1
            @pixel_count = read_pixel_count if @is_available
            @is_available
          end

          def PixelCount
            raise ::RuntimeError, "DataNotAvailable" unless self.IsComplete

            @pixel_count
          end

          private

          # `pComPtr` in the IL: with no native query object `IsComplete` answers the field rather
          # than asking the device.
          def has_renderer?
            output = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_occlusion_query_has_renderer", native_handle, output)
            output[0, 4].unpack1("L") == 1
          end

          def read_pixel_count
            output = CNA::Native.library.pointer_for("l", 0)
            CNA::Native.library.call("cna_occlusion_query_get_pixel_count", native_handle, output)
            output[0, 4].unpack1("l")
          end
        end

        # One place to build a `VertexBufferBinding` from `SetVertexBuffer`'s two arities, so the
        # constructor's own validation is what refuses a bad offset rather than a second copy of it.
        module RenderTargetBindingSupport
          module_function

          def vertex_binding(buffer, offset = nil)
            offset.nil? ? VertexBufferBinding.new(buffer) : VertexBufferBinding.new(buffer, offset)
          end
        end
        private_constant :RenderTargetBindingSupport

        # `RenderTarget2D`, `RenderTargetCube` and the `RenderTargetBinding` that names one, derived
        # from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
        #
        # ## A render target is a texture, on both sides of the boundary
        #
        # XNA derives `RenderTarget2D` from `Texture2D` and `RenderTargetCube` from `TextureCube`,
        # and CNA agrees: `cna_texture2d_get_data` reads a 2D target back, which is what the renderer
        # qualification has been doing since Native frontier 6. So each type is its texture base with
        # a different creator and a different destroyer, and the whole inherited transfer surface
        # keeps working.
        #
        # ## The constructor negotiates rather than records
        #
        # `CreateRenderTarget` passes the caller's **preferred** format, depth format and sample count
        # through `GraphicsAdapter.QueryFormat`, which answers what the adapter can actually give, and
        # the `RenderTargetHelper` it then builds stores those answers -- which is what the three
        # properties read. CNA negotiates in the same place, inside its create route, and reports the
        # result through `cna_render_target_get_info`. This projection therefore reads all four values
        # back from the info rather than storing what was asked for; a target that asked for
        # `Depth24Stencil8` and got `None` reports `None`, exactly as XNA does.
        #
        # The managed validation that survives the negotiation is `Texture2D.ValidateCreationParameters`,
        # which is the same null-device and positive-size rule the texture bases already carry.
        module RenderTargetState
          # `_contentLost` latches: `get_IsContentLost` returns the field once it is true and
          # otherwise re-reads the device's own lost state into it. CNA's `is_content_lost` is the
          # same fact from the renderer's side -- true from a real device reset until the target is
          # next bound -- so the latch is kept and the field is what a second read answers.
          #
          # DEVIATION, recorded: `ContentLost` is projected as a subscribable event and **never
          # fires**, for the reason the dynamic buffers' does. `is_content_lost` is false on every
          # renderer family that cannot lose a device, which is all three qualified artifacts, and
          # `cna_render_target_subscribe_content_lost` exists only in 0.21.0, so binding it would
          # both deliver nothing and end the retired headers' admission.
          def IsContentLost
            return true if @content_lost

            @content_lost = render_target_info.read_u8(40) == 1
          end

          private

          def render_target_info
            info = CNA::Native::Layouts::RenderTargetInfo.new
            CNA::Native.library.call("cna_render_target_get_info", native_handle, info.pointer)
            info
          end

          # The four values the helper stores, read back from the negotiation that produced them.
          def adopt_render_target_state(info)
            @content_lost = false
            @Format = SurfaceFormat.coerce(info.read_u32(24))
            @DepthStencilFormat = Graphics.const_get(:DepthFormat).coerce(info.read_u32(28))
            @MultiSampleCount = info.read_i32(32)
            @RenderTargetUsage = Graphics.const_get(:RenderTargetUsage).coerce(info.read_u32(36))
          end

          def render_target_release
            lambda { |value| CNA::Native.library.call("cna_render_target_destroy", value) }
          end
        end
        private_constant :RenderTargetState

        class RenderTarget2D < Texture2D
          public_class_method :new
          include RenderTargetState
          extend CNA::Runtime::EventOwner
          xna_event :ContentLost
          attr_reader :RenderTargetUsage, :MultiSampleCount, :DepthStencilFormat

          # Three constructors, and the two short ones are the long one with the IL's own literals:
          # `(device, w, h)` is `mipMap false, Color, None, 0, DiscardContents` and
          # `(device, w, h, mipMap, format, depthFormat)` adds `0, DiscardContents`.
          def initialize(graphicsDevice, width, height, mipMap = false,
                         preferredFormat = SurfaceFormat::Color,
                         preferredDepthFormat = Graphics.const_get(:DepthFormat)::None,
                         preferredMultiSampleCount = 0,
                         usage = Graphics.const_get(:RenderTargetUsage)::DiscardContents)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            pixels_wide = CNA::Runtime::Numeric.int32(width, "width")
            pixels_high = CNA::Runtime::Numeric.int32(height, "height")
            raise ::RangeError, "width" unless pixels_wide.positive?
            raise ::RangeError, "height" unless pixels_high.positive?
            raise ::TypeError, "mipMap" unless mipMap == true || mipMap == false

            samples = CNA::Runtime::Numeric.int32(preferredMultiSampleCount, "preferredMultiSampleCount")
            create_info = CNA::Native::Layouts::RenderTarget2DCreateInfo.new
            create_info.write_u32(8, pixels_wide)
            create_info.write_u32(12, pixels_high)
            create_info.write_u8(16, mipMap ? 1 : 0)
            create_info.write_u32(20, SurfaceFormat.coerce(preferredFormat).to_i)
            create_info.write_u32(24, Graphics.const_get(:DepthFormat).coerce(preferredDepthFormat).to_i)
            create_info.write_i32(28, samples)
            create_info.write_u32(32, Graphics.const_get(:RenderTargetUsage).coerce(usage).to_i)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_render_target2d_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_render_target(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          private

          def initialize_from_render_target(device, handle)
            release = render_target_release
            initialize_resource(device, handle, release)
            info = render_target_info
            @Width = info.read_u32(12)
            @Height = info.read_u32(16)
            @LevelCount = info.read_u32(20)
            @Bounds = Rectangle.new(0, 0, @Width, @Height)
            adopt_render_target_state(info)
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

        # The cube's two constructors take an edge `size` where the 2D pair take width and height,
        # and it has no three-argument form: the shortest is
        # `(device, size, mipMap, format, depthFormat)`.
        class RenderTargetCube < TextureCube
          public_class_method :new
          include RenderTargetState
          extend CNA::Runtime::EventOwner
          xna_event :ContentLost
          attr_reader :RenderTargetUsage, :MultiSampleCount, :DepthStencilFormat

          def initialize(graphicsDevice, size, mipMap, preferredFormat, preferredDepthFormat,
                         preferredMultiSampleCount = 0,
                         usage = Graphics.const_get(:RenderTargetUsage)::DiscardContents)
            raise ::ArgumentError, "graphicsDevice" if graphicsDevice.nil?
            unless graphicsDevice.instance_of?(GraphicsDevice)
              raise ::TypeError, "graphicsDevice must be GraphicsDevice"
            end

            edge = CNA::Runtime::Numeric.int32(size, "size")
            raise ::RangeError, "size" unless edge.positive?
            raise ::TypeError, "mipMap" unless mipMap == true || mipMap == false

            samples = CNA::Runtime::Numeric.int32(preferredMultiSampleCount, "preferredMultiSampleCount")
            create_info = CNA::Native::Layouts::RenderTargetCubeCreateInfo.new
            create_info.write_u32(8, edge)
            create_info.write_u8(12, mipMap ? 1 : 0)
            create_info.write_u32(16, SurfaceFormat.coerce(preferredFormat).to_i)
            create_info.write_u32(20, Graphics.const_get(:DepthFormat).coerce(preferredDepthFormat).to_i)
            create_info.write_i32(24, samples)
            create_info.write_u32(28, Graphics.const_get(:RenderTargetUsage).coerce(usage).to_i)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_render_target_cube_create", graphicsDevice.__send__(:native_handle),
                                     create_info.pointer, output)
            initialize_from_render_target(graphicsDevice, output[0, 8].unpack1("Q"))
          end

          private

          def initialize_from_render_target(device, handle)
            release = render_target_release
            initialize_resource(device, handle, release)
            info = render_target_info
            @Size = info.read_u32(12)
            @LevelCount = info.read_u32(20)
            adopt_render_target_state(info)
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

        # A `sequential sealed` value type over two fields, and the whole type is two stores and two
        # `ldfld`s: the constructors check the target for null with `NullNotAllowed` and validate
        # nothing else, not even the cube face. `RenderTarget` is declared as `Texture`, which is why
        # a cube binding answers the cube.
        #
        # There is no `cna_render_target_binding_init` to build one with -- unlike `VertexBufferBinding`,
        # whose values CNA fills -- because the C structure is only ever consumed by
        # `cna_graphics_device_set_render_targets`, a `GraphicsDevice` member this binding has not
        # projected. So this one is assembled here, which is what XNA's own constructor does.
        class RenderTargetBinding
          include CNA::Runtime::ValueSemantics
          attr_reader :RenderTarget, :CubeMapFace

          def initialize(renderTarget, cubeMapFace = nil)
            raise ::ArgumentError, "renderTarget" if renderTarget.nil?

            if renderTarget.is_a?(Graphics.const_get(:RenderTargetCube))
              @CubeMapFace = Graphics.const_get(:CubeMapFace).coerce(
                cubeMapFace.nil? ? Graphics.const_get(:CubeMapFace)::PositiveX : cubeMapFace
              )
            elsif renderTarget.is_a?(Graphics.const_get(:RenderTarget2D))
              unless cubeMapFace.nil?
                raise ::ArgumentError, "RenderTargetBinding.new takes a cubeMapFace only with a RenderTargetCube"
              end

              @CubeMapFace = Graphics.const_get(:CubeMapFace)::PositiveX
            else
              raise ::TypeError, "renderTarget must be a RenderTarget2D or a RenderTargetCube"
            end
            @RenderTarget = renderTarget
          end

          def self.op_Implicit(renderTarget) = new(renderTarget)

          # XNA declares neither Equals nor GetHashCode here, so what it has is ValueType's --
          # field-wise equality with a hash the CLR leaves unspecified. See VertexBufferBinding.
          def hash = value_components.hash

          private

          def value_components = [@RenderTarget, @CubeMapFace]
        end

        # ------------------------------------------------------------------------ the Effect cluster
        #
        # Nine types derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256
        # 560080fc…). Eight of them are `sealed` with an `assembly` constructor, so `new` stays
        # private under Foundation 25's rule and the only producer is `Effect`; `Effect` itself is
        # the ninth and is the one type here a consumer constructs.
        #
        # ## What CNA hands out, and why the tree is built once
        #
        # Every getter in CNA's effect surface returns an **owned view**, freshly allocated on each
        # call: two `cna_effect_get_parameters` calls answer two different collection handles, and
        # two `cna_effect_parameter_collection_get_at(0)` calls answer two different parameter
        # handles naming the same parameter. Measured, not assumed.
        #
        # XNA's collections are the opposite: `Effect`'s constructor builds one
        # `List<EffectParameter>` and `get_Parameters` is a single `ldfld`, so `effect.Parameters[0]`
        # is the **same object** every time and reference equality is observable. A fresh native
        # handle is therefore not a new XNA object, and the projection builds the whole graph once —
        # parameters, their elements, structure members and annotations, techniques, their passes and
        # annotations — holding one Ruby object per logical child and one native view behind it. The
        # views are released when the `Effect` is disposed, in the order they were taken.
        class EffectParameter
          private_class_method :new
          attr_reader :Name, :Semantic, :RowCount, :ColumnCount, :ParameterClass, :ParameterType,
                      :Elements, :StructureMembers, :Annotations

          # `EffectParameterClass.Scalar` and `EffectParameterType.String`, the two identities the
          # getters' guards compare against, and the numeric texture types `GetValueTexture*` accept.
          SCALAR = 0
          VECTOR = 1
          MATRIX_CLASS = 2
          STRING_TYPE = 4
          TEXTURE_TYPE = 5
          private_constant :SCALAR, :VECTOR, :MATRIX_CLASS, :STRING_TYPE, :TEXTURE_TYPE

          # ------------------------------------------------------------------ the scalar getters
          #
          # `GetValueBoolean`, `GetValueInt32` and `GetValueSingle` share one guard, and it is
          # **`Elements`**, not `StructureMembers`:
          #
          #     if (_paramClass != Scalar && pElementCollection.Count == 0)
          #         throw new InvalidCastException();
          #
          # `pElementCollection` is what `get_Elements` returns; `pParamCollection` is
          # `StructureMembers`. The two are easy to swap and the IL is unambiguous.
          #
          # `System.InvalidCastException` is not in the thrown-exception register yet and this is
          # the first member here to raise it: the CLR raises it for a conversion that cannot be
          # performed, and Ruby's own `TypeError` is what `Integer("x")`-style bad conversions raise.
          def GetValueBoolean
            guard_numeric!
            read_value("CNA_EFFECT_VALUE_BOOLEAN", "L", 4) == 1
          end

          def GetValueInt32
            guard_numeric!
            read_value("CNA_EFFECT_VALUE_INT32", "l", 4)
          end

          def GetValueSingle
            guard_numeric!
            read_value("CNA_EFFECT_VALUE_SINGLE", "f", 4)
          end

          # ------------------------------------------------------------------ the vector getters
          #
          #     result = default;
          #     if (Elements.Count == 0) {
          #         if (ParameterClass == Scalar) { f = GetFloat(); broadcast f; return result; }
          #         if (ParameterClass != Vector) throw new InvalidCastException();
          #         if (!(ColumnCount == N && RowCount == 1)) throw new InvalidCastException();
          #     }
          #     v = GetVector();  // a float4 whatever the declared width
          #
          # The scalar branch really does broadcast: `GetValueVector3` on a scalar answers
          # `(f, f, f)`. `GetValueQuaternion` is the same shape with `ColumnCount == 4`.
          def GetValueVector2 = vector_value(2) { |c| Vector2.new(c[0], c[1]) }
          def GetValueVector3 = vector_value(3) { |c| Vector3.new(c[0], c[1], c[2]) }
          def GetValueVector4 = vector_value(4) { |c| Vector4.new(c[0], c[1], c[2], c[3]) }
          def GetValueQuaternion = vector_value(4) { |c| Quaternion.new(c[0], c[1], c[2], c[3]) }

          # `GetValueMatrix` and `GetValueMatrixTranspose` share the vector getters' first branch and
          # then check only the class — there is **no** row/column test:
          #
          #     if (Elements.Count == 0) {
          #         if (ParameterClass == Scalar) { f = GetFloat(); set all sixteen to f; return; }
          #         if (ParameterClass != Matrix) throw new InvalidCastException();
          #     }
          def GetValueMatrix = matrix_value("CNA_EFFECT_VALUE_MATRIX")
          def GetValueMatrixTranspose = matrix_value("CNA_EFFECT_VALUE_MATRIX_TRANSPOSE")

          # `if (_paramType != String) throw new InvalidCastException();` — the type, not the class.
          def GetValueString
            raise ::TypeError, "InvalidCastException" unless @ParameterType.to_i == STRING_TYPE

            CNA::Native.library.counted_string("cna_effect_parameter_get_value_string_byte_count",
                                               "cna_effect_parameter_copy_value_string", handle)
          end

          # Each texture getter accepts `Texture` **or** its own dimension:
          # `if (_paramType != Texture && _paramType != Texture2D) throw new InvalidCastException()`.
          # A native null answers `nil`, which is what XNA answers when the effect holds none.
          def GetValueTexture2D = texture_value(7, "CNA_EFFECT_TEXTURE_2D")
          def GetValueTexture3D = texture_value(8, "CNA_EFFECT_TEXTURE_3D")
          def GetValueTextureCube = texture_value(9, "CNA_EFFECT_TEXTURE_CUBE")

          # ------------------------------------------------------------------- the array getters
          #
          # Every one opens `if (count <= 0) throw new ArgumentOutOfRangeException();` and then
          # allocates `new T[count]` before reading, so a count larger than the parameter holds
          # answers a partly-filled array rather than raising. The element type decides what CNA is
          # asked for; the count it answers is the number it really had.
          def GetValueBooleanArray(count) = array_value(count, "CNA_EFFECT_VALUE_BOOLEAN", "L", 4) { |v| v == 1 }
          def GetValueInt32Array(count) = array_value(count, "CNA_EFFECT_VALUE_INT32", "l", 4)
          def GetValueSingleArray(count) = array_value(count, "CNA_EFFECT_VALUE_SINGLE", "f", 4)

          def GetValueVector2Array(count) = vector_array(count, "CNA_EFFECT_VALUE_VECTOR2", 2) { |c| Vector2.new(c[0], c[1]) }
          def GetValueVector3Array(count) = vector_array(count, "CNA_EFFECT_VALUE_VECTOR3", 3) { |c| Vector3.new(c[0], c[1], c[2]) }
          def GetValueVector4Array(count) = vector_array(count, "CNA_EFFECT_VALUE_VECTOR4", 4) { |c| Vector4.new(c[0], c[1], c[2], c[3]) }
          def GetValueQuaternionArray(count) = vector_array(count, "CNA_EFFECT_VALUE_QUATERNION", 4) { |c| Quaternion.new(c[0], c[1], c[2], c[3]) }
          def GetValueMatrixArray(count) = matrix_array(count, "CNA_EFFECT_VALUE_MATRIX")
          def GetValueMatrixTransposeArray(count) = matrix_array(count, "CNA_EFFECT_VALUE_MATRIX_TRANSPOSE")

          # ------------------------------------------------------------------------ the setters
          #
          # XNA declares eighteen `SetValue` overloads and two `SetValueTranspose`. Ruby has no
          # overloading and cannot dispatch on parameter type by declaration, so all eighteen
          # collapse into one method that dispatches on the **value's own Ruby class** — which is
          # exactly what the CLR's overload resolution does with the argument's type.
          def SetValue(value)
            write_value(value, transpose: false)
          end

          def SetValueTranspose(value)
            unless value.instance_of?(Matrix) || (value.is_a?(::Array) && value.all? { |item| item.instance_of?(Matrix) })
              raise ::TypeError, "SetValueTranspose takes a Matrix or an Array of Matrix"
            end

            write_value(value, transpose: true)
          end

          # ------------------------------------------------------------------------------ internals

          private

          def initialize_from_native(effect, handle)
            @effect = effect
            @handle = handle
            info = CNA::Native::Layouts::EffectParameterInfo.new
            CNA::Native.library.call("cna_effect_parameter_get_info", handle, info.pointer)
            @RowCount = info.read_i32(8)
            @ColumnCount = info.read_i32(12)
            @ParameterClass = EffectParameterClass.coerce(info.read_u32(16))
            @ParameterType = EffectParameterType.coerce(info.read_u32(20))
            @Name = CNA::Native.library.counted_string("cna_effect_parameter_get_name_byte_count",
                                                       "cna_effect_parameter_copy_name", handle)
            @Semantic = CNA::Native.library.counted_string("cna_effect_parameter_get_semantic_byte_count",
                                                           "cna_effect_parameter_copy_semantic", handle)
            @Elements = EffectParameterCollection.__send__(
              :from_native, effect, effect.__send__(:child_view, "cna_effect_parameter_get_elements",
                                                    "cna_effect_parameter_collection_destroy", handle)
            )
            @StructureMembers = EffectParameterCollection.__send__(
              :from_native, effect, effect.__send__(:child_view, "cna_effect_parameter_get_structure_members",
                                                    "cna_effect_parameter_collection_destroy", handle)
            )
            @Annotations = EffectAnnotationCollection.__send__(
              :from_native, effect, effect.__send__(:child_view, "cna_effect_parameter_get_annotations",
                                                    "cna_effect_annotation_collection_destroy", handle)
            )
            self
          end

          def handle
            raise CNA::DisposedObjectError, "the Effect that owns this EffectParameter is disposed" if @effect.IsDisposed

            @handle
          end

          def guard_numeric!
            return if @ParameterClass.to_i == SCALAR || @Elements.Count.positive?

            raise ::TypeError, "InvalidCastException"
          end

          def read_value(value_type, format, bytes)
            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            buffer[0, bytes] = "\0" * bytes
            CNA::Native.library.call("cna_effect_parameter_get_value",
                                     handle, CNA::Native::Manifest::CONSTANTS.fetch(value_type), buffer)
            buffer[0, bytes].unpack1(format)
          end

          def read_floats(value_type, count)
            buffer = Fiddle::Pointer.malloc(4 * count, Fiddle::RUBY_FREE)
            buffer[0, 4 * count] = "\0" * (4 * count)
            CNA::Native.library.call("cna_effect_parameter_get_value",
                                     handle, CNA::Native::Manifest::CONSTANTS.fetch(value_type), buffer)
            buffer[0, 4 * count].unpack("f#{count}")
          end

          def vector_value(columns)
            if @Elements.Count.zero?
              if @ParameterClass.to_i == SCALAR
                broadcast = read_value("CNA_EFFECT_VALUE_SINGLE", "f", 4)
                return yield([broadcast] * 4)
              end
              raise ::TypeError, "InvalidCastException" unless @ParameterClass.to_i == VECTOR
              raise ::TypeError, "InvalidCastException" unless @ColumnCount == columns && @RowCount == 1
            end
            yield read_floats("CNA_EFFECT_VALUE_VECTOR4", 4)
          end

          def matrix_value(value_type)
            if @Elements.Count.zero?
              if @ParameterClass.to_i == SCALAR
                broadcast = read_value("CNA_EFFECT_VALUE_SINGLE", "f", 4)
                return Matrix.new(*([broadcast] * 16))
              end
              raise ::TypeError, "InvalidCastException" unless @ParameterClass.to_i == MATRIX_CLASS
            end
            Matrix.new(*read_floats(value_type, 16))
          end

          def texture_value(dimension, texture_type)
            declared = @ParameterType.to_i
            unless declared == TEXTURE_TYPE || declared == dimension
              raise ::TypeError, "InvalidCastException"
            end

            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_parameter_get_value_texture", handle,
                                     CNA::Native::Manifest::CONSTANTS.fetch(texture_type), output)
            native = output[0, 8].unpack1("Q")
            native.zero? ? nil : @effect.__send__(:texture_for, native, dimension)
          end

          def array_count!(count)
            requested = CNA::Runtime::Numeric.int32(count, "count")
            raise ::RangeError, "count" unless requested.positive?

            requested
          end

          def read_array(value_type, count, element_bytes)
            buffer = Fiddle::Pointer.malloc(element_bytes * count, Fiddle::RUBY_FREE)
            buffer[0, element_bytes * count] = "\0" * (element_bytes * count)
            written = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_parameter_get_values", handle,
                                     CNA::Native::Manifest::CONSTANTS.fetch(value_type), count,
                                     buffer, count, written)
            [buffer, written[0, 8].unpack1("Q")]
          end

          def array_value(count, value_type, format, bytes)
            requested = array_count!(count)
            buffer, written = read_array(value_type, requested, bytes)
            values = buffer[0, bytes * written].unpack("#{format}#{written}")
            values = values.map { |value| yield(value) } if block_given?
            values + ::Array.new(requested - written) { block_given? ? yield(0) : (format == "f" ? 0.0 : 0) }
          end

          def vector_array(count, value_type, columns)
            requested = array_count!(count)
            buffer, written = read_array(value_type, requested, 4 * columns)
            floats = buffer[0, 4 * columns * written].unpack("f#{columns * written}")
            filled = ::Array.new(written) { |index| yield(floats[index * columns, columns]) }
            filled + ::Array.new(requested - written) { yield([0.0] * columns) }
          end

          def matrix_array(count, value_type)
            requested = array_count!(count)
            buffer, written = read_array(value_type, requested, 64)
            floats = buffer[0, 64 * written].unpack("f#{16 * written}")
            filled = ::Array.new(written) { |index| Matrix.new(*floats[index * 16, 16]) }
            filled + ::Array.new(requested - written) { Matrix.new(*([0.0] * 16)) }
          end

          # One dispatch table, keyed by the value's own class, replacing the CLR's overload
          # resolution. A `Texture` and a `String` are objects rather than tagged numeric values, so
          # each has its own route.
          def write_value(value, transpose:)
            case value
            when Texture then return write_texture(value)
            when ::String then return write_string(value)
            when true, false then return write_scalar("CNA_EFFECT_VALUE_BOOLEAN", [value ? 1 : 0].pack("L"))
            when ::Integer then return write_scalar("CNA_EFFECT_VALUE_INT32", [CNA::Runtime::Numeric.int32(value, "value")].pack("l"))
            when ::Float then return write_scalar("CNA_EFFECT_VALUE_SINGLE", [value].pack("f"))
            when Matrix then return write_scalar(transpose ? "CNA_EFFECT_VALUE_MATRIX_TRANSPOSE" : "CNA_EFFECT_VALUE_MATRIX", pack_matrix(value))
            when Quaternion then return write_scalar("CNA_EFFECT_VALUE_QUATERNION", [value.X, value.Y, value.Z, value.W].pack("f4"))
            when Vector4 then return write_scalar("CNA_EFFECT_VALUE_VECTOR4", [value.X, value.Y, value.Z, value.W].pack("f4"))
            when Vector3 then return write_scalar("CNA_EFFECT_VALUE_VECTOR3", [value.X, value.Y, value.Z].pack("f3"))
            when Vector2 then return write_scalar("CNA_EFFECT_VALUE_VECTOR2", [value.X, value.Y].pack("f2"))
            when nil then raise ::ArgumentError, "value"
            end
            return write_array(value, transpose: transpose) if value.is_a?(::Array)

            raise ::TypeError, "no SetValue overload takes #{value.class}"
          end

          def write_array(values, transpose:)
            raise ::ArgumentError, "value" if values.empty?

            first = values.first
            values.each { |item| raise ::TypeError, "value" unless item.instance_of?(first.class) || (first == true || first == false ? (item == true || item == false) : false) }
            case first
            when true, false then write_values("CNA_EFFECT_VALUE_BOOLEAN", values.map { |v| v ? 1 : 0 }.pack("L*"), values.length)
            when ::Integer then write_values("CNA_EFFECT_VALUE_INT32", values.map { |v| CNA::Runtime::Numeric.int32(v, "value") }.pack("l*"), values.length)
            when ::Float then write_values("CNA_EFFECT_VALUE_SINGLE", values.pack("f*"), values.length)
            when Matrix then write_values(transpose ? "CNA_EFFECT_VALUE_MATRIX_TRANSPOSE" : "CNA_EFFECT_VALUE_MATRIX", values.map { |v| pack_matrix(v) }.join, values.length)
            when Quaternion then write_values("CNA_EFFECT_VALUE_QUATERNION", values.flat_map { |v| [v.X, v.Y, v.Z, v.W] }.pack("f*"), values.length)
            when Vector4 then write_values("CNA_EFFECT_VALUE_VECTOR4", values.flat_map { |v| [v.X, v.Y, v.Z, v.W] }.pack("f*"), values.length)
            when Vector3 then write_values("CNA_EFFECT_VALUE_VECTOR3", values.flat_map { |v| [v.X, v.Y, v.Z] }.pack("f*"), values.length)
            when Vector2 then write_values("CNA_EFFECT_VALUE_VECTOR2", values.flat_map { |v| [v.X, v.Y] }.pack("f*"), values.length)
            else raise ::TypeError, "no SetValue overload takes an Array of #{first.class}"
            end
          end

          def pack_matrix(value)
            (1..4).flat_map { |row| (1..4).map { |column| value.__send__("M#{row}#{column}") } }.pack("f16")
          end

          def write_scalar(value_type, bytes)
            CNA::Native.library.call("cna_effect_parameter_set_value", handle,
                                     CNA::Native::Manifest::CONSTANTS.fetch(value_type), Fiddle::Pointer[bytes])
            nil
          end

          def write_values(value_type, bytes, count)
            CNA::Native.library.call("cna_effect_parameter_set_values", handle,
                                     CNA::Native::Manifest::CONSTANTS.fetch(value_type),
                                     Fiddle::Pointer[bytes], count)
            nil
          end

          def write_string(value)
            bytes = value.encode(Encoding::UTF_8).b
            CNA::Native.library.call("cna_effect_parameter_set_value_string", handle,
                                     Fiddle::Pointer[bytes], bytes.bytesize)
            nil
          end

          # XNA's `SetValue(Texture)` is the base overload; the concrete dimension decides which
          # native slot CNA fills, and `CNA_EFFECT_TEXTURE_BASE` is the one for a plain `Texture`.
          def write_texture(value)
            slot = case value
                   when Texture2D then "CNA_EFFECT_TEXTURE_2D"
                   when Texture3D then "CNA_EFFECT_TEXTURE_3D"
                   when TextureCube then "CNA_EFFECT_TEXTURE_CUBE"
                   else "CNA_EFFECT_TEXTURE_BASE"
                   end
            CNA::Native.library.call("cna_effect_parameter_set_value_texture", handle,
                                     CNA::Native::Manifest::CONSTANTS.fetch(slot),
                                     value.__send__(:native_handle))
            nil
          end

          class << self
            private

            def from_native(effect, handle) = allocate.__send__(:initialize_from_native, effect, handle)
          end
        end

        # The four collections are one shape: a list built once, an `Item[Int32]` that answers
        # **null** rather than raising for an index outside it, an `Item[String]` that scans by name
        # with ordinal equality and answers null when nothing matches, a `Count`, and a
        # `GetEnumerator` over the list in order. Ruby cannot give one name two visibilities or two
        # parameter types, so `Item` projects to `[]` and dispatches on the key's class — the rule
        # `Dictionary`2` and `DisplayModeCollection` already follow.
        class EffectParameterCollection
          include ::Enumerable
          private_class_method :new

          def Count = @items.length

          def [](key)
            case key
            when ::Integer then key.negative? || key >= @items.length ? nil : @items[key]
            when ::String then @items.find { |item| item.Name == key }
            else raise ::TypeError, "EffectParameterCollection[] takes an Integer index or a String name"
            end
          end

          # `String.Compare(_semantic, semantic, StringComparison.OrdinalIgnoreCase)` — the one
          # member in this cluster whose match is **case-insensitive**, which is why CNA's own
          # `cna_effect_parameter_collection_find_semantic` is not bound: it matches exactly.
          def GetParameterBySemantic(semantic)
            return nil if semantic.nil?

            @items.find { |item| item.Semantic.casecmp(semantic).zero? }
          end

          def GetEnumerator = @items.each
          def each(&block) = @items.each(&block)

          private

          def initialize_from_native(effect, collection)
            @items = EffectParameterCollection.__send__(:build, effect, collection).freeze
            self
          end

          class << self
            private

            def from_native(effect, collection) = allocate.__send__(:initialize_from_native, effect, collection)

            def build(effect, collection)
              count = effect.__send__(:collection_count, "cna_effect_parameter_collection_get_count", collection)
              ::Array.new(count) do |index|
                EffectParameter.__send__(
                  :from_native, effect,
                  effect.__send__(:child_at, "cna_effect_parameter_collection_get_at",
                                  "cna_effect_parameter_destroy", collection, index)
                )
              end
            end
          end
        end

        # `EffectAnnotation` is `sealed` over six `ldfld` properties and eight `GetValue*` members,
        # and every one of the eight is the same three instructions: construct a temporary
        # `EffectParameter(pEffect, null, _handle, -1)` and forward to that type's getter. So an
        # annotation's value semantics **are** `EffectParameter`'s, including its guards, and the
        # values themselves come from CNA's own annotation routes.
        #
        # DEVIATION, recorded: XNA's temporary parameter builds an element collection from the same
        # D3DX descriptor, so its `Elements.Count` guard reads whatever the annotation's descriptor
        # says. CNA's annotation surface exposes no element collection, and an HLSL annotation is a
        # scalar, vector, matrix or string literal — never an array — so the guard is applied with a
        # count of zero. That is the one place this type is not a mechanical re-reading of the IL.
        class EffectAnnotation
          private_class_method :new
          attr_reader :Name, :Semantic, :RowCount, :ColumnCount, :ParameterClass, :ParameterType

          def GetValueBoolean
            guard_numeric!
            read("cna_effect_annotation_get_value_boolean", "L", 4) == 1
          end

          def GetValueInt32
            guard_numeric!
            read("cna_effect_annotation_get_value_int32", "l", 4)
          end

          def GetValueSingle
            guard_numeric!
            read("cna_effect_annotation_get_value_single", "f", 4)
          end

          def GetValueVector2 = vector(2, "cna_effect_annotation_get_value_vector2") { |c| Vector2.new(c[0], c[1]) }
          def GetValueVector3 = vector(3, "cna_effect_annotation_get_value_vector3") { |c| Vector3.new(c[0], c[1], c[2]) }
          def GetValueVector4 = vector(4, "cna_effect_annotation_get_value_vector4") { |c| Vector4.new(c[0], c[1], c[2], c[3]) }

          def GetValueMatrix
            if @ParameterClass.to_i.zero?
              broadcast = read("cna_effect_annotation_get_value_single", "f", 4)
              return Matrix.new(*([broadcast] * 16))
            end
            raise ::TypeError, "InvalidCastException" unless @ParameterClass.to_i == 2

            Matrix.new(*read_floats("cna_effect_annotation_get_value_matrix", 16))
          end

          def GetValueString
            raise ::TypeError, "InvalidCastException" unless @ParameterType.to_i == 4

            CNA::Native.library.counted_string("cna_effect_annotation_get_value_string_byte_count",
                                               "cna_effect_annotation_copy_value_string", handle)
          end

          private

          def initialize_from_native(effect, handle)
            @effect = effect
            @handle = handle
            info = CNA::Native::Layouts::EffectAnnotationInfo.new
            CNA::Native.library.call("cna_effect_annotation_get_info", handle, info.pointer)
            @RowCount = info.read_i32(8)
            @ColumnCount = info.read_i32(12)
            @ParameterClass = EffectParameterClass.coerce(info.read_u32(16))
            @ParameterType = EffectParameterType.coerce(info.read_u32(20))
            @Name = CNA::Native.library.counted_string("cna_effect_annotation_get_name_byte_count",
                                                       "cna_effect_annotation_copy_name", handle)
            @Semantic = CNA::Native.library.counted_string("cna_effect_annotation_get_semantic_byte_count",
                                                           "cna_effect_annotation_copy_semantic", handle)
            self
          end

          def handle
            raise CNA::DisposedObjectError, "the Effect that owns this EffectAnnotation is disposed" if @effect.IsDisposed

            @handle
          end

          def guard_numeric!
            raise ::TypeError, "InvalidCastException" unless @ParameterClass.to_i.zero?
          end

          def read(symbol, format, bytes)
            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            buffer[0, bytes] = "\0" * bytes
            CNA::Native.library.call(symbol, handle, buffer)
            buffer[0, bytes].unpack1(format)
          end

          def read_floats(symbol, count)
            buffer = Fiddle::Pointer.malloc(4 * count, Fiddle::RUBY_FREE)
            buffer[0, 4 * count] = "\0" * (4 * count)
            CNA::Native.library.call(symbol, handle, buffer)
            buffer[0, 4 * count].unpack("f#{count}")
          end

          def vector(columns, symbol)
            if @ParameterClass.to_i.zero?
              broadcast = read("cna_effect_annotation_get_value_single", "f", 4)
              return yield([broadcast] * 4)
            end
            raise ::TypeError, "InvalidCastException" unless @ParameterClass.to_i == 1
            raise ::TypeError, "InvalidCastException" unless @ColumnCount == columns && @RowCount == 1

            yield read_floats(symbol, columns)
          end

          class << self
            private

            def from_native(effect, handle) = allocate.__send__(:initialize_from_native, effect, handle)
          end
        end

        class EffectAnnotationCollection
          include ::Enumerable
          private_class_method :new

          def Count = @items.length

          def [](key)
            case key
            when ::Integer then key.negative? || key >= @items.length ? nil : @items[key]
            when ::String then @items.find { |item| item.Name == key }
            else raise ::TypeError, "EffectAnnotationCollection[] takes an Integer index or a String name"
            end
          end

          def GetEnumerator = @items.each
          def each(&block) = @items.each(&block)

          private

          def initialize_from_native(effect, collection)
            count = effect.__send__(:collection_count, "cna_effect_annotation_collection_get_count", collection)
            @items = ::Array.new(count) do |index|
              EffectAnnotation.__send__(
                :from_native, effect,
                effect.__send__(:child_at, "cna_effect_annotation_collection_get_at",
                                "cna_effect_annotation_destroy", collection, index)
              )
            end.freeze
            self
          end

          class << self
            private

            def from_native(effect, collection) = allocate.__send__(:initialize_from_native, effect, collection)
          end
        end

        # `EffectPass.Apply` is three managed steps before anything native happens:
        #
        #     Helpers.CheckDisposed(effect, effect.pComPtr);
        #     if (effect.CurrentTechnique != _technique)
        #         throw new InvalidOperationException(NotCurrentTechnique);
        #     effect.OnApply();
        #     … native begin/commit …
        #
        # The order matters and is reproduced: `OnApply` is a `famorassem` virtual whose XNA body is
        # a single `ret`, so a subclass overriding it observes the technique check having passed and
        # the native apply not yet having happened. CNA enforces the same rule itself — measured, a
        # pass outside the current technique answers `CNA_RESULT_INVALID_STATE` with "Applied a pass
        # not in the current technique!" — so the managed check is what puts the failure in XNA's
        # exception class and lets `OnApply` run in XNA's place.
        class EffectPass
          private_class_method :new
          attr_reader :Name, :Annotations

          def Apply
            raise CNA::DisposedObjectError, "the Effect that owns this EffectPass is disposed" if @effect.IsDisposed
            raise ::RuntimeError, "NotCurrentTechnique" unless @effect.CurrentTechnique.equal?(@technique)

            @effect.__send__(:OnApply)
            CNA::Native.library.call("cna_effect_pass_apply", @handle)
            nil
          end

          private

          def initialize_from_native(effect, technique, handle)
            @effect = effect
            @technique = technique
            @handle = handle
            @Name = CNA::Native.library.counted_string("cna_effect_pass_get_name_byte_count",
                                                       "cna_effect_pass_copy_name", handle)
            @Annotations = EffectAnnotationCollection.__send__(
              :from_native, effect, effect.__send__(:child_view, "cna_effect_pass_get_annotations",
                                                    "cna_effect_annotation_collection_destroy", handle)
            )
            self
          end

          class << self
            private

            def from_native(effect, technique, handle) = allocate.__send__(:initialize_from_native, effect, technique, handle)
          end
        end

        class EffectPassCollection
          include ::Enumerable
          private_class_method :new

          def Count = @items.length

          def [](key)
            case key
            when ::Integer then key.negative? || key >= @items.length ? nil : @items[key]
            when ::String then @items.find { |item| item.Name == key }
            else raise ::TypeError, "EffectPassCollection[] takes an Integer index or a String name"
            end
          end

          def GetEnumerator = @items.each
          def each(&block) = @items.each(&block)

          private

          def initialize_from_native(effect, technique, collection)
            count = effect.__send__(:collection_count, "cna_effect_pass_collection_get_count", collection)
            @items = ::Array.new(count) do |index|
              EffectPass.__send__(
                :from_native, effect, technique,
                effect.__send__(:child_at, "cna_effect_pass_collection_get_at",
                                "cna_effect_pass_destroy", collection, index)
              )
            end.freeze
            self
          end

          class << self
            private

            def from_native(effect, technique, collection) = allocate.__send__(:initialize_from_native, effect, technique, collection)
          end
        end

        class EffectTechnique
          private_class_method :new
          attr_reader :Name, :Passes, :Annotations

          private

          def initialize_from_native(effect, handle)
            @effect = effect
            @handle = handle
            @Name = CNA::Native.library.counted_string("cna_effect_technique_get_name_byte_count",
                                                       "cna_effect_technique_copy_name", handle)
            @Annotations = EffectAnnotationCollection.__send__(
              :from_native, effect, effect.__send__(:child_view, "cna_effect_technique_get_annotations",
                                                    "cna_effect_annotation_collection_destroy", handle)
            )
            @Passes = EffectPassCollection.__send__(
              :from_native, effect, self,
              effect.__send__(:child_view, "cna_effect_technique_get_passes",
                              "cna_effect_pass_collection_destroy", handle)
            )
            self
          end

          def native_handle = @handle

          class << self
            private

            def from_native(effect, handle) = allocate.__send__(:initialize_from_native, effect, handle)
          end
        end

        class EffectTechniqueCollection
          include ::Enumerable
          private_class_method :new

          def Count = @items.length

          def [](key)
            case key
            when ::Integer then key.negative? || key >= @items.length ? nil : @items[key]
            when ::String then @items.find { |item| item.Name == key }
            else raise ::TypeError, "EffectTechniqueCollection[] takes an Integer index or a String name"
            end
          end

          def GetEnumerator = @items.each
          def each(&block) = @items.each(&block)

          private

          def initialize_from_native(effect, collection)
            count = effect.__send__(:collection_count, "cna_effect_technique_collection_get_count", collection)
            @items = ::Array.new(count) do |index|
              EffectTechnique.__send__(
                :from_native, effect,
                effect.__send__(:child_at, "cna_effect_technique_collection_get_at",
                                "cna_effect_technique_destroy", collection, index)
              )
            end.freeze
            self
          end

          class << self
            private

            def from_native(effect, collection) = allocate.__send__(:initialize_from_native, effect, collection)
          end
        end

        # `Effect` is `public auto ansi beforefieldinit` over `GraphicsResource`, **not sealed** —
        # every stock effect derives from it — with two constructors, `Clone`, a `famorassem`
        # `OnApply`, a `family` `Dispose(bool)` and three properties.
        #
        # `CreateEffectFromCode`'s validation is reproduced in its own order, which is not the order
        # a reader would guess: the **bytecode is checked before the device**.
        #
        #   1. `effectCode == null || effectCode.Length == 0`
        #      → `ArgumentNullException("effectCode", NullNotAllowed)`
        #   2. `effectCode.Length % 4 != 0`
        #      → `ArgumentException(Format(ArrayMultipleFour, "effectCode"), "effectCode")`
        #   3. `graphicsDevice == null`
        #      → `ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`
        #   4. fewer than eight bytes, or a first dword that is not `0xBCF00BCF`
        #      → `InvalidOperationException(MustUserShaderCode)`
        #
        # The magic number is XNA's own effect-container header, and CNA refuses the same bytes for
        # the same reason, so check four is left to the route: it is the one that knows which
        # containers this build accepts.
        #
        # The `family` `Effect(Effect cloneSource)` constructor is the other producer, and `Clone` is
        # `newobj Effect::.ctor(Effect); ret`. Ruby has one `initialize`, so the two collapse onto
        # the argument's own class — `Effect.new(device, bytes)` or `Effect.new(source)`.
        class Effect < GraphicsResource
          public_class_method :new

          attr_reader :Parameters, :Techniques

          def initialize(*arguments)
            case arguments.length
            when 1 then handle = clone_source_handle(arguments[0])
            when 2 then handle = compile(arguments[0], arguments[1])
            else raise ::ArgumentError, "Effect.new takes (graphicsDevice, effectCode) or (cloneSource)"
            end
            device = arguments.length == 1 ? arguments[0].GraphicsDevice : arguments[0]
            release = lambda { |value| CNA::Native.library.call("cna_effect_destroy", value) }
            @views = []
            initialize_resource(device, handle, release)
            build_graph
          rescue Exception
            release_views
            if defined?(@native_handle) && @native_handle
              self.Dispose
            elsif handle
              release&.call(handle)
            end
            raise
          end

          # `newobj Effect::.ctor(Effect); ret` — nothing else.
          def Clone = Effect.new(self)

          # `ldfld _currentTechnique`. The field, not a native query: CNA hands back a fresh
          # technique view on every call and XNA hands back the object it holds.
          def CurrentTechnique = @current_technique

          # `Helpers.CheckDisposed`, then null → `ArgumentNullException("value", NullNotAllowed)`,
          # then a same-value write returns without touching anything, then a technique belonging to
          # another effect → a **parameterless** `InvalidOperationException`.
          def CurrentTechnique=(value)
            raise CNA::DisposedObjectError, "Effect is disposed" if self.IsDisposed
            raise ::ArgumentError, "value" if value.nil?
            return value if value.equal?(@current_technique)
            raise ::RuntimeError unless @Techniques.include?(value)

            CNA::Native.library.call("cna_effect_set_current_technique", native_handle,
                                     value.__send__(:native_handle))
            @current_technique = value
          end

          # `famorassem hidebysig newslot virtual instance void OnApply()` whose whole body is `ret`.
          # It exists to be overridden — every stock effect does — and `EffectPass.Apply` calls it.
          def OnApply = nil

          def Dispose(disposing = true)
            return if self.IsDisposed

            release_views
            super
          end

          private

          def compile(device, effect_code)
            raise ::ArgumentError, "effectCode" if effect_code.nil?
            raise ::TypeError, "effectCode must be a String of bytes" unless effect_code.is_a?(::String)
            raise ::ArgumentError, "effectCode" if effect_code.bytesize.zero?
            raise ::ArgumentError, "effectCode" unless (effect_code.bytesize % 4).zero?
            raise ::ArgumentError, "graphicsDevice" if device.nil?
            raise ::TypeError, "graphicsDevice must be GraphicsDevice" unless device.instance_of?(GraphicsDevice)

            bytes = effect_code.b
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_create_compiled", device.__send__(:native_handle),
                                     Fiddle::Pointer[bytes], bytes.bytesize, output)
            output[0, 8].unpack1("Q")
          end

          def clone_source_handle(source)
            raise ::ArgumentError, "cloneSource" if source.nil?
            raise ::TypeError, "cloneSource must be an Effect" unless source.is_a?(Effect)
            raise CNA::DisposedObjectError, "cloneSource is disposed" if source.IsDisposed
            raise ::ArgumentError, "graphicsDevice" if source.GraphicsDevice.nil?

            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_clone", source.__send__(:native_handle), output)
            output[0, 8].unpack1("Q")
          end

          # The whole object graph, once, exactly as XNA's constructor builds it.
          def build_graph
            @Parameters = EffectParameterCollection.__send__(
              :from_native, self, child_view("cna_effect_get_parameters",
                                             "cna_effect_parameter_collection_destroy", native_handle)
            )
            @Techniques = EffectTechniqueCollection.__send__(
              :from_native, self, child_view("cna_effect_get_techniques",
                                             "cna_effect_technique_collection_destroy", native_handle)
            )
            @current_technique = current_technique_from_native
            self
          end

          # CNA answers a fresh technique view, so the answer is matched back to the technique this
          # projection already holds by its native index rather than by its handle.
          def current_technique_from_native
            return nil if @Techniques.Count.zero?

            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_get_current_technique", native_handle, output)
            view = output[0, 8].unpack1("Q")
            return @Techniques[0] if view.zero?

            index = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_effect_technique_get_index_ext", view, index)
            selected = index[0, 4].unpack1("L")
            CNA::Native.library.call("cna_effect_technique_destroy", view)
            @Techniques[selected] || @Techniques[0]
          end

          # Every owned view this Effect took, with the route that releases it, released in reverse.
          def child_view(getter, destroy, owner)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call(getter, owner, output)
            record_view(output[0, 8].unpack1("Q"), destroy)
          end

          def child_at(getter, destroy, collection, index)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call(getter, collection, index, output)
            record_view(output[0, 8].unpack1("Q"), destroy)
          end

          def record_view(handle, destroy)
            @views << [handle, destroy]
            handle
          end

          def collection_count(symbol, collection)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call(symbol, collection, output)
            output[0, 8].unpack1("Q")
          end

          # A texture slot answers a **retained** native handle rather than one this binding
          # created, and CNA's header states the rule this projection follows everywhere else:
          # there is no route from a native object back to a handle a consumer owns. So a texture
          # this Effect never received through `SetValue` is not fabricated as a Ruby `Texture2D` —
          # the cache is what answers, and a slot filled by native code reads back as `nil`.
          def texture_for(_native, _dimension) = nil

          def release_views
            return unless defined?(@views) && @views

            @views.reverse_each do |handle, destroy|
              CNA::Native.library.call(destroy, handle)
            rescue CNA::NativeError
              nil
            end
            @views = []
          end
        end

        # `DirectionalLight` is a `sealed` class over three `EffectParameter` fields, a bool and
        # three cached `Vector3`s, and every one of its five identities is a field read, a field
        # write, or a null-guarded `EffectParameter.SetValue(Vector3)`. Its `NATIVE_RUNTIME`
        # deferral named `.ctor`, `set_DiffuseColor`, `set_Direction` and `set_Enabled` -- all four
        # because they reach `SetValue`, which is now projected. Nothing here touches the device.
        #
        # The three parameters are the effect's own, and every one of them may be null: a
        # `BasicEffect` with no specular parameter constructs a light with `specularColorParam`
        # null, and every write to it is skipped. That is why each setter checks.
        class DirectionalLight
          public_class_method :new
          attr_reader :Enabled, :Direction, :DiffuseColor, :SpecularColor

          # The constructor stores the three parameters, and then splits: with a `cloneSource` it
          # copies the **fields**, so no parameter is written; without one it goes through its own
          # three setters with `Vector3.Down`, `Vector3.One` and `Vector3.Zero`. `enabled` is still
          # false at that point, so only `set_Direction` reaches a parameter -- the colour setters
          # check `enabled` first, which is exactly the asymmetry the IL has.
          def initialize(directionParameter, diffuseColorParameter, specularColorParameter, cloneSource)
            @direction_parameter = require_parameter(directionParameter, "directionParameter")
            @diffuse_parameter = require_parameter(diffuseColorParameter, "diffuseColorParameter")
            @specular_parameter = require_parameter(specularColorParameter, "specularColorParameter")
            @Enabled = false
            @Direction = Vector3.Zero
            @DiffuseColor = Vector3.Zero
            @SpecularColor = Vector3.Zero
            if cloneSource.nil?
              self.Direction = Vector3.Down
              self.DiffuseColor = Vector3.One
              self.SpecularColor = Vector3.Zero
              return
            end
            unless cloneSource.instance_of?(DirectionalLight)
              raise ::TypeError, "cloneSource must be a DirectionalLight"
            end

            @Enabled = cloneSource.Enabled
            @Direction = cloneSource.Direction
            @DiffuseColor = cloneSource.DiffuseColor
            @SpecularColor = cloneSource.SpecularColor
          end

          # `beq.s` on the old value: an unchanged write does nothing at all. Enabling pushes the
          # two cached colours into their parameters; disabling pushes `Vector3.Zero` into both,
          # which is how XNA turns a light off in the shader without losing what it was set to.
          def Enabled=(value)
            enabled = require_boolean(value)
            return if enabled == @Enabled

            @Enabled = enabled
            write(@diffuse_parameter, enabled ? @DiffuseColor : Vector3.Zero)
            write(@specular_parameter, enabled ? @SpecularColor : Vector3.Zero)
          end

          # The direction is written whether the light is enabled or not.
          def Direction=(value)
            vector = require_vector3(value, "Direction")
            write(@direction_parameter, vector)
            @Direction = vector
          end

          def DiffuseColor=(value)
            vector = require_vector3(value, "DiffuseColor")
            write(@diffuse_parameter, vector) if @Enabled
            @DiffuseColor = vector
          end

          def SpecularColor=(value)
            vector = require_vector3(value, "SpecularColor")
            write(@specular_parameter, vector) if @Enabled
            @SpecularColor = vector
          end

          private

          # `brfalse` before every `callvirt`: a null parameter is skipped, not raised on.
          def write(parameter, vector)
            parameter&.SetValue(vector)
          end

          def require_parameter(value, name)
            return nil if value.nil?
            raise ::TypeError, "#{name} must be an EffectParameter" unless value.instance_of?(EffectParameter)

            value
          end

          def require_vector3(value, name)
            raise ::TypeError, "#{name} must be a Vector3" unless value.instance_of?(Vector3)

            # A CLR struct assignment copies; holding the caller's object would let a later
            # mutation of it change what this light reports.
            value.dup
          end

          def require_boolean(value)
            return value if value == true || value == false

            raise ::TypeError, "Enabled must be true or false"
          end
        end

        # One identity, and it is `ldarg.0; ldarg.1; call Effect::.ctor(Effect); ret`. `EffectMaterial`
        # adds no member, no field and no override -- it is a *named* effect, the type the content
        # pipeline gives a material so a `ModelMeshPart` can tell one clone from another. Its
        # `NATIVE_RUNTIME` deferral named that constructor, which reaches native only through the
        # `Effect` clone it delegates to.
        #
        # It does not override `Clone`, so cloning one answers an `Effect`, exactly as XNA does.
        class EffectMaterial < Effect
          public_class_method :new

          def initialize(cloneSource)
            super(cloneSource)
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

          # Five overloads in XNA, all of which forward to the seven-argument one, which stores its
          # arguments -- **nulls included** -- and lets `SetRenderState` substitute defaults at apply
          # time: `BlendState.AlphaBlend`, `SamplerState.LinearClamp`, `DepthStencilState.None` and
          # `RasterizerState.CullCounterClockwise`. CNA's `begin_with_effect` documents exactly those
          # four for a null descriptor, which is two independent authorities agreeing on the values.
          #
          # UPSTREAM_CNA_DEFECT: the route does **not** honour that documented null. Passing a null
          # descriptor is refused with `INVALID_ARGUMENT` and "The BlendState descriptor is invalid",
          # reproduced at the C ABI with no Ruby in the path
          # (`docs/sprite-batch-begin-upstream-defect.md`). So this projection substitutes the four
          # defaults **itself**, and that is not a workaround dressed up: `SetRenderState` performs
          # exactly that substitution in the IL, so passing the resolved state is reproducing XNA
          # rather than compensating for CNA. What the defect costs is only that the substitution
          # happens here instead of there, which nothing observable distinguishes.
          #
          # Three of the five are projected: the zero-argument one, `(sortMode, blendState)` and the
          # five-argument one. The other two take an `Effect`, which is not projected, so
          # `CNA_INVALID_HANDLE` -- the default sprite effect -- and a null transform are what the
          # three projected shapes pass, and no overload is offered that could not supply them.
          def Begin(*arguments)
            raise CNA::InvalidBindingStateError, "SpriteBatch.Begin cannot be nested" if @begun
            unless [0, 2, 5, 6, 7].include?(arguments.length)
              raise ArgumentError, "Begin takes (), (sortMode, blendState), " \
                                   "(sortMode, blendState, samplerState, depthStencilState, rasterizerState) " \
                                   "or either of those five plus (effect) and (effect, transformMatrix)"
            end

            if arguments.empty?
              info = CNA::Native::Layouts::SpriteBatchBeginInfo.new(SpriteSortMode::Deferred.to_i)
              CNA::Native.library.call("cna_sprite_batch_begin", native_handle, info.pointer)
              @begun = true
              return nil
            end

            sort_mode, blend, sampler, depth, rasterizer, effect, transform = arguments
            sort = SpriteSortMode.coerce(sort_mode)
            descriptors = [
              state_descriptor(blend, BlendState, BlendState::AlphaBlend, "blendState"),
              state_descriptor(sampler, SamplerState, SamplerState::LinearClamp, "samplerState"),
              state_descriptor(depth, DepthStencilState, DepthStencilState::None, "depthStencilState"),
              state_descriptor(rasterizer, RasterizerState, RasterizerState::CullCounterClockwise,
                               "rasterizerState")
            ]
            # `Effect` is stored as given, nulls included: the seven-argument overload's whole body
            # is seven `stfld`s and the interval checks. A null selects the stock sprite effect,
            # which is exactly what `CNA_INVALID_HANDLE` selects on the route.
            unless effect.nil? || effect.is_a?(Effect)
              raise TypeError, "effect must be an Effect or nil"
            end
            raise CNA::DisposedObjectError, "effect is disposed" if effect&.IsDisposed

            # The six-argument overload is `Begin(…, effect, Matrix.Identity)` -- one `call
            # Matrix::get_Identity` and a forward -- and a null `CNA_Matrix*` is the identity the
            # route documents, so the two agree without this projection choosing anything.
            matrix = nil
            unless transform.nil?
              raise TypeError, "transformMatrix must be a Matrix" unless transform.instance_of?(Matrix)

              matrix = CNA::Native::Layouts::Matrix.new
              (1..4).each do |row|
                (1..4).each do |column|
                  matrix.write_f32(((row - 1) * 4 + column - 1) * 4,
                                   CNA::Runtime::Numeric.f32(transform.__send__("M#{row}#{column}")))
                end
              end
            end
            CNA::Native.library.call("cna_sprite_batch_begin_with_effect", native_handle, sort.to_i,
                                     *descriptors.map(&:pointer),
                                     effect ? effect.__send__(:native_handle) : 0,
                                     matrix ? matrix.pointer : 0)
            @begun = true
            nil
          end

          # Seven overloads, split by what the second argument is. A `Vector2` is a **position** and
          # the sprite is scaled from it; a `Rectangle` is a **destination** and the sprite is
          # stretched to fill it, which is why those three carry no scale at all and why the longest
          # of them has eight parameters where the position form has nine. CNA carries the same
          # split in two structures and two submit routes, so the projection dispatches the way the
          # C ABI already does rather than inventing a shape.
          def Draw(*arguments)
            raise CNA::InvalidBindingStateError, "SpriteBatch.Draw requires Begin" unless @begun

            texture = arguments[0]
            raise TypeError, "texture must be Texture2D" unless texture.instance_of?(Texture2D)
            return draw_stretched(*arguments) if arguments[1].instance_of?(Rectangle)

            raise ArgumentError, "no implemented Foundation SpriteBatch.Draw overload matches" unless [3, 4, 9].include?(arguments.length)
            position = arguments[1]
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

          # Derived from the pinned Graphics IL. All six overloads are two null checks and a forward
          # to `SpriteFont.InternalDraw`; the method validates **nothing else**, and the interval
          # rule lives in `InternalDraw`'s own `SpriteBatch` call rather than here.
          #
          #     if (spriteFont == null) throw new ArgumentNullException("spriteFont");
          #     if (text == null)       throw new ArgumentNullException("text");
          #     spriteFont.InternalDraw(ref proxy, this, position, color,
          #                             rotation, origin, ref scale, effects, layerDepth);
          #
          # Six collapse to two Ruby arities. The `StringBuilder` half of each pair is already the
          # same call here, because `System.Text.StringBuilder` projects to a Ruby `String` -- the
          # decision `SpriteFont.MeasureString` recorded. The two nine-argument forms differ only in
          # whether `scale` is a `Single` or a `Vector2`, and the IL's own `Single` form widens it
          # into both components, so one method reads the argument it was given and does the same.
          def DrawString(*arguments)
            raise CNA::InvalidBindingStateError, "SpriteBatch.DrawString requires Begin" unless @begun
            unless [4, 9].include?(arguments.length)
              raise ArgumentError, "DrawString takes (font, text, position, color) or that plus " \
                                   "(rotation, origin, scale, effects, layerDepth)"
            end

            font, text, position, color = arguments
            raise ArgumentError, "spriteFont" if font.nil?
            raise ArgumentError, "text" if text.nil?
            raise TypeError, "spriteFont must be SpriteFont" unless font.instance_of?(SpriteFont)
            raise TypeError, "text must be String" unless text.instance_of?(::String)
            raise TypeError, "position must be Vector2" unless position.instance_of?(Vector2)
            raise TypeError, "color must be Color" unless color.instance_of?(Color)

            if arguments.length == 4
              rotation = 0.0
              origin = Vector2.Zero
              scale = Vector2.One
              effects = SpriteEffects::None
              depth = 0.0
            else
              rotation, origin, scale, effects, depth = arguments[4..]
              scale = Vector2.new(scale) if scale.instance_of?(Integer) || scale.instance_of?(Float)
            end
            raise TypeError, "origin and scale must be Vector2" unless origin.instance_of?(Vector2) && scale.instance_of?(Vector2)

            numeric = [position.X, position.Y, rotation, origin.X, origin.Y, scale.X, scale.Y, depth]
            raise RangeError, "SpriteBatch transforms must be finite" unless numeric.all? { |value| Float(value).finite? }

            command = CNA::Native::Layouts::SpriteTextCommand.new(
              sprite_font: font.__send__(:native_handle), text: text.b,
              position: position, color: color,
              rotation: CNA::Runtime::Numeric.f32(rotation), origin: origin, scale: scale,
              effects: SpriteEffects.coerce(effects).to_i,
              layer_depth: CNA::Runtime::Numeric.f32(depth)
            )
            CNA::Native.library.call("cna_sprite_batch_draw_string", native_handle, command.pointer)
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

          # The three destination-rectangle overloads:
          #
          #     Draw(texture, destinationRectangle, color)
          #     Draw(texture, destinationRectangle, sourceRectangle, color)
          #     Draw(texture, destinationRectangle, sourceRectangle, color,
          #          rotation, origin, effects, layerDepth)
          #
          # Eight parameters at most, because the destination sets the size and there is nothing for
          # a scale to mean.
          def draw_stretched(texture, destination, *rest)
            raise ArgumentError, "no implemented Foundation SpriteBatch.Draw overload matches" unless [1, 2, 6].include?(rest.length)

            if rest.length == 1
              source = nil
              color = rest[0]
              rotation = 0.0
              origin = Vector2.Zero
              effects = SpriteEffects::None
              depth = 0.0
            elsif rest.length == 2
              source, color = rest
              rotation = 0.0
              origin = Vector2.Zero
              effects = SpriteEffects::None
              depth = 0.0
            else
              source, color, rotation, origin, effects, depth = rest
            end
            raise TypeError, "sourceRectangle must be Rectangle or nil" unless source.nil? || source.instance_of?(Rectangle)
            raise TypeError, "color must be Color" unless color.instance_of?(Color)
            raise TypeError, "origin must be Vector2" unless origin.instance_of?(Vector2)

            numeric = [rotation, origin.X, origin.Y, depth]
            raise RangeError, "SpriteBatch transforms must be finite" unless numeric.all? { |value| Float(value).finite? }

            command = CNA::Native::Layouts::SpriteCommand.new(
              texture: texture.__send__(:native_handle), destination: destination, source: source,
              color: color, rotation: CNA::Runtime::Numeric.f32(rotation), origin: origin,
              effects: SpriteEffects.coerce(effects).to_i,
              layer_depth: CNA::Runtime::Numeric.f32(depth)
            )
            CNA::Native.library.call("cna_sprite_batch_submit_many", native_handle, command.pointer, 1)
            nil
          end

          # `SetRenderState`'s own substitution: a null argument is the documented default state,
          # resolved here because the route that documents the same defaults refuses a null
          # descriptor. The default objects are the projected presets, so what is sent is the exact
          # value XNA would have applied.
          def state_descriptor(state, klass, default, name)
            resolved = state.nil? ? default : state
            raise TypeError, name unless resolved.instance_of?(klass)

            resolved.__send__(:to_native_descriptor)
          end

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

require_relative "graphics/vertex_structs"
