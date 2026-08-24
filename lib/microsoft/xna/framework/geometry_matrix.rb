# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      class Matrix
        include CNA::Runtime::ValueSemantics
        N = CNA::Runtime::Numeric
        NAMES = (1..4).flat_map { |row| (1..4).map { |column| :"M#{row}#{column}" } }.freeze
        private_constant :N, :NAMES

        NAMES.each do |name|
          define_method(name) { instance_variable_get(:"@#{name}") }
          define_method(:"#{name}=") { |value| instance_variable_set(:"@#{name}", N.f32(value)) }
        end

        def initialize(*values)
          values = [0.0] * 16 if values.empty?
          raise ArgumentError, "Matrix.new expects zero or sixteen Single values" unless values.length == 16

          NAMES.zip(values).each { |name, value| public_send(:"#{name}=", value) }
        end

        class << self
          def Identity = new(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

          def CreateScale(*arguments)
            x, y, z = if arguments.length == 1 && arguments[0].instance_of?(Vector3)
                        [arguments[0].X, arguments[0].Y, arguments[0].Z]
                      elsif arguments.length == 1
                        [arguments[0], arguments[0], arguments[0]]
                      elsif arguments.length == 3
                        arguments
                      else
                        raise ArgumentError, "CreateScale expects scale, Vector3, or (x, y, z)"
                      end
            result = self.Identity; result.M11 = x; result.M22 = y; result.M33 = z; result
          end

          def CreateTranslation(*arguments)
            x, y, z = if arguments.length == 1 && arguments[0].instance_of?(Vector3)
                        [arguments[0].X, arguments[0].Y, arguments[0].Z]
                      elsif arguments.length == 3
                        arguments
                      else
                        raise ArgumentError, "CreateTranslation expects Vector3 or (x, y, z)"
                      end
            result = self.Identity; result.M41 = x; result.M42 = y; result.M43 = z; result
          end

          def CreateRotationX(radians)
            cosine = N.cos32(radians); sine = N.sin32(radians)
            new(1, 0, 0, 0, 0, cosine, sine, 0, 0, N.neg32(sine), cosine, 0, 0, 0, 0, 1)
          end

          def CreateRotationY(radians)
            cosine = N.cos32(radians); sine = N.sin32(radians)
            new(cosine, 0, N.neg32(sine), 0, 0, 1, 0, 0, sine, 0, cosine, 0, 0, 0, 0, 1)
          end

          def CreateRotationZ(radians)
            cosine = N.cos32(radians); sine = N.sin32(radians)
            new(cosine, sine, 0, 0, N.neg32(sine), cosine, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
          end

          def CreateFromAxisAngle(axis, angle)
            CNA::Runtime::GeometrySupport.require_type(axis, Vector3, "axis")
            x = axis.X; y = axis.Y; z = axis.Z; sine = N.sin32(angle); cosine = N.cos32(angle)
            xx = N.mul32(x, x); yy = N.mul32(y, y); zz = N.mul32(z, z)
            xy = N.mul32(x, y); xz = N.mul32(x, z); yz = N.mul32(y, z)
            new(
              N.add32(xx, N.mul32(cosine, N.sub32(1, xx))), N.add32(N.sub32(xy, N.mul32(cosine, xy)), N.mul32(sine, z)), N.sub32(N.sub32(xz, N.mul32(cosine, xz)), N.mul32(sine, y)), 0,
              N.sub32(N.sub32(xy, N.mul32(cosine, xy)), N.mul32(sine, z)), N.add32(yy, N.mul32(cosine, N.sub32(1, yy))), N.add32(N.sub32(yz, N.mul32(cosine, yz)), N.mul32(sine, x)), 0,
              N.add32(N.sub32(xz, N.mul32(cosine, xz)), N.mul32(sine, y)), N.sub32(N.sub32(yz, N.mul32(cosine, yz)), N.mul32(sine, x)), N.add32(zz, N.mul32(cosine, N.sub32(1, zz))), 0,
              0, 0, 0, 1
            )
          end

          def CreateFromQuaternion(value)
            CNA::Runtime::GeometrySupport.require_type(value, Quaternion, "quaternion")
            xx = N.mul32(value.X, value.X); yy = N.mul32(value.Y, value.Y); zz = N.mul32(value.Z, value.Z)
            xy = N.mul32(value.X, value.Y); xz = N.mul32(value.X, value.Z); yz = N.mul32(value.Y, value.Z)
            wx = N.mul32(value.W, value.X); wy = N.mul32(value.W, value.Y); wz = N.mul32(value.W, value.Z)
            new(
              N.sub32(1, N.mul32(2, N.add32(yy, zz))), N.mul32(2, N.add32(xy, wz)), N.mul32(2, N.sub32(xz, wy)), 0,
              N.mul32(2, N.sub32(xy, wz)), N.sub32(1, N.mul32(2, N.add32(xx, zz))), N.mul32(2, N.add32(yz, wx)), 0,
              N.mul32(2, N.add32(xz, wy)), N.mul32(2, N.sub32(yz, wx)), N.sub32(1, N.mul32(2, N.add32(xx, yy))), 0,
              0, 0, 0, 1
            )
          end

          def CreateFromYawPitchRoll(yaw, pitch, roll) = CreateFromQuaternion(Quaternion.CreateFromYawPitchRoll(yaw, pitch, roll))

          def CreateLookAt(camera_position, camera_target, camera_up)
            require_vectors(camera_position, camera_target, camera_up)
            backward = Vector3.Normalize(camera_position - camera_target)
            right = Vector3.Normalize(Vector3.Cross(camera_up, backward))
            up = Vector3.Cross(backward, right)
            new(right.X, up.X, backward.X, 0, right.Y, up.Y, backward.Y, 0, right.Z, up.Z, backward.Z, 0,
                N.neg32(Vector3.Dot(right, camera_position)), N.neg32(Vector3.Dot(up, camera_position)),
                N.neg32(Vector3.Dot(backward, camera_position)), 1)
          end

          def CreateWorld(position, forward, up)
            require_vectors(position, forward, up)
            backward = Vector3.Normalize(-forward)
            right = Vector3.Normalize(Vector3.Cross(up, backward))
            corrected_up = Vector3.Cross(backward, right)
            new(right.X, right.Y, right.Z, 0, corrected_up.X, corrected_up.Y, corrected_up.Z, 0,
                backward.X, backward.Y, backward.Z, 0, position.X, position.Y, position.Z, 1)
          end

          def CreatePerspectiveFieldOfView(field_of_view, aspect_ratio, near_distance, far_distance)
            fov = N.f32(field_of_view); aspect = N.f32(aspect_ratio)
            raise RangeError, "fieldOfView must be greater than zero and less than Pi" if fov <= 0 || fov >= MathHelper::Pi
            near_value, far_value = validate_perspective(near_distance, far_distance)
            y_scale = N.div32(1, N.f32(Math.tan(N.mul32(fov, 0.5)))); x_scale = N.div32(y_scale, aspect)
            denominator = N.sub32(near_value, far_value); depth = N.div32(far_value, denominator)
            new(x_scale, 0, 0, 0, 0, y_scale, 0, 0, 0, 0, depth, -1, 0, 0,
                N.div32(N.mul32(near_value, far_value), denominator), 0)
          end

          def CreatePerspective(width, height, near_distance, far_distance)
            width = N.f32(width); height = N.f32(height); near_value, far_value = validate_perspective(near_distance, far_distance)
            denominator = N.sub32(near_value, far_value); depth = N.div32(far_value, denominator)
            new(N.div32(N.mul32(2, near_value), width), 0, 0, 0, 0, N.div32(N.mul32(2, near_value), height), 0, 0,
                0, 0, depth, -1, 0, 0, N.div32(N.mul32(near_value, far_value), denominator), 0)
          end

          def CreatePerspectiveOffCenter(left, right, bottom, top, near_distance, far_distance)
            left = N.f32(left); right = N.f32(right); bottom = N.f32(bottom); top = N.f32(top)
            near_value, far_value = validate_perspective(near_distance, far_distance)
            width = N.sub32(right, left); height = N.sub32(top, bottom); denominator = N.sub32(near_value, far_value)
            new(N.div32(N.mul32(2, near_value), width), 0, 0, 0, 0, N.div32(N.mul32(2, near_value), height), 0, 0,
                N.div32(N.add32(left, right), width), N.div32(N.add32(top, bottom), height), N.div32(far_value, denominator), -1,
                0, 0, N.div32(N.mul32(near_value, far_value), denominator), 0)
          end

          def CreateOrthographic(width, height, near_distance, far_distance)
            width = N.f32(width); height = N.f32(height); near_value = N.f32(near_distance); far_value = N.f32(far_distance)
            depth = N.sub32(near_value, far_value)
            new(N.div32(2, width), 0, 0, 0, 0, N.div32(2, height), 0, 0, 0, 0, N.div32(1, depth), 0,
                0, 0, N.div32(near_value, depth), 1)
          end

          def CreateOrthographicOffCenter(left, right, bottom, top, near_distance, far_distance)
            left = N.f32(left); right = N.f32(right); bottom = N.f32(bottom); top = N.f32(top)
            near_value = N.f32(near_distance); far_value = N.f32(far_distance)
            new(N.div32(2, N.sub32(right, left)), 0, 0, 0, 0, N.div32(2, N.sub32(top, bottom)), 0, 0,
                0, 0, N.div32(1, N.sub32(near_value, far_value)), 0,
                N.div32(N.add32(left, right), N.sub32(left, right)), N.div32(N.add32(top, bottom), N.sub32(bottom, top)),
                N.div32(near_value, N.sub32(near_value, far_value)), 1)
          end

          def CreateBillboard(object_position, camera_position, camera_up, camera_forward)
            require_vectors(object_position, camera_position, camera_up)
            CNA::Runtime::GeometrySupport.require_type(camera_forward, Vector3, "cameraForwardVector") unless camera_forward.nil?
            facing = object_position - camera_position
            if facing.LengthSquared < N.f32(0.0001)
              facing = camera_forward ? -camera_forward : Vector3.Forward
            else
              facing = facing * N.div32(1, facing.Length)
            end
            right = Vector3.Normalize(Vector3.Cross(camera_up, facing)); up = Vector3.Cross(facing, right)
            new(right.X, right.Y, right.Z, 0, up.X, up.Y, up.Z, 0, facing.X, facing.Y, facing.Z, 0,
                object_position.X, object_position.Y, object_position.Z, 1)
          end

          def CreateConstrainedBillboard(object_position, camera_position, rotate_axis, camera_forward, object_forward)
            require_vectors(object_position, camera_position, rotate_axis)
            [camera_forward, object_forward].compact.each { |value| CNA::Runtime::GeometrySupport.require_type(value, Vector3) }
            facing = object_position - camera_position
            facing = if facing.LengthSquared < N.f32(0.0001)
                       camera_forward ? -camera_forward : Vector3.Forward
                     else
                       facing * N.div32(1, facing.Length)
                     end
            up = rotate_axis.dup; alignment = Vector3.Dot(rotate_axis, facing)
            if alignment.abs > N.f32(0.99825466)
              forward = object_forward&.dup || Vector3.Forward
              if Vector3.Dot(rotate_axis, forward).abs > N.f32(0.99825466)
                forward = Vector3.Dot(rotate_axis, Vector3.Forward).abs > N.f32(0.99825466) ? Vector3.Right : Vector3.Forward
              end
              right = Vector3.Normalize(Vector3.Cross(rotate_axis, forward)); forward = Vector3.Normalize(Vector3.Cross(right, rotate_axis))
            else
              right = Vector3.Normalize(Vector3.Cross(rotate_axis, facing)); forward = Vector3.Normalize(Vector3.Cross(right, up))
            end
            new(right.X, right.Y, right.Z, 0, up.X, up.Y, up.Z, 0, forward.X, forward.Y, forward.Z, 0,
                object_position.X, object_position.Y, object_position.Z, 1)
          end

          def CreateShadow(light_direction, plane)
            CNA::Runtime::GeometrySupport.require_type(light_direction, Vector3, "lightDirection")
            CNA::Runtime::GeometrySupport.require_type(plane, Plane, "plane")
            normalized = Plane.Normalize(plane); dot = Vector3.Dot(normalized.Normal, light_direction)
            x = N.neg32(normalized.Normal.X); y = N.neg32(normalized.Normal.Y)
            z = N.neg32(normalized.Normal.Z); d = N.neg32(normalized.D)
            new(N.add32(N.mul32(x, light_direction.X), dot), N.mul32(x, light_direction.Y), N.mul32(x, light_direction.Z), 0,
                N.mul32(y, light_direction.X), N.add32(N.mul32(y, light_direction.Y), dot), N.mul32(y, light_direction.Z), 0,
                N.mul32(z, light_direction.X), N.mul32(z, light_direction.Y), N.add32(N.mul32(z, light_direction.Z), dot), 0,
                N.mul32(d, light_direction.X), N.mul32(d, light_direction.Y), N.mul32(d, light_direction.Z), dot)
          end

          def CreateReflection(value)
            CNA::Runtime::GeometrySupport.require_type(value, Plane)
            plane = Plane.Normalize(value); x = plane.Normal.X; y = plane.Normal.Y; z = plane.Normal.Z
            dx = N.mul32(-2, x); dy = N.mul32(-2, y); dz = N.mul32(-2, z)
            new(N.add32(N.mul32(dx, x), 1), N.mul32(dy, x), N.mul32(dz, x), 0,
                N.mul32(dx, y), N.add32(N.mul32(dy, y), 1), N.mul32(dz, y), 0,
                N.mul32(dx, z), N.mul32(dy, z), N.add32(N.mul32(dz, z), 1), 0,
                N.mul32(dx, plane.D), N.mul32(dy, plane.D), N.mul32(dz, plane.D), 1)
          end

          def Transpose(value)
            require_matrix(value)
            new(*(1..4).flat_map { |row| (1..4).map { |column| value.public_send("M#{column}#{row}") } })
          end

          def Invert(matrix)
            require_matrix(matrix)
            n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14, n15, n16 = matrix.__send__(:value_components)
            n17 = N.sub32(N.mul32(n11, n16), N.mul32(n12, n15)); n18 = N.sub32(N.mul32(n10, n16), N.mul32(n12, n14))
            n19 = N.sub32(N.mul32(n10, n15), N.mul32(n11, n14)); n20 = N.sub32(N.mul32(n9, n16), N.mul32(n12, n13))
            n21 = N.sub32(N.mul32(n9, n15), N.mul32(n11, n13)); n22 = N.sub32(N.mul32(n9, n14), N.mul32(n10, n13))
            n23 = N.add32(N.sub32(N.mul32(n6, n17), N.mul32(n7, n18)), N.mul32(n8, n19))
            n24 = N.neg32(N.add32(N.sub32(N.mul32(n5, n17), N.mul32(n7, n20)), N.mul32(n8, n21)))
            n25 = N.add32(N.sub32(N.mul32(n5, n18), N.mul32(n6, n20)), N.mul32(n8, n22))
            n26 = N.neg32(N.add32(N.sub32(N.mul32(n5, n19), N.mul32(n6, n21)), N.mul32(n7, n22)))
            n27 = N.div32(1, N.sum32(N.mul32(n1, n23), N.mul32(n2, n24), N.mul32(n3, n25), N.mul32(n4, n26)))
            result = Array.new(16, 0.0)
            result[0] = N.mul32(n23, n27); result[4] = N.mul32(n24, n27); result[8] = N.mul32(n25, n27); result[12] = N.mul32(n26, n27)
            result[1] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n2, n17), N.mul32(n3, n18)), N.mul32(n4, n19))), n27)
            result[5] = N.mul32(N.add32(N.sub32(N.mul32(n1, n17), N.mul32(n3, n20)), N.mul32(n4, n21)), n27)
            result[9] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n1, n18), N.mul32(n2, n20)), N.mul32(n4, n22))), n27)
            result[13] = N.mul32(N.add32(N.sub32(N.mul32(n1, n19), N.mul32(n2, n21)), N.mul32(n3, n22)), n27)
            n28 = N.sub32(N.mul32(n7, n16), N.mul32(n8, n15)); n29 = N.sub32(N.mul32(n6, n16), N.mul32(n8, n14))
            n30 = N.sub32(N.mul32(n6, n15), N.mul32(n7, n14)); n31 = N.sub32(N.mul32(n5, n16), N.mul32(n8, n13))
            n32 = N.sub32(N.mul32(n5, n15), N.mul32(n7, n13)); n33 = N.sub32(N.mul32(n5, n14), N.mul32(n6, n13))
            result[2] = N.mul32(N.add32(N.sub32(N.mul32(n2, n28), N.mul32(n3, n29)), N.mul32(n4, n30)), n27)
            result[6] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n1, n28), N.mul32(n3, n31)), N.mul32(n4, n32))), n27)
            result[10] = N.mul32(N.add32(N.sub32(N.mul32(n1, n29), N.mul32(n2, n31)), N.mul32(n4, n33)), n27)
            result[14] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n1, n30), N.mul32(n2, n32)), N.mul32(n3, n33))), n27)
            n34 = N.sub32(N.mul32(n7, n12), N.mul32(n8, n11)); n35 = N.sub32(N.mul32(n6, n12), N.mul32(n8, n10))
            n36 = N.sub32(N.mul32(n6, n11), N.mul32(n7, n10)); n37 = N.sub32(N.mul32(n5, n12), N.mul32(n8, n9))
            n38 = N.sub32(N.mul32(n5, n11), N.mul32(n7, n9)); n39 = N.sub32(N.mul32(n5, n10), N.mul32(n6, n9))
            result[3] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n2, n34), N.mul32(n3, n35)), N.mul32(n4, n36))), n27)
            result[7] = N.mul32(N.add32(N.sub32(N.mul32(n1, n34), N.mul32(n3, n37)), N.mul32(n4, n38)), n27)
            result[11] = N.mul32(N.neg32(N.add32(N.sub32(N.mul32(n1, n35), N.mul32(n2, n37)), N.mul32(n4, n39))), n27)
            result[15] = N.mul32(N.add32(N.sub32(N.mul32(n1, n36), N.mul32(n2, n38)), N.mul32(n3, n39)), n27)
            new(*result)
          end

          def Lerp(a, b, amount)
            require_matrix(a); require_matrix(b)
            new(*a.__send__(:value_components).zip(b.__send__(:value_components)).map { |x, y| N.add32(x, N.mul32(N.sub32(y, x), amount)) })
          end

          def Transform(value, rotation)
            require_matrix(value); CNA::Runtime::GeometrySupport.require_type(rotation, Quaternion)
            terms = Quaternion.__send__(:rotation_terms, rotation); result = []
            (1..4).each do |row|
              x = value.public_send("M#{row}1"); y = value.public_send("M#{row}2"); z = value.public_send("M#{row}3")
              result.concat([N.sum32(N.mul32(x, terms[0]), N.mul32(y, terms[1]), N.mul32(z, terms[2])),
                             N.sum32(N.mul32(x, terms[3]), N.mul32(y, terms[4]), N.mul32(z, terms[5])),
                             N.sum32(N.mul32(x, terms[6]), N.mul32(y, terms[7]), N.mul32(z, terms[8])), value.public_send("M#{row}4")])
            end
            new(*result)
          end

          def Add(a, b) = a + b
          def Subtract(a, b) = a - b
          def Negate(value) = -value
          def Multiply(a, b) = a * b
          def Divide(a, b) = a / b

          private

          def validate_perspective(near_distance, far_distance)
            near_value = N.f32(near_distance); far_value = N.f32(far_distance)
            raise RangeError, "nearPlaneDistance must be positive" if near_value <= 0
            raise RangeError, "farPlaneDistance must be positive" if far_value <= 0
            raise RangeError, "nearPlaneDistance must be less than farPlaneDistance" if near_value >= far_value
            [near_value, far_value]
          end

          def require_vectors(*values) = values.each { |value| CNA::Runtime::GeometrySupport.require_type(value, Vector3) }
          def require_matrix(value) = CNA::Runtime::GeometrySupport.require_type(value, Matrix)
        end

        def Right = Vector3.new(@M11, @M12, @M13)
        def Right=(value)
          set_basis(value, :M11, :M12, :M13)
        end
        def Left = Vector3.new(N.neg32(@M11), N.neg32(@M12), N.neg32(@M13))
        def Left=(value)
          set_basis(value, :M11, :M12, :M13, negate: true)
        end
        def Up = Vector3.new(@M21, @M22, @M23)
        def Up=(value)
          set_basis(value, :M21, :M22, :M23)
        end
        def Down = Vector3.new(N.neg32(@M21), N.neg32(@M22), N.neg32(@M23))
        def Down=(value)
          set_basis(value, :M21, :M22, :M23, negate: true)
        end
        def Backward = Vector3.new(@M31, @M32, @M33)
        def Backward=(value)
          set_basis(value, :M31, :M32, :M33)
        end
        def Forward = Vector3.new(N.neg32(@M31), N.neg32(@M32), N.neg32(@M33))
        def Forward=(value)
          set_basis(value, :M31, :M32, :M33, negate: true)
        end
        def Translation = Vector3.new(@M41, @M42, @M43)
        def Translation=(value)
          set_basis(value, :M41, :M42, :M43)
        end

        # The three CLR out parameters map to an ordered Ruby tuple following
        # the leading Boolean return: [success, scale, rotation, translation].
        def Decompose
          translation = self.Translation
          basis = [Vector3.new(@M11, @M12, @M13), Vector3.new(@M21, @M22, @M23), Vector3.new(@M31, @M32, @M33)]
          scales = basis.map(&:Length)
          largest, middle, smallest = (0..2).sort_by { |index| -scales[index] }
          canonical = [Vector3.UnitX, Vector3.UnitY, Vector3.UnitZ]
          basis[largest] = canonical[largest] if scales[largest] < N.f32(0.0001)
          basis[largest] = Vector3.Normalize(basis[largest])
          if scales[middle] < N.f32(0.0001)
            least = (0..2).min_by { |index| Vector3.Dot(basis[largest], canonical[index]).abs }
            basis[middle] = Vector3.Cross(basis[largest], canonical[least])
          end
          basis[middle] = Vector3.Normalize(basis[middle])
          basis[smallest] = Vector3.Cross(basis[largest], basis[middle]) if scales[smallest] < N.f32(0.0001)
          basis[smallest] = Vector3.Normalize(basis[smallest])
          rotation_matrix = self.class.new(basis[0].X, basis[0].Y, basis[0].Z, 0, basis[1].X, basis[1].Y, basis[1].Z, 0,
                                           basis[2].X, basis[2].Y, basis[2].Z, 0, 0, 0, 0, 1)
          determinant = rotation_matrix.Determinant
          if determinant < 0
            scales[largest] = N.neg32(scales[largest]); basis[largest] = -basis[largest]
            rotation_matrix = self.class.new(basis[0].X, basis[0].Y, basis[0].Z, 0, basis[1].X, basis[1].Y, basis[1].Z, 0,
                                             basis[2].X, basis[2].Y, basis[2].Z, 0, 0, 0, 0, 1)
            determinant = N.neg32(determinant)
          end
          error = N.mul32(N.sub32(determinant, 1), N.sub32(determinant, 1)); scale = Vector3.new(*scales)
          return [false, scale, Quaternion.Identity, translation] if error.nan? || error > N.f32(0.0001)

          [true, scale, Quaternion.CreateFromRotationMatrix(rotation_matrix), translation]
        end

        def Determinant
          n1 = N.sub32(N.mul32(@M33, @M44), N.mul32(@M34, @M43)); n2 = N.sub32(N.mul32(@M32, @M44), N.mul32(@M34, @M42))
          n3 = N.sub32(N.mul32(@M32, @M43), N.mul32(@M33, @M42)); n4 = N.sub32(N.mul32(@M31, @M44), N.mul32(@M34, @M41))
          n5 = N.sub32(N.mul32(@M31, @M43), N.mul32(@M33, @M41)); n6 = N.sub32(N.mul32(@M31, @M42), N.mul32(@M32, @M41))
          a = N.add32(N.sub32(N.mul32(@M22, n1), N.mul32(@M23, n2)), N.mul32(@M24, n3))
          b = N.add32(N.sub32(N.mul32(@M21, n1), N.mul32(@M23, n4)), N.mul32(@M24, n5))
          c = N.add32(N.sub32(N.mul32(@M21, n2), N.mul32(@M22, n4)), N.mul32(@M24, n6))
          d = N.add32(N.sub32(N.mul32(@M21, n3), N.mul32(@M22, n5)), N.mul32(@M23, n6))
          N.sub32(N.add32(N.sub32(N.mul32(@M11, a), N.mul32(@M12, b)), N.mul32(@M13, c)), N.mul32(@M14, d))
        end

        def -@ = self.class.new(*value_components.map { |value| N.neg32(value) })
        def +(other) = component_operator(other) { |a, b| N.add32(a, b) }
        def -(other) = component_operator(other) { |a, b| N.sub32(a, b) }

        def *(other)
          return self.class.new(*value_components.map { |value| N.mul32(value, other) }) if other.instance_of?(Integer) || other.instance_of?(Float)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          values = []
          (1..4).each do |row|
            (1..4).each do |column|
              values << N.sum32(*(1..4).map { |index| public_send("M#{row}#{index}").then { |v| N.mul32(v, other.public_send("M#{index}#{column}")) } })
            end
          end
          self.class.new(*values)
        end

        def /(other)
          return component_operator(other) { |a, b| N.div32(a, b) } if other.instance_of?(self.class)
          if other.instance_of?(Integer) || other.instance_of?(Float)
            factor = N.div32(1, other)
            return self.class.new(*value_components.map { |value| N.mul32(value, factor) })
          end
          raise TypeError, "Matrix division expects Matrix or Single"
        end

        def GetHashCode = N.hash32_sum(*value_components.map { |value| N.single_hash(value) })

        def ToString
          rows = (1..4).map do |row|
            "{" + (1..4).map { |column| "M#{row}#{column}:#{N.single_string(public_send("M#{row}#{column}"))}" }.join(" ") + "}"
          end
          "{ #{rows.join(" ")} }"
        end
        alias to_s ToString

        private

        def value_components = NAMES.map { |name| public_send(name) }

        def set_basis(value, *names, negate: false)
          CNA::Runtime::GeometrySupport.require_type(value, Vector3)
          components = [value.X, value.Y, value.Z]
          components.map! { |component| N.neg32(component) } if negate
          names.zip(components).each { |name, component| public_send(:"#{name}=", component) }
          value
        end

        def component_operator(other)
          CNA::Runtime::GeometrySupport.require_type(other, self.class)
          self.class.new(*value_components.zip(other.__send__(:value_components)).map { |a, b| yield(a, b) })
        end
      end
    end
  end
end
