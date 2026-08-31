# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.IO.Stream`.
    #
    # This is a **BCL language projection**, not an XNA type. It lives in the CNA runtime rather
    # than a fabricated Ruby `::System` namespace, exactly as `EventArgs`, `Attribute`,
    # `ReadOnlyCollection`, `Collection` and `Dictionary` do. The whole derivation — the measured
    # CLR surface, the seventeen XNA members that reach it, the producer audit and the
    # `System.Byte[]` decision — is `docs/stream-projection-design.md`; what follows is only what
    # that derivation concluded.
    #
    # ## One public identity, several backings
    #
    # The CLR type is **abstract**, and XNA never names a concrete stream: `TitleContainer` returns
    # a `FileStream`, `StorageContainer` returns something else again, and a caller sees `Stream`
    # either way. So there is exactly one Ruby class here, and where the bytes live is a private
    # backing rather than a second projected identity. Inventing `CNA::Runtime::MemoryStream` would
    # add a BCL identity the selected XNA surface never names, which the register forbids.
    #
    # `new` is private for the reason Foundation 25 established for a CLR class with no public
    # constructor: a consumer cannot construct one, which is what "abstract" means from the outside.
    # Streams come from the members that produce them.
    #
    # ## The projected surface is the reached surface
    #
    # `CLR_SURFACE` is what a consumer of a stream this binding produces can actually call. Four
    # measured members are deliberately absent, and each for a stated reason:
    #
    # - `BeginRead`, `EndRead`, `BeginWrite`, `EndWrite` — the CLR asynchronous programming model,
    #   over `IAsyncResult` and a `WaitHandle`. No XNA member reaches them and this binding has no
    #   `IAsyncResult`; projecting them would mean inventing one.
    # - `Synchronized(Stream)` — returns a private `SyncStream` wrapper whose behaviour is not in the
    #   measured surface, so projecting it would be a guess about a type the inventory does not carry.
    # - `Null` — a static field whose behaviour belongs to the private nested `NullStream`. The
    #   inventory records only public nested types, so its behaviour is *not* measured here and a
    #   plausible reconstruction would be exactly the invention this project refuses.
    # - `CreateWaitHandle`, `ObjectInvariant`, `Dispose(Boolean)` — `family`, and this binding
    #   projects a protected member only when it supplies something a subclass needs.
    #
    # `CanTimeout`, `ReadTimeout` and `WriteTimeout` **are** projected, because they are the
    # cheapest kind of measured behaviour: the base answers `false` and both timeout properties
    # throw, which is a behaviour rather than a runtime.
    class Stream
      CLR_IDENTITY = "System.IO.Stream"

      # The measured CLR members this projection carries, in CLR spelling.
      CLR_SURFACE = %i[
        CanRead CanSeek CanTimeout CanWrite Length Position ReadTimeout WriteTimeout
        Read ReadByte Write WriteByte Seek SetLength Flush CopyTo Close Dispose
      ].freeze

      # `System.IO.SeekOrigin`, measured from the same mscorlib as the stream itself
      # (`docs/generated/bcl-inventory.json`): `Begin = 0`, `Current = 1`, `End = 2`. It reaches
      # this binding transitively, through `Stream::Seek` and through no XNA signature at all.
      # It is an ordinary CLR non-flags enum, so it takes the binding's unchanged enum policy --
      # the same `EnumValue`/`EnumType` pair every XNA enum here uses -- rather than a bag of Ruby
      # Integers. A BCL enum is not a lesser kind of enum.
      class SeekOrigin < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        CLR_IDENTITY = "System.IO.SeekOrigin"
        define_values({
          "Begin" => 0,
          "Current" => 1,
          "End" => 2
        })
      end

      # The default `CopyTo` buffer size is not measured — the CLR reads it from an internal
      # constant this inventory does not carry — so the two-argument overload is the one that
      # states a size, and the one-argument overload documents the number it chose here rather than
      # claiming it is Microsoft's.
      DEFAULT_COPY_BUFFER_SIZE = 81_920

      private_class_method :new

      class << self
        # The in-memory backing. `TitleContainer.OpenStream` and every other route CNA answers with
        # a whole file produce one of these: CNA's title routes hand back all the bytes at once, by
        # documented design, so there is nothing to read incrementally *from*.
        #
        # `writable` exists because the same backing serves both a read-only content stream and a
        # caller-supplied buffer a consumer writes into.
        def over_bytes(bytes, writable: false, name: nil)
          raise TypeError, "stream bytes must be a String" unless bytes.is_a?(::String)

          allocate.__send__(:initialize_over_bytes, bytes.b, writable, name)
        end
      end

      attr_reader :name

      def CanRead = !@closed
      def CanSeek = !@closed
      def CanWrite = @writable && !@closed
      def CanTimeout = false

      # Both timeout properties throw on the CLR base, and `System.InvalidOperationException` maps
      # to `RuntimeError` through the projection register.
      def ReadTimeout = raise(::RuntimeError, "Stream does not support timeouts")
      def WriteTimeout = raise(::RuntimeError, "Stream does not support timeouts")
      # A setter cannot use Ruby's endless method definition syntax, which is why these two are
      # spelled out where their getters are not.
      def ReadTimeout=(_value)
        raise ::RuntimeError, "Stream does not support timeouts"
      end

      def WriteTimeout=(_value)
        raise ::RuntimeError, "Stream does not support timeouts"
      end

      def Length
        ensure_open!
        @bytes.bytesize
      end

      def Position
        ensure_open!
        @position
      end

      def Position=(value)
        ensure_open!
        offset = integer(value, "value")
        raise ::RangeError, "Position must not be negative" if offset.negative?

        @position = offset
      end

      # `Seek` answers the new position, which is what makes it usable as a query.
      def Seek(offset, origin)
        ensure_open!
        offset = integer(offset, "offset")
        raise ::ArgumentError, "origin must be a SeekOrigin value" unless origin.instance_of?(SeekOrigin)

        base = case origin.to_i
               when 0 then 0
               when 1 then @position
               else @bytes.bytesize
               end
        target = base + offset
        raise ::IndexError, "cannot seek before the beginning of the stream" if target.negative?

        @position = target
      end

      def SetLength(_value)
        ensure_open!
        raise CNA::Runtime::NotSupportedError, "this stream cannot be resized"
      end

      # Reads into the caller's buffer and answers how many bytes were really read, which is zero
      # at the end of the stream and never negative. `System.Byte[]` projects to a binary Ruby
      # String, so the two properties a Ruby String has and a CLR array does not — it can be
      # resized and it can be frozen — are refused rather than silently allowed.
      def Read(buffer, offset, count)
        ensure_open!
        offset = integer(offset, "offset")
        count = integer(count, "count")
        validate_buffer!(buffer, offset, count)

        available = [@bytes.bytesize - @position, 0].max
        taken = [available, count].min
        return 0 if taken.zero?

        buffer[offset, taken] = @bytes.byteslice(@position, taken)
        @position += taken
        taken
      end

      # Answers the byte as an unsigned value, or **-1** at the end of the stream — the CLR returns
      # `Int32` for exactly that reason, and a Ruby `nil` would lose the distinction between "no
      # byte" and "a zero byte".
      def ReadByte
        ensure_open!
        return -1 if @position >= @bytes.bytesize

        byte = @bytes.getbyte(@position)
        @position += 1
        byte
      end

      def Write(buffer, offset, count)
        ensure_open!
        ensure_writable!
        offset = integer(offset, "offset")
        count = integer(count, "count")
        validate_buffer!(buffer, offset, count, mutating: false)
        grow_to(@position + count)
        @bytes[@position, count] = buffer.byteslice(offset, count)
        @position += count
        nil
      end

      def WriteByte(value)
        ensure_open!
        ensure_writable!
        byte = integer(value, "value")
        raise ::RangeError, "value must be a byte" unless byte.between?(0, 255)

        grow_to(@position + 1)
        @bytes.setbyte(@position, byte)
        @position += 1
        nil
      end

      def Flush
        ensure_open!
        nil
      end

      # Copies from the current position to the end, leaving this stream positioned at its end,
      # which is what a CLR `CopyTo` does.
      def CopyTo(destination, bufferSize = DEFAULT_COPY_BUFFER_SIZE)
        ensure_open!
        raise ::ArgumentError, "destination must be a Stream" unless destination.is_a?(Stream)
        size = integer(bufferSize, "bufferSize")
        raise ::RangeError, "bufferSize must be positive" unless size.positive?

        buffer = "\0".b * size
        loop do
          taken = self.Read(buffer, 0, size)
          break if taken.zero?

          destination.Write(buffer, 0, taken)
        end
        nil
      end

      # `Close` and `Dispose` are two measured public identities with one behaviour, and both are
      # idempotent: a second call is not an error.
      def Close
        @closed = true
        nil
      end

      def Dispose = self.Close

      def to_s = "#<#{self.class.name}#{@name ? " #{@name}" : ""} length=#{@bytes.bytesize} position=#{@position}>"
      alias inspect to_s

      private

      def initialize_over_bytes(bytes, writable, name)
        @bytes = bytes
        @position = 0
        @writable = writable
        @closed = false
        @name = name&.dup&.freeze
        self
      end

      def ensure_open!
        raise CNA::DisposedObjectError, "the stream is closed" if @closed
      end

      def ensure_writable!
        raise CNA::Runtime::NotSupportedError, "this stream is read-only" unless @writable
      end

      def integer(value, label)
        raise ::TypeError, "#{label} must be an Integer" unless value.is_a?(::Integer)

        value
      end

      # A CLR `byte[]` cannot be resized and is never frozen. A Ruby String is both, so a write into
      # the caller's buffer refuses each rather than resizing it or raising `FrozenError` from
      # inside the copy.
      def validate_buffer!(buffer, offset, count, mutating: true)
        raise ::TypeError, "buffer must be a String" unless buffer.is_a?(::String)
        raise ::RangeError, "offset must not be negative" if offset.negative?
        raise ::RangeError, "count must not be negative" if count.negative?
        raise ::ArgumentError, "offset and count exceed the buffer" if offset + count > buffer.bytesize
        return unless mutating
        raise ::ArgumentError, "buffer must not be frozen" if buffer.frozen?
      end

      def grow_to(size)
        @bytes << ("\0".b * (size - @bytes.bytesize)) if size > @bytes.bytesize
      end
    end
  end
end
