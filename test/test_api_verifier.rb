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

  def test_flags_enum_without_declared_zero_is_structurally_valid
    name = "Microsoft.Xna.Framework.SampleMask"
    reference_type = {
      "name" => name, "kind" => "enum", "flags" => true, "sealed" => true,
      "underlyingType" => "System.Int32", "baseType" => "System.Enum",
      "interfaces" => [], "directInterfaces" => [], "genericParameters" => [],
      "members" => [
        {"kind" => "field", "name" => "value__", "type" => "System.Int32", "static" => false,
         "access" => "public", "constant" => false, "value" => nil},
        {"kind" => "field", "name" => "One", "type" => name, "static" => true,
         "access" => "public", "constant" => true, "value" => "1"},
        {"kind" => "field", "name" => "Two", "type" => name, "static" => true,
         "access" => "public", "constant" => true, "value" => "2"},
        {"kind" => "field", "name" => "Four", "type" => name, "static" => true,
         "access" => "public", "constant" => true, "value" => "4"}
      ]
    }
    target_type = Marshal.load(Marshal.dump(reference_type))
    target_type["members"].reject! { |member| member["name"] == "value__" }
    target_type["rubyName"] = "Microsoft::Xna::Framework::SampleMask"
    result = verify({"types" => [reference_type]}, {"types" => [target_type]})

    assert_equal 0, result.counts.values.sum
    assert_equal [name], result.complete_types
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

  def test_gamepad_enum_flags_values_and_underlying_types_are_detected
    reference, target = gamepad_contracts
    buttons = target["types"].find { |type| type["name"].end_with?(".Buttons") }
    buttons["flags"] = false
    buttons["underlyingType"] = "System.UInt32"
    buttons["members"].find { |member| member["name"] == "LeftThumbstickRight" }["value"] = "1073741823"
    dead_zone = target["types"].find { |type| type["name"].end_with?(".GamePadDeadZone") }
    dead_zone["members"].find { |member| member["name"] == "Circular" }["value"] = "3"
    gamepad_type = target["types"].find { |type| type["name"].end_with?(".GamePadType") }
    gamepad_type["members"].find { |member| member["name"] == "BigButtonPad" }["value"] = "9"
    result = verify(reference, target)
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>=, 2
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>=, 4
  end

  def test_gamepad_flags_runtime_combination_mask_is_measured
    reference, target = gamepad_contracts
    buttons = Microsoft::Xna::Framework::Input::Buttons
    original = buttons.instance_variable_get(:@enum_mask)
    buttons.instance_variable_set(:@enum_mask, original ^ Microsoft::Xna::Framework::Input::Buttons::A.to_i)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  ensure
    buttons&.instance_variable_set(:@enum_mask, original) if original
  end

  def test_gamepad_managed_shape_mutations_are_detected
    reference, target = gamepad_contracts
    gamepad_buttons = target["types"].find { |type| type["name"].end_with?(".GamePadButtons") }
    property = Marshal.load(Marshal.dump(gamepad_buttons["members"].find { |member| member["name"] == "A" }))
    property["name"] = "LeftTrigger"
    gamepad_buttons["members"] << property

    dpad = target["types"].find { |type| type["name"].end_with?(".GamePadDPad") }
    constructor = dpad["members"].find { |member| member["kind"] == "constructor" }
    constructor["parameters"][2], constructor["parameters"][3] =
      constructor["parameters"][3], constructor["parameters"][2]

    triggers = target["types"].find { |type| type["name"].end_with?(".GamePadTriggers") }
    triggers["members"].find { |member| member["name"] == "Left" }["set"] = true

    thumbsticks = target["types"].find { |type| type["name"].end_with?(".GamePadThumbSticks") }
    thumbsticks["members"].find { |member| member["name"] == "Left" }["type"] = "Microsoft.Xna.Framework.Vector3"

    result = verify(reference, target)
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["PROPERTY_MAPPING_MISMATCH"], :>=, 2
  end

  def test_gamepad_capabilities_fake_constructor_and_missing_property_are_detected
    reference, target = gamepad_contracts
    capabilities = target["types"].find { |type| type["name"].end_with?(".GamePadCapabilities") }
    capabilities["members"] << {
      "kind" => "constructor", "name" => ".ctor", "static" => false, "access" => "public",
      "returnType" => nil, "genericParameters" => [], "parameters" => []
    }
    capabilities["members"].reject! { |member| member["name"] == "HasVoiceSupport" }
    result = verify(reference, target)
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
  end

  def test_gamepad_state_constructor_array_and_typed_equals_mutations_are_detected
    reference, target = gamepad_contracts
    state = target["types"].find { |type| type["name"].end_with?(".GamePadState") }
    constructors = state["members"].select { |member| member["kind"] == "constructor" }
    array_constructor = constructors.find { |member| member["parameters"].length == 5 }
    array_constructor["parameters"][4]["type"] = "Microsoft.Xna.Framework.Input.Buttons"
    state["members"].delete(constructors.find { |member| member["parameters"].length == 4 })
    object_equals = state["members"].find { |member| member["name"] == "Equals" }
    typed_equals = Marshal.load(Marshal.dump(object_equals))
    typed_equals["parameters"][0]["type"] = state["name"]
    state["members"] << typed_equals
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
  end

  def test_gamepad_static_overload_return_and_native_leaks_are_detected
    reference, target = gamepad_contracts
    gamepad = target["types"].find { |type| type["name"].end_with?(".GamePad") }
    state_overloads = gamepad["members"].select { |member| member["name"] == "GetState" }
    gamepad["members"].delete(state_overloads.find { |member| member["parameters"].length == 2 })
    gamepad["members"].find { |member| member["name"] == "SetVibration" }["returnType"] = "System.Void"
    gamepad["members"] << {
      "kind" => "method", "name" => "NativeState", "static" => true, "access" => "public",
      "returnType" => "CNA_Handle/CNA::Native/Fiddle::Pointer", "genericParameters" => [], "parameters" => []
    }
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["RETURN_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["RAW_HANDLE_LEAK"], :>, 0
    assert_operator result.counts["PUBLIC_NATIVE_FFI_LEAK"], :>, 0
  end

  def test_vertex_element_wrong_kind_missing_constructor_and_constructor_order_are_detected
    reference, target = vertex_contracts
    vertex = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
    vertex["kind"] = "class"
    constructor = vertex["members"].find { |member| member["kind"] == "constructor" }
    constructor["parameters"][0], constructor["parameters"][3] =
      constructor["parameters"][3], constructor["parameters"][0]
    result = verify(reference, target)
    assert_operator result.counts["TYPE_KIND_MISMATCH"], :>, 0
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0

    vertex["members"].delete(constructor)
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>, 0
  end

  def test_vertex_element_wrong_constructor_enum_types_are_detected
    reference, target = vertex_contracts
    constructor = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
                               .fetch("members").find { |member| member["kind"] == "constructor" }
    constructor["parameters"][1]["type"] = "Microsoft.Xna.Framework.Graphics.VertexElementUsage"
    constructor["parameters"][2]["type"] = "Microsoft.Xna.Framework.Graphics.VertexElementFormat"
    assert_operator verify(reference, target).counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
  end

  def test_vertex_element_property_kind_mutability_and_types_are_detected
    reference, target = vertex_contracts
    vertex = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
    offset = vertex["members"].find { |member| member["name"] == "Offset" }
    offset["kind"] = "field"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0

    reference, target = vertex_contracts
    vertex = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
    offset = vertex["members"].find { |member| member["name"] == "Offset" }
    offset["set"] = false
    offset["type"] = "System.Int64"
    vertex["members"].find { |member| member["name"] == "UsageIndex" }["type"] = "System.UInt32"
    assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>=, 2
  end

  def test_vertex_element_missing_enum_setters_and_wrong_usage_index_type_are_detected
    reference, target = vertex_contracts
    vertex = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
    vertex["members"].find { |member| member["name"] == "VertexElementFormat" }["set"] = false
    vertex["members"].find { |member| member["name"] == "VertexElementUsage" }["set"] = false
    vertex["members"].find { |member| member["name"] == "UsageIndex" }["type"] = "System.Int64"
    assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>=, 3
  end

  def test_vertex_element_typed_equals_and_missing_operator_identities_are_detected
    reference, target = vertex_contracts
    vertex = target["types"].find { |type| type["name"].end_with?(".VertexElement") }
    object_equals = vertex["members"].find { |member| member["name"] == "Equals" }
    typed_equals = Marshal.load(Marshal.dump(object_equals))
    typed_equals["parameters"][0]["type"] = vertex["name"]
    vertex["members"] << typed_equals
    vertex["members"].reject! { |member| %w[op_Equality op_Inequality].include?(member["name"]) }
    result = verify(reference, target)
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
    assert_operator result.counts["MISSING_MEMBER"], :>=, 2
    assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>=, 2
  end

  def test_vertex_element_enum_raw_values_flags_and_underlying_types_are_detected
    reference, target = vertex_contracts
    format = target["types"].find { |type| type["name"].end_with?(".VertexElementFormat") }
    usage = target["types"].find { |type| type["name"].end_with?(".VertexElementUsage") }
    format["members"].find { |member| member["name"] == "HalfVector4" }["value"] = "12"
    usage["members"].find { |member| member["name"] == "TessellateFactor" }["value"] = "13"
    format["flags"] = true
    usage["underlyingType"] = "System.UInt32"
    result = verify(reference, target)
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>=, 3
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_vertex_element_unexpected_public_helper_is_detected_at_runtime
    reference, target = vertex_contracts
    vertex = Microsoft::Xna::Framework::Graphics::VertexElement
    vertex.class_eval { def SizeInBytes = 16 }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    vertex&.__send__(:remove_method, :SizeInBytes) if vertex&.public_method_defined?(:SizeInBytes)
  end

  def test_display_orientation_missing_type_and_wrong_namespace_are_detected
    reference, target = display_orientation_contracts
    target["types"].clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = display_orientation_contracts
    orientation = target.fetch("types").first
    orientation["name"] = "Microsoft.Xna.Framework.Graphics.DisplayOrientation"
    orientation["rubyName"] = "Microsoft::Xna::Framework::Graphics::DisplayOrientation"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_display_orientation_kind_base_underlying_flags_and_values_are_detected
    reference, target = display_orientation_contracts
    orientation = target.fetch("types").first
    orientation["kind"] = "class"
    orientation["baseType"] = "System.Object"
    orientation["underlyingType"] = "System.UInt32"
    orientation["flags"] = false
    orientation.fetch("members").each { |member| member["value"] = (Integer(member.fetch("value")) + 8).to_s }
    result = verify(reference, target)
    assert_operator result.counts["TYPE_KIND_MISMATCH"], :>, 0
    assert_operator result.counts["BASE_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>=, 5
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>=, 2
  end

  def test_display_orientation_missing_portrait_exposed_storage_and_extra_member_are_detected
    reference, target = display_orientation_contracts
    orientation = target.fetch("types").first
    orientation.fetch("members").reject! { |member| member["name"] == "Portrait" }
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    orientation.fetch("members") << Marshal.load(Marshal.dump(storage))
    orientation.fetch("members") << {
      "kind" => "field", "name" => "Landscape", "type" => orientation.fetch("name"),
      "static" => true, "constant" => true, "value" => "3"
    }
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>=, 2
  end

  def test_display_orientation_runtime_flags_mask_is_measured
    reference, target = display_orientation_contracts
    orientation = Microsoft::Xna::Framework::DisplayOrientation
    original = orientation.instance_variable_get(:@enum_mask)
    orientation.instance_variable_set(:@enum_mask, original ^ 0x4)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  ensure
    orientation&.instance_variable_set(:@enum_mask, original) if original
  end

  def test_graphics_device_status_missing_type_and_wrong_namespace_are_detected
    reference, target = graphics_device_status_contracts
    target.fetch("types").clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = graphics_device_status_contracts
    status = target.fetch("types").first
    status["name"] = "Microsoft.Xna.Framework.GraphicsDeviceStatus"
    status["rubyName"] = "Microsoft::Xna::Framework::GraphicsDeviceStatus"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_graphics_device_status_kind_underlying_type_and_flags_are_detected
    reference, target = graphics_device_status_contracts
    status = target.fetch("types").first
    status["kind"] = "class"
    status["underlyingType"] = "System.UInt32"
    status["flags"] = true
    result = verify(reference, target)
    assert_operator result.counts["TYPE_KIND_MISMATCH"], :>, 0
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>, 0
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_graphics_device_status_each_wrong_raw_value_is_detected
    reference, target = graphics_device_status_contracts
    wrong_values = {"Normal" => "1", "Lost" => "2", "NotReset" => "0"}
    target.fetch("types").first.fetch("members").each do |member|
      member["value"] = wrong_values.fetch(member.fetch("name"))
    end
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>=, 3
  end

  def test_graphics_device_status_missing_not_reset_storage_and_extra_member_are_detected
    reference, target = graphics_device_status_contracts
    status = target.fetch("types").first
    status.fetch("members").reject! { |member| member["name"] == "NotReset" }
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    status.fetch("members") << Marshal.load(Marshal.dump(storage))
    status.fetch("members") << {
      "kind" => "field", "name" => "DeviceLost", "type" => status.fetch("name"),
      "static" => true, "constant" => true, "value" => "1"
    }
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>=, 2
  end

  def test_graphics_device_status_selected_surface_rejects_accidental_device_property
    reference, target = graphics_device_status_selected_surface_contracts
    full_reference = reference_contract
    property = full_reference.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    end.fetch("members").find { |member| member["kind"] == "property" && member["name"] == "GraphicsDeviceStatus" }
    target.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    end.fetch("members") << Marshal.load(Marshal.dump(property))

    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0
    selected_device = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__))).fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    end
    refute selected_device.fetch("members").any? { |member| member["name"] == "GraphicsDeviceStatus" }
  end

  def test_graphics_profile_missing_type_and_wrong_namespace_are_detected
    reference, target = graphics_profile_contracts
    target.fetch("types").clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = graphics_profile_contracts
    profile = target.fetch("types").first
    profile["name"] = "Microsoft.Xna.Framework.GraphicsProfile"
    profile["rubyName"] = "Microsoft::Xna::Framework::GraphicsProfile"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_graphics_profile_wrong_kind_underlying_type_and_flags_are_detected
    reference, target = graphics_profile_contracts
    target.fetch("types").first["kind"] = "class"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0

    reference, target = graphics_profile_contracts
    target.fetch("types").first["underlyingType"] = "System.UInt32"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0

    reference, target = graphics_profile_contracts
    target.fetch("types").first["flags"] = true
    assert_operator verify(reference, target).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_graphics_profile_reach_and_hidef_raw_value_mutations_are_detected
    reference, target = graphics_profile_contracts
    profile = target.fetch("types").first
    profile.fetch("members").find { |member| member["name"] == "Reach" }["value"] = "1"
    profile.fetch("members").find { |member| member["name"] == "HiDef" }["value"] = "0"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>=, 2
  end

  def test_graphics_profile_missing_hidef_exposed_storage_and_extra_enum_value_are_detected
    reference, target = graphics_profile_contracts
    profile = target.fetch("types").first
    profile.fetch("members").reject! { |member| member["name"] == "HiDef" }
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    profile.fetch("members") << Marshal.load(Marshal.dump(storage))
    profile.fetch("members") << {
      "kind" => "field", "name" => "Default", "type" => profile.fetch("name"),
      "static" => true, "constant" => true, "value" => "2"
    }
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>=, 2
  end

  def test_graphics_profile_unexpected_public_helper_is_detected_at_runtime
    reference, target = graphics_profile_contracts
    profile = Microsoft::Xna::Framework::Graphics::GraphicsProfile
    profile.class_eval { def SupportsHiDef? = false }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    profile&.__send__(:remove_method, :SupportsHiDef?) if profile&.public_method_defined?(:SupportsHiDef?)
  end

  def test_graphics_profile_selected_surface_rejects_accidental_device_and_manager_properties
    full_reference = reference_contract

    reference, target = graphics_profile_selected_surface_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    property = full_reference.fetch("types").find { |type| type.fetch("name") == device_name }
                             .fetch("members").find do |member|
      member["kind"] == "property" && member["name"] == "GraphicsProfile"
    end
    target.fetch("types").find { |type| type.fetch("name") == device_name }
          .fetch("members") << Marshal.load(Marshal.dump(property))
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    reference, target = graphics_profile_selected_surface_contracts
    manager_name = "Microsoft.Xna.Framework.GraphicsDeviceManager"
    property = full_reference.fetch("types").find { |type| type.fetch("name") == manager_name }
                             .fetch("members").find do |member|
      member["kind"] == "property" && member["name"] == "GraphicsProfile"
    end
    target.fetch("types").find { |type| type.fetch("name") == manager_name }
          .fetch("members") << Marshal.load(Marshal.dump(property))
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    selected = signature_contract.fetch("types")
    refute selected.find { |type| type.fetch("name") == device_name }.fetch("members")
                   .any? { |member| member["name"] == "GraphicsProfile" }
    refute selected.find { |type| type.fetch("name") == manager_name }.fetch("members")
                   .any? { |member| member["name"] == "GraphicsProfile" }
  end

  def test_clear_options_missing_type_and_wrong_namespace_are_detected
    reference, target = clear_options_contracts
    target.fetch("types").clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = clear_options_contracts
    options = target.fetch("types").first
    options["name"] = "Microsoft.Xna.Framework.ClearOptions"
    options["rubyName"] = "Microsoft::Xna::Framework::ClearOptions"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_clear_options_wrong_kind_underlying_type_and_flags_are_detected
    reference, target = clear_options_contracts
    target.fetch("types").first["kind"] = "class"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0

    reference, target = clear_options_contracts
    target.fetch("types").first["underlyingType"] = "System.UInt32"
    result = verify(reference, target)
    assert_operator result.counts["ENUM_VALUE_MISMATCH"], :>, 0
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0

    reference, target = clear_options_contracts
    target.fetch("types").first["flags"] = false
    assert_operator verify(reference, target).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_clear_options_each_wrong_raw_value_is_detected
    reference, target = clear_options_contracts
    wrong_values = {"Target" => "2", "DepthBuffer" => "4", "Stencil" => "8"}
    target.fetch("types").first.fetch("members").each do |member|
      member["value"] = wrong_values.fetch(member.fetch("name"))
    end
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>=, 3
  end

  def test_clear_options_missing_stencil_exposed_storage_and_invented_values_are_detected
    reference, target = clear_options_contracts
    options = target.fetch("types").first
    options.fetch("members").reject! { |member| member["name"] == "Stencil" }
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    options.fetch("members") << Marshal.load(Marshal.dump(storage))
    %w[None Default All].zip(%w[0 0 7]).each do |name, raw|
      options.fetch("members") << {
        "kind" => "field", "name" => name, "type" => options.fetch("name"),
        "static" => true, "constant" => true, "value" => raw
      }
    end
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>=, 4
  end

  def test_clear_options_unexpected_xna_member_and_public_helper_are_detected
    reference, target = clear_options_contracts
    options = target.fetch("types").first
    options.fetch("members") << {
      "kind" => "method", "name" => "HasFlag", "static" => false, "access" => "public",
      "returnType" => "System.Boolean", "genericParameters" => [], "parameters" => []
    }
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    options_class = Microsoft::Xna::Framework::Graphics::ClearOptions
    options_class.class_eval { def Target? = false }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    options_class&.__send__(:remove_method, :Target?) if options_class&.public_method_defined?(:Target?)
  end

  def test_clear_options_runtime_flags_mask_is_measured
    reference, target = clear_options_contracts
    options = Microsoft::Xna::Framework::Graphics::ClearOptions
    original = options.instance_variable_get(:@enum_mask)
    options.instance_variable_set(:@enum_mask, original ^ 0x4)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  ensure
    options&.instance_variable_set(:@enum_mask, original) if original
  end

  def test_clear_options_runtime_ordinary_enum_classification_is_detected
    reference, target = clear_options_contracts
    options = Microsoft::Xna::Framework::Graphics::ClearOptions
    original = options.instance_variable_get(:@enum_flags)
    options.instance_variable_set(:@enum_flags, false)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  ensure
    options&.instance_variable_set(:@enum_flags, original) unless original.nil?
  end

  def test_clear_options_selected_surface_rejects_both_accidental_clear_overloads
    %w[Microsoft.Xna.Framework.Color Microsoft.Xna.Framework.Vector4].each do |color_type|
      reference, target = clear_options_selected_surface_contracts
      full_device = reference_contract.fetch("types").find do |type|
        type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
      end
      overload = full_device.fetch("members").find do |member|
        member["name"] == "Clear" && member.fetch("parameters").map { |parameter| parameter.fetch("type") } == [
          "Microsoft.Xna.Framework.Graphics.ClearOptions", color_type, "System.Single", "System.Int32"
        ]
      end
      refute_nil overload, color_type
      target.fetch("types").find do |type|
        type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
      end.fetch("members") << Marshal.load(Marshal.dump(overload))
      result = verify(reference, target)
      assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0, color_type
      assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>, 0, color_type
    end

    selected_device = signature_contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    end
    clear_members = selected_device.fetch("members").select { |member| member["name"] == "Clear" }
    assert_equal 1, clear_members.length
    assert_equal ["Microsoft.Xna.Framework.Color"],
                 clear_members.first.fetch("parameters").map { |parameter| parameter.fetch("type") }
  end

  def test_depth_format_missing_type_and_wrong_namespace_are_detected
    reference, target = depth_format_contracts
    target.fetch("types").clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = depth_format_contracts
    format = target.fetch("types").first
    format["name"] = "Microsoft.Xna.Framework.DepthFormat"
    format["rubyName"] = "Microsoft::Xna::Framework::DepthFormat"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_depth_format_wrong_kind_underlying_type_and_flags_are_detected
    reference, target = depth_format_contracts
    target.fetch("types").first["kind"] = "class"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0

    reference, target = depth_format_contracts
    target.fetch("types").first["underlyingType"] = "System.UInt32"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0

    reference, target = depth_format_contracts
    target.fetch("types").first["flags"] = true
    assert_operator verify(reference, target).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_depth_format_each_wrong_raw_value_is_detected
    {"None" => "1", "Depth16" => "0", "Depth24" => "3", "Depth24Stencil8" => "2"}.each do |name, raw|
      reference, target = depth_format_contracts
      target.fetch("types").first.fetch("members").find { |member| member["name"] == name }["value"] = raw
      assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0, name
    end
  end

  def test_depth_format_missing_middle_and_final_values_are_detected
    %w[Depth24 Depth24Stencil8].each do |name|
      reference, target = depth_format_contracts
      target.fetch("types").first.fetch("members").reject! { |member| member["name"] == name }
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, name
      refute_includes result.complete_types, depth_format_name, name
    end
  end

  def test_depth_format_exposed_storage_extra_value_and_renamed_final_value_are_detected
    reference, target = depth_format_contracts
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    target.fetch("types").first.fetch("members") << Marshal.load(Marshal.dump(storage))
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    reference, target = depth_format_contracts
    target.fetch("types").first.fetch("members") << {
      "kind" => "field", "name" => "Depth32", "type" => depth_format_name,
      "static" => true, "constant" => true, "value" => "4"
    }
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    reference, target = depth_format_contracts
    target.fetch("types").first.fetch("members")
          .find { |member| member["name"] == "Depth24Stencil8" }["name"] = "Depth24Stencil"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
  end

  def test_depth_format_unexpected_xna_member_and_public_helper_are_detected
    reference, target = depth_format_contracts
    target.fetch("types").first.fetch("members") << {
      "kind" => "method", "name" => "HasStencil", "static" => false, "access" => "public",
      "returnType" => "System.Boolean", "genericParameters" => [], "parameters" => []
    }
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    format_class = Microsoft::Xna::Framework::Graphics::DepthFormat
    format_class.class_eval { def HasStencil? = false }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    format_class&.__send__(:remove_method, :HasStencil?) if format_class&.public_method_defined?(:HasStencil?)
  end

  def test_depth_format_is_never_accepted_as_a_flags_enum
    # Depth24Stencil8 = 3 is one declared ordinary literal, not Depth16 | Depth24.
    pinned = reference_contract.fetch("types").find { |type| type.fetch("name") == depth_format_name }
    selected = signature_contract.fetch("types").find { |type| type.fetch("name") == depth_format_name }
    assert_equal false, pinned.fetch("flags")
    assert_equal false, selected.fetch("flags")
    combined = selected.fetch("members").reduce(0) { |mask, member| mask | Integer(member.fetch("value")) }
    assert_equal 3, combined
    assert_equal 3, Integer(selected.fetch("members").find { |member| member["name"] == "Depth24Stencil8" }.fetch("value"))

    reference, target = depth_format_contracts
    format = Microsoft::Xna::Framework::Graphics::DepthFormat
    original_flags = format.instance_variable_get(:@enum_flags)
    format.instance_variable_set(:@enum_flags, true)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
    format.instance_variable_set(:@enum_flags, original_flags)

    reference, target = depth_format_contracts
    reference.fetch("types").first["flags"] = true
    target.fetch("types").first["flags"] = true
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0
    assert_equal 0, format.instance_variable_get(:@enum_mask)
    assert_raises(TypeError) { format::Depth16 | format::Depth24 }
    assert_raises(TypeError) { format::Depth24Stencil8 & format::Depth24 }
  ensure
    format&.instance_variable_set(:@enum_flags, original_flags) unless original_flags.nil?
  end

  def test_depth_format_selected_surface_rejects_accidental_manager_property
    manager_name = "Microsoft.Xna.Framework.GraphicsDeviceManager"
    reference, target = depth_format_selected_surface_contracts
    property = reference_contract.fetch("types").find { |type| type.fetch("name") == manager_name }
                                 .fetch("members").find do |member|
      member["kind"] == "property" && member["name"] == "PreferredDepthStencilFormat"
    end
    refute_nil property
    assert_equal depth_format_name, property.fetch("type")
    target.fetch("types").find { |type| type.fetch("name") == manager_name }
          .fetch("members") << Marshal.load(Marshal.dump(property))
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    selected_manager = signature_contract.fetch("types").find { |type| type.fetch("name") == manager_name }
    refute selected_manager.fetch("members").any? { |member| member["name"] == "PreferredDepthStencilFormat" }
    refute Microsoft::Xna::Framework::GraphicsDeviceManager.public_method_defined?(:PreferredDepthStencilFormat)
    refute Microsoft::Xna::Framework::GraphicsDeviceManager.public_method_defined?(:"PreferredDepthStencilFormat=")
  end

  def test_primitive_type_missing_type_and_wrong_namespace_are_detected
    reference, target = primitive_type_contracts
    target.fetch("types").clear
    assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0

    reference, target = primitive_type_contracts
    topology = target.fetch("types").first
    topology["name"] = "Microsoft.Xna.Framework.PrimitiveType"
    topology["rubyName"] = "Microsoft::Xna::Framework::PrimitiveType"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_TYPE"], :>, 0
    assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0
  end

  def test_primitive_type_wrong_kind_underlying_type_and_flags_are_detected
    reference, target = primitive_type_contracts
    target.fetch("types").first["kind"] = "struct"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0

    reference, target = primitive_type_contracts
    target.fetch("types").first["underlyingType"] = "System.UInt32"
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0

    reference, target = primitive_type_contracts
    target.fetch("types").first["flags"] = true
    assert_operator verify(reference, target).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
  end

  def test_primitive_type_each_wrong_raw_value_is_detected
    {"TriangleList" => "1", "TriangleStrip" => "0", "LineList" => "3", "LineStrip" => "2"}.each do |name, raw|
      reference, target = primitive_type_contracts
      target.fetch("types").first.fetch("members").find { |member| member["name"] == name }["value"] = raw
      assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0, name
    end
  end

  def test_primitive_type_rejects_the_xna31_direct3d9_ordering
    # XNA 3.1 declared LineList=1, LineStrip=2, TriangleList=3, TriangleStrip=4
    # alongside PointList=0 and TriangleFan=5. XNA 4.0 renumbered the survivors.
    reference, target = primitive_type_contracts
    legacy = {"TriangleList" => "3", "TriangleStrip" => "4", "LineList" => "1", "LineStrip" => "2"}
    target.fetch("types").first.fetch("members").each { |member| member["value"] = legacy.fetch(member.fetch("name")) }
    assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0

    pinned = reference_contract.fetch("types").find { |type| type.fetch("name") == primitive_type_name }
    assert_equal({"TriangleList" => "0", "TriangleStrip" => "1", "LineList" => "2", "LineStrip" => "3"},
                 pinned.fetch("members").reject { |member| member["name"] == "value__" }
                       .to_h { |member| [member.fetch("name"), member.fetch("value")] })
    refute pinned.fetch("members").any? { |member| %w[PointList TriangleFan].include?(member["name"]) }
  end

  def test_primitive_type_missing_middle_and_final_values_are_detected
    %w[LineList LineStrip].each do |name|
      reference, target = primitive_type_contracts
      target.fetch("types").first.fetch("members").reject! { |member| member["name"] == name }
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, name
      refute_includes result.complete_types, primitive_type_name, name
    end
  end

  def test_primitive_type_exposed_storage_extra_values_and_renamed_final_value_are_detected
    reference, target = primitive_type_contracts
    storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
    target.fetch("types").first.fetch("members") << Marshal.load(Marshal.dump(storage))
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    {"PointList" => "4", "TriangleFan" => "5"}.each do |name, raw|
      reference, target = primitive_type_contracts
      target.fetch("types").first.fetch("members") << {
        "kind" => "field", "name" => name, "type" => primitive_type_name,
        "static" => true, "constant" => true, "value" => raw
      }
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, name
    end

    reference, target = primitive_type_contracts
    target.fetch("types").first.fetch("members")
          .find { |member| member["name"] == "LineStrip" }["name"] = "LineStrips"
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>, 0
    assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0
  end

  def test_primitive_type_unexpected_xna_member_and_public_helper_are_detected
    reference, target = primitive_type_contracts
    target.fetch("types").first.fetch("members") << {
      "kind" => "method", "name" => "GetVertexCount", "static" => false, "access" => "public",
      "returnType" => "System.Int32", "genericParameters" => [], "parameters" => []
    }
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    topology_class = Microsoft::Xna::Framework::Graphics::PrimitiveType
    topology_class.class_eval { def VertexCount = 0 }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    topology_class&.__send__(:remove_method, :VertexCount) if topology_class&.public_method_defined?(:VertexCount)
  end

  def test_primitive_type_is_never_accepted_as_a_flags_enum
    # LineStrip = 3 is one declared ordinary literal, not TriangleStrip | LineList.
    pinned = reference_contract.fetch("types").find { |type| type.fetch("name") == primitive_type_name }
    selected = signature_contract.fetch("types").find { |type| type.fetch("name") == primitive_type_name }
    assert_equal false, pinned.fetch("flags")
    assert_equal false, selected.fetch("flags")
    combined = selected.fetch("members").reduce(0) { |mask, member| mask | Integer(member.fetch("value")) }
    assert_equal 3, combined
    assert_equal 3, Integer(selected.fetch("members").find { |member| member["name"] == "LineStrip" }.fetch("value"))

    reference, target = primitive_type_contracts
    topology = Microsoft::Xna::Framework::Graphics::PrimitiveType
    original_flags = topology.instance_variable_get(:@enum_flags)
    topology.instance_variable_set(:@enum_flags, true)
    assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0
    topology.instance_variable_set(:@enum_flags, original_flags)

    reference, target = primitive_type_contracts
    reference.fetch("types").first["flags"] = true
    target.fetch("types").first["flags"] = true
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["FLAGS_MAPPING_MISMATCH"], :>, 0
    assert_equal 0, topology.instance_variable_get(:@enum_mask)
    assert_raises(TypeError) { topology::TriangleStrip | topology::LineList }
    assert_raises(TypeError) { topology::LineStrip & topology::LineList }
  ensure
    topology&.instance_variable_set(:@enum_flags, original_flags) unless original_flags.nil?
  end

  def test_primitive_type_selected_surface_rejects_accidental_graphics_device_draw_members
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    draw_names = %w[DrawIndexedPrimitives DrawInstancedPrimitives DrawPrimitives
                    DrawUserIndexedPrimitives DrawUserPrimitives]
    reference_device = reference_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    draw_members = reference_device.fetch("members").select { |member| draw_names.include?(member["name"]) }
    assert_equal 9, draw_members.length
    assert draw_members.all? { |member|
      member.fetch("parameters").any? { |parameter| parameter.fetch("type") == primitive_type_name }
    }

    draw_names.each do |name|
      reference, target = primitive_type_selected_surface_contracts
      reference_device.fetch("members").select { |member| member["name"] == name }.each do |member|
        target.fetch("types").find { |type| type.fetch("name") == device_name }
              .fetch("members") << Marshal.load(Marshal.dump(member))
      end
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, name
    end

    selected_device = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    refute selected_device.fetch("members").any? { |member| member.fetch("name").start_with?("Draw") }
    draw_names.each do |name|
      refute Microsoft::Xna::Framework::Graphics::GraphicsDevice.public_method_defined?(name), name
    end
    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))
    draw_names.each do |name|
      assert strict.fetch("details").fetch("MISSING_MEMBER").any? { |label| label.include?("#{device_name}::#{name} ") }, name
    end
  end

  def test_viewport_missing_project_and_unproject_are_detected
    %w[Project Unproject].each do |name|
      reference, target = viewport_contracts
      target.fetch("types").first.fetch("members").reject! { |member| member["name"] == name }
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, name
      assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>, 0, name
    end
  end

  def test_viewport_project_arity_parameter_and_return_mutations_are_detected
    reference, target = viewport_contracts
    project = target.fetch("types").first.fetch("members").find { |member| member["name"] == "Project" }
    project.fetch("parameters").pop
    assert_operator verify(reference, target).counts["PARAMETER_MAPPING_MISMATCH"], :>, 0

    reference, target = viewport_contracts
    project = target.fetch("types").first.fetch("members").find { |member| member["name"] == "Project" }
    project.fetch("parameters")[0]["type"] = "Microsoft.Xna.Framework.Vector2"
    project.fetch("parameters")[1]["type"] = "Microsoft.Xna.Framework.Vector3"
    project["returnType"] = "Microsoft.Xna.Framework.Vector4"
    result = verify(reference, target)
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["RETURN_MAPPING_MISMATCH"], :>, 0
  end

  def test_viewport_unproject_arity_parameter_order_and_return_mutations_are_detected
    reference, target = viewport_contracts
    unproject = target.fetch("types").first.fetch("members").find { |member| member["name"] == "Unproject" }
    unproject.fetch("parameters") << {
      "name" => "extra", "type" => "Microsoft.Xna.Framework.Matrix", "ref" => false,
      "out" => false, "in" => false, "optional" => false
    }
    assert_operator verify(reference, target).counts["PARAMETER_MAPPING_MISMATCH"], :>, 0

    reference, target = viewport_contracts
    unproject = target.fetch("types").first.fetch("members").find { |member| member["name"] == "Unproject" }
    unproject.fetch("parameters")[0]["type"] = "Microsoft.Xna.Framework.Matrix"
    unproject.fetch("parameters")[2]["type"] = "Microsoft.Xna.Framework.Vector3"
    unproject["returnType"] = "Microsoft.Xna.Framework.Vector2"
    result = verify(reference, target)
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["RETURN_MAPPING_MISMATCH"], :>, 0
  end

  def test_viewport_title_safe_area_missing_type_and_writable_mutations_are_detected
    reference, target = viewport_contracts
    target.fetch("types").first.fetch("members").reject! { |member| member["name"] == "TitleSafeArea" }
    assert_operator verify(reference, target).counts["MISSING_MEMBER"], :>, 0

    reference, target = viewport_contracts
    property = target.fetch("types").first.fetch("members").find { |member| member["name"] == "TitleSafeArea" }
    property["type"] = "Microsoft.Xna.Framework.Vector4"
    property["set"] = true
    result = verify(reference, target)
    assert_operator result.counts["PROPERTY_MAPPING_MISMATCH"], :>, 0
  end

  def test_viewport_lowercase_alias_is_detected_at_runtime
    reference, target = viewport_contracts
    viewport = Microsoft::Xna::Framework::Graphics::Viewport
    viewport.class_eval { def project(*) = nil }
    assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
  ensure
    viewport&.__send__(:remove_method, :project) if viewport&.public_method_defined?(:project)
  end

  def test_viewport_native_parameter_leaks_are_detected
    reference, target = viewport_contracts
    project = target.fetch("types").first.fetch("members").find { |member| member["name"] == "Project" }
    project.fetch("parameters") << {
      "name" => "native", "type" => "CNA_Handle/CNA::Native/Fiddle::Pointer", "ref" => false,
      "out" => false, "in" => false, "optional" => false
    }
    result = verify(reference, target, runtime: true)
    assert_operator result.counts["PARAMETER_MAPPING_MISMATCH"], :>, 0
    assert_operator result.counts["RAW_HANDLE_LEAK"], :>, 0
    assert_operator result.counts["PUBLIC_NATIVE_FFI_LEAK"], :>, 0
  end

  def test_viewport_complete_selection_and_accidental_partial_state_are_measured
    selected = JSON.parse(File.read(File.expand_path("../tools/api_compat/selection.json", __dir__)))
                   .fetch("types").find { |type| type.fetch("name") == viewport_name }
    assert_equal true, selected.fetch("complete")

    reference, target = viewport_contracts
    target.fetch("types").first.fetch("members").reject! do |member|
      %w[Project Unproject TitleSafeArea].include?(member["name"])
    end
    result = verify(reference, target)
    assert_operator result.counts["MISSING_MEMBER"], :>=, 3
    assert_operator result.counts["OVERLOAD_MAPPING_MISMATCH"], :>=, 2
  end

  def test_viewport_selected_surface_rejects_graphics_device_viewport_setter
    reference, target = viewport_selected_surface_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    full_property = reference_contract.fetch("types").find { |type| type.fetch("name") == device_name }
                                      .fetch("members").find do |member|
      member["kind"] == "property" && member["name"] == "Viewport"
    end
    selected_property = target.fetch("types").find { |type| type.fetch("name") == device_name }
                              .fetch("members").find { |member| member["name"] == "Viewport" }
    selected_property["set"] = full_property.fetch("set")
    selected_property["setAccess"] = full_property.fetch("setAccess")
    assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>, 0

    actual_property = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
                                        .fetch("members").find { |member| member["name"] == "Viewport" }
    refute actual_property.fetch("set")
    refute Microsoft::Xna::Framework::Graphics::GraphicsDevice.public_method_defined?(:Viewport=)
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

  def gamepad_contracts
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    target = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
    names = %w[
      Buttons GamePad GamePadButtons GamePadCapabilities GamePadDPad GamePadDeadZone
      GamePadState GamePadThumbSticks GamePadTriggers GamePadType
    ].map { |name| "Microsoft.Xna.Framework.Input.#{name}" }
    reference_types = reference.fetch("types").select { |type| names.include?(type.fetch("name")) }
    target_types = target.fetch("types").select { |type| names.include?(type.fetch("name")) }
    [{"types" => reference_types}, {"types" => Marshal.load(Marshal.dump(target_types))}]
  end

  def vertex_contracts
    reference = JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
    target = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
    names = %w[VertexElement VertexElementFormat VertexElementUsage].map do |name|
      "Microsoft.Xna.Framework.Graphics.#{name}"
    end
    reference_types = reference.fetch("types").select { |type| names.include?(type.fetch("name")) }
    target_types = target.fetch("types").select { |type| names.include?(type.fetch("name")) }
    [{"types" => reference_types}, {"types" => Marshal.load(Marshal.dump(target_types))}]
  end

  def display_orientation_contracts
    reference = reference_contract
    target = signature_contract
    name = "Microsoft.Xna.Framework.DisplayOrientation"
    reference_types = reference.fetch("types").select { |type| type.fetch("name") == name }
    target_types = target.fetch("types").select { |type| type.fetch("name") == name }
    [{"types" => reference_types}, {"types" => Marshal.load(Marshal.dump(target_types))}]
  end

  def graphics_device_status_contracts
    reference = reference_contract
    target = signature_contract
    name = "Microsoft.Xna.Framework.Graphics.GraphicsDeviceStatus"
    reference_types = reference.fetch("types").select { |type| type.fetch("name") == name }
    target_types = target.fetch("types").select { |type| type.fetch("name") == name }
    [{"types" => reference_types}, {"types" => Marshal.load(Marshal.dump(target_types))}]
  end

  def graphics_device_status_selected_surface_contracts
    reference, target = graphics_device_status_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    selected_device = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    reference.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    target.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    [reference, target]
  end

  def graphics_profile_contracts
    reference = reference_contract
    target = signature_contract
    name = "Microsoft.Xna.Framework.Graphics.GraphicsProfile"
    reference_types = reference.fetch("types").select { |type| type.fetch("name") == name }
    target_types = target.fetch("types").select { |type| type.fetch("name") == name }
    [{"types" => reference_types}, {"types" => Marshal.load(Marshal.dump(target_types))}]
  end

  def graphics_profile_selected_surface_contracts
    reference, target = graphics_profile_contracts
    names = [
      "Microsoft.Xna.Framework.Graphics.GraphicsDevice",
      "Microsoft.Xna.Framework.GraphicsDeviceManager"
    ]
    names.each do |name|
      selected = signature_contract.fetch("types").find { |type| type.fetch("name") == name }
      reference.fetch("types") << Marshal.load(Marshal.dump(selected))
      target.fetch("types") << Marshal.load(Marshal.dump(selected))
    end
    [reference, target]
  end

  def clear_options_name
    "Microsoft.Xna.Framework.Graphics.ClearOptions"
  end

  def clear_options_contracts
    reference = reference_contract
    target = signature_contract
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == clear_options_name }
    target_type = target.fetch("types").find { |type| type.fetch("name") == clear_options_name }
    [{"types" => [reference_type]}, {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def clear_options_selected_surface_contracts
    reference, target = clear_options_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    selected_device = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    reference.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    target.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    [reference, target]
  end

  def depth_format_name
    "Microsoft.Xna.Framework.Graphics.DepthFormat"
  end

  def depth_format_contracts
    reference = reference_contract
    target = signature_contract
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == depth_format_name }
    target_type = target.fetch("types").find { |type| type.fetch("name") == depth_format_name }
    [{"types" => [reference_type]}, {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def depth_format_selected_surface_contracts
    reference, target = depth_format_contracts
    manager_name = "Microsoft.Xna.Framework.GraphicsDeviceManager"
    selected_manager = signature_contract.fetch("types").find { |type| type.fetch("name") == manager_name }
    reference.fetch("types") << Marshal.load(Marshal.dump(selected_manager))
    target.fetch("types") << Marshal.load(Marshal.dump(selected_manager))
    [reference, target]
  end

  def primitive_type_name
    "Microsoft.Xna.Framework.Graphics.PrimitiveType"
  end

  def primitive_type_contracts
    reference = reference_contract
    target = signature_contract
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == primitive_type_name }
    target_type = target.fetch("types").find { |type| type.fetch("name") == primitive_type_name }
    [{"types" => [reference_type]}, {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def primitive_type_selected_surface_contracts
    reference, target = primitive_type_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    selected_device = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    reference.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    target.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    [reference, target]
  end

  def viewport_name
    "Microsoft.Xna.Framework.Graphics.Viewport"
  end

  def viewport_contracts
    reference = reference_contract
    target = signature_contract
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == viewport_name }
    target_type = target.fetch("types").find { |type| type.fetch("name") == viewport_name }
    [{"types" => [reference_type]}, {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def viewport_selected_surface_contracts
    reference, target = viewport_contracts
    device_name = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    selected_device = signature_contract.fetch("types").find { |type| type.fetch("name") == device_name }
    reference.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    target.fetch("types") << Marshal.load(Marshal.dump(selected_device))
    [reference, target]
  end

  # --- Foundation 16 PURE MANAGED BATCH A -------------------------------------------------
  #
  # Twenty-four dependency-complete pure managed enums closed in one batch. Rather than one
  # bespoke fixture family per enum, every mutation below is applied to each batch type in
  # turn, so a wrong raw value, a leaked synthetic storage field, a flipped flags bit or an
  # invented literal is rejected for all twenty-four with the same evidence.
  BATCH_ENUMS = %w[
    Microsoft.Xna.Framework.Audio.AudioChannels
    Microsoft.Xna.Framework.Audio.AudioStopOptions
    Microsoft.Xna.Framework.Audio.MicrophoneState
    Microsoft.Xna.Framework.Audio.SoundState
    Microsoft.Xna.Framework.Graphics.Blend
    Microsoft.Xna.Framework.Graphics.BlendFunction
    Microsoft.Xna.Framework.Graphics.BufferUsage
    Microsoft.Xna.Framework.Graphics.ColorWriteChannels
    Microsoft.Xna.Framework.Graphics.CompareFunction
    Microsoft.Xna.Framework.Graphics.CubeMapFace
    Microsoft.Xna.Framework.Graphics.CullMode
    Microsoft.Xna.Framework.Graphics.EffectParameterClass
    Microsoft.Xna.Framework.Graphics.EffectParameterType
    Microsoft.Xna.Framework.Graphics.FillMode
    Microsoft.Xna.Framework.Graphics.IndexElementSize
    Microsoft.Xna.Framework.Graphics.PresentInterval
    Microsoft.Xna.Framework.Graphics.RenderTargetUsage
    Microsoft.Xna.Framework.Graphics.SetDataOptions
    Microsoft.Xna.Framework.Graphics.StencilOperation
    Microsoft.Xna.Framework.Graphics.TextureAddressMode
    Microsoft.Xna.Framework.Graphics.TextureFilter
    Microsoft.Xna.Framework.Media.MediaSourceType
    Microsoft.Xna.Framework.Media.MediaState
    Microsoft.Xna.Framework.Media.VideoSoundtrackType
  ].freeze

  # Foundation 17 added the Input.Touch closure. Its two enums join the same mutation battery.
  TOUCH_CLOSURE_ENUMS = %w[
    Microsoft.Xna.Framework.Input.Touch.GestureType
    Microsoft.Xna.Framework.Input.Touch.TouchLocationState
  ].freeze

  PURE_MANAGED_ENUMS = (BATCH_ENUMS + TOUCH_CLOSURE_ENUMS).freeze

  FLAGS_BATCH_ENUMS = %w[
    Microsoft.Xna.Framework.Input.Touch.GestureType
    Microsoft.Xna.Framework.Graphics.BufferUsage
    Microsoft.Xna.Framework.Graphics.ColorWriteChannels
    Microsoft.Xna.Framework.Graphics.SetDataOptions
  ].freeze

  def batch_enum_contracts(type_name)
    reference = reference_contract
    target = signature_contract
    reference_type = reference.fetch("types").find { |type| type.fetch("name") == type_name }
    target_type = target.fetch("types").find { |type| type.fetch("name") == type_name }
    refute_nil reference_type, type_name
    refute_nil target_type, type_name
    [{"types" => [reference_type]}, {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def test_batch_enums_are_selected_complete_and_locally_clean
    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))
    assert_equal 24, BATCH_ENUMS.length
    assert_equal 2, TOUCH_CLOSURE_ENUMS.length
    assert_equal 26, PURE_MANAGED_ENUMS.length
    assert_equal PURE_MANAGED_ENUMS.length, PURE_MANAGED_ENUMS.uniq.length
    touch_identities = TOUCH_CLOSURE_ENUMS.sum do |type_name|
      _reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first.fetch("members").length
    end
    assert_equal 15, touch_identities
    identities = BATCH_ENUMS.sum do |type_name|
      reference, target = batch_enum_contracts(type_name)
      # Structural only: a single-type contract cannot carry the whole runtime namespace,
      # so runtime leak walking is exercised by the full-surface verifier run instead.
      result = verify(reference, target)
      assert_equal 0, result.counts.values.sum, type_name
      assert_includes result.complete_types, type_name
      assert_includes strict.fetch("completeTypeNames"), type_name
      assert_equal 0, strict.fetch("localDiagnostics").fetch(type_name), type_name
      target.fetch("types").first.fetch("members").length
    end
    assert_equal 109, identities
  end

  def test_batch_enums_reject_a_missing_type_or_a_relocated_namespace
    PURE_MANAGED_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").clear
      assert_operator verify(reference, target).counts["MISSING_TYPE"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      relocated = "Microsoft.Xna.Framework.#{type_name.split(".").last}"
      target.fetch("types").first["name"] = relocated
      target.fetch("types").first["rubyName"] = relocated.gsub(".", "::")
      result = verify(reference, target)
      assert_operator result.counts["MISSING_TYPE"], :>, 0, type_name
      assert_operator result.counts["UNEXPECTED_TYPE"], :>, 0, type_name
    end
  end

  def test_batch_enums_reject_a_wrong_kind_underlying_type_or_flags_bit
    PURE_MANAGED_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first["kind"] = "struct"
      assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first["underlyingType"] = "System.UInt32"
      assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      selected = target.fetch("types").first
      selected["flags"] = !selected.fetch("flags")
      assert_operator verify(reference, target).counts["FLAGS_MAPPING_MISMATCH"], :>, 0, type_name
    end
  end

  def test_batch_enums_reject_every_individually_wrong_raw_value
    PURE_MANAGED_ENUMS.each do |type_name|
      _reference, pristine = batch_enum_contracts(type_name)
      pristine.fetch("types").first.fetch("members").each do |member|
        reference, target = batch_enum_contracts(type_name)
        mutated = target.fetch("types").first.fetch("members").find { |candidate| candidate["name"] == member["name"] }
        mutated["value"] = (Integer(member.fetch("value")) + 1).to_s
        assert_operator verify(reference, target).counts["ENUM_VALUE_MISMATCH"], :>, 0,
                        "#{type_name}::#{member["name"]}"
      end
    end
  end

  def test_batch_enums_reject_a_dropped_renamed_or_invented_literal
    PURE_MANAGED_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      dropped = target.fetch("types").first.fetch("members").pop.fetch("name")
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, "#{type_name}::#{dropped}"
      refute_includes result.complete_types, type_name

      reference, target = batch_enum_contracts(type_name)
      renamed = target.fetch("types").first.fetch("members").first
      renamed["name"] = "#{renamed.fetch("name")}Ex"
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, type_name
      assert_operator result.counts["UNEXPECTED_MEMBER"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      highest = target.fetch("types").first.fetch("members").map { |member| Integer(member.fetch("value")) }.max
      target.fetch("types").first.fetch("members") << {
        "kind" => "field", "name" => "Invented", "type" => type_name,
        "static" => true, "constant" => true, "value" => (highest + 1).to_s
      }
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, type_name
    end
  end

  def test_batch_enums_reject_exposed_synthetic_storage_and_a_helper_method
    PURE_MANAGED_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      storage = reference.fetch("types").first.fetch("members").find { |member| member["name"] == "value__" }
      refute_nil storage, type_name
      target.fetch("types").first.fetch("members") << Marshal.load(Marshal.dump(storage))
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first.fetch("members") << {
        "kind" => "method", "name" => "Parse", "static" => true, "access" => "public",
        "returnType" => type_name, "genericParameters" => [], "parameters" => []
      }
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, type_name
    end
  end

  def test_batch_enum_runtime_flags_and_masks_are_pinned_against_the_contract
    PURE_MANAGED_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      selected = target.fetch("types").first
      runtime_type = CNAApiCompat::NameMapper.runtime_constant_path(type_name)
                                             .split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      flags = selected.fetch("flags")
      assert_equal flags, FLAGS_BATCH_ENUMS.include?(type_name), type_name
      assert_equal flags, runtime_type.instance_variable_get(:@enum_flags), type_name
      expected_mask = flags ? selected.fetch("members").reduce(0) { |mask, member| mask | Integer(member.fetch("value")) } : 0
      assert_equal expected_mask, runtime_type.instance_variable_get(:@enum_mask), type_name

      original = runtime_type.instance_variable_get(:@enum_flags)
      begin
        runtime_type.instance_variable_set(:@enum_flags, !original)
        assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0, type_name
      ensure
        runtime_type.instance_variable_set(:@enum_flags, original)
      end
      assert_equal 0, verify(reference, target, runtime: true).counts.fetch("FLAGS_MAPPING_MISMATCH"), type_name
      assert_equal 0, verify(reference, target).counts.values.sum, type_name
    end
  end

  def test_batch_flags_enums_reject_a_wrong_runtime_combined_value_mask
    FLAGS_BATCH_ENUMS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      runtime_type = CNAApiCompat::NameMapper.runtime_constant_path(type_name)
                                             .split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      original = runtime_type.instance_variable_get(:@enum_mask)
      begin
        runtime_type.instance_variable_set(:@enum_mask, original | (original + 1))
        assert_operator verify(reference, target, runtime: true).counts["FLAGS_MAPPING_MISMATCH"], :>, 0, type_name
      ensure
        runtime_type.instance_variable_set(:@enum_mask, original)
      end
    end
  end

  INTERFACE_CONTRACTS = %w[
    Microsoft.Xna.Framework.Graphics.IEffectFog
    Microsoft.Xna.Framework.Graphics.IEffectMatrices
    Microsoft.Xna.Framework.IGameComponent
    Microsoft.Xna.Framework.IGraphicsDeviceManager
  ].freeze

  def test_interface_contracts_are_selected_complete_and_event_free
    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))
    identities = INTERFACE_CONTRACTS.sum do |type_name|
      reference, target = batch_enum_contracts(type_name)
      assert_equal "interface", target.fetch("types").first.fetch("kind"), type_name
      assert_equal 0, verify(reference, target).counts.values.sum, type_name
      assert_equal 0, strict.fetch("localDiagnostics").fetch(type_name), type_name
      assert_includes strict.fetch("completeTypeNames"), type_name
      refute target.fetch("types").first.fetch("members").any? { |member| member["kind"] == "event" }
      target.fetch("types").first.fetch("members").length
    end
    assert_equal 11, identities
  end

  def test_interface_contract_mutations_are_detected
    INTERFACE_CONTRACTS.each do |type_name|
      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first["kind"] = "class"
      assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0, type_name

      reference, target = batch_enum_contracts(type_name)
      dropped = target.fetch("types").first.fetch("members").pop.fetch("name")
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, "#{type_name}::#{dropped}"
      refute_includes result.complete_types, type_name

      reference, target = batch_enum_contracts(type_name)
      target.fetch("types").first.fetch("members") << {
        "kind" => "method", "name" => "Reset", "static" => false, "access" => "public",
        "returnType" => "System.Void", "genericParameters" => [], "parameters" => []
      }
      assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0, type_name
    end
  end

  def test_interface_property_accessors_are_pinned_in_both_directions
    {"Microsoft.Xna.Framework.Graphics.IEffectMatrices" => %w[World View Projection],
     "Microsoft.Xna.Framework.Graphics.IEffectFog" => %w[FogEnabled FogStart FogEnd FogColor]}
      .each do |type_name, properties|
      properties.each do |property|
        reference, target = batch_enum_contracts(type_name)
        member = target.fetch("types").first.fetch("members").find { |candidate| candidate["name"] == property }
        assert_equal true, member.fetch("get"), "#{type_name}::#{property}"
        assert_equal true, member.fetch("set"), "#{type_name}::#{property}"
        member["set"] = false
        assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>, 0, property
      end

      # A runtime module missing one declared setter must be reported as a missing member.
      interface = CNAApiCompat::NameMapper.runtime_constant_path(type_name)
                                          .split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      setter = :"#{properties.first}="
      original = interface.instance_method(setter)
      reference, target = batch_enum_contracts(type_name)
      begin
        interface.__send__(:remove_method, setter)
        assert_operator verify(reference, target, runtime: true).counts["MISSING_MEMBER"], :>, 0, type_name
      ensure
        interface.__send__(:define_method, setter, original)
      end
      assert_equal 0, verify(reference, target, runtime: true).counts["MISSING_MEMBER"], type_name
    end
  end

  # Foundation 20 replaced the "no selected type declares an event" safety assertion with a
  # measured projection policy: every selected event identity must project, and the strict report
  # must count the identities it measured.
  def test_every_selected_event_identity_is_measured_and_projected
    selected = signature_contract.fetch("types").flat_map do |type|
      type.fetch("members").select { |member| member.fetch("kind") == "event" }
          .map { |member| "#{type.fetch("name")}::#{member.fetch("name")}" }
    end
    # Foundation 35 added the first *concrete* owner: until then only the two abstract contracts
    # declared an event, so the census was four. Foundation 40 added a third abstract contract,
    # Graphics::IGraphicsDeviceService, whose four events are the graphics-device service events.
    assert_equal %w[
      Microsoft.Xna.Framework.GameComponentCollection::ComponentAdded
      Microsoft.Xna.Framework.GameComponentCollection::ComponentRemoved
      Microsoft.Xna.Framework.GameComponent::EnabledChanged
      Microsoft.Xna.Framework.GameComponent::UpdateOrderChanged
      Microsoft.Xna.Framework.GameComponent::Disposed
      Microsoft.Xna.Framework.IUpdateable::EnabledChanged
      Microsoft.Xna.Framework.IUpdateable::UpdateOrderChanged
      Microsoft.Xna.Framework.IDrawable::VisibleChanged
      Microsoft.Xna.Framework.IDrawable::DrawOrderChanged
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceDisposing
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceReset
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceResetting
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceCreated
      Microsoft.Xna.Framework.Game::Activated
      Microsoft.Xna.Framework.Game::Deactivated
      Microsoft.Xna.Framework.Game::Exiting
      Microsoft.Xna.Framework.Game::Disposed
    ], selected

    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))
    assert_equal selected, strict.fetch("eventIdentities")
    assert_equal selected.length, strict.fetch("EVENT_IDENTITIES")
    assert_equal 6, strict.fetch("EVENT_OWNER_TYPES")
    assert_equal "CNA::Runtime::Event", strict.fetch("EVENT_SUPPORT_TYPE")
    assert_equal 0, strict.fetch("EVENT_MAPPING_MISMATCH")

    # Every selected event's CLR support type is the generic delegate this projection maps, closed
    # over whatever args type the event declares -- System.EventArgs for the three interfaces, and
    # GameComponentCollectionEventArgs for the collection Foundation 35 added. One reader identity
    # answers for every closed form, which is the point of mapping the definition.
    signature_contract.fetch("types").each do |type|
      type.fetch("members").select { |member| member.fetch("kind") == "event" }.each do |member|
        assert_match(/\ASystem\.EventHandler`1\[[^\[\]]+\]\z/, member.fetch("type"))
        assert_equal true, member.fetch("add")
        assert_equal true, member.fetch("remove")
        assert_equal false, member.fetch("static")
      end
    end
    assert_equal ["System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]",
                  "System.EventHandler`1[System.EventArgs]"],
                 signature_contract.fetch("types").flat_map { |type|
                   type.fetch("members").select { |member| member.fetch("kind") == "event" }
                       .map { |member| member.fetch("type") }
                 }.uniq.sort
  end

  def test_event_kind_projects_exactly_one_reader_identity
    verifier = CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []})
    instance = {"kind" => "event", "name" => "Changed", "static" => false}
    assert_equal ["instance:Changed"], verifier.__send__(:ruby_projections, instance)
    assert_equal ["class:Changed"], verifier.__send__(:ruby_projections, instance.merge("static" => true))

    # Never an add_/remove_ pair, never a writer.
    projections = verifier.__send__(:ruby_projections, instance)
    refute_includes projections, "instance:add_Changed"
    refute_includes projections, "instance:remove_Changed"
    refute_includes projections, "instance:Changed="
  end

  def test_touch_panel_capabilities_struct_mutations_are_detected
    name = "Microsoft.Xna.Framework.Input.Touch.TouchPanelCapabilities"
    reference, target = batch_enum_contracts(name)
    assert_equal 0, verify(reference, target).counts.values.sum
    assert_equal "struct", target.fetch("types").first.fetch("kind")

    reference, target = batch_enum_contracts(name)
    target.fetch("types").first["kind"] = "class"
    assert_operator verify(reference, target).counts["TYPE_KIND_MISMATCH"], :>, 0

    %w[IsConnected MaximumTouchCount].each do |property|
      reference, target = batch_enum_contracts(name)
      target.fetch("types").first.fetch("members").reject! { |member| member["name"] == property }
      result = verify(reference, target)
      assert_operator result.counts["MISSING_MEMBER"], :>, 0, property
      refute_includes result.complete_types, name

      # A writable projection would be an invented identity: both properties are get-only.
      reference, target = batch_enum_contracts(name)
      target.fetch("types").first.fetch("members")
            .find { |member| member["name"] == property }["set"] = true
      assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>, 0, property

      reference, target = batch_enum_contracts(name)
      target.fetch("types").first.fetch("members")
            .find { |member| member["name"] == property }["type"] = "System.Single"
      assert_operator verify(reference, target).counts["PROPERTY_MAPPING_MISMATCH"], :>, 0, property
    end

    reference, target = batch_enum_contracts(name)
    target.fetch("types").first.fetch("members") << {
      "kind" => "method", "name" => "GetCapabilities", "static" => true, "access" => "public",
      "returnType" => name, "genericParameters" => [], "parameters" => []
    }
    assert_operator verify(reference, target).counts["UNEXPECTED_MEMBER"], :>, 0

    capabilities = Microsoft::Xna::Framework::Input::Touch::TouchPanelCapabilities
    begin
      capabilities.class_eval { def IsConnected=(value); end }
      assert_operator verify(reference, target, runtime: true).counts["UNEXPECTED_MEMBER"], :>, 0
    ensure
      capabilities.__send__(:remove_method, :IsConnected=)
    end
  end

  def test_touch_value_types_are_selected_but_no_touch_panel_surface_is
    reference = reference_contract
    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))

    # Foundation 23 completed the two publicly constructible value types from pinned IL.
    %w[TouchLocation GestureSample].each do |short|
      full = "Microsoft.Xna.Framework.Input.Touch.#{short}"
      assert signature_contract.fetch("types").any? { |type| type.fetch("name") == full }, full
      assert_includes strict.fetch("completeTypeNames"), full
    end

    # Foundation 31 added TouchCollection and its nested Enumerator, whose IL reads nothing.
    %w[TouchCollection TouchCollection+Enumerator].each do |short|
      full = "Microsoft.Xna.Framework.Input.Touch.#{short}"
      assert signature_contract.fetch("types").any? { |type| type.fetch("name") == full }, full
      assert_includes strict.fetch("completeTypeNames"), full
    end

    # Foundation 32 added TouchPanel. On this profile its whole assembly is a stub -- the IL
    # inventory measures no native reachability anywhere in it -- so nothing here reads a device.
    %w[TouchPanel].each do |short|
      full = "Microsoft.Xna.Framework.Input.Touch.#{short}"
      assert reference.fetch("types").any? { |type| type.fetch("name") == full }, full
      assert signature_contract.fetch("types").any? { |type| type.fetch("name") == full }, full
      assert_includes strict.fetch("completeTypeNames"), full
    end
    assert_empty strict.fetch("missingTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Input\.Touch\./)
  end

  def test_batch_does_not_expand_the_six_deferred_partial_runtime_types
    strict = JSON.parse(File.read(File.expand_path("../docs/generated/api-compat-report.json", __dir__)))
    partial = strict.fetch("partialTypes")
    assert_equal %w[
      Microsoft.Xna.Framework.Game
      Microsoft.Xna.Framework.GraphicsDeviceManager
      Microsoft.Xna.Framework.Graphics.GraphicsDevice
      Microsoft.Xna.Framework.Graphics.GraphicsResource
      Microsoft.Xna.Framework.Graphics.SpriteBatch
      Microsoft.Xna.Framework.Graphics.Texture2D
    ].sort, partial.keys.sort
    # 132 until Foundation 37 closed Game::Components and Game::Services, 130 until Foundation
    # 41 closed Game's four events and their three protected raisers -- the three methods among
    # those are also why the overload count fell by three -- and 117 until Foundation 44 closed
    # Game::Tick, a method, which is why the overload count fell by one more. The set of partial
    # types is what this test guards, and it is unchanged. Foundation 45 then closed
    # Game::IsActive, a property, so MISSING_MEMBER fell once more without moving the overloads.
    assert_equal 114, strict.fetch("MISSING_MEMBER")
    assert_equal 1, strict.fetch("PROPERTY_MAPPING_MISMATCH")
    assert_equal 45, strict.fetch("OVERLOAD_MAPPING_MISMATCH")

    # Every batch enum that a deferred member mentions leaves that member deferred.
    deferred = strict.fetch("details").fetch("MISSING_MEMBER")
    %w[SetRenderTarget PreferredDepthStencilFormat].each do |name|
      assert deferred.any? { |label| label.include?(name) }, name
    end
    assert_equal %i[IsDisposed Viewport Clear].sort,
                 Microsoft::Xna::Framework::Graphics::GraphicsDevice.public_instance_methods(false).sort
  end

  def reference_contract
    JSON.parse(File.read(File.expand_path("../tools/api_compat/reference/xna40-windows-runtime-contract.json", __dir__)))
  end

  def signature_contract
    JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
  end
end
