# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

class ApiVerifierTest < Minitest::Test
  TYPE_NAME = "Microsoft.Xna.Framework.Fixture"

  def base_type
    {
      "name" => TYPE_NAME, "rubyName" => TYPE_NAME.gsub(".", "::"), "kind" => "class",
      "flags" => false, "baseType" => "System.Object", "interfaces" => [],
      "directInterfaces" => [], "genericParameters" => [], "members" => [
        {"kind" => "constructor", "name" => ".ctor", "static" => false, "access" => "public", "genericParameters" => [], "parameters" => []},
        {"kind" => "method", "name" => "Measure", "static" => false, "access" => "public", "returnType" => "System.Int32", "genericParameters" => [], "parameters" => [{"name" => "value", "type" => "System.Single", "ref" => false, "out" => false, "in" => false, "optional" => false}]},
        {"kind" => "method", "name" => "Measure", "static" => false, "access" => "public", "returnType" => "System.Int32", "genericParameters" => [], "parameters" => []},
        {"kind" => "property", "name" => "Value", "type" => "System.Int32", "static" => false, "get" => true, "set" => true, "getAccess" => "public", "setAccess" => "public", "parameters" => []},
        {"kind" => "method", "name" => "op_Equality", "static" => true, "access" => "public", "returnType" => "System.Boolean", "genericParameters" => [], "parameters" => []},
        {"kind" => "event", "name" => "Changed", "static" => false, "access" => "public", "type" => "System.EventHandler"}
      ]
    }
  end

  def contracts
    reference_type = base_type
    reference = {"types" => [reference_type]}
    target = {"types" => [Marshal.load(Marshal.dump(reference_type))]}
    [reference, target]
  end

  def verify(reference, target, runtime: false)
    CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: runtime).verify
  end

  def assert_detects(category)
    reference, target = contracts
    yield(reference, target)
    assert_operator verify(reference, target).counts.fetch(category), :>, 0
  end

  def test_missing_type = assert_detects("MISSING_TYPE") { |_reference, target| target["types"].clear }
  def test_missing_member = assert_detects("MISSING_MEMBER") { |_reference, target| target["types"][0]["members"].pop }
  def test_wrong_type_kind = assert_detects("TYPE_KIND_MISMATCH") { |_reference, target| target["types"][0]["kind"] = "struct" }
  def test_wrong_base = assert_detects("BASE_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["baseType"] = "System.Exception" }
  def test_wrong_property_mutability = assert_detects("PROPERTY_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"][3]["set"] = false }
  def test_wrong_overload = assert_detects("OVERLOAD_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"].delete_at(2) }
  def test_wrong_parameter = assert_detects("PARAMETER_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"][1]["parameters"][0]["type"] = "System.Double" }
  def test_wrong_return = assert_detects("RETURN_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"][1]["returnType"] = "System.Int64" }
  def test_unexpected_type = assert_detects("UNEXPECTED_TYPE") { |_reference, target| target["types"] << target["types"][0].merge("name" => "Microsoft.Xna.Framework.Extra") }
  def test_unexpected_member = assert_detects("UNEXPECTED_MEMBER") { |_reference, target| target["types"][0]["members"] << target["types"][0]["members"][1].merge("name" => "Extra") }
  def test_event = assert_detects("EVENT_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"][5]["type"] = "System.Action" }
  def test_operator = assert_detects("OPERATOR_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["members"][4]["returnType"] = "System.Int32" }
  def test_generic = assert_detects("GENERIC_MAPPING_MISMATCH") { |_reference, target| target["types"][0]["genericParameters"] = ["T"] }

  def test_enum_value_and_flags
    enum = {"name" => "Microsoft.Xna.Framework.SampleEnum", "rubyName" => "Microsoft::Xna::Framework::SampleEnum", "kind" => "enum", "flags" => true, "baseType" => "System.Enum", "interfaces" => [], "directInterfaces" => [], "genericParameters" => [], "members" => [{"kind" => "field", "name" => "One", "type" => "Microsoft.Xna.Framework.SampleEnum", "static" => true, "access" => "public", "value" => "1"}]}
    target = Marshal.load(Marshal.dump(enum))
    target["flags"] = false
    target["members"][0]["value"] = "2"
    result = verify({"types" => [enum]}, {"types" => [target]})
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>, 0
  end

  def test_raw_handle_and_public_ffi_leaks
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    target = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
    target["types"][0]["members"][0]["returnType"] = "CNA_Handle/Fiddle"
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["RAW_HANDLE_LEAK"], :>, 0
    assert_operator result.counts["PUBLIC_NATIVE_FFI_LEAK"], :>, 0
  end

  def test_internal_helper_leak
    Microsoft::Xna::Framework.const_set(:VerifierLeakFixture, Module.new)
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    target = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
    assert_operator verify(reference, target, runtime: true).counts["INTERNAL_TYPE_LEAK"], :>, 0
  ensure
    Microsoft::Xna::Framework.__send__(:remove_const, :VerifierLeakFixture) if Microsoft::Xna::Framework.const_defined?(:VerifierLeakFixture, false)
  end

  def test_unmeasured_category
    reference, target = contracts
    target["unmeasuredCategories"] = ["fixture"]
    assert_operator verify(reference, target).counts["UNMEASURED_STRUCTURAL_CATEGORY"], :>, 0
  end

  def test_every_required_category_is_measured
    reference, target = contracts
    assert_equal CNAApiCompat::CATEGORIES.sort, verify(reference, target).counts.keys.sort
  end
end
