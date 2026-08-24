# frozen_string_literal: true

require "fiddle"
require "rbconfig"

module CNA
  module Native
    module Resolver
      ENVIRONMENT_VARIABLE = "CNA_NATIVE_LIBRARY"

      module_function

      def candidates
        explicit = ENV[ENVIRONMENT_VARIABLE]
        if explicit && !explicit.empty?
          raise CNA::NativeLoadError, "#{ENVIRONMENT_VARIABLE} must be an absolute file path" unless File.absolute_path(explicit) == explicit
          raise CNA::NativeLoadError, "#{ENVIRONMENT_VARIABLE} does not name a file: #{explicit}" unless File.file?(explicit)

          return [explicit]
        end

        packaged = File.expand_path("../#{RbConfig::CONFIG.fetch("host_os")}/#{library_filename}", __dir__)
        names = [packaged].select { |path| File.file?(path) }
        names + standard_names
      end

      def library_filename
        case RbConfig::CONFIG.fetch("host_os")
        when /darwin/ then "libcna_c_api.dylib"
        when /mswin|mingw/ then "cna_c_api.dll"
        else "libcna_c_api.so"
        end
      end

      def standard_names
        case RbConfig::CONFIG.fetch("host_os")
        when /darwin/ then ["libcna_c_api.dylib", "cna_c_api"]
        when /mswin|mingw/ then ["cna_c_api.dll", "cna_c_api"]
        else ["libcna_c_api.so", "cna_c_api"]
        end
      end

      def open
        errors = []
        candidates.each do |candidate|
          return [Fiddle::Handle.new(candidate), candidate]
        rescue Fiddle::DLError => error
          errors << "#{candidate}: #{error.message}"
        end
        raise CNA::NativeLoadError,
              "unable to load CNA C ABI library; set #{ENVIRONMENT_VARIABLE} to an absolute file (#{errors.join("; ")})"
      end
    end
  end
end
