# frozen_string_literal: true

require "json"
require_relative "../../lib/cna"

root = File.expand_path("../..", __dir__)
reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
target = JSON.parse(File.read(File.join(__dir__, "signatures.json")))
strict = JSON.parse(File.read(File.join(root, "docs", "generated", "api-compat-report.json")))

reference_by_name = reference.fetch("types").to_h { |type| [type.fetch("name"), type] }
target_names = target.fetch("types").map { |type| type.fetch("name") }
complete_names = strict.fetch("completeTypeNames")

extract_types = lambda do |signature|
  next [] unless signature

  reference_by_name.keys.select do |name|
    signature == name || signature.include?("[#{name}") || signature.include?(",#{name}") ||
      signature.include?("#{name}]") || signature.include?("#{name}&")
  end
end

type_dependencies = lambda do |type|
  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  type.fetch("members").each do |member|
    signatures.concat([member["type"], member["returnType"]])
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
  end
  signatures.compact.flat_map { |signature| extract_types.call(signature) }.uniq - [type.fetch("name")]
end

missing_labels = strict.fetch("details").fetch("MISSING_MEMBER")
reverse_edges = Hash.new { |hash, key| hash[key] = [] }
missing_labels.each do |label|
  owner, identity = label.split("::", 2)
  member_name = identity.sub(/ \(\d+ overloads?\)\z/, "")
  reference_by_name.fetch(owner).fetch("members").select { |member| member.fetch("name") == member_name }.each do |member|
    signatures = [member["type"], member["returnType"]]
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
    signatures.compact.flat_map { |signature| extract_types.call(signature) }.uniq.each do |dependency|
      reverse_edges[dependency] << label unless dependency == owner
    end
  end
end

candidates = reference.fetch("types").filter_map do |type|
  name = type.fetch("name")
  next if target_names.include?(name)

  dependencies = type_dependencies.call(type)
  unmet = dependencies - complete_names
  reverse = reverse_edges.fetch(name, []).uniq.sort
  expected = type.fetch("members").count do |member|
    !(type["kind"] == "enum" && member["name"] == "value__")
  end
  {
    "name" => name,
    "kind" => type.fetch("kind"),
    "expectedRubyIdentities" => expected,
    "dependencies" => dependencies.sort,
    "unmetDependencies" => unmet.sort,
    "partialRemainderReverseEdges" => reverse,
    "dependencyComplete" => unmet.empty?
  }
end

rank = lambda do |candidate|
  [candidate.fetch("expectedRubyIdentities"), candidate.fetch("name")]
end

# A BCL type counts as mapped when a type that is already complete projects it, or when the
# runtime's BCL projection register declares it. Both halves stay derived from measured work rather
# than an aspirational hand-maintained list: the register is resolved and shape-checked by the API
# verifier under LANGUAGE_MAPPING_MISMATCH, so it cannot claim a projection the runtime lacks.
register_bcl = CNA::Runtime::BclProjection.identities
mapped_bcl = target.fetch("types").each_with_object(register_bcl.dup) do |type, found|
  next unless complete_names.include?(type.fetch("name"))

  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  type.fetch("members").each do |member|
    signatures.concat([member["type"], member["returnType"]])
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
  end
  signatures.compact.each do |signature|
    stripped = signature.sub(/&\z/, "")
    found << stripped unless reference_by_name.keys.any? { |name| stripped.include?(name) }
  end
end.uniq.sort

unmapped_bcl = lambda do |type|
  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  type.fetch("members").each do |member|
    signatures.concat([member["type"], member["returnType"]])
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
  end
  signatures.compact.filter_map do |signature|
    stripped = signature.sub(/&\z/, "")
    next if reference_by_name.keys.any? { |name| stripped.include?(name) }
    next if mapped_bcl.include?(stripped)

    stripped
  end.uniq.sort
end

