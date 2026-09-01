# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 36 — `System.IDisposable` is a measured structural collapse.
#
# It projects to **no Ruby constant at all**, and the register records that decision so the API
# verifier can assert it still holds. This is the second entry, after `System.IServiceProvider`, and
# the first one with real reach: twenty-nine XNA types declare the interface.
#
# The measurement that settles it is small and complete: the admitted mscorlib says `IDisposable`
# declares exactly one member, `void Dispose()`, and nothing else. Every convention built on top of
# it — `Close`, `IsDisposed`, a finalizer contract, an ownership protocol — is not part of the
# interface, so none of them may be invented here.
#
# What the entry does **not** say is equally measured: mapping the identity is a statement about the
# interface and about nothing else. It does not claim any type's disposal is implemented and it does
# not make a native runtime available.
class DisposableCollapseTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  B = CNA::Runtime::BclProjection
  F = Microsoft::Xna::Framework

  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)

  CLR = "System.IDisposable"

  def implementors
    REFERENCE.fetch("types").select { |type| type.fetch("directInterfaces", []).include?(CLR) }
  end

  # ------------------------------------------------------------------------ the recorded decision

  def test_the_register_records_the_collapse_and_invents_nothing
    assert B.structural_collapse?(CLR)
    assert_equal ["System.Action`1", "System.IDisposable", "System.IServiceProvider"],
                 B::STRUCTURAL_COLLAPSE.keys.sort
    reason = B::STRUCTURAL_COLLAPSE.fetch(CLR)
    assert_includes reason, "Dispose()"
    assert_includes reason, "no Ruby constant"

    # It is an identity, not a projected type and not a thrown exception.
    assert_includes B.identities, CLR
    refute B::TYPES.key?(CLR)
    refute B::EXCEPTION_BASES.key?(CLR)
    refute B::THROWN_EXCEPTIONS.key?(CLR)
    assert_nil B.ruby_type(CLR)
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
  end

  # No constant, anywhere. Not at top level, not in the CNA runtime, not in the XNA namespaces, and
  # no fabricated ::System to hang one from.
  def test_no_constant_was_invented_for_it
    refute Object.const_defined?(:IDisposable, false)
    refute CNA::Runtime.const_defined?(:IDisposable, false)
    refute F.const_defined?(:IDisposable, false)
    refute F::Graphics.const_defined?(:IDisposable, false)
    refute F::Audio.const_defined?(:IDisposable, false)
    refute Object.const_defined?(:System, false)
    refute CNA::Runtime.const_defined?(:Disposable, false)
    refute F.const_defined?(:Disposable, false)
  end

  # And none of the conventions built on top of the interface was invented either. The interface
  # declares one member; these are not it.
  def test_no_close_alias_finalizer_api_or_ownership_wrapper_was_invented
    disposing = SIGNATURES.fetch("types").select do |type|
      type.fetch("members").any? { |member| member.fetch("name") == "Dispose" }
    end
    refute_empty disposing

    # A name counts as invented only when the type's *own* reference contract does not declare it,
    # so the rule stays measured rather than becoming a list of exempt names. `IsDisposed` is a real
    # XNA identity on GraphicsResource and GraphicsDevice, and `Finalize` is one on GameComponent;
    # both are exempted by that rule rather than by being written down here.
    candidates = %i[Close close IsDisposed Finalize finalize dispose! release Release
                    with_disposal using owned? take_ownership]
    disposing.each do |type|
      klass = type.fetch("rubyName").split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      declared = REFERENCE.fetch("types").find { |entry| entry.fetch("name") == type.fetch("name") }
                          .fetch("members").map { |member| member.fetch("name").to_sym }
      # An inherited member is not an invention: `DynamicSoundEffectInstance` declares
      # `Dispose(Boolean)` and inherits `IsDisposed` from `SoundEffectInstance`, which really does
      # declare it. What this test forbids is a member no type in the chain declares.
      inherited = REFERENCE.fetch("types")
                           .select { |entry| klass.ancestors.map(&:to_s).include?(entry.fetch("name").gsub(".", "::")) }
                           .flat_map { |entry| entry.fetch("members").map { |member| member.fetch("name").to_sym } }
      (candidates - declared - inherited).each do |invented|
        refute klass.public_method_defined?(invented), "#{type.fetch("rubyName")}##{invented}"
        refute klass.protected_method_defined?(invented), "#{type.fetch("rubyName")}##{invented}"
      end
    end

    # The two exemptions the rule produces, named so the rule cannot silently widen: `IsDisposed` on
    # the two graphics types and `Finalize` on GameComponent, each declared by its own contract.
    {"Microsoft.Xna.Framework.Graphics.GraphicsResource" => "IsDisposed",
     "Microsoft.Xna.Framework.Graphics.GraphicsDevice" => "IsDisposed",
     "Microsoft.Xna.Framework.GameComponent" => "Finalize"}.each do |name, identity|
      declared = REFERENCE.fetch("types").find { |type| type.fetch("name") == name }
                          .fetch("members").map { |member| member.fetch("name") }
      assert_includes declared, identity, name
    end
  end

  # ------------------------------------------------- why the collapse is the faithful projection

  # The whole interface is one member. Anything else a caller expects of "disposable" is convention.
  def test_the_interface_declares_exactly_one_member
    contracts = REFERENCE.fetch("types").select { |type| type.fetch("name") == CLR }
    assert_empty contracts, "IDisposable is a BCL type, not part of the XNA profile"

    # Every implementing XNA type's own contract carries the member, which is what "the contract
    # survives as those members" means. Twenty-eight declare it publicly.
    public_dispose = implementors.select do |type|
      type.fetch("members").any? do |member|
        member.fetch("name") == "Dispose" && member.fetch("parameters", []).empty? &&
          member["access"] == "public"
      end
    end
    assert_equal 29, implementors.length
    assert_equal 28, public_dispose.length
  end

  # The twenty-ninth is GraphicsDeviceManager, whose IL implements the member as an *explicit*
  # interface implementation -- `.override [mscorlib]System.IDisposable::Dispose` -- so it projects
  # to no member at all, under the same rule ReadOnlyCollection's twelve and Collection's fourteen
  # already follow. That is a loss the collapse records rather than papers over.
  def test_the_one_type_without_a_public_dispose_implements_it_explicitly
    only = implementors.reject do |type|
      type.fetch("members").any? do |member|
        member.fetch("name") == "Dispose" && member.fetch("parameters", []).empty? &&
          member["access"] == "public"
      end
    end
    assert_equal ["Microsoft.Xna.Framework.GraphicsDeviceManager"], only.map { |type| type.fetch("name") }

    manager = only.first
    assert_equal [["protected", ["System.Boolean"]]],
                 manager.fetch("members").select { |member| member.fetch("name") == "Dispose" }
                        .map { |member| [member["access"], member.fetch("parameters").map { |p| p.fetch("type") }] }

    # It is one of the six deferred partial runtime types and Dispose is in its missing list, so
    # nothing is being claimed for it here either way.
    assert_includes STRICT.fetch("partialTypes").keys, manager.fetch("name")
    assert(STRICT.fetch("partialTypes").fetch(manager.fetch("name"))
                 .any? { |entry| entry.include?("::Dispose") })
  end

  # The rule is the one IServiceProvider established, applied to a much larger set.
  def test_it_follows_the_established_structural_collapse_rule
    text = RULES.fetch("bclProjection").fetch("structuralCollapse")
    assert_includes text, "System.IDisposable"
    assert_includes text, "void Dispose()"
    assert_includes text, "no Ruby constant"
    assert_includes text, "does not make a native runtime available"

    # Same shape as the first entry: a one-member interface whose member the implementing type
    # already declares.
    assert_includes B::STRUCTURAL_COLLAPSE.fetch("System.IServiceProvider"), "GetService(Type)"
  end

  # ---------------------------------------------------------------------------- negative controls

  def verify_runtime
    CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true).verify
  end

  def test_the_shipped_register_is_accepted
    assert_equal 0, verify_runtime.counts.fetch("LANGUAGE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("LANGUAGE_MAPPING_MISMATCH")
  end

  def test_mutation_a_fabricated_runtime_module_is_caught
    CNA::Runtime.const_set(:IDisposable, Module.new)
    assert_operator verify_runtime.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0
  ensure
    CNA::Runtime.__send__(:remove_const, :IDisposable)
  end

  def test_mutation_a_fabricated_top_level_module_is_caught
    Object.const_set(:IDisposable, Module.new)
    assert_operator verify_runtime.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0
  ensure
    Object.__send__(:remove_const, :IDisposable)
  end

  def test_mutation_a_fabricated_system_namespace_is_caught
    Object.const_set(:System, Module.new)
    assert_operator verify_runtime.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0
  ensure
    Object.__send__(:remove_const, :System)
  end

  # A module inside the XNA namespaces is caught by the leak walk rather than by the register, which
  # is the other half of the same guarantee.
  def test_mutation_a_fabricated_xna_module_is_caught_as_an_internal_type_leak
    F.const_set(:IDisposable, Module.new)
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
    target = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    result = CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify
    assert_operator result.counts.fetch("INTERNAL_TYPE_LEAK"), :>, 0
  ensure
    F.__send__(:remove_const, :IDisposable)
  end

  # A Close alias on a projected type is an identity the CLR contract does not have, and the leak
  # walk measures it as such -- no allowlist and no name list involved.
  def test_mutation_a_close_alias_on_a_projected_type_is_an_unexpected_member
    target_type = SIGNATURES.fetch("types").find do |type|
      type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsResource"
    end
    klass = target_type.fetch("rubyName").split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
    klass.class_eval { def Close = self.Dispose }

    reference = {"types" => [REFERENCE.fetch("types").find { |type| type.fetch("name") == target_type.fetch("name") }]}
    result = CNAApiCompat::Verifier.new(reference: reference, target: {"types" => [target_type]}, runtime: true).verify
    assert_operator result.counts.fetch("UNEXPECTED_MEMBER"), :>, 0
  ensure
    klass&.__send__(:remove_method, :Close) if klass&.public_method_defined?(:Close)
  end

  # ------------------------------------------------------------------- exactly what it unblocked

  # Two types lose their BCL blocker and both keep NATIVE_RUNTIME, so neither becomes consumable.
  # This is the whole point of separating the two claims.
  def test_it_unblocked_two_types_and_made_neither_consumable
    by_name = FRONTIER.fetch("dependencyCompleteCandidates").to_h { |entry| [entry.fetch("name"), entry] }

    # SoundEffectInstance was the other of the two and has since been built, so only Cue is still
    # on the list to read. That the collapse left both blocked on NATIVE_RUNTIME alone is the claim,
    # and it is now asserted for the one that is still waiting plus the completion of the other.
    # Cue was the last of the two still on the list to read, and the XACT cluster built it. So the
    # claim is now asserted from the other side for both: the collapse left each blocked on
    # NATIVE_RUNTIME alone, and each was later completed by the milestone that resolved that.
    refute(by_name.key?("Microsoft.Xna.Framework.Audio.Cue"))
    %w[Microsoft.Xna.Framework.Audio.Cue
       Microsoft.Xna.Framework.Audio.SoundEffectInstance].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert IL.fetch("types").fetch(name).fetch("nativeReachable"), name
    end

    assert_empty FRONTIER.fetch("consumableCandidates")
    # BCL_PROJECTION was 5 until Foundation 46 projected Dictionary`2 and consumed
    # LaunchParameters, RUNTIME_DATA was 5 until Foundation 48 built GameWindow over the canonical
    # window routes, and BCL_PROJECTION fell to 2 when Foundation 49 projected the
    # SerializationInfo/StreamingContext pair and consumed both exception types that named it.
    # BCL_PROJECTION fell again, to 1, when the Stream projection consumed TitleContainer, and the
    # ContentManager milestone reshaped the rest: ContentManager left, ResourceContentManager and
    # GamerServicesComponent appeared behind it, and the System.Byte[] decision took Microphone's
    # BCL half away.
    # NATIVE_RUNTIME fell from 4 to 3 when Microphone was built, which is the sixth time that
    # blocker turned out not to be one. The XACT engine cluster then emptied
    # NATIVE_RUNTIME+RUNTIME_DATA entirely -- AudioCategory was its only entry -- and the banks and
    # the cue took Cue and WaveBank off too, which left no audio type on the frontier at all.
    assert_equal({"BCL_PROJECTION" => 2, "BCL_PROJECTION+NATIVE_RUNTIME" => 1,
                  "NATIVE_RUNTIME" => 2, "RUNTIME_DATA" => 1},
                 FRONTIER.fetch("blockerSummary"))
    assert_includes FRONTIER.fetch("mappedBclTypes"), CLR
  end

  # ContentManager kept a BCL blocker after this collapse, and the identity it needed was not the
  # only one it named: System.IO.Stream and System.Action`1 both had to be decided before it could
  # be built, and both since were. What survives of the original claim is that *this* collapse did
  # not unblock it, which is now stated by where it ended up rather than by what it was waiting on.
  def test_content_manager_needed_more_than_this_collapse
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |item| item.fetch("name") },
                    "Microsoft.Xna.Framework.Content.ContentManager"
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Content.ContentManager"
    assert_includes FRONTIER.fetch("mappedBclTypes"), CLR
    ["System.IO.Stream", "System.Action`1"].each do |later|
      assert_includes FRONTIER.fetch("mappedBclTypes"), later
    end
  end

  # ---------------------------------------------------------------- and exactly what it does not

  # Native frontier 3 proved SoundEffectInstance and Cue reach XACT. Mapping a BCL interface does
  # not change that, and no audio runtime is started here.
  def test_it_claims_no_native_disposal_and_starts_no_audio_runtime
    # Cue and AudioEngine were named here until the XACT cluster built them, which is the point
    # rather than a loss: mapping IDisposable did not build either, and later milestones did. What
    # this still asserts is that both really do reach XACT, which was the original claim.
    %w[Microsoft.Xna.Framework.Audio.Cue
       Microsoft.Xna.Framework.Audio.AudioEngine].each do |name|
      assert IL.fetch("types").fetch(name).fetch("nativeReachable"), name
      assert_includes STRICT.fetch("completeTypeNames"), name
    end
    # Every audio type exists now, built by later milestones one cluster at a time; what this one
    # claimed, and still claims, is that **it** built none of them. The native census below is what
    # measures that, and it is the assertion that survived every one of those milestones unchanged.

    # No native symbol was added for any of this.
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end

  # The collapse says nothing about whether a given type's disposal works: it maps one interface
  # identity and moves nothing. Game was the standing example -- a partial runtime type whose
  # Dispose(Boolean) the collapse did not supply -- and Foundation 47 later supplied it from its own
  # IL, which is exactly the separation this test exists to state.
  def test_it_completes_no_type_and_moves_no_missing_member
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES"),
                 "Foundation 38 added GameComponent, 40 IGraphicsDeviceService, 46 " \
                 "LaunchParameters, 48 GameWindow"
    # Game *was* the standing example of a partial type this collapse did not complete; the
    # ContentManager projection has since completed it outright, which does not weaken the claim
    # that this collapse moved nothing.
    assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Game")
    assert_equal 3, CNA::Runtime::BclProjection::STRUCTURAL_COLLAPSE.length
  end
end
