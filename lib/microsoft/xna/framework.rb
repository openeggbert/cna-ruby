module Microsoft
  module Xna
    module Framework
      class Vector2
        attr_accessor :X, :Y
        def initialize(x = 0.0, y = 0.0)
          @X = x.to_f
          @Y = y.to_f
        end
        def self.Zero; Vector2.new(0, 0); end
      end

      class Vector3
        attr_accessor :X, :Y, :Z
        def initialize(x = 0.0, y = 0.0, z = 0.0)
          @X = x.to_f
          @Y = y.to_f
          @Z = z.to_f
        end
        def self.Zero; Vector3.new(0, 0, 0); end
        def self.Up; Vector3.new(0, 1, 0); end
      end

      class Color
        attr_accessor :R, :G, :B, :A
        def initialize(r, g, b, a = 255)
          @R = r.to_i
          @G = g.to_i
          @B = b.to_i
          @A = a.to_i
        end
        def self.White; Color.new(255, 255, 255); end
        def self.Black; Color.new(0, 0, 0); end
        def self.CornflowerBlue; Color.new(100, 149, 237); end
      end

      class Matrix
        attr_accessor :M
        def initialize
          @M = Array.new(4) { Array.new(4, 0.0) }
        end
        def self.CreateIdentity
          m = Matrix.new
          4.times { |i| m.M[i][i] = 1.0 }
          m
        end
        def self.CreateScale(scale)
          m = CreateIdentity
          m.M[0][0] = m.M[1][1] = m.M[2][2] = scale.to_f
          m
        end
        def self.CreateRotationX(radians); CreateIdentity; end
        def self.CreateRotationY(radians); CreateIdentity; end
        def self.CreateTranslation(x, y, z); CreateIdentity; end
        def self.CreateLookAt(pos, target, up); CreateIdentity; end
        def self.CreatePerspectiveFieldOfView(fov, aspect, near, far); CreateIdentity; end
        def *(other); Matrix.CreateIdentity; end
      end

      class GameTime
        attr_accessor :TotalGameTime, :ElapsedGameTime
        def initialize
          @TotalGameTime = 0.0
          @ElapsedGameTime = 0.0
        end
      end

      class Game
        attr_accessor :Content, :GraphicsDevice
        def initialize
          @Content = nil
          @GraphicsDevice = nil
        end
        def Initialize; end
        def LoadContent; end
        def UnloadContent; end
        def Update(gameTime); end
        def Draw(gameTime); end
        def Exit; end
        def Run; end
      end
    end
  end
end