# Why a dependency-complete candidate still cannot be consumed safely.
#
# BCL_PROJECTION     the type's public signature names a BCL type no complete type projects.
# BEHAVIOR_EVIDENCE  the type declares a constructor or method whose behaviour lives in XNA IL.
#                    The pinned snapshot is metadata only, so that behaviour cannot be derived on
#                    this host without the retained original assemblies.
#
# EVENT_PROJECTION was retired in Foundation 20. Declaring a CLR event is no longer a blocker in
# itself: one CLR event projects to one Ruby event reader over CNA::Runtime::Event, and the API
# verifier measures that projection under EVENT_MAPPING_MISMATCH. What is left of the old blocker
# is exactly the question BCL_PROJECTION already measures — whether the event's
# System.EventHandler`1[TArgs] support type is projected by a complete type — plus, for a class,
# the IL that decides when the event is raised, which BEHAVIOR_EVIDENCE already measures.
classify = lambda do |type|
  blockers = []
  events = type.fetch("members").select { |member| member.fetch("kind") == "event" }
  bcl = unmapped_bcl.call(type)
  blockers << "BCL_PROJECTION" unless bcl.empty?

  behaviour = type.fetch("members").select { |member| %w[constructor method].include?(member.fetch("kind")) }
  metadata_complete = case type.fetch("kind")
                      when "enum" then true
                      when "interface" then true
                      else
                        # A struct with no declared constructor and only read-only properties is
                        # fully described by the CLR default value; anything else needs IL.
                        type.fetch("kind") == "struct" && behaviour.empty? &&
                          type.fetch("members").all? { |member| member.fetch("kind") == "property" && !member.fetch("set") }
                      end
  blockers << "BEHAVIOR_EVIDENCE" unless metadata_complete
  {"blockers" => blockers, "unmappedBclTypes" => bcl,
   "eventMembers" => events.map { |member| member.fetch("name") },
   "behaviourBearingMembers" => behaviour.map { |member| member.fetch("name") }.uniq}
end

dependency_complete = candidates.map do |candidate|
  candidate.merge(classify.call(reference_by_name.fetch(candidate.fetch("name"))))
end.select { |candidate| candidate.fetch("dependencyComplete") }.sort_by(&rank)

consumable = dependency_complete.select { |candidate| candidate.fetch("blockers").empty? }
pure_managed_enums = dependency_complete.select { |candidate| candidate.fetch("kind") == "enum" }

# Preferred route, unchanged since Foundation 9: a dependency-complete managed enum that a selected
# partial remainder still references. When that route is exhausted the ranked consumable list is
# used instead, so leaf progress never requires expanding one of the deferred partial types.
partial_remainder_enums = pure_managed_enums.reject do |candidate|
  candidate.fetch("partialRemainderReverseEdges").empty? || !candidate.fetch("blockers").empty?
end

selected = partial_remainder_enums.first || consumable.first
selection_route = if selected.nil?
                    "none-consumable"
                  elsif partial_remainder_enums.first
                    "partial-remainder-referenced"
                  else
                    "global-consumable-rank"
                  end

blocker_summary = dependency_complete.each_with_object(Hash.new(0)) do |candidate, counts|
  key = candidate.fetch("blockers").empty? ? "NONE" : candidate.fetch("blockers").join("+")
  counts[key] += 1
end.sort.to_h

report = {
  "schemaVersion" => 3,
  "referenceTypes" => reference_by_name.length,
  "targetTypes" => target_names.length,
  "completeTypes" => complete_names.length,
  "partialTypes" => strict.fetch("partialTypes").keys,
  "missingTypes" => strict.fetch("missingTypeNames").length,
  "candidatePolicy" => "missing type; all XNA public-signature dependencies complete; consumable only when no BCL_PROJECTION or BEHAVIOR_EVIDENCE blocker applies; a selected partial remainder reverse edge wins the tie; then fewest expected Ruby identities",
  "retiredBlockers" => {
    "EVENT_PROJECTION" => "retired in Foundation 20; one CLR event projects to one Ruby event reader over CNA::Runtime::Event and the API verifier measures it under EVENT_MAPPING_MISMATCH. The residue is BCL_PROJECTION on the EventHandler`1 support type and, for classes, BEHAVIOR_EVIDENCE on the raising IL."
  },
  "selectionRoute" => selection_route,
  "mappedBclTypes" => mapped_bcl,
  "bclProjectionRegister" => {
    "types" => CNA::Runtime::BclProjection::TYPES,
    "exceptionBases" => CNA::Runtime::BclProjection::EXCEPTION_BASES
  },
  "blockerSummary" => blocker_summary,
  "consumableCandidates" => consumable,
  "dependencyCompleteCandidates" => dependency_complete,
  "pureManagedEnumCandidates" => pure_managed_enums,
  "eligibleManagedEnums" => partial_remainder_enums,
  "selectedNext" => selected&.merge("selectedOnly" => true, "started" => false)
}

