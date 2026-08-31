# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 28 — the Microsoft .NET Framework mscorlib admitted as a **separate** BCL authority.
#
# Every BCL identity this binding had projected until now had an empty or scalar surface, so
# "measured" and "obvious" happened to coincide. `ReadOnlyCollection`1` is the first one with a real
# member surface and real behaviour, and the project's rule is that behaviour comes from the exact
# original binary or not at all. That required a third reference authority beside the XNA metadata
# contract and the XNA IL provenance register.
#
# Two properties of that authority are what this test exists to hold:
#
# 1. It is **separate**. mscorlib is not an XNA assembly. Admitting it must not move
#    REFERENCE_TYPES, REFERENCE_MEMBERS or a single number in the XNA IL inventory.
# 2. It is **demand-driven**. A family is admitted only because the XNA reference contract names it.
#    Without that rule the inventory becomes a reimplementation of the .NET Framework.
class BclInventoryTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  INVENTORY = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  PROVENANCE = ROOT.join("tools", "api_compat", "reference", "BCL_PROVENANCE.md").read

  READ_ONLY_COLLECTION = "System.Collections.ObjectModel.ReadOnlyCollection`1"
  COLLECTION = "System.Collections.ObjectModel.Collection`1"
  DICTIONARY = "System.Collections.Generic.Dictionary`2"

  def types = INVENTORY.fetch("types")

  def type(name) = types.fetch(name)

  def member(name, member_name, index: 0)
    type(name).fetch("members").select { |entry| entry.fetch("name") == member_name }.fetch(index)
  end

  # ------------------------------------------------------------------------------ the identity

  def test_the_admitted_assembly_is_microsofts_net_framework_4_mscorlib
    assembly = INVENTORY.fetch("assembly")
    assert_equal "mscorlib", assembly.fetch("assemblyName")
    assert_equal "4.0.0.0", assembly.fetch("assemblyVersion")
    assert_equal "4.0.0.0", assembly.fetch("observedAssemblyVersion")
    assert_equal 5196112, assembly.fetch("bytes")
    assert_equal "5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63", assembly.fetch("sha256")
    assert_equal 64, assembly.fetch("sha256").length
    assert_equal "Microsoft Corporation", assembly.fetch("company")
    assert_equal "Microsoft Common Language Runtime Class Library", assembly.fetch("description")
    assert assembly.fetch("observedFileVersion").start_with?("4.0.30319.1"), assembly.fetch("observedFileVersion")
  end

  # The token is a conclusion drawn from the assembly's own .publickey blob, not a constant the
  # tool trusts. mscorlib carries the ECMA standard key, and that blob is what hashes to this token.
  def test_the_public_key_token_is_derived_rather_than_asserted
    assembly = INVENTORY.fetch("assembly")
    assert_equal "b77a5c561934e089", assembly.fetch("derivedPublicKeyToken")
    assert_equal assembly.fetch("publicKeyToken"), assembly.fetch("derivedPublicKeyToken")
    assert_includes assembly.fetch("publicKeyTokenDerivation"), "SHA-1"

    ecma = ["00000000000000000400000000000000"].pack("H*")
    derived = Digest::SHA1.digest(ecma).bytes.last(8).reverse.map { |byte| format("%02x", byte) }.join
    assert_equal assembly.fetch("derivedPublicKeyToken"), derived
  end

  # What makes this *the* mscorlib rather than *an* mscorlib: every pinned XNA assembly binds to
  # exactly this identity.
  def test_all_ten_pinned_xna_assemblies_bind_this_exact_mscorlib_identity
    pairing = INVENTORY.fetch("pairing").fetch("assemblies")
    assert_equal 10, pairing.length
    assert_equal IL.fetch("assemblies").map { |entry| entry.fetch("name") }.sort,
                 pairing.map { |entry| entry.fetch("assembly") }.sort
    pairing.each do |entry|
      assert_equal INVENTORY.fetch("assembly").fetch("observedAssemblyVersion"),
                   entry.fetch("referencedVersion"), entry.fetch("assembly")
      assert_equal INVENTORY.fetch("assembly").fetch("derivedPublicKeyToken"),
                   entry.fetch("referencedPublicKeyToken"), entry.fetch("assembly")
    end
  end

  def test_the_provenance_register_pins_the_same_identity_and_no_machine_local_path
    assembly = INVENTORY.fetch("assembly")
    assert_includes PROVENANCE, assembly.fetch("sha256")
    assert_includes PROVENANCE, assembly.fetch("derivedPublicKeyToken")
    assert_includes PROVENANCE, assembly.fetch("bytes").to_s
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}, PROVENANCE)
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}i,
                 ROOT.join("docs", "generated", "bcl-inventory.json").read)
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}i,
                 ROOT.join("tools", "api_compat", "build_bcl_inventory.rb").read)
  end

  def test_no_microsoft_binary_is_committed
    tracked = `cd #{ROOT} && git ls-files`.split("\n")
    refute_empty tracked
    assert_empty tracked.grep(/\.(?:dll|exe|pdb|winmd)\z/i)
  end

  # ---------------------------------------------------------------------------- the separation

  def test_admitting_mscorlib_moves_no_xna_metric
    assert_equal 257, STRICT.fetch("REFERENCE_TYPES")
    assert_equal 2964, STRICT.fetch("REFERENCE_MEMBERS")
    assert_equal 257, IL.fetch("REFERENCE_TYPES")
    assert_equal 257, IL.fetch("TYPES_WITH_IL")
    assert_equal 0, IL.fetch("TYPES_WITHOUT_IL")
    assert_equal 10, IL.fetch("assemblies").length
    refute IL.fetch("assemblies").any? { |entry| entry.fetch("name").start_with?("mscorlib") }
    assert_includes INVENTORY.fetch("separateFromXna"), "REFERENCE_TYPES"
  end

  def test_no_bcl_identity_is_an_xna_identity
    xna = REFERENCE.fetch("types").map { |entry| entry.fetch("name") }
    types.each_key do |identity|
      refute_includes xna, identity
      refute identity.start_with?("Microsoft.Xna."), identity
    end
    # And none of them entered the XNA IL inventory either.
    types.each_key { |identity| refute IL.fetch("types").key?(identity), identity }
  end

  def test_the_bcl_metrics_are_reported_separately_and_add_up
    assert_equal 4, INVENTORY.fetch("BCL_FAMILIES")
    assert_equal INVENTORY.fetch("families").length, INVENTORY.fetch("BCL_FAMILIES")
    assert_equal types.length, INVENTORY.fetch("BCL_TYPES")
    assert_equal types.values.sum { |entry| entry.fetch("members").length }, INVENTORY.fetch("BCL_MEMBERS")
    assert_equal types.keys.count { |identity| identity.end_with?("Exception") },
                 INVENTORY.fetch("BCL_EXCEPTION_TYPES")
    assert_operator INVENTORY.fetch("BCL_TYPES"), :>, 0
    assert_operator INVENTORY.fetch("BCL_MEMBERS"), :>, 0
  end

  # --------------------------------------------------------------------------- demand-driven

  def test_every_admitted_family_is_named_by_the_xna_reference_contract
    signatures = REFERENCE.fetch("types").flat_map do |entry|
      values = [entry["baseType"], *entry.fetch("directInterfaces", [])]
      entry.fetch("members").each do |item|
        values.concat([item["type"], item["returnType"]])
        values.concat(item.fetch("parameters", []).map { |parameter| parameter["type"] })
      end
      values.compact
    end

    INVENTORY.fetch("families").each do |family|
      identity = family.fetch("family")
      assert(signatures.any? { |signature| signature.include?(identity) }, identity)
      refute_empty family.fetch("xnaConsumers"), identity
      assert_equal family.fetch("xnaConsumers").length, family.fetch("xnaConsumerCount"), identity
      assert_includes family.fetch("types"), identity
    end
  end

  def test_the_read_only_collection_consumers_are_exactly_the_ten_the_contract_names
    family = INVENTORY.fetch("families").find { |entry| entry.fetch("family") == READ_ONLY_COLLECTION }
    assert_equal %w[
      Microsoft.Xna.Framework.Audio.AudioEngine::RendererDetails
      Microsoft.Xna.Framework.Audio.Microphone::All
      Microsoft.Xna.Framework.Graphics.GraphicsAdapter::Adapters
      Microsoft.Xna.Framework.Graphics.ModelBoneCollection
      Microsoft.Xna.Framework.Graphics.ModelEffectCollection
      Microsoft.Xna.Framework.Graphics.ModelMeshCollection
      Microsoft.Xna.Framework.Graphics.ModelMeshPartCollection
      Microsoft.Xna.Framework.Graphics.SpriteFont::Characters
      Microsoft.Xna.Framework.Media.VisualizationData::Frequencies
      Microsoft.Xna.Framework.Media.VisualizationData::Samples
    ], family.fetch("xnaConsumers").map { |entry| entry.sub(" (base)", "") }

    # Exactly four XNA types take it as their CLR base.
    bases = REFERENCE.fetch("types").select { |entry| entry["baseType"].to_s.start_with?(READ_ONLY_COLLECTION) }
    assert_equal 4, bases.length
    assert_equal family.fetch("xnaConsumers").count { |entry| entry.end_with?("(base)") }, bases.length
  end

  def test_the_dictionary_family_is_here_for_launch_parameters_alone
    family = INVENTORY.fetch("families").find { |entry| entry.fetch("family") == DICTIONARY }
    assert_equal ["Microsoft.Xna.Framework.LaunchParameters (base)"], family.fetch("xnaConsumers")
    assert_equal "System.Collections.Generic.Dictionary`2[System.String,System.String]",
                 REFERENCE.fetch("types").find { |entry|
                   entry.fetch("name") == "Microsoft.Xna.Framework.LaunchParameters"
                 }.fetch("baseType")
  end

  # ------------------------------------------------------ the nested and generic declarations

  # The same extractor defect Native frontier 2 fixed on the XNA side would silently fold a nested
  # type into its parent here. Dictionary`2 proves both halves at once: a generic definition that
  # `ikdasm` declares as ``Name`2<K,V>`` and closes as ``Name`2``, carrying nested types two levels
  # deep, addressed the way the reference contract spells them — Parent+Child, never Parent/Child.
  # `implements` is a comma-separated list, but a constructed generic carries commas of its own:
  # `IDictionary`2<!TKey,!TValue>` is one entry, and splitting naively recorded `!TValue` as an
  # interface of its own.
  def test_a_constructed_generic_interface_is_one_entry_and_not_split_at_its_type_arguments
    dictionary = type(DICTIONARY)
    assert_equal %w[
      System.Collections.Generic.IDictionary`2 System.Collections.Generic.ICollection`1
      System.Collections.Generic.IEnumerable`1 System.Collections.IDictionary
      System.Collections.ICollection System.Collections.IEnumerable
      System.Runtime.Serialization.ISerializable System.Runtime.Serialization.IDeserializationCallback
    ], dictionary.fetch("interfaces")
    types.each do |identity, entry|
      entry.fetch("interfaces").each do |interface|
        refute interface.start_with?("!"), "#{identity}: #{interface}"
        refute_empty interface, identity
      end
      # The declared form keeps its type arguments; the reduced form never does.
      assert_equal entry.fetch("interfaces").length, entry.fetch("interfaceDeclarations").length, identity
    end
  end

  def test_nested_and_generic_declarations_are_discovered_two_levels_deep
    %W[
      #{DICTIONARY}+Enumerator
      #{DICTIONARY}+KeyCollection
      #{DICTIONARY}+KeyCollection+Enumerator
      #{DICTIONARY}+ValueCollection
      #{DICTIONARY}+ValueCollection+Enumerator
    ].each do |identity|
      entry = type(identity)
      refute_empty entry.fetch("members"), identity
      refute_includes identity, "/"
    end

    # A declaring type owns only what it declares. Dictionary`2 has one MoveNext of its own —
    # none — while each of its three enumerators declares its own.
    refute type(DICTIONARY).fetch("members").any? { |entry| entry.fetch("name") == "MoveNext" }
    %W[#{DICTIONARY}+Enumerator #{DICTIONARY}+KeyCollection+Enumerator
       #{DICTIONARY}+ValueCollection+Enumerator].each do |identity|
      assert(type(identity).fetch("members").any? { |entry| entry.fetch("name") == "MoveNext" }, identity)
    end

    assert_equal 1, type(READ_ONLY_COLLECTION).fetch("genericParameters")
    assert_equal 2, type(DICTIONARY).fetch("genericParameters")
  end

  # ------------------------------------------------------------------ the measured behaviour

  # The decisive fact for the Ruby projection: every public read member of ReadOnlyCollection`1
  # forwards to the backing IList<T> it was constructed with. It is a live view, never a snapshot.
  def test_read_only_collection_is_a_view_over_its_backing_list
    entry = type(READ_ONLY_COLLECTION)
    assert_equal "System.Object", entry.fetch("baseType")
    assert_equal %w[
      System.Collections.Generic.IList`1 System.Collections.Generic.ICollection`1
      System.Collections.Generic.IEnumerable`1 System.Collections.IList
      System.Collections.ICollection System.Collections.IEnumerable
    ], entry.fetch("interfaces")

    constructor = member(READ_ONLY_COLLECTION, ".ctor")
    assert_equal ["class System.Collections.Generic.IList`1<!T>"],
                 constructor.fetch("parameters").map { |parameter| parameter.fetch("type") }
    assert constructor.fetch("behaviour").fetch("storesConstructorArgumentToField")
    assert_equal [{"exception" => "System.ArgumentNullException",
                   "via" => "System.ThrowHelper::ThrowArgumentNullException", "argument" => "list"}],
                 constructor.fetch("behaviour").fetch("throws")

    {
      "get_Count" => "System.Collections.Generic.ICollection`1::get_Count",
      "get_Item" => "System.Collections.Generic.IList`1::get_Item",
      "Contains" => "System.Collections.Generic.ICollection`1::Contains",
      "CopyTo" => "System.Collections.Generic.ICollection`1::CopyTo",
      "GetEnumerator" => "System.Collections.Generic.IEnumerable`1::GetEnumerator",
      "IndexOf" => "System.Collections.Generic.IList`1::IndexOf"
    }.each do |name, target|
      behaviour = member(READ_ONLY_COLLECTION, name).fetch("behaviour")
      assert_equal target, behaviour.fetch("delegatesTo"), name
      assert_equal "list", behaviour.fetch("viaField"), name
      refute behaviour.key?("throws"), name
    end
  end

  # None of the six public read members validates anything of its own: bounds behaviour, ordering,
  # equality and enumeration are all the backing list's.
  def test_read_only_collection_adds_no_validation_of_its_own
    %w[get_Count get_Item Contains CopyTo GetEnumerator IndexOf].each do |name|
      refute member(READ_ONLY_COLLECTION, name).fetch("behaviour").key?("throws"), name
    end
  end

  def test_the_public_surface_is_exactly_six_reads_two_properties_an_indexer_and_a_protected_items
    entry = type(READ_ONLY_COLLECTION)
    public_members = entry.fetch("members").select { |item| item.fetch("access") == "public" }
    assert_equal [%w[constructor .ctor], %w[method Contains], %w[method CopyTo],
                  %w[method GetEnumerator], %w[method IndexOf], %w[method get_Count],
                  %w[method get_Item], %w[property Count], %w[property Item]],
                 public_members.map { |item| [item.fetch("kind"), item.fetch("name")] }.sort

    protected_members = entry.fetch("members").select { |item| item.fetch("access") == "family" }
    assert_equal [%w[method get_Items], %w[property Items]],
                 protected_members.map { |item| [item.fetch("kind"), item.fetch("name")] }.sort
  end

  # "Read-only" is a statement about the wrapper's interface, not about the backing list. Every
  # mutating path is an explicit interface implementation whose whole body is a throw.
  def test_every_mutating_path_throws_not_supported_unconditionally
    mutators = type(READ_ONLY_COLLECTION).fetch("members").select do |item|
      item.fetch("behaviour", {}).fetch("throws", []).any? { |throw| throw.fetch("exception") == "System.NotSupportedException" }
    end
    assert_equal %w[
      System.Collections.Generic.ICollection<T>.Add
      System.Collections.Generic.ICollection<T>.Clear
      System.Collections.Generic.ICollection<T>.Remove
      System.Collections.Generic.IList<T>.Insert
      System.Collections.Generic.IList<T>.RemoveAt
      System.Collections.Generic.IList<T>.set_Item
      System.Collections.IList.Add
      System.Collections.IList.Clear
      System.Collections.IList.Insert
      System.Collections.IList.Remove
      System.Collections.IList.RemoveAt
      System.Collections.IList.set_Item
    ], mutators.map { |item| item.fetch("name") }.sort

    mutators.each do |item|
      assert item.fetch("behaviour").fetch("throwsUnconditionally"), item.fetch("name")
      assert item.fetch("explicitInterface"), item.fetch("name")
      assert_equal ["NotSupported_ReadOnlyCollection"],
                   item.fetch("behaviour").fetch("throws").map { |throw| throw["resource"] }.uniq,
                   item.fetch("name")
    end
  end

  # Collection`1 is measured beside it because the contrast is the evidence: the mutable sibling
  # exposes the same reads *publicly* and refuses to mutate only when its own backing list is
  # read-only. Both are views; only one publishes mutation.
  def test_collection_is_the_mutable_sibling_and_is_also_a_view
    entry = type(COLLECTION)
    assert_equal "System.Object", entry.fetch("baseType")
    %w[get_Count get_Item Contains CopyTo GetEnumerator IndexOf].each do |name|
      behaviour = member(COLLECTION, name).fetch("behaviour")
      assert_equal "items", behaviour.fetch("viaField"), name
    end
    %w[Add Clear Insert Remove RemoveAt set_Item].each do |name|
      item = member(COLLECTION, name)
      assert_equal "public", item.fetch("access"), name
      assert(item.fetch("behaviour").fetch("throws").any? { |throw|
        throw.fetch("exception") == "System.NotSupportedException"
      }, name)
      # Conditional: it throws only when the backing IList<T> is itself read-only.
      refute item.fetch("behaviour").key?("throwsUnconditionally"), name
    end
    # The protected mutation hooks forward to the backing list rather than to a copy.
    %w[ClearItems InsertItem RemoveItem SetItem].each do |name|
      assert_equal "family", member(COLLECTION, name).fetch("access"), name
      assert_equal "items", member(COLLECTION, name).fetch("behaviour").fetch("viaField"), name
    end
  end

  # ------------------------------------------------------------------- the exception closure

  def test_the_exception_closure_is_measured_from_what_the_families_throw
    exceptions = types.keys.select { |identity| identity.end_with?("Exception") }.sort
    assert_equal %w[
      System.ArgumentException
      System.ArgumentNullException
      System.ArgumentOutOfRangeException
      System.Collections.Generic.KeyNotFoundException
      System.Exception
      System.InvalidOperationException
      System.NotSupportedException
      System.ObjectDisposedException
      System.Runtime.Serialization.SerializationException
      System.SystemException
    ], exceptions

    thrown = types.values.flat_map { |entry| entry.fetch("members") }
                  .flat_map { |item| item.fetch("behaviour", {}).fetch("throws", []) }
                  .map { |throw| throw.fetch("exception") }.uniq
    refute_empty thrown
    thrown.each { |identity| assert types.key?(identity), identity }
  end

  def test_not_supported_exception_sits_under_system_exception_through_system_exception
    assert_equal "System.SystemException", type("System.NotSupportedException").fetch("baseType")
    assert_equal "System.Exception", type("System.SystemException").fetch("baseType")
    assert_equal "System.Object", type("System.Exception").fetch("baseType")
    # The closure stops at the projection root: System.Exception is where the register already maps.
    assert_equal "StandardError", CNA::Runtime::BclProjection::EXCEPTION_BASES.fetch("System.Exception")

    constructors = type("System.NotSupportedException").fetch("members")
                                                       .select { |item| item.fetch("kind") == "constructor" }
    assert_equal [[], ["string"], ["string", "class System.Exception"],
                  ["class System.Runtime.Serialization.SerializationInfo",
                   "valuetype System.Runtime.Serialization.StreamingContext"]],
                 constructors.map { |item| item.fetch("parameters").map { |parameter| parameter.fetch("type") } }
    assert_equal %w[public public public family], constructors.map { |item| item.fetch("access") }
  end

  # The helper map is derived by reading which exception each ThrowHelper method constructs, so a
  # throw fact never guesses at an exception identity from a method name.
  def test_the_throw_helper_resolution_is_derived
    resolution = INVENTORY.fetch("throwHelperResolution")
    assert_equal "System.NotSupportedException", resolution.fetch("ThrowNotSupportedException")
    assert_equal "System.ArgumentNullException", resolution.fetch("ThrowArgumentNullException")
    assert_equal "System.ArgumentOutOfRangeException", resolution.fetch("ThrowArgumentOutOfRangeException")
    assert_equal "System.ArgumentException", resolution.fetch("ThrowArgumentException")
    assert_equal "System.InvalidOperationException", resolution.fetch("ThrowInvalidOperationException")
    resolution.each do |helper, exception|
      assert helper.include?("Throw"), helper
      assert exception.end_with?("Exception"), exception
    end
  end

  # A two-argument throw helper wraps onto a second line in the disassembly. Reading only the first
  # line loses the ExceptionResource half and mislabels the ExceptionArgument, which is exactly what
  # this fact would have recorded before the extractor folded continuation lines back.
  def test_a_wrapped_two_argument_throw_helper_resolves_both_literals
    copy_to = member(READ_ONLY_COLLECTION, "System.Collections.ICollection.CopyTo")
    out_of_range = copy_to.fetch("behaviour").fetch("throws")
                          .find { |throw| throw.fetch("exception") == "System.ArgumentOutOfRangeException" }
    assert_equal "ArgumentOutOfRange_NeedNonNegNum", out_of_range.fetch("resource")
    assert_equal "arrayIndex", out_of_range.fetch("argument")
  end
end
