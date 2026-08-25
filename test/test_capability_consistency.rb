# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../tools/capability_consistency"

# The runtime capability registry, measured against the rest of the project.
#
# Foundation 27 reported fully green while `docs/runtime-capabilities.json` still carried
# `mapping.event-projection` and `mapping.bcl-projection` as active unresolved decisions — beside
# the `managed.*` rows that had resolved them — and `evidence.retained-xna-assemblies` as an
# unavailable upstream input, beside the hash-pinned IL provenance that had admitted it. Several
# rows also asserted that types the strict report marks COMPLETE were absent.
#
# Nothing in the pipeline compared the registry against anything, so nothing caught it. These tests
# do, from measured state rather than from fixed strings, and `tools/generate_capabilities.rb`
# refuses to write the generated document while any contradiction stands.
class CapabilityConsistencyTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  REGISTRY = JSON.parse(ROOT.join("docs", "runtime-capabilities.json").read).freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read).freeze
  PRE_FIX = JSON.parse(
    ROOT.join("test", "fixtures", "capability-registry-foundation-27-prefix.json").read
  ).freeze

  def namespaces
    @namespaces ||= CapabilityConsistency.framework_namespaces(
      types: CapabilityConsistency.projected_types(SIGNATURES)
    )
  end

  def check(registry, il_inventory: IL)
    CapabilityConsistency.check(registry: registry, strict: STRICT, il_inventory: il_inventory,
                                namespaces: namespaces)
  end

  def rows(registry) = registry.fetch("capabilities")
  def row(registry, id) = rows(registry).find { |candidate| candidate.fetch("id") == id }

  # ------------------------------------------------------------------------------- live registry

  def test_the_live_registry_agrees_with_measured_project_state
    findings = check(REGISTRY)
    assert_empty findings.map(&:to_s), "the capability registry contradicts measured project state"
  end

  def test_the_registry_uses_only_categories_the_gate_classifies
    # A new category would otherwise slip past every polarity rule.
    used = rows(REGISTRY).map { |capability| capability.fetch("category") }.uniq.sort
    assert_equal used, (used & CapabilityConsistency::KNOWN_CATEGORIES).sort
    refute_empty used & CapabilityConsistency::RESOLVED_CATEGORIES
  end

  def test_every_capability_row_is_well_formed_and_uniquely_identified
    ids = rows(REGISTRY).map { |capability| capability.fetch("id") }
    assert_equal ids.length, ids.uniq.length
    rows(REGISTRY).each do |capability|
      assert_equal %w[category evidence id status], capability.keys.sort, capability.fetch("id")
      refute_empty capability.fetch("status").to_s, capability.fetch("id")
    end
  end

  # ------------------------------------------------------- the three resolved blockers, by name

  def test_the_retired_mapping_blockers_are_gone_and_their_verified_successors_stand_alone
    %w[event-projection bcl-projection readonly-collection].each do |subject|
      assert_nil row(REGISTRY, "mapping.#{subject}"), "mapping.#{subject} was resolved and must not stand"
      successor = row(REGISTRY, "managed.#{subject}")
      refute_nil successor, subject
      assert_equal "VERIFIED_MANAGED", successor.fetch("category"), subject
    end
    # The category itself is not retired -- the checker classifies it as unresolved precisely so a
    # real undecided mapping can be recorded. What must not come back is any blocker named above.
    # Foundation 29 retired mapping.readonly-collection: Foundation 28 admitted an mscorlib to
    # measure the type against, and the measurement settled the design. One decision legitimately
    # stands, NotSupportedException, which six TouchCollection identities throw.
    undecided = rows(REGISTRY).select do |capability|
      capability.fetch("category") == "UNRESOLVED_MAPPING_DECISION"
    end
    assert_equal %w[mapping.not-supported-exception],
                 undecided.map { |capability| capability.fetch("id") }.sort
  end

  def test_the_retained_assembly_blocker_is_replaced_by_measured_provenance
    assert_nil row(REGISTRY, "evidence.retained-xna-assemblies")
    provenance = row(REGISTRY, "reference.xna-il-provenance")
    refute_nil provenance
    assert_equal "VERIFIED_MANAGED", provenance.fetch("category")
    # The inventory really did admit them, which is what makes the old row false.
    assert_operator IL.fetch("assemblies").length, :>, 0
    assert_operator IL.fetch("TYPES_WITH_IL"), :>, 0

    # The one upstream input that is still genuinely absent kept an identity that says so.
    corpus = row(REGISTRY, "evidence.behavior-corpus-upstream-source")
    refute_nil corpus
    assert_equal "UPSTREAM_INPUT_UNAVAILABLE", corpus.fetch("category")
    assert_includes corpus.fetch("evidence"),
                    "398d0201af0e3c719c152f8659a871cb59710a7dfafc079df6694d453c737855"
  end

  # --------------------------------------------------------------------- generated capability doc

  def test_the_generated_document_matches_the_registry_exactly
    expected = ["# Runtime capabilities", "", "| Capability | Category | Status | Evidence |",
                "| --- | --- | --- | --- |"]
    rows(REGISTRY).each do |capability|
      expected << "| `#{capability["id"]}` | #{capability["category"]} | #{capability["status"]} " \
                  "| #{capability["evidence"] || "—"} |"
    end
    assert_equal expected.join("\n") + "\n",
                 ROOT.join("docs", "generated", "runtime-capabilities.md").read
  end

  def test_the_generated_document_carries_no_retired_blocker_claim
    document = ROOT.join("docs", "generated", "runtime-capabilities.md").read
    ["blocked pending review", "mapping.event-projection", "mapping.bcl-projection",
     "evidence.retained-xna-assemblies"].each do |stale|
      refute_includes document, stale
    end
    # UNRESOLVED_MAPPING_DECISION may appear, but only for a decision that is genuinely open.
    undecided = document.lines.grep(/UNRESOLVED_MAPPING_DECISION/)
    assert_equal 1, undecided.length
    assert_equal %w[mapping.not-supported-exception],
                 undecided.map { |line| line[/`([^`]+)`/, 1] }.sort
    # The one row that legitimately still reports an unavailable input is the corpus source.
    unavailable = document.lines.grep(/not available on this host/)
    assert_equal 1, unavailable.length
    assert_includes unavailable.first, "evidence.behavior-corpus-upstream-source"
  end

  # ------------------------------------------------------------------------- negative controls

  # The registry rows below are byte-identical to the ones committed at Foundation 27, so this is
  # the state that shipped green, not a hand-written approximation of it.
  def test_the_gate_fails_against_the_committed_foundation_27_registry
    findings = check(PRE_FIX)
    refute_empty findings, "the gate must reject the state it was written to catch"
    assert_equal %w[
      ABSENT_COMPLETE_TYPE
      CONTRADICTORY_SUBJECT
      NAMESPACE_COUNT
      PRESENT_NAMESPACE_CLAIMED_ABSENT
      UNAVAILABLE_ADMITTED_INPUT
      UNIMPLEMENTED_WITH_COMPLETE_TYPES
    ], findings.map(&:rule).uniq.sort
  end

  def test_each_historical_defect_is_caught_by_its_own_rule
    {
      "mapping.event-projection" => "CONTRADICTORY_SUBJECT",
      "mapping.bcl-projection" => "CONTRADICTORY_SUBJECT",
      "evidence.retained-xna-assemblies" => "UNAVAILABLE_ADMITTED_INPUT",
      "managed.touch-closure" => "ABSENT_COMPLETE_TYPE",
      "input.touch" => "ABSENT_COMPLETE_TYPE",
      "managed.pure-enum-batch.audio" => "NAMESPACE_COUNT",
      "managed.xna-exception-types" => "PRESENT_NAMESPACE_CLAIMED_ABSENT",
      "audio-media" => "UNIMPLEMENTED_WITH_COMPLETE_TYPES"
    }.each do |id, rule|
      findings = check(PRE_FIX).select { |finding| finding.capability.include?(id) }
      refute_empty findings, id
      assert_includes findings.map(&:rule), rule, id
      # And the corrected row for the same identity is clean, where the identity survived.
      next if row(REGISTRY, id).nil?

      assert_empty check({"capabilities" => [row(REGISTRY, id)]}).map(&:to_s), id
    end
  end

  def test_a_duplicate_identity_is_caught
    duplicated = {"capabilities" => [row(REGISTRY, "managed.event-projection")] * 2}
    assert_includes check(duplicated).map(&:rule), "DUPLICATE_IDENTITY"
  end

  def test_an_unclassified_category_is_caught
    invented = row(REGISTRY, "managed.event-projection").merge("category" => "PROBABLY_FINE")
    assert_includes check({"capabilities" => [invented]}).map(&:rule), "UNKNOWN_CATEGORY"
  end

  def test_the_unavailable_input_rule_only_fires_while_the_inventory_is_admitted
    stale = row(PRE_FIX, "evidence.retained-xna-assemblies")
    registry = {"capabilities" => [stale]}
    assert_includes check(registry).map(&:rule), "UNAVAILABLE_ADMITTED_INPUT"
    # With nothing admitted the same row is simply a true statement, and the rule stays quiet.
    assert_empty check(registry, il_inventory: nil).map(&:rule)
  end

  def test_a_newly_completed_type_reopens_a_namespace_claim
    # Simulates the next milestone: a row that enumerates a namespace it no longer describes.
    understated = row(REGISTRY, "input.touch")
                  .merge("evidence" => "Input.Touch holds TouchLocationState and GestureType only; " \
                                       "everything else remains absent")
    findings = check({"capabilities" => [understated]})
    assert_includes findings.map(&:rule), "UNIMPLEMENTED_WITH_COMPLETE_TYPES"
    assert(findings.any? { |finding| finding.detail.include?("TouchPanelCapabilities") ||
                                     finding.detail.include?("TouchLocation") })
  end
end
