# frozen_string_literal: true

require "json"
require "set"
require_relative "name_mapper"
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
#
# Having no public constructor is **not** on its own a reason to be here. Foundation 25 established
# that such a class projects with `new` made private, the way GraphicsResource and Texture already
# do, so that its public non-constructibility is part of the contract and a future producer has the
# internal path the CLR gives it. What keeps a type here is that its values, or the arguments its
# internal constructor needs, do not exist on this host.
RUNTIME_DATA = {
  "Microsoft.Xna.Framework.Audio.AudioCategory" => "an XACT AudioEngine category handle; SetVolume/Pause/Resume/Stop act on a live engine this binding does not have",
  "Microsoft.Xna.Framework.Media.MediaSource" => "GetAvailableMediaSources enumerates the host media sources; no media stack has been queried",
  "Microsoft.Xna.Framework.Media.Video" => "its internal constructor takes a GraphicsDevice, one of the deferred partial runtime types, and builds a Duration from tick components the content pipeline supplies; no producer exists"
}.freeze

# VisualizationData was in this register until Foundation 51, on the reasoning that it is "filled by
# MediaPlayer.GetVisualizationData from live playback". That is a statement about the *filler*, not
# the type: its constructor is public and seventy-five bytes, allocating two float[0x100] arrays and
# wrapping each in a ReadOnlyCollection<float>, and it reaches nothing. Foundation 24 settled the
# same case for AudioListener and AudioEmitter -- managed holders a consumer can build and set,
# whose effect nothing here ever hears.

# RendererDetail was in this register until Foundation 50, on the reasoning that "values come from
# XACT audio renderer enumeration; no audio engine exists in this binding and no renderer has been
# enumerated". That is a statement about the *producer*, not the type: the pinned Xact.dll shows a
# sealed value type over two string fields whose seven identities are field reads, ordinal string
# comparisons and an XOR, with not one native reach among them. Foundation 25 settled the same case
# for Graphics.DisplayMode -- a constructor-free class projects with construction made private, and
# completing it implies nothing about the enumerator that would fill it.

# Native frontier 4 audited the audio-playback cluster and did *not* move it here, deliberately.
# `Audio.SoundEffectInstance` reports `NATIVE_RUNTIME`, which means only that its own IL reaches a
# native entry point -- the reasoning corrected twice already. The canonical path is complete in the
# ABI and executes end to end, and `cna_audio_get_capabilities` reports playback available; what is
# missing is the observable behaviour those routes document. `SoundState` never leaves `Stopped`
# through play, frame steps, a dispatcher pump, pause, resume and stop, a full second of PCM answers
# a zero duration, and `set_is_looped` is refused in every state -- identically with `CNA_AUDIO`
# unset and with `CNA_AUDIO=SDL`, so it is not the null backend. That is neither a missing runtime
# value, which is what this register is for, nor a missing route: it is an upstream CNA condition,
# recorded as the `audio.sound-effect-playback` capability and measured in
# `docs/generated/audio-native-report.json`. `Audio.Cue`, `Graphics.EffectAnnotation` and
# `Graphics.TextureCollection` were audited with it and each has its own distinct reason -- a missing
# `.xgs` asset and two missing types, a compiled effect with parameters, and no CNA route at all.

# GameWindow was here until Foundation 48, on the reasoning that it is "an abstract window whose
# concrete implementation is the platform window behind Game; projecting it would require the
# deferred Game/window runtime". That reasoning was wrong in the same way FrameworkDispatcher's was:
# the concrete implementation this binding needs is CNA's, and the canonical C ABI already exposes
# every member XNA leaves abstract -- title, allow-user-resizing, client bounds, current
# orientation, the native handle, the screen device name, the screen-device-change pair and the
# three window events. Every one of those routes is addressed through the *game* handle, so there is
# no second lifetime to reconcile and no producer to invent. The values HEADLESS answers -- a zero
# rectangle, a zero handle, an empty device name -- are the host's honest report of a platform with
# no native window, not missing input, which is what this register is for.

