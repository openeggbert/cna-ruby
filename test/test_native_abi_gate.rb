# frozen_string_literal: true

require "minitest/autorun"
require_relative "reviewed_measurements"
require_relative "../lib/cna"
require_relative "../tools/native_abi/gate"

# Mutation controls for the native ABI gate.
#
# The gate's whole claim is that a Ruby declaration which stopped matching the canonical C headers
# would be caught by a compiler rather than by a reviewer's memory. A gate that has only ever been
# seen to pass is not evidence for that claim, so every test below plants exactly one defect of a
# kind that has actually happened in bindings -- a parameter width, an enum constant, a struct field
# offset, a symbol no header declares, a callback argument, a by-value expansion, an inadmissible
# ABI version -- and requires the gate to name it. Each also asserts the *unmutated* surface is
# clean against the same measurement, so a test cannot pass merely because everything is broken.
#
# The canonical headers are never modified: the mutation is always on the Ruby side, which is the
# side that can actually drift.
class NativeAbiGateTest < Minitest::Test
  M = CNA::Native::Manifest
  L = CNA::Native::Layouts

  def self.headers = ENV["CNA_HEADERS"]

  # The probe is compiled once for the whole class: it is the expensive part, and every mutation
  # compares against the same measurement.
  def self.records
    @records ||= NativeAbiGate.measure(headers)
  end

  def setup
    skip "CNA_HEADERS not supplied" unless self.class.headers
    @records = self.class.records
  end

  def compare(functions: M::FUNCTIONS, layouts: L::STRUCTURES, constants: M::CONSTANTS)
    NativeAbiGate.compare(@records, functions: functions, layouts: layouts, constants: constants)
  end

  def assert_gate_reports(pattern, mismatches)
    assert mismatches.any? { |line| line.match?(pattern) },
           "gate did not report #{pattern.inspect}; it said #{mismatches.inspect}"
  end

  # The control for every mutation below: the real surface is clean against the same records.
  def test_the_unmutated_surface_is_clean
    mismatches, missing = compare
    assert_empty mismatches
    assert_empty missing
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), M::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:callbacks), M::CALLBACKS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), M::CONSTANTS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), L::STRUCTURES.length
  end

  # A width mutation is the classic silent one: `int64_t` and `int32_t` both marshal, and on a
  # little-endian host a truncated write often *looks* right for small values.
  def test_a_wrong_parameter_width_fails_the_gate
    victim = M::FUNCTIONS.find { |entry| entry.symbol == "cna_game_set_target_elapsed_time_ticks" }
    mutated = victim.with(c_arguments: [victim.c_arguments[0], "int32_t"])
    mismatches, = compare(functions: [mutated])
    assert_gate_reports(/signature cna_game_set_target_elapsed_time_ticks: .*int64_t.*int32_t/, mismatches)
  end

  # A dropped `const` is a real API-contract change and the gate reconstructs the C spelling
  # including it, so it must be caught too.
  def test_a_dropped_const_qualifier_fails_the_gate
    victim = M::FUNCTIONS.find { |entry| entry.symbol == "cna_game_create" }
    mutated = victim.with(const_arguments: [false, false])
    mismatches, = compare(functions: [mutated])
    assert_gate_reports(/signature cna_game_create:/, mismatches)
  end

  # Pointer depth is not implied by the Fiddle type: every pointer is `TYPE_VOIDP`, so only the
  # recorded depth distinguishes `CNA_Handle*` from `CNA_Handle**`.
  def test_a_wrong_pointer_depth_fails_the_gate
    victim = M::FUNCTIONS.find { |entry| entry.symbol == "cna_game_create" }
    mutated = victim.with(pointer_depths: [1, 2])
    mismatches, = compare(functions: [mutated])
    assert_gate_reports(/signature cna_game_create: .*CNA_Handle\*\*/, mismatches)
  end

  # Two button bits swapped is the shape of defect that makes a controller report the wrong button
  # forever without any call ever failing.
  def test_a_swapped_enum_constant_fails_the_gate
    mutated = M::CONSTANTS.merge(
      "CNA_GAMEPAD_BUTTON_A" => M::CONSTANTS.fetch("CNA_GAMEPAD_BUTTON_B"),
      "CNA_GAMEPAD_BUTTON_B" => M::CONSTANTS.fetch("CNA_GAMEPAD_BUTTON_A")
    )
    mismatches, = compare(constants: mutated)
    assert_gate_reports(/constant CNA_GAMEPAD_BUTTON_A:/, mismatches)
    assert_gate_reports(/constant CNA_GAMEPAD_BUTTON_B:/, mismatches)
  end

  # A constant this binding invented but no header declares.
  def test_a_constant_no_header_declares_fails_the_gate
    mismatches, = compare(constants: M::CONSTANTS.merge("CNA_GAMEPAD_BUTTON_IMAGINARY" => 1))
    assert_gate_reports(/constant CNA_GAMEPAD_BUTTON_IMAGINARY: C=nil/, mismatches)
  end

  # A wrong field offset reads the neighbouring field. `CNA_MouseState`'s scroll wheels are
  # adjacent `int32_t`s, so swapping their offsets is invisible to every type system involved.
  def test_a_wrong_struct_field_offset_fails_the_gate
    mismatches, = compare(layouts: [mutated_layout(L::MouseState, "scroll_wheel") { |field| field.with(offset: field.offset + 4) }])
    assert_gate_reports(/field CNA_MouseState\.scroll_wheel:/, mismatches)
  end

  def test_a_wrong_struct_size_fails_the_gate
    mismatches, = compare(layouts: [resized_layout(L::GamePadState, L::GamePadState.size + 8)])
    assert_gate_reports(/layout CNA_GamePadState:/, mismatches)
  end

  # A manifest entry naming a symbol the canonical headers do not declare is counted, not merely
  # reported: `MISSING_HEADER_SYMBOLS` is a measurement in the published report.
  def test_a_manifest_symbol_no_header_declares_is_measured_as_missing
    invented = M.signature("cna_game_teleport", M::T[:result], [M::T[:handle]], ownership: "invented")
    mismatches, missing = compare(functions: [invented])
    assert_equal ["cna_game_teleport"], missing
    assert_gate_reports(/signature cna_game_teleport: no canonical declaration measured/, mismatches)
  end

  # The by-value expansion is the one place where the Ruby argument list deliberately does *not*
  # match the C one, so the gate reconstructs the aggregate before comparing. Losing the expansion
  # record must fail rather than quietly compare two eightbytes against one struct.
  def test_a_lost_by_value_expansion_fails_the_gate
    victim = M::FUNCTIONS.find { |entry| entry.symbol == "cna_game_set_window_title" }
    assert_equal 1, victim.value_aggregates.length, "the fixture must really be a by-value route"
    mutated = victim.with(value_aggregates: {})
    mismatches, = compare(functions: [mutated])
    assert_gate_reports(/signature cna_game_set_window_title:/, mismatches)
  end

  # A by-value expansion that still claims to be one but decomposes into the wrong eightbytes.
  def test_a_wrong_by_value_member_count_fails_the_gate
    victim = M::FUNCTIONS.find { |entry| entry.symbol == "cna_game_window_end_screen_device_change" }
    aggregate = victim.value_aggregates.fetch(1)
    mutated = victim.with(value_aggregates: { 1 => aggregate.merge(members: 3) })
    mismatches, = compare(functions: [mutated])
    assert_gate_reports(/signature cna_game_window_end_screen_device_change:/, mismatches)
  end

  # The callback table is compiler-checked inside `probe.c` by `_Static_assert`, so the control for
  # a wrong callback argument is that the probe itself refuses to compile. This mutates the probe's
  # *copy*, never the tracked file.
  def test_a_wrong_callback_argument_fails_to_compile
    source = File.read(File.expand_path("../tools/native_abi/probe.c", __dir__))
    mutated = source.sub(
      "typedef CNA_Result (*expected_lifecycle)(CNA_Handle, const CNA_GameTime*, void*, CNA_CallbackError*);",
      "typedef CNA_Result (*expected_lifecycle)(CNA_Handle, const CNA_GameTime*, void*, CNA_ErrorInfo*);"
    )
    refute_equal source, mutated, "the probe's lifecycle typedef must be the one that was mutated"
    assert_probe_source_rejected(mutated, /lifecycle callback mismatch/)
  end

  # The same control for a plain function prototype: `CHECK_FN` is a `_Static_assert` too, so a
  # prototype that stopped matching the header is a compile error and not a runtime surprise.
  def test_a_wrong_prototype_fails_to_compile
    source = File.read(File.expand_path("../tools/native_abi/probe.c", __dir__))
    mutated = source.sub(
      "CHECK_FN(cna_game_run, CNA_Result, (CNA_Handle));",
      "CHECK_FN(cna_game_run, CNA_Result, (uint32_t));"
    )
    refute_equal source, mutated
    assert_probe_source_rejected(mutated, /prototype mismatch: cna_game_run/)
  end

  # The admission gate itself: a version outside the reviewed set is refused, and the refusal names
  # the set, the version found and the library.
  def test_an_inadmissible_abi_version_is_refused_by_name
    message = CNA::Native::Library.admission_failure("/tmp/libcna_c_api.so", 0x0000_0300)
    assert_match(/0\.3\.0/, message)
    assert_match(%r{/tmp/libcna_c_api\.so}, message)
    M::ADMITTED_ABI_VERSIONS.each { |value| assert_match(/#{Regexp.escape(M.decode_abi_version(value))}/, message) }
    refute_match(/expected 0\.7\.0/, message, "the refusal must not name a single frozen version")
  end

  def test_the_admission_check_reports_headers_outside_the_set
    decode = ->(value) { M.decode_abi_version(value) }
    records = { "CONSTANT" => [%w[CNA_ABI_VERSION 3]] }
    mismatches = NativeAbiGate.admission_mismatches(records, "/tmp/include", M::ADMITTED_ABI_VERSIONS, decode)
    assert_gate_reports(%r{admission /tmp/include: headers declare CNA C ABI 0\.0\.3}, mismatches)
  end

  # Every admitted version must agree on every measurement except the version constant. That
  # equality is the evidence for admitting more than one at a time, so it has to be falsifiable.
  def test_cross_version_comparison_ignores_the_version_and_catches_everything_else
    left = { "CONSTANT" => [%w[CNA_ABI_VERSION 1792], %w[CNA_TRUE 1]], "SIGNATURE" => [%w[cna_game_run CNA_Result CNA_Handle]] }
    right = { "CONSTANT" => [%w[CNA_ABI_VERSION 5376], %w[CNA_TRUE 1]], "SIGNATURE" => [%w[cna_game_run CNA_Result CNA_Handle]] }
    assert_empty NativeAbiGate.cross_version_mismatches({ "a" => left, "b" => right })

    diverged = { "CONSTANT" => [%w[CNA_ABI_VERSION 5376], %w[CNA_TRUE 2]], "SIGNATURE" => [%w[cna_game_run CNA_Result uint32_t]] }
    mismatches = NativeAbiGate.cross_version_mismatches({ "a" => left, "b" => diverged })
    assert_gate_reports(/cross-version CONSTANT CNA_TRUE:/, mismatches)
    assert_gate_reports(/cross-version SIGNATURE cna_game_run:/, mismatches)
  end

  private

  def assert_probe_source_rejected(source, pattern)
    require "open3"
    require "tmpdir"
    Dir.mktmpdir("cna-ruby-abi-mutation-") do |directory|
      path = File.join(directory, "probe.c")
      File.write(path, source)
      output, status = Open3.capture2e(ENV.fetch("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
                                       "-I#{self.class.headers}", path, "-o", File.join(directory, "probe"))
      refute status.success?, "the mutated probe compiled; the static assertions are not doing their job"
      assert_match pattern, output
    end
  end

  # Builds a throwaway layout class carrying one mutated field, so the real layout is untouched.
  def mutated_layout(original, field_name)
    fields = original.fields.map { |field| field.name == field_name ? yield(field) : field }
    clone_layout(original, size: original.size, alignment: original.alignment, fields: fields)
  end

  def resized_layout(original, size)
    clone_layout(original, size: size, alignment: original.alignment, fields: original.fields)
  end

  def clone_layout(original, size:, alignment:, fields:)
    name = original.name
    Class.new(L::Structure) do
      @size = size
      @alignment = alignment
      @fields = fields.freeze
      define_singleton_method(:name) { name }
    end
  end
end
