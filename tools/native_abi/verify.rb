# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require_relative "../../lib/cna"

headers = ENV["CNA_HEADERS"] || ARGV.shift
abort "usage: CNA_HEADERS=/path/to/modules/c-api/include CNA_NATIVE_LIBRARY=/absolute/libcna_c_api.so ruby tools/native_abi/verify.rb" unless headers
header = File.join(headers, "CNA", "C", "cna.h")
abort "canonical header not found: #{header}" unless File.file?(header)

probe_output = nil
Dir.mktmpdir("cna-ruby-abi-") do |directory|
  executable = File.join(directory, "probe")
  command = [ENV.fetch("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror", "-I#{headers}", File.join(__dir__, "probe.c"), "-o", executable]
  output, status = Open3.capture2e(*command)
  abort "native ABI probe compile failed:\n#{output}" unless status.success?
  probe_output, status = Open3.capture2e(executable)
  abort "native ABI probe execution failed:\n#{probe_output}" unless status.success?
end

records = Hash.new { |hash, key| hash[key] = [] }
probe_output.each_line do |line|
  kind, *values = line.strip.split("|")
  records[kind] << values
end

# An aggregate passed by value is expanded in the manifest into the eightbytes the platform ABI
# puts in registers, because Fiddle cannot pass an aggregate. The expansion is recorded on the
# signature, so the C spelling is reconstructed here and compared with what the header really
# declares -- a decomposition that stopped matching the header fails this probe rather than going
# unnoticed.
def ruby_signature(entry)
  aggregates = entry.respond_to?(:value_aggregates) ? (entry.value_aggregates || {}) : {}
  arguments = []
  index = 0
  while index < entry.c_arguments.length
    aggregate = aggregates[index]
    if aggregate
      arguments << aggregate.fetch(:c)
      index += aggregate.fetch(:members)
    else
      prefix = entry.const_arguments[index] ? "const " : ""
      stars = "*" * entry.pointer_depths[index]
      arguments << "#{prefix}#{entry.c_arguments[index]}#{stars}"
      index += 1
    end
  end
  "#{entry.c_return}|#{arguments.join(",")}"
end

mismatches = []
c_signatures = records["SIGNATURE"].to_h { |name, result, arguments| [name, "#{result}|#{arguments}"] }
CNA::Native::Manifest::FUNCTIONS.each do |entry|
  expected = c_signatures[entry.symbol]
  actual = ruby_signature(entry)
  mismatches << "signature #{entry.symbol}: C=#{expected.inspect} Ruby=#{actual.inspect}" unless expected == actual
end

layout_by_c_name = CNA::Native::Layouts::STRUCTURES.to_h do |layout|
  ["CNA_#{layout.name.split("::").last}", layout]
end
c_structs = records["STRUCT"].to_h { |name, size, alignment| [name, [Integer(size), Integer(alignment)]] }
c_fields = records["FIELD"].to_h { |struct_name, field_name, offset, size| ["#{struct_name}.#{field_name}", [Integer(offset), Integer(size)]] }
layout_by_c_name.each do |name, layout|
  c_size, c_alignment = c_structs.fetch(name, [nil, nil])
  mismatches << "layout #{name}: C size/alignment=#{[c_size, c_alignment]} Ruby=#{[layout.size, layout.alignment]}" unless [c_size, c_alignment] == [layout.size, layout.alignment]
  layout.fields.each do |field|
    c_measurement = c_fields["#{name}.#{field.name}"]
    mismatches << "field #{name}.#{field.name}: C=#{c_measurement.inspect} Ruby=#{[field.offset, field.size].inspect}" unless c_measurement == [field.offset, field.size]
  end
end

c_constants = records["CONSTANT"].to_h { |name, value| [name, Integer(value)] }
CNA::Native::Manifest::CONSTANTS.each do |name, value|
  mismatches << "constant #{name}: C=#{c_constants[name].inspect} Ruby=#{value}" unless c_constants[name] == value
end

missing_library = []
library = CNA::Native.library
CNA::Native::Manifest::FUNCTIONS.each do |entry|
  library.function(entry.symbol)
rescue KeyError
  missing_library << entry.symbol
end

signature_measurements = CNA::Native::Manifest::FUNCTIONS.sum { |entry| 1 + entry.c_arguments.length }
c_layout_measurements = records["STRUCT"].length * 2 + records["FIELD"].length * 2
ruby_layout_measurements = layout_by_c_name.values.sum { |layout| 2 + layout.fields.length * 2 }
report = {
  "schemaVersion" => 1,
  "abiVersion" => format("0x%08x", library.abi_version),
  "library" => library.path,
  "BOUND_FUNCTIONS" => CNA::Native::Manifest::FUNCTIONS.length,
  "SIGNATURE_MEASUREMENTS" => signature_measurements,
  "C_LAYOUT_MEASUREMENTS" => c_layout_measurements,
  "RUBY_LAYOUT_MEASUREMENTS" => ruby_layout_measurements,
  "CALLBACKS" => CNA::Native::Manifest::CALLBACKS.length,
  "CONSTANTS" => CNA::Native::Manifest::CONSTANTS.length,
  "MISSING_HEADER_SYMBOLS" => 0,
  "MISSING_LIBRARY_SYMBOLS" => missing_library.length,
  "ABI_MISMATCHES" => mismatches.length,
  "mismatches" => mismatches,
  "missingLibrarySymbols" => missing_library
}

destination = File.expand_path("../../docs/generated/native-abi-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
report.each { |key, value| puts "#{key}=#{value}" if key.match?(/\A[A-Z_]+\z/) }
abort mismatches.join("\n") unless mismatches.empty? && missing_library.empty?
