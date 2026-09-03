# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "pathname"
require_relative "reviewed_measurements"

# The qualification report, and the guard it did not have.
#
# `docs/generated/qualification-report.json` was **hand-authored** for the Foundations 34-39 session
# and never regenerated. Sixty milestones later it still described a 141-type surface, a 0.7.0 ABI,
# six partial types and that session's own commit list, in the directory where every other file is
# produced by a tool. Nothing produced it, nothing read it and nothing compared it to anything,
# which is exactly the shape of staleness `plan.md`'s prose had and the dependency frontier had.
#
# It is kept as `docs/qualification-foundations-34-39.json`, unchanged and out of `generated/`,
# because it is a truthful record of a real run that other documents cite. What is generated now
# comes from `tools/run_qualification.rb`, and every field of it that duplicates another report is
# compared against that report here. The parts no other report holds — the suite totals on each
# qualified artifact, the artifact hashes, the toolchain — are checked for shape and for the one
# property that matters: nothing failed that this project has not explained.
class QualificationReportTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  REPORT = JSON.parse(ROOT.join("docs", "generated", "qualification-report.json").read).freeze
  HISTORICAL_PATH = ROOT.join("docs", "qualification-foundations-34-39.json")

  # `tools/run_qualification.rb` runs this very suite once per qualified artifact to measure it, and
  # the report those runs are measuring for does not exist yet. Inside them this guard would be
  # comparing the *previous* milestone's report against the current one's inputs and failing every
  # artifact, so the tool sets `CNA_QUALIFICATION_RUN` and the guard stands down. Every ordinary
  # `rake test` -- including the one a milestone finishes with -- runs it.
  def setup
    return if ENV["CNA_QUALIFICATION_RUN"].to_s.empty?

    skip "inside tools/run_qualification.rb, which is measuring the run this report describes"
  end

  def report(name) = JSON.parse(ROOT.join("docs", "generated", name).read)

  def registry = JSON.parse(ROOT.join("docs", "runtime-capabilities.json").read)

  def test_it_is_generated_and_says_so
    assert_equal 2, REPORT.fetch("schemaVersion")
    assert_equal "tools/run_qualification.rb", REPORT.fetch("generatedBy")
    assert_equal "docs/qualification-foundations-34-39.json", REPORT.fetch("historicalRecord")
    assert_equal registry.fetch("milestone"), REPORT.fetch("milestone")
    assert_match(/\A\d{4}-\d{2}-\d{2}\z/, REPORT.fetch("date"))
  end

  # The historical record stays what it was: a record, not a claim about now.
  def test_the_hand_authored_record_is_kept_out_of_the_generated_directory
    assert_path_exists HISTORICAL_PATH
    refute_path_exists ROOT.join("docs", "generated", "qualification-foundations-34-39.json")
    historical = JSON.parse(HISTORICAL_PATH.read)
    assert_equal "Foundations 34-39", historical.fetch("milestone")
    assert_equal 1, historical.fetch("schemaVersion")
    # And it is genuinely a different measurement, so nothing can mistake one for the other.
    refute_equal REPORT.fetch("strict").fetch("TARGET_TYPES"),
                 historical.fetch("strict").fetch("TARGET_TYPES")
  end

  # ------------------------------------------------------------------ the duplicated blocks

  def test_the_strict_block_is_the_strict_report
    strict = report("api-compat-report.json")
    expected = strict.select { |_key, value| value.is_a?(Integer) }.sort.to_h
    assert_equal expected, REPORT.fetch("strict")
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, REPORT.fetch("strict").fetch("COMPLETE_TYPES")
  end

  def test_the_partial_remainder_is_the_strict_reports
    strict = report("api-compat-report.json")
    assert_equal({ "count" => strict.fetch("PARTIAL_TYPES"), "outstanding" => strict.fetch("partialTypes") },
                 REPORT.fetch("remainingPartialTypes"))
  end

  def test_the_native_abi_block_is_the_abi_report
    abi = report("native-abi-report.json").reject { |key, _| key == "mismatches" }
    assert_equal abi, REPORT.fetch("nativeAbi")
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), REPORT.fetch("nativeAbi").fetch("BOUND_FUNCTIONS")
    assert_equal 0, REPORT.fetch("nativeAbi").fetch("ABI_MISMATCHES")
  end

  def test_the_behaviour_block_is_the_corpus_report
    corpus = report("behavior-corpus-report.json")
    assert_equal corpus.fetch("OBSERVATIONS"), REPORT.fetch("behavior").fetch("OBSERVATIONS")
    assert_equal corpus.fetch("ASSERTIONS"), REPORT.fetch("behavior").fetch("ASSERTIONS")
    assert_equal corpus.fetch("provenanceCounts"), REPORT.fetch("behavior").fetch("provenanceCounts")
    assert_equal 0, REPORT.fetch("behavior").fetch("FAILURES")
  end

  def test_the_frontier_block_is_the_frontier_report
    frontier = report("public-signature-dependency-report.json")
    assert_equal frontier.fetch("dependencyCompleteCandidates").length,
                 REPORT.fetch("dependencyFrontier").fetch("dependencyCompleteCandidates")
    assert_equal frontier.fetch("consumableCandidates").length,
                 REPORT.fetch("dependencyFrontier").fetch("consumableCandidates")
    assert_equal frontier.fetch("selectionRoute"), REPORT.fetch("dependencyFrontier").fetch("selectionRoute")
    assert_equal frontier.fetch("selectedNext"), REPORT.fetch("dependencyFrontier").fetch("selectedNext")
  end

  def test_the_provenance_and_capability_blocks_are_their_reports
    provenance = report("xna-il-inventory.json")
    %w[REFERENCE_TYPES TYPES_WITH_IL TYPES_NATIVE_REACHABLE].each do |key|
      assert_equal provenance.fetch(key), REPORT.fetch("ilProvenance").fetch(key), key
    end
    assert_equal registry.fetch("capabilities").length, REPORT.fetch("capabilities").fetch("CAPABILITIES")
    assert_equal 0, REPORT.fetch("capabilities").fetch("CAPABILITY_CONTRADICTIONS")
  end

  # ------------------------------------------------------------------ the artifacts

  # The three qualified artifacts, each still on disk and still the bytes that were qualified.
  def test_every_qualified_artifact_is_the_one_that_was_measured
    ids = REPORT.fetch("artifacts").map { |artifact| artifact.fetch("id") }
    assert_equal %w[HEADLESS OPENGL33 OPENGLES3_FX], ids
    REPORT.fetch("artifacts").each do |artifact|
      path = Pathname(artifact.fetch("library"))
      next skip("#{artifact.fetch("id")} artifact is not on this host") unless path.exist?

      assert_equal artifact.fetch("librarySha256"), Digest::SHA256.file(path.to_s).hexdigest,
                   artifact.fetch("id")
    end
  end

  # The whole point of running the suite three times: the same tests, and nothing unexplained.
  #
  # `unexplained` is the assertion that matters and it is exact — every problem block the run
  # produced that does not carry the X-acquisition signature is in it, `Failure` blocks included,
  # so a real regression on a windowed artifact cannot be absorbed by the environment's flake.
  def test_the_same_suite_runs_on_all_three_and_nothing_is_unexplained
    runs = REPORT.fetch("artifacts").map { |artifact| artifact.fetch("suite").fetch("runs") }
    assert_equal 1, runs.uniq.length, "the three artifacts must run the same suite"
    REPORT.fetch("artifacts").each do |artifact|
      suite = artifact.fetch("suite")
      assert_empty suite.fetch("unexplained"), artifact.fetch("id")
      assert_operator suite.fetch("assertions"), :>, suite.fetch("runs"), artifact.fetch("id")
      # The identity that makes `unexplained` exact rather than a subset.
      assert_equal suite.fetch("failures") + suite.fetch("errors"),
                   suite.fetch("xDisplayAcquisitionFlakes") + suite.fetch("unexplained").length,
                   artifact.fetch("id")
    end
  end

  # The headless artifact opens no display, so it has no excuse: it must be clean outright, and it
  # is the one that pins what "green" means for the other two.
  def test_the_headless_artifact_is_clean_outright
    headless = REPORT.fetch("artifacts").find { |artifact| artifact.fetch("id") == "HEADLESS" }
    refute headless.fetch("opensADisplay")
    assert_equal 0, headless.fetch("suite").fetch("failures")
    assert_equal 0, headless.fetch("suite").fetch("errors")
    assert_equal 0, headless.fetch("suite").fetch("xDisplayAcquisitionFlakes")
  end

  # And the two that do open one are the two that may carry the flake at all.
  def test_only_a_windowed_artifact_may_carry_the_flake
    REPORT.fetch("artifacts").each do |artifact|
      next if artifact.fetch("opensADisplay")

      assert_equal 0, artifact.fetch("suite").fetch("xDisplayAcquisitionFlakes"), artifact.fetch("id")
    end
    assert_equal %w[OPENGL33 OPENGLES3_FX],
                 REPORT.fetch("artifacts").select { |a| a.fetch("opensADisplay") }.map { |a| a.fetch("id") }
  end

  # ------------------------------------------------------------------ the toolchain

  def test_the_toolchain_is_the_pinned_one
    toolchain = REPORT.fetch("toolchain")
    assert_equal RUBY_ENGINE, toolchain.fetch("rubyEngine")
    assert_match(/\Aruby 3\.3\./, toolchain.fetch("ruby"))
    refute toolchain.fetch("systemRubyPresent"),
           "the interpreter is the relocated pinned Debian ruby3.3 under ~/deps, not a system one"
    %w[fiddle rbs bundler rake].each { |key| refute_nil toolchain.fetch(key), key }
  end

  def test_the_git_block_names_the_branch_and_nothing_that_goes_stale
    git = REPORT.fetch("git")
    assert_equal %w[branch head worktreeClean], git.keys.sort
    assert_match(/\A[0-9a-f]{40}\z/, git.fetch("head"))
  end
end
