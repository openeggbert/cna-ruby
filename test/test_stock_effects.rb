# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The other four stock effects — `SkinnedEffect`, `AlphaTestEffect`, `DualTextureEffect` and
# `EnvironmentMapEffect` — and with them the whole five-type family.
#
# What makes these projections rather than re-implementations is the same measurement `BasicEffect`
# rests on: **CNA's constructor defaults are the IL's**, so nothing is fabricated. Where a
# constructor's tail does something CNA does not — `DirectionalLight0.Enabled = true` in two of
# them, and `SkinnedEffect`'s seventy-two identity bone transforms — the projection performs exactly
# that statement and no more.
class StockEffectsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FAMILY = %w[BasicEffect SkinnedEffect AlphaTestEffect DualTextureEffect EnvironmentMapEffect].freeze

  # The parameter collections CNA 0.21.0 builds, measured identically on `HEADLESS`, `OPENGL33` and
  # the compiled-effects artifact: `[name, RowCount, ColumnCount]` in declaration order.
  STOCK_EFFECT_PARAMETERS = {
    "BasicEffect" => [],
    "SkinnedEffect" => [
      ["DiffuseColor", 1, 4], ["EmissiveColor", 1, 3], ["SpecularColor", 1, 3],
      ["SpecularPower", 1, 1], ["EyePosition", 1, 3], ["FogColor", 1, 3], ["FogVector", 1, 4],
      ["World", 4, 4], ["WorldInverseTranspose", 4, 4], ["WorldViewProj", 4, 4],
      ["Bones", 72, 4], ["ShaderIndex", 1, 1]
    ],
    "AlphaTestEffect" => [
      ["DiffuseColor", 1, 4], ["AlphaTest", 1, 4], ["FogColor", 1, 3], ["FogVector", 1, 4],
      ["WorldViewProj", 4, 4], ["ShaderIndex", 1, 1]
    ],
    "DualTextureEffect" => [
      ["DiffuseColor", 1, 4], ["FogColor", 1, 3], ["FogVector", 1, 4], ["WorldViewProj", 4, 4],
      ["ShaderIndex", 1, 1]
    ],
    "EnvironmentMapEffect" => [
      ["EnvironmentMapAmount", 1, 1], ["EnvironmentMapSpecular", 1, 3], ["FresnelFactor", 1, 1],
      ["DiffuseColor", 1, 4], ["EmissiveColor", 1, 3], ["EyePosition", 1, 3], ["FogColor", 1, 3],
      ["FogVector", 1, 4], ["World", 4, 4], ["WorldInverseTranspose", 4, 4],
      ["WorldViewProj", 4, 4], ["ShaderIndex", 1, 1]
    ]
  }.freeze

  def test_all_five_are_complete
    FAMILY.each do |name|
      full = "Microsoft.Xna.Framework.Graphics.#{name}"
      assert ReviewedScoreboard.complete?(STRICT, full), name
      assert_operator G.const_get(name), :<, G::Effect, name
    end
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  # Which contracts each declares is the metadata's, and two of the five have no lighting at all.
  def test_each_declares_exactly_the_contracts_the_metadata_says
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
    FAMILY.each do |name|
      declared = reference.fetch("types").find { |type| type.fetch("name") == "Microsoft.Xna.Framework.Graphics.#{name}" }
                          .fetch("interfaces")
      %w[IEffectFog IEffectLights IEffectMatrices].each do |contract|
        expected = declared.include?("Microsoft.Xna.Framework.Graphics.#{contract}")
        assert_equal expected, G.const_get(name).include?(G.const_get(contract)), "#{name} #{contract}"
      end
    end
    refute G::AlphaTestEffect.include?(G::IEffectLights)
    refute G::DualTextureEffect.include?(G::IEffectLights)
    refute G::AlphaTestEffect.method_defined?(:DirectionalLight0)
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

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = EffectGame.new { |device| yield device }
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

  # ------------------------------------------------------------------ shared shape

  # The three families every one of them shares: the matrices, the fog, and — for the three that
  # declare it — the lighting.
  def test_the_shared_contracts_behave_the_same_on_every_effect
    outcome = with_device do |device|
      FAMILY.to_h do |name|
        effect = G.const_get(name).new(device)
        begin
          effect.World = F::Matrix.CreateTranslation(F::Vector3.new(1.0, 2.0, 3.0))
          effect.FogEnabled = true
          effect.FogStart = 0.25
          effect.FogEnd = 0.75
          effect.FogColor = F::Vector3.new(0.1, 0.2, 0.3)
          row = {
            world: [effect.World.M41, effect.World.M42, effect.World.M43],
            view: effect.View == F::Matrix.Identity,
            fog: [effect.FogEnabled, effect.FogStart, effect.FogEnd, components(effect.FogColor)],
            lights: effect.respond_to?(:DirectionalLight0)
          }
          row[:lighting] = effect.LightingEnabled if effect.class.public_method_defined?(:LightingEnabled)
          [name, row]
        ensure
          effect.Dispose
        end
      end
    end
    outcome.each do |name, row|
      assert_equal [1.0, 2.0, 3.0], row.fetch(:world), name
      assert row.fetch(:view), name
      assert_equal true, row.fetch(:fog).fetch(0), name
      assert_in_delta 0.25, row.fetch(:fog).fetch(1), 1e-6, name
      assert_in_delta 0.75, row.fetch(:fog).fetch(2), 1e-6, name
      assert_equal false, row.fetch(:lighting, false), name
      # Only `BasicEffect` publishes `LightingEnabled` at all; see the explicit-implementation test.
      assert_equal(name == "BasicEffect", row.key?(:lighting), name)
    end
    assert_equal({ "BasicEffect" => true, "SkinnedEffect" => true, "AlphaTestEffect" => false,
                   "DualTextureEffect" => false, "EnvironmentMapEffect" => true },
                 outcome.transform_values { |row| row.fetch(:lights) })
  end

  # ------------------------------------------------------------------ the explicit member

  # `SkinnedEffect` and `EnvironmentMapEffect` implement `IEffectLights.LightingEnabled`
  # **explicitly**, so neither declares it publicly and neither can be unlit. `BasicEffect` is the
  # one of the three lit effects that declares it as its own property.
  def test_lighting_enabled_is_explicit_on_two_of_the_three_lit_effects
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
    %w[SkinnedEffect EnvironmentMapEffect].each do |name|
      declared = reference.fetch("types").find { |type| type.fetch("name") == "Microsoft.Xna.Framework.Graphics.#{name}" }
                          .fetch("members").map { |member| member.fetch("name") }
      refute_includes declared, "LightingEnabled", name
      type = G.const_get(name)
      refute type.public_method_defined?(:LightingEnabled), name
      assert type.private_method_defined?(:LightingEnabled), name
      assert type.private_method_defined?(:"LightingEnabled="), name
    end
    assert G::BasicEffect.public_method_defined?(:LightingEnabled)
    assert G::BasicEffect.public_method_defined?(:"LightingEnabled=")
  end

  # `get` is `ldc.i4.1; ret`; `set` refuses `false` with the `CantDisableLighting` resource
  # formatted by the type's own name, and accepts `true` as a no-op.
  def test_the_explicit_setter_refuses_false_with_the_ils_message
    outcome = with_device do |device|
      %w[SkinnedEffect EnvironmentMapEffect].to_h do |name|
        effect = G.const_get(name).new(device)
        begin
          [name, [effect.__send__(:LightingEnabled),
                  error_of { effect.__send__(:LightingEnabled=, false) },
                  error_of { effect.__send__(:LightingEnabled=, true) },
                  effect.__send__(:LightingEnabled)]]
        ensure
          effect.Dispose
        end
      end
    end
    outcome.each do |name, (before, refused, accepted, after)|
      assert_equal true, before, name
      assert_equal [CNA::Runtime::NotSupportedError,
                    "#{name} does not support setting LightingEnabled to false."], refused, name
      assert_equal :ok, accepted, name
      assert_equal true, after, name
    end
  end

  # ------------------------------------------------------------------ the parameter collections

  # MEASURED, and the correction to what `BasicEffect` alone suggested: four of the five **do**
  # declare parameters, and only `BasicEffect` answers an empty collection. The names and shapes
  # below are CNA's, asserted so a change upstream is caught rather than absorbed; XNA's own shader
  # parameters are not claimed to be these. See
  # `docs/stock-effect-parameter-upstream-defect.md`.
  def test_the_parameter_collections_are_the_measured_ones
    measured = with_device do |device|
      FAMILY.to_h do |name|
        effect = G.const_get(name).new(device)
        begin
          rows = (0...effect.Parameters.Count).map do |index|
            parameter = effect.Parameters[index]
            [parameter.Name, parameter.RowCount, parameter.ColumnCount]
          end
          [name, [rows, effect.Techniques.Count]]
        ensure
          effect.Dispose
        end
      end
    end
    measured.each { |name, (_rows, techniques)| assert_equal 1, techniques, name }
    assert_equal STOCK_EFFECT_PARAMETERS, measured.transform_values(&:first)
  end

  # The empty one, kept as its own assertion so it reads as the gap it is rather than as a shape.
  def test_basic_effect_is_the_only_one_with_an_empty_parameter_collection
    empty = with_device do |device|
      FAMILY.select do |name|
        effect = G.const_get(name).new(device)
        begin
          effect.Parameters.Count.zero?
        ensure
          effect.Dispose
        end
      end
    end
    assert_equal %w[BasicEffect], empty
  end

  # ------------------------------------------------------------------ SkinnedEffect

  def test_the_skinned_constructor_tail_is_the_ils
    outcome = with_device do |device|
      effect = G::SkinnedEffect.new(device)
      begin
        bones = effect.GetBoneTransforms(G::SkinnedEffect::MaxBones)
        [effect.DirectionalLight0.Enabled, components(effect.SpecularColor), effect.SpecularPower,
         effect.WeightsPerVertex, bones.length, bones.all? { |bone| bone == F::Matrix.Identity }]
      ensure
        effect.Dispose
      end
    end
    assert_equal true, outcome.fetch(0), "DirectionalLight0.Enabled = true"
    assert_equal [1.0, 1.0, 1.0], outcome.fetch(1)
    assert_in_delta 16.0, outcome.fetch(2)
    assert_equal 4, outcome.fetch(3)
    # `SetBoneTransforms(new Matrix[MaxBones])` with every entry `Matrix.Identity`.
    assert_equal 72, outcome.fetch(4)
    assert outcome.fetch(5)
  end

  def test_max_bones_is_a_compile_time_constant
    assert_equal 72, G::SkinnedEffect::MaxBones
    assert G::SkinnedEffect.const_defined?(:MaxBones, false)
    refute G::SkinnedEffect.method_defined?(:MaxBones), "a literal field is a constant, not a method"
  end

  # `GetBoneTransforms` answers a **fresh array**, so a caller cannot reach the effect's own copy.
  def test_the_bone_transforms_round_trip_through_a_fresh_array
    outcome = with_device do |device|
      effect = G::SkinnedEffect.new(device)
      begin
        effect.SetBoneTransforms([F::Matrix.Identity,
                                  F::Matrix.CreateTranslation(F::Vector3.new(1.0, 2.0, 3.0))])
        first = effect.GetBoneTransforms(2)
        second = effect.GetBoneTransforms(2)
        [first.length, first.fetch(0) == F::Matrix.Identity,
         [first.fetch(1).M41, first.fetch(1).M42, first.fetch(1).M43],
         first.equal?(second)]
      ensure
        effect.Dispose
      end
    end
    assert_equal 2, outcome.fetch(0)
    assert outcome.fetch(1)
    assert_equal [1.0, 2.0, 3.0], outcome.fetch(2)
    refute outcome.fetch(3), "a fresh array each call"
  end

  def test_the_bone_and_weight_guards
    outcomes = with_device do |device|
      effect = G::SkinnedEffect.new(device)
      begin
        {
          nil_bones: error_of { effect.SetBoneTransforms(nil) },
          empty_bones: error_of { effect.SetBoneTransforms([]) },
          not_matrices: error_of { effect.SetBoneTransforms([1, 2]) },
          too_many: error_of { effect.SetBoneTransforms(::Array.new(73) { F::Matrix.Identity }) },
          zero_count: error_of { effect.GetBoneTransforms(0) },
          past_max: error_of { effect.GetBoneTransforms(73) },
          three_weights: error_of { effect.WeightsPerVertex = 3 },
          ok_weights: error_of { effect.WeightsPerVertex = 2 }
        }
      ensure
        effect.Dispose
      end
    end
    assert_equal [ArgumentError, "boneTransforms"], outcomes.fetch(:nil_bones)
    assert_equal [ArgumentError, "boneTransforms"], outcomes.fetch(:empty_bones)
    assert_equal TypeError, outcomes.fetch(:not_matrices).fetch(0)
    assert_equal [ArgumentError, "boneTransforms"], outcomes.fetch(:too_many)
    assert_equal [RangeError, "count"], outcomes.fetch(:zero_count)
    assert_equal [RangeError, "count"], outcomes.fetch(:past_max)
    # Only one, two or four are legal.
    assert_equal [RangeError, "value"], outcomes.fetch(:three_weights)
    assert_equal :ok, outcomes.fetch(:ok_weights)
  end

  # ------------------------------------------------------------------ AlphaTestEffect

  def test_the_alpha_test_defaults_and_members
    outcome = with_device do |device|
      effect = G::AlphaTestEffect.new(device)
      begin
        defaults = [effect.AlphaFunction, effect.ReferenceAlpha, effect.Alpha,
                    components(effect.DiffuseColor), effect.VertexColorEnabled]
        effect.AlphaFunction = G::CompareFunction::Less
        effect.ReferenceAlpha = 128
        [defaults, [effect.AlphaFunction, effect.ReferenceAlpha]]
      ensure
        effect.Dispose
      end
    end
    defaults, written = outcome
    # `alphaFunction = 6` in the constructor, which is `CompareFunction.Greater`.
    assert_equal G::CompareFunction::Greater, defaults.fetch(0)
    assert_equal 0, defaults.fetch(1)
    assert_in_delta 1.0, defaults.fetch(2)
    assert_equal [1.0, 1.0, 1.0], defaults.fetch(3)
    assert_equal false, defaults.fetch(4)
    assert_equal [G::CompareFunction::Less, 128], written
  end

  # ------------------------------------------------------------------ DualTextureEffect

  # The one accessor in the family that takes an index: both textures share a route.
  def test_the_two_textures_are_two_slots_of_one_route
    outcome = with_device do |device|
      effect = G::DualTextureEffect.new(device)
      first = G::Texture2D.new(device, 2, 2)
      second = G::Texture2D.new(device, 4, 4)
      begin
        assert_nil effect.Texture
        assert_nil effect.Texture2
        effect.Texture = first
        effect.Texture2 = second
        both = [effect.Texture.equal?(first), effect.Texture2.equal?(second),
                effect.Texture.equal?(second)]
        effect.Texture = nil
        [both, effect.Texture, effect.Texture2.equal?(second)]
      ensure
        effect.Texture = nil
        effect.Texture2 = nil
        effect.Dispose
        first.Dispose
        second.Dispose
      end
    end
    assert_equal [true, true, false], outcome.fetch(0), "the two slots are independent"
    assert_nil outcome.fetch(1)
    assert outcome.fetch(2), "clearing one leaves the other"
  end

  # ------------------------------------------------------------------ EnvironmentMapEffect

  def test_the_environment_map_defaults_and_its_cube
    outcome = with_device do |device|
      effect = G::EnvironmentMapEffect.new(device)
      begin
        defaults = [effect.DirectionalLight0.Enabled, effect.EnvironmentMapAmount,
                    components(effect.EnvironmentMapSpecular), effect.FresnelFactor,
                    effect.EnvironmentMap]
        wrong = error_of { effect.EnvironmentMap = G::Texture2D.new(device, 2, 2) }
        [defaults, wrong]
      ensure
        effect.Dispose
      end
    end
    defaults, wrong = outcome
    assert_equal true, defaults.fetch(0), "DirectionalLight0.Enabled = true"
    assert_in_delta 1.0, defaults.fetch(1)
    assert_equal [0.0, 0.0, 0.0], defaults.fetch(2), "EnvironmentMapSpecular is a Vector3, not a flag"
    assert_in_delta 1.0, defaults.fetch(3)
    assert_nil defaults.fetch(4)
    assert_equal [TypeError, "EnvironmentMap must be a TextureCube or nil"], wrong
  end

  # ------------------------------------------------------------------ Clone

  # Each `Clone` is `newobj <ThisType>::.ctor(<ThisType>)`, so it answers its own type and copies
  # every property, including the two the base does not know about.
  def test_every_clone_answers_its_own_type_and_copies_its_own_members
    outcome = with_device do |device|
      results = {}
      %w[SkinnedEffect AlphaTestEffect DualTextureEffect EnvironmentMapEffect].each do |name|
        effect = G.const_get(name).new(device)
        begin
          effect.Alpha = 0.5
          effect.FogEnabled = true
          effect.World = F::Matrix.CreateTranslation(F::Vector3.new(7.0, 8.0, 9.0))
          case name
          when "SkinnedEffect"
            effect.WeightsPerVertex = 2
            effect.SetBoneTransforms([F::Matrix.CreateTranslation(F::Vector3.new(4.0, 5.0, 6.0))])
          when "AlphaTestEffect"
            effect.AlphaFunction = G::CompareFunction::LessEqual
            effect.ReferenceAlpha = 64
          when "EnvironmentMapEffect"
            effect.EnvironmentMapAmount = 0.25
            effect.FresnelFactor = 0.75
          end
          clone = effect.Clone
          begin
            row = { class: clone.class, alpha: clone.Alpha, fog: clone.FogEnabled,
                    world: clone.World == effect.World }
            case name
            when "SkinnedEffect"
              bone = clone.GetBoneTransforms(1).fetch(0)
              row[:extra] = [clone.WeightsPerVertex, [bone.M41, bone.M42, bone.M43]]
            when "AlphaTestEffect"
              row[:extra] = [clone.AlphaFunction, clone.ReferenceAlpha]
            when "EnvironmentMapEffect"
              row[:extra] = [clone.EnvironmentMapAmount, clone.FresnelFactor]
            end
            results[name] = row
          ensure
            clone.Dispose
          end
        ensure
          effect.Dispose
        end
      end
      results
    end
    outcome.each do |name, row|
      assert_equal G.const_get(name), row.fetch(:class), name
      assert_in_delta 0.5, row.fetch(:alpha), 1e-6, name
      assert_equal true, row.fetch(:fog), name
      assert row.fetch(:world), name
    end
    assert_equal [2, [4.0, 5.0, 6.0]], outcome.fetch("SkinnedEffect").fetch(:extra)
    assert_equal [G::CompareFunction::LessEqual, 64], outcome.fetch("AlphaTestEffect").fetch(:extra)
    amount, fresnel = outcome.fetch("EnvironmentMapEffect").fetch(:extra)
    assert_in_delta 0.25, amount, 1e-6
    assert_in_delta 0.75, fresnel, 1e-6
  end

  # ------------------------------------------------------------------ disposal

  # None of the five declares a `Dispose`; the light views go with the rest of the effect's views.
  def test_none_of_them_declares_a_dispose_and_the_light_views_are_released
    FAMILY.each do |name|
      refute_includes G.const_get(name).public_instance_methods(false), :Dispose, name
    end
    outcome = with_device do |device|
      %w[SkinnedEffect EnvironmentMapEffect].to_h do |name|
        effect = G.const_get(name).new(device)
        views = effect.__send__(:instance_variable_get, :@stock_light_views).dup
        effect.Dispose
        [name, [views.length, views.include?(0), effect.__send__(:instance_variable_get, :@stock_light_views), effect.IsDisposed]]
      end
    end
    outcome.each do |name, (count, has_zero, after, disposed)|
      assert_equal 3, count, name
      refute has_zero, name
      assert_empty after, name
      assert disposed, name
    end
  end

  # `AlphaTestEffect` and `DualTextureEffect` declare no lighting, so they acquire no view at all.
  def test_an_unlit_effect_acquires_no_light_view
    outcome = with_device do |device|
      %w[AlphaTestEffect DualTextureEffect].to_h do |name|
        effect = G.const_get(name).new(device)
        begin
          [name, effect.__send__(:instance_variable_get, :@stock_light_views)]
        ensure
          effect.Dispose
        end
      end
    end
    outcome.each { |name, views| assert_nil views, name }
  end
end
