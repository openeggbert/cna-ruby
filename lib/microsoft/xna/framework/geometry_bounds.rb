# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      class ContainmentType < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({ "Disjoint" => 0, "Contains" => 1, "Intersects" => 2 })
      end

      class PlaneIntersectionType < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({ "Front" => 0, "Back" => 1, "Intersecting" => 2 })
      end

      class Plane
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        def initialize(*arguments)
          normal, d = case arguments.length
                      when 0
                        [Vector3.Zero, 0.0]
                      when 1
                        value = CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector4, "value")
                        [Vector3.new(value.X, value.Y, value.Z), value.W]
                      when 2
                        [CNA::Runtime::GeometrySupport.require_type(arguments[0], Vector3, "normal"), arguments[1]]
                      when 3
                        point1, point2, point3 = arguments
                        [point1, point2, point3].each { |value| CNA::Runtime::GeometrySupport.require_type(value, Vector3, "point") }
                        result = Vector3.Normalize(Vector3.Cross(point2 - point1, point3 - point1))
                        [result, N.neg32(Vector3.Dot(result, point1))]
                      when 4
                        [Vector3.new(arguments[0], arguments[1], arguments[2]), arguments[3]]
                      else
                        raise ArgumentError, "Plane.new expects (), Vector4, (normal, d), three points, or (a, b, c, d)"
                      end
          self.Normal = normal
          self.D = d
        end

        def Normal = @normal.dup
        def D = @d

        def Normal=(value)
          @normal = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Normal").dup
        end

        def D=(value)
          @d = N.f32(value)
        end

        class << self
          def Normalize(value)
            result = CNA::Runtime::GeometrySupport.require_type(value, Plane, "value").dup
            result.Normalize
            result
          end

          def Transform(plane, transform)
            plane = CNA::Runtime::GeometrySupport.require_type(plane, Plane, "plane")
            if transform.instance_of?(Matrix)
              inverse = Matrix.Invert(transform)
              normal = plane.Normal
              return new(
                dot4(normal.X, normal.Y, normal.Z, plane.D, inverse.M11, inverse.M12, inverse.M13, inverse.M14),
                dot4(normal.X, normal.Y, normal.Z, plane.D, inverse.M21, inverse.M22, inverse.M23, inverse.M24),
                dot4(normal.X, normal.Y, normal.Z, plane.D, inverse.M31, inverse.M32, inverse.M33, inverse.M34),
                dot4(normal.X, normal.Y, normal.Z, plane.D, inverse.M41, inverse.M42, inverse.M43, inverse.M44)
              )
            end
            return new(Vector3.Transform(plane.Normal, transform), plane.D) if transform.instance_of?(Quaternion)

            raise TypeError, "transform must be Matrix or Quaternion"
          end

          private

          def dot4(x, y, z, w, a, b, c, d)
            N.add32(N.add32(N.mul32(x, a), N.mul32(y, b)), N.add32(N.mul32(z, c), N.mul32(w, d)))
          end
        end

        def Normalize
          length_squared = @normal.LengthSquared
          unless N.sub32(length_squared, 1.0).abs < N.f32(1.1920929e-7)
            factor = N.div32(1.0, N.sqrt32(length_squared))
            @normal = @normal * factor
            @d = N.mul32(@d, factor)
          end
          nil
        end

        def Dot(value)
          value = CNA::Runtime::GeometrySupport.require_type(value, Vector4, "value")
          N.add32(N.add32(N.mul32(@normal.X, value.X), N.mul32(@normal.Y, value.Y)),
                  N.add32(N.mul32(@normal.Z, value.Z), N.mul32(@d, value.W)))
        end

        def DotCoordinate(value)
          N.add32(Vector3.Dot(@normal, CNA::Runtime::GeometrySupport.require_type(value, Vector3, "value")), @d)
        end

        def DotNormal(value)
          Vector3.Dot(@normal, CNA::Runtime::GeometrySupport.require_type(value, Vector3, "value"))
        end

        def Intersects(value)
          case value
          when BoundingSphere
            distance = DotCoordinate(value.Center)
            return PlaneIntersectionType::Front if distance > value.Radius
            return PlaneIntersectionType::Back if distance < N.neg32(value.Radius)
            PlaneIntersectionType::Intersecting
          when BoundingBox
            minimum = value.Min; maximum = value.Max
            negative = Vector3.new(@normal.X >= 0 ? minimum.X : maximum.X,
                                   @normal.Y >= 0 ? minimum.Y : maximum.Y,
                                   @normal.Z >= 0 ? minimum.Z : maximum.Z)
            positive = Vector3.new(@normal.X >= 0 ? maximum.X : minimum.X,
                                   @normal.Y >= 0 ? maximum.Y : minimum.Y,
                                   @normal.Z >= 0 ? maximum.Z : minimum.Z)
            return PlaneIntersectionType::Front if DotCoordinate(negative) > 0
            DotCoordinate(positive) < 0 ? PlaneIntersectionType::Back : PlaneIntersectionType::Intersecting
          when BoundingFrustum
            value.Intersects(self)
          else
            raise TypeError, "Plane.Intersects expects BoundingBox, BoundingSphere, or BoundingFrustum"
          end
        end

        def GetHashCode = N.hash32_sum(@normal.GetHashCode, N.single_hash(@d))
        def ToString = "{Normal:#{@normal} D:#{N.single_string(@d)}}"
        alias to_s ToString

        private

        def value_components = [@normal.dup, @d]
      end

      class Ray
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        def initialize(*arguments)
          position, direction = case arguments.length
                                when 0 then [Vector3.Zero, Vector3.Zero]
                                when 2 then arguments
                                else raise ArgumentError, "Ray.new expects () or (position, direction)"
                                end
          self.Position = position
          self.Direction = direction
        end

        def Position = @position.dup
        def Direction = @direction.dup

        def Position=(value)
          @position = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Position").dup
        end

        def Direction=(value)
          @direction = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Direction").dup
        end

        def Intersects(value)
          case value
          when BoundingBox, BoundingFrustum
            value.Intersects(self)
          when BoundingSphere
            offset = value.Center - @position
            distance_squared = offset.LengthSquared
            radius_squared = N.mul32(value.Radius, value.Radius)
            return N.f32(0) if distance_squared <= radius_squared
            projection = Vector3.Dot(offset, @direction)
            return nil if projection < 0
            closest_squared = N.sub32(distance_squared, N.mul32(projection, projection))
            return nil if closest_squared > radius_squared
            N.sub32(projection, N.sqrt32(N.sub32(radius_squared, closest_squared)))
          when Plane
            denominator = Vector3.Dot(value.Normal, @direction)
            return nil if denominator.abs < N.f32(1.0e-5)
            distance = N.div32(N.neg32(N.add32(Vector3.Dot(value.Normal, @position), value.D)), denominator)
            return(distance < N.f32(-1.0e-5) ? nil : N.f32(0)) if distance < 0
            distance
          else
            raise TypeError, "Ray.Intersects expects BoundingBox, BoundingSphere, BoundingFrustum, or Plane"
          end
        end

        def GetHashCode = N.hash32_sum(@position.GetHashCode, @direction.GetHashCode)
        def ToString = "{Position:#{@position} Direction:#{@direction}}"
        alias to_s ToString

        private

        def value_components = [@position.dup, @direction.dup]
      end

      class BoundingBox
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N
        CornerCount = 8

        def initialize(*arguments)
          minimum, maximum = case arguments.length
                             when 0 then [Vector3.Zero, Vector3.Zero]
                             when 2 then arguments
                             else raise ArgumentError, "BoundingBox.new expects () or (min, max)"
                             end
          self.Min = minimum
          self.Max = maximum
        end

        def Min = @min.dup
        def Max = @max.dup

        def Min=(value)
          @min = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Min").dup
        end

        def Max=(value)
          @max = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Max").dup
        end

        class << self
          def CreateMerged(original, additional)
            original = CNA::Runtime::GeometrySupport.require_type(original, BoundingBox, "original")
            additional = CNA::Runtime::GeometrySupport.require_type(additional, BoundingBox, "additional")
            new(Vector3.Min(original.Min, additional.Min), Vector3.Max(original.Max, additional.Max))
          end

          def CreateFromSphere(sphere)
            sphere = CNA::Runtime::GeometrySupport.require_type(sphere, BoundingSphere, "sphere")
            radius = Vector3.new(sphere.Radius)
            new(sphere.Center - radius, sphere.Center + radius)
          end

          def CreateFromPoints(points)
            values = geometry_points(points)
            minimum = Vector3.new(N.f32(3.402823466e38)); maximum = Vector3.new(N.f32(-3.402823466e38))
            values.each do |value|
              minimum = Vector3.Min(minimum, value)
              maximum = Vector3.Max(maximum, value)
            end
            new(minimum, maximum)
          end

          private

          def geometry_points(points)
            raise TypeError, "points cannot be nil" if points.nil?
            values = points.to_a
            raise ArgumentError, "points must contain at least one point" if values.empty?
            values.each { |value| CNA::Runtime::GeometrySupport.require_type(value, Vector3, "point") }
            values
          rescue NoMethodError
            raise TypeError, "points must be enumerable"
          end
        end

        def GetCorners(corners = :__return__)
          values = corner_values
          return values if corners == :__return__
          corners = CNA::Runtime::GeometrySupport.require_array(corners, "corners")
          raise ArgumentError, "corners must contain at least eight entries" if corners.length < CornerCount
          values.each_with_index { |value, index| corners[index] = value }
          nil
        end

        def Contains(value)
          case value
          when Vector3
            (@min.X <= value.X && value.X <= @max.X && @min.Y <= value.Y && value.Y <= @max.Y &&
              @min.Z <= value.Z && value.Z <= @max.Z) ? ContainmentType::Contains : ContainmentType::Disjoint
          when BoundingBox
            return ContainmentType::Disjoint unless Intersects(value)
            (@min.X <= value.Min.X && value.Max.X <= @max.X && @min.Y <= value.Min.Y && value.Max.Y <= @max.Y &&
              @min.Z <= value.Min.Z && value.Max.Z <= @max.Z) ? ContainmentType::Contains : ContainmentType::Intersects
          when BoundingSphere
            return ContainmentType::Disjoint unless Intersects(value)
            center = value.Center; radius = value.Radius
            contained = N.add32(@min.X, radius) <= center.X && center.X <= N.sub32(@max.X, radius) && N.sub32(@max.X, @min.X) > radius &&
                        N.add32(@min.Y, radius) <= center.Y && center.Y <= N.sub32(@max.Y, radius) && N.sub32(@max.Y, @min.Y) > radius &&
                        N.add32(@min.Z, radius) <= center.Z && center.Z <= N.sub32(@max.Z, radius) && N.sub32(@max.Z, @min.Z) > radius
            contained ? ContainmentType::Contains : ContainmentType::Intersects
          when BoundingFrustum
            return ContainmentType::Contains if value.GetCorners.all? { |corner| Contains(corner) == ContainmentType::Contains }
            Intersects(value) ? ContainmentType::Intersects : ContainmentType::Disjoint
          else
            raise TypeError, "BoundingBox.Contains received an unsupported value"
          end
        end

        def Intersects(value)
          case value
          when BoundingBox
            !(@max.X < value.Min.X || @min.X > value.Max.X || @max.Y < value.Min.Y || @min.Y > value.Max.Y ||
              @max.Z < value.Min.Z || @min.Z > value.Max.Z)
          when BoundingSphere
            closest = Vector3.Clamp(value.Center, @min, @max)
            Vector3.DistanceSquared(value.Center, closest) <= N.mul32(value.Radius, value.Radius)
          when BoundingFrustum
            value.Intersects(self)
          when Plane
            value.Intersects(self)
          when Ray
            ray_intersection(value)
          else
            raise TypeError, "BoundingBox.Intersects received an unsupported value"
          end
        end

        def GetHashCode = N.hash32_sum(@min.GetHashCode, @max.GetHashCode)
        def ToString = "{Min:#{@min} Max:#{@max}}"
        alias to_s ToString

        private

        def value_components = [@min.dup, @max.dup]

        def corner_values
          [
            Vector3.new(@min.X, @max.Y, @max.Z), Vector3.new(@max.X, @max.Y, @max.Z),
            Vector3.new(@max.X, @min.Y, @max.Z), Vector3.new(@min.X, @min.Y, @max.Z),
            Vector3.new(@min.X, @max.Y, @min.Z), Vector3.new(@max.X, @max.Y, @min.Z),
            Vector3.new(@max.X, @min.Y, @min.Z), Vector3.new(@min.X, @min.Y, @min.Z)
          ]
        end

        def ray_intersection(ray)
          distance = N.f32(0); maximum_distance = N.f32(3.402823466e38)
          [[ray.Position.X, ray.Direction.X, @min.X, @max.X],
           [ray.Position.Y, ray.Direction.Y, @min.Y, @max.Y],
           [ray.Position.Z, ray.Direction.Z, @min.Z, @max.Z]].each do |position, direction, low, high|
            if direction.abs < N.f32(1.0e-6)
              return nil if position < low || position > high
              next
            end
            inverse = N.div32(1, direction); near = N.mul32(N.sub32(low, position), inverse); far = N.mul32(N.sub32(high, position), inverse)
            near, far = far, near if near > far
            distance = MathHelper.Max(near, distance); maximum_distance = MathHelper.Min(far, maximum_distance)
            return nil if distance > maximum_distance
          end
          distance
        end

        def gjk_center = Vector3.Lerp(@min, @max, 0.5)
        def gjk_support(direction) = Vector3.new(direction.X >= 0 ? @max.X : @min.X,
                                                 direction.Y >= 0 ? @max.Y : @min.Y,
                                                 direction.Z >= 0 ? @max.Z : @min.Z)
      end

      class BoundingSphere
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        private_constant :N

        def initialize(*arguments)
          center, radius = case arguments.length
                           when 0 then [Vector3.Zero, 0.0]
                           when 2 then arguments
                           else raise ArgumentError, "BoundingSphere.new expects () or (center, radius)"
                           end
          self.Center = center
          self.Radius = radius
        end

        def Center = @center.dup
        def Radius = @radius

        def Center=(value)
          @center = CNA::Runtime::GeometrySupport.require_type(value, Vector3, "Center").dup
        end

        def Radius=(value)
          converted = N.f32(value)
          raise ArgumentError, "radius must be non-negative" if converted < 0
          @radius = converted
        end

        class << self
          def CreateFromBoundingBox(box)
            box = CNA::Runtime::GeometrySupport.require_type(box, BoundingBox, "box")
            center = Vector3.Lerp(box.Min, box.Max, 0.5)
            new(center, N.mul32(Vector3.Distance(box.Min, box.Max), 0.5))
          end

          def CreateFromFrustum(frustum)
            frustum = CNA::Runtime::GeometrySupport.require_type(frustum, BoundingFrustum, "frustum")
            CreateFromPoints(frustum.GetCorners)
          end

          def CreateMerged(original, additional)
            original = CNA::Runtime::GeometrySupport.require_type(original, BoundingSphere, "original")
            additional = CNA::Runtime::GeometrySupport.require_type(additional, BoundingSphere, "additional")
            difference = additional.Center - original.Center; distance = difference.Length
            if N.add32(original.Radius, additional.Radius) >= distance
              return original.dup if N.sub32(original.Radius, additional.Radius) >= distance
              return additional.dup if N.sub32(additional.Radius, original.Radius) >= distance
            end
            direction = difference * N.div32(1, distance)
            minimum = MathHelper.Min(N.neg32(original.Radius), N.sub32(distance, additional.Radius))
            maximum = MathHelper.Max(original.Radius, N.add32(distance, additional.Radius))
            radius = N.mul32(N.sub32(maximum, minimum), 0.5)
            new(original.Center + direction * N.add32(radius, minimum), radius)
          end

          def CreateFromPoints(points)
            values = BoundingBox.__send__(:geometry_points, points)
            min_x = max_x = min_y = max_y = min_z = max_z = values[0]
            values.each do |value|
              min_x = value if value.X < min_x.X; max_x = value if value.X > max_x.X
              min_y = value if value.Y < min_y.Y; max_y = value if value.Y > max_y.Y
              min_z = value if value.Z < min_z.Z; max_z = value if value.Z > max_z.Z
            end
            pairs = [[min_x, max_x], [min_y, max_y], [min_z, max_z]]
            first, last = pairs.max_by { |a, b| Vector3.Distance(a, b) }
            center = Vector3.Lerp(last, first, 0.5); radius = N.mul32(Vector3.Distance(first, last), 0.5)
            values.each do |value|
              offset = value - center; distance = offset.Length
              next unless distance > radius
              radius = N.mul32(N.add32(radius, distance), 0.5)
              center += offset * N.sub32(1, N.div32(radius, distance))
            end
            new(center, radius)
          end
        end

        def Contains(value)
          case value
          when Vector3
            Vector3.DistanceSquared(@center, value) < N.mul32(@radius, @radius) ? ContainmentType::Contains : ContainmentType::Disjoint
          when BoundingSphere
            distance = Vector3.Distance(@center, value.Center)
            return ContainmentType::Disjoint if N.add32(@radius, value.Radius) < distance
            N.sub32(@radius, value.Radius) >= distance ? ContainmentType::Contains : ContainmentType::Intersects
          when BoundingBox
            return ContainmentType::Disjoint unless value.Intersects(self)
            radius_squared = N.mul32(@radius, @radius)
            value.GetCorners.all? { |corner| Vector3.DistanceSquared(@center, corner) <= radius_squared } ? ContainmentType::Contains : ContainmentType::Intersects
          when BoundingFrustum
            return ContainmentType::Contains if value.GetCorners.all? { |corner| Contains(corner) == ContainmentType::Contains }
            Intersects(value) ? ContainmentType::Intersects : ContainmentType::Disjoint
          else
            raise TypeError, "BoundingSphere.Contains received an unsupported value"
          end
        end

        def Intersects(value)
          case value
          when BoundingBox, BoundingFrustum, Plane, Ray
            value.Intersects(self)
          when BoundingSphere
            total = N.add32(@radius, value.Radius)
            N.mul32(total, total) > Vector3.DistanceSquared(@center, value.Center)
          else
            raise TypeError, "BoundingSphere.Intersects received an unsupported value"
          end
        end

        def Transform(matrix)
          matrix = CNA::Runtime::GeometrySupport.require_type(matrix, Matrix, "matrix")
          lengths = [[matrix.M11, matrix.M12, matrix.M13], [matrix.M21, matrix.M22, matrix.M23], [matrix.M31, matrix.M32, matrix.M33]].map do |row|
            N.sum32(*row.map { |value| N.mul32(value, value) })
          end
          self.class.new(Vector3.Transform(@center, matrix), N.mul32(@radius, N.sqrt32(lengths.max)))
        end

        def GetHashCode = N.hash32_sum(@center.GetHashCode, N.single_hash(@radius))
        def ToString = "{Center:#{@center} Radius:#{N.single_string(@radius)}}"
        alias to_s ToString

        private

        def value_components = [@center.dup, @radius]
        def gjk_center = @center.dup
        def gjk_support(direction)
          length = direction.Length
          length.zero? ? @center.dup : @center + direction * N.div32(@radius, length)
        end
      end

      class BoundingFrustum
        N = CNA::Runtime::Numeric
        private_constant :N
        CornerCount = 8

        def initialize(value)
          self.Matrix = value
        end

        def Matrix = @matrix.dup
        def Near = @planes[0].dup
        def Far = @planes[1].dup
        def Left = @planes[2].dup
        def Right = @planes[3].dup
        def Top = @planes[4].dup
        def Bottom = @planes[5].dup

        def Matrix=(value)
          value = CNA::Runtime::GeometrySupport.require_type(value, Matrix, "Matrix")
          @matrix = value.dup
          @planes = [
            Plane.new(N.neg32(value.M13), N.neg32(value.M23), N.neg32(value.M33), N.neg32(value.M43)),
            Plane.new(N.add32(N.neg32(value.M14), value.M13), N.add32(N.neg32(value.M24), value.M23), N.add32(N.neg32(value.M34), value.M33), N.add32(N.neg32(value.M44), value.M43)),
            Plane.new(N.sub32(N.neg32(value.M14), value.M11), N.sub32(N.neg32(value.M24), value.M21), N.sub32(N.neg32(value.M34), value.M31), N.sub32(N.neg32(value.M44), value.M41)),
            Plane.new(N.add32(N.neg32(value.M14), value.M11), N.add32(N.neg32(value.M24), value.M21), N.add32(N.neg32(value.M34), value.M31), N.add32(N.neg32(value.M44), value.M41)),
            Plane.new(N.add32(N.neg32(value.M14), value.M12), N.add32(N.neg32(value.M24), value.M22), N.add32(N.neg32(value.M34), value.M32), N.add32(N.neg32(value.M44), value.M42)),
            Plane.new(N.sub32(N.neg32(value.M14), value.M12), N.sub32(N.neg32(value.M24), value.M22), N.sub32(N.neg32(value.M34), value.M32), N.sub32(N.neg32(value.M44), value.M42))
          ]
          @planes.each do |plane|
            length = plane.Normal.Length
            plane.Normal = plane.Normal / length
            plane.D = N.div32(plane.D, length)
          end
          lines = [line(0, 2), line(3, 0), line(2, 1), line(1, 3)]
          @corners = Array.new(8)
          @corners[0] = plane_line_intersection(4, lines[0]); @corners[3] = plane_line_intersection(5, lines[0])
          @corners[1] = plane_line_intersection(4, lines[1]); @corners[2] = plane_line_intersection(5, lines[1])
          @corners[4] = plane_line_intersection(4, lines[2]); @corners[7] = plane_line_intersection(5, lines[2])
          @corners[5] = plane_line_intersection(4, lines[3]); @corners[6] = plane_line_intersection(5, lines[3])
          value
        end

        def GetCorners(corners = :__return__)
          values = @corners.map(&:dup)
          return values if corners == :__return__
          corners = CNA::Runtime::GeometrySupport.require_array(corners, "corners")
          raise ArgumentError, "corners must contain at least eight entries" if corners.length < CornerCount
          values.each_with_index { |value, index| corners[index] = value }
          nil
        end

        def Contains(value)
          case value
          when Vector3
            @planes.any? { |plane| plane.DotCoordinate(value) > N.f32(1.0e-5) } ? ContainmentType::Disjoint : ContainmentType::Contains
          when BoundingBox
            intersects = false
            @planes.each do |plane|
              relation = plane.Intersects(value)
              return ContainmentType::Disjoint if relation == PlaneIntersectionType::Front
              intersects = true if relation == PlaneIntersectionType::Intersecting
            end
            intersects ? ContainmentType::Intersects : ContainmentType::Contains
          when BoundingSphere
            inside = 0
            @planes.each do |plane|
              distance = plane.DotCoordinate(value.Center)
              return ContainmentType::Disjoint if distance > value.Radius
              inside += 1 if distance < N.neg32(value.Radius)
            end
            inside == 6 ? ContainmentType::Contains : ContainmentType::Intersects
          when BoundingFrustum
            return ContainmentType::Disjoint unless Intersects(value)
            value.GetCorners.all? { |corner| Contains(corner) == ContainmentType::Contains } ? ContainmentType::Contains : ContainmentType::Intersects
          else
            raise TypeError, "BoundingFrustum.Contains received an unsupported value"
          end
        end

        def Intersects(value)
          case value
          when BoundingBox, BoundingSphere, BoundingFrustum
            GeometryIntersections.gjk_intersects(self, value)
          when Plane
            mask = 0
            @corners.each do |corner|
              mask |= value.DotCoordinate(corner) > 0 ? 1 : 2
              return PlaneIntersectionType::Intersecting if mask == 3
            end
            mask == 1 ? PlaneIntersectionType::Front : PlaneIntersectionType::Back
          when Ray
            return N.f32(0) if Contains(value.Position) == ContainmentType::Contains
            ray_intersection(value)
          else
            raise TypeError, "BoundingFrustum.Intersects received an unsupported value"
          end
        end

        def ==(other) = other.instance_of?(self.class) && @matrix == other.__send__(:raw_matrix)
        alias eql? ==
        def Equals(other) = self == other
        def GetHashCode = @matrix.GetHashCode
        def hash = GetHashCode
        def ToString = "{Near:#{self.Near} Far:#{self.Far} Left:#{self.Left} Right:#{self.Right} Top:#{self.Top} Bottom:#{self.Bottom}}"
        alias to_s ToString

        private

        def raw_matrix = @matrix

        def line(first, second)
          plane1 = @planes[first]; plane2 = @planes[second]
          direction = Vector3.Cross(plane1.Normal, plane2.Normal)
          position = Vector3.Cross(plane2.Normal * N.neg32(plane1.D) + plane1.Normal * plane2.D, direction) / direction.LengthSquared
          Ray.new(position, direction)
        end

        def plane_line_intersection(index, ray)
          plane = @planes[index]
          distance = N.div32(N.sub32(N.neg32(plane.D), Vector3.Dot(plane.Normal, ray.Position)), Vector3.Dot(plane.Normal, ray.Direction))
          ray.Position + ray.Direction * distance
        end

        def ray_intersection(ray)
          entry = N.f32(-3.402823466e38); exit_distance = N.f32(3.402823466e38)
          @planes.each do |plane|
            direction_dot = Vector3.Dot(ray.Direction, plane.Normal); position_dot = plane.DotCoordinate(ray.Position)
            if direction_dot.abs < N.f32(1.0e-5)
              return nil if position_dot > 0
              next
            end
            distance = N.div32(N.neg32(position_dot), direction_dot)
            if direction_dot < 0
              return nil if distance > exit_distance
              entry = [entry, distance].max
            else
              return nil if distance < entry
              exit_distance = [exit_distance, distance].min
            end
          end
          result = entry >= 0 ? entry : exit_distance
          result >= 0 ? result : nil
        end

        def gjk_center
          @corners.reduce(Vector3.Zero) { |sum, value| sum + value } / 8
        end

        def gjk_support(direction)
          @corners.max_by { |value| Vector3.Dot(value, direction) }.dup
        end
      end

      module GeometryIntersections
        module_function

        def gjk_intersects(first, second)
          direction = first.__send__(:gjk_center) - second.__send__(:gjk_center)
          direction = Vector3.UnitX if direction.LengthSquared.zero?
          simplex = [support(first, second, direction)]; direction = -simplex[0]
          64.times do
            return true if direction.LengthSquared.zero?
            point = support(first, second, direction)
            return false if Vector3.Dot(point, direction) < 0
            simplex << point
            contains, direction = update(simplex)
            return true if contains
          end
          false
        end

        def support(first, second, direction)
          first.__send__(:gjk_support, direction) - second.__send__(:gjk_support, -direction)
        end

        def triple_cross(a, b, c) = Vector3.Cross(Vector3.Cross(a, b), c)

        def update(simplex)
          a = simplex[-1]; ao = -a
          if simplex.length == 2
            b = simplex[-2]; ab = b - a
            if Vector3.Dot(ab, ao) > 0
              direction = triple_cross(ab, ao, ab)
              return [true, Vector3.Zero] if direction.LengthSquared.zero?
              return [false, direction]
            end
            simplex.replace([a]); return [false, ao]
          end
          if simplex.length == 3
            b = simplex[-2]; c = simplex[-3]; ab = b - a; ac = c - a; abc = Vector3.Cross(ab, ac)
            if Vector3.Dot(Vector3.Cross(abc, ac), ao) > 0
              if Vector3.Dot(ac, ao) > 0
                simplex.replace([c, a]); return [false, triple_cross(ac, ao, ac)]
              end
              return reduce_line(simplex, a, b, ab, ao)
            end
            return reduce_line(simplex, a, b, ab, ao) if Vector3.Dot(Vector3.Cross(ab, abc), ao) > 0
            return [false, abc] if Vector3.Dot(abc, ao) > 0
            simplex.replace([b, c, a]); return [false, -abc]
          end
          b = simplex[-2]; c = simplex[-3]; d = simplex[-4]
          ab = b - a; ac = c - a; ad = d - a
          abc = Vector3.Cross(ab, ac); acd = Vector3.Cross(ac, ad); adb = Vector3.Cross(ad, ab)
          if Vector3.Dot(abc, ao) > 0 then simplex.replace([c, b, a]); return [false, abc] end
          if Vector3.Dot(acd, ao) > 0 then simplex.replace([d, c, a]); return [false, acd] end
          if Vector3.Dot(adb, ao) > 0 then simplex.replace([b, d, a]); return [false, adb] end
          [true, Vector3.Zero]
        end

        def reduce_line(simplex, a, b, ab, ao)
          if Vector3.Dot(ab, ao) > 0
            simplex.replace([b, a]); [false, triple_cross(ab, ao, ab)]
          else
            simplex.replace([a]); [false, ao]
          end
        end
        private_class_method :support, :triple_cross, :update, :reduce_line
      end
      private_constant :GeometryIntersections
    end
  end
end
