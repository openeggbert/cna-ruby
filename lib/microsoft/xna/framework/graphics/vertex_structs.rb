# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      module Graphics
        # `.ctor(Vector3 position, Color color)` is two `stfld` and nothing else. The static
        # declaration is `new VertexDeclaration(new VertexElement(0, Vector3, Position, 0),
        # new VertexElement(12, Color, Color, 0))` with `Name` set afterwards -- stride 16.
        class VertexPositionColor
          include CNA::Runtime::ValueSemantics
          include IVertexType
          include CNA::Runtime::VertexStruct

          attr_reader :Position, :Color

          def initialize(position = Vector3.new, color = Framework::Color.new)
            self.Position = position
            self.Color = color
          end

          def Position=(value)
            @Position = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Position").dup
          end

          def Color=(value)
            @Color = CNA::Runtime::GeometrySupport.require_type(value, Framework::Color, "Color").dup
          end

          def ToString = "{Position:#{@Position} Color:#{@Color}}"
          alias to_s ToString

          VertexDeclaration = Graphics.const_get(:VertexDeclaration).new(
            VertexElement.new(0, VertexElementFormat::Vector3, VertexElementUsage::Position, 0),
            VertexElement.new(12, VertexElementFormat::Color, VertexElementUsage::Color, 0)
          )
          VertexDeclaration.Name = "VertexPositionColor.VertexDeclaration"

          private

          def value_components = [@Position, @Color]
          def vertex_words = position_words << @Color.PackedValue
        end

        # `.ctor(Vector3 position, Vector2 textureCoordinate)`; the declaration is Vector3 at 0 and
        # Vector2 at 12 -- stride 20.
        class VertexPositionTexture
          include CNA::Runtime::ValueSemantics
          include IVertexType
          include CNA::Runtime::VertexStruct

          attr_reader :Position, :TextureCoordinate

          def initialize(position = Vector3.new, texture_coordinate = Vector2.new)
            self.Position = position
            self.TextureCoordinate = texture_coordinate
          end

          def Position=(value)
            @Position = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Position").dup
          end

          def TextureCoordinate=(value)
            @TextureCoordinate = CNA::Runtime::GeometrySupport
                                 .require_type(value, Vector2, "TextureCoordinate").dup
          end

          def ToString = "{Position:#{@Position} TextureCoordinate:#{@TextureCoordinate}}"
          alias to_s ToString

          VertexDeclaration = Graphics.const_get(:VertexDeclaration).new(
            VertexElement.new(0, VertexElementFormat::Vector3, VertexElementUsage::Position, 0),
            VertexElement.new(12, VertexElementFormat::Vector2, VertexElementUsage::TextureCoordinate, 0)
          )
          VertexDeclaration.Name = "VertexPositionTexture.VertexDeclaration"

          private

          def value_components = [@Position, @TextureCoordinate]

          def vertex_words
            numeric = CNA::Runtime::Numeric
            position_words + [numeric.f32_bits(@TextureCoordinate.X), numeric.f32_bits(@TextureCoordinate.Y)]
          end
        end

        # `.ctor(Vector3 position, Color color, Vector2 textureCoordinate)`; Vector3 at 0, Color at
        # 12, Vector2 at 16 -- stride 24.
        class VertexPositionColorTexture
          include CNA::Runtime::ValueSemantics
          include IVertexType
          include CNA::Runtime::VertexStruct

          attr_reader :Position, :Color, :TextureCoordinate

          def initialize(position = Vector3.new, color = Framework::Color.new,
                         texture_coordinate = Vector2.new)
            self.Position = position
            self.Color = color
            self.TextureCoordinate = texture_coordinate
          end

          def Position=(value)
            @Position = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Position").dup
          end

          def Color=(value)
            @Color = CNA::Runtime::GeometrySupport.require_type(value, Framework::Color, "Color").dup
          end

          def TextureCoordinate=(value)
            @TextureCoordinate = CNA::Runtime::GeometrySupport
                                 .require_type(value, Vector2, "TextureCoordinate").dup
          end

          def ToString
            "{Position:#{@Position} Color:#{@Color} TextureCoordinate:#{@TextureCoordinate}}"
          end
          alias to_s ToString

          VertexDeclaration = Graphics.const_get(:VertexDeclaration).new(
            VertexElement.new(0, VertexElementFormat::Vector3, VertexElementUsage::Position, 0),
            VertexElement.new(12, VertexElementFormat::Color, VertexElementUsage::Color, 0),
            VertexElement.new(16, VertexElementFormat::Vector2, VertexElementUsage::TextureCoordinate, 0)
          )
          VertexDeclaration.Name = "VertexPositionColorTexture.VertexDeclaration"

          private

          def value_components = [@Position, @Color, @TextureCoordinate]

          def vertex_words
            numeric = CNA::Runtime::Numeric
            position_words + [@Color.PackedValue,
                              numeric.f32_bits(@TextureCoordinate.X),
                              numeric.f32_bits(@TextureCoordinate.Y)]
          end
        end

        # `.ctor(Vector3 position, Vector3 normal, Vector2 textureCoordinate)`; Vector3 at 0,
        # Vector3 at 12, Vector2 at 24 -- stride 32.
        class VertexPositionNormalTexture
          include CNA::Runtime::ValueSemantics
          include IVertexType
          include CNA::Runtime::VertexStruct

          attr_reader :Position, :Normal, :TextureCoordinate

          def initialize(position = Vector3.new, normal = Vector3.new,
                         texture_coordinate = Vector2.new)
            self.Position = position
            self.Normal = normal
            self.TextureCoordinate = texture_coordinate
          end

          def Position=(value)
            @Position = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Position").dup
          end

          def Normal=(value)
            @Normal = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Normal").dup
          end

          def TextureCoordinate=(value)
            @TextureCoordinate = CNA::Runtime::GeometrySupport
                                 .require_type(value, Vector2, "TextureCoordinate").dup
          end

          def ToString
            "{Position:#{@Position} Normal:#{@Normal} TextureCoordinate:#{@TextureCoordinate}}"
          end
          alias to_s ToString

          VertexDeclaration = Graphics.const_get(:VertexDeclaration).new(
            VertexElement.new(0, VertexElementFormat::Vector3, VertexElementUsage::Position, 0),
            VertexElement.new(12, VertexElementFormat::Vector3, VertexElementUsage::Normal, 0),
            VertexElement.new(24, VertexElementFormat::Vector2, VertexElementUsage::TextureCoordinate, 0)
          )
          VertexDeclaration.Name = "VertexPositionNormalTexture.VertexDeclaration"

          private

          def value_components = [@Position, @Normal, @TextureCoordinate]

          def vertex_words
            numeric = CNA::Runtime::Numeric
            position_words + [numeric.f32_bits(@Normal.X), numeric.f32_bits(@Normal.Y),
                              numeric.f32_bits(@Normal.Z),
                              numeric.f32_bits(@TextureCoordinate.X),
                              numeric.f32_bits(@TextureCoordinate.Y)]
          end
        end
      end
    end
  end
end
