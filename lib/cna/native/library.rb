# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    class Library
      RESULT_IO = 5
      RESULT_BUFFER_TOO_SMALL = 14
      RESULT_NOT_SUPPORTED = 6
      RESULT_THREAD = 8

      attr_reader :path, :abi_version

      def initialize
        Layouts.verify_host!
        @handle, @path = Resolver.open
        @functions = {}
        bind_manifest!
        @abi_version = function("cna_get_abi_version").call
        raise CNA::AbiMismatchError, self.class.admission_failure(path, abi_version) unless Manifest::ADMITTED_ABI_VERSIONS.include?(abi_version)
      rescue Fiddle::DLError => error
        raise CNA::NativeLoadError, "cannot load CNA library #{path || "(unresolved)"}: #{error.message}"
      end

      # The refusal names the whole admitted set, the version actually found and the library it
      # came from. It never names a single hard-coded version, so it cannot go stale the way
      # "expected 0.7.0" did once the admitted set moved.
      def self.admission_failure(path, actual)
        admitted = Manifest::ADMITTED_ABI_VERSIONS
                   .map { |value| format("%s (0x%08x)", Manifest.decode_abi_version(value), value) }
                   .join(", ")
        format("CNA C ABI %s (0x%08x) reported by %s is not admitted; this build of cna-ruby admits %s",
               Manifest.decode_abi_version(actual), actual, path, admitted)
      end

      def function(name) = @functions.fetch(name)

      def call(name, *arguments)
        result = function(name).call(*arguments)
        check(result, name)
      end

      def check(result, operation)
        return result if result.zero?

        detail, category = last_error
        exception = case result
                    when RESULT_NOT_SUPPORTED then CNA::CapabilityError
                    when RESULT_THREAD then CNA::OwnerThreadError
                    else CNA::NativeError
                    end
        if exception <= CNA::NativeError
          raise exception.new(operation, result, category: category, detail: detail)
        end
        raise exception, "#{operation} failed with CNA result #{result}: #{detail}"
      end

      def last_error
        info = Layouts::ErrorInfo.new
        result = function("cna_error_get_last_info").call(info.pointer)
        return [nil, nil] unless result.zero?

        size = pointer_for("Q", 0)
        result = function("cna_error_get_last_message_size").call(size)
        return [nil, info.read_u32(12)] unless result.zero?
        bytes = size[0, 8].unpack1("Q")
        return ["", info.read_u32(12)] if bytes.zero?

        buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
        required = pointer_for("Q", 0)
        copied = function("cna_error_copy_last_message").call(buffer, bytes, required)
        message = copied.zero? ? buffer[0, bytes].force_encoding(Encoding::UTF_8) : nil
        [message, info.read_u32(12)]
      rescue StandardError
        [nil, nil]
      end

      # The two-call "ask for the size, then copy" shape every counted-string route in this ABI
      # uses. `leading` is whatever the route takes before the destination -- a handle, or a handle
      # and an index -- and the answer is UTF-8, never a byte string.
      def counted_string(size_symbol, copy_symbol, *leading)
        size = pointer_for("Q", 0)
        call(size_symbol, *leading, size)
        bytes = size[0, 8].unpack1("Q")
        return "" if bytes.zero?

        buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
        call(copy_symbol, *leading, buffer, bytes, size)
        buffer[0, bytes].force_encoding(Encoding::UTF_8)
      end

      # `counted_string` for a route whose copy takes an **index** as well as the buffer, and whose
      # count route takes the same leading arguments. `StorageContainer.GetDirectoryNames` is the
      # shape: one count call for the pattern, then one copy call per index.
      def counted_string_at(copy_symbol, handle, view, index)
        size = pointer_for("Q", 0)
        # MEASURED: the sizing call answers `CNA_RESULT_BUFFER_TOO_SMALL` **and fills the count**,
        # which is the header's own contract ("Receives the required byte count", and
        # "insufficient capacity performs no partial write"). So 14 is the expected answer here and
        # only another code is a failure -- and the count is read either way.
        result = function(copy_symbol).call(handle, view.read_u64(0), view.read_u64(8), index, nil, 0, size)
        check(result, copy_symbol) unless result == RESULT_BUFFER_TOO_SMALL
        bytes = size[0, 8].unpack1("Q")
        return "" if bytes.zero?

        buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
        call(copy_symbol, handle, view.read_u64(0), view.read_u64(8), index, buffer, bytes, size)
        buffer[0, bytes].force_encoding(Encoding::UTF_8)
      end

      def pointer_for(format, value = 0)
        data = [value].pack(format)
        pointer = Fiddle::Pointer.malloc(data.bytesize, Fiddle::RUBY_FREE)
        pointer[0, data.bytesize] = data
        pointer
      end

      private

      def bind_manifest!
        Manifest::FUNCTIONS.each do |entry|
          address = @handle[entry.symbol]
          @functions[entry.symbol] = Fiddle::Function.new(address, entry.fiddle_arguments, entry.fiddle_return)
        rescue Fiddle::DLError => error
          raise CNA::MissingSymbolError, "CNA C ABI library #{path} is missing required symbol #{entry.symbol}: #{error.message}"
        end
      end
    end

    module_function

    def library
      @library ||= Library.new
    end

    def reset_for_test!
      @library = nil
    end
  end
end
