# frozen_string_literal: true

module CNA
  module Runtime
    module Numeric
      module_function

      def f32(value)
        raise TypeError, "Single must be an Integer or Float" if value == true || value == false
        raise TypeError, "Single must be an Integer or Float" unless value.is_a?(Integer) || value.is_a?(Float)

        converted = Float(value)
        return converted if converted.nan?

        [converted].pack("e").unpack1("e")
      rescue RangeError
        value.negative? ? -Float::INFINITY : Float::INFINITY
      end

      # MRI converts a binary32 NaN to a canonical positive Ruby Float while
      # unpacking. Construct the equivalent negative quiet NaN in binary64 so
      # its sign remains observable when the binding narrows it again.
      def negative_nan = [0xfff8_0000_0000_0000].pack("Q<").unpack1("E")

      def add32(left, right)
        a = f32(left); b = f32(right)
        return a if a.nan?
        return b if b.nan?
        return negative_nan if a.infinite? && b.infinite? && a.negative? != b.negative?

        f32(a + b)
      end

      def sub32(left, right)
        a = f32(left); b = f32(right)
        return a if a.nan?
        return neg32(b) if b.nan?
        return negative_nan if a.infinite? && b.infinite? && a.negative? == b.negative?

        f32(a - b)
      end

      def mul32(left, right)
        a = f32(left); b = f32(right)
        return a if a.nan?
        return b if b.nan?
        return negative_nan if (a.zero? && b.infinite?) || (b.zero? && a.infinite?)

        f32(a * b)
      end
      def neg32(value) = f32(-f32(value))

      def sqrt32(value)
        number = f32(value)
        return negative_nan if number.negative?

        f32(Math.sqrt(number))
      end

      def sin32(value) = f32(Math.sin(f32(value)))
      def cos32(value) = f32(Math.cos(f32(value)))

      def acos32(value)
        f32(Math.acos(f32(value)))
      rescue Math::DomainError
        negative_nan
      end

      def sum32(*values)
        raise ArgumentError, "sum32 requires at least one value" if values.empty?

        values.drop(1).reduce(f32(values.first)) { |sum, value| add32(sum, value) }
      end

      def div32(left, right)
        a = f32(left)
        b = f32(right)
        return a if a.nan?
        return b if b.nan?
        return negative_nan if (a.zero? && b.zero?) || (a.infinite? && b.infinite?)
        return (a.negative? ^ (1.0 / b).negative?) ? -Float::INFINITY : Float::INFINITY if b.zero?

        f32(a / b)
      end

      def int32(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside Int32" unless (-2_147_483_648..2_147_483_647).cover?(value)

        value
      end

      def uint8(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside Byte" unless (0..255).cover?(value)

        value
      end

      def int8(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside SByte" unless (-128..127).cover?(value)

        value
      end

      def uint16(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside UInt16" unless (0..65_535).cover?(value)

        value
      end

      def int16(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside Int16" unless (-32_768..32_767).cover?(value)

        value
      end

      def uint32(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside UInt32" unless (0..4_294_967_295).cover?(value)

        value
      end

      def uint64(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        raise RangeError, "#{name} is outside UInt64" unless (0..18_446_744_073_709_551_615).cover?(value)

        value
      end

      def pointer_width_bits = Fiddle::SIZEOF_VOIDP * 8

      def intptr(value, name = "value")
        raise TypeError, "#{name} must be an Integer" unless value.instance_of?(Integer)
        bits = pointer_width_bits
        minimum = -(1 << (bits - 1))
        maximum = (1 << (bits - 1)) - 1
        raise RangeError, "#{name} is outside IntPtr" unless (minimum..maximum).cover?(value)

        value
      end

      def intptr_to_uint64_bits(value, name = "value")
        number = intptr(value, name)
        number & ((1 << pointer_width_bits) - 1)
      end

      def intptr_from_uint64_bits(value)
        bits = pointer_width_bits
        narrowed = uint64(value, "native IntPtr") & ((1 << bits) - 1)
        sign_extend(narrowed, bits)
      end

      def sign_extend(value, bits)
        mask = (1 << bits) - 1
        narrowed = value & mask
        sign = 1 << (bits - 1)
        (narrowed & sign).zero? ? narrowed : narrowed - (1 << bits)
      end

      def f32_bits(value)
        number = f32(value)
        if number.nan?
          sign = [number].pack("E").unpack1("Q<") >> 63
          return (sign << 31) | 0x7fc0_0000
        end

        [number].pack("e").unpack1("L<")
      end

      def f32_from_bits(value)
        bits = uint32(value, "bits")
        [bits].pack("L<").unpack1("e")
      end

      def wrap_int32(value)
        bits = value & 0xffff_ffff
        bits < 0x8000_0000 ? bits : bits - 0x1_0000_0000
      end

      def single_hash(value)
        bits = [f32(value)].pack("e").unpack1("L<")
        bits &= 0x7f80_0000 if ((bits - 1) & 0x7fff_ffff) >= 0x7f80_0000
        wrap_int32(bits)
      end

      def hash32_sum(*values)
        wrap_int32(values.reduce(0) { |sum, value| sum + value })
      end

      def single_string(value)
        number = f32(value)
        return "NaN" if number.nan?
        return number.negative? ? "-Infinity" : "Infinity" if number.infinite?
        return "0" if number.zero?

        format("%.7g", number)
      end
    end
  end
end
