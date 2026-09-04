# frozen_string_literal: true

require "fiddle"
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
    fillers = entry.respond_to?(:abi_fillers) ? (entry.abi_fillers || []) : []
    arguments = []
    index = 0
    while index < entry.c_arguments.length
      aggregate = aggregates[index]
      if aggregate
        arguments << aggregate.fetch(:c)
        index += aggregate.fetch(:members)
      elsif fillers.include?(index)
        # A register filler is not an argument of the C function at all — it exists only to push a
        # MEMORY-class aggregate onto the stack — so it contributes nothing to the reconstruction.
        index += 1
      else
        prefix = entry.const_arguments[index] ? "const " : ""
        stars = "*" * entry.pointer_depths[index]
        arguments << "#{prefix}#{entry.c_arguments[index]}#{stars}"
        index += 1
      end
    end
    "#{entry.c_return}|#{arguments.join(",")}"
  end

  # System V x86-64 argument classification, re-derived from the aggregate's **measured** size
  # rather than taken from the manifest's word for it.
  #
  #   * an aggregate of at most two eightbytes travels in registers, one Fiddle argument each and
  #     no fillers;
  #   * anything larger is MEMORY class: it is pushed on the stack, so the expansion must declare
  #     `ceil(size / 8)` eightbytes *and* enough integer-register fillers that they overflow there.
  #
  # Both numbers are computed here from `sizeof` and from the arguments that precede the aggregate,
  # so a manifest that declares the wrong shape fails the gate instead of producing a call that
  # reads the callee's stack at the wrong offset.
  INTEGER_ARGUMENT_REGISTERS = 6
  FIDDLE_DOUBLE = Fiddle::TYPE_DOUBLE

  def aggregate_mismatches(entry, c_structs)
    aggregates = entry.respond_to?(:value_aggregates) ? (entry.value_aggregates || {}) : {}
    fillers = entry.respond_to?(:abi_fillers) ? (entry.abi_fillers || []) : []
    mismatches = []
    aggregates.each do |index, aggregate|
      name = aggregate.fetch(:c)
      size, = c_structs[name]
      if size.nil?
        mismatches << "aggregate #{entry.symbol}: #{name} has no measured layout"
        next
      end
      eightbytes = (size + 7) / 8
      declared_fillers = aggregate.fetch(:fillers, 0)
      unless aggregate.fetch(:members) == eightbytes
        mismatches << "aggregate #{entry.symbol}: #{name} is #{size} bytes so it expands into "                       "#{eightbytes} eightbytes, manifest declares #{aggregate.fetch(:members)}"
      end
      # The eightbyte *class* decides which register file carries it, and getting that wrong is
      # silent: an SSE eightbyte declared as an integer lands in `rdi` where the callee reads
      # `xmm0`. So the declaration and the Fiddle types must agree — a `double` argument is the
      # only way Fiddle reaches an XMM register.
      declared_class = aggregate.fetch(:register_class, "INTEGER")
      members = (index...(index + aggregate.fetch(:members)))
      sse = members.all? { |position| entry.fiddle_arguments[position] == FIDDLE_DOUBLE }
      unless sse == (declared_class == "SSE")
        mismatches << "aggregate #{entry.symbol}: #{name} is declared #{declared_class} class but " \
                      "its eightbytes are #{sse ? "SSE" : "not SSE"} at the Fiddle boundary"
      end
      expected_fillers = if size <= 16
                           0
                         else
                           consumed = integer_registers_consumed(aggregates, fillers, c_structs,
                                                                 index - declared_fillers)
                           [INTEGER_ARGUMENT_REGISTERS - consumed, 0].max
                         end
      next if declared_fillers == expected_fillers

      mismatches << "aggregate #{entry.symbol}: #{name} is #{size} bytes and follows "                     "#{index - declared_fillers} argument(s), so it needs #{expected_fillers} "                     "register filler(s), manifest declares #{declared_fillers}"
    end
    mismatches
  end

  def inside_aggregate?(aggregates, position)
    aggregates.any? { |start, aggregate| position > start && position < start + aggregate.fetch(:members) }
  end

  # How many INTEGER argument registers the first `limit` manifest positions consume.
  #
  # A scalar consumes one and so does a register filler — that is what a filler is for. An
  # aggregate consumes registers **only** when it really travels in them: SSE eightbytes go to the
  # xmm file and MEMORY-class ones go on the stack, so neither takes an integer register, and a
  # second MEMORY aggregate after a first therefore needs no fillers of its own. `cna_model_draw`,
  # which passes three `CNA_Matrix` by value, is the route that made the difference measurable:
  # the earlier formula counted each aggregate's first position as one integer argument and asked
  # the second and third matrices for four and three fillers that the callee never reads.
  def integer_registers_consumed(aggregates, fillers, c_structs, limit)
    consumed = 0
    position = 0
    while position < limit
      aggregate = aggregates[position]
      if aggregate
        size, = c_structs[aggregate.fetch(:c)]
        register_class = aggregate.fetch(:register_class, "INTEGER")
        consumed += aggregate.fetch(:members) if register_class == "INTEGER" && !size.nil? && size <= 16
        position += aggregate.fetch(:members)
        next
      end

      consumed += 1
      position += 1
    end
    consumed
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
    # The header root's own encoded version, which is what a `since:` route is compared against.
    root_version = records["CONSTANT"].to_h { |name, value| [name, Integer(value)] }["CNA_ABI_VERSION"]
    functions.each do |entry|
      since = entry.respond_to?(:since) ? entry.since : nil
      # A route declared only from a later ABI version is absent from an older root **by
      # declaration**, and the probe does not emit it there either. Skipping it here is what keeps
      # the older root admitted; skipping it anywhere else would be a hole, so the skip is narrow:
      # only this entry, only this root, and only because the manifest says so.
      next if since && root_version && root_version < since

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
    functions.each do |entry|
      since = entry.respond_to?(:since) ? entry.since : nil
      next if since && root_version && root_version < since

      mismatches.concat(aggregate_mismatches(entry, c_structs))
    end
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

  # Every admitted version must agree on every measurement **except** the ABI version itself and
  # the routes the manifest declares `since:` a later version. That equality is the whole evidence
  # for admitting more than one version at a time; when it stops holding for anything else, the
  # extra version has to leave the set rather than be waved through.
  #
  # `later_only` is the set of symbols the manifest says arrived after the oldest admitted root.
  # It is a **declaration**, not a discovery: a symbol absent from one root and not declared here
  # is still a cross-version mismatch, which is what stops the exception from widening on its own.
  def cross_version_mismatches(measurements, later_only: [])
    later_only = later_only.to_a
    reference_root, reference = measurements.first
    measurements.drop(1).flat_map do |root, records|
      %w[SIGNATURE STRUCT FIELD CONSTANT].flat_map do |kind|
        left = normalize(reference[kind], kind)
        right = normalize(records[kind], kind)
        (left.keys | right.keys).filter_map do |key|
          next if left[key] == right[key]
          # A declared later-only route may be present in one root and absent from the other, and
          # nothing else: if both roots declare it they must still agree.
          next if kind == "SIGNATURE" && later_only.include?(key) && (left[key].nil? || right[key].nil?)

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
