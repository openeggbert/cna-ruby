# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The four graphics state objects — `BlendState`, `DepthStencilState`, `RasterizerState` and
# `SamplerState`. They arrived on the dependency frontier the moment `GraphicsResource` completed,
# all four reported `NATIVE_RUNTIME`, and the audit that word demands found the ninth instance of
# the same fallacy: what makes each type native-reachable is `Apply`, which is `assembly`-visible in
# XNA, is not in the pinned contract, and is therefore not a projected identity at all. The public
# surface is a constructor, an inherited `Dispose`, properties and static presets — managed, every
# one of them.
#
# Values are derived from the pinned Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…) and
# then **cross-checked against CNA's own** `cna_*_state_init` presets, field by field. One
# disagreement was found and is asserted as a disagreement rather than reconciled.
class GraphicsStateObjectsTest < Minitest::Test
  G = Microsoft::Xna::Framework::Graphics
  F = Microsoft::Xna::Framework
  L = CNA::Native::Layouts
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze

  NAMES = %w[
    Microsoft.Xna.Framework.Graphics.BlendState
    Microsoft.Xna.Framework.Graphics.DepthStencilState
    Microsoft.Xna.Framework.Graphics.RasterizerState
    Microsoft.Xna.Framework.Graphics.SamplerState
  ].freeze

  # ------------------------------------------------------------------ the audit, before the work

  # The blocker word named a member the contract does not have. `Apply` is the **only** thing that
  # makes any of the four native-reachable, and it is `assembly` in the IL, so no consumer of this
  # binding could ever call it and no identity is lost by not projecting it.
  def test_the_native_reachability_is_an_internal_member_the_contract_never_selects
    NAMES.each do |name|
      entry = IL.fetch("types").fetch(name)
      assert entry.fetch("nativeReachable"), name
      assert_equal ["Apply"], entry.fetch("nativeReachableMethods"), name
      refute_includes REFERENCE.fetch(name).fetch("members").map { |m| m.fetch("name") }, "Apply", name
    end
  end

  def test_the_four_are_complete_and_left_the_frontier
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    candidates = FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }
    NAMES.each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      refute_includes candidates, name
      assert_equal "Microsoft.Xna.Framework.Graphics.GraphicsResource", REFERENCE.fetch(name).fetch("baseType")
    end
    # Completing SamplerState uncovered the collection built out of it, which is what completing a
    # base always does on this frontier.
    assert_includes candidates, "Microsoft.Xna.Framework.Graphics.SamplerStateCollection"
  end

  # ------------------------------------------------------------------------ the defaults, from IL

  def test_blend_state_defaults_are_the_il_set_defaults
    state = G::BlendState.new
    assert_equal G::Blend::One, state.ColorSourceBlend
    assert_equal G::Blend::Zero, state.ColorDestinationBlend
    assert_equal G::BlendFunction::Add, state.ColorBlendFunction
    assert_equal G::Blend::One, state.AlphaSourceBlend
    assert_equal G::Blend::Zero, state.AlphaDestinationBlend
    assert_equal G::BlendFunction::Add, state.AlphaBlendFunction
    assert_equal [G::ColorWriteChannels::All] * 4,
                 [state.ColorWriteChannels, state.ColorWriteChannels1,
                  state.ColorWriteChannels2, state.ColorWriteChannels3]
    assert_equal F::Color.White, state.BlendFactor
    assert_equal(-1, state.MultiSampleMask)
  end

  def test_depth_stencil_state_defaults_are_the_il_set_defaults
    state = G::DepthStencilState.new
    assert state.DepthBufferEnable
    assert state.DepthBufferWriteEnable
    assert_equal G::CompareFunction::LessEqual, state.DepthBufferFunction
    refute state.StencilEnable
    refute state.TwoSidedStencilMode
    assert_equal [G::CompareFunction::Always] * 2,
                 [state.StencilFunction, state.CounterClockwiseStencilFunction]
    assert_equal [G::StencilOperation::Keep] * 6,
                 [state.StencilPass, state.StencilFail, state.StencilDepthBufferFail,
                  state.CounterClockwiseStencilPass, state.CounterClockwiseStencilFail,
                  state.CounterClockwiseStencilDepthBufferFail]
    assert_equal [-1, -1, 0], [state.StencilMask, state.StencilWriteMask, state.ReferenceStencil]
  end

  def test_rasterizer_and_sampler_defaults_are_the_il_set_defaults
    rasterizer = G::RasterizerState.new
    assert_equal G::CullMode::CullCounterClockwiseFace, rasterizer.CullMode
    assert_equal G::FillMode::Solid, rasterizer.FillMode
    refute rasterizer.ScissorTestEnable
    assert rasterizer.MultiSampleAntiAlias
    assert_equal [0.0, 0.0], [rasterizer.DepthBias, rasterizer.SlopeScaleDepthBias]

    sampler = G::SamplerState.new
    assert_equal G::TextureFilter::Linear, sampler.Filter
    assert_equal [G::TextureAddressMode::Wrap] * 3,
                 [sampler.AddressU, sampler.AddressV, sampler.AddressW]
    assert_equal [4, 0, 0.0],
                 [sampler.MaxAnisotropy, sampler.MaxMipLevel, sampler.MipMapLevelOfDetailBias]
  end

  # ------------------------------------------------------------------------------- the presets

  # Each preset is one private constructor that runs `SetDefaults` and then assigns its arguments,
  # so what a preset differs from the default state by is exactly its constructor arguments and
  # nothing else. That is asserted rather than described: every other property matches a fresh one.
  def test_each_preset_differs_from_a_fresh_state_only_where_its_constructor_assigns
    {
      G::BlendState::Opaque => { ColorSourceBlend: G::Blend::One, ColorDestinationBlend: G::Blend::Zero,
                                 AlphaSourceBlend: G::Blend::One, AlphaDestinationBlend: G::Blend::Zero },
      G::BlendState::AlphaBlend => { ColorSourceBlend: G::Blend::One,
                                     ColorDestinationBlend: G::Blend::InverseSourceAlpha,
                                     AlphaSourceBlend: G::Blend::One,
                                     AlphaDestinationBlend: G::Blend::InverseSourceAlpha },
      G::BlendState::Additive => { ColorSourceBlend: G::Blend::SourceAlpha,
                                   ColorDestinationBlend: G::Blend::One,
                                   AlphaSourceBlend: G::Blend::SourceAlpha,
                                   AlphaDestinationBlend: G::Blend::One },
      G::BlendState::NonPremultiplied => { ColorSourceBlend: G::Blend::SourceAlpha,
                                           ColorDestinationBlend: G::Blend::InverseSourceAlpha,
                                           AlphaSourceBlend: G::Blend::SourceAlpha,
                                           AlphaDestinationBlend: G::Blend::InverseSourceAlpha },
      G::DepthStencilState::None => { DepthBufferEnable: false, DepthBufferWriteEnable: false },
      G::DepthStencilState::Default => { DepthBufferEnable: true, DepthBufferWriteEnable: true },
      G::DepthStencilState::DepthRead => { DepthBufferEnable: true, DepthBufferWriteEnable: false },
      G::RasterizerState::CullNone => { CullMode: G::CullMode::None },
      G::RasterizerState::CullClockwise => { CullMode: G::CullMode::CullClockwiseFace },
      G::RasterizerState::CullCounterClockwise => { CullMode: G::CullMode::CullCounterClockwiseFace },
      G::SamplerState::PointWrap => { Filter: G::TextureFilter::Point, AddressU: G::TextureAddressMode::Wrap,
                                      AddressV: G::TextureAddressMode::Wrap, AddressW: G::TextureAddressMode::Wrap },
      G::SamplerState::AnisotropicClamp => { Filter: G::TextureFilter::Anisotropic,
                                             AddressU: G::TextureAddressMode::Clamp,
                                             AddressV: G::TextureAddressMode::Clamp,
                                             AddressW: G::TextureAddressMode::Clamp }
    }.each do |preset, assigned|
      fresh = preset.class.new
      properties(preset.class).each do |property|
        expected = assigned.key?(property) ? assigned.fetch(property) : fresh.public_send(property)
        assert_equal expected, preset.public_send(property), "#{preset.Name}##{property}"
      end
    end
  end

  # The default state really is one of the presets in three of the four families, which is a fact
  # about XNA rather than a coincidence of this projection.
  def test_three_of_the_four_defaults_coincide_with_a_named_preset
    assert_state_equal G::BlendState.new, G::BlendState::Opaque
    assert_state_equal G::DepthStencilState.new, G::DepthStencilState::Default
    assert_state_equal G::RasterizerState.new, G::RasterizerState::CullCounterClockwise
    assert_state_equal G::SamplerState.new, G::SamplerState::LinearWrap
  end

  def test_the_preset_names_are_the_ils_own_strings
    assert_equal %w[BlendState.Opaque BlendState.AlphaBlend BlendState.Additive
                    BlendState.NonPremultiplied],
                 [G::BlendState::Opaque, G::BlendState::AlphaBlend, G::BlendState::Additive,
                  G::BlendState::NonPremultiplied].map(&:Name)
    assert_equal %w[DepthStencilState.None DepthStencilState.Default DepthStencilState.DepthRead],
                 [G::DepthStencilState::None, G::DepthStencilState::Default,
                  G::DepthStencilState::DepthRead].map(&:Name)
    assert_equal %w[RasterizerState.CullNone RasterizerState.CullClockwise
                    RasterizerState.CullCounterClockwise],
                 [G::RasterizerState::CullNone, G::RasterizerState::CullClockwise,
                  G::RasterizerState::CullCounterClockwise].map(&:Name)
    assert_equal %w[SamplerState.PointWrap SamplerState.PointClamp SamplerState.LinearWrap
                    SamplerState.LinearClamp SamplerState.AnisotropicWrap
                    SamplerState.AnisotropicClamp],
                 [G::SamplerState::PointWrap, G::SamplerState::PointClamp, G::SamplerState::LinearWrap,
                  G::SamplerState::LinearClamp, G::SamplerState::AnisotropicWrap,
                  G::SamplerState::AnisotropicClamp].map(&:Name)
    # `ToString` is GraphicsResource's, and a named resource answers its name.
    assert_equal "BlendState.Additive", G::BlendState::Additive.ToString
    assert_equal "BlendState", G::BlendState.new.ToString
  end

  # ----------------------------------------------------------------------------- ThrowIfBound

  # `isBound` is set by the preset constructor and by `Apply`. Only the first is reachable here, so
  # a preset refuses every setter and a fresh state accepts every one — measured in both directions
  # for every property of all four types, not for one example.
  def test_every_preset_setter_refuses_and_every_fresh_setter_accepts
    [[G::BlendState::Opaque, G::BlendState.new],
     [G::DepthStencilState::Default, G::DepthStencilState.new],
     [G::RasterizerState::CullNone, G::RasterizerState.new],
     [G::SamplerState::PointClamp, G::SamplerState.new]].each do |bound, fresh|
      properties(fresh.class).each do |property|
        value = fresh.public_send(property)
        error = assert_raises(RuntimeError, "#{bound.Name}##{property}") do
          bound.public_send(:"#{property}=", value)
        end
        assert_includes error.message, bound.class.name.split("::").last
        assert_includes error.message, "bound"
        # And the refusal really refused: the preset still answers what it did.
        refute_equal value.object_id, bound.public_send(property).object_id if value.is_a?(F::Color)

        fresh.public_send(:"#{property}=", value)
      end
    end
  end

  # `System.InvalidOperationException` projects to `RuntimeError` through the measured BCL register,
  # which is what makes the exception above the right one rather than a convenient one.
  def test_the_refusal_is_the_projected_invalid_operation_exception
    assert_equal "RuntimeError",
                 CNA::Runtime::BclProjection::THROWN_EXCEPTIONS
                   .fetch("System.InvalidOperationException")
  end

  # ------------------------------------------------------------- the GraphicsResource inheritance

  # These are the first `GraphicsResource` subclasses in this binding that own **no native handle
  # and no device**: the IL's constructors call `Object::.ctor()` and then `SetDefaults`, so
  # `GraphicsDevice` is genuinely null until `Apply` binds one, and `Apply` is not projected.
  def test_they_are_graphics_resources_with_no_device_and_no_handle
    NAMES.each do |name|
      klass = Object.const_get(name.gsub(".", "::").sub("Microsoft::Xna::Framework", "Microsoft::Xna::Framework"))
      state = klass.new
      assert klass < G::GraphicsResource, name
      assert_nil state.GraphicsDevice, name
      refute state.IsDisposed, name
      assert_nil state.instance_variable_get(:@native_handle), name
      assert_nil state.Tag, name
    end
  end

  # Disposal is the base's contract and nothing else: idempotent, `Disposing` raised by an explicit
  # `Dispose` and by nothing else, and `IsDisposed` true before the handler sees it.
  def test_disposal_is_the_inherited_contract
    state = G::BlendState.new
    observed = []
    state.Disposing.add(->(sender, _args) { observed << [sender.equal?(state), sender.IsDisposed] })
    state.Dispose
    assert_equal [[true, true]], observed
    assert state.IsDisposed
    state.Dispose
    assert_equal 1, observed.length, "disposal is idempotent"

    finalized = G::BlendState.new
    finalized.Disposing.add(->(_s, _a) { flunk "the finalizer path announces nothing" })
    finalized.__send__(:Finalize)
    assert finalized.IsDisposed
  end

  # No Ruby finalizer is registered for any of them: nothing in this binding is released by the
  # garbage collector. The check is on code rather than on the word, because `GC.SuppressFinalize`
  # is discussed in comments throughout.
  def test_no_finalizer_is_registered
    source = ROOT.join("lib", "cna", "runtime", "graphics_state.rb").read.lines
                 .reject { |line| line.strip.start_with?("#") }.join
    refute_includes source, "define_finalizer"
    refute_includes source, "ObjectSpace"
  end

  # --------------------------------------------------------------- typing, which is this binding's

  # The IL validates **nothing** in these setters — an undeclared enum value is stored. What refuses
  # a wrong value here is the projection's typing, and that difference is recorded rather than
  # presented as XNA's rule.
  def test_the_setters_refuse_by_type_where_xna_stores_anything
    state = G::BlendState.new
    assert_raises(TypeError) { state.ColorSourceBlend = 0 }
    assert_raises(TypeError) { state.ColorSourceBlend = G::BlendFunction::Add }
    assert_raises(TypeError) { state.MultiSampleMask = 1.5 }
    assert_raises(RangeError) { state.MultiSampleMask = 2**31 }
    assert_raises(TypeError) { state.BlendFactor = "white" }

    depth = G::DepthStencilState.new
    assert_raises(TypeError) { depth.DepthBufferEnable = 1 }
    assert_raises(TypeError) { depth.DepthBufferEnable = nil }

    rasterizer = G::RasterizerState.new
    rasterizer.DepthBias = 1
    assert_equal 1.0, rasterizer.DepthBias, "an Integer is a Single the CLR would widen"
    assert_raises(TypeError) { rasterizer.DepthBias = "0" }
  end

  # `Color` is a value type, so the property must not hand out the object it stores.
  def test_the_color_property_copies_in_both_directions
    state = G::BlendState.new
    colour = F::Color.new(1, 2, 3, 4)
    state.BlendFactor = colour
    refute_same colour, state.BlendFactor
    refute_same state.BlendFactor, state.BlendFactor
    assert_equal colour, state.BlendFactor

    colour.R = 250
    assert_equal 1, state.BlendFactor.R, "mutating the argument afterwards must not reach the state"
  end

  # ------------------------------------------------------- the cross-check against CNA's own values

  # Every projected preset is asserted equal to what `cna_*_state_init` answers, field by field.
  # This is what makes the derivation measured rather than merely self-consistent: two independent
  # authorities — the pinned XNA IL and the qualified CNA artifact — agree on 63 of the 65 values.
  def test_the_projected_presets_agree_with_cnas_own_field_by_field
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    blend = L::BlendState.new
    { 4 => G::BlendState::Opaque, 2 => G::BlendState::AlphaBlend, 1 => G::BlendState::Additive,
      3 => G::BlendState::NonPremultiplied, 0 => G::BlendState.new }.each do |preset, state|
      CNA::Native.library.call("cna_blend_state_init", preset, blend.pointer)
      assert_equal blend.read_u32(8), state.AlphaBlendFunction.value, state.Name.to_s
      assert_equal blend.read_u32(12), state.AlphaDestinationBlend.value, state.Name.to_s
      assert_equal blend.read_u32(16), state.AlphaSourceBlend.value, state.Name.to_s
      assert_equal blend.read_u32(20), state.ColorBlendFunction.value, state.Name.to_s
      assert_equal blend.read_u32(24), state.ColorDestinationBlend.value, state.Name.to_s
      assert_equal blend.read_u32(28), state.ColorSourceBlend.value, state.Name.to_s
      assert_equal [blend.read_u32(32), blend.read_u32(36), blend.read_u32(40), blend.read_u32(44)],
                   [state.ColorWriteChannels.value, state.ColorWriteChannels1.value,
                    state.ColorWriteChannels2.value, state.ColorWriteChannels3.value]
      assert_equal blend.pointer[48, 4].unpack("C4"),
                   [state.BlendFactor.R, state.BlendFactor.G, state.BlendFactor.B, state.BlendFactor.A]
      assert_equal blend.read_i32(52), state.MultiSampleMask
    end

    rasterizer = L::RasterizerState.new
    { 0 => G::RasterizerState.new, 1 => G::RasterizerState::CullClockwise,
      2 => G::RasterizerState::CullCounterClockwise, 3 => G::RasterizerState::CullNone }.each do |preset, state|
      CNA::Native.library.call("cna_rasterizer_state_init", preset, rasterizer.pointer)
      assert_equal rasterizer.read_u32(8), state.CullMode.value, state.Name.to_s
      assert_equal rasterizer.read_u32(12), state.FillMode.value, state.Name.to_s
      assert_equal rasterizer.read_f32(16), state.DepthBias, state.Name.to_s
      assert_equal rasterizer.read_f32(20), state.SlopeScaleDepthBias, state.Name.to_s
      assert_equal rasterizer.read_u8(24) == 1, state.MultiSampleAntiAlias, state.Name.to_s
      assert_equal rasterizer.read_u8(25) == 1, state.ScissorTestEnable, state.Name.to_s
    end

    sampler = L::SamplerState.new
    { 0 => G::SamplerState.new, 1 => G::SamplerState::AnisotropicClamp,
      2 => G::SamplerState::AnisotropicWrap, 3 => G::SamplerState::LinearClamp,
      4 => G::SamplerState::LinearWrap, 5 => G::SamplerState::PointClamp,
      6 => G::SamplerState::PointWrap }.each do |preset, state|
      CNA::Native.library.call("cna_sampler_state_init", preset, sampler.pointer)
      assert_equal sampler.read_u32(8), state.AddressU.value, state.Name.to_s
      assert_equal sampler.read_u32(12), state.AddressV.value, state.Name.to_s
      assert_equal sampler.read_u32(16), state.AddressW.value, state.Name.to_s
      assert_equal sampler.read_u32(20), state.Filter.value, state.Name.to_s
      assert_equal sampler.read_i32(24), state.MaxAnisotropy, state.Name.to_s
      assert_equal sampler.read_i32(28), state.MaxMipLevel, state.Name.to_s
      assert_equal sampler.read_f32(32), state.MipMapLevelOfDetailBias, state.Name.to_s
    end
  end

  # The one disagreement, isolated. XNA's `SetDefaults` writes `ldc.i4.m1` into both stencil masks;
  # CNA answers `Int32.MaxValue`. `-1` is every bit of the D3D9 DWORD mask and `0x7FFFFFFF` drops
  # the top one, so on any stencil buffer XNA can create the two are behaviourally identical -- but
  # the value a consumer reads back is not, and the pinned IL is this binding's authority.
  # Classified UPSTREAM_CNA_DIVERGENCE, reproduced rather than reconciled: if CNA changes, this
  # fails and says so.
  def test_the_stencil_masks_are_where_cna_and_the_pinned_il_disagree
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    depth = L::DepthStencilState.new
    { 0 => G::DepthStencilState::Default, 1 => G::DepthStencilState::DepthRead,
      2 => G::DepthStencilState::None }.each do |preset, state|
      CNA::Native.library.call("cna_depth_stencil_state_init", preset, depth.pointer)
      assert_equal depth.read_u8(8) == 1, state.DepthBufferEnable, state.Name
      assert_equal depth.read_u8(9) == 1, state.DepthBufferWriteEnable, state.Name
      assert_equal depth.read_u8(10) == 1, state.StencilEnable, state.Name
      assert_equal depth.read_u8(11) == 1, state.TwoSidedStencilMode, state.Name
      assert_equal depth.read_u32(12), state.DepthBufferFunction.value, state.Name
      assert_equal depth.read_u32(16), state.StencilFunction.value, state.Name
      assert_equal depth.read_i32(28), state.ReferenceStencil, state.Name
      assert_equal [depth.read_u32(32), depth.read_u32(36), depth.read_u32(40)],
                   [state.StencilFail.value, state.StencilDepthBufferFail.value, state.StencilPass.value]
      assert_equal depth.read_u32(44), state.CounterClockwiseStencilFunction.value, state.Name
      assert_equal [depth.read_u32(48), depth.read_u32(52), depth.read_u32(56)],
                   [state.CounterClockwiseStencilFail.value,
                    state.CounterClockwiseStencilDepthBufferFail.value,
                    state.CounterClockwiseStencilPass.value]

      # The divergence, in both directions so neither side is assumed.
      assert_equal 2_147_483_647, depth.read_i32(20), "CNA answers Int32.MaxValue"
      assert_equal 2_147_483_647, depth.read_i32(24), "CNA answers Int32.MaxValue"
      assert_equal(-1, state.StencilMask, "the pinned IL writes ldc.i4.m1")
      assert_equal(-1, state.StencilWriteMask, "the pinned IL writes ldc.i4.m1")
    end
  end

  # The four routes take no handle at all, which is why the whole cross-check runs without a Game,
  # a GraphicsDevice or a renderer.
  def test_the_four_init_routes_need_no_handle
    %w[cna_blend_state_init cna_depth_stencil_state_init
       cna_rasterizer_state_init cna_sampler_state_init].each do |symbol|
      entry = CNA::Native::Manifest::FUNCTIONS.find { |item| item.symbol == symbol }
      refute_nil entry, symbol
      refute_includes entry.c_arguments, "CNA_Handle", symbol
      assert_equal 2, entry.c_arguments.length, symbol
    end
    # And the device-facing halves of that header stay unbound: applying a state is
    # GraphicsDevice's surface, and XNA's own Apply is not a projected identity.
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[cna_graphics_device_set_blend_state cna_graphics_device_get_blend_state
       cna_graphics_device_set_sampler_state cna_sprite_batch_begin_with_states].each do |symbol|
      refute_includes symbols, symbol
    end
  end

  private

  def properties(klass)
    klass.public_instance_methods(false).grep_v(/=\z/).sort
  end

  def assert_state_equal(left, right)
    properties(left.class).each do |property|
      assert_equal right.public_send(property), left.public_send(property),
                   "#{left.class}##{property}"
    end
  end
end
