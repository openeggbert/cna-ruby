# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      class MathHelper
        N = CNA::Runtime::Numeric
        private_constant :N
        E = N.f32(2.71828175)
        Log2E = N.f32(1.442695)
        Log10E = N.f32(0.4342945)
        Pi = N.f32(3.14159274)
        TwoPi = N.f32(6.28318548)
        PiOver2 = N.f32(1.57079637)
        PiOver4 = N.f32(0.7853982)

        class << self
          def new(*) = raise(TypeError, "MathHelper is static")
          def ToRadians(degrees) = N.mul32(degrees, N.f32(0.0174532924))
          def ToDegrees(radians) = N.mul32(radians, N.f32(57.29578))
          def Distance(value1, value2) = N.f32(N.sub32(value1, value2).abs)

          def Min(value1, value2)
            a = N.f32(value1); b = N.f32(value2)
            return a if a.nan?

            a < b ? a : b
          end

          def Max(value1, value2)
            a = N.f32(value1); b = N.f32(value2)
            return a if a.nan?

            a > b ? a : b
          end

          def Clamp(value, minimum, maximum)
            result = N.f32(value); lower = N.f32(minimum); upper = N.f32(maximum)
            result = upper if result > upper
            result = lower if result < lower
            result
          end

          def Lerp(value1, value2, amount) = N.add32(value1, N.mul32(N.sub32(value2, value1), amount))

          def Barycentric(value1, value2, value3, amount1, amount2)
            N.add32(N.add32(value1, N.mul32(N.sub32(value2, value1), amount1)),
                    N.mul32(N.sub32(value3, value1), amount2))
          end

          def SmoothStep(value1, value2, amount)
            t = Clamp(amount, 0.0, 1.0)
            t = N.mul32(N.mul32(t, t), N.sub32(3.0, N.mul32(2.0, t)))
            Lerp(value1, value2, t)
          end

          def CatmullRom(value1, value2, value3, value4, amount)
            t = N.f32(amount); t2 = N.mul32(t, t); t3 = N.mul32(t, t2)
            quadratic = N.sub32(
              N.add32(N.sub32(N.mul32(2.0, value1), N.mul32(5.0, value2)), N.mul32(4.0, value3)), value4
            )
            cubic = N.add32(
              N.sub32(N.add32(N.f32(-N.f32(value1)), N.mul32(3.0, value2)), N.mul32(3.0, value3)), value4
            )
            inner = N.add32(N.mul32(2.0, value2), N.mul32(N.add32(N.f32(-N.f32(value1)), value3), t))
            inner = N.add32(inner, N.mul32(quadratic, t2))
            inner = N.add32(inner, N.mul32(cubic, t3))
            N.mul32(0.5, inner)
          end

          def Hermite(value1, tangent1, value2, tangent2, amount)
            t = N.f32(amount); t2 = N.mul32(t, t); t3 = N.mul32(t, t2)
            h1 = N.add32(N.sub32(N.mul32(2.0, t3), N.mul32(3.0, t2)), 1.0)
            h3 = N.add32(N.mul32(-2.0, t3), N.mul32(3.0, t2))
            h2 = N.add32(N.sub32(t3, N.mul32(2.0, t2)), t)
            h4 = N.sub32(t3, t2)
            result = N.add32(N.mul32(value1, h1), N.mul32(value2, h3))
            result = N.add32(result, N.mul32(tangent1, h2))
            N.add32(result, N.mul32(tangent2, h4))
          end

          def WrapAngle(angle)
            value = N.f32(N.f32(angle).remainder(TwoPi))
            value = N.add32(value, TwoPi) if value <= -Pi
            value = N.sub32(value, TwoPi) if value > Pi
            value
          rescue Math::DomainError
            Float::NAN
          end
        end
        private_class_method :new
      end

      class Vector2
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        attr_reader :X, :Y

        def initialize(*arguments)
          x, y = case arguments.length
                 when 0 then [0.0, 0.0]
                 when 1 then [arguments[0], arguments[0]]
                 when 2 then arguments
                 else raise ArgumentError, "Vector2.new expects (), (value), or (x, y)"
                 end
          self.X = x; self.Y = y
        end

        def X=(value)
          @X = N.f32(value)
        end

        def Y=(value)
          @Y = N.f32(value)
        end

        class << self
          def Zero = new(0.0)
          def One = new(1.0)
          def UnitX = new(1.0, 0.0)
          def UnitY = new(0.0, 1.0)
          def Distance(value1, value2) = (value1 - value2).Length
          def DistanceSquared(value1, value2) = (value1 - value2).LengthSquared
          def Dot(value1, value2) = N.add32(N.mul32(value1.X, value2.X), N.mul32(value1.Y, value2.Y))

          def Normalize(value)
            copy = value.dup
            copy.Normalize
            copy
          end

          def Reflect(vector, normal) = vector - normal * N.mul32(2.0, Dot(vector, normal))
          def Min(value1, value2) = new(value1.X < value2.X ? value1.X : value2.X, value1.Y < value2.Y ? value1.Y : value2.Y)
          def Max(value1, value2) = new(value1.X > value2.X ? value1.X : value2.X, value1.Y > value2.Y ? value1.Y : value2.Y)
          def Clamp(value, minimum, maximum) = new(MathHelper.Clamp(value.X, minimum.X, maximum.X), MathHelper.Clamp(value.Y, minimum.Y, maximum.Y))
          def Lerp(value1, value2, amount) = new(MathHelper.Lerp(value1.X, value2.X, amount), MathHelper.Lerp(value1.Y, value2.Y, amount))
          def Barycentric(a, b, c, amount1, amount2) = new(MathHelper.Barycentric(a.X, b.X, c.X, amount1, amount2), MathHelper.Barycentric(a.Y, b.Y, c.Y, amount1, amount2))
          def SmoothStep(a, b, amount) = new(MathHelper.SmoothStep(a.X, b.X, amount), MathHelper.SmoothStep(a.Y, b.Y, amount))
          def CatmullRom(a, b, c, d, amount) = new(MathHelper.CatmullRom(a.X, b.X, c.X, d.X, amount), MathHelper.CatmullRom(a.Y, b.Y, c.Y, d.Y, amount))
          def Hermite(a, tangent1, b, tangent2, amount) = new(MathHelper.Hermite(a.X, tangent1.X, b.X, tangent2.X, amount), MathHelper.Hermite(a.Y, tangent1.Y, b.Y, tangent2.Y, amount))
          def Negate(value) = -value
          def Add(value1, value2) = value1 + value2
          def Subtract(value1, value2) = value1 - value2
          def Multiply(value1, value2) = value1 * value2
          def Divide(value1, value2) = value1 / value2
        end

        def LengthSquared = N.add32(N.mul32(@X, @X), N.mul32(@Y, @Y))
        def Length = N.f32(Math.sqrt(self.LengthSquared))

        def Normalize
          factor = N.div32(1.0, self.Length)
          self.X = N.mul32(@X, factor); self.Y = N.mul32(@Y, factor)
          nil
        end

        def -@ = self.class.new(N.f32(-@X), N.f32(-@Y))

        def +(other)
          require_vector!(other)
          self.class.new(N.add32(@X, other.X), N.add32(@Y, other.Y))
        end

        def -(other)
          require_vector!(other)
          self.class.new(N.sub32(@X, other.X), N.sub32(@Y, other.Y))
        end

        def *(other)
          return self.class.new(N.mul32(@X, other.X), N.mul32(@Y, other.Y)) if other.instance_of?(self.class)
          return self.class.new(N.mul32(@X, other), N.mul32(@Y, other)) if other.instance_of?(Integer) || other.instance_of?(Float)

          raise TypeError, "Vector2 multiplication expects Vector2 or Single"
        end

        def /(other)
          return self.class.new(N.div32(@X, other.X), N.div32(@Y, other.Y)) if other.instance_of?(self.class)
          if other.instance_of?(Integer) || other.instance_of?(Float)
            factor = N.div32(1.0, other)
            return self.class.new(N.mul32(@X, factor), N.mul32(@Y, factor))
          end
          raise TypeError, "Vector2 division expects Vector2 or Single"
        end

        def GetHashCode = N.hash32_sum(N.single_hash(@X), N.single_hash(@Y))
        def ToString = "{X:#{N.single_string(@X)} Y:#{N.single_string(@Y)}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y]
        def require_vector!(value)
          raise TypeError, "expected Vector2" unless value.instance_of?(self.class)
        end
      end

      class Point
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N
        attr_reader :X, :Y

        def initialize(*arguments)
          x, y = case arguments.length
                 when 0 then [0, 0]
                 when 2 then arguments
                 else raise ArgumentError, "Point.new expects () or (x, y)"
                 end
          self.X = x; self.Y = y
        end

        def X=(value)
          @X = N.int32(value, "X")
        end

        def Y=(value)
          @Y = N.int32(value, "Y")
        end
        def self.Zero = new(0, 0)
        def GetHashCode = N.wrap_int32(@X + @Y)
        def ToString = "{X:#{@X} Y:#{@Y}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y]
      end

      class Rectangle
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N
        attr_reader :X, :Y, :Width, :Height

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0, 0, 0, 0]
                   when 4 then arguments
                   else raise ArgumentError, "Rectangle.new expects () or (x, y, width, height)"
                   end
          self.X, self.Y, self.Width, self.Height = values
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
        def Left = @X
        def Right = N.wrap_int32(@X + @Width)
        def Top = @Y
        def Bottom = N.wrap_int32(@Y + @Height)
        def Location = Point.new(@X, @Y)

        def Location=(value)
          raise TypeError, "Location expects Point" unless value.instance_of?(Point)
          self.X = value.X; self.Y = value.Y
        end

        def Center = Point.new(N.wrap_int32(@X + (@Width / 2.0).truncate), N.wrap_int32(@Y + (@Height / 2.0).truncate))
        def self.Empty = new
        def IsEmpty = @X.zero? && @Y.zero? && @Width.zero? && @Height.zero?

        def Offset(*arguments)
          dx, dy = if arguments.length == 1 && arguments[0].instance_of?(Point)
                     [arguments[0].X, arguments[0].Y]
                   elsif arguments.length == 2
                     arguments
                   else
                     raise ArgumentError, "Offset expects Point or (offsetX, offsetY)"
                   end
          self.X = N.wrap_int32(@X + N.int32(dx)); self.Y = N.wrap_int32(@Y + N.int32(dy))
          nil
        end

        def Inflate(horizontal, vertical)
          h = N.int32(horizontal); v = N.int32(vertical)
          self.X = N.wrap_int32(@X - h); self.Y = N.wrap_int32(@Y - v)
          self.Width = N.wrap_int32(@Width + h * 2); self.Height = N.wrap_int32(@Height + v * 2)
          nil
        end

        def Contains(*arguments)
          if arguments.length == 2
            x = N.int32(arguments[0]); y = N.int32(arguments[1])
            @X <= x && x < self.Right && @Y <= y && y < self.Bottom
          elsif arguments.length == 1 && arguments[0].instance_of?(Point)
            Contains(arguments[0].X, arguments[0].Y)
          elsif arguments.length == 1 && arguments[0].instance_of?(Rectangle)
            other = arguments[0]
            @X <= other.X && other.Right <= self.Right && @Y <= other.Y && other.Bottom <= self.Bottom
          else
            raise ArgumentError, "Contains expects (x, y), Point, or Rectangle"
          end
        end

        def Intersects(other)
          raise TypeError, "Intersects expects Rectangle" unless other.instance_of?(Rectangle)
          other.Left < self.Right && self.Left < other.Right && other.Top < self.Bottom && self.Top < other.Bottom
        end

        def self.Intersect(a, b)
          raise TypeError, "Intersect expects Rectangle values" unless a.instance_of?(self) && b.instance_of?(self)
          left = [a.Left, b.Left].max; top = [a.Top, b.Top].max
          right = [a.Right, b.Right].min; bottom = [a.Bottom, b.Bottom].min
          right > left && bottom > top ? new(left, top, right - left, bottom - top) : self.Empty
        end

        def self.Union(a, b)
          raise TypeError, "Union expects Rectangle values" unless a.instance_of?(self) && b.instance_of?(self)
          left = [a.Left, b.Left].min; top = [a.Top, b.Top].min
          right = [a.Right, b.Right].max; bottom = [a.Bottom, b.Bottom].max
          new(left, top, right - left, bottom - top)
        end

        def GetHashCode = N.wrap_int32(@X + @Y + @Width + @Height)
        def ToString = "{X:#{@X} Y:#{@Y} Width:#{@Width} Height:#{@Height}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y, @Width, @Height]
      end

      class Color
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0, 0, 0, 0]
                   when 3 then [*arguments, 255]
                   when 4 then arguments
                   else raise ArgumentError, "Foundation Color.new expects (), (r, g, b), or (r, g, b, a)"
                   end
          raise TypeError, "Color channel constructors require Int32" unless values.all? { |value| value.instance_of?(Integer) }
          @packed = 0
          self.R, self.G, self.B, self.A = values
        end

        def R = @packed & 0xff
        def G = (@packed >> 8) & 0xff
        def B = (@packed >> 16) & 0xff
        def A = (@packed >> 24) & 0xff
        def R=(value)
          @packed = (@packed & 0xffff_ff00) | [[N.int32(value), 0].max, 255].min
        end

        def G=(value)
          @packed = (@packed & 0xffff_00ff) | ([[N.int32(value), 0].max, 255].min << 8)
        end

        def B=(value)
          @packed = (@packed & 0xff00_ffff) | ([[N.int32(value), 0].max, 255].min << 16)
        end

        def A=(value)
          @packed = (@packed & 0x00ff_ffff) | ([[N.int32(value), 0].max, 255].min << 24)
        end
        def PackedValue = @packed
        def PackedValue=(value)
          @packed = N.uint32(value, "PackedValue")
        end

        class << self
          def from_packed(value)
            new.tap { |color| color.PackedValue = value }
          end
          private :from_packed
          def Transparent = from_packed(0x00ff_ffff)
          def Black = from_packed(0xff00_0000)
          def CornflowerBlue = from_packed(0xffed_9564)
          def White = from_packed(0xffff_ffff)

          def Lerp(value1, value2, amount)
            raise TypeError, "Lerp expects Color values" unless value1.instance_of?(self) && value2.instance_of?(self)
            fraction = [[(N.f32(amount) * 65_536.0).round, 0].max, 65_536].min
            new(*[value1.R, value1.G, value1.B, value1.A].zip([value2.R, value2.G, value2.B, value2.A]).map { |a, b| a + (((b - a) * fraction) >> 16) })
          end

          def Multiply(value, scale)
            raise TypeError, "Multiply expects Color" unless value.instance_of?(self)
            scaled = N.mul32(scale, 65_536.0)
            fixed = scaled.nan? || scaled <= 0 ? 0 : [scaled.to_i, 16_777_215].min
            new(*[value.R, value.G, value.B, value.A].map { |channel| [255, (channel * fixed) >> 16].min })
          end
        end

        def *(scale) = self.class.Multiply(self, scale)
        def GetHashCode = N.wrap_int32(@packed)
        def ToString = "{R:#{self.R} G:#{self.G} B:#{self.B} A:#{self.A}}"
        alias to_s ToString

        private

        def value_components = [self.R, self.G, self.B, self.A]
      end

      class GameTime
        include CNA::Runtime::ValueSemantics
        attr_reader :TotalGameTime, :ElapsedGameTime, :IsRunningSlowly

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0.0, 0.0, false]
                   when 2 then [*arguments, false]
                   when 3 then arguments
                   else raise ArgumentError, "GameTime.new expects (), (total, elapsed), or (total, elapsed, running_slowly)"
                   end
          raise TypeError, "TimeSpan maps to numeric seconds" unless values[0].is_a?(Numeric) && values[1].is_a?(Numeric)
          raise TypeError, "IsRunningSlowly must be true or false" unless values[2] == true || values[2] == false
          @TotalGameTime = Float(values[0]); @ElapsedGameTime = Float(values[1]); @IsRunningSlowly = values[2]
        end

        private

        def value_components = [@TotalGameTime, @ElapsedGameTime, @IsRunningSlowly]
      end

      class PlayerIndex < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({ "One" => 0, "Two" => 1, "Three" => 2, "Four" => 3 })
      end
    end
  end
end
