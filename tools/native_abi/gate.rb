# frozen_string_literal: true

require "open3"
require "tmpdir"

# The comparison half of the native ABI gate, separated from `verify.rb` so that it can be driven
# with a *mutated* manifest as well as the real one. A gate nobody has ever seen fail is not
# evidence, so `test/test_native_abi_gate.rb` plants one defect at a time -- a wrong parameter
# width, a swapped enum constant, a wrong struct field offset, a manifest symbol no header
# declares, a wrong callback argument, a broken by-value expansion -- and requires this module to
# report exactly that defect against unmodified canonical headers.
module NativeAbiGate
  module_function

  # Compiles `probe.c` against one header root and returns its records grouped by kind.
  def measure(headers, compiler: ENV.fetch("CC", "cc"))
    header = File.join(headers, "CNA", "C", "cna.h")
    raise ArgumentError, "canonical header not found: #{header}" unless File.file?(header)

    output = nil
    Dir.mktmpdir("cna-ruby-abi-") do |directory|
      executable = File.join(directory, "probe")
      command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I#{headers}",
                 File.join(__dir__, "probe.c"), "-o", executable]
      compile_output, status = Open3.capture2e(*command)
      raise "native ABI probe compile failed for #{headers}:\n#{compile_output}" unless status.success?

      output, status = Open3.capture2e(executable)
      raise "native ABI probe execution failed for #{headers}:\n#{output}" unless status.success?
    end

    records = Hash.new { |hash, key| hash[key] = [] }
    output.each_line do |line|
      kind, *values = line.strip.split("|")
      records[kind] << values
    end
    records
  end

  # An aggregate passed by value is expanded in the manifest into the eightbytes the platform ABI
  # puts in registers, because Fiddle cannot pass an aggregate. The expansion is recorded on the
  # signature, so the C spelling is reconstructed here and compared with what the header really
  # declares -- a decomposition that stopped matching the header fails this gate rather than going
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

  # Compares one header root's measurements with the supplied manifest surface.
  #
  # Returns `[mismatches, missing_header_symbols]`. `missing_header_symbols` is measured rather
  # than asserted: a manifest entry whose symbol the probe emitted no `SIGNATURE` record for is a
  # symbol the canonical headers do not declare under that name.
  def compare(records, functions:, layouts:, constants:)
    mismatches = []
    missing_header_symbols = []

    c_signatures = records["SIGNATURE"].to_h { |name, result, arguments| [name, "#{result}|#{arguments}"] }
    functions.each do |entry|
      expected = c_signatures[entry.symbol]
      if expected.nil?
        missing_header_symbols << entry.symbol
        mismatches << "signature #{entry.symbol}: no canonical declaration measured"
        next
      end
      actual = ruby_signature(entry)
      mismatches << "signature #{entry.symbol}: C=#{expected.inspect} Ruby=#{actual.inspect}" unless expected == actual
    end

    layout_by_c_name = layouts.to_h { |layout| ["CNA_#{layout.name.split("::").last}", layout] }
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
    constants.each do |name, value|
      mismatches << "constant #{name}: C=#{c_constants[name].inspect} Ruby=#{value}" unless c_constants[name] == value
    end

    [mismatches, missing_header_symbols]
  end

  # The admission check: every header root must itself report an admitted `CNA_ABI_VERSION`.
  def admission_mismatches(records, headers, admitted, decode)
    measured = records["CONSTANT"].to_h { |name, value| [name, Integer(value)] }["CNA_ABI_VERSION"]
    return ["admission #{headers}: headers declare no CNA_ABI_VERSION"] if measured.nil?
    return [] if admitted.include?(measured)

    ["admission #{headers}: headers declare CNA C ABI #{decode.call(measured)} " \
     "(0x#{format("%08x", measured)}), which is not in the admitted set " \
     "#{admitted.map { |value| decode.call(value) }.join(", ")}"]
  end

  # Every admitted version must agree on every measurement **except** the ABI version itself.
  # That equality is the whole evidence for admitting more than one version at a time; when it
  # stops holding, the extra version has to leave the set rather than be waved through.
  def cross_version_mismatches(measurements)
    reference_root, reference = measurements.first
    measurements.drop(1).flat_map do |root, records|
      %w[SIGNATURE STRUCT FIELD CONSTANT].flat_map do |kind|
        left = normalize(reference[kind], kind)
        right = normalize(records[kind], kind)
        (left.keys | right.keys).filter_map do |key|
          next if left[key] == right[key]

          "cross-version #{kind} #{key}: #{reference_root}=#{left[key].inspect} #{root}=#{right[key].inspect}"
        end
      end
    end
  end

  def normalize(rows, kind)
    (rows || []).to_h do |row|
      key = kind == "FIELD" ? row.take(2).join(".") : row.first
      [key, row.drop(kind == "FIELD" ? 2 : 1)]
    end.reject { |key, _| key == "CNA_ABI_VERSION" }
  end
end
