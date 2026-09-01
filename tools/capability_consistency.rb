# frozen_string_literal: true

require "json"

# Measured consistency of the runtime capability registry.
#
# Foundation 27 qualified fully green while `docs/runtime-capabilities.json` still carried three
# resolved blockers as active decisions and several rows asserting that types the strict report
# marks COMPLETE were absent. Nothing in the pipeline compared the registry against the rest of the
# project, so nothing caught it.
#
# Every rule here is derived from measurable project state — the strict report, the IL inventory and
# the live Ruby namespaces — rather than from fixed strings, so a future milestone that reintroduces
# the same class of contradiction fails without anyone having to remember this one.
module CapabilityConsistency
  # `VERIFIED_NATIVE_RENDERER` is not a synonym for `VERIFIED_NATIVE`. Every native claim this
  # project made before Native frontier 6 was measured against an artifact built
  # `CNA_GRAPHICS_RENDERER=HEADLESS`, whose descriptor sets `needsWindow = false` and whose
  # readback route answers `CNA_RESULT_NOT_SUPPORTED`: routes execute and report success, and no
  # pixel is ever produced. A claim that needs a renderer that really rasterises is a different
  # claim from one that needs only a canonical route, and conflating the two is exactly how
  # "verified" came to mean two things.
  RESOLVED_CATEGORIES = %w[VERIFIED_MANAGED VERIFIED_NATIVE VERIFIED_NATIVE_ROUTE VERIFIED_NATIVE_RENDERER].freeze
  UNRESOLVED_CATEGORIES = %w[
    UNRESOLVED_MAPPING_DECISION UPSTREAM_INPUT_UNAVAILABLE UPSTREAM_CNA_BLOCKED
    UNIMPLEMENTED_CNA_RUBY BACKEND_BLOCKED
  ].freeze
  # Neither resolved nor blocked: a standing statement about the environment or the language.
  INFORMATIONAL_CATEGORIES = %w[
    PLATFORM_PENDING HARDWARE_PENDING ASSET_PENDING LANGUAGE_MAPPING_LIMITATION
  ].freeze
  KNOWN_CATEGORIES = (RESOLVED_CATEGORIES + UNRESOLVED_CATEGORIES + INFORMATIONAL_CATEGORIES).freeze

  # A *global* assertion that something is absent, unimplemented or not present. A scoped
  # non-claim — "no render target support is claimed" — is deliberately not one of these: it says
  # what a capability claims, not what the binding contains, and stays true when a later milestone
  # adds the type from its own evidence.
  GLOBAL_ABSENCE = /
    \bremains?\s+absent\b | \bremain\s+absent\b |
    \bremains?\s+unimplemented\b | \bremain\s+unimplemented\b |
    \bis\s+implemented\s+or\s+claimed\b | \bare\s+implemented\b |
    \bnamespace\s+is\s+added\b | \bis\s+added\b |
    \bexists\s+or\s+is\s+claimed\b
  /xi.freeze

  UNIVERSAL_ABSENCE = /\b(?:remains?|remain|stay|stays)\s+(?:absent|unimplemented)\b/i.freeze

  NAMESPACE_COUNT = /
    (?:Microsoft\.Xna\.Framework\.)?(?<namespace>[A-Z]\w*(?:\.[A-Z]\w*)?)\s+namespace\s+
    (?:contains|holds)(?:\s+exactly)?(?:\s+these)?\s+(?<count>\w+)\s+(?:enums|types)
  /xi.freeze

  NAMESPACE_ABSENT = /\bno\s+(?<subjects>[^.;]+?)\s+namespace\s+is\s+added\b/i.freeze

  NUMBER_WORDS = {
    "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6, "seven" => 7,
    "eight" => 8, "nine" => 9, "ten" => 10, "eleven" => 11, "twelve" => 12
  }.freeze

  Finding = Struct.new(:rule, :capability, :detail) do
    def to_s = "#{rule} [#{capability}] #{detail}"
  end

  # `namespaces` maps a dotted Framework namespace ("Input.Touch") to the Ruby constant, or nil.
  # It is injected so the checker stays usable from a tool, a test and a fixture alike.
  def self.check(registry:, strict:, il_inventory:, namespaces:)
    rows = registry.fetch("capabilities")
    complete = strict.fetch("completeTypeNames")
    findings = []
    findings.concat(unknown_categories(rows))
    findings.concat(duplicate_identities(rows))
    findings.concat(contradictory_subjects(rows))
    findings.concat(unavailable_admitted_input(rows, il_inventory))
    findings.concat(absent_complete_types(rows, complete))
    findings.concat(namespace_counts(rows, namespaces))
    findings.concat(absent_present_namespaces(rows, namespaces))
    findings.concat(unimplemented_subsystems(rows, complete, namespaces))
    findings
  end

  # A category the gate does not classify would silently escape every polarity rule below, so an
  # unrecognised one is itself a finding rather than a hole.
  def self.unknown_categories(rows)
    rows.reject { |row| KNOWN_CATEGORIES.include?(row["category"]) }.map do |row|
      Finding.new("UNKNOWN_CATEGORY", row.fetch("id"), "category #{row["category"].inspect} is unclassified")
    end
  end

  # Two rows may not share an identity: the registry is current state, so an identity has one truth.
  def self.duplicate_identities(rows)
    rows.map { |row| row.fetch("id") }.tally.select { |_, count| count > 1 }.map do |id, count|
      Finding.new("DUPLICATE_IDENTITY", id, "appears #{count} times")
    end
  end

  # `mapping.event-projection` blocked while `managed.event-projection` is verified is the exact
  # defect this rule exists for: the identity subject is shared, the resolution polarity is not.
  def self.contradictory_subjects(rows)
    rows.group_by { |row| row.fetch("id").split(".", 2).last }.filter_map do |subject, group|
      resolved = group.select { |row| RESOLVED_CATEGORIES.include?(row["category"]) }
      unresolved = group.select { |row| UNRESOLVED_CATEGORIES.include?(row["category"]) }
      next if resolved.empty? || unresolved.empty?

      Finding.new("CONTRADICTORY_SUBJECT", unresolved.map { |row| row.fetch("id") }.join(", "),
                  "subject #{subject.inspect} is also #{resolved.map { |row| row.fetch("id") }.join(", ")}")
    end
  end

  # An upstream input cannot be unavailable while the project measurably admits it. The IL
  # inventory only exists when every pinned assembly was admitted by exact SHA-256.
  def self.unavailable_admitted_input(rows, il_inventory)
    return [] if il_inventory.nil?
    return [] unless il_inventory.fetch("TYPES_WITH_IL", 0).positive?

    admitted = il_inventory.fetch("assemblies").length
    rows.select { |row| row["category"] == "UPSTREAM_INPUT_UNAVAILABLE" }.filter_map do |row|
      text = "#{row.fetch("id")} #{row["evidence"]}"
      next unless text.match?(/xna/i) && text.match?(/\b(?:IL|assembl\w*)\b/i)

      Finding.new("UNAVAILABLE_ADMITTED_INPUT", row.fetch("id"),
                  "claims XNA IL/assemblies are unavailable while the inventory admits #{admitted}")
    end
  end

  # A globally absent or unimplemented claim may not name a type the strict report calls COMPLETE.
  def self.absent_complete_types(rows, complete)
    short = complete.to_h { |name| [name.split(".").last, name] }
    rows.flat_map do |row|
      clauses(row["evidence"]).flat_map do |clause|
        next [] unless clause.match?(GLOBAL_ABSENCE)

        short.filter_map do |name, full|
          next unless clause.match?(/(?<![\w])#{Regexp.escape(name)}(?![\w])/)

          Finding.new("ABSENT_COMPLETE_TYPE", row.fetch("id"),
                      "#{full} is COMPLETE but the evidence says: #{clause.strip}")
        end
      end
    end
  end

  # "the Audio namespace contains these four enums and nothing else" is checked against the live
  # namespace, so a later milestone that adds a type to it cannot leave the claim standing.
  def self.namespace_counts(rows, namespaces)
    rows.flat_map do |row|
      row["evidence"].to_s.scan(NAMESPACE_COUNT).map { Regexp.last_match }.filter_map do |match|
        claimed = NUMBER_WORDS[match[:count].downcase] || Integer(match[:count], exception: false)
        namespace = namespaces[match[:namespace]]
        next if claimed.nil? || namespace.nil?

        actual = namespace.constants(false).length
        next if actual == claimed

        Finding.new("NAMESPACE_COUNT", row.fetch("id"),
                    "claims #{match[:namespace]} holds #{claimed}, live namespace holds #{actual}")
      end
    end
  end

  # "no Content or Storage namespace is added" is checked against the live namespaces.
  def self.absent_present_namespaces(rows, namespaces)
    rows.flat_map do |row|
      row["evidence"].to_s.scan(NAMESPACE_ABSENT).map { Regexp.last_match }.flat_map do |match|
        match[:subjects].split(/,|\bor\b|\band\b/).map(&:strip).filter_map do |subject|
          next unless namespaces.key?(subject)

          Finding.new("PRESENT_NAMESPACE_CLAIMED_ABSENT", row.fetch("id"),
                      "#{subject} exists but the evidence says it is not added")
        end
      end
    end
  end

  # A subsystem row asserting that everything in its scope stays absent must account for the types
  # in that scope the strict report marks COMPLETE. Requiring the row to name every one of them is
  # what makes it self-maintaining: the next milestone that completes a type in the namespace has
  # to say so here too, which is precisely the drift that went unnoticed through Foundation 27.
  def self.unimplemented_subsystems(rows, complete, namespaces)
    rows.select { |row| row["category"] == "UNIMPLEMENTED_CNA_RUBY" }.flat_map do |row|
      evidence = row["evidence"].to_s
      next [] unless evidence.match?(UNIVERSAL_ABSENCE)

      scoped_namespaces(row.fetch("id"), namespaces).filter_map do |dotted, _namespace|
        present = complete.select { |name| name.start_with?("Microsoft.Xna.Framework.#{dotted}.") }
        unnamed = present.reject do |name|
          short = name.split(".").last
          evidence.match?(/(?<![\w])#{Regexp.escape(short)}(?![\w])/)
        end
        next if unnamed.empty?

        Finding.new("UNIMPLEMENTED_WITH_COMPLETE_TYPES", row.fetch("id"),
                    "#{dotted} holds #{unnamed.length} COMPLETE types the evidence does not name, " \
                    "first #{unnamed.first}")
      end
    end
  end

  # `audio-media` scopes to Audio and Media; `input.touch` scopes to Input.Touch. Only the most
  # specific match is reported, so Input.Touch does not also drag in the whole of Input.
  def self.scoped_namespaces(id, namespaces)
    segments = id.split(/[.\-]/).map(&:downcase)
    matched = namespaces.keys.select do |dotted|
      dotted.split(".").map(&:downcase).all? { |part| segments.include?(part) }
    end
    specific = matched.reject { |dotted| matched.any? { |other| other != dotted && other.start_with?("#{dotted}.") } }
    specific.to_h { |dotted| [dotted, namespaces.fetch(dotted)] }
  end

  def self.clauses(evidence) = evidence.to_s.split(/;|(?<=\.)\s+/)

  # Every module under Microsoft::Xna::Framework that is a namespace rather than a projected XNA
  # type, keyed by its dotted name relative to the facade, so the rules above can compare a registry
  # claim against the namespace that actually exists. XNA interfaces project to Ruby modules too,
  # and `types` excludes them.
  def self.framework_namespaces(types: [], root: Microsoft::Xna::Framework, prefix: nil, found: {})
    root.constants(false).each do |constant|
      value = root.const_get(constant, false)
      next unless value.instance_of?(Module)
      next if types.include?(value)

      dotted = prefix ? "#{prefix}.#{constant}" : constant.to_s
      found[dotted] = value
      framework_namespaces(types: types, root: value, prefix: dotted, found: found)
    end
    found
  end

  # The Ruby constants the selected XNA surface projects, so namespaces can be told from types.
  def self.projected_types(signatures)
    signatures.fetch("types").filter_map do |type|
      type.fetch("rubyName").split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
    rescue NameError
      nil
    end
  end

  private_class_method :unknown_categories, :duplicate_identities, :contradictory_subjects,
                       :unavailable_admitted_input,
                       :absent_complete_types, :namespace_counts, :absent_present_namespaces,
                       :unimplemented_subsystems
end
