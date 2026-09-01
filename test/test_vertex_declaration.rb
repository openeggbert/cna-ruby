# frozen_string_literal: true

require "minitest/autorun"
require "fiddle"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Graphics.VertexDeclaration` — the only dependency-complete candidate that ever carried **two**
# blockers, and the tenth in which the blocker word named a member the pinned contract never
# selects. `NATIVE_RUNTIME` was `Bind`/`Unbind`, both `assembly`; `INTERFACE_PRODUCER_MISSING` was
# `IVertexType::get_VertexDeclaration`, whose only caller is the `assembly` static `FromType`.
# Neither is a projected identity, and the public surface is pure managed arithmetic.
class VertexDeclarationTest < Minitest::Test
  G = Microsoft::Xna::Framework::Graphics
  VD = G::VertexDeclaration
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.VertexDeclaration"

  def element(offset, format, usage, index)
    G::VertexElement.new(offset, G::VertexElementFormat.const_get(format),
                         G::VertexElementUsage.const_get(usage), index)
  end

  # --------------------------------------------------------------- the audit, before the work

  def test_both_blockers_named_members_the_contract_never_selects
    entry = IL.fetch("types").fetch(NAME)
    assert entry.fetch("nativeReachable")
    assert_equal %w[Bind Unbind], entry.fetch("nativeReachableMethods")
    declared = REFERENCE.fetch(NAME).fetch("members").map { |member| member.fetch("name") }
    %w[Bind Unbind FromType].each { |internal| refute_includes declared, internal }
    # The interface half: the IL really does reach IVertexType, and the reference really does not
    # declare a member that could get there.
    assert_includes entry.fetch("externalMemberReferences"),
                    "Microsoft.Xna.Framework.Graphics.IVertexType::get_VertexDeclaration"
    assert_equal %w[.ctor .ctor GetVertexElements Dispose VertexStride].sort, declared.sort
  end

  def test_it_is_complete_and_left_the_frontier
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
    candidates = FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }
    refute_includes candidates, NAME
    # Nothing on the frontier carries the producer blocker any more: this was the only
    # dependency-complete candidate that did.
    refute FRONTIER.fetch("blockerSummary").keys.any? { |key| key.include?("INTERFACE_PRODUCER_MISSING") }
    # And it uncovered the interface itself, which the frontier then **selected** -- only the
    # second time it has ever selected rather than listed.
    # ...and the same milestone projected that interface, which uncovered the four vertex
    # structs in turn -- the first consumable candidates this frontier has carried since
    # Foundation 32.
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.IVertexType"
    # ...and the milestone straight after built all four of them, so the queue is empty again and
    # the interface finally has real producers.
    assert_empty FRONTIER.fetch("consumableCandidates")
    assert_includes STRICT.fetch("completeTypeNames"),
                    "Microsoft.Xna.Framework.Graphics.VertexPositionColor"
  end

  # ---------------------------------------------------------------------- the contract shape

  def test_it_is_a_graphics_resource_with_a_public_constructor_and_no_device
    assert VD < G::GraphicsResource
    declaration = VD.new(element(0, "Vector3", "Position", 0))
    assert_nil declaration.GraphicsDevice, "no device until the assembly-visible Bind supplies one"
    refute declaration.IsDisposed
    assert_nil declaration.instance_variable_get(:@native_handle)
    assert_equal %i[GetVertexElements VertexStride], VD.public_instance_methods(false).sort
    # `Dispose(bool)` is `Unbind(); base.Dispose(disposing)`, and nothing here binds, so the base
    # implementation is the whole of it and is selected rather than reimplemented.
    assert_equal G::GraphicsResource, VD.instance_method(:Dispose).owner
  end

  # `params VertexElement[]` means both call shapes compile in C#, so both are accepted here, and
  # the two overloads collapse on whether the first argument is the stride.
  def test_the_params_array_and_the_two_overloads_collapse_by_arity
    position = element(0, "Vector3", "Position", 0)
    colour = element(12, "Color", "Color", 0)
    assert_equal 16, VD.new(position, colour).VertexStride
    assert_equal 16, VD.new([position, colour]).VertexStride
    assert_equal 32, VD.new(32, position, colour).VertexStride
    assert_equal 32, VD.new(32, [position, colour]).VertexStride
    # The collapse costs nothing: no overload category entry names this type.
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, NAME)
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
  end

  # `if (elements == null || elements.Length == 0) throw new ArgumentNullException(...)` — an
  # **empty** array is an ArgumentNullException, not an ArgumentException, which is the detail a
  # paraphrase loses.
  def test_an_empty_or_missing_element_list_is_the_null_exception
    assert_raises(ArgumentError) { VD.new([]) }
    # A bare nil reaches the element type check rather than the emptiness one, which is Ruby's
    # typing speaking where the CLR would have had a null array.
    assert_raises(TypeError) { VD.new(nil) }
    assert_raises(ArgumentError) { VD.new(4, []) }
    assert_raises(TypeError) { VD.new(element(0, "Single", "Position", 0), "not an element") }
  end

  # Cloned on the way in and on the way out: neither the caller's array nor the one
  # `GetVertexElements` answers is the declaration's own.
  def test_the_elements_are_copied_in_both_directions
    source = [element(0, "Vector3", "Position", 0), element(12, "Color", "Color", 0)]
    declaration = VD.new(source)
    source[0].Offset = 64
    assert_equal 0, declaration.GetVertexElements.first.Offset, "the caller's array is not the declaration's"

    first = declaration.GetVertexElements
    second = declaration.GetVertexElements
    refute_same first, second
    refute_same first.first, second.first
    assert_equal first, second
    first.first.Offset = 64
    assert_equal 0, declaration.GetVertexElements.first.Offset, "and what it hands out is not either"
  end

  # ----------------------------------------------------------- the stride, and its cross-check

  # `GetVertexStride` is a **maximum** of `Offset + GetTypeSize(Format)`, not a sum, so elements may
  # be declared in any order and holes are kept. Every value is asserted against CNA's own
  # `cna_vertex_declaration_create` + `get_stride`, so the arithmetic is measured twice.
  def test_the_stride_is_the_maximum_extent_and_agrees_with_cnas_own
    cases = [
      [[element(0, "Vector3", "Position", 0), element(12, "Color", "Color", 0)], 16],
      [[element(0, "Vector2", "Position", 0)], 8],
      [[element(0, "Vector4", "Position", 0), element(16, "Vector4", "TextureCoordinate", 0)], 32],
      [[element(0, "HalfVector2", "Position", 0), element(4, "Short4", "TextureCoordinate", 1)], 12],
      # Declared out of order, and the later element is the one that sets the stride.
      [[element(16, "Single", "Position", 0), element(0, "Vector4", "Color", 0)], 20],
      # A hole between the two is kept rather than closed.
      [[element(0, "Single", "Position", 0), element(8, "Single", "Color", 0)], 12]
    ]
    cases.each do |elements, expected|
      assert_equal expected, VD.new(elements).VertexStride, elements.map(&:ToString).join(" ")
      next unless ENV["CNA_NATIVE_LIBRARY"]

      assert_equal expected, cna_stride(elements), "CNA computes the same stride"
    end
  end

  # Every one of the twelve declared formats, against CNA's own arithmetic rather than only against
  # the table this binding transcribed from `GetTypeSize`.
  def test_every_format_size_agrees_with_cnas_own
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    VD::FORMAT_SIZES.each_key do |format|
      elements = [element(0, format, "Position", 0)]
      assert_equal VD::FORMAT_SIZES.fetch(format), VD.new(elements).VertexStride, format
      assert_equal VD.new(elements).VertexStride, cna_stride(elements), format
    end
    assert_equal VD::FORMAT_SIZES.keys.sort, G::VertexElementFormat.constants(false).map(&:to_s).sort
    assert_equal 12, VD::FORMAT_SIZES.length
  end

  # ------------------------------------------------------------------------- Validate, in order

  # The four refusals `VertexElementValidator.Validate` can reach from Ruby, each raised at the
  # point the IL raises it. The fifth — a `VertexElementUsage` outside 0..12 — is unreachable here,
  # because the usage is a projected enum and no such value can be constructed.
  def test_each_validation_refusal_in_the_ils_own_order
    assert_raises(RangeError) { VD.new(0, element(0, "Single", "Position", 0)) }
    assert_raises(RangeError) { VD.new(-4, element(0, "Single", "Position", 0)) }

    stride = assert_raises(ArgumentError) { VD.new(6, element(0, "Single", "Position", 0)) }
    assert_includes stride.message, "multiple of four"

    outside = assert_raises(ArgumentError) { VD.new(4, element(2, "Single", "Position", 0)) }
    assert_includes outside.message, "outside the vertex stride"

    duplicate = assert_raises(ArgumentError) do
      VD.new(element(0, "Vector3", "Position", 0), element(12, "Color", "Position", 0))
    end
    assert_includes duplicate.message, "duplicate"

    overlap = assert_raises(ArgumentError) do
      VD.new(element(0, "Vector3", "Position", 0), element(4, "Color", "Color", 0))
    end
    assert_includes overlap.message, "overlap"

    # The offset check really is per element rather than only on the stride, and it comes **after**
    # the outside-stride check -- an offset of 2 in a stride of 8 reaches the multiple-of-four one.
    offset = assert_raises(ArgumentError) { VD.new(8, element(2, "Single", "Position", 0)) }
    assert_includes offset.message, "multiple of four"

    # The usage check the IL opens with -- `usage < 0 || usage > 12` -- is unreachable here: the
    # projected enum declares exactly the thirteen and refuses anything else.
    assert_equal 13, G::VertexElementUsage.constants(false).length
    assert_raises(RangeError) { G::VertexElementUsage.coerce(13) }
    assert_raises(RangeError) { element(0, "Single", "Position", 0).VertexElementUsage = 13 }
  end

  # A declaration whose elements exactly tile the stride is accepted, and so is one with a hole.
  def test_the_accepting_cases
    assert_equal 16, VD.new(element(0, "Vector3", "Position", 0), element(12, "Color", "Color", 0)).VertexStride
    assert_equal 32, VD.new(32, element(0, "Vector3", "Position", 0), element(12, "Color", "Color", 0)).VertexStride
    # The same usage with different usage indices is not a duplicate.
    assert_equal 16, VD.new(element(0, "Vector2", "TextureCoordinate", 0),
                            element(8, "Vector2", "TextureCoordinate", 1)).VertexStride
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_buffer_binding_or_vertex_type_producer
    # `VertexPositionColor` left this list when the four vertex structs were built; what **this**
    # milestone claimed is unchanged, and the buffers and the binding manager are still absent.
    %i[VertexBuffer IndexBuffer DynamicVertexBuffer DeclarationManager]
      .each { |absent| refute G.const_defined?(absent, false), absent.to_s }
    %i[Bind Unbind FromType].each { |absent| refute VD.public_method_defined?(absent), absent.to_s }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # The stride cross-check is what these are for; nothing in `lib/` calls them, and the three
    # routes XNA has no identity for stay unbound.
    %w[cna_vertex_declaration_create_with_stride cna_vertex_declaration_create_empty
       cna_vertex_declaration_copy_type_name cna_vertex_buffer_create].each do |absent|
      refute_includes symbols, absent
    end
  end

  private

  # CNA's own stride for the same elements: create, ask, destroy. It takes no device and no game.
  def cna_stride(elements)
    library = CNA::Native.library
    buffer = Fiddle::Pointer.malloc(16 * elements.length)
    elements.each_with_index do |item, index|
      buffer[index * 16, 16] = [item.Offset, item.VertexElementFormat.to_i,
                                item.VertexElementUsage.to_i, item.UsageIndex].pack("l4")
    end
    output = library.pointer_for("Q", 0)
    library.call("cna_vertex_declaration_create", buffer, elements.length, output)
    handle = output[0, 8].unpack1("Q")
    stride = library.pointer_for("l", 0)
    library.call("cna_vertex_declaration_get_stride", handle, stride)
    library.call("cna_vertex_declaration_destroy", handle)
    stride[0, 4].unpack1("l")
  end
end
