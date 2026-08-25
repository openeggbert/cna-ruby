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
  # blocker: what is left of the retired EVENT_PROJECTION blocker is BCL_PROJECTION on the
  # EventHandler`1 support type and, for a class, BEHAVIOR_EVIDENCE on the raising IL.
  def blockers_for(type, mapped)
    blockers = []
    blockers << "BCL_PROJECTION" unless unmapped_bcl(type, mapped).empty?

    behaviour = type.fetch("members").select { |member| %w[constructor method].include?(member.fetch("kind")) }
    metadata_complete =
      case type.fetch("kind")
      when "enum", "interface" then true
      when "struct"
        behaviour.empty? &&
          type.fetch("members").all? { |member| member.fetch("kind") == "property" && !member.fetch("set") }
      else false
      end
    blockers << "BEHAVIOR_EVIDENCE" unless metadata_complete
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

  def test_every_type_completed_in_foundations_16_to_20_classifies_as_consumable
    mapped = mapped_bcl_from_complete_types
    assert_equal 33, CONSUMED.length

    CONSUMED.each do |name|
      type = BY_NAME.fetch(name)
      assert_empty blockers_for(type, mapped), "#{name} was shipped, so it must classify consumable"
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
  end

  def test_the_frontier_is_blocked_and_every_blocker_is_attributed
    assert_empty REPORT.fetch("consumableCandidates")
    assert_nil REPORT["selectedNext"]
    assert_equal "none-consumable", REPORT.fetch("selectionRoute")
    assert_equal 38, REPORT.fetch("dependencyCompleteCandidates").length
    assert_equal REPORT.fetch("dependencyCompleteCandidates").length,
                 REPORT.fetch("blockerSummary").values.sum
    refute REPORT.fetch("blockerSummary").key?("NONE")

    REPORT.fetch("dependencyCompleteCandidates").each do |candidate|
      refute_empty candidate.fetch("blockers"), candidate.fetch("name")
      refute_includes candidate.fetch("blockers"), "EVENT_PROJECTION", candidate.fetch("name")
      if candidate.fetch("blockers").include?("BEHAVIOR_EVIDENCE")
        assert candidate.fetch("behaviourBearingMembers").any? || candidate.fetch("kind") == "class",
               candidate.fetch("name")
      end
    end
    assert_equal %w[EVENT_PROJECTION], REPORT.fetch("retiredBlockers").keys
  end

  # Foundation 21 — the general exception base mapping is made, so the six XNA exception types whose
  # whole non-XNA surface is System.Exception / ExternalException are blocked on XNA IL alone.
  def test_exception_cluster_is_blocked_on_il_alone_once_the_base_mapping_exists
    assert_equal({"types" => CNA::Runtime::BclProjection::TYPES,
                  "exceptionBases" => CNA::Runtime::BclProjection::EXCEPTION_BASES},
                 REPORT.fetch("bclProjectionRegister"))

    exceptions = BY_NAME.keys.grep(/Exception\z/).sort
    assert_equal 8, exceptions.length
    exceptions.each { |name| assert_includes STRICT.fetch("missingTypeNames"), name }

    il_only = %w[
      Microsoft.Xna.Framework.Audio.InstancePlayLimitException
      Microsoft.Xna.Framework.Audio.NoAudioHardwareException
      Microsoft.Xna.Framework.Audio.NoMicrophoneConnectedException
      Microsoft.Xna.Framework.Graphics.DeviceLostException
      Microsoft.Xna.Framework.Graphics.DeviceNotResetException
      Microsoft.Xna.Framework.Graphics.NoSuitableGraphicsDeviceException
    ]
    il_only.each do |name|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_equal ["BEHAVIOR_EVIDENCE"], candidate.fetch("blockers"), name
      assert_empty candidate.fetch("unmappedBclTypes"), name
      assert_equal [".ctor"], candidate.fetch("behaviourBearingMembers"), name
      # Every declared member is a constructor: nothing but construction is left to establish.
      assert(BY_NAME.fetch(name).fetch("members").all? { |member| member.fetch("kind") == "constructor" }, name)
    end

    # The two serialisable exceptions still need a BCL cluster this milestone deliberately skips.
    %w[
      Microsoft.Xna.Framework.Content.ContentLoadException
      Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException
    ].each do |name|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_includes candidate.fetch("blockers"), "BCL_PROJECTION", name
      assert_includes candidate.fetch("unmappedBclTypes"), "System.Runtime.Serialization.SerializationInfo", name
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
    assert_equal ["BEHAVIOR_EVIDENCE"], window.fetch("blockers")
    assert_empty window.fetch("unmappedBclTypes")

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
      "Microsoft.Xna.Framework.GameWindow" => "BEHAVIOR_EVIDENCE",
      "Microsoft.Xna.Framework.Audio.Microphone" => "BCL_PROJECTION",
      "Microsoft.Xna.Framework.Input.Touch.TouchLocation" => "BEHAVIOR_EVIDENCE",
      "Microsoft.Xna.Framework.Graphics.PresentationParameters" => "BEHAVIOR_EVIDENCE",
      "Microsoft.Xna.Framework.Audio.AudioListener" => "BEHAVIOR_EVIDENCE",
      "Microsoft.Xna.Framework.Graphics.DeviceLostException" => "BEHAVIOR_EVIDENCE",
      "Microsoft.Xna.Framework.Content.ContentSerializerAttribute" => "BCL_PROJECTION",
      "Microsoft.Xna.Framework.TitleContainer" => "BCL_PROJECTION"
    }.each do |name, expected|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_includes candidate.fetch("blockers"), expected, name
    end
  end

  def test_touch_location_is_blocked_only_on_retained_assembly_evidence
    # It became dependency-complete because Foundation 17 completed TouchLocationState, and its
    # signature names no unmapped BCL type. What it still needs is XNA IL for Equals, GetHashCode,
    # ToString and TryGetPreviousLocation, which this host does not carry.
    candidate = REPORT.fetch("dependencyCompleteCandidates")
                      .find { |item| item.fetch("name") == "Microsoft.Xna.Framework.Input.Touch.TouchLocation" }
    refute_nil candidate
    assert_equal ["BEHAVIOR_EVIDENCE"], candidate.fetch("blockers")
    assert_empty candidate.fetch("unmappedBclTypes")
    assert_empty candidate.fetch("eventMembers")
    assert_includes candidate.fetch("dependencies"), "Microsoft.Xna.Framework.Input.Touch.TouchLocationState"
    assert_includes candidate.fetch("behaviourBearingMembers"), "TryGetPreviousLocation"
    assert_includes candidate.fetch("behaviourBearingMembers"), "GetHashCode"
  end
end
