# frozen_string_literal: true

require "json"

# The one place a measured project count is read from.
#
# `plan.md` and `NEXT.md` both state measurements in prose, and both had gone stale — `plan.md` by
# eleven milestones, still describing a 177-type surface, a 229-function manifest and `Effect`,
# `SpriteBatch` and a real renderer as future work after every one of those had landed. That is the
# same defect the dependency frontier had, the behaviour corpus's authoring files had, and
# `plan.md`'s own "Deferred boundaries" section had: **a document stating measured facts, beside a
# tool that measures them, with nothing comparing the two**.
#
# Correcting the prose fixes one milestone. What this module exists for is the other half: every
# count is named here once, read from the generated reports, and rendered into a delimited block
# both documents carry, so `test/test_document_scoreboard.rb` can fail the suite the moment a
# document and the reports disagree. A number that has no `Fact` here may not appear in `plan.md`
# at all — the numeral sweep in that test enforces it — so the way to add a claim is to add a fact.
module CNAScoreboard
  ROOT = File.expand_path("..", __dir__)

  BEGIN_MARK = "<!-- scoreboard:begin -->"
  END_MARK = "<!-- scoreboard:end -->"

  GENERATED_BY = "tools/scoreboard.rb"

  Fact = Struct.new(:key, :value, :label, :group, keyword_init: true)

  class << self
    def report(name) = JSON.parse(File.read(File.join(ROOT, "docs", "generated", name)))

    def registry = JSON.parse(File.read(File.join(ROOT, "docs", "runtime-capabilities.json")))

    # Every fact, in the order the rendered block presents them. `group` is the table section.
    def facts
      @facts ||= begin
        strict = report("api-compat-report.json")
        abi = report("native-abi-report.json")
        corpus = report("behavior-corpus-report.json")
        frontier = report("public-signature-dependency-report.json")
        partial = strict.fetch("partialTypes")

        # Everything the verifier counts that is not one of the four categories named below. It is
        # summed rather than listed so that a category which becomes non-zero cannot hide: the block
        # says zero, and the moment one fires the block says otherwise and both documents fail.
        named = %w[MISSING_TYPE MISSING_MEMBER OVERLOAD_MAPPING_MISMATCH PROPERTY_MAPPING_MISMATCH]
        others = strict.select { |key, value| structural_category?(key, value) && !named.include?(key) }

        [
          fact("REFERENCE_TYPES", strict.fetch("REFERENCE_TYPES"), "XNA 4.0 Windows reference types", "Selected surface"),
          fact("PROJECTED_TYPES", strict.fetch("TARGET_TYPES"), "types this binding projects", "Selected surface"),
          fact("PROJECTED_MEMBERS", strict.fetch("TARGET_MEMBERS"), "Ruby member identities", "Selected surface"),
          fact("COMPLETE_TYPES", strict.fetch("COMPLETE_TYPES"), "complete types", "Selected surface"),
          fact("PARTIAL_TYPES", strict.fetch("PARTIAL_TYPES"), "partial types", "Selected surface"),
          fact("MISSING_TYPES", strict.fetch("MISSING_TYPES"), "missing types", "Selected surface"),
          fact("EVENT_IDENTITIES", strict.fetch("EVENT_IDENTITIES"), "event identities", "Selected surface"),
          fact("EVENT_OWNER_TYPES", strict.fetch("EVENT_OWNER_TYPES"), "types owning an event", "Selected surface"),
          fact("BCL_IDENTITIES", strict.fetch("BCL_PROJECTED_IDENTITIES"), "projected BCL identities", "Selected surface"),

          fact("TOTAL_DIAGNOSTICS", strict.fetch("TOTAL_DIAGNOSTICS"), "strict diagnostics in total", "Strict diagnostics"),
          fact("MISSING_TYPE", strict.fetch("MISSING_TYPE"), "`MISSING_TYPE`", "Strict diagnostics"),
          fact("MISSING_MEMBER", strict.fetch("MISSING_MEMBER"), "`MISSING_MEMBER`", "Strict diagnostics"),
          fact("OVERLOAD_MAPPING_MISMATCH", strict.fetch("OVERLOAD_MAPPING_MISMATCH"), "`OVERLOAD_MAPPING_MISMATCH`", "Strict diagnostics"),
          fact("PROPERTY_MAPPING_MISMATCH", strict.fetch("PROPERTY_MAPPING_MISMATCH"), "`PROPERTY_MAPPING_MISMATCH`", "Strict diagnostics"),
          fact("OTHER_STRUCTURAL_DIAGNOSTICS", others.values.sum, "every other structural category, summed", "Strict diagnostics"),
          fact("ALLOWLIST_ENTRIES", strict.fetch("ALLOWLIST_ENTRIES"), "allowlist entries", "Strict diagnostics"),
          fact("UNMEASURED_STRUCTURAL_CATEGORY", strict.fetch("UNMEASURED_STRUCTURAL_CATEGORY"), "`UNMEASURED_STRUCTURAL_CATEGORY`", "Strict diagnostics"),

          fact("GRAPHICS_DEVICE_OUTSTANDING", outstanding(partial, "Microsoft.Xna.Framework.Graphics.GraphicsDevice"),
               "members `GraphicsDevice` still owes", "Partial remainders"),
          fact("GRAPHICS_DEVICE_MANAGER_OUTSTANDING", outstanding(partial, "Microsoft.Xna.Framework.GraphicsDeviceManager"),
               "members `GraphicsDeviceManager` still owes", "Partial remainders"),

          fact("ABI_FUNCTIONS", abi.fetch("BOUND_FUNCTIONS"), "bound C functions", "Native ABI"),
          fact("ABI_CALLBACKS", abi.fetch("CALLBACKS"), "callbacks", "Native ABI"),
          fact("ABI_CONSTANTS", abi.fetch("CONSTANTS"), "constants", "Native ABI"),
          fact("ABI_LAYOUTS", abi.fetch("STRUCT_LAYOUTS"), "struct layouts", "Native ABI"),
          fact("ABI_ADMITTED_VERSIONS", abi.fetch("ADMITTED_ABI_VERSIONS"), "admitted encoded ABI versions", "Native ABI"),
          fact("ABI_HEADER_ROOTS", abi.fetch("HEADER_ROOTS_VERIFIED"), "header roots cross-verified", "Native ABI"),
          fact("ABI_MISMATCHES", abi.fetch("ABI_MISMATCHES"), "`ABI_MISMATCHES`", "Native ABI"),
          fact("ABI_CROSS_VERSION_MISMATCHES", abi.fetch("CROSS_VERSION_MISMATCHES"), "`CROSS_VERSION_MISMATCHES`", "Native ABI"),
          fact("ABI_MISSING_HEADER_SYMBOLS", abi.fetch("MISSING_HEADER_SYMBOLS"), "missing header symbols", "Native ABI"),
          fact("ABI_MISSING_LIBRARY_SYMBOLS", abi.fetch("MISSING_LIBRARY_SYMBOLS"), "missing library symbols", "Native ABI"),

          fact("CORPUS_OBSERVATIONS", corpus.fetch("OBSERVATIONS"), "behaviour-corpus observations", "Behaviour corpus"),
          fact("CORPUS_FAILURES", corpus.fetch("FAILURES"), "behaviour-corpus failures", "Behaviour corpus"),

          fact("FRONTIER_CANDIDATES", frontier.fetch("dependencyCompleteCandidates").length,
               "dependency-complete frontier candidates", "Dependency frontier"),
          fact("FRONTIER_CONSUMABLE", frontier.fetch("consumableCandidates").length,
               "of them consumable now", "Dependency frontier"),

          fact("CAPABILITY_ROWS", registry.fetch("capabilities").length, "runtime capability rows", "Capability registry")
        ]
      end
    end

    def value(key) = facts.find { |entry| entry.key == key }&.value || raise(KeyError, "no scoreboard fact #{key}")

    def keys = facts.map(&:key)

    # The delimited block both documents carry, markers included.
    def block
      lines = [BEGIN_MARK, "", "<!-- Generated by #{GENERATED_BY}; edit the reports, never this block. -->", ""]
      facts.group_by(&:group).each do |group, entries|
        lines << "**#{group}**"
        lines << ""
        lines << "| count | what it measures |"
        lines << "| ---: | --- |"
        entries.each { |entry| lines << "| #{entry.value} | #{entry.label} |" }
        lines << ""
      end
      lines << END_MARK
      lines.join("\n")
    end

    # Replace the delimited block in `text`, or raise if the document does not carry one.
    def rewrite(text)
      pattern = /#{Regexp.escape(BEGIN_MARK)}.*?#{Regexp.escape(END_MARK)}/m
      raise ArgumentError, "document carries no #{BEGIN_MARK} … #{END_MARK} block" unless text.match?(pattern)

      text.sub(pattern) { block }
    end

    def extract(text)
      text[/#{Regexp.escape(BEGIN_MARK)}.*?#{Regexp.escape(END_MARK)}/m] ||
        raise(ArgumentError, "document carries no #{BEGIN_MARK} … #{END_MARK} block")
    end

    private

    def fact(key, value, label, group) = Fact.new(key: key, value: value, label: label, group: group)

    def structural_category?(key, value) = key.match?(/\A[A-Z][A-Z_]+\z/) && value.is_a?(Integer) && category_names.include?(key)

    # The verifier's own category list, read from the verifier rather than restated, so a category
    # added there is summed here without anyone remembering to.
    def category_names
      @category_names ||= begin
        require_relative "api_compat/verifier"
        CNAApiCompat::CATEGORIES
      end
    end

    def outstanding(partial, name)
      partial.fetch(name) { raise KeyError, "#{name} is no longer partial; the scoreboard fact must go" }.length
    end
  end
end
