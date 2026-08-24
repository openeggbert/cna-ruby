# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"
require_relative "../tools/api_compat/name_mapper"

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

  def curve_contracts(type_name)
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == type_name }
    mapped = Marshal.load(Marshal.dump(reference_type))
    mapped["members"].reject! { |member| mapped["kind"] == "enum" && member["name"] == "value__" }
    mapped["rubyName"] = mapped.fetch("name").gsub(".", "::")
    [{"types" => [reference_type]}, {"types" => [mapped]}]
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

  def test_clr_name_mapper_preserves_ordinary_and_nested_names
    assert_equal "Microsoft::Xna::Framework::Vector4",
                 CNAApiCompat::NameMapper.runtime_constant_path("Microsoft.Xna.Framework.Vector4")
    assert_equal "Example::Outer::Inner",
                 CNAApiCompat::NameMapper.runtime_constant_path("Example.Outer+Inner")
  end

  def test_clr_name_mapper_rewrites_generic_definitions_deterministically
    assert_equal "Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVectorOfT",
                 CNAApiCompat::NameMapper.runtime_constant_path("Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector`1")
    assert_equal "Example::PairOfT1T2", CNAApiCompat::NameMapper.runtime_constant_path("Example.Pair`2")
    assert_raises(ArgumentError) do
      CNAApiCompat::NameMapper.runtime_constant_path("Example.Pair`2[System.Int32,System.String]")
    end
  end

  def test_packed_vector_collision_not_rewritten_is_detected
    reference, target = packed_vector_contracts
    generic = target["types"].find { |type| type["name"].end_with?("IPackedVector`1") }
    generic["rubyName"] = "Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVector"
    assert_operator verify(reference, target).counts["LANGUAGE_MAPPING_MISMATCH"], :>, 0
  end

  def test_packed_vector_wrong_generic_parameter_is_detected
    reference, target = packed_vector_contracts
    generic = target["types"].find { |type| type["name"].end_with?("IPackedVector`1") }
    generic["genericParameters"][0]["name"] = "TWrong"
    assert_operator verify(reference, target).counts["GENERIC_MAPPING_MISMATCH"], :>, 0
  end

  def test_packed_vector_wrong_generic_interface_inheritance_is_detected
    reference, target = packed_vector_contracts
    generic = target["types"].find { |type| type["name"].end_with?("IPackedVector`1") }
    generic["interfaces"] = []
    generic["directInterfaces"] = []
    assert_operator verify(reference, target).counts["INTERFACE_MAPPING_MISMATCH"], :>, 0
  end

  def test_packed_vector_wrong_concrete_tpacked_is_detected
    reference, target = packed_vector_contracts
    alpha = target["types"].find { |type| type["name"].end_with?("Alpha8") }
    alpha["directInterfaces"][0] = alpha["directInterfaces"][0].sub("System.Byte", "System.UInt16")
    assert_operator verify(reference, target).counts["INTERFACE_MAPPING_MISMATCH"], :>, 0
  end

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

  def test_curve_key_collection_wrong_item_mutability_is_detected
    reference, target = curve_contracts("Microsoft.Xna.Framework.CurveKeyCollection")
    target["types"][0]["members"].find { |member| member["name"] == "Item" }["set"] = false
    assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>, 0
  end

  def test_curve_key_collection_wrong_enumerator_return_is_detected
    reference, target = curve_contracts("Microsoft.Xna.Framework.CurveKeyCollection")
    target["types"][0]["members"].find { |member| member["name"] == "GetEnumerator" }["returnType"] = "System.Object"
    assert_operator verify(reference, target).counts["RETURN_MAPPING_MISMATCH"], :>, 0
  end

  def test_curve_key_collection_missing_generic_interface_is_detected
    reference, target = curve_contracts("Microsoft.Xna.Framework.CurveKeyCollection")
    target["types"][0]["directInterfaces"] = []
    assert_operator verify(reference, target).counts["INTERFACE_MAPPING_MISMATCH"], :>, 0
  end

  def test_curve_key_wrong_reference_kind_is_detected
    reference, target = curve_contracts("Microsoft.Xna.Framework.CurveKey")
    target["types"][0]["kind"] = "struct"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0
  end

  def test_curve_enum_wrong_raw_value_is_detected
    reference, target = curve_contracts("Microsoft.Xna.Framework.CurveLoopType")
    target["types"][0]["members"].find { |member| member["name"] == "Oscillate" }["value"] = "4"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0
  end

  def test_mouse_state_wrong_kind_constructor_order_and_missing_x_buttons_are_detected
    reference, target = mouse_contracts
    state = target["types"].find { |type| type["name"].end_with?(".MouseState") }
    state["kind"] = "class"
    constructor = state["members"].find { |member| member["kind"] == "constructor" }
    constructor["parameters"][4], constructor["parameters"][5] =
      constructor["parameters"][5], constructor["parameters"][4]
    state["members"].reject! { |member| %w[XButton1 XButton2].include?(member["name"]) }
    result = verify(reference, target)
    assert_operator result.counts["TYPE_KIND_MISMATCH"], :>, 0
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["MISSING_MEMBER"], :>=, 2
  end

  def test_mouse_state_mutable_x_extra_typed_equals_and_missing_operator_are_detected
    reference, target = mouse_contracts
    state = target["types"].find { |type| type["name"].end_with?(".MouseState") }
    state["members"].find { |member| member["name"] == "X" }["set"] = true
    object_equals = state["members"].find { |member| member["name"] == "Equals" }
    typed_equals = Marshal.load(Marshal.dump(object_equals))
    typed_equals["parameters"][0]["type"] = state["name"]
    state["members"] << typed_equals
    state["members"].reject! { |member| member["name"] == "op_Inequality" }
    result = verify(reference, target)
    assert_operator result.counts["PROPERTY_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
  end

  def test_mouse_button_state_wrong_enum_value_is_detected
    reference, target = mouse_contracts
    button = target["types"].find { |type| type["name"].end_with?(".ButtonState") }
    button["members"].find { |member| member["name"] == "Pressed" }["value"] = "2"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0
  end

  def test_mouse_constructibility_static_members_and_set_position_width_are_detected
    reference, target = mouse_contracts
    mouse = target["types"].find { |type| type["name"].end_with?(".Mouse") }
    mouse["members"] << {
      "kind" => "constructor", "name" => ".ctor", "static" => false, "access" => "public",
      "returnType" => nil, "genericParameters" => [], "parameters" => []
    }
    mouse["members"].find { |member| member["name"] == "GetState" }["static"] = false
    mouse["members"].find { |member| member["name"] == "SetPosition" }["parameters"][0]["type"] = "System.Int64"
    result = verify(reference, target)
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
  end

  def test_mouse_window_handle_mutability_type_and_intptr_mapping_are_detected
    reference, target = mouse_contracts
    property = target["types"].find { |type| type["name"].end_with?(".Mouse") }["members"].find do |member|
      member["name"] == "WindowHandle"
    end
    property["set"] = false
    property["type"] = "System.UInt64"
    target["languageTypeMappings"]["System.IntPtr"]["rubyType"] = "String"
    result = verify(reference, target)
    assert_operator result.counts["PROPERTY_MAPPING_MISMATCH"], :>, 0
    # Retain System.IntPtr on a second member so the formal mapping remains required.
    property["type"] = "System.IntPtr"
    assert_operator verify(reference, target).counts["LANGUAGE_MAPPING_MISMATCH"], :>, 0
  end

  def test_mouse_raw_pointer_mapping_and_extra_native_handle_are_detected
    reference, target = mouse_contracts
    mouse = target["types"].find { |type| type["name"].end_with?(".Mouse") }
    mouse["members"].find { |member| member["name"] == "WindowHandle" }["type"] = "Fiddle::Pointer"
    mouse["members"] << {
      "kind" => "method", "name" => "NativeHandle", "static" => true, "access" => "public",
      "returnType" => "CNA_Handle", "genericParameters" => [], "parameters" => []
    }
    target["languageTypeMappings"]["System.IntPtr"]["rubyType"] = "Fiddle::Pointer"
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["RAW_HANDLE_LEAK"], :>, 0
    assert_operator result.counts["PUBLIC_NATIVE_FFI_LEAK"], :>, 0
  end


  def packed_vector_contracts
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    names = [
      "Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector",
      "Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector`1",
      "Microsoft.Xna.Framework.Graphics.PackedVector.Alpha8"
    ]
    reference_types = reference.fetch("types").select { |type| names.include?(type.fetch("name")) }
    target_types = Marshal.load(Marshal.dump(reference_types))
    target_types.each do |type|
      type["rubyName"] = CNAApiCompat::NameMapper.runtime_constant_path(type.fetch("name"))
    end
    [{"types" => reference_types}, {"types" => target_types}]
  end

  def mouse_contracts
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    names = %w[
      Microsoft.Xna.Framework.Input.ButtonState
      Microsoft.Xna.Framework.Input.MouseState
      Microsoft.Xna.Framework.Input.Mouse
    ]
    reference_types = reference.fetch("types").select { |type| names.include?(type.fetch("name")) }
    target_types = Marshal.load(Marshal.dump(reference_types))
    target_types.each do |type|
      type["members"].reject! { |member| type["kind"] == "enum" && member["name"] == "value__" }
      type["rubyName"] = CNAApiCompat::NameMapper.runtime_constant_path(type.fetch("name"))
    end
    mapping = Marshal.load(Marshal.dump(CNAApiCompat::LANGUAGE_TYPE_MAPPINGS))
    [{"types" => reference_types}, {"types" => target_types, "languageTypeMappings" => mapping}]
  end
end