destination = File.join(root, "docs", "generated", "public-signature-dependency-report.json")
File.write(destination, JSON.pretty_generate(report) + "\n")

blocker_notes = {
  "BCL_PROJECTION" => "public signature names a BCL type that no complete type projects",
  "BEHAVIOR_EVIDENCE" => "declares a constructor or method whose behaviour lives in XNA IL; the pinned snapshot is metadata only"
}
lines = ["# Dependency frontier", "",
         "Every missing type whose XNA public-signature dependencies are already complete, and the",
         "exact reason each one cannot yet be consumed. Regenerated by",
         "`tools/api_compat/analyze_dependencies.rb`.", "",
         "Consumable now: #{consumable.length}. Dependency-complete but blocked: #{dependency_complete.length - consumable.length}.", ""]
blocker_notes.each { |key, note| lines << "- `#{key}` — #{note}" }
lines << ""
lines << "`EVENT_PROJECTION` was retired in Foundation 20. One CLR event projects to one Ruby event"
lines << "reader over `CNA::Runtime::Event`, and the API verifier measures that projection under"
lines << "`EVENT_MAPPING_MISMATCH`. Declaring an event no longer blocks a candidate; the residue is"
lines << "`BCL_PROJECTION` on its `System.EventHandler`1[TArgs]` support type and, for a class,"
lines << "`BEHAVIOR_EVIDENCE` on the IL that decides when the event is raised."
lines << ""
dependency_complete.group_by { |candidate| candidate.fetch("blockers") }.sort_by { |key, _| key.join }.each do |blockers, list|
  lines << "## #{blockers.empty? ? "CONSUMABLE" : blockers.join(" + ")} (#{list.length})"
  lines << ""
  lines << "| Type | Kind | Ruby identities | Detail |"
  lines << "| --- | --- | --- | --- |"
  list.sort_by { |candidate| candidate.fetch("name") }.each do |candidate|
    detail = []
    detail << "events: #{candidate.fetch("eventMembers").join(", ")}" unless candidate.fetch("eventMembers").empty?
    detail << "unmapped BCL: #{candidate.fetch("unmappedBclTypes").join(", ")}" unless candidate.fetch("unmappedBclTypes").empty?
    unless candidate.fetch("behaviourBearingMembers").empty?
      detail << "IL-bearing: #{candidate.fetch("behaviourBearingMembers").first(6).join(", ")}"
    end
    lines << "| `#{candidate.fetch("name")}` | #{candidate.fetch("kind")} | #{candidate.fetch("expectedRubyIdentities")} | #{detail.join("; ")} |"
  end
  lines << ""
end
File.write(File.join(root, "docs", "generated", "dependency-frontier.md"), lines.join("\n") + "\n")
puts "DEPENDENCY_COMPLETE_CANDIDATES=#{dependency_complete.length}"
puts "CONSUMABLE_CANDIDATES=#{consumable.length}"
puts "PURE_MANAGED_ENUM_CANDIDATES=#{pure_managed_enums.length}"
puts "DEPENDENCY_CANDIDATES=#{partial_remainder_enums.length}"
blocker_summary.each { |key, count| puts "BLOCKED_#{key}=#{count}" }
puts "SELECTION_ROUTE=#{selection_route}"
puts "SELECTED_NEXT=#{selected ? selected.fetch("name") : "none"}"
puts "SELECTED_ONLY=true"
puts "STARTED=false"
