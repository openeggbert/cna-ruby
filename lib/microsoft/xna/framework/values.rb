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

        def Center
          Point.new(
            N.wrap_int32(@X + truncating_half(@Width)),
            N.wrap_int32(@Y + truncating_half(@Height))
          )
        end
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
          right > left && bottom > top ? new(left, top, N.wrap_int32(right - left), N.wrap_int32(bottom - top)) : self.Empty
        end

        def self.Union(a, b)
          raise TypeError, "Union expects Rectangle values" unless a.instance_of?(self) && b.instance_of?(self)
          left = [a.Left, b.Left].min; top = [a.Top, b.Top].min
          right = [a.Right, b.Right].max; bottom = [a.Bottom, b.Bottom].max
          new(left, top, N.wrap_int32(right - left), N.wrap_int32(bottom - top))
        end

        def GetHashCode = N.wrap_int32(@X + @Y + @Width + @Height)
        def ToString = "{X:#{@X} Y:#{@Y} Width:#{@Width} Height:#{@Height}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y, @Width, @Height]
        def truncating_half(value) = value.negative? ? -((-value) / 2) : value / 2
      end

      class Color
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        # Exact packed UInt32 values from the pinned XNA 4.0 Windows runtime
        # Color property bodies. Each public property constructs a fresh value.
        NAMED_COLORS = {
          "Transparent" => 0,
          "AliceBlue" => 4_294_965_488,
          "AntiqueWhite" => 4_292_340_730,
          "Aqua" => 4_294_967_040,
          "Aquamarine" => 4_292_149_119,
          "Azure" => 4_294_967_280,
          "Beige" => 4_292_670_965,
          "Bisque" => 4_291_093_759,
          "Black" => 4_278_190_080,
          "BlanchedAlmond" => 4_291_685_375,
          "Blue" => 4_294_901_760,
          "BlueViolet" => 4_293_012_362,
          "Brown" => 4_280_953_509,
          "BurlyWood" => 4_287_084_766,
          "CadetBlue" => 4_288_716_383,
          "Chartreuse" => 4_278_255_487,
          "Chocolate" => 4_280_183_250,
          "Coral" => 4_283_465_727,
          "CornflowerBlue" => 4_293_760_356,
          "Cornsilk" => 4_292_671_743,
          "Crimson" => 4_282_127_580,
          "Cyan" => 4_294_967_040,
          "DarkBlue" => 4_287_299_584,
          "DarkCyan" => 4_287_335_168,
          "DarkGoldenrod" => 4_278_945_464,
          "DarkGray" => 4_289_309_097,
          "DarkGreen" => 4_278_215_680,
          "DarkKhaki" => 4_285_249_469,
          "DarkMagenta" => 4_287_299_723,
          "DarkOliveGreen" => 4_281_297_749,
          "DarkOrange" => 4_278_226_175,
          "DarkOrchid" => 4_291_572_377,
          "DarkRed" => 4_278_190_219,
          "DarkSalmon" => 4_286_224_105,
          "DarkSeaGreen" => 4_287_347_855,
          "DarkSlateBlue" => 4_287_315_272,
          "DarkSlateGray" => 4_283_387_695,
          "DarkTurquoise" => 4_291_939_840,
          "DarkViolet" => 4_292_018_324,
          "DeepPink" => 4_287_829_247,
          "DeepSkyBlue" => 4_294_950_656,
          "DimGray" => 4_285_098_345,
          "DodgerBlue" => 4_294_938_654,
          "Firebrick" => 4_280_427_186,
          "FloralWhite" => 4_293_982_975,
          "ForestGreen" => 4_280_453_922,
          "Fuchsia" => 4_294_902_015,
          "Gainsboro" => 4_292_664_540,
          "GhostWhite" => 4_294_965_496,
          "Gold" => 4_278_245_375,
          "Goldenrod" => 4_280_329_690,
          "Gray" => 4_286_611_584,
          "Green" => 4_278_222_848,
          "GreenYellow" => 4_281_335_725,
          "Honeydew" => 4_293_984_240,
          "HotPink" => 4_290_013_695,
          "IndianRed" => 4_284_243_149,
          "Indigo" => 4_286_709_835,
          "Ivory" => 4_293_984_255,
          "Khaki" => 4_287_424_240,
          "Lavender" => 4_294_633_190,
          "LavenderBlush" => 4_294_308_095,
          "LawnGreen" => 4_278_254_716,
          "LemonChiffon" => 4_291_689_215,
          "LightBlue" => 4_293_318_829,
          "LightCoral" => 4_286_611_696,
          "LightCyan" => 4_294_967_264,
          "LightGoldenrodYellow" => 4_292_016_890,
          "LightGreen" => 4_287_688_336,
          "LightGray" => 4_292_072_403,
          "LightPink" => 4_290_885_375,
          "LightSalmon" => 4_286_226_687,
          "LightSeaGreen" => 4_289_376_800,
          "LightSkyBlue" => 4_294_626_951,
          "LightSlateGray" => 4_288_252_023,
          "LightSteelBlue" => 4_292_789_424,
          "LightYellow" => 4_292_935_679,
          "Lime" => 4_278_255_360,
          "LimeGreen" => 4_281_519_410,
          "Linen" => 4_293_325_050,
          "Magenta" => 4_294_902_015,
          "Maroon" => 4_278_190_208,
          "MediumAquamarine" => 4_289_383_782,
          "MediumBlue" => 4_291_624_960,
          "MediumOrchid" => 4_292_040_122,
          "MediumPurple" => 4_292_571_283,
          "MediumSeaGreen" => 4_285_641_532,
          "MediumSlateBlue" => 4_293_814_395,
          "MediumSpringGreen" => 4_288_346_624,
          "MediumTurquoise" => 4_291_613_000,
          "MediumVioletRed" => 4_286_911_943,
          "MidnightBlue" => 4_285_536_537,
          "MintCream" => 4_294_639_605,
          "MistyRose" => 4_292_994_303,
          "Moccasin" => 4_290_110_719,
          "NavajoWhite" => 4_289_584_895,
          "Navy" => 4_286_578_688,
          "OldLace" => 4_293_326_333,
          "Olive" => 4_278_222_976,
          "OliveDrab" => 4_280_520_299,
          "Orange" => 4_278_232_575,
          "OrangeRed" => 4_278_207_999,
          "Orchid" => 4_292_243_674,
          "PaleGoldenrod" => 4_289_390_830,
          "PaleGreen" => 4_288_215_960,
          "PaleTurquoise" => 4_293_848_751,
          "PaleVioletRed" => 4_287_852_763,
          "PapayaWhip" => 4_292_210_687,
          "PeachPuff" => 4_290_370_303,
          "Peru" => 4_282_353_101,
          "Pink" => 4_291_543_295,
          "Plum" => 4_292_714_717,
          "PowderBlue" => 4_293_320_880,
          "Purple" => 4_286_578_816,
          "Red" => 4_278_190_335,
          "RosyBrown" => 4_287_598_524,
          "RoyalBlue" => 4_292_962_625,
          "SaddleBrown" => 4_279_453_067,
          "Salmon" => 4_285_694_202,
          "SandyBrown" => 4_284_523_764,
          "SeaGreen" => 4_283_927_342,
          "SeaShell" => 4_293_850_623,
          "Sienna" => 4_281_160_352,
          "Silver" => 4_290_822_336,
          "SkyBlue" => 4_293_643_911,
          "SlateBlue" => 4_291_648_106,
          "SlateGray" => 4_287_660_144,
          "Snow" => 4_294_638_335,
          "SpringGreen" => 4_286_578_432,
          "SteelBlue" => 4_290_019_910,
          "Tan" => 4_287_411_410,
          "Teal" => 4_286_611_456,
          "Thistle" => 4_292_394_968,
          "Tomato" => 4_282_868_735,
          "Turquoise" => 4_291_878_976,
          "Violet" => 4_293_821_166,
          "Wheat" => 4_289_978_101,
          "White" => 4_294_967_295,
          "WhiteSmoke" => 4_294_309_365,
          "Yellow" => 4_278_255_615,
          "YellowGreen" => 4_281_519_514
        }.freeze
        private_constant :NAMED_COLORS

        def initialize(*arguments)
          @packed = case arguments.length
                    when 0 then 0
                    when 1 then pack_vector(arguments[0])
                    when 3, 4 then pack_channels(arguments)
                    else raise ArgumentError, "Color.new expects (), Vector3, Vector4, or three/four homogeneous channel values"
                    end
        end

        def R = @packed & 0xff
        def G = (@packed >> 8) & 0xff
        def B = (@packed >> 16) & 0xff
        def A = (@packed >> 24) & 0xff
        def R=(value)
          @packed = (@packed & 0xffff_ff00) | N.uint8(value, "R")
        end

        def G=(value)
          @packed = (@packed & 0xffff_00ff) | (N.uint8(value, "G") << 8)
        end

        def B=(value)
          @packed = (@packed & 0xff00_ffff) | (N.uint8(value, "B") << 16)
        end

        def A=(value)
          @packed = (@packed & 0x00ff_ffff) | (N.uint8(value, "A") << 24)
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

          NAMED_COLORS.each do |name, packed|
            define_method(name) { from_packed(packed) }
          end

          def FromNonPremultiplied(*arguments)
            if arguments.length == 1 && arguments[0].instance_of?(Vector4)
              vector = arguments[0]
              return from_packed(pack_unorm_channels(
                N.mul32(vector.X, vector.W), N.mul32(vector.Y, vector.W),
                N.mul32(vector.Z, vector.W), vector.W
              ))
            end
            if arguments.length == 4 && arguments.all? { |value| value.instance_of?(Integer) }
              r, g, b, a = arguments.map.with_index { |value, index| N.int32(value, %w[r g b a][index]) }
              return from_packed(pack_bytes(
                clamp_byte(truncating_divide(r * a, 255)),
                clamp_byte(truncating_divide(g * a, 255)),
                clamp_byte(truncating_divide(b * a, 255)),
                clamp_byte(a)
              ))
            end
            raise TypeError, "FromNonPremultiplied expects Vector4 or four Int32 values"
          end

          def Lerp(value1, value2, amount)
            raise TypeError, "Lerp expects Color values" unless value1.instance_of?(self) && value2.instance_of?(self)
            fraction = pack_unorm(65_536.0, amount)
            channels = [value1.R, value1.G, value1.B, value1.A]
            targets = [value2.R, value2.G, value2.B, value2.A]
            from_packed(pack_bytes(*channels.zip(targets).map { |a, b| a + (((b - a) * fraction) >> 16) }))
          end

          def Multiply(value, scale)
            raise TypeError, "Multiply expects Color" unless value.instance_of?(self)
            scaled = N.mul32(scale, 65_536.0)
            fixed = if scaled.nan? || scaled < 0.0
                      0
                    elsif scaled > 16_777_215.0
                      16_777_215
                    else
                      scaled.to_i
                    end
            channels = [value.R, value.G, value.B, value.A].map { |channel| [255, (channel * fixed) >> 16].min }
            from_packed(pack_bytes(*channels))
          end

          private

          def pack_bytes(r, g, b, a) = r | (g << 8) | (b << 16) | (a << 24)

          def clamp_byte(value)
            return 0 if value < 0
            return 255 if value > 255

            value
          end

          def truncating_divide(value, divisor)
            quotient = value.abs / divisor
            value.negative? ? -quotient : quotient
          end

          def pack_unorm(bitmask, value)
            scaled = N.mul32(value, bitmask)
            return 0 if scaled.nan? || scaled < 0.0
            return bitmask.to_i if scaled.infinite? || scaled > bitmask

            scaled.round(half: :even).to_i
          end

          def pack_unorm_channels(r, g, b, a)
            pack_bytes(
              pack_unorm(255.0, r), pack_unorm(255.0, g),
              pack_unorm(255.0, b), pack_unorm(255.0, a)
            )
          end
        end

        def ToVector3 = Vector3.new(N.div32(self.R, 255.0), N.div32(self.G, 255.0), N.div32(self.B, 255.0))
        def ToVector4 = Vector4.new(N.div32(self.R, 255.0), N.div32(self.G, 255.0), N.div32(self.B, 255.0), N.div32(self.A, 255.0))

        def *(scale) = self.class.Multiply(self, scale)
        def GetHashCode = N.wrap_int32(@packed)
        def ToString = "{R:#{self.R} G:#{self.G} B:#{self.B} A:#{self.A}}"
        alias to_s ToString

        private

        def value_components = [self.R, self.G, self.B, self.A]

        def pack_vector(value)
          if value.instance_of?(Vector3)
            return self.class.__send__(:pack_unorm_channels, value.X, value.Y, value.Z, 1.0)
          end
          if value.instance_of?(Vector4)
            return self.class.__send__(:pack_unorm_channels, value.X, value.Y, value.Z, value.W)
          end

          raise TypeError, "Color vector constructor expects Vector3 or Vector4"
        end

        def pack_channels(arguments)
          values = arguments.length == 3 ? [*arguments, arguments.first.instance_of?(Integer) ? 255 : 1.0] : arguments
          if values.all? { |value| value.instance_of?(Integer) }
            channels = values.map.with_index do |value, index|
              self.class.__send__(:clamp_byte, N.int32(value, %w[r g b a][index]))
            end
            return self.class.__send__(:pack_bytes, *channels)
          end
          if values.all? { |value| value.instance_of?(Float) }
            return self.class.__send__(:pack_unorm_channels, *values)
          end

          raise TypeError, "Color channel constructors require all Int32 or all Single values"
        end
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

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…): the
      # constructor is `base()` followed by one field store, and GameComponent is a single field
      # read. XNA validates nothing, so null is accepted. Nothing in this binding raises the
      # GameComponentCollection events that carry this type.
      class GameComponentCollectionEventArgs < CNA::Runtime::EventArgs
        attr_reader :GameComponent

        def initialize(gameComponent)
          super()
          unless gameComponent.nil? || gameComponent.is_a?(IGameComponent)
            raise TypeError, "gameComponent must be an IGameComponent"
          end

          @GameComponent = gameComponent
        end
      end

      class PlayerIndex < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({ "One" => 0, "Two" => 1, "Three" => 2, "Four" => 3 })
      end

      class DisplayOrientation < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({
          "Default" => 0,
          "LandscapeLeft" => 1,
          "LandscapeRight" => 2,
          "Portrait" => 4
        }, flags: true)
      end
    end
  end
end
