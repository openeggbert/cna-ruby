require_relative '../framework'

module Microsoft
  module Xna
    module Framework
      module Graphics
        class Viewport
          attr_accessor :X, :Y, :Width, :Height
          def initialize(x, y, w, h)
            @X, @Y, @Width, @Height = x, y, w, h
          end
        end

        class GraphicsDevice
          attr_accessor :Viewport
          def initialize
            @Viewport = Viewport.new(0, 0, 1280, 720)
          end
          def Clear(color); end
        end

        class GraphicsDeviceManager
          attr_accessor :GraphicsDevice
          def initialize(game)
            @GraphicsDevice = GraphicsDevice.new
            game.GraphicsDevice = @GraphicsDevice
          end
        end

        class SpriteBatch
          attr_accessor :GraphicsDevice
          def initialize(graphicsDevice)
            @GraphicsDevice = graphicsDevice
          end
          def Begin; end
          def End; end
          def Draw(texture, position, sourceRectangle, color, rotation, origin, scale, effects = 0, layerDepth = 0.0); end
          def DrawRect(texture, destinationRectangle, color); end
        end

        class Texture2D
          attr_accessor :Width, :Height
          def initialize(graphicsDevice, width, height)
            @Width, @Height = width, height
          end
          def SetData(data); end
        end

        class BasicEffect
          attr_accessor :World, :View, :Projection, :TextureEnabled, :Texture
          def initialize(graphicsDevice)
            @World = Matrix.CreateIdentity
            @View = Matrix.CreateIdentity
            @Projection = Matrix.CreateIdentity
            @TextureEnabled = false
            @Texture = nil
          end
          def Apply; end
        end
      end
    end
  end
end
