# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `SpriteBatch.Begin`'s state-bearing overloads — the two of its five that need no `Effect`, and the
# member that finally consumes the four graphics state objects for something other than themselves.
class SpriteBatchBeginStatesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.SpriteBatch"

  # ------------------------------------------------------------------- the contract, from metadata

  # Five overloads; three are projected and the two that take an `Effect` are not, because nothing
  # in this binding produces one.
  def test_three_of_the_five_are_projected_and_the_two_needing_an_effect_are_not
    overloads = REFERENCE.fetch(NAME).fetch("members")
                         .select { |member| member.fetch("name") == "Begin" }
                         .map { |member| member.fetch("parameters").map { |p| p.fetch("type") } }
    assert_equal 5, overloads.length
    with_effect = overloads.select { |types| types.any? { |type| type.end_with?(".Effect") } }
    assert_equal 2, with_effect.length
    assert_equal [0, 2, 5], (overloads - with_effect).map(&:length).sort

    # `Draw`'s three destination-rectangle overloads were built in the milestone straight after,
    # and the two `Effect`-taking `Begin` forms in the one that built the `Effect` cluster, which is
    # what completed the type. What **this** milestone claimed -- that it projected exactly the
    # three needing no `Effect` -- is unchanged, and the two that do are now projected as well.
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, NAME)
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    assert G.const_defined?(:Effect, false), "which is what let the other two be built"
  end

  # ------------------------------------------------------------------------------ live behaviour

  class BatchGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call(G::SpriteBatch.new(self.GraphicsDevice))
    ensure
      self.Exit
    end
  end

  def with_batch
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = BatchGame.new { |batch| yield batch }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def test_all_three_projected_shapes_open_and_close_an_interval
    values = with_batch do |batch|
      results = []
      batch.Begin
      results << batch.End
      batch.Begin(G::SpriteSortMode::Deferred, G::BlendState::Opaque)
      results << batch.End
      batch.Begin(G::SpriteSortMode::Deferred, G::BlendState::AlphaBlend, G::SamplerState::LinearClamp,
                  G::DepthStencilState::None, G::RasterizerState::CullCounterClockwise)
      results << batch.End
      results
    end
    assert_equal [nil, nil, nil], values
  end

  # `SetRenderState` substitutes `BlendState.AlphaBlend`, `SamplerState.LinearClamp`,
  # `DepthStencilState.None` and `RasterizerState.CullCounterClockwise` for a null field, so passing
  # nils must behave exactly as passing those four objects.
  def test_a_nil_state_is_the_ils_own_default
    values = with_batch do |batch|
      implicit = begin
        batch.Begin(G::SpriteSortMode::Deferred, nil, nil, nil, nil)
        batch.End
        :ok
      rescue => error
        [error.class, error.message]
      end
      explicit = begin
        batch.Begin(G::SpriteSortMode::Deferred, G::BlendState::AlphaBlend, G::SamplerState::LinearClamp,
                    G::DepthStencilState::None, G::RasterizerState::CullCounterClockwise)
        batch.End
        :ok
      rescue => error
        [error.class, error.message]
      end
      # The two-argument overload leaves the other three null, which is the same substitution.
      two = begin
        batch.Begin(G::SpriteSortMode::Deferred, nil)
        batch.End
        :ok
      rescue => error
        [error.class, error.message]
      end
      [implicit, explicit, two]
    end
    assert_equal %i[ok ok ok], values
  end

  # UPSTREAM_CNA_DEFECT, reproduced rather than hidden: the route documents "or null for AlphaBlend"
  # and refuses a null descriptor. The projection therefore resolves the default itself -- which is
  # what `SetRenderState` does anyway -- and the raw route is asserted to still refuse, so the
  # document stays honest if CNA changes.
  def test_the_route_still_refuses_the_null_its_header_documents
    values = with_batch do |batch|
      handle = batch.__send__(:native_handle)
      begin
        CNA::Native.library.call("cna_sprite_batch_begin_with_effect", handle,
                                 G::SpriteSortMode::Deferred.to_i, 0, 0, 0, 0, 0, 0)
        :accepted
      rescue => error
        [error.class, error.message]
      end
    end
    assert_equal CNA::NativeError, values[0]
    assert_includes values[1], "BlendState descriptor is invalid"
  end

  def test_the_arity_and_type_refusals
    values = with_batch do |batch|
      [(begin; batch.Begin(G::SpriteSortMode::Deferred); nil; rescue => e; e.class; end),
       (begin; batch.Begin(G::SpriteSortMode::Deferred, 0); nil; rescue => e; e.class; end),
       (begin; batch.Begin(G::SpriteSortMode::Deferred, G::BlendState::Opaque, G::BlendState::Opaque,
                           nil, nil); nil; rescue => e; e.class; end),
       # An Integer coerces to the declared enum value, as every enum-typed parameter here does;
       # an undeclared one does not.
       (begin; batch.Begin(0, nil); batch.End; :coerced; rescue => e; e.class; end),
       (begin; batch.Begin(99, nil); nil; rescue => e; e.class; end),
       (begin
          batch.Begin
          batch.Begin(G::SpriteSortMode::Deferred, nil)
          nil
        rescue => e
          batch.End
          e.class
        end)]
    end
    assert_equal [ArgumentError, TypeError, TypeError, :coerced, RangeError,
                  CNA::InvalidBindingStateError], values
  end

  # The four state objects are now consumed by something other than themselves, and the descriptor a
  # state writes is the same one the sampler collection writes -- one mapping, two callers.
  def test_the_state_descriptor_is_shared_with_the_sampler_collection
    descriptor = G::SamplerState::PointClamp.__send__(:to_native_descriptor)
    assert_instance_of CNA::Native::Layouts::SamplerState, descriptor
    assert_equal G::TextureAddressMode::Clamp.to_i, descriptor.read_u32(8)
    assert_equal G::TextureFilter::Point.to_i, descriptor.read_u32(20)
    %i[BlendState DepthStencilState RasterizerState SamplerState].each do |name|
      assert G.const_get(name).private_method_defined?(:to_native_descriptor), name.to_s
    end
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_effect_transform_or_device_state_property
    # `Effect` left this list when the cluster was built; what this milestone claimed, and still
    # claims, is that **it** built none of it -- three Begin overloads and no effect surface.
    # The three device state properties left this list when the device's own state slice landed;
    # what this milestone claimed, and still claims, is that **it** added none of them -- it passed
    # four state descriptors to one SpriteBatch route and touched no device property.
    %i[SetRenderTarget DrawPrimitives].each do |absent|
      refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # `begin_with_states` stays unbound: `begin_with_effect` is the route XNA's seven-argument
    # Begin maps to, and its last two parameters are what the Effect-taking overloads now fill.
    refute_includes symbols, "cna_sprite_batch_begin_with_states"
    assert_includes symbols, "cna_sprite_batch_begin_with_effect"
    assert_includes symbols, "cna_sprite_batch_begin"
  end
end
