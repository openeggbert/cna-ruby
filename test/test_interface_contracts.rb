# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundations 18 and 20 — the managed XNA interface contracts.
#
# XNA interfaces project to Ruby modules whose members raise NotImplementedError, exactly as the
# PackedVector interface contracts already do. Foundation 18 closed the four event-free contracts;
# Foundation 20 added IUpdateable and IDrawable once one CLR event gained one Ruby event-reader
# identity over CNA::Runtime::Event. On an abstract contract the event reader raises
# NotImplementedError like every other member: an interface declares the identity and never owns
# an invocation list.
class InterfaceContractsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics

  CONTRACTS = {
    "Microsoft.Xna.Framework.IGameComponent" => %i[Initialize],
    "Microsoft.Xna.Framework.IGraphicsDeviceManager" => %i[BeginDraw CreateDevice EndDraw],
    "Microsoft.Xna.Framework.IUpdateable" =>
      %i[Enabled EnabledChanged Update UpdateOrder UpdateOrderChanged],
    "Microsoft.Xna.Framework.IDrawable" =>
      %i[Draw DrawOrder DrawOrderChanged Visible VisibleChanged],
    "Microsoft.Xna.Framework.Graphics.IEffectMatrices" =>
      %i[Projection Projection= View View= World World=],
    "Microsoft.Xna.Framework.Graphics.IEffectFog" =>
      %i[FogColor FogColor= FogEnabled FogEnabled= FogEnd FogEnd= FogStart FogStart=],
    "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService" =>
      %i[DeviceCreated DeviceDisposing DeviceReset DeviceResetting GraphicsDevice],
    # The third effect contract, projectable only once something produced a `DirectionalLight`.
    "Microsoft.Xna.Framework.Graphics.IEffectLights" =>
      %i[AmbientLightColor AmbientLightColor= DirectionalLight0 DirectionalLight1 DirectionalLight2
         EnableDefaultLighting LightingEnabled LightingEnabled=]
  }.freeze

  # Declaration order, which for each entry is the pinned metadata order rather than alphabetical.
  EVENT_CONTRACTS = {
    "Microsoft.Xna.Framework.IUpdateable" => %i[EnabledChanged UpdateOrderChanged],
    "Microsoft.Xna.Framework.IDrawable" => %i[VisibleChanged DrawOrderChanged],
    "Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService" =>
      %i[DeviceDisposing DeviceReset DeviceResetting DeviceCreated]
  }.freeze

  REFERENCE = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  SIGNATURES = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  PARTIAL_RUNTIME_TYPES = [
    "Microsoft::Xna::Framework::Game",
    "Microsoft::Xna::Framework::GraphicsDeviceManager",
    "Microsoft::Xna::Framework::Graphics::GraphicsDevice",
    "Microsoft::Xna::Framework::Graphics::GraphicsResource",
    "Microsoft::Xna::Framework::Graphics::Texture2D",
    "Microsoft::Xna::Framework::Graphics::SpriteBatch"
  ].freeze

  def resolve(name)
    name.split(/[.:]+/).reduce(Object) { |scope, segment| scope.const_get(segment, false) }
  end

  def test_every_selected_interface_matches_the_pinned_contract
    CONTRACTS.each_key do |clr_name|
      pinned = REFERENCE.fetch(clr_name)
      assert_equal "interface", pinned.fetch("kind"), clr_name
      assert_nil pinned["baseType"], clr_name
      assert_empty pinned.fetch("directInterfaces"), clr_name

      expected_events = EVENT_CONTRACTS.fetch(clr_name, [])
      assert_equal expected_events,
                   pinned.fetch("members").select { |member| member.fetch("kind") == "event" }
                         .map { |member| member.fetch("name").to_sym }, clr_name

      selected = SIGNATURES.fetch(clr_name)
      assert_equal pinned.fetch("members"), selected.fetch("members"), clr_name
      assert_equal clr_name.split(".").join("::"), selected.fetch("rubyName")
    end
    assert_equal 32, CONTRACTS.keys.sum { |name| SIGNATURES.fetch(name).fetch("members").length }
  end

  def test_every_interface_is_a_module_exposing_exactly_its_declared_projections
    CONTRACTS.each do |clr_name, expected|
      interface = resolve(clr_name)
      assert_instance_of Module, interface, clr_name
      refute_instance_of Class, interface, clr_name
      assert_equal expected, interface.public_instance_methods(false).sort, clr_name
      assert_empty interface.protected_instance_methods(false), clr_name
      assert_empty interface.private_instance_methods(false), clr_name
      assert_empty interface.constants(false), clr_name
      assert_empty interface.singleton_methods(false), clr_name
    end
  end

  def test_property_projections_match_the_declared_get_and_set_accessors
    CONTRACTS.each_key do |clr_name|
      interface = resolve(clr_name)
      SIGNATURES.fetch(clr_name).fetch("members").each do |member|
        name = member.fetch("name")
        case member.fetch("kind")
        when "property"
          assert interface.method_defined?(name), "#{clr_name}##{name}"
          assert_equal member.fetch("set"), interface.method_defined?(:"#{name}="),
                       "#{clr_name}##{name}= must match the declared setter"
        when "method"
          assert interface.method_defined?(name), "#{clr_name}##{name}"
          refute interface.method_defined?(:"#{name}="), "#{clr_name}##{name}="
        when "event"
          # One CLR event, one Ruby reader: no writer and no add_/remove_ pair.
          assert interface.method_defined?(name), "#{clr_name}##{name}"
          refute interface.method_defined?(:"#{name}="), "#{clr_name}##{name}="
          refute interface.method_defined?(:"add_#{name}"), "#{clr_name}#add_#{name}"
          refute interface.method_defined?(:"remove_#{name}"), "#{clr_name}#remove_#{name}"
        end
      end
    end
  end

  def test_every_member_is_abstract_and_names_its_own_contract
    CONTRACTS.each do |clr_name, expected|
      interface = resolve(clr_name)
      short = clr_name.split(".").last
      host = Class.new { include(interface) }

      expected.each do |name|
        instance = host.new
        arity = interface.instance_method(name).arity
        error = assert_raises(NotImplementedError, "#{clr_name}##{name}") do
          instance.public_send(name, *Array.new(arity, nil))
        end
        assert_equal "#{short}##{name}", error.message
      end
    end
  end

  def test_interface_arities_match_the_declared_parameter_lists
    CONTRACTS.each_key do |clr_name|
      interface = resolve(clr_name)
      SIGNATURES.fetch(clr_name).fetch("members").each do |member|
        name = member.fetch("name")
        case member.fetch("kind")
        when "method"
          assert_equal member.fetch("parameters").length, interface.instance_method(name).arity,
                       "#{clr_name}##{name}"
        when "property"
          assert_equal 0, interface.instance_method(name).arity, "#{clr_name}##{name}"
          assert_equal 1, interface.instance_method(:"#{name}=").arity if member.fetch("set")
        when "event"
          assert_equal 0, interface.instance_method(name).arity, "#{clr_name}##{name}"
        end
      end
    end
  end

  def test_no_partial_runtime_type_includes_an_interface_contract
    # Including one would add public members that the partial selected surface does not declare.
    modules = CONTRACTS.keys.map { |name| resolve(name) }
    PARTIAL_RUNTIME_TYPES.each do |name|
      type = resolve(name)
      modules.each do |interface|
        refute_includes type.ancestors, interface, "#{name} must not include #{interface}"
      end
    end
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_SURFACE, G::GraphicsDevice.public_instance_methods(false).sort

    strict = JSON.parse(Pathname(__dir__).join("..", "docs", "generated", "api-compat-report.json").read)
    # Foundation 37 closed Game::Components and Game::Services, the first two members any deferred
    # partial has lost. Both are pure managed state and neither needed an interface contract.
    assert_equal ReviewedScoreboard::MISSING_MEMBER, strict.fetch("MISSING_MEMBER")
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, strict.fetch("PARTIAL_TYPES")
  end

  def test_event_bearing_interfaces_are_complete_with_their_events_projected
    %w[IUpdateable IDrawable].each do |short|
      clr_name = "Microsoft.Xna.Framework.#{short}"
      pinned = REFERENCE.fetch(clr_name)
      events = pinned.fetch("members").select { |member| member.fetch("kind") == "event" }
      assert_equal 2, events.length, clr_name
      assert(events.all? { |event| event.fetch("type") == "System.EventHandler`1[System.EventArgs]" })

      assert SIGNATURES.key?(clr_name), clr_name
      assert_equal pinned.fetch("members"), SIGNATURES.fetch(clr_name).fetch("members"), clr_name
      assert F.const_defined?(short.to_sym, false), "Framework::#{short}"
    end

    strict = JSON.parse(Pathname(__dir__).join("..", "docs", "generated", "api-compat-report.json").read)
    %w[IUpdateable IDrawable].each do |short|
      name = "Microsoft.Xna.Framework.#{short}"
      assert_includes strict.fetch("completeTypeNames"), name
      assert_equal 0, strict.fetch("localDiagnostics").fetch(name), name
    end
  end

  def test_interfaces_imply_no_component_effect_or_device_runtime
    # GameServiceContainer arrived in Foundation 33, GameComponentCollection in 35 and GameComponent
    # in 38, each from its own IL rather than from anything these interfaces imply. What the
    # contracts still imply is nothing: a fresh container is empty, a fresh collection is empty, and
    # a fresh component reaches no device.
    # LaunchParameters arrived in Foundation 46 from its own IL and its own BCL base, and
    # GameWindow in 48 from its own IL over the canonical window routes.
    %i[DrawableGameComponent]
      .each { |name| refute F.const_defined?(name, false), "Framework::#{name}" }
    # Foundation 40 projected IGraphicsDeviceService -- under Graphics, which is where the pinned
    # contract declares it, and never under Framework. Its existence is a contract, not a runtime:
    # nothing conforms to it and Game.Services holds no key for it.
    refute F.const_defined?(:IGraphicsDeviceService, false), "Framework::IGraphicsDeviceService"
    assert G.const_defined?(:IGraphicsDeviceService, false), "Graphics::IGraphicsDeviceService"
    assert_nil F::GameServiceContainer.new.GetService(G::IGraphicsDeviceService)
    assert_empty F::Game.new.Services.instance_variable_get(:@services)
    assert_equal 0, F::GameComponentCollection.new.Count

    # GameComponent implements both contracts, which is what makes it concrete; it adds no member
    # beyond the fourteen its own contract declares.
    assert_includes F::GameComponent.ancestors, F::IUpdateable
    refute_includes F::GameComponent.ancestors, F::IDrawable
    assert_nil F::GameServiceContainer.new.GetService(F::IGraphicsDeviceManager)
    # `IVertexType` and `VertexDeclaration` left this list when they were built; what this test
    # claims -- that **these** interface contracts imply no component, effect or device runtime --
    # is unchanged, and the interface that arrived is asserted to be abstract like the rest.
    # The nine `Effect` types left this list when the cluster was built, and `DirectionalLight` and
    # `IEffectLights` when the light was; what this milestone claimed, and still claims, is that
    # **it** built none of them. `IEffectLights` is asserted below to be as abstract as the rest.
    %i[SkinnedEffect IEffectSkinning].each do |name|
      refute G.const_defined?(name, false), "Graphics::#{name}"
    end
    assert_kind_of Module, G::IEffectLights
    refute_kind_of Class, G::IEffectLights
    assert_raises(NotImplementedError) { Object.new.extend(G::IEffectLights).EnableDefaultLighting }
    # And nothing conforms to it: the light is not an implementer, it is what an implementer hands out.
    refute_includes G::DirectionalLight.ancestors, G::IEffectLights
    assert_kind_of Module, G::IVertexType
    assert_raises(NotImplementedError) { Object.new.extend(G::IVertexType).VertexDeclaration }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end
end
