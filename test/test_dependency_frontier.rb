# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundations 19 and 20 — the dependency frontier blocker register.
#
# tools/api_compat/analyze_dependencies.rb classifies every dependency-complete missing type by why
# it cannot yet be consumed. This test pins that classification two ways: the rule must agree with
# the generated report, and it must retroactively classify every type completed in Foundations 16
# to 20 as consumable. If the rule ever drifts so that already-shipped work would have been called
# blocked — or blocked work would have been called consumable — this fails.
#
# Foundation 20 retired the EVENT_PROJECTION blocker: declaring a CLR event is no longer a reason
# to defer a type, because one CLR event now projects to one Ruby event reader over
# CNA::Runtime::Event and the API verifier measures it.
class DependencyFrontierTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  REPORT = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)

  BY_NAME = REFERENCE.fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  # Everything closed by the three preceding milestones.
  CONSUMED = (
    JSON.parse(ROOT.join("behavior", "xna40-pure-managed-enum-batch-values.json").read)
        .fetch("observations").map { |item| item.fetch("args").first } +
    %w[
      Microsoft.Xna.Framework.Input.Touch.TouchLocationState
      Microsoft.Xna.Framework.Input.Touch.GestureType
      Microsoft.Xna.Framework.Input.Touch.TouchPanelCapabilities
      Microsoft.Xna.Framework.IGameComponent
      Microsoft.Xna.Framework.IGraphicsDeviceManager
      Microsoft.Xna.Framework.Graphics.IEffectMatrices
      Microsoft.Xna.Framework.Graphics.IEffectFog
      Microsoft.Xna.Framework.IUpdateable
      Microsoft.Xna.Framework.IDrawable
      Microsoft.Xna.Framework.Audio.InstancePlayLimitException
      Microsoft.Xna.Framework.Audio.NoAudioHardwareException
      Microsoft.Xna.Framework.Audio.NoMicrophoneConnectedException
      Microsoft.Xna.Framework.Graphics.DeviceLostException
      Microsoft.Xna.Framework.Graphics.DeviceNotResetException
      Microsoft.Xna.Framework.Graphics.NoSuitableGraphicsDeviceException
    ]
  ).compact.uniq.freeze

  def signatures_of(type)
    values = [type["baseType"], *type.fetch("directInterfaces", [])]
    type.fetch("members").each do |member|
      values.concat([member["type"], member["returnType"]])
      values.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
    end
    values.compact
  end

  def unmapped_bcl(type, mapped)
    signatures_of(type).filter_map do |signature|
      stripped = signature.sub(/&\z/, "")
      next if BY_NAME.keys.any? { |name| stripped.include?(name) }
      next if mapped.include?(stripped)

      stripped
    end.uniq.sort
  end

  # The same rule the tool applies, restated independently here. Declaring a CLR event is not a
  # blocker (retired in Foundation 20) and neither is declaring a constructor or method (retired in
  # Foundation 22, once the hash-pinned original assemblies were located): what blocks a candidate
  # is an unmapped BCL type, absent IL, IL that reaches a native entry point, or values only a
  # device or media stack can supply.
  def blockers_for(type, mapped)
    name = type.fetch("name")
    blockers = []
    blockers << "BCL_PROJECTION" unless unmapped_bcl(type, mapped).empty?

    behaviour = type.fetch("members").select { |member| %w[constructor method].include?(member.fetch("kind")) }
    il = IL.fetch("types")[name]
    blockers << "IL_UNAVAILABLE" if il.nil? && !behaviour.empty?
    blockers << "NATIVE_RUNTIME" if il && il.fetch("nativeReachable")
    blockers << "RUNTIME_DATA" if REPORT.fetch("runtimeDataRegister").key?(name)
    blockers
  end

  # The same two halves the tool uses, restated independently: types that are already complete, plus
  # the runtime's measured BCL projection register.
  def mapped_bcl_from_complete_types
    register = CNA::Runtime::BclProjection::TYPES.keys + CNA::Runtime::BclProjection::EXCEPTION_BASES.keys
    SIGNATURES.fetch("types").each_with_object(register.uniq.sort) do |type, found|
      next unless STRICT.fetch("completeTypeNames").include?(type.fetch("name"))

      signatures_of(type).each do |signature|
        stripped = signature.sub(/&\z/, "")
        found << stripped unless BY_NAME.keys.any? { |name| stripped.include?(name) }
      end
    end.uniq.sort
  end

  def test_report_is_the_current_schema_and_agrees_with_the_independent_rule
    assert_equal 3, REPORT.fetch("schemaVersion")
    mapped = mapped_bcl_from_complete_types
    assert_equal mapped, REPORT.fetch("mappedBclTypes")

    REPORT.fetch("dependencyCompleteCandidates").each do |candidate|
      type = BY_NAME.fetch(candidate.fetch("name"))
      assert_equal blockers_for(type, mapped), candidate.fetch("blockers"), candidate.fetch("name")
      assert_equal unmapped_bcl(type, mapped), candidate.fetch("unmappedBclTypes"), candidate.fetch("name")
      assert_empty candidate.fetch("unmetDependencies"), candidate.fetch("name")
    end
  end

  # Foundation 22 — the pinned original assemblies were located by hash, so the IL inventory is
  # real evidence rather than an assumption.
  def test_the_il_inventory_is_hash_pinned_and_covers_the_reference_surface
    assert_equal 1, IL.fetch("schemaVersion")
    assert_equal REFERENCE.fetch("types").length, IL.fetch("REFERENCE_TYPES")
    assert_equal 250, IL.fetch("TYPES_WITH_IL")

    provenance = ROOT.join("tools", "api_compat", "reference", "XNA_IL_PROVENANCE.md").read
    IL.fetch("assemblies").each do |assembly|
      assert_equal 64, assembly.fetch("sha256").length, assembly.fetch("name")
      assert_equal "4.0.0.0", assembly.fetch("version")
      # Every hash the inventory reports is pinned in the committed provenance register.
      assert_includes provenance, assembly.fetch("sha256"), assembly.fetch("name")
      assert_includes provenance, assembly.fetch("name")
    end
    # The two hashes every earlier milestone cited as sourceAssemblySha256 are in the register.
    assert_includes provenance, "38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130"
    assert_includes provenance, "560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55"
    # No Microsoft-owned bytes and no machine-local path may be committed.
    refute_match(%r{/home/|/rv/|/tmp/}, provenance)
    refute_match(%r{/home/|/rv/|/tmp/}, ROOT.join("docs", "generated", "xna-il-inventory.json").read)

    assert_equal REPORT.fetch("ilProvenance").fetch("assemblies"), IL.fetch("assemblies").length
    assert_equal REPORT.fetch("ilProvenance").fetch("typesNativeReachable"), IL.fetch("TYPES_NATIVE_REACHABLE")
  end

  # The classifier must agree with what this binding already knows is native.
  def test_native_reachability_agrees_with_the_shipped_native_boundary
    native = IL.fetch("types").select { |_name, entry| entry.fetch("nativeReachable") }.keys
    # Every partial runtime type except the pure-managed GraphicsResource contract is native.
    %w[
      Microsoft.Xna.Framework.Game
      Microsoft.Xna.Framework.GraphicsDeviceManager
      Microsoft.Xna.Framework.Graphics.GraphicsDevice
      Microsoft.Xna.Framework.Graphics.Texture2D
      Microsoft.Xna.Framework.Graphics.SpriteBatch
    ].each { |name| assert_includes native, name, name }

    # The only complete types that are native-reachable are the three whose native routes this
    # binding really implements; every other complete type is pure managed.
    assert_equal %w[
      Microsoft.Xna.Framework.Graphics.Texture
      Microsoft.Xna.Framework.Input.GamePad
      Microsoft.Xna.Framework.Input.Mouse
    ], (STRICT.fetch("completeTypeNames") & native).sort

    assert_operator IL.fetch("TYPES_NATIVE_REACHABLE"), :>, 0
    assert_operator IL.fetch("TYPES_NATIVE_REACHABLE"), :<, IL.fetch("TYPES_WITH_IL")
  end

  # Every runtime-data deferral must name a real type and say exactly what input is missing.
  def test_every_runtime_data_deferral_is_justified
    register = REPORT.fetch("runtimeDataRegister")
    refute_empty register
    register.each do |name, justification|
      assert BY_NAME.key?(name), name
      refute_empty justification.to_s, name
      refute_includes STRICT.fetch("completeTypeNames"), name, name
      # A runtime-data deferral is about missing values, never about missing IL.
      assert IL.fetch("types").key?(name), name
    end
  end

  def test_every_type_completed_in_foundations_16_to_22_classifies_as_consumable
    mapped = mapped_bcl_from_complete_types
    assert_equal 39, CONSUMED.length

    CONSUMED.each do |name|
      type = BY_NAME.fetch(name)
      assert_empty blockers_for(type, mapped), "#{name} was shipped, so it must classify consumable"
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
  end

  def test_the_frontier_has_a_measured_work_queue_and_every_blocker_is_attributed
    assert_equal 32, REPORT.fetch("dependencyCompleteCandidates").length
    assert_equal REPORT.fetch("dependencyCompleteCandidates").length,
                 REPORT.fetch("blockerSummary").values.sum
    assert_equal 7, REPORT.fetch("consumableCandidates").length
    assert_equal REPORT.fetch("consumableCandidates").length, REPORT.fetch("blockerSummary").fetch("NONE")
    assert_equal "global-consumable-rank", REPORT.fetch("selectionRoute")
    refute_nil REPORT["selectedNext"]

    REPORT.fetch("dependencyCompleteCandidates").each do |candidate|
      %w[EVENT_PROJECTION BEHAVIOR_EVIDENCE].each do |retired|
        refute_includes candidate.fetch("blockers"), retired, candidate.fetch("name")
      end
      # Declaring a constructor or method is now a work marker, never a blocker.
      if candidate.fetch("ilDerivationRequired")
        refute_empty candidate.fetch("behaviourBearingMembers"), candidate.fetch("name")
      end
      assert candidate.fetch("ilAvailable") || candidate.fetch("blockers").include?("IL_UNAVAILABLE"),
             candidate.fetch("name")
      if candidate.fetch("blockers").include?("NATIVE_RUNTIME")
        refute_empty candidate.fetch("nativeReachableMethods"), candidate.fetch("name")
      end
      if candidate.fetch("blockers").include?("RUNTIME_DATA")
        refute_nil candidate.fetch("runtimeDataDetail"), candidate.fetch("name")
      end
    end
    assert_equal %w[BEHAVIOR_EVIDENCE EVENT_PROJECTION], REPORT.fetch("retiredBlockers").keys.sort
  end

  # Every consumable candidate really is pure managed, hash-pinned and dependency-complete.
  def test_every_consumable_candidate_is_pure_managed_with_available_il
    assert_equal %w[
      Microsoft.Xna.Framework.Audio.AudioEmitter
      Microsoft.Xna.Framework.Audio.AudioListener
      Microsoft.Xna.Framework.GameComponentCollectionEventArgs
      Microsoft.Xna.Framework.Graphics.DisplayMode
      Microsoft.Xna.Framework.Graphics.PresentationParameters
      Microsoft.Xna.Framework.Input.Touch.GestureSample
      Microsoft.Xna.Framework.Input.Touch.TouchLocation
    ], REPORT.fetch("consumableCandidates").map { |candidate| candidate.fetch("name") }.sort

    REPORT.fetch("consumableCandidates").each do |candidate|
      name = candidate.fetch("name")
      assert_empty candidate.fetch("blockers"), name
      assert_empty candidate.fetch("unmetDependencies"), name
      assert_empty candidate.fetch("unmappedBclTypes"), name
      assert candidate.fetch("ilAvailable"), name
      entry = IL.fetch("types").fetch(name)
      refute entry.fetch("nativeReachable"), name
      assert_includes IL.fetch("assemblies").map { |assembly| assembly.fetch("name") }, entry.fetch("assembly"), name
      refute_includes STRICT.fetch("completeTypeNames"), name, name
    end
  end

  # Foundation 22 — the pinned IL settled every XNA exception constructor, so six are complete and
  # only the two carrying a protected serialization constructor remain.
  def test_six_exception_types_are_complete_and_two_remain_on_the_serialization_cluster
    exceptions = BY_NAME.keys.grep(/Exception\z/).sort
    assert_equal 8, exceptions.length

    completed = %w[
      Microsoft.Xna.Framework.Audio.InstancePlayLimitException
      Microsoft.Xna.Framework.Audio.NoAudioHardwareException
      Microsoft.Xna.Framework.Audio.NoMicrophoneConnectedException
      Microsoft.Xna.Framework.Graphics.DeviceLostException
      Microsoft.Xna.Framework.Graphics.DeviceNotResetException
      Microsoft.Xna.Framework.Graphics.NoSuitableGraphicsDeviceException
    ]
    completed.each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      refute IL.fetch("types").fetch(name).fetch("nativeReachable"), name
    end

    (exceptions - completed).each do |name|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_equal ["BCL_PROJECTION"], candidate.fetch("blockers"), name
      assert_includes candidate.fetch("unmappedBclTypes"), "System.Runtime.Serialization.SerializationInfo", name
      assert candidate.fetch("ilAvailable"), name
    end
  end

  def test_the_event_args_projection_is_visible_to_the_frontier
    assert_includes REPORT.fetch("mappedBclTypes"), "System.EventArgs"
    %w[
      Microsoft.Xna.Framework.GameComponentCollectionEventArgs
      Microsoft.Xna.Framework.Graphics.ResourceCreatedEventArgs
      Microsoft.Xna.Framework.Graphics.ResourceDestroyedEventArgs
    ].each do |name|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      refute_includes candidate.fetch("unmappedBclTypes"), "System.EventArgs", name
      assert_equal "System.EventArgs", BY_NAME.fetch(name).fetch("baseType"), name
    end
  end

  # An event-declaring type is now blocked only for reasons that have nothing to do with events.
  def test_event_declaring_candidates_are_no_longer_blocked_by_their_events
    events = REPORT.fetch("dependencyCompleteCandidates").reject { |item| item.fetch("eventMembers").empty? }
    assert_equal ["Microsoft.Xna.Framework.Audio.Microphone", "Microsoft.Xna.Framework.GameWindow"],
                 events.map { |item| item.fetch("name") }.sort

    window = events.find { |item| item.fetch("name") == "Microsoft.Xna.Framework.GameWindow" }
    assert_equal %w[ScreenDeviceNameChanged ClientSizeChanged OrientationChanged], window.fetch("eventMembers")
    assert_equal ["RUNTIME_DATA"], window.fetch("blockers")
    assert_empty window.fetch("unmappedBclTypes")
    assert_includes window.fetch("runtimeDataDetail"), "window"

    # Completing IUpdateable/IDrawable is what projected the EventHandler`1 support type.
    assert_includes REPORT.fetch("mappedBclTypes"), "System.EventHandler`1[System.EventArgs]"
  end

  # The GameComponent family is the cluster event projection was expected to unlock. It stays out
  # for reasons the graph measures rather than for anything about events.
  def test_game_component_family_is_not_dependency_complete
    {
      "Microsoft.Xna.Framework.GameComponent" => %w[Microsoft.Xna.Framework.Game],
      "Microsoft.Xna.Framework.DrawableGameComponent" => %w[
        Microsoft.Xna.Framework.Game Microsoft.Xna.Framework.GameComponent
        Microsoft.Xna.Framework.Graphics.GraphicsDevice
      ],
      "Microsoft.Xna.Framework.GameComponentCollection" => %w[
        Microsoft.Xna.Framework.Game Microsoft.Xna.Framework.GameComponent
        Microsoft.Xna.Framework.GameComponentCollectionEventArgs
      ]
    }.each do |name, unmet|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      assert_nil candidate, "#{name} must not be dependency-complete"
      assert_includes STRICT.fetch("missingTypeNames"), name

      type = BY_NAME.fetch(name)
      assert_includes type.fetch("members").map { |member| member.fetch("kind") }, "event", name
      unmet.each { |dependency| refute_includes STRICT.fetch("completeTypeNames"), dependency, dependency }
    end

    # Game is one of the six deferred partial runtime types, so the whole family stays deferred.
    assert_includes STRICT.fetch("partialTypes").keys, "Microsoft.Xna.Framework.Game"
  end

  def test_named_frontier_examples_keep_their_expected_blocker
    {
      "Microsoft.Xna.Framework.GameWindow" => "RUNTIME_DATA",
      "Microsoft.Xna.Framework.Audio.Microphone" => "NATIVE_RUNTIME",
      "Microsoft.Xna.Framework.Graphics.EffectAnnotation" => "NATIVE_RUNTIME",
      "Microsoft.Xna.Framework.Graphics.TextureCollection" => "NATIVE_RUNTIME",
      "Microsoft.Xna.Framework.Audio.RendererDetail" => "RUNTIME_DATA",
      "Microsoft.Xna.Framework.Media.Video" => "RUNTIME_DATA",
      "Microsoft.Xna.Framework.Content.ContentSerializerAttribute" => "BCL_PROJECTION",
      "Microsoft.Xna.Framework.TitleContainer" => "BCL_PROJECTION"
    }.each do |name, expected|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_includes candidate.fetch("blockers"), expected, name
    end
  end

  def test_touch_location_is_now_consumable_from_pinned_il
    # It was deferred only because the retained assemblies were believed absent. They are not: the
    # Input.Touch assembly is hash-pinned, its IL carries every member, and none of it is native.
    candidate = REPORT.fetch("dependencyCompleteCandidates")
                      .find { |item| item.fetch("name") == "Microsoft.Xna.Framework.Input.Touch.TouchLocation" }
    refute_nil candidate
    assert_empty candidate.fetch("blockers")
    assert_empty candidate.fetch("unmappedBclTypes")
    assert_empty candidate.fetch("eventMembers")
    assert_includes candidate.fetch("dependencies"), "Microsoft.Xna.Framework.Input.Touch.TouchLocationState"
    assert_includes candidate.fetch("behaviourBearingMembers"), "TryGetPreviousLocation"
    assert_includes candidate.fetch("behaviourBearingMembers"), "GetHashCode"
    assert candidate.fetch("ilDerivationRequired")
    assert candidate.fetch("ilAvailable")
    assert_equal "Microsoft.Xna.Framework.Input.Touch.dll", candidate.fetch("ilAssembly")
    refute IL.fetch("types").fetch("Microsoft.Xna.Framework.Input.Touch.TouchLocation").fetch("nativeReachable")
  end
end
