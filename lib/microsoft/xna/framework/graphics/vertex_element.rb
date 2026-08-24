# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      module Graphics
        class VertexElementFormat < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Single" => 0,
            "Vector2" => 1,
            "Vector3" => 2,
            "Vector4" => 3,
            "Color" => 4,
            "Byte4" => 5,
            "Short2" => 6,
            "Short4" => 7,
            "NormalizedShort2" => 8,
            "NormalizedShort4" => 9,
            "HalfVector2" => 10,
            "HalfVector4" => 11
          })
        end

        class VertexElementUsage < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Position" => 0,
            "Color" => 1,
            "TextureCoordinate" => 2,
            "Normal" => 3,
            "Binormal" => 4,
            "Tangent" => 5,
            "BlendIndices" => 6,
            "BlendWeight" => 7,
            "Depth" => 8,
            "Fog" => 9,
            "PointSize" => 10,
            "Sample" => 11,
            "TessellateFactor" => 12
          })
        end

        class VertexElement
          include CNA::Runtime::ValueSemantics

          N = CNA::Runtime::Numeric
          private_constant :N

          attr_reader :Offset, :VertexElementFormat, :VertexElementUsage, :UsageIndex

          def initialize(*arguments)
            offset, element_format, element_usage, usage_index = case arguments.length
                                                                 when 0
                                                                   [0, Graphics::VertexElementFormat::Single,
                                                                    Graphics::VertexElementUsage::Position, 0]
                                                                 when 4
                                                                   arguments
                                                                 else
                                                                   raise ArgumentError,
                                                                         "VertexElement.new expects () or " \
                                                                         "(offset, elementFormat, elementUsage, usageIndex)"
                                                                 end
            self.Offset = offset
            self.VertexElementFormat = element_format
            self.VertexElementUsage = element_usage
            self.UsageIndex = usage_index
          end

          def Offset=(value)
            @Offset = N.int32(value, "Offset")
          end

          def VertexElementFormat=(value)
            @VertexElementFormat = Graphics::VertexElementFormat.coerce(value)
          end

          def VertexElementUsage=(value)
            @VertexElementUsage = Graphics::VertexElementUsage.coerce(value)
          end

          def UsageIndex=(value)
            @UsageIndex = N.int32(value, "UsageIndex")
          end

          def Equals(other) = self == other

          def ==(other)
            other.instance_of?(self.class) &&
              @Offset == other.Offset &&
              @UsageIndex == other.UsageIndex &&
              @VertexElementUsage == other.VertexElementUsage &&
              @VertexElementFormat == other.VertexElementFormat
          end

          def !=(other) = !(self == other)
          alias eql? ==

          def GetHashCode
            value = N.wrap_int32(
              @Offset ^ @VertexElementFormat.to_i ^ @VertexElementUsage.to_i ^ @UsageIndex
            )
            value.zero? ? 2_147_483_647 : value
          end

          def ToString
            "{Offset:#{@Offset} Format:#{@VertexElementFormat} " \
              "Usage:#{@VertexElementUsage} UsageIndex:#{@UsageIndex}}"
          end

          alias to_s ToString

          private

          def value_components
            [@Offset, @VertexElementFormat, @VertexElementUsage, @UsageIndex]
          end
        end
      end
    end
  end
end
