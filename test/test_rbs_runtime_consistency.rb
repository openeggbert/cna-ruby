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

  def test_display_orientation_rbs_retains_exact_four_identity_flags_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.DisplayOrientation"
    end
    refute_nil selected
    assert_equal 4, selected.fetch("members").length
    assert_equal true, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework.rbs"))
    refute_includes source, "untyped"
    refute_match(/\*\w*/, source)
    %w[Default LandscapeLeft LandscapeRight Portrait].each do |name|
      assert_includes source, "#{name}: DisplayOrientation"
    end
    assert_includes source, "def |: (DisplayOrientation other) -> DisplayOrientation"
    assert_includes source, "def &: (DisplayOrientation other) -> DisplayOrientation"
    refute_includes source, "def ToString"
    refute_includes source, "def HasFlag"
  end

  def test_graphics_device_status_rbs_retains_exact_three_identity_non_flags_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDeviceStatus"
    end
    refute_nil selected
    assert_equal 3, selected.fetch("members").length
    assert_equal "enum", selected.fetch("kind")
    assert_equal false, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class GraphicsDeviceStatus\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    %w[Normal Lost NotReset].each do |name|
      assert_includes section, "#{name}: GraphicsDeviceStatus"
    end
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)
    refute_includes section, "def |:"
    refute_includes section, "def &:"
    refute_includes section, "def ToString"
    refute_includes source, "attr_reader GraphicsDeviceStatus:"
    refute_match(/def GraphicsDeviceStatus:/, source)
  end

  def test_graphics_profile_rbs_retains_exact_two_identity_non_flags_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsProfile"
    end
    refute_nil selected
    assert_equal 2, selected.fetch("members").length
    assert_equal "enum", selected.fetch("kind")
    assert_equal false, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class GraphicsProfile\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    %w[Reach HiDef].each do |name|
      assert_includes section, "#{name}: GraphicsProfile"
    end
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)
    refute_includes section, "def |:"
    refute_includes section, "def &:"
    refute_includes section, "def ToString"
    refute_includes source, "attr_reader GraphicsProfile:"
    refute_match(/def GraphicsProfile:/, source)
  end

  def test_clear_options_rbs_retains_exact_three_identity_flags_projection_without_named_zero
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.ClearOptions"
    end
    refute_nil selected
    assert_equal 3, selected.fetch("members").length
    assert_equal "enum", selected.fetch("kind")
    assert_equal true, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")
    assert_equal({"Target" => "1", "DepthBuffer" => "2", "Stencil" => "4"},
                 selected.fetch("members").to_h { |member| [member.fetch("name"), member.fetch("value")] })

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class ClearOptions\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    %w[Target DepthBuffer Stencil].each do |name|
      assert_includes section, "#{name}: ClearOptions"
    end
    %w[None Default Empty All value__].each do |name|
      refute_includes section, "#{name}:"
    end
    assert_includes section, "def |: (ClearOptions other) -> ClearOptions"
    assert_includes section, "def &: (ClearOptions other) -> ClearOptions"
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)
    refute_includes section, "def ToString"
    refute_includes source, "def Clear: (ClearOptions"
    assert_includes source, "def Clear: (Color color) -> nil"
  end

  def test_depth_format_rbs_retains_exact_four_identity_non_flags_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.DepthFormat"
    end
    refute_nil selected
    assert_equal 4, selected.fetch("members").length
    assert_equal "enum", selected.fetch("kind")
    assert_equal false, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")
    assert_equal({"None" => "0", "Depth16" => "1", "Depth24" => "2", "Depth24Stencil8" => "3"},
                 selected.fetch("members").to_h { |member| [member.fetch("name"), member.fetch("value")] })

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class DepthFormat\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    %w[None Depth16 Depth24 Depth24Stencil8].each do |name|
      assert_includes section, "#{name}: DepthFormat"
    end
    declared = section.lines.filter_map { |line| line[/\A\s+(\w+):/, 1] }
    assert_equal %w[None Depth16 Depth24 Depth24Stencil8], declared
    %w[Default Depth32 Stencil8 D24S8 value__].each { |name| refute_includes declared, name }
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)
    refute_includes section, "def |:"
    refute_includes section, "def &:"
    refute_includes section, "def ToString"
    # `PreferredDepthStencilFormat` and `DepthStencilState` were both absent from this file until
    # the milestones that built them. What this test claims about `DepthFormat` is unchanged, and it
    # is now stated on the enum's own declared section, which is where the claim always lived: the
    # enum still declares four identities, no flags operators and no conversion.
    refute_includes section, "PreferredDepthStencilFormat"
    refute_includes section, "DepthStencilState"
  end

  def test_primitive_type_rbs_retains_exact_four_identity_non_flags_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.PrimitiveType"
    end
    refute_nil selected
    assert_equal 4, selected.fetch("members").length
    assert_equal "enum", selected.fetch("kind")
    assert_equal false, selected.fetch("flags")
    assert_equal "System.Int32", selected.fetch("underlyingType")
    assert_equal({"TriangleList" => "0", "TriangleStrip" => "1", "LineList" => "2", "LineStrip" => "3"},
                 selected.fetch("members").to_h { |member| [member.fetch("name"), member.fetch("value")] })

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class PrimitiveType\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    %w[TriangleList TriangleStrip LineList LineStrip].each do |name|
      assert_includes section, "#{name}: PrimitiveType"
    end
    declared = section.lines.filter_map { |line| line[/\A\s+(\w+):/, 1] }
    assert_equal %w[TriangleList TriangleStrip LineList LineStrip], declared
    %w[PointList TriangleFan Default None value__].each { |name| refute_includes declared, name }
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)
    refute_includes section, "def |:"
    refute_includes section, "def &:"
    refute_includes section, "def ToString"
    # `VertexDeclaration` left this list when it was built: it holds no buffer and draws nothing,
    # and its own renderer contact is the assembly-visible Bind/Unbind the contract never selects.
    # What this test claims about `PrimitiveType` is unchanged.
    %w[DrawPrimitives DrawIndexedPrimitives DrawInstancedPrimitives DrawUserPrimitives
       DrawUserIndexedPrimitives VertexBuffer IndexBuffer].each do |name|
      refute_includes source, name
    end
  end

  def test_viewport_rbs_retains_exact_complete_fourteen_identity_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    selected = contract.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.Viewport"
    end
    refute_nil selected
    assert_equal "struct", selected.fetch("kind")
    assert_equal 14, selected.fetch("members").length

    source = File.read(SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs"))
    match = source.match(/^        class Viewport\n(?<body>.*?)^        end$/m)
    refute_nil match
    section = match[:body]
    assert_includes section, "def Project: (Vector3 source, Matrix projection, Matrix view, Matrix world) -> Vector3"
    assert_includes section, "def Unproject: (Vector3 source, Matrix projection, Matrix view, Matrix world) -> Vector3"
    assert_includes section, "attr_reader TitleSafeArea: Rectangle"
    refute_includes section, "attr_accessor TitleSafeArea"
    refute_includes section, "attr_writer TitleSafeArea"
    refute_includes section, "def project"
    refute_includes section, "def unproject"
    refute_includes section, "untyped"
    refute_match(/\*\w*/, section)

    viewport = Microsoft::Xna::Framework::Graphics::Viewport
    assert_equal 4, viewport.instance_method(:Project).arity
    assert_equal 4, viewport.instance_method(:Unproject).arity
    refute viewport.public_method_defined?(:TitleSafeArea=)
    refute viewport.public_method_defined?(:project)
    refute viewport.public_method_defined?(:unproject)
  end

  def test_foundation16_batch_rbs_projects_every_enum_identity_in_pinned_order
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    batch = contract.fetch("types").select do |type|
      type.fetch("kind") == "enum" && FOUNDATION16_BATCH.include?(type.fetch("name"))
    end
    assert_equal FOUNDATION16_BATCH.length, batch.length
    assert_equal 109, batch.sum { |type| type.fetch("members").length }

    sources = {
      "Audio" => SIGNATURE_ROOT.join("microsoft", "xna", "audio.rbs").read,
      "Media" => SIGNATURE_ROOT.join("microsoft", "xna", "media.rbs").read,
      "Graphics" => SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs").read
    }

    batch.each do |type|
      name = type.fetch("name")
      short = name.split(".").last
      namespace = name.split(".")[3]
      source = sources.fetch(namespace)
      match = source.match(/^        class #{short}\n(?<body>.*?)^        end$/m)
      refute_nil match, name
      section = match[:body]

      declared = section.lines.filter_map { |line| line[/\A\s+(\w+): /, 1] }
      assert_equal type.fetch("members").map { |member| member.fetch("name") }, declared, name
      declared.each { |literal| assert_includes section, "#{literal}: #{short}" }
      refute_includes section, "untyped"
      refute_includes section, "value__"
      refute_match(/\*\w*/, section)
      refute_includes section, "def ToString"
      refute_includes section, "def Parse"

      if type.fetch("flags")
        assert_includes section, "def |: (#{short} other) -> #{short}", name
        assert_includes section, "def &: (#{short} other) -> #{short}", name
      else
        refute_includes section, "def |:", name
        refute_includes section, "def &:", name
      end
    end
  end

  def test_foundation18_interface_contracts_rbs_declares_every_projection
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[
      Microsoft.Xna.Framework.IGameComponent
      Microsoft.Xna.Framework.IGraphicsDeviceManager
      Microsoft.Xna.Framework.Graphics.IEffectMatrices
      Microsoft.Xna.Framework.Graphics.IEffectFog
    ]
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 4, selected.length
    assert_equal 11, selected.sum { |type| type.fetch("members").length }
    assert(selected.all? { |type| type.fetch("kind") == "interface" })

    environment = load_environment
    selected.each do |type|
      name = "::#{type.fetch("rubyName")}"
      _key, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == name }
      refute_nil entry, name
      declaration = entry.decls.first.decl
      assert_instance_of RBS::AST::Declarations::Module, declaration, name

      declared = declaration.members.flat_map do |member|
        case member
        when RBS::AST::Members::MethodDefinition then [member.name]
        when RBS::AST::Members::AttrAccessor then [member.name, :"#{member.name}="]
        when RBS::AST::Members::AttrReader then [member.name]
        when RBS::AST::Members::AttrWriter then [:"#{member.name}="]
        else []
        end
      end

      expected = type.fetch("members").flat_map do |member|
        case member.fetch("kind")
        when "method" then [member.fetch("name").to_sym]
        when "property"
          [member.fetch("name").to_sym,
           (member.fetch("set") ? :"#{member.fetch("name")}=" : nil)].compact
        else []
        end
      end
      assert_equal expected.sort, declared.sort, name

      runtime_type = resolve_constant(name)
      assert_instance_of Module, runtime_type
      declared.each { |method| assert runtime_type.method_defined?(method), "#{name}##{method}" }
    end

    source = SIGNATURE_ROOT.join("microsoft", "xna", "interfaces.rbs").read
    refute_includes source, "untyped"
    %w[IEffectLights IEffectSkinning].each do |absent|
      refute_includes source, "module #{absent}\n"
    end
    # Foundation 40 projected IGraphicsDeviceService, so it is no longer on the absent list. It is
    # event-bearing, which is why it is measured by the event-interface test rather than this one.
    assert_includes source, "module IGraphicsDeviceService\n"
  end

  # Foundation 20 — the two event-bearing interfaces. Every CLR event declares exactly one Ruby
  # event reader in RBS, returning the generic subscription primitive; no add_/remove_ pair and no
  # writer is declared anywhere.
  def test_foundation20_event_interfaces_rbs_declares_one_reader_per_event
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[Microsoft.Xna.Framework.IUpdateable Microsoft.Xna.Framework.IDrawable]
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 2, selected.length
    assert_equal 10, selected.sum { |type| type.fetch("members").length }
    assert_equal 4, selected.sum { |type| type.fetch("members").count { |member| member.fetch("kind") == "event" } }

    environment = load_environment
    selected.each do |type|
      name = "::#{type.fetch("rubyName")}"
      _key, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == name }
      refute_nil entry, name
      declaration = entry.decls.first.decl
      assert_instance_of RBS::AST::Declarations::Module, declaration, name

      declared = declaration.members.flat_map do |member|
        case member
        when RBS::AST::Members::MethodDefinition then [member.name]
        when RBS::AST::Members::AttrAccessor then [member.name, :"#{member.name}="]
        when RBS::AST::Members::AttrReader then [member.name]
        when RBS::AST::Members::AttrWriter then [:"#{member.name}="]
        else []
        end
      end

      expected = type.fetch("members").flat_map do |member|
        case member.fetch("kind")
        when "method", "event" then [member.fetch("name").to_sym]
        when "property"
          [member.fetch("name").to_sym,
           (member.fetch("set") ? :"#{member.fetch("name")}=" : nil)].compact
        else []
        end
      end
      assert_equal expected.sort, declared.sort, name

      runtime_type = resolve_constant(name)
      assert_instance_of Module, runtime_type
      declared.each { |method| assert runtime_type.method_defined?(method), "#{name}##{method}" }

      type.fetch("members").select { |member| member.fetch("kind") == "event" }.each do |member|
        identity = member.fetch("name").to_sym
        definition = declaration.members.find do |candidate|
          candidate.is_a?(RBS::AST::Members::MethodDefinition) && candidate.name == identity
        end
        refute_nil definition, "#{name}##{identity}"
        assert_equal "::CNA::Runtime::Event", definition.overloads.first.method_type.type.return_type.to_s
        refute_includes declared, :"#{identity}=", "#{name}##{identity}="
        refute_includes declared, :"add_#{identity}", "#{name}#add_#{identity}"
        refute_includes declared, :"remove_#{identity}", "#{name}#remove_#{identity}"
      end
    end

    runtime = SIGNATURE_ROOT.join("cna", "runtime_event.rbs").read
    assert_includes runtime, "class Event"
    assert_includes runtime, "class EventArgs"
    assert_includes runtime, "Empty: EventArgs"
    %w[emit fire trigger subscribe unsubscribe clear].each do |absent|
      refute_includes runtime, "def #{absent}:", absent
    end
  end

  # Foundation 40 — the graphics-device service contract in RBS. Five members: one read-only
  # property returning the partial GraphicsDevice, and four event readers returning the generic
  # subscription primitive. No setter, no add_/remove_ pair, and nothing untyped.
  def test_foundation40_graphics_device_service_rbs_declares_its_exact_contract
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    name = "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"
    type = contract.fetch("types").find { |candidate| candidate.fetch("name") == name }
    refute_nil type, name
    assert_equal "interface", type.fetch("kind")
    assert_equal 5, type.fetch("members").length
    assert_equal 4, type.fetch("members").count { |member| member.fetch("kind") == "event" }

    environment = load_environment
    ruby_name = "::#{type.fetch("rubyName")}"
    assert_equal "::Microsoft::Xna::Framework::Graphics::IGraphicsDeviceService", ruby_name
    _key, entry = environment.class_decls.find { |candidate, _value| candidate.to_s == ruby_name }
    refute_nil entry, ruby_name
    declaration = entry.decls.first.decl
    assert_instance_of RBS::AST::Declarations::Module, declaration, ruby_name
    assert_empty declaration.self_types, ruby_name

    declared = declaration.members.map do |member|
      assert_instance_of RBS::AST::Members::MethodDefinition, member, ruby_name
      member.name
    end
    assert_equal %i[DeviceCreated DeviceDisposing DeviceReset DeviceResetting GraphicsDevice],
                 declared.sort

    runtime_type = resolve_constant(ruby_name)
    assert_instance_of Module, runtime_type
    declared.each { |method| assert runtime_type.method_defined?(method), "#{ruby_name}##{method}" }

    getter = declaration.members.find { |member| member.name == :GraphicsDevice }
    assert_equal "::Microsoft::Xna::Framework::Graphics::GraphicsDevice",
                 getter.overloads.first.method_type.type.return_type.to_s
    type.fetch("members").select { |member| member.fetch("kind") == "event" }.each do |member|
      identity = member.fetch("name").to_sym
      definition = declaration.members.find { |candidate| candidate.name == identity }
      refute_nil definition, "#{ruby_name}##{identity}"
      assert_equal "::CNA::Runtime::Event", definition.overloads.first.method_type.type.return_type.to_s
      refute_includes declared, :"#{identity}=", "#{ruby_name}##{identity}="
      refute_includes declared, :"add_#{identity}", "#{ruby_name}#add_#{identity}"
      refute_includes declared, :"remove_#{identity}", "#{ruby_name}#remove_#{identity}"
    end
    refute_includes declared, :GraphicsDevice=, "#{ruby_name}#GraphicsDevice="
  end

  def test_foundation17_touch_closure_rbs_matches_the_pinned_contract
    contract = JSON.parse(File.read(Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json")))
    names = %w[TouchLocationState GestureType TouchPanelCapabilities]
             .map { |short| "Microsoft.Xna.Framework.Input.Touch.#{short}" }
    selected = contract.fetch("types").select { |type| names.include?(type.fetch("name")) }
    assert_equal 3, selected.length
    assert_equal 17, selected.sum { |type| type.fetch("members").length }

    source = SIGNATURE_ROOT.join("microsoft", "xna", "touch.rbs").read
    selected.each do |type|
      short = type.fetch("name").split(".").last
      match = source.match(/^          class #{short}\n(?<body>.*?)^          end$/m)
      refute_nil match, short
      section = match[:body]
      refute_includes section, "untyped"

      if type.fetch("kind") == "enum"
        declared = section.lines.filter_map { |line| line[/\A\s+(\w+): /, 1] }
        assert_equal type.fetch("members").map { |member| member.fetch("name") }, declared, short
        if type.fetch("flags")
          assert_includes section, "def |: (#{short} other) -> #{short}"
        else
          refute_includes section, "def |:"
        end
      else
        assert_includes section, "attr_reader IsConnected: bool"
        assert_includes section, "attr_reader MaximumTouchCount: Integer"
        refute_includes section, "attr_accessor"
        refute_includes section, "attr_writer"
        refute_includes section, "def initialize"
      end
    end

    # Foundation 23 added TouchLocation and GestureSample and Foundation 31 the TouchCollection
    # pair. TouchPanel, the one type that would read a touch device, stays out of the signatures
    # entirely; it is a prefix of the selected TouchPanelCapabilities, so absence is asserted per
    # declaration.
    # Foundation 32 added TouchPanel, closing the namespace; nothing in Input.Touch is absent now.
    %w[TouchLocation GestureSample TouchCollection TouchPanel].each do |present|
      assert_includes source, "class #{present}\n"
    end
    # The nested enumerator is declared inside its declaring type, which is how the Ruby nested
    # naming policy spells `TouchCollection+Enumerator`.
    assert_includes source, "            class Enumerator\n"

    environment = load_environment
    declared = environment.class_decls.keys.map(&:to_s)
                          .select { |name| name.start_with?("::Microsoft::Xna::Framework::Input::Touch::") }
    expected = names + %w[Microsoft.Xna.Framework.Input.Touch.TouchLocation
                          Microsoft.Xna.Framework.Input.Touch.GestureSample
                          Microsoft.Xna.Framework.Input.Touch.TouchCollection
                          Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator
                          Microsoft.Xna.Framework.Input.Touch.TouchPanel]
    assert_equal expected.map { |name| "::#{name.split(/[.+]/).join("::")}" }.sort, declared.sort
    declared.each { |name| refute_nil resolve_constant(name) }
  end

  # Foundation 50 added RendererDetail to the same namespace from its own IL: a sealed value type
  # over two strings, which this milestone's enums and exceptions neither imply nor produce.
  def test_foundation16_audio_and_media_signatures_declare_only_selected_enums_and_exceptions
    environment = load_environment
    exceptions = %w[InstancePlayLimitException NoAudioHardwareException NoMicrophoneConnectedException]
    {"::Microsoft::Xna::Framework::Audio" =>
       %w[AudioChannels AudioStopOptions MicrophoneState SoundState RendererDetail] + exceptions,
     "::Microsoft::Xna::Framework::Media" =>
       %w[MediaSourceType MediaState VideoSoundtrackType VisualizationData
          VisualizationData::FloatCollection Video]}.each do |namespace, expected|
      declared = environment.class_decls.keys.map(&:to_s).select { |name| name.start_with?("#{namespace}::") }
      assert_equal expected.map { |name| "#{namespace}::#{name}" }.sort, declared.sort
      declared.each do |name|
        runtime_type = resolve_constant(name)
        short = name.split("::").last
        if exceptions.include?(short)
          assert_operator runtime_type, :<, StandardError, name
        elsif short == "RendererDetail"
          # Foundation 50: a value type, not an enum and not an exception.
          assert_includes runtime_type.ancestors, CNA::Runtime::ValueSemantics, name
        elsif short == "VisualizationData"
          # Foundation 51: an ordinary managed holder, neither enum nor exception.
          assert_equal Object, runtime_type.superclass, name
        elsif short == "Video"
          # Foundation 52: an ordinary managed holder, neither enum nor exception.
          assert_equal Object, runtime_type.superclass, name
        elsif short == "FloatCollection"
          # Its nested ReadOnlyCollection<float>, closed over System.Single.
          assert_operator runtime_type, :<, CNA::Runtime::ReadOnlyCollection, name
        else
          assert_operator runtime_type, :<, CNA::Runtime::EnumValue, name
        end
      end
    end

    # Substring checks would match the selected MicrophoneState literal, so assert on declarations.
    # Video left this list in Foundation 52, projected from its own IL as five ldfld getters.
    %w[SoundEffect Microphone AudioEngine WaveBank SoundBank Cue MediaPlayer MediaLibrary
       Song Album VideoPlayer Playlist].each do |absent|
      %w[audio.rbs media.rbs].each do |file|
        refute_includes SIGNATURE_ROOT.join("microsoft", "xna", file).read, "class #{absent}\n"
      end
    end
  end

  def test_foundation16_batch_adds_no_deferred_renderer_or_device_signature
    source = SIGNATURE_ROOT.join("microsoft", "xna", "framework", "graphics.rbs").read
    # TextureCube is a declared EffectParameterType literal, so absence is asserted per declaration.
    # Foundation 24 added the PresentationParameters managed descriptor; the renderer and device
    # types it names remain absent.
    # The four state objects left this list when they were built; what this batch claimed, and
    # still claims, is that **it** declared none of them -- it declared the eight enums they are
    # made of and nothing that holds one.
    %w[RenderTarget2D RenderTargetCube TextureCube Texture3D VertexBuffer IndexBuffer
       Effect BasicEffect GraphicsAdapter].each do |absent|
      refute_includes source, "class #{absent}\n"
      refute_includes source, "class #{absent} <"
    end
    assert_includes source, "class VertexDeclaration < GraphicsResource"
    %w[BlendState DepthStencilState RasterizerState SamplerState]
      .each { |present| assert_includes source, "class #{present} < GraphicsResource" }
    # Foundation 24 and 25 added these managed descriptors.
    %w[PresentationParameters DisplayMode DisplayModeCollection]
      .each { |present| assert_includes source, "class #{present}\n" }
    %w[ResourceCreatedEventArgs ResourceDestroyedEventArgs]
      .each { |present| assert_includes source, "class #{present} <" }
    %w[SetRenderTarget SetRenderTargets DrawPrimitives DrawIndexedPrimitives GetRenderTargets]
      .each { |absent| refute_includes source, absent }
  end

  private

  FOUNDATION16_BATCH = %w[
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
