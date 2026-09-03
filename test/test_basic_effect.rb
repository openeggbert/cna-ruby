# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `Graphics.BasicEffect`, the first of the five stock effects — and the first type in this binding
# whose whole surface is CNA's rather than a shader's.
#
# XNA's `BasicEffect` is an `Effect` over a built-in compiled shader whose twenty-odd properties are
# cached in managed fields and flushed into `EffectParameter`s by `OnApply` under a dirty-flag mask.
# CNA's is a native object with typed accessors, and **its defaults are XNA's, member for member** —
# which is what makes this a projection rather than a re-implementation.
#
# Two things a consumer can see are recorded rather than hidden. `Parameters` is **empty** on a stock
# effect, because `cna_basic_effect_create`'s effect declares no parameters at all; and `OnApply`
# does nothing, because every setter writes through to CNA immediately, so there is nothing pending
# to flush.
class BasicEffectTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.BasicEffect"

  def test_the_type_is_complete_and_declares_the_three_interfaces
    assert ReviewedScoreboard.complete?(STRICT, NAME)
    refute_includes STRICT.fetch("partialTypes").keys, NAME
    %i[IEffectFog IEffectLights IEffectMatrices].each do |contract|
      assert G::BasicEffect.include?(G.const_get(contract)), contract.to_s
    end
    assert_operator G::BasicEffect, :<, G::Effect
    assert_operator G::BasicEffect, :<, G::GraphicsResource
  end

  class EffectGame < F::Game
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

  def with_effect
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = EffectGame.new do |device|
      effect = G::BasicEffect.new(device)
      begin
        yield effect, device
      ensure
        effect.Dispose
      end
    end
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def error_of
    yield
    :ok
  rescue StandardError => error
    [error.class, error.message]
  end

  def components(vector) = [vector.X, vector.Y, vector.Z]

  # ------------------------------------------------------------------ the defaults

  # The constructor IL, statement for statement, and CNA answers every one of them. The
  # `DirectionalLight0.Enabled = true` at the end is the one a reader would not guess.
  def test_every_constructor_default_is_the_ils
    values = with_effect do |effect, _device|
      {
        world: effect.World == F::Matrix.Identity,
        view: effect.View == F::Matrix.Identity,
        projection: effect.Projection == F::Matrix.Identity,
        diffuse: components(effect.DiffuseColor),
        emissive: components(effect.EmissiveColor),
        specular: components(effect.SpecularColor),
        specular_power: effect.SpecularPower,
        alpha: effect.Alpha,
        ambient: components(effect.AmbientLightColor),
        lighting: effect.LightingEnabled,
        per_pixel: effect.PreferPerPixelLighting,
        texture_enabled: effect.TextureEnabled,
        vertex_colour: effect.VertexColorEnabled,
        fog_enabled: effect.FogEnabled,
        fog_start: effect.FogStart,
        fog_end: effect.FogEnd,
        fog_colour: components(effect.FogColor),
        texture: effect.Texture
      }
    end
    assert values.fetch(:world) && values.fetch(:view) && values.fetch(:projection)
    assert_equal [1.0, 1.0, 1.0], values.fetch(:diffuse)
    assert_equal [0.0, 0.0, 0.0], values.fetch(:emissive)
    assert_equal [1.0, 1.0, 1.0], values.fetch(:specular)
    assert_in_delta 16.0, values.fetch(:specular_power)
    assert_in_delta 1.0, values.fetch(:alpha)
    assert_equal [0.0, 0.0, 0.0], values.fetch(:ambient)
    assert_equal [0.0, 0.0, 0.0], values.fetch(:fog_colour)
    assert_in_delta 0.0, values.fetch(:fog_start)
    assert_in_delta 1.0, values.fetch(:fog_end)
    %i[lighting per_pixel texture_enabled vertex_colour fog_enabled].each do |flag|
      assert_equal false, values.fetch(flag), flag.to_s
    end
    assert_nil values.fetch(:texture)
  end

  def test_the_three_lights_start_as_the_constructor_leaves_them
    lights = with_effect do |effect, _device|
      (0..2).map do |index|
        light = effect.__send__(:"DirectionalLight#{index}")
        [light.Enabled, components(light.Direction),
         components(light.DiffuseColor), components(light.SpecularColor)]
      end
    end
    # `DirectionalLight0.Enabled = true` is the constructor's, and the other two stay off.
    assert_equal [true, false, false], lights.map(&:first)
    lights.each do |_enabled, direction, diffuse, specular|
      assert_equal [0.0, -1.0, 0.0], direction, "Vector3.Down"
      assert_equal [1.0, 1.0, 1.0], diffuse, "Vector3.One"
      assert_equal [0.0, 0.0, 0.0], specular, "Vector3.Zero"
    end
  end

  # ------------------------------------------------------------------ the recorded deviations

  # `cna_basic_effect_create`'s effect declares no parameters, where XNA's shader declares one per
  # property — and where CNA's own four sibling stock effects each declare theirs. Measured, and
  # asserted so that a future CNA that does declare them fails here rather than silently changing
  # what `Parameters` means. `docs/stock-effect-parameter-upstream-defect.md` carries the whole
  # family's measurement; `test/test_stock_effects.rb` asserts the other four.
  def test_a_stock_effect_has_no_parameters_and_one_technique
    counts = with_effect { |effect, _device| [effect.Parameters.Count, effect.Techniques.Count] }
    assert_equal [0, 1], counts
  end

  # Every setter writes through, so nothing is pending and `OnApply` has nothing to flush.
  def test_on_apply_does_nothing_and_changes_nothing
    outcome = with_effect do |effect, _device|
      effect.DiffuseColor = F::Vector3.new(0.25, 0.5, 0.75)
      before = components(effect.DiffuseColor)
      result = effect.OnApply
      [before, result, components(effect.DiffuseColor)]
    end
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(0)
    assert_nil outcome.fetch(1)
    assert_equal outcome.fetch(0), outcome.fetch(2)
  end

  # ------------------------------------------------------------------ the properties

  def test_every_property_round_trips
    outcome = with_effect do |effect, _device|
      world = F::Matrix.new(*(1..16).map { |index| index / 8.0 })
      effect.World = world
      effect.View = F::Matrix.CreateTranslation(F::Vector3.new(1.0, 2.0, 3.0))
      effect.Projection = F::Matrix.Identity
      effect.DiffuseColor = F::Vector3.new(0.25, 0.5, 0.75)
      effect.EmissiveColor = F::Vector3.new(0.125, 0.25, 0.375)
      effect.SpecularColor = F::Vector3.new(0.5, 0.5, 0.5)
      effect.SpecularPower = 8.0
      effect.Alpha = 0.5
      effect.AmbientLightColor = F::Vector3.new(0.1, 0.2, 0.3)
      effect.LightingEnabled = true
      effect.PreferPerPixelLighting = true
      effect.TextureEnabled = true
      effect.VertexColorEnabled = true
      effect.FogEnabled = true
      effect.FogStart = 0.25
      effect.FogEnd = 0.75
      effect.FogColor = F::Vector3.new(0.9, 0.8, 0.7)
      {
        world: effect.World == world,
        view: components(F::Vector3.new(effect.View.M41, effect.View.M42, effect.View.M43)),
        diffuse: components(effect.DiffuseColor), emissive: components(effect.EmissiveColor),
        specular: components(effect.SpecularColor), specular_power: effect.SpecularPower,
        alpha: effect.Alpha, ambient: components(effect.AmbientLightColor),
        flags: [effect.LightingEnabled, effect.PreferPerPixelLighting,
                effect.TextureEnabled, effect.VertexColorEnabled, effect.FogEnabled],
        fog: [effect.FogStart, effect.FogEnd, components(effect.FogColor)]
      }
    end
    assert outcome.fetch(:world), "a Matrix survives the MEMORY-class by-value expansion exactly"
    assert_equal [1.0, 2.0, 3.0], outcome.fetch(:view)
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(:diffuse)
    assert_equal [0.125, 0.25, 0.375], outcome.fetch(:emissive)
    assert_equal [0.5, 0.5, 0.5], outcome.fetch(:specular)
    assert_in_delta 8.0, outcome.fetch(:specular_power)
    assert_in_delta 0.5, outcome.fetch(:alpha)
    assert_equal [true, true, true, true, true], outcome.fetch(:flags)
    assert_in_delta 0.25, outcome.fetch(:fog).fetch(0)
    assert_in_delta 0.75, outcome.fetch(:fog).fetch(1)
  end

  def test_the_type_guards
    outcomes = with_effect do |effect, _device|
      {
        world: error_of { effect.World = 5 },
        diffuse: error_of { effect.DiffuseColor = 5 },
        fog_colour: error_of { effect.FogColor = F::Vector2.Zero },
        lighting: error_of { effect.LightingEnabled = 1 },
        texture: error_of { effect.Texture = 5 },
        alpha: error_of { effect.Alpha = "x" }
      }
    end
    outcomes.each { |name, outcome| assert_equal TypeError, outcome.fetch(0), name.to_s }
    assert_equal "World must be a Matrix", outcomes.fetch(:world).fetch(1)
    assert_equal "LightingEnabled must be true or false", outcomes.fetch(:lighting).fetch(1)
  end

  # ------------------------------------------------------------------ the lights

  # `ldfld light0` — the same object every call, which is what makes
  # `effect.DirectionalLight0.Enabled = true` work at all.
  def test_each_light_is_one_object
    same = with_effect do |effect, _device|
      (0..2).map { |index| effect.__send__(:"DirectionalLight#{index}").equal?(effect.__send__(:"DirectionalLight#{index}")) }
    end
    assert_equal [true, true, true], same
  end

  # `DirectionalLight`'s managed rules are unchanged by the native backing: the colours are written
  # only while the light is enabled, and disabling pushes zero into both without losing the cache.
  def test_the_light_keeps_the_ils_enabled_gated_colour_rule
    outcome = with_effect do |effect, _device|
      light = effect.DirectionalLight1
      assert_equal false, light.Enabled
      light.DiffuseColor = F::Vector3.new(0.25, 0.5, 0.75)
      cached_while_off = components(light.DiffuseColor)
      light.Enabled = true
      after_enable = components(light.DiffuseColor)
      light.Enabled = false
      after_disable = components(light.DiffuseColor)
      [cached_while_off, after_enable, after_disable, light.Enabled]
    end
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(0), "the cache takes the value even while off"
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(1)
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(2), "and disabling does not lose it"
    assert_equal false, outcome.fetch(3)
  end

  def test_the_light_direction_is_written_whether_enabled_or_not
    outcome = with_effect do |effect, _device|
      light = effect.DirectionalLight2
      light.Direction = F::Vector3.new(1.0, 0.0, 0.0)
      [light.Enabled, components(light.Direction)]
    end
    assert_equal [false, [1.0, 0.0, 0.0]], outcome
  end

  # `EnableDefaultLighting` is `LightingEnabled = true` plus XNA's standard three-point preset, and
  # `cna_effect_lights_enable_default` produces XNA's own values — the key light's
  # (1, 0.9607843, 0.80784315) and its direction (-0.5265408, -0.5735765, -0.6275069).
  def test_enable_default_lighting_is_xnas_preset
    outcome = with_effect do |effect, _device|
      effect.EnableDefaultLighting
      [effect.LightingEnabled,
       (0..2).map { |index| effect.__send__(:"DirectionalLight#{index}").Enabled },
       components(effect.DirectionalLight0.DiffuseColor),
       components(effect.DirectionalLight0.Direction),
       components(effect.AmbientLightColor)]
    end
    assert_equal true, outcome.fetch(0)
    assert_equal [true, true, true], outcome.fetch(1)
    outcome.fetch(2).zip([1.0, 0.9607843, 0.80784315]).each { |actual, expected| assert_in_delta expected, actual, 1e-6 }
    outcome.fetch(3).zip([-0.5265408, -0.5735765, -0.6275069]).each { |actual, expected| assert_in_delta expected, actual, 1e-6 }
    outcome.fetch(4).each { |channel| assert_operator channel, :>, 0.0, "the preset sets an ambient" }
  end

  # ------------------------------------------------------------------ Texture

  # CNA hands back only a handle and this ABI has no route from a native object back to one — the
  # rule `TextureCollection` records — so the getter answers the object it was given.
  def test_the_texture_answers_the_object_it_was_given
    outcome = with_effect do |effect, device|
      texture = G::Texture2D.new(device, 4, 4)
      begin
        effect.Texture = texture
        assigned = effect.Texture.equal?(texture)
        effect.Texture = nil
        [assigned, effect.Texture, effect.TextureEnabled]
      ensure
        effect.Texture = nil
        texture.Dispose
      end
    end
    assert outcome.fetch(0)
    assert_nil outcome.fetch(1)
    # `set_Texture` does not enable texturing; `TextureEnabled` is its own property, as in XNA.
    assert_equal false, outcome.fetch(2)
  end

  # ------------------------------------------------------------------ Clone

  # `newobj BasicEffect::.ctor(BasicEffect)`, whose copy constructor copies every cached field.
  def test_clone_is_a_distinct_basic_effect_with_every_property_copied
    outcome = with_effect do |effect, _device|
      effect.DiffuseColor = F::Vector3.new(0.25, 0.5, 0.75)
      effect.Alpha = 0.5
      effect.FogEnabled = true
      effect.World = F::Matrix.CreateTranslation(F::Vector3.new(4.0, 5.0, 6.0))
      effect.DirectionalLight1.Enabled = true
      effect.DirectionalLight1.DiffuseColor = F::Vector3.new(0.1, 0.2, 0.3)
      clone = effect.Clone
      begin
        result = {
          class: clone.class, distinct: !clone.equal?(effect),
          diffuse: components(clone.DiffuseColor), alpha: clone.Alpha,
          fog: clone.FogEnabled, world: clone.World == effect.World,
          light: [clone.DirectionalLight1.Enabled, components(clone.DirectionalLight1.DiffuseColor)],
          lights_distinct: !clone.DirectionalLight1.equal?(effect.DirectionalLight1)
        }
        # A clone is independent: changing it does not reach back.
        clone.Alpha = 0.125
        result[:source_alpha] = effect.Alpha
        result
      ensure
        clone.Dispose
      end
    end
    assert_equal G::BasicEffect, outcome.fetch(:class)
    assert outcome.fetch(:distinct)
    assert_equal [0.25, 0.5, 0.75], outcome.fetch(:diffuse)
    assert_in_delta 0.5, outcome.fetch(:alpha)
    assert_equal true, outcome.fetch(:fog)
    assert outcome.fetch(:world)
    assert_equal true, outcome.fetch(:light).fetch(0)
    assert_equal [0.1, 0.2, 0.3].map { |v| v.to_f }, outcome.fetch(:light).fetch(1).map { |v| v.round(6) }
    assert outcome.fetch(:lights_distinct)
    assert_in_delta 0.5, outcome.fetch(:source_alpha)
  end

  # ------------------------------------------------------------------ disposal

  # `BasicEffect` declares no `Dispose` of its own — it inherits `Effect`'s — and the three light
  # views go with the rest of the effect's views rather than through an override.
  def test_disposal_releases_the_light_views_without_a_dispose_override
    refute_includes G::BasicEffect.public_instance_methods(false), :Dispose
    game = EffectGame.new do |device|
      effect = G::BasicEffect.new(device)
      views = effect.__send__(:instance_variable_get, :@stock_light_views).dup
      effect.Dispose
      [views, effect.IsDisposed, effect.__send__(:instance_variable_get, :@stock_light_views)]
    end
    begin
      game.Run
    ensure
      game.Dispose
    end
    skip "CNA_NATIVE_LIBRARY not supplied" if game.result.nil?
    views, disposed, after = game.result
    assert_equal 3, views.length
    refute_includes views, 0
    assert disposed
    assert_empty after
  end

  # ------------------------------------------------------------------ the ABI expansions

  # The two by-value shapes this milestone added, re-derived from the manifest so a "simplification"
  # fails here as well as at the ABI probe.
  def test_the_manifest_records_an_sse_vector_and_a_memory_matrix
    vector = CNA::Native::Manifest::FUNCTIONS.find { |entry| entry.symbol == "cna_basic_effect_set_diffuse_color" }
    aggregate = vector.value_aggregates.values.fetch(0)
    assert_equal "CNA_Vector3", aggregate.fetch(:c)
    assert_equal 2, aggregate.fetch(:members)
    assert_equal 0, aggregate.fetch(:fillers), "SSE eightbytes need no integer filler"
    assert_equal "SSE", aggregate.fetch(:register_class)
    assert_empty vector.abi_fillers

    matrix = CNA::Native::Manifest::FUNCTIONS.find { |entry| entry.symbol == "cna_effect_matrices_set_world" }
    memory = matrix.value_aggregates.values.fetch(0)
    assert_equal "CNA_Matrix", memory.fetch(:c)
    assert_equal 8, memory.fetch(:members)
    assert_equal 5, memory.fetch(:fillers)
    assert_equal "INTEGER", memory.fetch(:register_class)
    assert_equal [1, 2, 3, 4, 5], matrix.abi_fillers
  end
end
