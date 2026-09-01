# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"

# The behaviour corpus is two kinds of file, and only one of them is enforced.
#
# `tools/run_behavior_corpus.rb` reads exactly one file -- `behavior/xna40-foundation-values.json`,
# the aggregate -- and replays every observation in it. The per-milestone `*-values.json` files
# beside it are the authoring records: each milestone wrote its own observations there and merged
# them into the aggregate. Nothing measured the relationship between the two, so a per-milestone
# file could disagree with what is actually replayed and no run would say a word.
#
# It had already happened. `member_level_dependency.frontier_effect` carried a duplicated sentence
# in the aggregate that the per-milestone file did not, and the two notes had been diverging since
# Foundation 52. That is a documentation defect rather than a measurement one -- the aggregate is
# what gates -- but a documentation record that silently stops matching what it documents is worth
# exactly nothing, so the relationship is measured here.
class BehaviorCorpusIntegrityTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  AGGREGATE_PATH = ROOT.join("behavior", "xna40-foundation-values.json")
  AGGREGATE = JSON.parse(AGGREGATE_PATH.read).freeze
  BY_ID = AGGREGATE.fetch("observations").to_h { |item| [item.fetch("id"), item] }.freeze

  MILESTONE_FILES = ROOT.glob("behavior/*.json").reject { |path| path == AGGREGATE_PATH }.sort.freeze

  # Seven rows whose **shape** changed after their own milestone merged them, so the per-milestone
  # file holds the expectation as it was written and the aggregate holds the one that is replayed.
  # Each is a real supersession rather than a mistake, and each is named with what moved. The
  # register is closed: an eighth entry is a new drift and fails.
  SUPERSEDED = {
    "bcl_projection.register" => "the register row dropped its middle element",
    "content_attribute.register" => "the register row dropped its middle element",
    "bcl_projection.register_time_span" => "the register row dropped its middle element",
    "event_projection.support_type.contract" => "the row was rewritten to carry its subjects in args",
    "event_projection.deferred_family.contract" => "each family tuple dropped its trailing flag",
    "touch_closure.touch_panel_capabilities.default_value" => "the row dropped a trailing element",
    "il_provenance.assemblies" => "native-reachable reference types moved 61 -> 77 in Native frontier 3"
  }.freeze

  def milestone_observations
    MILESTONE_FILES.flat_map do |path|
      JSON.parse(path.read).fetch("observations").map { |item| [path.basename.to_s, item] }
    end
  end

  def test_the_aggregate_is_what_the_runner_replays_and_has_no_duplicate_ids
    assert_equal AGGREGATE.fetch("observations").length, BY_ID.length, "duplicate observation id"
    assert_equal "MIXED_WITH_OBSERVATION_PROVENANCE", AGGREGATE.fetch("category")
    assert_equal 526, AGGREGATE.fetch("observations").length
    assert_includes AGGREGATE_PATH.read, "never CNA output"
  end

  def test_every_milestone_observation_reaches_the_aggregate
    milestone_observations.each do |file, item|
      assert_includes BY_ID, item.fetch("id"), "#{file} carries #{item.fetch("id")}, which is never replayed"
    end
  end

  # The point of the whole file: a per-milestone record that disagrees with the replayed one is
  # either a named supersession or a defect, and there is no third case.
  def test_the_only_disagreements_are_the_named_supersessions
    drifted = milestone_observations.reject { |_file, item| BY_ID.fetch(item.fetch("id")) == item }
                                    .map { |_file, item| item.fetch("id") }.sort
    assert_equal SUPERSEDED.keys.sort, drifted
  end

  # And the supersessions are supersessions of the *expectation*, never of what the row is about.
  def test_a_superseded_row_still_describes_the_same_observation
    milestone_observations.each do |_file, item|
      next unless SUPERSEDED.key?(item.fetch("id"))

      replayed = BY_ID.fetch(item.fetch("id"))
      assert_equal item.fetch("operation"), replayed.fetch("operation"), item.fetch("id")
      assert_equal item.fetch("provenance"), replayed.fetch("provenance"), item.fetch("id")
    end
  end

  # The boundary this repository will not cross, asserted on the file that gates rather than on
  # prose: no observation may be sourced from CNA.
  def test_no_observation_claims_cna_provenance
    # 253 of the observations carry no key at all: they are the imported originals, and the runner
    # defaults them to PURE_XNA_DERIVED, which is the only default it has. So the assertion is on
    # the defaulted value, exactly as the generated report counts it.
    counts = AGGREGATE.fetch("observations")
                      .group_by { |item| item.fetch("provenance", "PURE_XNA_DERIVED") }
                      .transform_values(&:length)
    assert_equal({"PURE_XNA_DERIVED" => 390, "RUBY_MAPPING_QUALIFICATION" => 136}, counts)
    refute_includes AGGREGATE.fetch("observations").map { |item| item["provenance"] },
                    "CNA_NATIVE_INTEGRATION"
  end
end
