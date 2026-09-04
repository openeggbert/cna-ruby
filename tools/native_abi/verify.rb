# frozen_string_literal: true

require "json"
require_relative "gate"
require_relative "../../lib/cna"

# `CNA_HEADERS` names the canonical header root of the **loaded** library's ABI version.
# `CNA_ADMITTED_HEADERS` optionally names the header roots of every *other* admitted version,
# colon-separated. The gate then proves the admission policy rather than asserting it: each root
# must declare an admitted `CNA_ABI_VERSION`, and all roots must agree on every other measurement.
headers = ENV["CNA_HEADERS"] || ARGV.shift
abort "usage: CNA_HEADERS=/path/to/modules/c-api/include [CNA_ADMITTED_HEADERS=root:root] " \
      "CNA_NATIVE_LIBRARY=/absolute/libcna_c_api.so ruby tools/native_abi/verify.rb" unless headers

admitted = CNA::Native::Manifest::ADMITTED_ABI_VERSIONS
decode = ->(value) { CNA::Native::Manifest.decode_abi_version(value) }
roots = [headers, *(ENV["CNA_ADMITTED_HEADERS"] || "").split(":")].reject(&:empty?).uniq

measurements = roots.to_h do |root|
  [root, NativeAbiGate.measure(root)]
rescue ArgumentError, RuntimeError => error
  abort error.message
end

records = measurements.fetch(headers)
mismatches, missing_header_symbols = NativeAbiGate.compare(
  records,
  functions: CNA::Native::Manifest::FUNCTIONS,
  layouts: CNA::Native::Layouts::STRUCTURES,
  constants: CNA::Native::Manifest::CONSTANTS
)
admission = measurements.flat_map { |root, rows| NativeAbiGate.admission_mismatches(rows, root, admitted, decode) }
later_only = CNA::Native::Manifest::FUNCTIONS.select(&:since).map(&:symbol)
cross_version = NativeAbiGate.cross_version_mismatches(measurements, later_only: later_only)
mismatches.concat(admission).concat(cross_version)

missing_library = []
library = CNA::Native.library
CNA::Native::Manifest::FUNCTIONS.each do |entry|
  library.function(entry.symbol)
rescue KeyError
  missing_library << entry.symbol
end
unless admitted.include?(library.abi_version)
  mismatches << "admission #{library.path}: #{CNA::Native::Library.admission_failure(library.path, library.abi_version)}"
end

signature_measurements = CNA::Native::Manifest::FUNCTIONS.sum { |entry| 1 + entry.c_arguments.length }
c_layout_measurements = records["STRUCT"].length * 2 + records["FIELD"].length * 2
ruby_layout_measurements = CNA::Native::Layouts::STRUCTURES.sum { |layout| 2 + layout.fields.length * 2 }
report = {
  "schemaVersion" => 2,
  "abiVersion" => format("0x%08x", library.abi_version),
  "abiVersionName" => decode.call(library.abi_version),
  "admittedAbiVersions" => admitted.map { |value| decode.call(value) },
  "headerRoots" => roots,
  "library" => library.path,
  "BOUND_FUNCTIONS" => CNA::Native::Manifest::FUNCTIONS.length,
  "SIGNATURE_MEASUREMENTS" => signature_measurements,
  "C_LAYOUT_MEASUREMENTS" => c_layout_measurements,
  "RUBY_LAYOUT_MEASUREMENTS" => ruby_layout_measurements,
  "STRUCT_LAYOUTS" => CNA::Native::Layouts::STRUCTURES.length,
  "CALLBACKS" => CNA::Native::Manifest::CALLBACKS.length,
  "CONSTANTS" => CNA::Native::Manifest::CONSTANTS.length,
  "ADMITTED_ABI_VERSIONS" => admitted.length,
  "HEADER_ROOTS_VERIFIED" => roots.length,
  "CROSS_VERSION_MISMATCHES" => cross_version.length,
  "MISSING_HEADER_SYMBOLS" => missing_header_symbols.length,
  "MISSING_LIBRARY_SYMBOLS" => missing_library.length,
  "ABI_MISMATCHES" => mismatches.length,
  "mismatches" => mismatches,
  "missingHeaderSymbols" => missing_header_symbols,
  "missingLibrarySymbols" => missing_library
}

destination = File.expand_path("../../docs/generated/native-abi-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
report.each { |key, value| puts "#{key}=#{value}" if key.match?(/\A[A-Z_]+\z/) }
abort mismatches.join("\n") unless mismatches.empty? && missing_library.empty?
