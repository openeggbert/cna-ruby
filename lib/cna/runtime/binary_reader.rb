# frozen_string_literal: true

module CNA
  module Runtime
    # `System.IO.BinaryReader`, the CLR base of `Content.ContentReader`.
    #
    # Measured from the pinned Microsoft .NET Framework 4.0 `mscorlib` rather than remembered:
    # `docs/generated/bcl-inventory.json` carries the family, its twenty-six public identities, the
    # exceptions each of them throws and the base and interface it declares. The XNA reference
    # contract names it exactly once — as `ContentReader`'s `baseType` — which is what admits it,
    # and `ContentReader`'s own `ReadSingle`, `ReadDouble`, `ReadVector2/3/4`, `ReadMatrix`,
    # `ReadQuaternion` and `ReadColor` are each a sequence of calls back into it.
    #
    # **Two of the twenty-six are deliberately not projected**, and both for the same measured
    # reason rather than for convenience:
    #
    # - `ReadDecimal` returns `System.Decimal`. The BCL inventory admits a family only when the XNA
    #   reference contract really names it, and no XNA signature names `System.Decimal` — the tool
    #   aborts on a family with no consumer. So the type this member returns cannot be admitted,
    #   and neither can the member. `BCL_PROJECTION_SCOPE`.
    # - `.ctor(Stream, Encoding)` names `System.Text.Encoding`, which no XNA signature names
    #   either. XNA's own `ContentReader..ctor` calls `BinaryReader::.ctor(Stream)` — one argument,
    #   measured in the pinned IL at `IL_0002` — so the overload this binding needs is the one it
    #   projects. `BCL_PROJECTION_SCOPE`.
    #
    # These two are the classification doing what it is for: **refusing a BCL family nothing
    # demands**. That is a different thing from deferring a family the project has selected, which
    # is what it wrongly recorded for the thirteen `Design` converters until Foundation 105 built
    # them — and which `test/test_design_converters.rb` now gates against.
    #
    # Everything else is here, reading little-endian off the projected `System.IO.Stream`, which is
    # the byte order the CLR's own `BinaryReader` uses on every platform it ships on.
    class BinaryReader
      # `new BinaryReader(Stream)` refuses a null stream with `ArgumentNullException` and an
      # unreadable one with `ArgumentException`, both measured in the inventory.
      def initialize(input)
        raise ::ArgumentError, "input" if input.nil?
        raise ::TypeError, "input must be a CNA::Runtime::Stream" unless input.is_a?(Stream)
        raise ::ArgumentError, "Stream was not readable" unless input.CanRead

        @stream = input
        @closed = false
      end

      # `get_BaseStream` answers the stream the reader was built over, unchanged.
      def BaseStream
        ensure_open!
        @stream
      end

      # `Close` and `Dispose` are one operation in the IL: `Dispose()` is `Dispose(true)` and
      # `Close()` is the same call. Closing twice is not an error; reading afterwards is.
      def Close
        return nil if @closed

        @closed = true
        @stream.Close
        nil
      end

      def Dispose = self.Close

      # -------------------------------------------------------------- the fixed-width primitives

      def ReadBoolean = !read_exactly(1).getbyte(0).zero?
      def ReadByte = read_exactly(1).getbyte(0)
      def ReadSByte = read_exactly(1).unpack1("c")
      def ReadInt16 = read_exactly(2).unpack1("s<")
      def ReadUInt16 = read_exactly(2).unpack1("v")
      def ReadInt32 = read_exactly(4).unpack1("l<")
      def ReadUInt32 = read_exactly(4).unpack1("V")
      def ReadInt64 = read_exactly(8).unpack1("q<")
      def ReadUInt64 = read_exactly(8).unpack1("Q<")

      # `System.Single` is a four-byte IEEE-754 value; the CLR reads it as a `UInt32` and
      # reinterprets, which is the same four bytes in the same order.
      def ReadSingle = CNA::Runtime::Numeric.f32(read_exactly(4).unpack1("e"))
      def ReadDouble = read_exactly(8).unpack1("E")

      # --------------------------------------------------------------------------- characters

      # `System.Char` projects to an Integer code unit, which is the decision `SpriteFont`
      # recorded. `Read()` answers **-1** at the end of the stream, which is why the CLR declares
      # it `Int32` and why a Ruby `nil` would be wrong here.
      #
      # DEVIATION, recorded rather than hidden: the CLR decodes through the reader's encoding and
      # answers the *first UTF-16 code unit* of the character, so a non-BMP code point answers a
      # lone high surrogate and the next call answers its low half. A lone surrogate is a value a
      # Ruby caller can do nothing correct with, so this projection refuses one instead.
      def Read(*arguments)
        return read_code_unit(consume: true) if arguments.empty?
        raise ::ArgumentError, "Read takes no arguments or three" unless arguments.length == 3

        buffer, index, count = arguments
        raise ::ArgumentError, "buffer" if buffer.nil?

        index = integer(index, "index")
        count = integer(count, "count")
        raise ::RangeError, "index" if index.negative?
        raise ::RangeError, "count" if count.negative?

        case buffer
        when ::String then read_into_bytes(buffer, index, count)
        when ::Array then read_into_chars(buffer, index, count)
        else raise ::TypeError, "buffer must be a byte String or an Array of code units"
        end
      end

      # `ReadChar` is `Read()` with the end of the stream made an error rather than a value.
      def ReadChar
        unit = read_code_unit(consume: true)
        raise ::EOFError, "end of stream" if unit.negative?

        unit
      end

      # `PeekChar` answers -1 at the end of the stream and leaves the position where it found it.
      def PeekChar = read_code_unit(consume: false)

      # `ReadChars(int)` is the plural of the `System.Char` decision: an Array of Integer code
      # units, short at the end of the stream rather than raising, which is the CLR's own contract.
      def ReadChars(count)
        ensure_open!
        count = integer(count, "count")
        raise ::RangeError, "count" if count.negative?

        units = []
        count.times do
          unit = read_code_unit(consume: true)
          break if unit.negative?

          units << unit
        end
        units
      end

      # `ReadString` is a 7-bit-encoded byte count followed by that many encoded bytes.
      def ReadString
        count = read_7_bit_encoded_int
        raise ::IOError, "invalid string length #{count}" if count.negative?
        return +"" if count.zero?

        read_exactly(count).force_encoding(::Encoding::UTF_8)
      end

      # `System.Byte[]` projects to a binary Ruby String, so this answers one. It reads *up to*
      # `count` bytes and answers what it got, which is how the CLR signals a short stream here.
      def ReadBytes(count)
        ensure_open!
        count = integer(count, "count")
        raise ::RangeError, "count" if count.negative?
        return +"".b if count.zero?

        buffer = +"\0".b * count
        taken = @stream.Read(buffer, 0, count)
        buffer.byteslice(0, taken)
      end

      protected

      # `Read7BitEncodedInt` is `family` in the CLR, so it is protected here. Seven bits per byte,
      # low group first; a fifth continuation byte is `FormatException`, which this binding raises
      # as the `IOError` its own stream failures use.
      def read_7_bit_encoded_int
        value = 0
        shift = 0
        loop do
          raise ::IOError, "7-bit encoded integer is too long" if shift == 35

          byte = read_exactly(1).getbyte(0)
          value |= (byte & 0x7F) << shift
          shift += 7
          break if (byte & 0x80).zero?
        end
        value
      end

      # Reads exactly `count` bytes or fails. Every fixed-width primitive goes through it, so a
      # truncated stream is one failure with one message rather than a silent short read.
      def read_exactly(count)
        ensure_open!
        return +"".b if count.zero?

        buffer = +"\0".b * count
        taken = @stream.Read(buffer, 0, count)
        raise ::EOFError, "end of stream" unless taken == count

        buffer
      end

      def stream = @stream

      private

      def read_code_unit(consume:)
        ensure_open!
        start = @stream.Position
        first = @stream.ReadByte
        return -1 if first.negative?

        length = utf8_length(first)
        bytes = +"".b
        bytes << first.chr
        (length - 1).times do
          continuation = @stream.ReadByte
          raise ::EOFError, "end of stream" if continuation.negative?

          bytes << continuation.chr
        end
        @stream.Position = start unless consume
        code_point = bytes.force_encoding(::Encoding::UTF_8).unpack1("U")
        raise ::RangeError, "a non-BMP character has no single UTF-16 code unit" if code_point > 0xFFFF

        code_point
      end

      def read_into_bytes(buffer, index, count)
        ensure_open!
        raise ::ArgumentError, "buffer is too small" if buffer.bytesize - index < count

        count.zero? ? 0 : @stream.Read(buffer, index, count)
      end

      def read_into_chars(buffer, index, count)
        ensure_open!
        raise ::ArgumentError, "buffer is too small" if buffer.length - index < count

        taken = 0
        count.times do
          unit = read_code_unit(consume: true)
          break if unit.negative?

          buffer[index + taken] = unit
          taken += 1
        end
        taken
      end

      def utf8_length(first)
        return 1 if first < 0x80
        return 2 if (first & 0xE0) == 0xC0
        return 3 if (first & 0xF0) == 0xE0
        return 4 if (first & 0xF8) == 0xF0

        raise ::IOError, "malformed UTF-8 lead byte"
      end

      def integer(value, label)
        raise ::TypeError, "#{label} must be an Integer" unless value.is_a?(::Integer)

        value
      end

      def ensure_open!
        raise CNA::DisposedObjectError, self.class.name if @closed
      end
    end
  end
end
