# frozen_string_literal: true

require "json"
require "digest"
require "fiddle"
require "open3"

# The qualification report, measured rather than written down.
#
# `docs/generated/qualification-report.json` used to be a **hand-authored record of one session** —
# it carried "Foundations 34-39", a 141-type surface, a 0.7.0 ABI and that session's own commit
# list, and sixty milestones later it still did, because nothing produced it and nothing compared it
# to anything. It is the same defect `plan.md`'s prose had and the dependency frontier had before
# each was guarded: a document stating measured facts, beside tools that measure them, with nothing
# in between.
#
# That file is kept, unchanged, as `docs/qualification-foundations-34-39.json`: it is a real
# historical record of a real run and several of its findings are cited elsewhere. What lives in
# `docs/generated/` now is this tool's output, and `test/test_qualification_report.rb` fails the
# suite whenever any part of it disagrees with the report it was derived from.
#
# What this measures that no other report does is the **suite itself, on every qualified artifact**.
# `rake test` is run once per artifact and its totals are parsed out. The two windowed artifacts
# need an X display and `SDL_VIDEODRIVER=x11`, and each attempt gets a **fresh private `Xvfb`** —
# never an inherited `DISPLAY`, because two of the three artifacts really do create windows and a
# qualification run must not open them on whatever session happens to be logged in.
module CNAQualification
  ROOT = File.expand_path("..", __dir__)
  DEPS = File.join(Dir.home, "deps")

  # The three qualified artifacts, in the order the evidence documents name them. `renderer` is what
  # each one's own `[INFO][RENDER]` line reports, asserted below rather than assumed.
  ARTIFACTS = [
    { "id" => "HEADLESS", "root" => "cna-c-abi-0.21.0", "display" => false },
    { "id" => "OPENGL33", "root" => "cna-c-abi-0.21.0-opengl33", "display" => true },
    { "id" => "OPENGLES3_FX", "root" => "cna-c-abi-0.21.0-opengles3-fx", "display" => true }
  ].freeze

  SUITE_LINE = /^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips/
  # One minitest problem block: the header, then everything up to the next header or the summary.
  PROBLEM = /^\s+\d+\) (Failure|Error):\n(.*?)(?=^\s+\d+\) (?:Failure|Error):|^\d+ runs,|\z)/m

  # MEASURED, and recorded rather than papered over: on the two windowed artifacts a small, varying
  # number of the ~1735 games — zero to a handful, different ones each run — fail to create with
  # SDL's `AcquireSubsystem(Video) failed: x11 not available`. It reproduces against a fresh
  # `Xvfb`, against one shared by two consecutive suites, and with `-maxclients 2048`, so it is
  # neither a client-limit nor a server-lifetime effect; it is the X display refusing an open under
  # churn, and every affected test passes on its own immediately afterwards.
  #
  # It also produces **collateral**: a test whose game never came up can fail an ordinary assertion
  # with no `Error` of its own — `[RuntimeError] exception expected, not CNA::NativeError` is the
  # measured example. So the signature is matched against the whole problem block, `Failure` blocks
  # included, and anything that does not carry it is `unexplained` and fails
  # `test/test_qualification_report.rb`. A real regression can never hide behind it.
  X_ACQUISITION = /x11 not available/

  class << self
    def report(name) = JSON.parse(File.read(File.join(ROOT, "docs", "generated", name)))

    def registry = JSON.parse(File.read(File.join(ROOT, "docs", "runtime-capabilities.json")))

    def run
      strict = report("api-compat-report.json")
      abi = report("native-abi-report.json")
      corpus = report("behavior-corpus-report.json")
      frontier = report("public-signature-dependency-report.json")
      provenance = report("xna-il-inventory.json")

      {
        "schemaVersion" => 2,
        "generatedBy" => "tools/run_qualification.rb",
        "historicalRecord" => "docs/qualification-foundations-34-39.json",
        "milestone" => registry.fetch("milestone"),
        "date" => Time.now.utc.strftime("%Y-%m-%d"),
        "toolchain" => toolchain,
        "git" => git_state,
        "artifacts" => ARTIFACTS.map { |entry| qualify(entry) },
        "strict" => strict_block(strict),
        "remainingPartialTypes" => {
          "count" => strict.fetch("PARTIAL_TYPES"),
          "outstanding" => strict.fetch("partialTypes")
        },
        "nativeAbi" => abi.reject { |key, _| key == "mismatches" },
        "behavior" => {
          "OBSERVATIONS" => corpus.fetch("OBSERVATIONS"),
          "ASSERTIONS" => corpus.fetch("ASSERTIONS"),
          "FAILURES" => corpus.fetch("FAILURES"),
          "provenanceCounts" => corpus.fetch("provenanceCounts")
        },
        "dependencyFrontier" => {
          "dependencyCompleteCandidates" => frontier.fetch("dependencyCompleteCandidates").length,
          "consumableCandidates" => frontier.fetch("consumableCandidates").length,
          "selectionRoute" => frontier.fetch("selectionRoute"),
          "selectedNext" => frontier.fetch("selectedNext")
        },
        "ilProvenance" => {
          "REFERENCE_TYPES" => provenance.fetch("REFERENCE_TYPES"),
          "TYPES_WITH_IL" => provenance.fetch("TYPES_WITH_IL"),
          "TYPES_NATIVE_REACHABLE" => provenance.fetch("TYPES_NATIVE_REACHABLE")
        },
        "capabilities" => {
          "CAPABILITIES" => registry.fetch("capabilities").length,
          "CAPABILITY_CONTRADICTIONS" => contradictions
        }
      }
    end

    private

    # Only the counted categories, so a category the verifier adds is carried without editing this.
    def strict_block(strict)
      strict.select { |_key, value| value.is_a?(Integer) }.sort.to_h
    end

    def toolchain
      {
        "ruby" => RUBY_DESCRIPTION,
        "rubyEngine" => RUBY_ENGINE,
        "fiddle" => Fiddle::VERSION,
        "rbs" => capture("rbs", "--version")&.split&.last,
        "bundler" => capture("bundle", "--version")&.split&.last,
        "rake" => capture("rake", "--version")&.split&.last,
        "systemRubyPresent" => File.exist?("/usr/bin/ruby")
      }
    end

    def git_state
      {
        "branch" => capture("git", "rev-parse", "--abbrev-ref", "HEAD"),
        "head" => capture("git", "rev-parse", "HEAD"),
        "worktreeClean" => capture("git", "status", "--porcelain").to_s.empty?
      }
    end

    def contradictions
      output = capture("ruby", File.join(ROOT, "tools", "capability_consistency.rb"))
      output.to_s[/CAPABILITY_CONTRADICTIONS=(\d+)/, 1].to_i
    end

    # A private display, started for one attempt and stopped after it.
    # `CNA_QUALIFICATION_DISPLAY` overrides, for a host with no `Xvfb`.
    def on_fresh_display
      return yield(ENV["CNA_QUALIFICATION_DISPLAY"]) unless ENV["CNA_QUALIFICATION_DISPLAY"].to_s.empty?

      number = 90 + rand(9)
      pid = spawn("Xvfb", ":#{number}", "-screen", "0", "1280x800x24",
                  out: File::NULL, err: File::NULL)
      sleep 2
      begin
        yield(":#{number}")
      ensure
        Process.kill("TERM", pid)
        Process.wait(pid)
      end
    end

    # One run per artifact, recorded as it happened. There is deliberately **no retry**: the
    # X-acquisition fault is frequent enough on the windowed artifacts that retrying rarely buys a
    # clean run and always triples the cost, and re-rolling until the environment behaves is not a
    # measurement. What the guard requires instead is that every problem in the run is attributable
    # to that fault — `unexplained` empty — and that the headless artifact, which opens no display
    # at all, is clean outright.
    def qualify(entry)
      root = File.join(DEPS, entry.fetch("root"))
      library = File.join(root, "libcna_c_api.so")
      raise "qualified artifact missing: #{library}" unless File.exist?(library)

      warn "qualifying #{entry.fetch("id")}…"
      environment = { "CNA_NATIVE_LIBRARY" => library }
      result =
        if entry.fetch("display")
          on_fresh_display { |display| suite(environment.merge("DISPLAY" => display, "SDL_VIDEODRIVER" => "x11")) }
        else
          suite(environment)
        end

      entry.slice("id").merge(
        "library" => library,
        "librarySha256" => Digest::SHA256.file(library).hexdigest,
        "opensADisplay" => entry.fetch("display"),
        "suite" => result
      )
    end

    # `CNA_QUALIFICATION_RUN` tells `test/test_qualification_report.rb` to stand down. It has to:
    # the report it guards is the one this run is about to write, so inside these runs it is stale
    # by construction and would report the previous milestone's numbers as a failure of this one.
    # Every ordinary `rake test` runs it, which is where it does its work.
    def suite(environment)
      output, = Open3.capture2e(environment.merge("CNA_QUALIFICATION_RUN" => "1"),
                                "rake", "test", chdir: ROOT)
      match = output[SUITE_LINE, 0] or raise "no suite total in:\n#{output.lines.last(20).join}"
      runs, assertions, failures, errors, skips = match.scan(/\d+/).map(&:to_i)
      problems = output.scan(PROBLEM).map { |kind, body| [kind, body.strip] }
      flakes, unexplained = problems.partition { |_kind, body| body.match?(X_ACQUISITION) }
      { "runs" => runs, "assertions" => assertions, "failures" => failures,
        "errors" => errors, "skips" => skips,
        "xDisplayAcquisitionFlakes" => flakes.length,
        "unexplained" => unexplained.map { |kind, body| "#{kind}: #{body.lines.first(3).join.strip}" } }
    end

    def capture(*command)
      output, status = Open3.capture2e(*command, chdir: ROOT)
      status.success? ? output.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  result = CNAQualification.run
  path = File.join(CNAQualification::ROOT, "docs", "generated", "qualification-report.json")
  File.write(path, JSON.pretty_generate(result) + "\n")
  result.fetch("artifacts").each do |artifact|
    suite = artifact.fetch("suite")
    puts "#{artifact.fetch("id")}=#{suite.fetch("runs")} runs / #{suite.fetch("assertions")} assertions / " \
         "#{suite.fetch("failures")} failures / #{suite.fetch("errors")} errors / #{suite.fetch("skips")} skips"
  end
  puts "SUITE_UNEXPLAINED=#{result.fetch("artifacts").sum { |a| a.fetch("suite").fetch("unexplained").length }}"
  puts "X_DISPLAY_FLAKES=#{result.fetch("artifacts").sum { |a| a.fetch("suite").fetch("xDisplayAcquisitionFlakes") }}"
end