# FrameworkDispatcher was here until the native/CNA expansion audit, on the reasoning that "Update
# pumps the live audio and media services; with neither present it would be a no-op pretending to
# be a pump". That reasoning was wrong about where the pump lives. This binding's audio and media
# *are* CNA, and the canonical C ABI exposes `cna_framework_dispatcher_update` -- the same drain
# CNA's own game loop drives. Forwarding to it is the faithful analogue of draining the XNA queue,
# so the projection performs a real pump rather than standing in for one. What is genuinely absent
# is the managed fan-out, because none of the five sinks the IL dispatches to is projected yet --
# and an absent subscriber is not a missing runtime value, which is what this register is for.

reference_by_name = reference.fetch("types").to_h { |type| [type.fetch("name"), type] }
target_names = target.fetch("types").map { |type| type.fetch("name") }
complete_names = strict.fetch("completeTypeNames")

# A type name occurring inside a signature counts as a dependency only when it is bounded on both
# sides. Testing a prefix alone -- `signature.include?("[#{name}")` -- matched any *longer* name
# that merely starts with the shorter one, and the Game family is full of them: the signature
# `System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]` was reported as
# naming `Game` and `GameComponent` as well, so `GameComponentCollection` was recorded as blocked on
# two types it never mentions. This is the same class of blind spot Native frontiers 2 and 3 closed
# in the IL extractor -- a scanner anchored on one side of a token -- seen in the signature graph.
#
# The delimiters are the ones a signature really uses: a constructed generic opens with `[`,
# separates with `,` and closes with `]`; an array appends `[]`; a byref appends `&`. A nested type
# spelled `Parent+Child` is deliberately *not* matched by its parent's name, exactly as before: the
# declaring-type edge is added separately by `type_dependencies`.
OPENING = ["[", ","].freeze
CLOSING = ["]", ",", "[", "&"].freeze

extract_types = lambda do |signature|
  next [] unless signature

  reference_by_name.keys.select do |name|
    next true if signature == name

    offset = 0
    bounded = false
    while (index = signature.index(name, offset))
      before = index.zero? ? nil : signature[index - 1]
      after = signature[index + name.length]
      bounded = (before.nil? || OPENING.include?(before)) && (after.nil? || CLOSING.include?(after))
      break if bounded

      offset = index + 1
    end
    bounded
  end
end

type_dependencies = lambda do |type|
  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  # A nested type's declaring type is a public-signature dependency even when no member mentions
  # it: `TouchCollection+Enumerator` cannot be named, constructed or read without `TouchCollection`,
  # whose `Item` and `Count` its `Current` and `MoveNext` call. Without this the pair looks like one
  # consumable type and one blocked one, when in truth neither can be closed without the other.
  # This is the same blind spot Foundation 26 closed for a constructed generic hiding its
  # definition behind an XNA type argument, one level up.
  declaring = type.fetch("name")[/\A(.+)\+[^+]+\z/, 1]
  signatures << declaring if declaring
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

