# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "json"
require "rbs"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

class RbsRuntimeConsistencyTest < Minitest::Test
  SIGNATURE_ROOT = Pathname(__dir__).join("..", "sig").expand_path
  TYPE_PREFIX = "::Microsoft"

  def test_every_declared_xna_type_and_member_exists_at_runtime
    loader = RBS::EnvironmentLoader.new
    loader.add(path: SIGNATURE_ROOT)
    environment = RBS::Environment.from_loader(loader).resolve_type_names

    declarations = environment.class_decls.filter_map do |name, entry|
      [name, entry] if name.to_s.start_with?(TYPE_PREFIX)
    end

    refute_empty declarations
    declarations.each do |name, entry|
      runtime_type = resolve_constant(name)
      declaration = entry.decls.first.decl

      if declaration.is_a?(RBS::AST::Declarations::Module)
        assert_kind_of Module, runtime_type, name.to_s
      else
        assert_instance_of Class, runtime_type, name.to_s
      end

      declaration.members.each do |member|
        verify_member(runtime_type, member)
      end
    end
  end

  def test_geometry_rbs_retains_every_static_contract_identity
    environment = load_environment
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    geometry_names = %w[
      Vector2 Vector3 Vector4 Quaternion Matrix Plane Ray BoundingBox BoundingSphere BoundingFrustum
      ContainmentType PlaneIntersectionType
    ].map { |name| "Microsoft.Xna.Framework.#{name}" }
    selected = contract.fetch("types").select { |type| geometry_names.include?(type.fetch("name")) }
    expected = selected.sum do |type|
      type.fetch("members").sum do |member|
        if %w[constructor method].include?(member["kind"])
          1
        elsif member["kind"] == "property"
          (member["get"] ? 1 : 0) + (member["set"] ? 1 : 0)
        else
          0
        end
      end
    end
    actual = selected.sum do |type|
      name, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == "::#{type.fetch("rubyName")}" }
      raise "missing geometry RBS declaration #{type.fetch("rubyName")}" unless name
      entry.decls.sum do |declaration|
        declaration.decl.members.sum do |member|
          member.instance_of?(RBS::AST::Members::MethodDefinition) ? member.overloads.length : 0
        end
      end
    end
    assert_equal expected, actual
    refute_includes File.read(SIGNATURE_ROOT.join("microsoft", "xna", "geometry.rbs")), "untyped"
  end

  def test_presentation_value_rbs_retains_every_static_contract_identity
    environment = load_environment
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").select do |type|
      %w[Microsoft.Xna.Framework.Color Microsoft.Xna.Framework.Rectangle].include?(type.fetch("name"))
    end
    operators = {"op_Equality" => "==", "op_Inequality" => "!=", "op_Multiply" => "*"}

    assert_equal 2, selected.length
    selected.each do |type|
      _name, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == "::#{type.fetch("rubyName")}" }
      refute_nil entry, type.fetch("rubyName")
      definitions = entry.decls.flat_map do |declaration|
        declaration.decl.members.grep(RBS::AST::Members::MethodDefinition)
      end.group_by { |member| member.name.to_s }
      expected = type.fetch("members").select { |member| %w[constructor method].include?(member["kind"]) }.group_by do |member|
        member["kind"] == "constructor" ? "initialize" : operators.fetch(member["name"], member["name"])
      end
      expected.each do |method_name, identities|
        actual = definitions.fetch(method_name).sum { |definition| definition.overloads.length }
        projected_default = method_name == "initialize" ? 1 : 0
        assert_equal identities.length + projected_default, actual, "#{type.fetch("name")}##{method_name}"
      end
    end
    assert_equal 19, selected.find { |type| type["name"].end_with?(".Color") }.fetch("members").count { |member| %w[constructor method].include?(member["kind"]) }
    assert_equal 21, selected.find { |type| type["name"].end_with?(".Rectangle") }.fetch("members").count { |member| %w[constructor method].include?(member["kind"]) }
    refute_includes File.read(SIGNATURE_ROOT.join("microsoft", "xna", "presentation_values.rbs")), "untyped"
  end

  def test_curve_rbs_retains_every_static_contract_identity_and_collection_projection
    environment = load_environment
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    curve_names = %w[Curve CurveKey CurveKeyCollection CurveContinuity CurveLoopType CurveTangent].map do |name|
      "Microsoft.Xna.Framework.#{name}"
    end
    selected = contract.fetch("types").select { |type| curve_names.include?(type.fetch("name")) }
    expected_methods = selected.sum do |type|
      type.fetch("members").sum do |member|
        if %w[constructor method].include?(member["kind"])
          1
        elsif member["kind"] == "property"
          (member["get"] ? 1 : 0) + (member["set"] ? 1 : 0)
        else
          0
        end
      end
    end
    actual_methods = selected.sum do |type|
      name, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == "::#{type.fetch("rubyName")}" }
      raise "missing Curve RBS declaration #{type.fetch("rubyName")}" unless name
      entry.decls.sum do |declaration|
        declaration.decl.members.sum do |member|
          member.instance_of?(RBS::AST::Members::MethodDefinition) ? member.overloads.length : 0
        end
      end
    end
    assert_equal 6, selected.length
    assert_equal 49, selected.sum { |type| type.fetch("members").length }
    assert_equal expected_methods, actual_methods

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "curve.rbs"))
    refute_includes source, "untyped"
    refute_match(/\*\w*/, source)
    assert_includes source, "def []: (Integer index) -> CurveKey"
    assert_includes source, "def []=: (Integer index, CurveKey value) -> CurveKey"
    assert_includes source, "def GetEnumerator: () -> Enumerator[CurveKey, nil]"
  end

  def test_packed_vector_rbs_retains_generic_and_all_171_callable_identities
    environment = load_environment
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").select do |type|
      type.fetch("name").start_with?("Microsoft.Xna.Framework.Graphics.PackedVector.")
    end
    assert_equal 19, selected.length
    assert_equal 171, selected.sum { |type| type.fetch("members").length }

    expected = selected.sum do |type|
      type.fetch("members").sum do |member|
        if %w[constructor method].include?(member["kind"])
          1
        elsif member["kind"] == "property"
          (member["get"] ? 1 : 0) + (member["set"] ? 1 : 0)
        else
          0
        end
      end
    end
    actual = selected.sum do |type|
      _name, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == "::#{type.fetch("rubyName")}" }
      refute_nil entry, type.fetch("rubyName")
      entry.decls.sum do |declaration|
        declaration.decl.members.sum do |member|
          case member
          when RBS::AST::Members::MethodDefinition then member.overloads.length
          when RBS::AST::Members::AttrAccessor then 2
          when RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter then 1
          else 0
          end
        end
      end
    end
    assert_equal expected, actual
    assert_equal 189, actual

    generic_name, generic_entry = environment.class_decls.find do |name, _entry|
      name.to_s == "::Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVectorOfT"
    end
    refute_nil generic_name
    generic = generic_entry.decls.first.decl
    assert_equal ["TPacked"], generic.type_params.map { |parameter| parameter.name.to_s }
    includes = generic.members.grep(RBS::AST::Members::Include).map { |member| member.name.to_s }
    assert_includes includes, "::Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVector"

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "packed_vector.rbs"))
    refute_includes source, "untyped"
    refute_match(/\*\w*/, source)
    assert_includes source, "module IPackedVectorOfT[TPacked]"
  end

  def test_mouse_rbs_retains_exact_cluster_and_signed_intptr_integer_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[
      Microsoft.Xna.Framework.Input.ButtonState
      Microsoft.Xna.Framework.Input.MouseState
      Microsoft.Xna.Framework.Input.Mouse
    ]
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 3, selected.length
    assert_equal 19, selected.sum { |type| type.fetch("members").length }
    assert_equal CNAApiCompat::LANGUAGE_TYPE_MAPPINGS.fetch("System.IntPtr"),
                 contract.fetch("languageTypeMappings").fetch("System.IntPtr")

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "input.rbs"))
    refute_includes source, "untyped"
    refute_match(/\*\w*/, source)
    assert_includes source, "def initialize: (Integer x, Integer y, Integer scrollWheel, ButtonState leftButton, ButtonState middleButton, ButtonState rightButton, ButtonState xButton1, ButtonState xButton2) -> void"
    assert_includes source, "def Equals: (Object obj) -> bool"
    refute_includes source, "def Equals: (MouseState"
    assert_includes source, "def self.WindowHandle: () -> Integer"
    assert_includes source, "def self.WindowHandle=: (Integer value) -> Integer"
  end

  def test_gamepad_rbs_retains_exact_126_identity_cluster_and_array_overloads
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[
      Buttons GamePad GamePadButtons GamePadCapabilities GamePadDPad GamePadDeadZone
      GamePadState GamePadThumbSticks GamePadTriggers GamePadType
    ].map { |name| "Microsoft.Xna.Framework.Input.#{name}" }
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 10, selected.length
    assert_equal 126, selected.sum { |type| type.fetch("members").length }

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "input.rbs"))
    refute_includes source, "untyped"
    refute_includes source, "class GamePadCapabilities\n          def initialize"
    assert_includes source, "| (::Microsoft::Xna::Framework::Vector2 leftThumbStick, ::Microsoft::Xna::Framework::Vector2 rightThumbStick, Float leftTrigger, Float rightTrigger, Array[Buttons] buttons) -> void"
    assert_includes source, "def self.GetState: (::Microsoft::Xna::Framework::PlayerIndex playerIndex) -> GamePadState"
    assert_includes source, "| (::Microsoft::Xna::Framework::PlayerIndex playerIndex, GamePadDeadZone deadZoneMode) -> GamePadState"
    refute_match(/def Equals: \(GamePad(?:Buttons|DPad|State|ThumbSticks|Triggers)/, source)
    assert_includes source, "def self.SetVibration: (::Microsoft::Xna::Framework::PlayerIndex playerIndex, Float leftMotor, Float rightMotor) -> bool"
  end

  def test_vertex_element_rbs_retains_exact_35_identity_closure_and_default_projection
    environment = load_environment
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[VertexElement VertexElementFormat VertexElementUsage].map do |name|
      "Microsoft.Xna.Framework.Graphics.#{name}"
    end
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 3, selected.length
    assert_equal 35, selected.sum { |type| type.fetch("members").length }

    expected_callable = selected.sum do |type|
      type.fetch("members").sum do |member|
        if %w[constructor method].include?(member["kind"])
          1
        elsif member["kind"] == "property"
          (member["get"] ? 1 : 0) + (member["set"] ? 1 : 0)
        else
          0
        end
      end
    end
    actual_callable = selected.sum do |type|
      _name, entry = environment.class_decls.find do |candidate, _value|
        candidate.to_s == "::#{type.fetch("rubyName")}"
      end
      refute_nil entry, type.fetch("rubyName")
      entry.decls.sum do |declaration|
        declaration.decl.members.sum do |member|
          member.instance_of?(RBS::AST::Members::MethodDefinition) ? member.overloads.length : 0
        end
      end
    end
    assert_equal 14, expected_callable
    assert_equal expected_callable + 1, actual_callable

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "vertex_element.rbs"))
    refute_includes source, "untyped"
    refute_match(/\*\w*/, source)
    assert_includes source, "def initialize: () -> void"
    assert_includes source, "| (Integer offset, VertexElementFormat elementFormat, VertexElementUsage elementUsage, Integer usageIndex) -> void"
    assert_includes source, "def Equals: (Object obj) -> bool"
    refute_includes source, "def Equals: (VertexElement"
    assert_includes source, "def ==: (VertexElement right) -> bool"
    assert_includes source, "def !=: (VertexElement right) -> bool"
    assert_equal 12, selected.find { |type| type["name"].end_with?(".VertexElementFormat") }.fetch("members").length
    assert_equal 13, selected.find { |type| type["name"].end_with?(".VertexElementUsage") }.fetch("members").length
  end

  private

  def load_environment
    loader = RBS::EnvironmentLoader.new
    loader.add(path: SIGNATURE_ROOT)
    RBS::Environment.from_loader(loader).resolve_type_names
  end

  def resolve_constant(name)
    name.to_s.delete_prefix("::").split("::").reduce(Object) do |scope, segment|
      assert scope.const_defined?(segment, false), "missing RBS runtime type #{name}"
      scope.const_get(segment, false)
    end
  end

  def verify_member(runtime_type, member)
    case member
    when RBS::AST::Members::MethodDefinition
      assert_method(runtime_type, member.name, member.kind)
    when RBS::AST::Members::AttrReader
      assert_method(runtime_type, member.name, member.kind)
    when RBS::AST::Members::AttrWriter
      assert_method(runtime_type, :"#{member.name}=", member.kind)
    when RBS::AST::Members::AttrAccessor
      assert_method(runtime_type, member.name, member.kind)
      assert_method(runtime_type, :"#{member.name}=", member.kind)
    when RBS::AST::Declarations::Constant
      constant_name = member.name.name
      assert runtime_type.const_defined?(constant_name, false),
             "missing runtime constant #{runtime_type}::#{constant_name}"
    end
  end

  def assert_method(runtime_type, name, kind)
    exists = if kind == :singleton
               runtime_type.respond_to?(name, true)
             else
               runtime_type.public_instance_methods.include?(name) ||
                 runtime_type.protected_instance_methods.include?(name) ||
                 runtime_type.private_instance_methods.include?(name)
             end
    assert exists, "missing #{kind} method #{runtime_type}##{name} declared by RBS"
  end
end
