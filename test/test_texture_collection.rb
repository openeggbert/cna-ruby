# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Graphics.TextureCollection`, and the two `GraphicsDevice` properties that produce one.
#
# Native frontier 4 recorded this type as "the one case where `NATIVE_RUNTIME` was the right word —
# no CNA route at all". That was wrong, and not because the ABI moved: `cna_graphics_device_get_texture`
# and `cna_graphics_device_set_texture` are exported by the **retired 0.7.0 artifact** as well. This
# file exists partly to keep that correction attached to a test rather than only to prose.
class TextureCollectionTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  TC = G::TextureCollection
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze

  # ------------------------------------------------------------------- the contract, from metadata

  def test_its_whole_public_surface_is_one_indexer
    contract = REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.TextureCollection")
    assert contract.fetch("sealed")
    assert_equal 1, contract.fetch("members").length
    member = contract.fetch("members").first
    assert_equal %w[property Item], [member.fetch("kind"), member.fetch("name")]
    assert_equal ["System.Int32"], member.fetch("parameters").map { |p| p.fetch("type") }
    assert_equal %w[public public], [member.fetch("getAccess"), member.fetch("setAccess")]

    # The constructor is `assembly`, so `new` is private under Foundation 25's rule and a consumer
    # reaches one only through the device.
    assert_raises(NoMethodError) { TC.new(nil, 0) }
    # XNA publishes no `Length`, `Count` or enumerator, so neither does this.
    %i[Length Count GetEnumerator each].each { |absent| refute TC.public_method_defined?(absent), absent.to_s }
    assert_equal %i[[] []=], TC.public_instance_methods(false).sort
  end

  def test_the_scoreboard_records_it_complete_and_the_device_gained_two_members
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.TextureCollection"
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Graphics.GraphicsDevice")
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "Textures"
    refute_includes remainder, "VertexTextures"
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") },
                    "Microsoft.Xna.Framework.Graphics.TextureCollection"
  end

  # The correction itself: the routes this type needs were always there.
  def test_the_routes_native_frontier_4_said_did_not_exist
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_graphics_device_get_texture"
    assert_includes symbols, "cna_graphics_device_set_texture"
    # `unbind_texture` is deliberately absent: XNA's collection has no member that unbinds one
    # texture from every slot, so there is no identity to carry it.
    refute_includes symbols, "cna_graphics_device_unbind_texture"
    assert_equal 16, CNA::Native::Manifest::CONSTANTS.fetch("CNA_TEXTURE_COLLECTION_MAX_TEXTURES")
    assert_equal [0, 1], [CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_PIXEL"),
                          CNA::Native::Manifest::CONSTANTS.fetch("CNA_SHADER_STAGE_VERTEX")]
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
    skip "CNA_TEST_PNG not supplied" unless ENV["CNA_TEST_PNG"] && File.file?(ENV["CNA_TEST_PNG"])

    game = DeviceGame.new { |device| yield device }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def texture(device) = File.open(ENV.fetch("CNA_TEST_PNG"), "rb") { |s| G::Texture2D.FromStream(device, s) }

  # Both getters are one `ldfld` over a field the constructor fills, so each answers the same object
  # every time — and the two are different objects, because they address different sampler stages.
  def test_each_property_answers_one_stable_object_and_the_two_are_distinct
    values = with_device do |device|
      [device.Textures.equal?(device.Textures),
       device.VertexTextures.equal?(device.VertexTextures),
       device.Textures.equal?(device.VertexTextures),
       device.Textures.instance_of?(TC)]
    end
    assert_equal [true, true, false, true], values
  end

  # `if (index < 0 || index >= _maxTextures) throw new ArgumentOutOfRangeException("index")`, and an
  # empty slot answers `ldnull`.
  def test_the_index_bounds_and_the_empty_slot
    values = with_device do |device|
      collection = device.Textures
      [collection[0], collection[15],
       (begin; collection[-1]; nil; rescue => e; e.class; end),
       (begin; collection[16]; nil; rescue => e; e.class; end),
       (begin; collection[0] = nil; collection[16] = nil; nil; rescue => e; e.class; end),
       (begin; collection["0"]; nil; rescue => e; e.class; end)]
    end
    assert_nil values[0]
    assert_nil values[1]
    assert_equal [RangeError, RangeError, RangeError, TypeError], values[2..]
  end

  # The getter answers the object that was set, which is the whole reason it keeps a cache: CNA has
  # no route from a native object back to a handle, and says so in its own header.
  def test_a_bound_texture_reads_back_as_the_same_object
    values = with_device do |device|
      collection = device.Textures
      bitmap = texture(device)
      collection[3] = bitmap
      same = collection[3].equal?(bitmap)
      bound = collection.send(:slot_bound?, 3)
      elsewhere = collection[4]
      other_stage = device.VertexTextures[3]
      [same, bound, elsewhere, other_stage]
    end
    assert_equal true, values[0]
    assert_equal true, values[1], "the device really has a texture in that slot"
    assert_nil values[2], "binding one slot must not fill another"
    assert_nil values[3], "the pixel and vertex collections are separate stages"
  end

  def test_assigning_nil_clears_the_slot_in_the_device_as_well_as_the_cache
    values = with_device do |device|
      collection = device.Textures
      collection[2] = texture(device)
      before = [collection[2].nil?, collection.send(:slot_bound?, 2)]
      collection[2] = nil
      after = [collection[2].nil?, collection.send(:slot_bound?, 2)]
      [before, after]
    end
    assert_equal [[false, true], [true, false]], values
  end

  def test_a_disposed_texture_is_refused_and_the_slot_is_untouched
    values = with_device do |device|
      collection = device.Textures
      keeper = texture(device)
      collection[1] = keeper
      dead = texture(device)
      dead.Dispose
      refused = begin; collection[1] = dead; nil; rescue => e; e.class; end
      [refused, collection[1].equal?(keeper)]
    end
    assert_equal [CNA::DisposedObjectError, true]  , values
  end

  # The recorded deviation says a slot filled by canonical CNA code reads back as nil here, because
  # CNA has no route from a native object to a handle and the cache cannot know about a binding it
  # did not make. `bound` is what makes that case detectable rather than silent.
  #
  # The measurement below is the honest limit of that claim on this artifact: `SpriteBatch` is the
  # canonical filler, and after `End` the slot is empty in **both** views — CNA unbinds what it
  # bound. So the divergent case is real per CNA's own header and is **not reachable** from the
  # surface this binding currently projects, and the two views agreeing is what is asserted rather
  # than a divergence that was not observed. If a later milestone adds a member that leaves a slot
  # filled behind it, this is where the deviation becomes visible.
  def test_a_sprite_batch_flush_leaves_both_views_agreeing
    values = with_device do |device|
      bitmap = texture(device)
      batch = G::SpriteBatch.new(device)
      batch.Begin
      batch.Draw(bitmap, F::Vector2.new(0.0, 0.0), F::Color.White)
      batch.End
      collection = device.Textures
      [collection[0], collection.send(:slot_bound?, 0)]
    end
    assert_nil values[0]
    assert_equal false, values[1], "CNA unbinds what its own flush bound, so the two views agree"
  end

  # And the divergence the deviation describes is constructed directly, so the *mechanism* is
  # tested even though no projected member reaches it: bind through the collection, then drop the
  # cache the way a foreign binder would leave it.
  def test_the_cache_is_what_the_getter_answers_and_bound_is_what_the_device_reports
    values = with_device do |device|
      collection = device.Textures
      bitmap = texture(device)
      collection[5] = bitmap
      collection.instance_variable_get(:@bound).delete(5)
      [collection[5], collection.send(:slot_bound?, 5)]
    end
    assert_nil values[0], "the getter answers the cache"
    assert_equal true, values[1], "and `bound` still reports the device, which is the whole point"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_sampler_state_effect_or_draw_surface
    # `SamplerState` left this list when the four state objects were built, and
    # `SamplerStateCollection` in the milestone straight after. What this test claims is unchanged:
    # **this** milestone added neither, and the device members it added were the two texture
    # collections, which the assertion below still pins exactly.
    %i[SamplerState SamplerStateCollection].each { |present| assert G.const_defined?(present, false) }
    # `TextureCube` and `Texture3D` left this list when they were built; what this milestone
    # claimed, and still claims, is that **it** built neither -- it bound two device collections
    # that hold a `Texture`, not a second texture type.
    # The nine `Effect` types left this list when the cluster was built; what this milestone
    # claimed, and still claims, is that **it** built none of them.
    # The five buffer types left this list when they were built; what this milestone claimed,
    # and still claims, is that **it** built none of them.
    # `RenderTarget2D` left this list when the render targets were built; `SetRenderTarget` below
    # is still absent, which is the claim that matters here.
    %i[BasicEffect].each do |absent|
      refute G.const_defined?(absent, false), absent.to_s
    end
    %i[DrawPrimitives DrawIndexedPrimitives DrawUserPrimitives SetRenderTarget
       BlendState DepthStencilState].each do |absent|
      refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s
    end
  end
end
