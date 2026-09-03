# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `DirectionalLight`, `EffectMaterial` and the `IEffectLights` contract they unblocked.
#
# All three sat on the frontier under `NATIVE_RUNTIME`, and for all three the word named something
# that is now projected: the light's four "native" identities reach `EffectParameter.SetValue`, and
# the material's single constructor reaches `Effect`'s clone constructor. Neither type touches the
# device itself, so the light's whole behaviour is testable with no renderer at all — which is why
# most of this file needs no `skip`.
class DirectionalLightTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  LIGHT = "Microsoft.Xna.Framework.Graphics.DirectionalLight"
  MATERIAL = "Microsoft.Xna.Framework.Graphics.EffectMaterial"

  # ------------------------------------------------------------------------------- the contract

  def test_all_three_are_complete_and_carry_the_declared_shapes
    [LIGHT, MATERIAL, "Microsoft.Xna.Framework.Graphics.IEffectLights"].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_empty ReviewedScoreboard.partial_remainder(STRICT, name), name
    end
    assert REFERENCE.fetch(LIGHT).fetch("sealed"), "the light is sealed"
    assert_equal "System.Object", REFERENCE.fetch(LIGHT).fetch("baseType")
    refute REFERENCE.fetch(MATERIAL).fetch("sealed"), "the material is not"
    assert_equal "Microsoft.Xna.Framework.Graphics.Effect", REFERENCE.fetch(MATERIAL).fetch("baseType")
    assert_equal G::Effect, G::EffectMaterial.superclass
    # One identity, and it is the constructor.
    assert_equal 1, REFERENCE.fetch(MATERIAL).fetch("members").length
    assert_equal "constructor", REFERENCE.fetch(MATERIAL).fetch("members").first.fetch("kind")
  end

  # ------------------------------------------------------- the light, with no parameters at all
  #
  # Every `callvirt` in this type is guarded by a `brfalse`, so a light built over three nulls is a
  # complete, working object that writes nowhere. That is what a `BasicEffect` whose shader declares
  # no specular parameter really constructs.

  def test_the_constructor_defaults_are_down_one_and_zero
    light = G::DirectionalLight.new(nil, nil, nil, nil)
    assert_equal F::Vector3.Down, light.Direction
    assert_equal F::Vector3.One, light.DiffuseColor
    assert_equal F::Vector3.Zero, light.SpecularColor
    refute light.Enabled, "a light starts disabled"
  end

  def test_a_clone_source_copies_the_fields_and_the_parameters_are_still_the_new_ones
    source = G::DirectionalLight.new(nil, nil, nil, nil)
    source.Enabled = true
    source.Direction = F::Vector3.new(1.0, 2.0, 3.0)
    source.DiffuseColor = F::Vector3.new(0.25, 0.5, 0.75)
    source.SpecularColor = F::Vector3.new(4.0, 5.0, 6.0)

    clone = G::DirectionalLight.new(nil, nil, nil, source)
    assert clone.Enabled
    assert_equal F::Vector3.new(1.0, 2.0, 3.0), clone.Direction
    assert_equal F::Vector3.new(0.25, 0.5, 0.75), clone.DiffuseColor
    assert_equal F::Vector3.new(4.0, 5.0, 6.0), clone.SpecularColor
    # The clone copied values, not the source: mutating one does not move the other.
    clone.Direction = F::Vector3.Up
    assert_equal F::Vector3.new(1.0, 2.0, 3.0), source.Direction
  end

  def test_the_refusals_are_the_ils_types
    assert_raises(::TypeError) { G::DirectionalLight.new(Object.new, nil, nil, nil) }
    assert_raises(::TypeError) { G::DirectionalLight.new(nil, nil, nil, Object.new) }
    light = G::DirectionalLight.new(nil, nil, nil, nil)
    assert_raises(::TypeError) { light.Direction = [1, 2, 3] }
    assert_raises(::TypeError) { light.DiffuseColor = 1.0 }
    assert_raises(::TypeError) { light.SpecularColor = nil }
    assert_raises(::TypeError) { light.Enabled = 1 }
    assert_raises(::ArgumentError) { G::DirectionalLight.new(nil, nil, nil) }
  end

  # A CLR struct assignment copies. Holding the caller's `Vector3` would let a later mutation of it
  # change what the light reports, which no XNA program can observe.
  def test_a_vector_is_copied_in_rather_than_retained
    light = G::DirectionalLight.new(nil, nil, nil, nil)
    vector = F::Vector3.new(1.0, 1.0, 1.0)
    light.Direction = vector
    vector.X = 99.0
    assert_equal 1.0, light.Direction.X
  end

  # ------------------------------------------------------- the light, over real EffectParameters

  # `CNA_TEST_FX_BASIC` is FNA's own stock `BasicEffect.fxb`, referenced by path and never copied
  # into this repository. It is the authentic fixture for this type: `BasicEffect` is where XNA
  # constructs a `DirectionalLight`, and this shader declares exactly the three `float3` parameters
  # it constructs one over — `DirLight0Direction`, `DirLight0DiffuseColor`, `DirLight0SpecularColor`.
  def with_basic_effect
    skip "this renderer has no compiled-effect runtime" unless RendererEnvironment.compiled_effects?
    fixture = ENV["CNA_TEST_FX_BASIC"]
    skip "CNA_TEST_FX_BASIC not supplied" unless fixture && File.file?(fixture)

    game = LightGame.new { |device| yield(device, File.binread(fixture)) }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  class LightGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  # The three parameters a light is built over, by the names the shader declares.
  def light_parameters(effect, index)
    %w[Direction DiffuseColor SpecularColor].map { |part| effect.Parameters["DirLight#{index}#{part}"] }
  end

  def test_a_write_through_the_light_lands_in_the_parameter
    values = with_basic_effect do |device, bytecode|
      effect = G::Effect.new(device, bytecode)
      begin
        direction, diffuse, specular = light_parameters(effect, 0)
        light = G::DirectionalLight.new(direction, diffuse, specular, nil)
        constructed = [direction.GetValueVector3, diffuse.GetValueVector3, specular.GetValueVector3]
        light.Direction = F::Vector3.new(0.5, -0.25, 0.125)
        [constructed, direction.GetValueVector3, light.Direction]
      ensure
        effect.Dispose
      end
    end
    # The constructor's three setters run with `enabled` still false, so only the direction is
    # written through: `Vector3.Down` reaches the shader while `One` and `Zero` stay cached.
    assert_equal F::Vector3.Down, values[0][0]
    assert_equal F::Vector3.Zero, values[0][1], "a disabled light writes no diffuse colour"
    assert_equal F::Vector3.Zero, values[0][2]
    assert_equal F::Vector3.new(0.5, -0.25, 0.125), values[1], "and the direction always writes"
    assert_equal F::Vector3.new(0.5, -0.25, 0.125), values[2]
  end

  # `set_DiffuseColor` writes only while the light is enabled, and `set_Enabled` is what pushes the
  # cached colours in — or `Vector3.Zero` out. Both halves are asserted from the parameters' side.
  def test_the_colours_reach_the_parameters_only_while_the_light_is_enabled
    values = with_basic_effect do |device, bytecode|
      effect = G::Effect.new(device, bytecode)
      begin
        direction, diffuse, specular = light_parameters(effect, 1)
        light = G::DirectionalLight.new(direction, diffuse, specular, nil)
        light.DiffuseColor = F::Vector3.new(0.75, 0.5, 0.25)
        light.SpecularColor = F::Vector3.new(0.125, 0.25, 0.375)
        while_disabled = [diffuse.GetValueVector3, specular.GetValueVector3]
        light.Enabled = true
        while_enabled = [diffuse.GetValueVector3, specular.GetValueVector3]
        light.Enabled = false
        after_disable = [diffuse.GetValueVector3, specular.GetValueVector3]
        # An unchanged write is `beq.s` and does nothing at all.
        diffuse.SetValue(F::Vector3.new(9.0, 9.0, 9.0))
        light.Enabled = false
        after_no_op = diffuse.GetValueVector3
        [while_disabled, while_enabled, after_disable, after_no_op,
         [light.DiffuseColor, light.SpecularColor]]
      ensure
        effect.Dispose
      end
    end
    assert_equal [F::Vector3.Zero, F::Vector3.Zero], values[0], "a disabled light writes no colour"
    assert_equal [F::Vector3.new(0.75, 0.5, 0.25), F::Vector3.new(0.125, 0.25, 0.375)], values[1]
    assert_equal [F::Vector3.Zero, F::Vector3.Zero], values[2],
                 "disabling pushes zero rather than forgetting"
    assert_equal F::Vector3.new(9.0, 9.0, 9.0), values[3], "and an unchanged write does nothing"
    assert_equal [F::Vector3.new(0.75, 0.5, 0.25), F::Vector3.new(0.125, 0.25, 0.375)], values[4],
                 "the cached colours survive both"
  end

  # A clone copies the fields and writes nothing, so the parameters it is given keep whatever the
  # effect had — which is how `BasicEffect.Clone` hands three lights to a new effect.
  def test_a_clone_over_live_parameters_writes_nothing
    values = with_basic_effect do |device, bytecode|
      effect = G::Effect.new(device, bytecode)
      begin
        direction, diffuse, specular = light_parameters(effect, 2)
        source = G::DirectionalLight.new(nil, nil, nil, nil)
        source.Enabled = true
        source.Direction = F::Vector3.new(1.0, 0.0, 0.0)
        direction.SetValue(F::Vector3.new(7.0, 7.0, 7.0))
        clone = G::DirectionalLight.new(direction, diffuse, specular, source)
        [direction.GetValueVector3, clone.Direction, clone.Enabled]
      ensure
        effect.Dispose
      end
    end
    assert_equal F::Vector3.new(7.0, 7.0, 7.0), values[0], "the clone constructor wrote nothing"
    assert_equal F::Vector3.new(1.0, 0.0, 0.0), values[1]
    assert values[2]
  end

  # ------------------------------------------------------------------------------- the material

  def test_the_material_is_a_named_clone_of_an_effect
    values = with_basic_effect do |device, bytecode|
      effect = G::Effect.new(device, bytecode)
      material = nil
      begin
        material = G::EffectMaterial.new(effect)
        [material.is_a?(G::Effect), material.Parameters.Count == effect.Parameters.Count,
         material.equal?(effect), material.Clone.class,
         (begin; G::EffectMaterial.new(nil); rescue StandardError => e; e.class; end),
         (begin; G::EffectMaterial.new(Object.new); rescue StandardError => e; e.class; end)]
      ensure
        material&.Dispose
        effect.Dispose
      end
    end
    assert values[0], "an EffectMaterial is an Effect"
    assert values[1], "and carries the same parameters"
    refute values[2]
    # It does not override Clone, so cloning one answers an Effect -- which is what XNA does.
    assert_equal G::Effect, values[3]
    # The clone constructor's own refusals, inherited unchanged: null is
    # ArgumentNullException("cloneSource") and a non-effect is a type error.
    assert_equal ::ArgumentError, values[4]
    assert_equal ::TypeError, values[5]
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_builds_no_stock_effect_and_no_lighting_runtime
    # `BasicEffect` left this list in Foundation 97; the other four are still absent.
    %i[SkinnedEffect EnvironmentMapEffect AlphaTestEffect DualTextureEffect]
      .each { |absent| refute G.const_defined?(absent, false), absent.to_s }
    # The light is a plain object: it has no handle, no disposal and no device.
    light = G::DirectionalLight.new(nil, nil, nil, nil)
    refute light.respond_to?(:Dispose)
    refute light.respond_to?(:GraphicsDevice)
    refute_includes G::DirectionalLight.ancestors, G::GraphicsResource
    # This milestone bound no route: everything it needed was bound by the Effect cluster. The
    # `cna_directional_light_*` family arrived with `BasicEffect`, which is where CNA's stock effect
    # carries its three lights as native member views -- see `test_basic_effect.rb`.
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    parameter_backed = G::DirectionalLight.new(nil, nil, nil, nil)
    assert_nil parameter_backed.__send__(:instance_variable_get, :@light_handle),
               "a light over EffectParameters reaches no route at all"
  end
end
