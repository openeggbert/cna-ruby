# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      module Graphics
        module PackedVector
          module IPackedVector
            def ToVector4 = raise(NotImplementedError, "IPackedVector#ToVector4")
            def PackFromVector4(_vector) = raise(NotImplementedError, "IPackedVector#PackFromVector4")
            private :ToVector4, :PackFromVector4
          end

          module IPackedVectorOfT
            include IPackedVector

            def PackedValue = raise(NotImplementedError, "IPackedVectorOfT#PackedValue")
            def PackedValue=(_value)
              raise NotImplementedError, "IPackedVectorOfT#PackedValue="
            end
          end

          class Alpha8
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint8, 2

            def initialize(alpha)
              initialize_packed(CNA::Runtime::PackedVectorPacking.pack_unorm(255, alpha))
            end

            def ToAlpha = CNA::Runtime::PackedVectorPacking.unpack_unorm(255, @packed_value)

            private

            def PackFromVector4(vector)
              require_vector4(vector)
              self.PackedValue = CNA::Runtime::PackedVectorPacking.pack_unorm(255, vector.W)
              nil
            end

            def ToVector4 = Vector4.new(0.0, 0.0, 0.0, self.ToAlpha)
            def require_vector4(value)
              raise TypeError, "vector must be Vector4" unless value.instance_of?(Vector4)
            end
          end

          class Bgr565
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint16, 4

            def initialize(*arguments)
              x, y, z = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector3, 3, "Bgr565")
              initialize_packed(self.class.__send__(:pack, x, y, z))
            end

            def ToVector3
              Vector3.new(
                CNA::Runtime::PackedVectorPacking.unpack_unorm(31, @packed_value >> 11),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(63, @packed_value >> 5),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(31, @packed_value)
              )
            end

            class << self
              private

              def pack(x, y, z)
                (CNA::Runtime::PackedVectorPacking.pack_unorm(31, x) << 11) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(63, y) << 5) |
                  CNA::Runtime::PackedVectorPacking.pack_unorm(31, z)
              end
            end

            private

            def PackFromVector4(vector)
              require_vector4(vector)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z)
              nil
            end

            def ToVector4
              value = self.ToVector3
              Vector4.new(value, 1.0)
            end

            def require_vector4(value)
              raise TypeError, "vector must be Vector4" unless value.instance_of?(Vector4)
            end
          end

          class Bgra4444
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint16, 4

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Bgra4444")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(
                CNA::Runtime::PackedVectorPacking.unpack_unorm(15, @packed_value >> 8),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(15, @packed_value >> 4),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(15, @packed_value),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(15, @packed_value >> 12)
              )
            end

            class << self
              private

              def pack(x, y, z, w)
                (CNA::Runtime::PackedVectorPacking.pack_unorm(15, x) << 8) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(15, y) << 4) |
                  CNA::Runtime::PackedVectorPacking.pack_unorm(15, z) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(15, w) << 12)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class Bgra5551
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint16, 4

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Bgra5551")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(
                CNA::Runtime::PackedVectorPacking.unpack_unorm(31, @packed_value >> 10),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(31, @packed_value >> 5),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(31, @packed_value),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(1, @packed_value >> 15)
              )
            end

            class << self
              private

              def pack(x, y, z, w)
                (CNA::Runtime::PackedVectorPacking.pack_unorm(31, x) << 10) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(31, y) << 5) |
                  CNA::Runtime::PackedVectorPacking.pack_unorm(31, z) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(1, w) << 15)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class Byte4
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Byte4")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(@packed_value & 0xff, (@packed_value >> 8) & 0xff,
                          (@packed_value >> 16) & 0xff, @packed_value >> 24)
            end

            class << self
              private

              def pack(x, y, z, w)
                CNA::Runtime::PackedVectorPacking.pack_unsigned(255, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_unsigned(255, y) << 8) |
                  (CNA::Runtime::PackedVectorPacking.pack_unsigned(255, z) << 16) |
                  (CNA::Runtime::PackedVectorPacking.pack_unsigned(255, w) << 24)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class HalfSingle
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint16, 4

            def initialize(value)
              initialize_packed(CNA::Runtime::PackedVectorPacking.pack_half(value))
            end

            def ToSingle = CNA::Runtime::PackedVectorPacking.unpack_half(@packed_value)
            def ToString = CNA::Runtime::PackedVectorPacking.single_string(self.ToSingle)
            alias to_s ToString

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = CNA::Runtime::PackedVectorPacking.pack_half(vector.X)
              nil
            end

            def ToVector4 = Vector4.new(self.ToSingle, 0.0, 0.0, 1.0)
          end

          class HalfVector2
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              x, y = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector2, 2, "HalfVector2")
              initialize_packed(self.class.__send__(:pack, x, y))
            end

            def ToVector2
              Vector2.new(CNA::Runtime::PackedVectorPacking.unpack_half(@packed_value & 0xffff),
                          CNA::Runtime::PackedVectorPacking.unpack_half(@packed_value >> 16))
            end

            def ToString
              value = self.ToVector2
              CNA::Runtime::PackedVectorPacking.vector_string([value.X, value.Y])
            end
            alias to_s ToString

            class << self
              private

              def pack(x, y)
                CNA::Runtime::PackedVectorPacking.pack_half(x) |
                  (CNA::Runtime::PackedVectorPacking.pack_half(y) << 16)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y)
              nil
            end

            def ToVector4
              value = self.ToVector2
              Vector4.new(value, 0.0, 1.0)
            end
          end

          class HalfVector4
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint64, 16

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "HalfVector4")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(*4.times.map do |index|
                CNA::Runtime::PackedVectorPacking.unpack_half((@packed_value >> (index * 16)) & 0xffff)
              end)
            end

            def ToString
              value = self.ToVector4
              CNA::Runtime::PackedVectorPacking.vector_string([value.X, value.Y, value.Z, value.W])
            end
            alias to_s ToString

            class << self
              private

              def pack(*values)
                values.each_with_index.reduce(0) do |bits, (value, index)|
                  bits | (CNA::Runtime::PackedVectorPacking.pack_half(value) << (index * 16))
                end
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class NormalizedByte2
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint16, 4

            def initialize(*arguments)
              x, y = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector2, 2, "NormalizedByte2")
              initialize_packed(self.class.__send__(:pack, x, y))
            end

            def ToVector2
              Vector2.new(CNA::Runtime::PackedVectorPacking.unpack_snorm(255, @packed_value),
                          CNA::Runtime::PackedVectorPacking.unpack_snorm(255, @packed_value >> 8))
            end

            class << self
              private

              def pack(x, y)
                CNA::Runtime::PackedVectorPacking.pack_snorm(255, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_snorm(255, y) << 8)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y)
              nil
            end

            def ToVector4
              value = self.ToVector2
              Vector4.new(value, 0.0, 1.0)
            end
          end

          class NormalizedByte4
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "NormalizedByte4")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(*4.times.map do |index|
                CNA::Runtime::PackedVectorPacking.unpack_snorm(255, @packed_value >> (index * 8))
              end)
            end

            class << self
              private

              def pack(*values)
                values.each_with_index.reduce(0) do |bits, (value, index)|
                  bits | (CNA::Runtime::PackedVectorPacking.pack_snorm(255, value) << (index * 8))
                end
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class NormalizedShort2
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              x, y = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector2, 2, "NormalizedShort2")
              initialize_packed(self.class.__send__(:pack, x, y))
            end

            def ToVector2
              Vector2.new(CNA::Runtime::PackedVectorPacking.unpack_snorm(65_535, @packed_value),
                          CNA::Runtime::PackedVectorPacking.unpack_snorm(65_535, @packed_value >> 16))
            end

            class << self
              private

              def pack(x, y)
                CNA::Runtime::PackedVectorPacking.pack_snorm(65_535, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_snorm(65_535, y) << 16)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y)
              nil
            end

            def ToVector4
              value = self.ToVector2
              Vector4.new(value, 0.0, 1.0)
            end
          end

          class NormalizedShort4
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint64, 16

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "NormalizedShort4")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(*4.times.map do |index|
                CNA::Runtime::PackedVectorPacking.unpack_snorm(65_535, @packed_value >> (index * 16))
              end)
            end

            class << self
              private

              def pack(*values)
                values.each_with_index.reduce(0) do |bits, (value, index)|
                  bits | (CNA::Runtime::PackedVectorPacking.pack_snorm(65_535, value) << (index * 16))
                end
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class Rg32
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              x, y = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector2, 2, "Rg32")
              initialize_packed(self.class.__send__(:pack, x, y))
            end

            def ToVector2
              Vector2.new(CNA::Runtime::PackedVectorPacking.unpack_unorm(65_535, @packed_value),
                          CNA::Runtime::PackedVectorPacking.unpack_unorm(65_535, @packed_value >> 16))
            end

            class << self
              private

              def pack(x, y)
                CNA::Runtime::PackedVectorPacking.pack_unorm(65_535, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(65_535, y) << 16)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y)
              nil
            end

            def ToVector4
              value = self.ToVector2
              Vector4.new(value, 0.0, 1.0)
            end
          end

          class Rgba1010102
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Rgba1010102")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(
                CNA::Runtime::PackedVectorPacking.unpack_unorm(1023, @packed_value),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(1023, @packed_value >> 10),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(1023, @packed_value >> 20),
                CNA::Runtime::PackedVectorPacking.unpack_unorm(3, @packed_value >> 30)
              )
            end

            class << self
              private

              def pack(x, y, z, w)
                CNA::Runtime::PackedVectorPacking.pack_unorm(1023, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(1023, y) << 10) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(1023, z) << 20) |
                  (CNA::Runtime::PackedVectorPacking.pack_unorm(3, w) << 30)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class Rgba64
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint64, 16

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Rgba64")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(*4.times.map do |index|
                CNA::Runtime::PackedVectorPacking.unpack_unorm(65_535, @packed_value >> (index * 16))
              end)
            end

            class << self
              private

              def pack(*values)
                values.each_with_index.reduce(0) do |bits, (value, index)|
                  bits | (CNA::Runtime::PackedVectorPacking.pack_unorm(65_535, value) << (index * 16))
                end
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end

          class Short2
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint32, 8

            def initialize(*arguments)
              x, y = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector2, 2, "Short2")
              initialize_packed(self.class.__send__(:pack, x, y))
            end

            def ToVector2
              Vector2.new(CNA::Runtime::Numeric.sign_extend(@packed_value, 16),
                          CNA::Runtime::Numeric.sign_extend(@packed_value >> 16, 16))
            end

            class << self
              private

              def pack(x, y)
                CNA::Runtime::PackedVectorPacking.pack_signed(65_535, x) |
                  (CNA::Runtime::PackedVectorPacking.pack_signed(65_535, y) << 16)
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y)
              nil
            end

            def ToVector4
              value = self.ToVector2
              Vector4.new(value, 0.0, 1.0)
            end
          end

          class Short4
            include IPackedVectorOfT
            include CNA::Runtime::PackedVectorValue
            packed_vector_storage :uint64, 16

            def initialize(*arguments)
              values = CNA::Runtime::PackedVectorPacking.constructor_components(arguments, Vector4, 4, "Short4")
              initialize_packed(self.class.__send__(:pack, *values))
            end

            def ToVector4
              Vector4.new(*4.times.map do |index|
                CNA::Runtime::Numeric.sign_extend(@packed_value >> (index * 16), 16)
              end)
            end

            class << self
              private

              def pack(*values)
                values.each_with_index.reduce(0) do |bits, (value, index)|
                  bits | (CNA::Runtime::PackedVectorPacking.pack_signed(65_535, value) << (index * 16))
                end
              end
            end

            private

            def PackFromVector4(vector)
              raise TypeError, "vector must be Vector4" unless vector.instance_of?(Vector4)
              self.PackedValue = self.class.__send__(:pack, vector.X, vector.Y, vector.Z, vector.W)
              nil
            end
          end
        end
      end
    end
  end
end
