# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The four XNA 4.0 vertex structs — the first types in this binding that **conform** to a projected
# interface rather than merely declaring one, and the first candidates the dependency frontier has
# ranked as consumable since Foundation 32. `SELECTED_NEXT` named `VertexPositionColor`; this is
# that selection acted on, and its three siblings with it.
class VertexStructsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze

  TYPES = {
    G::VertexPositionColor => %i[Position Color],
    G::VertexPositionTexture => %i[Position TextureCoordinate],
    G::VertexPositionColorTexture => %i[Position Color TextureCoordinate],
    G::VertexPositionNormalTexture => %i[Position Normal TextureCoordinate]
  }.freeze

  def clr(type) = "Microsoft.Xna.Framework.Graphics.#{type.name.split("::").last}"

  # ------------------------------------------------------------------ the contract, from metadata

  def test_all_four_are_complete_and_the_queue_they_were_selected_from_is_empty_again
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    TYPES.each_key do |type|
      assert_includes STRICT.fetch("completeTypeNames"), clr(type)
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(clr(type))
    end
    assert_empty FRONTIER.fetch("consumableCandidates"), "the queue was consumed rather than grown"
    assert_equal "none-consumable", FRONTIER.fetch("selectionRoute")
    # 4 until Media.VideoPlayer's blocker was audited in the milestone after this one, 3 until the
    # Effect cluster uncovered EffectMaterial and DirectionalLight behind the Effect base. What this
    # test claims -- that the queue these four came from was consumed -- is unchanged.
    assert_equal 4, FRONTIER.fetch("dependencyCompleteCandidates").length
  end

  def test_each_is_a_value_type_declaring_the_interface_with_the_same_six_member_shape
    TYPES.each do |type, fields|
      contract = REFERENCE.fetch(clr(type))
      assert_equal "struct", contract.fetch("kind"), clr(type)
      assert_equal ["Microsoft.Xna.Framework.Graphics.IVertexType"], contract.fetch("interfaces"), clr(type)
      kinds = contract.fetch("members").group_by { |member| member.fetch("kind") }
      assert_equal 1, kinds.fetch("constructor").length, clr(type)
      assert_equal %w[GetHashCode ToString op_Equality op_Inequality Equals].sort,
                   kinds.fetch("method").map { |member| member.fetch("name") }.sort, clr(type)
      instance_fields = kinds.fetch("field").reject { |member| member.fetch("static") }
      assert_equal fields.map(&:to_s), instance_fields.map { |member| member.fetch("name") }, clr(type)
      static_fields = kinds.fetch("field").select { |member| member.fetch("static") }
      assert_equal %w[VertexDeclaration], static_fields.map { |member| member.fetch("name") }, clr(type)
    end
  end

  # ------------------------------------------------- the producer, which is the point of the four

  # Foundation 40's rule, from the other side at last: an interface has a producer when some type
  # declares it in the pinned contract, is complete here, **and** whose live Ruby class really
  # includes the projected module. All three halves hold for all four, so `IVertexType` is the
  # first interface this binding has ever provided.
  def test_they_are_the_first_real_producers_of_a_projected_interface
    TYPES.each_key do |type|
      assert_includes type.ancestors, G::IVertexType, clr(type)
      assert type.new.is_a?(G::IVertexType), clr(type)
    end
    # And the rule still refuses the interface it has always refused, so nothing was loosened.
    producerless = (FRONTIER.fetch("dependencyCompleteCandidates") +
                    FRONTIER.fetch("partialDependencySatisfiedCandidates") +
                    FRONTIER.fetch("ilOnlyBlockedCandidates"))
                   .flat_map { |entry| entry.fetch("producerlessInterfaces") }.uniq
    assert_equal ["Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"], producerless
  end

  # XNA implements `IVertexType.VertexDeclaration` **explicitly**: the metadata says
  # `private hidebysig newslot specialname virtual final`, so `v.VertexDeclaration` does not compile
  # on the concrete type in C# either. The Ruby analogue is a private instance method, and the
  # public name of the same spelling is the static field. Both halves are asserted.
  def test_the_interface_member_is_private_and_the_static_field_is_not
    TYPES.each_key do |type|
      value = type.new
      refute type.public_method_defined?(:VertexDeclaration), clr(type)
      assert type.private_method_defined?(:VertexDeclaration), clr(type)
      assert_raises(NoMethodError) { value.VertexDeclaration }
      assert_same type.const_get(:VertexDeclaration), value.__send__(:VertexDeclaration), clr(type)
      # The static field is a constant, which is what a `static initonly` field projects to.
      assert_instance_of G::VertexDeclaration, type.const_get(:VertexDeclaration), clr(type)
    end
  end

  # ------------------------------------------------------------- the declarations, from the cctor

  def test_each_static_declaration_is_the_ils_own_elements_stride_and_name
    expected = {
      G::VertexPositionColor => [16, "VertexPositionColor.VertexDeclaration",
                                 [[0, "Vector3", "Position", 0], [12, "Color", "Color", 0]]],
      G::VertexPositionTexture => [20, "VertexPositionTexture.VertexDeclaration",
                                   [[0, "Vector3", "Position", 0],
                                    [12, "Vector2", "TextureCoordinate", 0]]],
      G::VertexPositionColorTexture => [24, "VertexPositionColorTexture.VertexDeclaration",
                                        [[0, "Vector3", "Position", 0], [12, "Color", "Color", 0],
                                         [16, "Vector2", "TextureCoordinate", 0]]],
      G::VertexPositionNormalTexture => [32, "VertexPositionNormalTexture.VertexDeclaration",
                                         [[0, "Vector3", "Position", 0],
                                          [12, "Vector3", "Normal", 0],
                                          [24, "Vector2", "TextureCoordinate", 0]]]
    }
    expected.each do |type, (stride, name, elements)|
      declaration = type.const_get(:VertexDeclaration)
      assert_equal stride, declaration.VertexStride, clr(type)
      assert_equal name, declaration.Name, clr(type)
      assert_equal elements,
                   declaration.GetVertexElements.map { |element|
                     [element.Offset, element.VertexElementFormat.to_s,
                      element.VertexElementUsage.to_s, element.UsageIndex]
                   }, clr(type)
      # It is `static initonly`: the same object every time, and the stride is the one the
      # declaration's own arithmetic computed rather than a number written down here twice.
      assert_same declaration, type.const_get(:VertexDeclaration)
      assert_nil declaration.GraphicsDevice
    end
  end

  # ------------------------------------------------------------------------------ value semantics

  def test_the_constructor_stores_and_copies_every_field
    position = F::Vector3.new(1, 2, 3)
    colour = F::Color.new(10, 20, 30, 40)
    vertex = G::VertexPositionColor.new(position, colour)
    assert_equal position, vertex.Position
    assert_equal colour, vertex.Color
    refute_same position, vertex.Position
    position.X = 99
    assert_equal 1, vertex.Position.X, "the caller's Vector3 is not the vertex's"

    normal = G::VertexPositionNormalTexture.new(F::Vector3.new(1, 0, 0), F::Vector3.new(0, 1, 0),
                                                F::Vector2.new(0.25, 0.75))
    assert_equal [1.0, 0.0, 0.0], [normal.Position.X, normal.Position.Y, normal.Position.Z]
    assert_equal [0.0, 1.0, 0.0], [normal.Normal.X, normal.Normal.Y, normal.Normal.Z]
    assert_equal [0.25, 0.75], [normal.TextureCoordinate.X, normal.TextureCoordinate.Y]
  end

  def test_the_fields_are_public_and_mutable_and_refuse_a_wrong_type
    vertex = G::VertexPositionColorTexture.new
    vertex.Position = F::Vector3.new(4, 5, 6)
    vertex.Color = F::Color.new(1, 2, 3, 4)
    vertex.TextureCoordinate = F::Vector2.new(7, 8)
    assert_equal 4.0, vertex.Position.X
    assert_equal 1, vertex.Color.R
    assert_equal 7.0, vertex.TextureCoordinate.X
    assert_raises(TypeError) { vertex.Position = F::Vector2.new(1, 2) }
    assert_raises(TypeError) { vertex.Color = 0 }
    assert_raises(TypeError) { vertex.TextureCoordinate = F::Vector3.new }
  end

  # `op_Equality` compares every field; `Equals(object)` is `obj != null && obj.GetType() ==
  # GetType() && this == (T)obj`, so an unrelated type and a *different* vertex struct with the
  # same values are both false.
  def test_equality_is_field_wise_and_exact_typed
    left = G::VertexPositionColor.new(F::Vector3.new(1, 2, 3), F::Color.new(4, 5, 6, 7))
    right = G::VertexPositionColor.new(F::Vector3.new(1, 2, 3), F::Color.new(4, 5, 6, 7))
    other = G::VertexPositionColor.new(F::Vector3.new(1, 2, 3), F::Color.new(4, 5, 6, 8))
    assert_equal left, right
    assert left.Equals(right)
    refute left.Equals(other)
    assert left != other
    refute left != right
    refute left.Equals(nil)
    refute left.Equals("VertexPositionColor")
    refute left.Equals(G::VertexPositionTexture.new)
    assert_equal left.GetHashCode, right.GetHashCode
  end

  def test_dup_and_clone_build_independent_values
    TYPES.each do |type, fields|
      original = type.new
      copy = original.dup
      refute_same original, copy
      assert_equal original, copy
      fields.each { |field| refute_same original.public_send(field), copy.public_send(field) }
      assert_equal original, original.clone
    end
  end

  # ------------------------------------------------------------------------------- GetHashCode

  # `Helpers.SmartGetHashCode` over the sequential layout: XOR every complete 32-bit word, and
  # substitute Int32.MaxValue for zero. The all-default value of every one of the four is the zero
  # case, which is why they all answer the same number.
  def test_the_hash_is_the_xor_of_the_layouts_words_with_the_zero_substitution
    TYPES.each_key do |type|
      assert_equal 2_147_483_647, type.new.GetHashCode, clr(type)
    end

    numeric = CNA::Runtime::Numeric
    vertex = G::VertexPositionColor.new(F::Vector3.new(1, 2, 3), F::Color.new(10, 20, 30, 40))
    words = [numeric.f32_bits(1.0), numeric.f32_bits(2.0), numeric.f32_bits(3.0),
             vertex.Color.PackedValue]
    assert_equal numeric.wrap_int32(words.reduce(:^)), vertex.GetHashCode

    textured = G::VertexPositionNormalTexture.new(F::Vector3.new(1, 0, 0), F::Vector3.new(0, 1, 0),
                                                  F::Vector2.new(0.5, 0.25))
    words = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.5, 0.25].map { |value| numeric.f32_bits(value) }
    assert_equal numeric.wrap_int32(words.reduce(:^)), textured.GetHashCode

    # Ruby's `hash` follows GetHashCode, so two equal vertices land in the same Hash bucket.
    assert_equal({ vertex => :ok }[G::VertexPositionColor.new(F::Vector3.new(1, 2, 3),
                                                              F::Color.new(10, 20, 30, 40))], :ok)
  end

  def test_to_string_is_the_ils_own_format
    assert_equal "{Position:{X:1 Y:2 Z:3} Color:{R:10 G:20 B:30 A:40}}",
                 G::VertexPositionColor.new(F::Vector3.new(1, 2, 3), F::Color.new(10, 20, 30, 40)).ToString
    assert_equal "{Position:{X:0 Y:0 Z:0} TextureCoordinate:{X:0 Y:0}}",
                 G::VertexPositionTexture.new.ToString
    assert_includes G::VertexPositionColorTexture.new.ToString, "Color:"
    assert_includes G::VertexPositionNormalTexture.new.ToString, "Normal:"
    TYPES.each_key { |type| assert_equal type.new.ToString, type.new.to_s, clr(type) }
  end

  # ------------------------------------------------------------------- and exactly what they do not

  def test_they_add_no_buffer_effect_or_draw_surface
    # The nine `Effect` types left this list when the cluster was built; what this milestone
    # claimed, and still claims, is that **it** built none of them.
    %i[VertexBuffer IndexBuffer DynamicVertexBuffer BasicEffect VertexPositionNormalColorTexture].each do |absent|
      refute G.const_defined?(absent, false), absent.to_s
    end
    %i[SetVertexBuffer Indices DrawUserPrimitives DrawPrimitives].each do |absent|
      refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s
    end
    # The helper module is in CNA::Runtime, not the XNA namespace, which the verifier measures as
    # INTERNAL_TYPE_LEAK and which this binding has got wrong before.
    refute G.const_defined?(:VertexStruct, false)
    assert CNA::Runtime.const_defined?(:VertexStruct, false)
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
