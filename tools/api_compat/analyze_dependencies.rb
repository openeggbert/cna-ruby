# frozen_string_literal: true

require "json"
require_relative "../../lib/cna"

root = File.expand_path("../..", __dir__)
reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
target = JSON.parse(File.read(File.join(__dir__, "signatures.json")))
strict = JSON.parse(File.read(File.join(root, "docs", "generated", "api-compat-report.json")))
il_inventory = JSON.parse(File.read(File.join(root, "docs", "generated", "xna-il-inventory.json")))
il_types = il_inventory.fetch("types")

# A type whose behaviour the pinned IL proves, but whose *values* only a device, driver, codec,
# media library or attached hardware can supply. IL availability settles semantics, never the
# availability of runtime data, and this project does not fabricate capability values. Each entry
# must name the exact missing input; test/test_dependency_frontier.rb enforces that.
RUNTIME_DATA = {
  "Microsoft.Xna.Framework.Audio.RendererDetail" => "values come from XACT audio renderer enumeration; no audio engine exists in this binding and no renderer has been enumerated",
  "Microsoft.Xna.Framework.Audio.AudioCategory" => "an XACT AudioEngine category handle; SetVolume/Pause/Resume/Stop act on a live engine this binding does not have",
  "Microsoft.Xna.Framework.Media.MediaSource" => "GetAvailableMediaSources enumerates the host media sources; no media stack has been queried",
  "Microsoft.Xna.Framework.Media.Video" => "produced only by the content pipeline or MediaLibrary; no producer exists and the class declares no public constructor",
  "Microsoft.Xna.Framework.Media.VisualizationData" => "filled by MediaPlayer.GetVisualizationData from live playback",
  "Microsoft.Xna.Framework.Graphics.ResourceCreatedEventArgs" => "raised only by GraphicsDevice.ResourceCreated; the class declares no public constructor and no producer exists",
  "Microsoft.Xna.Framework.Graphics.ResourceDestroyedEventArgs" => "raised only by GraphicsDevice.ResourceDestroyed; the class declares no public constructor and no producer exists",
  "Microsoft.Xna.Framework.GameWindow" => "an abstract window whose concrete implementation is the platform window behind Game; projecting it would require the deferred Game/window runtime",
  "Microsoft.Xna.Framework.FrameworkDispatcher" => "Update pumps the live audio and media services; with neither present it would be a no-op pretending to be a pump"
}.freeze

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
# BCL_PROJECTION   the type's public signature names a BCL type no complete type projects.
# IL_UNAVAILABLE   the type declares behaviour but no pinned assembly carries its IL.
# NATIVE_RUNTIME   the type's own IL reaches a native entry point, so faithful behaviour needs CNA
#                  or platform support this managed sequence does not add.
# RUNTIME_DATA     the pinned IL settles the type's semantics, but its values come only from a
#                  device, driver, codec, media library or attached hardware that has not been
#                  queried. Fabricating them is refused.
#
# EVENT_PROJECTION was retired in Foundation 20. BEHAVIOR_EVIDENCE was retired in Foundation 22:
# the original XNA 4.0 Windows assemblies are on this host, hash-pinned by
# tools/api_compat/reference/XNA_IL_PROVENANCE.md, so "behaviour lives in IL" is a statement about
# work to do rather than about missing input. Declaring a constructor or method is now reported as
# the informational `ilDerivationRequired` flag, not as a blocker.
classify = lambda do |type|
  name = type.fetch("name")
  blockers = []
  events = type.fetch("members").select { |member| member.fetch("kind") == "event" }
  bcl = unmapped_bcl.call(type)
  blockers << "BCL_PROJECTION" unless bcl.empty?

  behaviour = type.fetch("members").select { |member| %w[constructor method].include?(member.fetch("kind")) }
  il = il_types[name]
  blockers << "IL_UNAVAILABLE" if il.nil? && !behaviour.empty?
  blockers << "NATIVE_RUNTIME" if il && il.fetch("nativeReachable")
  blockers << "RUNTIME_DATA" if RUNTIME_DATA.key?(name)

  {"blockers" => blockers, "unmappedBclTypes" => bcl,
   "eventMembers" => events.map { |member| member.fetch("name") },
   "behaviourBearingMembers" => behaviour.map { |member| member.fetch("name") }.uniq,
   "ilDerivationRequired" => !behaviour.empty?,
   "ilAvailable" => !il.nil?,
   "ilAssembly" => il && il.fetch("assembly"),
   "nativeReachableMethods" => il ? il.fetch("nativeReachableMethods") : [],
   "runtimeDataDetail" => RUNTIME_DATA[name]}
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
  "candidatePolicy" => "missing type; all XNA public-signature dependencies complete; consumable only when no BCL_PROJECTION, IL_UNAVAILABLE, NATIVE_RUNTIME or RUNTIME_DATA blocker applies; a selected partial remainder reverse edge wins the tie; then fewest expected Ruby identities",
  "ilProvenance" => {
    "register" => "tools/api_compat/reference/XNA_IL_PROVENANCE.md",
    "inventory" => "docs/generated/xna-il-inventory.json",
    "assemblies" => il_inventory.fetch("assemblies").length,
    "typesWithIl" => il_inventory.fetch("TYPES_WITH_IL"),
    "typesNativeReachable" => il_inventory.fetch("TYPES_NATIVE_REACHABLE")
  },
  "runtimeDataRegister" => RUNTIME_DATA,
  "retiredBlockers" => {
    "EVENT_PROJECTION" => "retired in Foundation 20; one CLR event projects to one Ruby event reader over CNA::Runtime::Event and the API verifier measures it under EVENT_MAPPING_MISMATCH. The residue is BCL_PROJECTION on the EventHandler`1 support type and, for classes, the IL that decides when the event is raised.",
    "BEHAVIOR_EVIDENCE" => "retired in Foundation 22; the original hash-pinned XNA 4.0 Windows assemblies are available on this host, so declaring a constructor or method is work to do, not missing input. It is reported as the informational ilDerivationRequired flag and split into the IL_UNAVAILABLE, NATIVE_RUNTIME and RUNTIME_DATA blockers, which name what is genuinely absent."
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
  "IL_UNAVAILABLE" => "declares behaviour but no pinned assembly carries its IL",
  "NATIVE_RUNTIME" => "its own IL reaches a native entry point, so faithful behaviour needs CNA or platform support this managed sequence does not add",
  "RUNTIME_DATA" => "the pinned IL settles its semantics, but its values come only from a device, driver, codec or media library that has not been queried"
}
lines = ["# Dependency frontier", "",
         "Every missing type whose XNA public-signature dependencies are already complete, and the",
         "exact reason each one cannot yet be consumed. Regenerated by",
         "`tools/api_compat/analyze_dependencies.rb`.", "",
         "Consumable now: #{consumable.length}. Dependency-complete but blocked: #{dependency_complete.length - consumable.length}.", ""]
blocker_notes.each { |key, note| lines << "- `#{key}` — #{note}" }
lines << ""
lines << "`EVENT_PROJECTION` was retired in Foundation 20 and `BEHAVIOR_EVIDENCE` in Foundation 22."
lines << "The original XNA 4.0 Windows assemblies are on this host, hash-pinned by"
lines << "`tools/api_compat/reference/XNA_IL_PROVENANCE.md`, so \"behaviour lives in IL\" is work to do"
lines << "rather than missing input. Native reachability is measured from that IL:"
lines << "#{il_inventory.fetch("TYPES_NATIVE_REACHABLE")} of #{il_inventory.fetch("TYPES_WITH_IL")} reference types reach a native entry point."
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
    unless candidate.fetch("nativeReachableMethods").empty?
      detail << "native: #{candidate.fetch("nativeReachableMethods").first(4).join(", ")}"
    end
    detail << candidate.fetch("runtimeDataDetail") if candidate.fetch("runtimeDataDetail")
    unless candidate.fetch("behaviourBearingMembers").empty?
      detail << "IL to derive: #{candidate.fetch("behaviourBearingMembers").first(6).join(", ")}"
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
