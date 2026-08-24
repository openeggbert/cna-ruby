# frozen_string_literal: true

module CNA
  module Runtime
    module PackedVectorPacking
      N = Numeric
      private_constant :N
      module_function

      def round_to_even(value)
        value.round(half: :even)
      end

      def clamp_and_round(value, minimum, maximum)
        number = N.f32(value)
        return 0 if number.nan?
        return number.negative? ? minimum : maximum if number.infinite?
        return minimum if number < minimum
        return maximum if number > maximum

        round_to_even(number)
      end

      def pack_unsigned(bitmask, value)
        clamp_and_round(value, 0, bitmask)
      end

      def pack_signed(bitmask, value)
        maximum = bitmask >> 1
        minimum = -maximum - 1
        clamp_and_round(value, minimum, maximum) & bitmask
      end

      def pack_unorm(bitmask, value)
        scaled = N.mul32(value, bitmask)
        clamp_and_round(scaled, 0, bitmask)
      end

      def unpack_unorm(bitmask, value)
        N.div32(value & bitmask, bitmask)
      end

      def pack_snorm(bitmask, value)
        maximum = bitmask >> 1
        scaled = N.mul32(value, maximum)
        clamp_and_round(scaled, -maximum, maximum) & bitmask
      end

      def unpack_snorm(bitmask, value)
        sign = (bitmask + 1) >> 1
        bits = value & bitmask
        return N.f32(-1.0) if (bits & sign) != 0 && bits == sign

        signed = (bits & sign).zero? ? bits : bits - (bitmask + 1)
        N.div32(signed, bitmask >> 1)
      end

      # XNA 4.0's HalfUtils conversion is intentionally reproduced from its
      # observed binary32 behavior. Exponent 31 decodes as finite; overflow,
      # Infinity, and NaN pack to signed 0x7fff rather than IEEE infinity/NaN.
      def pack_half(value)
        bits = N.f32_bits(value)
        sign = (bits & 0x8000_0000) >> 16
        magnitude = bits & 0x7fff_ffff
        return sign | 0x7fff if magnitude > 0x47ff_efff

        if magnitude < 0x3880_0000
          fraction = (magnitude & 0x007f_ffff) | 0x0080_0000
          shift = 113 - (magnitude >> 23)
          shifted = shift <= 31 ? fraction >> shift : 0
          return sign | ((shifted + 4095 + ((shifted >> 13) & 1)) >> 13)
        end

        adjusted = magnitude - 0x3800_0000 + 4095 + ((magnitude >> 13) & 1)
        sign | (adjusted >> 13)
      end

      def unpack_half(value)
        bits = N.uint16(value)
        fraction = bits & 0x03ff
        if (bits & 0x7c00).zero?
          if fraction.zero?
            result = (bits & 0x8000) << 16
          else
            exponent = -14
            while (fraction & 0x0400).zero?
              exponent -= 1
              fraction <<= 1
            end
            fraction &= 0x03ff
            result = ((bits & 0x8000) << 16) | ((exponent + 127) << 23) | (fraction << 13)
          end
        else
          exponent = ((bits >> 10) & 0x1f) - 15 + 127
          result = ((bits & 0x8000) << 16) | (exponent << 23) | (fraction << 13)
        end
        N.f32_from_bits(result)
      end

      def constructor_components(arguments, vector_type, count, type_name)
        if arguments.length == 1 && arguments[0].instance_of?(vector_type)
          vector = arguments[0]
          return %i[X Y Z W].first(count).map { |component| vector.public_send(component) }
        end
        return arguments.map { |value| N.f32(value) } if arguments.length == count

        raise ArgumentError, "#{type_name}.new expects #{vector_type.name.split("::").last} or #{count} Single components"
      end

      def single_string(value)
        N.single_string(value).sub("e", "E")
      end

      def vector_string(values)
        names = %w[X Y Z W]
        "{" + values.each_with_index.map { |value, index| "#{names[index]}:#{single_string(value)}" }.join(" ") + "}"
      end
    end

    module PackedVectorValue
      N = Numeric
      private_constant :N

      module ClassMethods
        private

        def packed_vector_storage(validator, hex_width)
          @packed_vector_validator = validator
          @packed_vector_hex_width = hex_width
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

      def PackedValue = @packed_value

      def PackedValue=(value)
        validator = self.class.instance_variable_get(:@packed_vector_validator)
        @packed_value = N.public_send(validator, value, "PackedValue")
      end

      def ==(other) = other.instance_of?(self.class) && @packed_value == other.PackedValue
      def !=(other) = !(self == other)
      alias eql? ==
      def Equals(other) = self == other
      def hash = self.GetHashCode

      def GetHashCode
        width = self.class.instance_variable_get(:@packed_vector_hex_width)
        return @packed_value if width <= 4
        return N.wrap_int32(@packed_value) if width == 8

        N.wrap_int32((@packed_value & 0xffff_ffff) ^ (@packed_value >> 32))
      end

      def ToString
        width = self.class.instance_variable_get(:@packed_vector_hex_width)
        @packed_value.to_s(16).upcase.rjust(width, "0")
      end
      alias to_s ToString

      private

      def initialize_packed(value)
        self.PackedValue = value
      end
    end
  end
end
