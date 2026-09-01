# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Graphics.SamplerStateCollection`, and the two `GraphicsDevice` properties that produce one.
#
# It arrived on the frontier the moment `SamplerState` completed — the uncovering a completed base
# always causes — carrying `NATIVE_RUNTIME`. That word is right here for the first time in a while,
# and it is right in a way that made the type buildable rather than blocked: the setter really does
# reach the device, and `cna_graphics_device_set_sampler_state` is exactly the route it needs.
class SamplerStateCollectionTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  SSC = G::SamplerStateCollection
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.SamplerStateCollection"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_its_whole_public_surface_is_one_indexer
    contract = REFERENCE.fetch(NAME)
    assert contract.fetch("sealed")
    assert_equal "System.Object", contract.fetch("baseType"), "unlike the state it holds, it is not a resource"
    assert_equal 1, contract.fetch("members").length
    member = contract.fetch("members").first
    assert_equal %w[property Item], [member.fetch("kind"), member.fetch("name")]
    assert_equal ["System.Int32"], member.fetch("parameters").map { |p| p.fetch("type") }
    assert_equal %w[public public], [member.fetch("getAccess"), member.fetch("setAccess")]

    # The constructor is `assembly`, so a consumer reaches one only through the device.
    assert_raises(NoMethodError) { SSC.new(nil, 0) }
    %i[Length Count GetEnumerator each].each { |absent| refute SSC.public_method_defined?(absent), absent.to_s }
    assert_equal %i[[] []=], SSC.public_instance_methods(false).sort
  end

  def test_the_scoreboard_records_it_complete_and_the_device_gained_two_members
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Graphics.GraphicsDevice")
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "SamplerStates"
    refute_includes remainder, "VertexSamplerStates"
    # The three device state properties were deliberately outstanding here -- each one's setter
    # ends an active EffectPass, and no Effect was projected then. Both halves have since landed,
    # and what this milestone claimed is unchanged: it added the two collections and nothing else.
    %w[BlendState DepthStencilState RasterizerState].each { |name| refute_includes remainder, name }
    %w[SetRenderTarget DrawPrimitives Present].each { |name| assert_includes remainder, name }
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }, NAME
  end

  # ------------------------------------------------------------------------------- the routes

  def test_the_two_routes_it_needs_and_the_bound_they_carry
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_graphics_device_get_sampler_state"
    assert_includes symbols, "cna_graphics_device_set_sampler_state"
    assert_equal 16, CNA::Native::Manifest::CONSTANTS.fetch("CNA_MAX_SAMPLERS")
    assert_equal SSC::MAX_SAMPLERS, CNA::Native::Manifest::CONSTANTS.fetch("CNA_MAX_SAMPLERS")
    # These were unbound here, for the reason the state-object milestone recorded: applying a
    # whole pipeline state is GraphicsDevice's surface and not this collection's. It is bound now,
    # by GraphicsDevice's own state slice, which is the same statement from the other side.
    %w[cna_graphics_device_set_blend_state cna_graphics_device_set_depth_stencil_state
       cna_graphics_device_set_rasterizer_state].each { |symbol| assert_includes symbols, symbol }
  end

  # ------------------------------------------------------------------------------ live behaviour

  class DeviceGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = DeviceGame.new { |device| yield device }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def filter_of(collection, slot) = collection.__send__(:device_state, slot).read_u32(20)
  def address_u_of(collection, slot) = collection.__send__(:device_state, slot).read_u32(8)

  # Both getters are one `ldfld` over a field the constructor fills, so each answers the same object
  # every time, and the two are different objects because they address different shader stages.
  def test_each_property_answers_one_stable_object_and_the_two_are_distinct
    values = with_device do |device|
      [device.SamplerStates.equal?(device.SamplerStates),
       device.VertexSamplerStates.equal?(device.VertexSamplerStates),
       device.SamplerStates.equal?(device.VertexSamplerStates),
       device.SamplerStates.instance_of?(SSC),
       device.SamplerStates.equal?(device.Textures)]
    end
    assert_equal [true, true, false, true, false], values
  end

  # The deviation this type records, and the measurement that backs it. XNA's `InitializeDeviceState`
  # applies `SamplerState.LinearWrap` to every slot when the device is created; this binding does not
  # own device creation, so it seeds the cache with the same object instead — and the claim that the
  # device really is in that state is measured through CNA's own getter rather than assumed.
  def test_the_seeded_cache_matches_what_the_device_actually_reports
    values = with_device do |device|
      collection = device.SamplerStates
      linear_wrap = G::SamplerState::LinearWrap
      [(0...SSC::MAX_SAMPLERS).all? { |slot| collection[slot].equal?(linear_wrap) },
       (0...SSC::MAX_SAMPLERS).map { |slot| [filter_of(collection, slot), address_u_of(collection, slot)] }.uniq,
       [linear_wrap.Filter.value, linear_wrap.AddressU.value],
       (0...SSC::MAX_SAMPLERS).all? { |slot| device.VertexSamplerStates[slot].equal?(linear_wrap) }]
    end
    assert values[0], "every pixel slot is seeded with LinearWrap"
    assert_equal [[0, 0]], values[1], "and CNA reports exactly one state across all sixteen slots"
    assert_equal values[2], values[1].first, "which is LinearWrap's own filter and address"
    assert values[3], "the vertex stage too"
  end

  # `if (index < 0 || index >= pSamplerList.Length) throw new ArgumentOutOfRangeException("index")`,
  # on the getter and the setter alike.
  def test_the_index_bounds
    values = with_device do |device|
      collection = device.SamplerStates
      [collection[0].class,
       collection[15].class,
       (begin; collection[-1]; nil; rescue => e; e.class; end),
       (begin; collection[16]; nil; rescue => e; e.class; end),
       (begin; collection[16] = G::SamplerState::PointClamp; nil; rescue => e; e.class; end),
       (begin; collection["0"]; nil; rescue => e; e.class; end)]
    end
    assert_equal [G::SamplerState, G::SamplerState, RangeError, RangeError, RangeError, TypeError], values
  end

  # `if (value == null) throw new ArgumentNullException("value", NullNotAllowed)` — which is where
  # this collection and `TextureCollection` really differ: that one accepts `null` to unbind, and
  # this one refuses it. The difference is XNA's, and both directions are asserted.
  def test_it_refuses_null_where_the_texture_collection_accepts_it
    values = with_device do |device|
      [(begin; device.SamplerStates[0] = nil; nil; rescue => e; e.class; end),
       (begin; device.Textures[0] = nil; :accepted; rescue => e; e.class; end),
       (begin; device.SamplerStates[0] = G::BlendState::Opaque; nil; rescue => e; e.class; end)]
    end
    assert_equal [ArgumentError, :accepted, TypeError], values
  end

  # A real assignment reaches the device, and the getter still answers the cache rather than the
  # device — both asserted in the same pass, because that is the pairing a paraphrase loses.
  def test_an_assignment_reaches_the_device_and_the_getter_answers_the_cache
    values = with_device do |device|
      collection = device.SamplerStates
      before = [filter_of(collection, 3), address_u_of(collection, 3)]
      collection[3] = G::SamplerState::PointClamp
      after = [filter_of(collection, 3), address_u_of(collection, 3)]
      [before, after, collection[3].equal?(G::SamplerState::PointClamp), collection[3].Name,
       filter_of(collection, 4), device.VertexSamplerStates[3].Name]
    end
    assert_equal [0, 0], values[0], "LinearWrap before"
    assert_equal [1, 1], values[1], "Point and Clamp after"
    assert values[2], "the cache holds the very object that was assigned"
    assert_equal "SamplerState.PointClamp", values[3]
    assert_equal 0, values[4], "and only the slot written changed"
    assert_equal "SamplerState.LinearWrap", values[5], "the other stage is untouched"
  end

  # The short-circuit is **reference** equality, not value equality: re-assigning the same object
  # does nothing, and assigning a distinct but value-identical state does reach the device. The
  # second half is what a `==` short-circuit would get wrong, so it is measured directly.
  def test_the_short_circuit_is_reference_equality
    values = with_device do |device|
      collection = device.SamplerStates
      collection[7] = G::SamplerState::PointClamp
      same = collection[7] = G::SamplerState::PointClamp
      twin = G::SamplerState.new
      twin.Filter = G::TextureFilter::Point
      twin.AddressU = G::TextureAddressMode::Clamp
      twin.AddressV = G::TextureAddressMode::Clamp
      twin.AddressW = G::TextureAddressMode::Clamp
      collection[7] = twin
      [same.equal?(G::SamplerState::PointClamp), collection[7].equal?(twin),
       [filter_of(collection, 7), address_u_of(collection, 7)]]
    end
    assert values[0]
    assert values[1], "a distinct object replaces the cached one even when the values match"
    assert_equal [1, 1], values[2], "and the device still holds the same values"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_device_state_property_effect_or_draw_surface
    # The three state properties left this list when the device's state slice landed; what this
    # milestone claimed, and still claims, is that **it** added neither them nor any draw surface.
    %i[SetRenderTarget DrawPrimitives DrawUserPrimitives].each do |absent|
      refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s
    end
    # The nine `Effect` types left this list when the cluster was built and `RenderTarget2D` when
    # the render targets were; what this milestone claimed, and still claims, is that **it** built
    # none of them, and `SetRenderTarget` above is still absent -- a target that exists is not a
    # target that can be bound.
    %i[BasicEffect]
      .each { |absent| refute G.const_defined?(absent, false), absent.to_s }
    # XNA's own `Apply` stays unprojected on the state it holds, which is what makes the setter's
    # native step this collection's rather than SamplerState's.
    refute G::SamplerState.public_method_defined?(:Apply)
  end
end
