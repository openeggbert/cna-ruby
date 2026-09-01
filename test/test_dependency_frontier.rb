# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
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
      Microsoft.Xna.Framework.Input.Touch.TouchLocation
      Microsoft.Xna.Framework.Input.Touch.GestureSample
      Microsoft.Xna.Framework.Audio.AudioListener
      Microsoft.Xna.Framework.Audio.AudioEmitter
      Microsoft.Xna.Framework.Graphics.PresentationParameters
      Microsoft.Xna.Framework.GameComponentCollectionEventArgs
      Microsoft.Xna.Framework.Graphics.DisplayMode
      Microsoft.Xna.Framework.Graphics.ResourceCreatedEventArgs
      Microsoft.Xna.Framework.Graphics.ResourceDestroyedEventArgs
      Microsoft.Xna.Framework.Graphics.DisplayModeCollection
      Microsoft.Xna.Framework.Content.ContentSerializerAttribute
      Microsoft.Xna.Framework.Content.ContentSerializerCollectionItemNameAttribute
      Microsoft.Xna.Framework.Content.ContentSerializerIgnoreAttribute
      Microsoft.Xna.Framework.Content.ContentSerializerRuntimeTypeAttribute
      Microsoft.Xna.Framework.Content.ContentSerializerTypeVersionAttribute
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

  # The same reduction the tool applies: a constructed generic hides its definition behind its type
  # arguments, so each signature yields the whole string when it names no XNA type, plus the outer
  # definition whenever there is one.
  def bcl_identities(signature)
    stripped = signature.sub(/&\z/, "")
    outer = stripped.split("[", 2).first
    # Foundation 29: once the register projects a generic definition, a constructed form of it is
    # no longer opaque -- it requires the definition's projection plus its type arguments'. A
    # generic the register does not project stays opaque, because then the whole constructed form
    # really is what is missing.
    if outer != stripped && (CNA::Runtime::BclProjection::TYPES.key?(outer) ||
                             CNA::Runtime::BclProjection.structural_collapse?(outer))
      return ([outer] + CNA::Runtime::BclProjection.element_types(stripped)
                                                   .flat_map { |argument| bcl_identities(argument) }).uniq
    end

    # A CLR generic parameter placeholder is a language construct, not a type identity. `!!0` names
    # a generic *method*'s parameter and `!0` a generic type's; what resolves the first is the
    # generic-method projection rule and the second `projects_elements`, and neither is a BCL type
    # anything could ever map. Restated here rather than delegated, so the tool and the test have to
    # agree on the spelling as well as on the idea.
    return [] if stripped.match?(/\A!!?\d+(\[\])*\z/)

    identities = []
    identities << stripped unless BY_NAME.keys.any? { |name| stripped.include?(name) }
    identities << outer if outer != stripped && !BY_NAME.key?(outer)
    identities.uniq
  end

  def unmapped_bcl(type, mapped)
    signatures_of(type).flat_map { |signature| bcl_identities(signature) }
                       .reject { |identity| mapped.include?(identity) }.uniq.sort
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
  # the runtime's measured BCL projection register. The register is all three of its parts -- a
  # projected type, an exception base and a *structural collapse* each settle an identity, and a
  # collapse settles it precisely by deciding no constant is needed. Until Foundation 36 the one
  # collapsed identity was also reachable from a complete type's signatures, so leaving it out here
  # happened to agree; System.IDisposable is declared only by types that are missing or partial, so
  # it no longer does.
  def mapped_bcl_from_complete_types
    register = CNA::Runtime::BclProjection::TYPES.keys +
               CNA::Runtime::BclProjection::EXCEPTION_BASES.keys +
               CNA::Runtime::BclProjection::STRUCTURAL_COLLAPSE.keys
    SIGNATURES.fetch("types").each_with_object(register.uniq.sort) do |type, found|
      next unless STRICT.fetch("completeTypeNames").include?(type.fetch("name"))

      signatures_of(type).each { |signature| found.concat(bcl_identities(signature)) }
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

  # Native frontier 2 — the extractor reads nested and generic type declarations, which it had
  # silently folded into their parents since Foundation 22.
  def test_the_extractor_addresses_nested_and_generic_type_declarations
    %w[
      Microsoft.Xna.Framework.Graphics.ModelBoneCollection+Enumerator
      Microsoft.Xna.Framework.Graphics.ModelEffectCollection+Enumerator
      Microsoft.Xna.Framework.Graphics.ModelMeshCollection+Enumerator
      Microsoft.Xna.Framework.Graphics.ModelMeshPartCollection+Enumerator
      Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator
      Microsoft.Xna.Framework.Content.ContentTypeReader`1
      Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector`1
    ].each do |name|
      entry = IL.fetch("types").fetch(name)
      assert_operator entry.fetch("ilLines"), :>, 0, name
      refute_nil entry.fetch("declaredMethods"), name
    end

    # A declaring type counts only what it declares itself. Both of these previously absorbed a
    # nested type's fields: TouchCollection reported 16 for its own 11, and FrameworkDispatcher 5
    # for its own 3, because the two ManagedCallAndArg fields were counted as its own.
    assert_equal 11, IL.fetch("types")
                       .fetch("Microsoft.Xna.Framework.Input.Touch.TouchCollection")
                       .fetch("declaredFields")
    assert_equal 3, IL.fetch("types")
                      .fetch("Microsoft.Xna.Framework.FrameworkDispatcher")
                      .fetch("declaredFields")

    # A nested type owns its own methods and constructor rather than lending them to its parent.
    enumerator = IL.fetch("types")
                   .fetch("Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator")
    assert_equal 5, enumerator.fetch("declaredMethods")
    assert_equal 2, enumerator.fetch("declaredFields")
    assert_equal ["assembly"], enumerator.fetch("constructors").map { |ctor| ctor.fetch("access") }
  end

  # Native frontier 3 — the extractor reads a method name past a `modopt(...)`/`modreq(...)` return
  # modifier, which is how every mixed-mode C++/CLI thunk in these assemblies is declared.
  #
  # The defect was silent and expensive: `.method public hidebysig static int32
  # modopt([mscorlib]...IsLong) Play(uint32)` was recorded under the name `modopt`, while every call
  # site resolved to `...::Play`, so every edge into XNA's native-methods classes dangled and the
  # types that call them looked pure managed. This pins both halves — the name rule itself, and the
  # reachability it restores.
  def test_the_extractor_reads_a_method_name_past_a_return_type_modifier
    name_of = lambda do |header|
      searchable = header.gsub(/(?:pinvokeimpl|marshal|modopt|modreq)\s*\([^)]*\)/, " ")
      searchable[/([A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/, 1]
    end
    assert_equal "Play",
                 name_of.call("public hidebysig static int32 " \
                              "modopt([mscorlib]System.Runtime.CompilerServices.IsLong) Play(uint32 h)")
    assert_equal "Apply3D",
                 name_of.call("public hidebysig static int32 modreq([mscorlib]System.Object) " \
                              "Apply3D(uint32 h, float32 x)")
    # The two forms the extractor always handled still work.
    assert_equal "GetKeyboardState",
                 name_of.call('public hidebysig static pinvokeimpl("user32.dll" winapi) ' \
                              "int32 GetKeyboardState(uint8[] state)")
    assert_equal "Ordinary", name_of.call("public hidebysig instance void Ordinary(int32 value)")

    # And the reachability it restores, on the type that exposed it. SoundEffectInstance's own IL
    # calls SoundEffectUnsafeNativeMethods::Play/Stop/Pause/SetVolume, whose bodies are
    # `calli unmanaged thiscall`.
    entry = IL.fetch("types").fetch("Microsoft.Xna.Framework.Audio.SoundEffectInstance")
    assert entry.fetch("nativeReachable")
    refute_empty entry.fetch("nativeReachableMethods")
    assert_equal 254, IL.fetch("NATIVE_ENTRY_POINT_METHODS") if IL.key?("NATIVE_ENTRY_POINT_METHODS")
    assert_equal 77, IL.fetch("TYPES_NATIVE_REACHABLE")
    # The correction added reachability and took none away.
    %w[
      Microsoft.Xna.Framework.Graphics.Texture
      Microsoft.Xna.Framework.Input.GamePad
      Microsoft.Xna.Framework.Input.Mouse
      Microsoft.Xna.Framework.Graphics.GraphicsDevice
    ].each { |name| assert IL.fetch("types").fetch(name).fetch("nativeReachable"), name }
    # Nothing in the pure-managed families gained it.
    %w[
      Microsoft.Xna.Framework.Vector2
      Microsoft.Xna.Framework.Matrix
      Microsoft.Xna.Framework.Input.Touch.TouchPanel
      Microsoft.Xna.Framework.GameServiceContainer
    ].each { |name| refute IL.fetch("types").fetch(name).fetch("nativeReachable"), name }
  end

  # Foundation 22 — the pinned original assemblies were located by hash, so the IL inventory is
  # real evidence rather than an assumption.
  def test_the_il_inventory_is_hash_pinned_and_covers_the_reference_surface
    assert_equal 1, IL.fetch("schemaVersion")
    assert_equal REFERENCE.fetch("types").length, IL.fetch("REFERENCE_TYPES")
    # Native frontier 2 made the extractor nested- and generic-aware. Every reference type is now
    # covered, where seven were previously reported as carrying no IL at all: the five nested
    # `+Enumerator` types, whose declarations `ikdasm` indents inside their parent and closes with
    # the short name, and the two generic definitions, which it declares as `Name`1<T>` and closes
    # as `Name`1`.
    assert_equal REFERENCE.fetch("types").length, IL.fetch("TYPES_WITH_IL")
    assert_equal 0, IL.fetch("TYPES_WITHOUT_IL")
    assert_empty IL.fetch("typesWithoutIl")

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

    # The only complete types that are native-reachable are the four whose native routes this
    # binding really implements; every other complete type is pure managed. FrameworkDispatcher
    # joined them in Native frontier 3, which is the honest reading: its drain reaches XACT through
    # SoundEffect.RecycleStoppedFireAndForgetInstances, and this binding's projection forwards to
    # the canonical CNA pump.
    # Game and ContentManager joined them when each was completed, and both belong: Game's IL
    # reaches the host and this projection is a façade over CNA's native Game, and ContentManager's
    # reaches the content pipeline, which is exactly the native route `Load<Texture2D>` calls. Every
    # entry on this list is a type whose native boundary the binding really implements, which is the
    # property the list exists to check -- not a count that must stay still.
    assert_equal %w[
      Microsoft.Xna.Framework.Audio.AudioCategory
      Microsoft.Xna.Framework.Audio.AudioEngine
      Microsoft.Xna.Framework.Audio.Cue
      Microsoft.Xna.Framework.Audio.DynamicSoundEffectInstance
      Microsoft.Xna.Framework.Audio.Microphone
      Microsoft.Xna.Framework.Audio.SoundBank
      Microsoft.Xna.Framework.Audio.SoundEffect
      Microsoft.Xna.Framework.Audio.SoundEffectInstance
      Microsoft.Xna.Framework.Audio.WaveBank
      Microsoft.Xna.Framework.Content.ContentManager
      Microsoft.Xna.Framework.FrameworkDispatcher
      Microsoft.Xna.Framework.Game
      Microsoft.Xna.Framework.GamerServices.GamerServicesComponent
      Microsoft.Xna.Framework.Graphics.Texture
      Microsoft.Xna.Framework.Graphics.TextureCollection
      Microsoft.Xna.Framework.Input.GamePad
      Microsoft.Xna.Framework.Input.Mouse
    ], (STRICT.fetch("completeTypeNames") & native).sort
    %w[
      Microsoft.Xna.Framework.FrameworkDispatcher
      Microsoft.Xna.Framework.Graphics.Texture
      Microsoft.Xna.Framework.Input.GamePad
      Microsoft.Xna.Framework.Input.Mouse
    ].each do |name|
      assert(CNA::Native::Manifest::FUNCTIONS.any? { |signature| signature.symbol.start_with?("cna_") },
             name)
    end

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

  def test_every_type_completed_in_foundations_16_to_27_classifies_as_consumable
    mapped = mapped_bcl_from_complete_types
    assert_equal 54, CONSUMED.length

    CONSUMED.each do |name|
      type = BY_NAME.fetch(name)
      assert_empty blockers_for(type, mapped), "#{name} was shipped, so it must classify consumable"
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
  end

  def test_the_frontier_has_a_measured_work_queue_and_every_blocker_is_attributed
    assert_equal 6, REPORT.fetch("dependencyCompleteCandidates").length
    assert_equal REPORT.fetch("dependencyCompleteCandidates").length,
                 REPORT.fetch("blockerSummary").values.sum
    # Foundation 31 completed the TouchCollection pair, which made TouchPanel consumable, and
    # Foundation 32 consumed it. The queue is empty again and every entry left is blocked.
    assert_equal 0, REPORT.fetch("consumableCandidates").length
    refute REPORT.fetch("blockerSummary").key?("NONE")
    assert_equal "none-consumable", REPORT.fetch("selectionRoute")
    assert_nil REPORT["selectedNext"]

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
    assert_empty REPORT.fetch("consumableCandidates")

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

    # The other two were held on the serialization cluster until Foundation 49 projected it, which
    # is the transition this measurement exists to make visible: they left the frontier by their
    # blocker being *resolved*, not by the rule being relaxed.
    (exceptions - completed).each do |name|
      refute(REPORT.fetch("dependencyCompleteCandidates").any? { |item| item.fetch("name") == name }, name)
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_includes REPORT.fetch("mappedBclTypes"), "System.Runtime.Serialization.SerializationInfo"
    end
  end

  def test_the_event_args_projection_is_visible_to_the_frontier
    assert_includes REPORT.fetch("mappedBclTypes"), "System.EventArgs"
    # Foundation 24 consumed the one EventArgs subclass with a public constructor.
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.GameComponentCollectionEventArgs"
    assert_equal CNA::Runtime::EventArgs,
                 Microsoft::Xna::Framework::GameComponentCollectionEventArgs.superclass

    # Foundation 25 consumed the remaining EventArgs subclasses, whose only constructor is internal.
    %w[
      Microsoft.Xna.Framework.Graphics.ResourceCreatedEventArgs
      Microsoft.Xna.Framework.Graphics.ResourceDestroyedEventArgs
    ].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal "System.EventArgs", BY_NAME.fetch(name).fetch("baseType"), name
      runtime = name.split(".").reduce(Object) { |scope, part| scope.const_get(part, false) }
      assert_equal CNA::Runtime::EventArgs, runtime.superclass, name
      # A CLR class with no public constructor projects with `new` made private.
      refute runtime.respond_to?(:new), name
    end
  end

  # An event-declaring type is now blocked only for reasons that have nothing to do with events.
  def test_event_declaring_candidates_are_no_longer_blocked_by_their_events
    events = REPORT.fetch("dependencyCompleteCandidates").reject { |item| item.fetch("eventMembers").empty? }
    # Audio.Cue joined the list when AudioEmitter and AudioListener completed its dependencies.
    # GameWindow was the third until Foundation 48 built it, which is what an event-declaring
    # candidate reaching the frontier is for; DynamicSoundEffectInstance was the fourth, arriving
    # the same way when the audio cluster completed its base and leaving again when it was built,
    # and Microphone the fifth, whose BufferReady is now a projected event identity. WaveBank was
    # the sixth, arriving the way DynamicSoundEffectInstance did -- the XACT engine cluster
    # completed the AudioEngine its constructor names -- and then the banks and the cue were built
    # together, which emptied this list. Every event-declaring candidate the frontier ever raised
    # has now been consumed, so what is asserted is that emptiness rather than a name.
    assert_empty events.map { |item| item.fetch("name") }

    # Completing IUpdateable/IDrawable is what projected the EventHandler`1 support type.
    assert_includes REPORT.fetch("mappedBclTypes"), "System.EventHandler`1[System.EventArgs]"
  end

  # The GameComponent family is the cluster event projection was expected to unlock. Two of its
  # three members have since left it: GameComponentCollection in Foundation 35, because it never
  # depended on either component class -- see the extractor correction below -- and GameComponent
  # itself in Foundation 38, once Game.Components gave it a producer. DrawableGameComponent stays
  # out for a reason the graph measures rather than for anything about events.
  def test_game_component_family_is_not_dependency_complete
    {
      "Microsoft.Xna.Framework.DrawableGameComponent" => %w[
        Microsoft.Xna.Framework.Graphics.GraphicsDevice
      ]
    }.each do |name, unmet|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      assert_nil candidate, "#{name} must not be dependency-complete"
      assert_includes STRICT.fetch("missingTypeNames"), name

      type = BY_NAME.fetch(name)
      assert_includes type.fetch("members").map { |member| member.fetch("kind") }, "event", name
      unmet.each { |dependency| refute_includes STRICT.fetch("completeTypeNames"), dependency, dependency }
    end

    # Game *was* one of the deferred partial runtime types when this was written, and the point
    # was that a partial Game declaring Components and Services was already enough: what a missing
    # type needs is its *dependencies* complete. `Game.Content` has since completed Game outright,
    # which only strengthens that, so the assertion states the stronger fact.
    assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Game")
    %w[Microsoft.Xna.Framework.GameComponentCollection
       Microsoft.Xna.Framework.GameComponent].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_nil REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
    end
  end

  # Foundation 35 corrected the signature-graph extractor. A type name occurring inside a signature
  # was matched by an *unbounded prefix* test -- `signature.include?("[#{name}")` -- so any longer
  # name starting with a shorter one matched it too, and the Game family is full of those. The
  # signature `System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]` was
  # therefore read as naming `Game` and `GameComponent`, and GameComponentCollection was recorded as
  # blocked on two types its public surface never mentions.
  #
  # This is the same class of blind spot Native frontiers 2 and 3 closed in the IL extractor -- a
  # scanner anchored on one side of a token -- seen in the signature graph. It ran in both
  # directions: 18 spurious edges across 15 types, and 21 edges missed entirely, because a name
  # followed by `[` (an array, or a generic definition used as an interface) matched nothing.
  def test_the_signature_extractor_bounds_a_name_on_both_sides
    collection = BY_NAME.fetch("Microsoft.Xna.Framework.GameComponentCollection")
    signature = collection.fetch("members").find { |member| member.fetch("kind") == "event" }.fetch("type")
    assert_equal "System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]", signature

    # The unbounded prefix test the correction replaced, shown failing on this exact signature.
    %w[Microsoft.Xna.Framework.Game Microsoft.Xna.Framework.GameComponent].each do |shorter|
      assert signature.include?("[#{shorter}"), "the old test matched #{shorter}"
      refute signature.include?("[#{shorter}]"), "#{shorter} is not what the signature names"
    end

    # And the edges the old test missed: a name followed by `[` was never matched.
    declaration = BY_NAME.fetch("Microsoft.Xna.Framework.Graphics.PackedVector.Alpha8")
                         .fetch("directInterfaces")
                         .find { |entry| entry.include?("IPackedVector`1") }
    assert declaration.start_with?("Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector`1[")
    refute declaration.include?("IPackedVector`1]")
  end

  def test_named_frontier_examples_keep_their_expected_blocker
    {
      # Microphone was here under NATIVE_RUNTIME until that deferral was checked too, and it was
      # wrong for a third reason: not the ABI, not the host, but nothing at all. This machine has
      # three capture devices, CNA enumerates every one, and the retired 0.7.0 headers declare the
      # same sixteen routes. Graphics.GraphicsAdapter replaces it as the NATIVE_RUNTIME example.
      "Microsoft.Xna.Framework.Graphics.GraphicsAdapter" => "NATIVE_RUNTIME",
      # TextureCollection was here until its deferral was checked and turned out to be simply
      # mistaken -- the two routes it needs were exported by the retired artifact too.
      "Microsoft.Xna.Framework.Graphics.EffectAnnotation" => "NATIVE_RUNTIME",
      # TitleContainer used to be here under BCL_PROJECTION and is deliberately not replaced by
      # another example: the Stream projection consumed it, which is what a retired blocker looks
      # like. `test_the_stream_projection_consumed_title_container` asserts that directly.
      # ContentManager left too, consumed by the Stream and Action`1 projections. What is left
      # under BCL_PROJECTION is the converter family and the ResourceContentManager the completed
      # ContentManager uncovered behind it.
      "Microsoft.Xna.Framework.Design.MathTypeConverter" => "BCL_PROJECTION",
      "Microsoft.Xna.Framework.Content.ResourceContentManager" => "BCL_PROJECTION"
    }.each do |name, expected|
      candidate = REPORT.fetch("dependencyCompleteCandidates").find { |item| item.fetch("name") == name }
      refute_nil candidate, name
      assert_includes candidate.fetch("blockers"), expected, name
    end
  end

  def test_touch_location_and_gesture_sample_were_consumed_from_pinned_il
    # It was deferred only because the retained assemblies were believed absent. They are not: the
    # Input.Touch assembly is hash-pinned, its IL carries every member, and none of it is native.
    %w[Microsoft.Xna.Framework.Input.Touch.TouchLocation
       Microsoft.Xna.Framework.Input.Touch.GestureSample].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      refute REPORT.fetch("dependencyCompleteCandidates").any? { |item| item.fetch("name") == name }, name
      entry = IL.fetch("types").fetch(name)
      assert_equal "Microsoft.Xna.Framework.Input.Touch.dll", entry.fetch("assembly"), name
      assert_equal "b0585224c18022c3661057ae79544644c10f33f1dc529678364f3d6b25151c25",
                   entry.fetch("assemblySha256"), name
      refute entry.fetch("nativeReachable"), name
    end
    # TouchCollection and its nested Enumerator were mutually blocked until Foundation 31 closed
    # the pair together; neither could ever have been selected alone, because a nested type cannot
    # be named or read without its declaring type and the declaring type's GetEnumerator returns
    # the nested one. Both are complete now.
    %w[Microsoft.Xna.Framework.Input.Touch.TouchCollection
       Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      refute REPORT.fetch("dependencyCompleteCandidates").any? { |item| item.fetch("name") == name }, name
    end
    # Completing the pair made TouchPanel the first consumable candidate the frontier had had since
    # Foundation 27, and Foundation 32 consumed it. The whole Input.Touch namespace is complete.
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Input.Touch.TouchPanel"
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch("Microsoft.Xna.Framework.Input.Touch.TouchPanel")
    assert_empty STRICT.fetch("missingTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Input\.Touch\./)
    # The enumerator was the single IL_UNAVAILABLE entry until Native frontier 2, on the ground
    # that "ikdasm does not emit the nested enumerator under a name the inventory can address". It
    # emits it; the extractor could not read it. With that fixed the classification is honest on
    # both counts: the IL is there, and the type is not dependency-complete, because a nested type
    # cannot be named or read without its declaring type and TouchCollection is still missing.
    entry = IL.fetch("types").fetch("Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator")
    assert_operator entry.fetch("ilLines"), :>, 0
    assert_operator entry.fetch("declaredMethods"), :>, 0
    refute(REPORT.fetch("dependencyCompleteCandidates").any? { |item|
      item.fetch("name") == "Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator"
    })
    # Nothing is blocked on missing IL any more.
    assert_empty REPORT.fetch("dependencyCompleteCandidates")
                       .select { |item| item.fetch("blockers").include?("IL_UNAVAILABLE") }
  end
end
