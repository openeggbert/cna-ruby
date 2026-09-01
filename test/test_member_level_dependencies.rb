# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 39 — the member-level half of the dependency graph.
#
# The signature graph can only see the *types* a public signature names, so it answers
# "GameComponent depends on Game" and stops. Two things it cannot see follow from that, and this
# milestone measures both from the pinned IL:
#
#   1. **A dependency on a partial type may already be met.** A partial type is a real Ruby class
#      with a real surface; what a dependent needs is the members it actually calls.
#      `GameComponent`'s whole body reaches exactly one `Game` member, `get_Components`, which
#      Foundation 37 completed — so Foundation 38's selection was sound, and this is where that is
#      proved rather than asserted.
#
#   2. **A dependency may be invisible to a signature entirely.** `DrawableGameComponent`'s whole
#      device-service handshake lives in a private field, so the signature graph never saw
#      `IGraphicsDeviceService` — while its `Initialize` throws
#      `InvalidOperationException(MissingGraphicsDeviceService)` unless a producer registers one.
#      Without this, that type would have looked ready.
#
# The policy is deliberately **not** relaxed. `dependencyComplete` still means every dependency is
# complete and `selectedNext` still comes from `consumableCandidates`; what is added is reported for
# a maintainer to act on.
class MemberLevelDependenciesTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
  REPORT = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)

  def edges(name) = IL.fetch("types").fetch(name).fetch("externalMemberReferences")

  def candidate(name)
    (REPORT.fetch("dependencyCompleteCandidates") +
     REPORT.fetch("partialDependencySatisfiedCandidates") +
     REPORT.fetch("ilOnlyBlockedCandidates")).find { |entry| entry.fetch("name") == name }
  end

  # ---------------------------------------------------------------------- the edges are measured

  def test_every_type_with_il_carries_its_external_member_edges
    assert_equal 257, IL.fetch("TYPES_WITH_IL")
    assert IL.fetch("types").each_value.all? { |entry| entry.key?("externalMemberReferences") }
    assert_equal IL.fetch("types").each_value.sum { |entry| entry.fetch("externalMemberReferences").length },
                 IL.fetch("MEMBER_LEVEL_EDGES")
    assert_operator IL.fetch("MEMBER_LEVEL_EDGES"), :>, 3000
  end

  # An edge names a reference type other than its owner, spelled the way the contract spells it.
  def test_every_edge_is_normalised_and_never_self_referential
    IL.fetch("types").each do |owner, entry|
      entry.fetch("externalMemberReferences").each do |edge|
        target, member = edge.split("::", 2)
        refute_equal owner, target, edge
        refute_nil member, edge
        refute_includes edge, "/", "a nested type must be spelled Parent+Child"
        refute_includes edge, "'", "a quoted name must be stripped"
      end
    end
  end

  # It is purely additive: the native-reachability measurement Native frontier 3 settled is
  # untouched.
  def test_the_native_reachability_measurement_did_not_move
    assert_equal 77, IL.fetch("TYPES_NATIVE_REACHABLE")
    assert_equal 254, IL.fetch("NATIVE_ENTRY_POINT_METHODS")
    assert_equal 0, IL.fetch("TYPES_WITHOUT_IL")
  end

  # ------------------------------------------------------- what it proves about Foundation 38

  # GameComponent's entire IL reaches exactly one member of Game, and Foundation 37 completed it.
  def test_game_component_reaches_exactly_one_game_member_and_it_is_complete
    reached = edges("Microsoft.Xna.Framework.GameComponent").grep(/\AMicrosoft\.Xna\.Framework\.Game::/)
    assert_equal ["Microsoft.Xna.Framework.Game::get_Components"], reached

    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
                      .map { |label| label.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "Components"
    assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Game")
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.GameComponent"
  end

  # -------------------------------------------------------- what it proves about the next one

  # DrawableGameComponent looked signature-satisfied and is not: its IL reaches nine members of a
  # missing type the signature graph never saw.
  # The nine service edges are an IL fact and never move. What Foundation 40 changed is only which
  # blocker they produce: the interface is complete now, so the *type* is no longer missing -- and
  # the type is still not consumable, because nothing provides the service.
  def test_drawable_game_component_reaches_nine_members_of_the_device_service
    service = edges("Microsoft.Xna.Framework.DrawableGameComponent")
                .grep(/IGraphicsDeviceService::/)
    assert_equal 9, service.length
    assert_includes service, "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::get_GraphicsDevice"
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"
    assert_includes STRICT.fetch("missingTypeNames"), "Microsoft.Xna.Framework.DrawableGameComponent"

    entry = candidate("Microsoft.Xna.Framework.DrawableGameComponent")
    refute_nil entry
    assert_empty entry.fetch("ilOnlyUnmetDependencies"),
                 "the interface it reaches is complete, so no il-only *type* is unmet"

    # And the single Game member it reaches really is complete, which is why the type's blocker is
    # the producer and nothing else.
    assert_equal ["Microsoft.Xna.Framework.Game::get_Services"],
                 edges("Microsoft.Xna.Framework.DrawableGameComponent").grep(/Framework\.Game::/)
    # It reaches no member of GraphicsDevice at all: it holds the device and republishes it.
    assert_empty edges("Microsoft.Xna.Framework.DrawableGameComponent")
                   .grep(/Graphics\.GraphicsDevice::/)
  end

  # ------------------------------------------------- Foundation 40: completing a contract is not
  # ------------------------------------------------- the same as providing one

  # The structural graph now finds every dependency met -- and the type still cannot be used. This
  # is the exact gap the producer blocker closes, and it must never silently reopen.
  def test_drawable_game_component_stays_blocked_on_a_producer_not_on_a_type
    entry = candidate("Microsoft.Xna.Framework.DrawableGameComponent")
    assert entry.fetch("partialDependencySatisfied"),
           "structurally every dependency is met, which is precisely why the blocker is needed"
    assert_equal ["INTERFACE_PRODUCER_MISSING"], entry.fetch("blockers")
    assert_equal ["Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"],
                 entry.fetch("producerlessInterfaces")
    refute_includes REPORT.fetch("consumableCandidates").map { |c| c.fetch("name") },
                    "Microsoft.Xna.Framework.DrawableGameComponent"
  end

  # The rule is general, not a special case wearing one type's name: it is asked of every interface,
  # and it independently catches a second, unrelated pair.
  def test_the_producer_rule_is_general_and_catches_an_unrelated_case
    caught = (REPORT.fetch("dependencyCompleteCandidates") +
              REPORT.fetch("partialDependencySatisfiedCandidates") +
              REPORT.fetch("ilOnlyBlockedCandidates"))
             .select { |entry| entry.fetch("blockers").include?("INTERFACE_PRODUCER_MISSING") }
             .to_h { |entry| [entry.fetch("name"), entry.fetch("producerlessInterfaces")] }
    # VertexDeclaration was the second case until it was built; the rule that caught it is
    # unchanged and still catches the first. It is worth recording what happened to it: the
    # interface it reached, IVertexType, has since been projected too and **still has no
    # producer**, because nothing in this binding conforms to it -- which is the next test's
    # subject and the reason a completed interface is not a provider.
    assert_equal({
                   "Microsoft.Xna.Framework.DrawableGameComponent" =>
                     ["Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"]
                 }, caught)
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.IVertexType"
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.VertexDeclaration"
    assert_includes REPORT.fetch("candidatePolicy"), "INTERFACE_PRODUCER_MISSING"
  end

  # Conformance is measured through real Ruby ancestry, so a module that merely exists cannot make
  # the blocker disappear. GraphicsDeviceManager is the sole declared implementer in the pinned
  # contract, it is partial, and its Ruby class does not include the module.
  def test_no_projected_type_conforms_to_the_device_service
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
    service = "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"
    declared = reference.fetch("types").select { |type| type.fetch("interfaces").include?(service) }
                        .map { |type| type.fetch("name") }
    assert_equal ["Microsoft.Xna.Framework.GraphicsDeviceManager"], declared
    assert_includes STRICT.fetch("partialTypes").keys, "Microsoft.Xna.Framework.GraphicsDeviceManager"

    module_ = Microsoft::Xna::Framework::Graphics::IGraphicsDeviceService
    refute_includes Microsoft::Xna::Framework::GraphicsDeviceManager.ancestors, module_,
                    "conformance must not be claimed while the contract members are abstract stubs"
    assert_raises(NotImplementedError) { Class.new { include module_ }.new.GraphicsDevice }
  end

  # GamerServicesComponent was blocked on a *member* of the partial Game, not only on the
  # GamerServices runtime. It has since been built, so it is off the candidate list; what the
  # measurement owns is the **edge**, which is still there and is still what the signature graph
  # cannot see.
  def test_gamer_services_component_reaches_a_game_member_the_signature_graph_cannot_see
    name = "Microsoft.Xna.Framework.GamerServices.GamerServicesComponent"
    assert_includes STRICT.fetch("completeTypeNames"), name
    reached = edges(name).grep(/\AMicrosoft\.Xna\.Framework\.Game::/)
                         .map { |edge| edge.split("::", 2).last }
    assert_includes reached, "get_Window"

    # Foundation 48 completed GameWindow and with it Game::Window, so the edge this row measures
    # now reaches a member that exists. What the measurement owns is the edge itself -- that
    # GamerServicesComponent's IL reaches `get_Window` at all, which the signature graph cannot
    # see -- and that is unchanged.
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Game")
                      .map { |label| label.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "Window"
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.GameWindow"
  end

  # ------------------------------------------------------------------ the near-misses it exposes

  # Six candidates the signature graph called fully dependency-complete are held back by a type only
  # their IL reaches. Reporting them is the point: without it each looked ready.
  def test_the_measurement_exposes_candidates_the_signature_graph_called_complete
    signature_complete = REPORT.fetch("ilOnlyBlockedCandidates")
                               .select { |entry| entry.fetch("unmetDependencies").empty? }
    # 6 until ContentManager completed -- it left this list and so did Microphone, whose only
    # remaining blocker was the `System.Byte[]` the Stream projection decided -- 5 until the audio
    # cluster took SoundEffectInstance, 3 until the XACT engine cluster took Cue -- its one il-only
    # unmet dependency was AudioEngine -- and 2 until SpriteFont was built, whose own il-only
    # dependency, SpriteBatch, had been complete all along.
    # 1 until GraphicsResource completed and put VertexDeclaration and SamplerState here: both are
    # dependency-complete by the signature graph and both reach a type only their IL names --
    # IVertexType for the first, EffectPass for the second.
    # 3 until SamplerState was built, which took it back to 2, and 1 when VertexDeclaration
    # followed it: both blockers named members the pinned contract never selects.
    assert_equal 1, signature_complete.length
    names = signature_complete.map { |entry| entry.fetch("name") }.sort
    # ContentManager was here until the Stream and Action`1 projections consumed it.
    assert_equal ["Microsoft.Xna.Framework.Graphics.EffectAnnotation"], names
    refute_includes names, "Microsoft.Xna.Framework.Audio.Cue"
  end

  # It strengthens Foundation 36's conclusion rather than contradicting it: a candidate can be
  # blocked twice over with only one reason visible in the signature graph.
  #
  # Both audio instances of that shape have since been resolved the way a doubly blocked candidate
  # is supposed to be -- by building the type that was the second blocker. SoundEffectInstance went
  # first, with the SoundEffect behind it; Cue followed when the XACT engine cluster built the
  # AudioEngine its IL reaches. So the shape is now demonstrated in Graphics, and the audio pair is
  # asserted to be resolved rather than quietly dropped.
  #
  # `SpriteFont` is deliberately not the example even though it is doubly blocked in the report: its
  # il-only dependency is `SpriteBatch`, which is **complete**, so what holds it is its own BCL
  # blockers rather than a missing type. `EffectAnnotation`'s `EffectParameter` really is missing,
  # which is the shape this test is about.
  def test_a_candidate_can_be_blocked_twice_over
    {"Microsoft.Xna.Framework.Graphics.EffectAnnotation" => "Microsoft.Xna.Framework.Graphics.EffectParameter"}
      .each do |name, blocker|
      entry = candidate(name)
      assert_includes entry.fetch("blockers"), "NATIVE_RUNTIME", "still native-blocked"
      assert_includes entry.fetch("ilOnlyUnmetDependencies"), blocker, "and blocked on a missing type too"
      assert_includes STRICT.fetch("missingTypeNames"), blocker
    end

    # Cue's second blocker was AudioEngine; building that cleared this half, and the milestone
    # straight after built Cue itself, so both are complete and neither is a candidate any more.
    assert_nil REPORT.fetch("dependencyCompleteCandidates")
                     .find { |item| item.fetch("name") == "Microsoft.Xna.Framework.Audio.Cue" }
    %w[Microsoft.Xna.Framework.Audio.AudioEngine
       Microsoft.Xna.Framework.Audio.Cue].each { |name| assert_includes STRICT.fetch("completeTypeNames"), name }
  end

  # ------------------------------------------------------------------- the policy is not relaxed

  def test_the_candidate_policy_and_selection_route_are_unchanged
    assert_includes REPORT.fetch("candidatePolicy"), "all XNA public-signature dependencies complete"
    assert_includes REPORT.fetch("candidatePolicy"), "deliberately do not relax"
    # 19 until Foundation 46 took LaunchParameters off the frontier by projecting Dictionary`2,
    # 12 until the Stream projection consumed TitleContainer, and 9 until Microphone was built. The
    # XACT engine cluster held it at 8 -- AudioCategory left and WaveBank arrived behind
    # AudioEngine -- building the banks and the cue took it to 6, which emptied the Audio namespace
    # off the frontier entirely, MediaSource took it to 5 and emptied the RUNTIME_DATA register with
    # it, SpriteFont took it to 4 -- the first candidate a BCL decision alone really unblocked --
    # and ResourceContentManager to 3, the first this frontier ever *selected* rather than listed.
    # and ResourceContentManager to 3. Then it *rose* to 9, which is what a frontier advancing
    # looks like: GraphicsResource completing made the four graphics state objects and
    # VertexDeclaration dependency-complete, and Texture2D completing did the same for VideoPlayer.
    # and back to 6 when the four state objects were audited and built, 5 when
    # SamplerStateCollection followed them, and 8 when VertexDeclaration and the IVertexType it
    # uncovered were both built -- putting the four vertex structs on the queue, the first
    # consumable candidates since Foundation 32.
    # ...and 4 when those four were built, which consumed the queue rather than growing it.
    assert_equal 4, REPORT.fetch("dependencyCompleteCandidates").length
    assert_empty REPORT.fetch("consumableCandidates")
    assert_equal "none-consumable", REPORT.fetch("selectionRoute")
    assert_nil REPORT.fetch("selectedNext")

    # Nothing reported here becomes consumable, and the type-level lists are byte-identical to what
    # they were: the two new reports sit beside the policy rather than inside it. Some entries in
    # ilOnlyBlockedCandidates *are* dependency-complete by the type-level rule -- that is precisely
    # what makes reporting them worthwhile.
    consumable = REPORT.fetch("consumableCandidates").map { |entry| entry.fetch("name") }
    (REPORT.fetch("partialDependencySatisfiedCandidates") +
     REPORT.fetch("ilOnlyBlockedCandidates")).each do |entry|
      refute_includes consumable, entry.fetch("name")
    end
    assert_equal 1, REPORT.fetch("ilOnlyBlockedCandidates").count { |entry| entry.fetch("dependencyComplete") }
  end

  # The one candidate the refinement cleared, and what happened to it. Foundation 39 selected it and
  # Foundation 40 built it, so it has left the candidate list entirely -- a candidate is by
  # definition a type this projection does not target, and it is targeted now.
  def test_the_candidate_the_refinement_cleared_became_a_complete_type
    name = "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService"
    assert_includes STRICT.fetch("completeTypeNames"), name
    refute_includes STRICT.fetch("missingTypeNames"), name
    assert_nil candidate(name), "a completed type is no longer a candidate for anything"
    refute_includes REPORT.fetch("partialDependencySatisfiedCandidates").map { |e| e.fetch("name") }, name

    # The two IL facts that made it selectable are permanent and are re-derived here rather than
    # recalled: the interface reaches no member of anything at all, so in particular it reaches no
    # member of the partial GraphicsDevice whose type its property names.
    assert_empty edges(name)
    assert_equal 0, edges(name).grep(/Graphics\.GraphicsDevice::/).length
    assert_includes STRICT.fetch("partialTypes").keys, "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

    # A partial dependency is therefore *satisfiable*: the rule must stay member-level and must
    # never regress to "any reference to a partial type blocks".
    device = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
    still_satisfied = REPORT.fetch("partialDependencySatisfiedCandidates").select do |entry|
      entry.fetch("partialTypeDependencies").key?(device)
    end
    refute_empty still_satisfied, "naming a partial type must not by itself block a candidate"
    still_satisfied.each do |entry|
      assert_empty entry.fetch("partialTypeDependencies").fetch(device).fetch("reachedButMissing")
    end
  end
end
