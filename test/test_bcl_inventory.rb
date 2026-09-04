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
  DESIGN = JSON.parse(ROOT.join("docs", "generated", "design-converter-inventory.json").read)

  READ_ONLY_COLLECTION = "System.Collections.ObjectModel.ReadOnlyCollection`1"
  COLLECTION = "System.Collections.ObjectModel.Collection`1"
  DICTIONARY = "System.Collections.Generic.Dictionary`2"

  def types = INVENTORY.fetch("types")

  def type(name) = types.fetch(name)

  def member(name, member_name, index: 0)
    type(name).fetch("members").select { |entry| entry.fetch("name") == member_name }.fetch(index)
  end

  # ------------------------------------------------------------------------------ the identity

  # Two authorities, each admitted independently and to the same standard. mscorlib came first, at
  # Foundation 28; System.dll follows at Foundation 105 because the thirteen XNA Design converters
  # reach System.ComponentModel, which mscorlib does not declare.
  EXPECTED_AUTHORITIES = {
    "mscorlib" => {
      "assemblyName" => "mscorlib", "bytes" => 5196112,
      "sha256" => "5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63",
      "company" => "Microsoft Corporation",
      "description" => "Microsoft Common Language Runtime Class Library",
      "referrers" => 10
    },
    "System" => {
      "assemblyName" => "System", "bytes" => 3481928,
      "sha256" => "c3182e40f09a8d3a0167a833dc1ce7c3cb2bfddbd32031d8d3f41481d0467462",
      "company" => "Microsoft Corporation",
      "description" => ".NET Framework",
      "referrers" => 6
    }
  }.freeze

  def authority(name) = INVENTORY.fetch("authorities").fetch(name)

  def test_both_admitted_assemblies_are_microsofts_net_framework_4_binaries
    assert_equal EXPECTED_AUTHORITIES.keys.sort, INVENTORY.fetch("authorities").keys.sort
    assert_equal EXPECTED_AUTHORITIES.length, INVENTORY.fetch("BCL_AUTHORITIES")
    EXPECTED_AUTHORITIES.each do |name, expected|
      record = authority(name)
      assert_equal expected.fetch("assemblyName"), record.fetch("assemblyName"), name
      assert_equal "4.0.0.0", record.fetch("assemblyVersion"), name
      assert_equal "4.0.0.0", record.fetch("observedAssemblyVersion"), name
      assert_equal expected.fetch("bytes"), record.fetch("bytes"), name
      assert_equal expected.fetch("sha256"), record.fetch("sha256"), name
      assert_equal 64, record.fetch("sha256").length, name
      assert_equal expected.fetch("company"), record.fetch("company"), name
      assert_equal expected.fetch("description"), record.fetch("description"), name
      assert record.fetch("observedFileVersion").start_with?("4.0.30319.1"), record.fetch("observedFileVersion")
    end
    # Two different binaries, not the same one admitted twice.
    assert_equal 2, INVENTORY.fetch("authorities").values.map { |record| record.fetch("sha256") }.uniq.length
  end

  # The token is a conclusion drawn from each assembly's own .publickey blob, not a constant the
  # tool trusts. Both carry the ECMA standard key, and that blob is what hashes to this token.
  def test_every_public_key_token_is_derived_rather_than_asserted
    ecma = ["00000000000000000400000000000000"].pack("H*")
    derived = Digest::SHA1.digest(ecma).bytes.last(8).reverse.map { |byte| format("%02x", byte) }.join
    assert_equal "b77a5c561934e089", derived

    EXPECTED_AUTHORITIES.each_key do |name|
      record = authority(name)
      assert_equal "b77a5c561934e089", record.fetch("derivedPublicKeyToken"), name
      assert_equal record.fetch("publicKeyToken"), record.fetch("derivedPublicKeyToken"), name
      assert_includes record.fetch("publicKeyTokenDerivation"), "SHA-1"
      assert_equal record.fetch("derivedPublicKeyToken"), derived, name
    end
  end

  # What makes each of these *the* assembly rather than *an* assembly: the pinned XNA assemblies
  # that reference it bind exactly this identity. Which assemblies those are is measured rather
  # than assumed to be all ten -- four of them declare no reference to System.dll at all, and
  # demanding that they did would be a vacuous proof.
  def test_each_authority_is_paired_against_exactly_the_xna_assemblies_that_reference_it
    xna = IL.fetch("assemblies").map { |entry| entry.fetch("name") }.sort
    EXPECTED_AUTHORITIES.each do |name, expected|
      record = authority(name)
      pairing = record.fetch("pairing")
      assert_equal expected.fetch("referrers"), pairing.fetch("assemblies").length, name
      assert_equal pairing.fetch("xnaReferrers"), pairing.fetch("assemblies").map { |entry| entry.fetch("assembly") }.sort, name
      # Referrers and non-referrers partition the ten pinned assemblies exactly.
      assert_equal xna, (pairing.fetch("xnaReferrers") + pairing.fetch("xnaNonReferrers")).sort, name
      assert_empty pairing.fetch("xnaReferrers") & pairing.fetch("xnaNonReferrers"), name
      refute_empty pairing.fetch("assemblies"), name

      pairing.fetch("assemblies").each do |entry|
        assert_equal record.fetch("observedAssemblyVersion"), entry.fetch("referencedVersion"), entry.fetch("assembly")
        assert_equal record.fetch("derivedPublicKeyToken"), entry.fetch("referencedPublicKeyToken"), entry.fetch("assembly")
      end
    end
    # mscorlib is bound by all ten; System by six. A tool that silently treated one authority's
    # pairing as the other's would make these equal.
    assert_equal 10, authority("mscorlib").fetch("pairing").fetch("assemblies").length
    assert_equal 6, authority("System").fetch("pairing").fetch("assemblies").length
    assert_equal %w[
      Microsoft.Xna.Framework.Avatar.dll Microsoft.Xna.Framework.Input.Touch.dll
      Microsoft.Xna.Framework.Storage.dll Microsoft.Xna.Framework.Video.dll
    ], authority("System").fetch("pairing").fetch("xnaNonReferrers")
    assert_empty authority("mscorlib").fetch("pairing").fetch("xnaNonReferrers")
  end

  def test_the_provenance_register_pins_the_same_identities_and_no_machine_local_path
    EXPECTED_AUTHORITIES.each_key do |name|
      record = authority(name)
      assert_includes PROVENANCE, record.fetch("sha256"), name
      assert_includes PROVENANCE, record.fetch("derivedPublicKeyToken"), name
      assert_includes PROVENANCE, record.fetch("bytes").to_s, name
    end
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}, PROVENANCE)
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}i,
                 ROOT.join("docs", "generated", "bcl-inventory.json").read)
    refute_match(%r{/home/|/rv/|/tmp/|drive_c}i,
                 ROOT.join("tools", "api_compat", "build_bcl_inventory.rb").read)
  end

  # Twelve identities are declared by *both* admitted assemblies, `System.ThrowHelper` among them,
  # and they are different types. Every extracted type therefore records which authority it came
  # from, and the throw-helper resolution tables are per authority rather than merged.
  def test_each_extracted_type_records_the_authority_that_declares_it
    types.each do |identity, record|
      assert_includes EXPECTED_AUTHORITIES.keys, record.fetch("authority"), identity
    end
    assert_equal EXPECTED_AUTHORITIES.keys.sort, INVENTORY.fetch("throwHelperResolution").keys.sort
    refute_empty INVENTORY.fetch("throwHelperResolution").fetch("mscorlib")
    assert_equal types.length, INVENTORY.fetch("BCL_TYPES_BY_AUTHORITY").values.sum
    assert_equal INVENTORY.fetch("BCL_MEMBERS"), INVENTORY.fetch("BCL_MEMBERS_BY_AUTHORITY").values.sum
    assert_equal INVENTORY.fetch("BCL_FAMILIES"), INVENTORY.fetch("BCL_FAMILIES_BY_AUTHORITY").values.sum
    EXPECTED_AUTHORITIES.each_key do |name|
      assert_operator INVENTORY.fetch("BCL_TYPES_BY_AUTHORITY").fetch(name), :>, 0, name
      assert_operator INVENTORY.fetch("BCL_FAMILIES_BY_AUTHORITY").fetch(name), :>, 0, name
    end
    # Every family names an admitted authority, and that authority really declares its types.
    INVENTORY.fetch("families").each do |family|
      assert_includes EXPECTED_AUTHORITIES.keys, family.fetch("authority"), family.fetch("family")
      assert_equal family.fetch("authority"), type(family.fetch("family")).fetch("authority"), family.fetch("family")
    end
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
    refute IL.fetch("assemblies").any? { |entry| entry.fetch("name") == "System.dll" }
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
    # Five when the Stream projection landed; ten once the Storage family added the three IO
    # enums, `IAsyncResult` and the one `WaitHandle` member reachable through it; eleven with
    # `System.IO.BinaryReader`, the CLR base of `Content.ContentReader`; twenty-six once the
    # Design family admitted System.dll -- seven ComponentModel families from the new authority
    # and eight more from mscorlib that the converters reach.
    assert_equal 26, INVENTORY.fetch("BCL_FAMILIES")
    assert_equal({"mscorlib" => 19, "System" => 7}, INVENTORY.fetch("BCL_FAMILIES_BY_AUTHORITY"))
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

    bcl_signatures = INVENTORY.fetch("types").flat_map do |_, record|
      record.fetch("members").flat_map do |item|
        [item["returnType"], item["declaration"], *item.fetch("parameters", []).map { |parameter| parameter["type"] }]
      end
    end.compact

    INVENTORY.fetch("families").each do |family|
      identity = family.fetch("family")
      assert_equal family.fetch("xnaConsumers").length, family.fetch("xnaConsumerCount"), identity
      assert_includes family.fetch("types"), identity

      # Demand is direct when an XNA signature names the family, and transitive when an
      # already-admitted family's *measured* surface does. Both are demand; neither is optional.
      # A family with an empty consumer list of the kind it claims would be scope creep, and the
      # builder aborts on it, so this restates the rule independently rather than trusting it.
      case family.fetch("demand")
      when "direct"
        assert(signatures.any? { |signature| signature.include?(identity) }, identity)
        refute_empty family.fetch("xnaConsumers"), identity
      when "transitive"
        assert_empty family.fetch("xnaConsumers"), identity
        refute(signatures.any? { |signature| signature.include?(identity) },
               "#{identity} claims transitive demand but an XNA signature names it")
        refute_empty family.fetch("bclConsumers"), identity
        family.fetch("bclConsumers").each do |consumer|
          assert_includes INVENTORY.fetch("types"), consumer.split("::").first, consumer
        end
        assert(bcl_signatures.any? { |signature| signature.include?(identity) }, identity)
      when "behavioural"
        # The third demand channel: no signature names it and no admitted BCL member's does, yet
        # the measured XNA behaviour calls it and a consumer observes the result. The evidence is
        # the generated design inventory rather than a claim, so it is checked against that file.
        assert_empty family.fetch("xnaConsumers"), identity
        assert_empty family.fetch("bclConsumers"), identity
        refute(signatures.any? { |signature| signature.include?(identity) },
               "#{identity} claims behavioural demand but an XNA signature names it")
        assert_includes DESIGN.fetch("reachedBclIdentities").keys,
                        "#{family.fetch("designReachAuthority")}:#{identity}", identity
      else
        flunk "#{identity} declares an unknown demand #{family.fetch("demand").inspect}"
      end
    end
  end

  # `System.IO.SeekOrigin` is the first transitively demanded family: no XNA signature names it, and
  # `System.IO.Stream::Seek` does. Its three members are what a consumer of a produced stream needs
  # in order to seek at all, and they are read out of the assembly rather than remembered.
  def test_the_seek_origin_enum_is_measured_and_transitively_demanded
    record = INVENTORY.fetch("types").fetch("System.IO.SeekOrigin")
    assert_equal "enum", record.fetch("kind")
    assert_equal "System.Enum", record.fetch("baseType")
    literals = record.fetch("members").select { |item| item.key?("literal") }
                     .to_h { |item| [item.fetch("name"), item.fetch("literal")] }
    assert_equal({ "Begin" => "int32(0x00000000)", "Current" => "int32(0x00000001)",
                   "End" => "int32(0x00000002)" }, literals)

    family = INVENTORY.fetch("families").find { |entry| entry.fetch("family") == "System.IO.SeekOrigin" }
    assert_equal "transitive", family.fetch("demand")
    assert_equal ["System.IO.Stream::Seek"], family.fetch("bclConsumers")
  end

  # A literal field's name is bounded on the left by its type and on the right by its `=`. Reading
  # the last token of the whole declaration names every enum member after its own value, which is
  # the scanner defect this project has hit before. This is the control for it.
  def test_a_literal_field_is_named_before_its_value_and_not_after_it
    INVENTORY.fetch("types").each do |identity, record|
      record.fetch("members").select { |item| item.fetch("kind") == "field" }.each do |item|
        refute_match(/\Aint\d|\A[a-z]+\(0x/, item.fetch("name"), "#{identity}::#{item.fetch("name")}")
        next unless item.key?("literal")

        assert item.fetch("declaration").include?("#{item.fetch("name")} = #{item.fetch("literal")}"),
               "#{identity}::#{item.fetch("name")}"
      end
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
      System.Globalization.CultureNotFoundException
      System.IO.IOException
      System.InvalidOperationException
      System.NotImplementedException
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
  #
  # It is keyed by authority: both admitted assemblies declare their own `System.ThrowHelper`, and
  # merging them would resolve a System.dll member's throw against mscorlib's class.
  def test_the_throw_helper_resolution_is_derived
    resolution = INVENTORY.fetch("throwHelperResolution").fetch("mscorlib")
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
