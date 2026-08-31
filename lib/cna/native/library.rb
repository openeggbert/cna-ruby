# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    class Library
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