# The member-level half of the dependency graph, from the IL inventory.
#
# The signature graph can only see the *types* a public signature names, so it answers "X depends on
# Game" and stops. When that dependency is one of the deferred partial runtime types, the answer is
# too coarse to act on: a partial type is a real Ruby class with a real surface, and what a
# dependent needs is the members it actually calls, not all of them. Foundation 39 records those
# edges, so the question can now be asked.
#
# This does **not** widen the candidate policy. `dependencyComplete` still means every dependency is
# complete, and `selectedNext` still comes from `consumableCandidates`. What is added is a separate,
# named report: for an unmet dependency that is *partial*, which of its members this type's own IL
# reaches, and whether each of those is complete. A type whose every reached member is complete is
# reported as `partialDependencySatisfied`, which is a statement a maintainer can act on rather than
# a policy this tool applies on its own.
member_edges = il_types.transform_values { |entry| entry.fetch("externalMemberReferences", []) }
partial_names = strict.fetch("partialTypes").keys
partial_missing = strict.fetch("partialTypes").transform_values do |labels|
  labels.map { |label| label.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
end

reached_members = lambda do |name, dependency|
  member_edges.fetch(name, []).filter_map do |edge|
    owner, member = edge.split("::", 2)
    next unless owner == dependency

    member.sub(/\Aget_|\Aset_|\Aadd_|\Aremove_/, "")
  end.uniq.sort
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
  # A dependency the *IL* reaches that no public signature names. DrawableGameComponent is the case
  # that forced this: its whole device-service handshake lives in a private field, so the signature
  # graph could not see `IGraphicsDeviceService` at all and reported the type as blocked only on
  # partial dependencies -- when in truth its `Initialize` throws
  # InvalidOperationException(MissingGraphicsDeviceService) unless a producer registers one, and no
  # producer exists. Ignoring these would let a type look ready that cannot be initialised.
  il_only = member_edges.fetch(name, []).map { |edge| edge.split("::", 2).first }.uniq
                        .select { |owner| reference_by_name.key?(owner) }
                        .reject { |owner| owner == name || dependencies.include?(owner) }
  il_only_unmet = (il_only - complete_names).sort
  partial_unmet = unmet & partial_names
  missing_unmet = unmet - partial_names
  partial_detail = partial_unmet.to_h do |dependency|
    reached = reached_members.call(name, dependency)
    still_missing = reached & partial_missing.fetch(dependency, [])
    [dependency, {"reachedMembers" => reached, "reachedButMissing" => still_missing.sort}]
  end
  {
    "name" => name,
    "kind" => type.fetch("kind"),
    "expectedRubyIdentities" => expected,
    "dependencies" => dependencies.sort,
    "unmetDependencies" => unmet.sort,
    "missingTypeDependencies" => missing_unmet.sort,
    "partialTypeDependencies" => partial_detail,
    "ilOnlyDependencies" => il_only.sort,
    "ilOnlyUnmetDependencies" => il_only_unmet,
    # True when every unmet dependency is a *partial* type, every member of it this type's own IL
    # reaches is already complete, and the IL reaches no unmet type the signature graph never saw.
    # It is reported, never acted on.
    "partialDependencySatisfied" => missing_unmet.empty? && !partial_unmet.empty? &&
                                    il_only_unmet.empty? &&
                                    partial_detail.values.all? { |detail| detail.fetch("reachedButMissing").empty? },
    "partialRemainderReverseEdges" => reverse,
    "dependencyComplete" => unmet.empty?
  }
end

rank = lambda do |candidate|
  [candidate.fetch("expectedRubyIdentities"), candidate.fetch("name")]
end

# A constructed generic hides its definition behind its type arguments: the signature
# `System.Collections.Generic.List`1[Microsoft.Xna.Framework.Graphics.DisplayMode]` names an XNA
# type, but what it actually requires is a projection of `List`1`. Every signature is therefore
# reduced to the BCL identities it really names — the outer definition, plus the whole signature
# when it names no XNA type at all — and the same reduction is applied on both sides, so a generic
# definition a complete type already projects counts as mapped.
bcl_identities = lambda do |signature|
  stripped = signature.sub(/&\z/, "")
  outer = stripped.split("[", 2).first
  # Once the register projects a generic *definition*, a constructed form of it is no longer
  # opaque: what `ReadOnlyCollection`1[System.Single]` requires is the definition's projection plus
  # a projection of Single, and reporting the whole constructed string as one unmapped identity
  # hides that. This is the Foundation 26 blind spot seen from the other side — there a constructed
  # generic hid its definition behind an XNA type argument, here it hides its already-mapped
  # definition behind a BCL one. A generic the register does *not* project stays opaque, because
  # then the whole constructed form really is what is missing.
  if outer != stripped && CNA::Runtime::BclProjection::TYPES.key?(outer)
    return ([outer] + CNA::Runtime::BclProjection.element_types(stripped).flat_map { |argument|
      bcl_identities.call(argument)
    }).uniq
  end

  identities = []
  identities << stripped unless reference_by_name.keys.any? { |name| stripped.include?(name) }
  identities << outer if outer != stripped && !reference_by_name.key?(outer)
  identities.uniq
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
  signatures.compact.each { |signature| found.concat(bcl_identities.call(signature)) }
end.uniq.sort

unmapped_bcl = lambda do |type|
  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  type.fetch("members").each do |member|
    signatures.concat([member["type"], member["returnType"]])
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
  end
  signatures.compact.flat_map { |signature| bcl_identities.call(signature) }
            .reject { |identity| mapped_bcl.include?(identity) }.uniq.sort
end

# Which interfaces something in this projection actually conforms to.
#
# Foundation 40 forced this. Completing an interface as an abstract contract makes it a *complete
# type*, so every structural test the graph applies starts passing for a dependent that calls into
# it -- while nothing at all provides the service. `DrawableGameComponent` is the case: the moment
# `IGraphicsDeviceService` existed it reported `partialDependencySatisfied` with no blocker, even
# though its `Initialize` throws `InvalidOperationException(MissingGraphicsDeviceService)` unless a
# producer is registered. The type-level graph cannot see that, because a producer is not a type
# dependency: it is an *object* that conforms.
#
# So conformance is measured, not assumed. An interface has a producer when some type declares it
# in the pinned contract, is complete in this projection, **and** whose Ruby class actually includes
# the projected module. All three halves are required: the first is metadata, the second is this
# projection's own scoreboard, and the third is the only one that proves a live object would answer
# `is_a?`, which is what the GameServiceContainer projection of CLR assignability tests.
#
# This names no type and carries no allowlist. It is the same question asked of every interface.
interface_names = reference.fetch("types").select { |type| type.fetch("kind") == "interface" }
                           .map { |type| type.fetch("name") }.to_set

resolve_module = lambda do |clr_name|
  CNAApiCompat::NameMapper.runtime_constant_path(clr_name)
                          .split("::").reduce(Object) { |scope, segment| scope.const_get(segment, false) }
rescue NameError
  nil
end

interface_producers = interface_names.to_h do |interface|
  projected = resolve_module.call(interface)
  conformers = reference.fetch("types").select do |type|
    type.fetch("interfaces", []).include?(interface) &&
      complete_names.include?(type.fetch("name")) &&
      !projected.nil? &&
      (concrete = resolve_module.call(type.fetch("name"))) &&
      concrete.ancestors.include?(projected)
  end.map { |type| type.fetch("name") }
  [interface, conformers]
end

# Every interface a candidate's own IL calls a member of -- which is the precise test, because
# naming an interface in a signature requires no instance while calling one does.
reached_interfaces = lambda do |name|
  member_edges.fetch(name, []).map { |edge| edge.split("::", 2).first }
              .select { |owner| interface_names.include?(owner) }.uniq.sort
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
# INTERFACE_PRODUCER_MISSING
#                  the type's own IL calls members of an interface that nothing in this projection
#                  conforms to, so the type would compile and then raise on first use.
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
  producerless = reached_interfaces.call(name).reject { |interface| interface_producers.fetch(interface, []).any? }
  blockers << "INTERFACE_PRODUCER_MISSING" unless producerless.empty?

  {"blockers" => blockers, "unmappedBclTypes" => bcl,
   "reachedInterfaces" => reached_interfaces.call(name),
   "producerlessInterfaces" => producerless,
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
  "candidatePolicy" => "missing type; all XNA public-signature dependencies complete, which is a type-level test the member-level edges recorded in the IL inventory can now refine but deliberately do not relax; consumable only when no BCL_PROJECTION, IL_UNAVAILABLE, NATIVE_RUNTIME, RUNTIME_DATA or INTERFACE_PRODUCER_MISSING blocker applies; a selected partial remainder reverse edge wins the tie; then fewest expected Ruby identities",
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
  # Candidates the signature graph blocks only on a partial type, every member of which their own IL
  # already finds complete. Reported for a maintainer to act on; the selection route never uses it.
  "partialDependencySatisfiedCandidates" => candidates.select { |candidate| candidate.fetch("partialDependencySatisfied") }
                                                      .map { |candidate| candidate.merge(classify.call(reference_by_name.fetch(candidate.fetch("name")))) }
                                                      .sort_by(&rank),
  # The other half of the same measurement: a candidate the signature graph would have called
  # satisfied, held back by a type only its IL reaches. Reported so the near-miss is visible rather
  # than silently absent from the list above.
  "ilOnlyBlockedCandidates" => candidates.select do |candidate|
    candidate.fetch("missingTypeDependencies").empty? && !candidate.fetch("ilOnlyUnmetDependencies").empty?
  end.map { |candidate| candidate.merge(classify.call(reference_by_name.fetch(candidate.fetch("name")))) }.sort_by(&rank),
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
