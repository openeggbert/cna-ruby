# frozen_string_literal: true

require_relative "stream"

module CNA
  module Runtime
    # A file inside a container, opened through one of CNA's four open routes.
    #
    # It is a `CNA::Runtime::Stream` — the projection of `System.IO.Stream`, which is what
    # `CreateFile` and `OpenFile` are declared to return — with a native backing rather than the
    # in-memory one `TitleContainer` produces. Every member reaches its own `cna_storage_stream_*`
    # route, so a large file is read incrementally rather than materialised, which is the whole
    # difference from `Stream.over_bytes`.
    class StorageStream < CNA::Runtime::Stream
      def CanRead = native_boolean("cna_storage_stream_get_can_read")
      def CanSeek = native_boolean("cna_storage_stream_get_can_seek")
      def CanWrite = native_boolean("cna_storage_stream_get_can_write")
      def CanTimeout = false

      def Length = native_i64("cna_storage_stream_get_length")

      def Position = native_i64("cna_storage_stream_get_position")

      def Position=(value)
        self.Seek(value, CNA::Runtime::Stream::SeekOrigin::Begin)
        value
      end

      def Seek(offset, origin)
        ensure_open!
        output = CNA::Native.library.pointer_for("q", 0)
        CNA::Native.library.call("cna_storage_stream_seek", @handle,
                                 integer(offset, "offset"),
                                 CNA::Runtime::Stream::SeekOrigin.coerce(origin).to_i, output)
        output[0, 8].unpack1("q")
      end

      def SetLength(value)
        ensure_open!
        CNA::Native.library.call("cna_storage_stream_set_length", @handle, integer(value, "value"))
        nil
      end

      def Read(buffer, offset, count)
        ensure_open!
        validate_buffer!(buffer, offset, count)
        return 0 if count.zero?

        destination = Fiddle::Pointer.malloc(count, Fiddle::RUBY_FREE)
        written = CNA::Native.library.pointer_for("Q", 0)
        CNA::Native.library.call("cna_storage_stream_read", @handle, destination, count, written)
        read = written[0, 8].unpack1("Q")
        buffer[offset, read] = destination[0, read] if read.positive?
        read
      end

      def Write(buffer, offset, count)
        ensure_open!
        validate_buffer!(buffer, offset, count, mutating: false)
        return nil if count.zero?

        CNA::Native.library.call("cna_storage_stream_write", @handle,
                                 Fiddle::Pointer[buffer[offset, count]], count)
        nil
      end

      def Flush
        ensure_open!
        CNA::Native.library.call("cna_storage_stream_flush", @handle)
        nil
      end

      # `Close` is `Dispose(true)` in the CLR and this one really closes the native file.
      def Close
        return nil if @closed

        @closed = true
        begin
          CNA::Native.library.call("cna_storage_stream_close", @handle)
        rescue CNA::NativeError
          nil
        end
        nil
      end

      def to_s = "#<#{self.class.name} #{@name}>"

      private

      def initialize_native(handle, name)
        @handle = handle
        @name = name
        @closed = false
        @position = 0
        @bytes = +""
        @writable = true
        self
      end

      def ensure_open!
        raise ::RuntimeError, "the stream is closed" if @closed
      end

      def native_boolean(symbol)
        return false if @closed

        output = CNA::Native.library.pointer_for("C", 0)
        CNA::Native.library.call(symbol, @handle, output)
        !output[0, 1].unpack1("C").zero?
      end

      def native_i64(symbol)
        ensure_open!
        output = CNA::Native.library.pointer_for("q", 0)
        CNA::Native.library.call(symbol, @handle, output)
        output[0, 8].unpack1("q")
      end

      class << self
        private

        def from_native(handle, name) = allocate.__send__(:initialize_native, handle, name)
      end
    end
  end
end
