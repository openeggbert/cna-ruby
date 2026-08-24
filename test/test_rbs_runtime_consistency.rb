# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "json"
require "rbs"
require_relative "../lib/cna"

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
