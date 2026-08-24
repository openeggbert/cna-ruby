# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      class Vector2
        class << self
          def Transform(*arguments) = transform_dispatch(arguments, normal: false)
          def TransformNormal(*arguments) = transform_dispatch(arguments, normal: true)

          private

          def transform_one(value, transform, normal: false)
            CNA::Runtime::GeometrySupport.require_type(value, Vector2)
            if transform.instance_of?(Matrix)
              x = N.sum32(N.mul32(value.X, transform.M11), N.mul32(value.Y, transform.M21))
              y = N.sum32(N.mul32(value.X, transform.M12), N.mul32(value.Y, transform.M22))
              return new(x, y) if normal

              return new(N.add32(x, transform.M41), N.add32(y, transform.M42))
            end
            raise TypeError, "TransformNormal expects a Matrix" if normal
            if transform.instance_of?(Quaternion)
              terms = Quaternion.__send__(:rotation_terms, transform)
              return new(
                N.sum32(N.mul32(value.X, terms[0]), N.mul32(value.Y, terms[1])),
                N.sum32(N.mul32(value.X, terms[3]), N.mul32(value.Y, terms[4]))
              )
            end
            raise TypeError, "transform must be Matrix or Quaternion"
          end

          def transform_dispatch(arguments, normal:)
            return transform_one(arguments[0], arguments[1], normal: normal) if arguments.length == 2 && arguments[0].instance_of?(Vector2)

            if arguments.length == 3
              source, transform, destination = arguments
              source_index = destination_index = 0
              length = source.instance_of?(Array) ? source.length : 0
            elsif arguments.length == 6
              source, source_index, transform, destination, destination_index, length = arguments
            else
              raise ArgumentError, "no matching XNA #{normal ? "TransformNormal" : "Transform"} overload"
            end
            source_index, destination_index, length = CNA::Runtime::GeometrySupport.transform_range(
              source, source_index, destination, destination_index, length, Vector2
            )
            length.times do |offset|
              destination[destination_index + offset] = transform_one(source[source_index + offset], transform, normal: normal)
            end
            nil
          end
        end
      end

      class Vector3
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        attr_reader :X, :Y, :Z

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0.0, 0.0, 0.0]
                   when 1 then [arguments[0], arguments[0], arguments[0]]
                   when 2
                     CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector2, "value")
                     [arguments[0].X, arguments[0].Y, arguments[1]]
                   when 3 then arguments
                   else raise ArgumentError, "Vector3.new expects (), (value), (Vector2, z), or (x, y, z)"
                   end
          self.X, self.Y, self.Z = values
        end

        def X=(value)
          @X = N.f32(value)
        end

        def Y=(value)
          @Y = N.f32(value)
        end

        def Z=(value)
          @Z = N.f32(value)
        end

        class << self
          def Zero = new(0.0)
          def One = new(1.0)
          def UnitX = new(1.0, 0.0, 0.0)
          def UnitY = new(0.0, 1.0, 0.0)
          def UnitZ = new(0.0, 0.0, 1.0)
          def Up = new(0.0, 1.0, 0.0)
          def Down = new(0.0, -1.0, 0.0)
          def Right = new(1.0, 0.0, 0.0)
          def Left = new(-1.0, 0.0, 0.0)
          def Forward = new(0.0, 0.0, -1.0)
          def Backward = new(0.0, 0.0, 1.0)
          def Distance(a, b) = (a - b).Length
          def DistanceSquared(a, b) = (a - b).LengthSquared

          def Dot(a, b)
            require_values(a, b)
            N.sum32(N.mul32(a.X, b.X), N.mul32(a.Y, b.Y), N.mul32(a.Z, b.Z))
          end

          def Cross(a, b)
            require_values(a, b)
            new(
              N.sub32(N.mul32(a.Y, b.Z), N.mul32(a.Z, b.Y)),
              N.sub32(N.mul32(a.Z, b.X), N.mul32(a.X, b.Z)),
              N.sub32(N.mul32(a.X, b.Y), N.mul32(a.Y, b.X))
            )
          end

          def Normalize(value) = value.dup.tap(&:Normalize)
          def Reflect(vector, normal) = vector - normal * N.mul32(2.0, Dot(vector, normal))
          def Min(a, b) = component_binary(a, b) { |x, y| x < y ? x : y }
          def Max(a, b) = component_binary(a, b) { |x, y| x > y ? x : y }
          def Clamp(value, minimum, maximum) = new(*components(value).zip(components(minimum), components(maximum)).map { |x, low, high| MathHelper.Clamp(x, low, high) })
          def Lerp(a, b, amount) = component_binary(a, b) { |x, y| MathHelper.Lerp(x, y, amount) }
          def Barycentric(a, b, c, amount1, amount2) = new(*components(a).zip(components(b), components(c)).map { |x, y, z| MathHelper.Barycentric(x, y, z, amount1, amount2) })
          def SmoothStep(a, b, amount) = component_binary(a, b) { |x, y| MathHelper.SmoothStep(x, y, amount) }
          def CatmullRom(a, b, c, d, amount) = new(*components(a).zip(components(b), components(c), components(d)).map { |w, x, y, z| MathHelper.CatmullRom(w, x, y, z, amount) })
          def Hermite(a, tangent1, b, tangent2, amount) = new(*components(a).zip(components(tangent1), components(b), components(tangent2)).map { |w, x, y, z| MathHelper.Hermite(w, x, y, z, amount) })
          def Negate(value) = -value
          def Add(a, b) = a + b
          def Subtract(a, b) = a - b
          def Multiply(a, b) = a * b
          def Divide(a, b) = a / b
          def Transform(*arguments) = transform_dispatch(arguments, normal: false)
          def TransformNormal(*arguments) = transform_dispatch(arguments, normal: true)

          private

          def components(value)
            CNA::Runtime::GeometrySupport.require_type(value, Vector3)
            [value.X, value.Y, value.Z]
          end

          def require_values(*values) = values.each { |value| CNA::Runtime::GeometrySupport.require_type(value, Vector3) }
          def component_binary(a, b, &block) = new(*components(a).zip(components(b)).map(&block))

          def transform_one(value, transform, normal: false)
            CNA::Runtime::GeometrySupport.require_type(value, Vector3)
            if transform.instance_of?(Matrix)
              x = N.sum32(N.mul32(value.X, transform.M11), N.mul32(value.Y, transform.M21), N.mul32(value.Z, transform.M31))
              y = N.sum32(N.mul32(value.X, transform.M12), N.mul32(value.Y, transform.M22), N.mul32(value.Z, transform.M32))
              z = N.sum32(N.mul32(value.X, transform.M13), N.mul32(value.Y, transform.M23), N.mul32(value.Z, transform.M33))
              return new(x, y, z) if normal

              return new(N.add32(x, transform.M41), N.add32(y, transform.M42), N.add32(z, transform.M43))
            end
            raise TypeError, "TransformNormal expects a Matrix" if normal
            if transform.instance_of?(Quaternion)
              terms = Quaternion.__send__(:rotation_terms, transform)
              return new(
                N.sum32(N.mul32(value.X, terms[0]), N.mul32(value.Y, terms[1]), N.mul32(value.Z, terms[2])),
                N.sum32(N.mul32(value.X, terms[3]), N.mul32(value.Y, terms[4]), N.mul32(value.Z, terms[5])),
                N.sum32(N.mul32(value.X, terms[6]), N.mul32(value.Y, terms[7]), N.mul32(value.Z, terms[8]))
              )
            end
            raise TypeError, "transform must be Matrix or Quaternion"
          end

          def transform_dispatch(arguments, normal:)
            return transform_one(arguments[0], arguments[1], normal: normal) if arguments.length == 2 && arguments[0].instance_of?(Vector3)

            if arguments.length == 3
              source, transform, destination = arguments
              source_index = destination_index = 0
              length = source.instance_of?(Array) ? source.length : 0
            elsif arguments.length == 6
              source, source_index, transform, destination, destination_index, length = arguments
            else
              raise ArgumentError, "no matching XNA #{normal ? "TransformNormal" : "Transform"} overload"
            end
            source_index, destination_index, length = CNA::Runtime::GeometrySupport.transform_range(
              source, source_index, destination, destination_index, length, Vector3
            )
            length.times do |offset|
              destination[destination_index + offset] = transform_one(source[source_index + offset], transform, normal: normal)
            end
            nil
          end
        end

        def LengthSquared = N.sum32(N.mul32(@X, @X), N.mul32(@Y, @Y), N.mul32(@Z, @Z))
        def Length = N.sqrt32(self.LengthSquared)

        def Normalize
          factor = N.div32(1.0, self.Length)
          self.X = N.mul32(@X, factor); self.Y = N.mul32(@Y, factor); self.Z = N.mul32(@Z, factor)
          nil
        end

        def -@ = self.class.new(N.neg32(@X), N.neg32(@Y), N.neg32(@Z))

        def +(other)
          require_vector!(other)
          self.class.new(N.add32(@X, other.X), N.add32(@Y, other.Y), N.add32(@Z, other.Z))
        end

        def -(other)
          require_vector!(other)
          self.class.new(N.sub32(@X, other.X), N.sub32(@Y, other.Y), N.sub32(@Z, other.Z))
        end

        def *(other)
          return self.class.new(N.mul32(@X, other.X), N.mul32(@Y, other.Y), N.mul32(@Z, other.Z)) if other.instance_of?(self.class)
          return self.class.new(N.mul32(@X, other), N.mul32(@Y, other), N.mul32(@Z, other)) if other.instance_of?(Integer) || other.instance_of?(Float)

          raise TypeError, "Vector3 multiplication expects Vector3 or Single"
        end

        def /(other)
          return self.class.new(N.div32(@X, other.X), N.div32(@Y, other.Y), N.div32(@Z, other.Z)) if other.instance_of?(self.class)
          if other.instance_of?(Integer) || other.instance_of?(Float)
            factor = N.div32(1.0, other)
            return self.class.new(N.mul32(@X, factor), N.mul32(@Y, factor), N.mul32(@Z, factor))
          end
          raise TypeError, "Vector3 division expects Vector3 or Single"
        end

        def GetHashCode = N.hash32_sum(N.single_hash(@X), N.single_hash(@Y), N.single_hash(@Z))
        def ToString = "{X:#{N.single_string(@X)} Y:#{N.single_string(@Y)} Z:#{N.single_string(@Z)}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y, @Z]
        def require_vector!(value) = CNA::Runtime::GeometrySupport.require_type(value, self.class)
      end

      class Vector4
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N
        attr_reader :X, :Y, :Z, :W

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0.0, 0.0, 0.0, 0.0]
                   when 1 then [arguments[0]] * 4
                   when 2
                     CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector3)
                     [arguments[0].X, arguments[0].Y, arguments[0].Z, arguments[1]]
                   when 3
                     CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector2)
                     [arguments[0].X, arguments[0].Y, arguments[1], arguments[2]]
                   when 4 then arguments
                   else raise ArgumentError, "no matching XNA Vector4 constructor"
                   end
          self.X, self.Y, self.Z, self.W = values
        end

        def X=(value)
          @X = N.f32(value)
        end

        def Y=(value)
          @Y = N.f32(value)
        end

        def Z=(value)
          @Z = N.f32(value)
        end

        def W=(value)
          @W = N.f32(value)
        end

        class << self
          def Zero = new(0.0)
          def One = new(1.0)
          def UnitX = new(1.0, 0.0, 0.0, 0.0)
          def UnitY = new(0.0, 1.0, 0.0, 0.0)
          def UnitZ = new(0.0, 0.0, 1.0, 0.0)
          def UnitW = new(0.0, 0.0, 0.0, 1.0)
          def Distance(a, b) = (a - b).Length
          def DistanceSquared(a, b) = (a - b).LengthSquared
          def Dot(a, b) = N.sum32(*components(a).zip(components(b)).map { |x, y| N.mul32(x, y) })
          def Normalize(value) = value.dup.tap(&:Normalize)
          def Min(a, b) = component_binary(a, b) { |x, y| x < y ? x : y }
          def Max(a, b) = component_binary(a, b) { |x, y| x > y ? x : y }
          def Clamp(value, minimum, maximum) = new(*components(value).zip(components(minimum), components(maximum)).map { |x, low, high| MathHelper.Clamp(x, low, high) })
          def Lerp(a, b, amount) = component_binary(a, b) { |x, y| MathHelper.Lerp(x, y, amount) }
          def Barycentric(a, b, c, amount1, amount2) = new(*components(a).zip(components(b), components(c)).map { |x, y, z| MathHelper.Barycentric(x, y, z, amount1, amount2) })
          def SmoothStep(a, b, amount) = component_binary(a, b) { |x, y| MathHelper.SmoothStep(x, y, amount) }
          def CatmullRom(a, b, c, d, amount) = new(*components(a).zip(components(b), components(c), components(d)).map { |w, x, y, z| MathHelper.CatmullRom(w, x, y, z, amount) })
          def Hermite(a, tangent1, b, tangent2, amount) = new(*components(a).zip(components(tangent1), components(b), components(tangent2)).map { |w, x, y, z| MathHelper.Hermite(w, x, y, z, amount) })
          def Negate(value) = -value
          def Add(a, b) = a + b
          def Subtract(a, b) = a - b
          def Multiply(a, b) = a * b
          def Divide(a, b) = a / b
          def Transform(*arguments) = transform_dispatch(arguments)

          private

          def components(value)
            CNA::Runtime::GeometrySupport.require_type(value, Vector4)
            [value.X, value.Y, value.Z, value.W]
          end

          def component_binary(a, b, &block) = new(*components(a).zip(components(b)).map(&block))

          def transform_one(value, transform)
            if transform.instance_of?(Quaternion)
              if value.instance_of?(Vector2)
                rotated = Vector3.__send__(:transform_one, Vector3.new(value.X, value.Y, 0.0), transform)
                return new(rotated, 1.0)
              elsif value.instance_of?(Vector3)
                return new(Vector3.__send__(:transform_one, value, transform), 1.0)
              elsif value.instance_of?(Vector4)
                rotated = Vector3.__send__(:transform_one, Vector3.new(value.X, value.Y, value.Z), transform)
                return new(rotated, value.W)
              end
              raise TypeError, "value must be Vector2, Vector3, or Vector4"
            end
            raise TypeError, "transform must be Matrix or Quaternion" unless transform.instance_of?(Matrix)

            values = if value.instance_of?(Vector2)
                       [value.X, value.Y, 0.0, 1.0]
                     elsif value.instance_of?(Vector3)
                       [value.X, value.Y, value.Z, 1.0]
                     elsif value.instance_of?(Vector4)
                       [value.X, value.Y, value.Z, value.W]
                     else
                       raise TypeError, "value must be Vector2, Vector3, or Vector4"
                     end
            new(*(1..4).map do |column|
              N.sum32(*(1..4).map { |row| N.mul32(values[row - 1], transform.public_send("M#{row}#{column}")) })
            end)
          end

          def transform_dispatch(arguments)
            if arguments.length == 2 && [Vector2, Vector3, Vector4].any? { |type| arguments[0].instance_of?(type) }
              return transform_one(arguments[0], arguments[1])
            end
            if arguments.length == 3
              source, transform, destination = arguments
              source_index = destination_index = 0
              length = source.instance_of?(Array) ? source.length : 0
            elsif arguments.length == 6
              source, source_index, transform, destination, destination_index, length = arguments
            else
              raise ArgumentError, "no matching XNA Vector4.Transform overload"
            end
            source_index, destination_index, length = CNA::Runtime::GeometrySupport.transform_range(
              source, source_index, destination, destination_index, length, Vector4
            )
            length.times { |offset| destination[destination_index + offset] = transform_one(source[source_index + offset], transform) }
            nil
          end
        end

        def LengthSquared = N.sum32(N.mul32(@X, @X), N.mul32(@Y, @Y), N.mul32(@Z, @Z), N.mul32(@W, @W))
        def Length = N.sqrt32(self.LengthSquared)

        def Normalize
          factor = N.div32(1.0, self.Length)
          self.X = N.mul32(@X, factor); self.Y = N.mul32(@Y, factor)
          self.Z = N.mul32(@Z, factor); self.W = N.mul32(@W, factor)
          nil
        end

        def -@ = self.class.new(*value_components.map { |value| N.neg32(value) })
        def +(other) = component_operator(other) { |a, b| N.add32(a, b) }
        def -(other) = component_operator(other) { |a, b| N.sub32(a, b) }

        def *(other)
          return component_operator(other) { |a, b| N.mul32(a, b) } if other.instance_of?(self.class)
          return self.class.new(*value_components.map { |value| N.mul32(value, other) }) if other.instance_of?(Integer) || other.instance_of?(Float)

          raise TypeError, "Vector4 multiplication expects Vector4 or Single"
        end

        def /(other)
          return component_operator(other) { |a, b| N.div32(a, b) } if other.instance_of?(self.class)
          if other.instance_of?(Integer) || other.instance_of?(Float)
            factor = N.div32(1.0, other)
            return self.class.new(*value_components.map { |value| N.mul32(value, factor) })
          end
          raise TypeError, "Vector4 division expects Vector4 or Single"
        end

        def GetHashCode = N.hash32_sum(*value_components.map { |value| N.single_hash(value) })
        def ToString = "{X:#{N.single_string(@X)} Y:#{N.single_string(@Y)} Z:#{N.single_string(@Z)} W:#{N.single_string(@W)}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y, @Z, @W]
        def component_operator(other)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          self.class.new(*value_components.zip(other.__send__(:value_components)).map { |a, b| yield(a, b) })
        end
      end

      class Quaternion
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N
        attr_reader :X, :Y, :Z, :W

        def initialize(*arguments)
          values = case arguments.length
                   when 0 then [0.0, 0.0, 0.0, 0.0]
                   when 2
                     CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector3, "vectorPart")
                     [arguments[0].X, arguments[0].Y, arguments[0].Z, arguments[1]]
                   when 4 then arguments
                   else raise ArgumentError, "Quaternion.new expects (), (Vector3, scalarPart), or (x, y, z, w)"
                   end
          self.X, self.Y, self.Z, self.W = values
        end

        def X=(value)
          @X = N.f32(value)
        end

        def Y=(value)
          @Y = N.f32(value)
        end

        def Z=(value)
          @Z = N.f32(value)
        end

        def W=(value)
          @W = N.f32(value)
        end

        class << self
          def Identity = new(0.0, 0.0, 0.0, 1.0)
          def Normalize(value) = value.dup.tap(&:Normalize)
          def Conjugate(value) = new(N.neg32(value.X), N.neg32(value.Y), N.neg32(value.Z), value.W)
          def Dot(a, b) = N.sum32(*components(a).zip(components(b)).map { |x, y| N.mul32(x, y) })

          def Inverse(value)
            factor = N.div32(1.0, value.LengthSquared)
            new(N.mul32(N.neg32(value.X), factor), N.mul32(N.neg32(value.Y), factor),
                N.mul32(N.neg32(value.Z), factor), N.mul32(value.W, factor))
          end

          def CreateFromAxisAngle(axis, angle)
            CNA::Runtime::GeometrySupport.require_type(axis, Vector3, "axis")
            half = N.mul32(angle, 0.5); sine = N.sin32(half)
            new(N.mul32(axis.X, sine), N.mul32(axis.Y, sine), N.mul32(axis.Z, sine), N.cos32(half))
          end

          def CreateFromYawPitchRoll(yaw, pitch, roll)
            half_roll = N.mul32(roll, 0.5); sr = N.sin32(half_roll); cr = N.cos32(half_roll)
            half_pitch = N.mul32(pitch, 0.5); sp = N.sin32(half_pitch); cp = N.cos32(half_pitch)
            half_yaw = N.mul32(yaw, 0.5); sy = N.sin32(half_yaw); cy = N.cos32(half_yaw)
            new(
              N.add32(N.mul32(N.mul32(cy, sp), cr), N.mul32(N.mul32(sy, cp), sr)),
              N.sub32(N.mul32(N.mul32(sy, cp), cr), N.mul32(N.mul32(cy, sp), sr)),
              N.sub32(N.mul32(N.mul32(cy, cp), sr), N.mul32(N.mul32(sy, sp), cr)),
              N.add32(N.mul32(N.mul32(cy, cp), cr), N.mul32(N.mul32(sy, sp), sr))
            )
          end

          def CreateFromRotationMatrix(matrix)
            CNA::Runtime::GeometrySupport.require_type(matrix, Matrix, "matrix")
            trace = N.sum32(matrix.M11, matrix.M22, matrix.M33)
            if trace > 0.0
              root = N.sqrt32(N.add32(trace, 1.0)); factor = N.div32(0.5, root)
              return new(N.mul32(N.sub32(matrix.M23, matrix.M32), factor),
                         N.mul32(N.sub32(matrix.M31, matrix.M13), factor),
                         N.mul32(N.sub32(matrix.M12, matrix.M21), factor), N.mul32(root, 0.5))
            end
            if matrix.M11 >= matrix.M22 && matrix.M11 >= matrix.M33
              root = N.sqrt32(N.sub32(N.sub32(N.add32(1.0, matrix.M11), matrix.M22), matrix.M33)); factor = N.div32(0.5, root)
              return new(N.mul32(0.5, root), N.mul32(N.add32(matrix.M12, matrix.M21), factor),
                         N.mul32(N.add32(matrix.M13, matrix.M31), factor), N.mul32(N.sub32(matrix.M23, matrix.M32), factor))
            end
            if matrix.M22 > matrix.M33
              root = N.sqrt32(N.sub32(N.sub32(N.add32(1.0, matrix.M22), matrix.M11), matrix.M33)); factor = N.div32(0.5, root)
              return new(N.mul32(N.add32(matrix.M21, matrix.M12), factor), N.mul32(0.5, root),
                         N.mul32(N.add32(matrix.M32, matrix.M23), factor), N.mul32(N.sub32(matrix.M31, matrix.M13), factor))
            end
            root = N.sqrt32(N.sub32(N.sub32(N.add32(1.0, matrix.M33), matrix.M11), matrix.M22)); factor = N.div32(0.5, root)
            new(N.mul32(N.add32(matrix.M31, matrix.M13), factor), N.mul32(N.add32(matrix.M32, matrix.M23), factor),
                N.mul32(0.5, root), N.mul32(N.sub32(matrix.M12, matrix.M21), factor))
          end

          def Lerp(a, b, amount)
            inverse = N.sub32(1.0, amount)
            result = if Dot(a, b) >= 0.0
                       new(*components(a).zip(components(b)).map { |x, y| N.add32(N.mul32(inverse, x), N.mul32(amount, y)) })
                     else
                       new(*components(a).zip(components(b)).map { |x, y| N.sub32(N.mul32(inverse, x), N.mul32(amount, y)) })
                     end
            Normalize(result)
          end

          def Slerp(a, b, amount)
            cosine = Dot(a, b); flip = cosine < 0.0; cosine = N.neg32(cosine) if flip
            if cosine > N.f32(0.999999)
              left = N.sub32(1.0, amount); right = flip ? N.neg32(amount) : N.f32(amount)
            else
              angle = N.acos32(cosine)
              inverse_sine = N.div32(1.0, N.sin32(angle))
              left = N.mul32(N.sin32(N.mul32(N.sub32(1.0, amount), angle)), inverse_sine)
              right = N.mul32(N.sin32(N.mul32(amount, angle)), inverse_sine)
              right = N.neg32(right) if flip
            end
            new(*components(a).zip(components(b)).map { |x, y| N.add32(N.mul32(x, left), N.mul32(y, right)) })
          end

          def Concatenate(value1, value2)
            components(value1); components(value2)
            value2 * value1
          end

          def Negate(value) = -value
          def Add(a, b) = a + b
          def Subtract(a, b) = a - b
          def Multiply(a, b) = a * b
          def Divide(a, b) = a / b

          private

          def components(value)
            CNA::Runtime::GeometrySupport.require_type(value, Quaternion)
            [value.X, value.Y, value.Z, value.W]
          end

          def rotation_terms(rotation)
            components(rotation)
            x2 = N.add32(rotation.X, rotation.X); y2 = N.add32(rotation.Y, rotation.Y); z2 = N.add32(rotation.Z, rotation.Z)
            wx2 = N.mul32(rotation.W, x2); wy2 = N.mul32(rotation.W, y2); wz2 = N.mul32(rotation.W, z2)
            xx2 = N.mul32(rotation.X, x2); xy2 = N.mul32(rotation.X, y2); xz2 = N.mul32(rotation.X, z2)
            yy2 = N.mul32(rotation.Y, y2); yz2 = N.mul32(rotation.Y, z2); zz2 = N.mul32(rotation.Z, z2)
            [N.sub32(N.sub32(1.0, yy2), zz2), N.sub32(xy2, wz2), N.add32(xz2, wy2),
             N.add32(xy2, wz2), N.sub32(N.sub32(1.0, xx2), zz2), N.sub32(yz2, wx2),
             N.sub32(xz2, wy2), N.add32(yz2, wx2), N.sub32(N.sub32(1.0, xx2), yy2)]
          end
        end

        def LengthSquared = N.sum32(N.mul32(@X, @X), N.mul32(@Y, @Y), N.mul32(@Z, @Z), N.mul32(@W, @W))
        def Length = N.sqrt32(self.LengthSquared)

        def Normalize
          factor = N.div32(1.0, self.Length)
          self.X = N.mul32(@X, factor); self.Y = N.mul32(@Y, factor)
          self.Z = N.mul32(@Z, factor); self.W = N.mul32(@W, factor)
          nil
        end

        def Conjugate
          self.X = N.neg32(@X); self.Y = N.neg32(@Y); self.Z = N.neg32(@Z)
          nil
        end

        def -@ = self.class.new(*value_components.map { |value| N.neg32(value) })
        def +(other) = component_operator(other) { |a, b| N.add32(a, b) }
        def -(other) = component_operator(other) { |a, b| N.sub32(a, b) }

        def *(other)
          return self.class.new(*value_components.map { |value| N.mul32(value, other) }) if other.instance_of?(Integer) || other.instance_of?(Float)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          self.class.new(
            N.add32(N.add32(N.mul32(@X, other.W), N.mul32(other.X, @W)), N.sub32(N.mul32(@Y, other.Z), N.mul32(@Z, other.Y))),
            N.add32(N.add32(N.mul32(@Y, other.W), N.mul32(other.Y, @W)), N.sub32(N.mul32(@Z, other.X), N.mul32(@X, other.Z))),
            N.add32(N.add32(N.mul32(@Z, other.W), N.mul32(other.Z, @W)), N.sub32(N.mul32(@X, other.Y), N.mul32(@Y, other.X))),
            N.sub32(N.mul32(@W, other.W), N.sum32(N.mul32(@X, other.X), N.mul32(@Y, other.Y), N.mul32(@Z, other.Z)))
          )
        end

        def /(other)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          self * self.class.Inverse(other)
        end

        def GetHashCode = N.hash32_sum(*value_components.map { |value| N.single_hash(value) })
        def ToString = "{X:#{N.single_string(@X)} Y:#{N.single_string(@Y)} Z:#{N.single_string(@Z)} W:#{N.single_string(@W)}}"
        alias to_s ToString

        private

        def value_components = [@X, @Y, @Z, @W]
        def component_operator(other)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          self.class.new(*value_components.zip(other.__send__(:value_components)).map { |a, b| yield(a, b) })
        end
      end
    end
  end
end
