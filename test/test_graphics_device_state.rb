# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s state slice — the three state objects it holds and the three scalars two of them
# carry, plus the scissor rectangle. Seven of the thirty-seven members the device still owed.
class GraphicsDeviceStateTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
  SLICE = %w[BlendState DepthStencilState RasterizerState BlendFactor MultiSampleMask
             ReferenceStencil ScissorRectangle].freeze

  # ------------------------------------------------------------------------------- the contract

  def test_the_slice_left_the_partial_remainder_and_the_rest_did_not
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME)
    SLICE.each { |member| refute_includes remainder.join(" "), "::#{member} ", member }
    # The device is still partial, and `ReviewedScoreboard` names the whole remainder once rather
    # than each test naming a sample of it.
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING,
                 ReviewedScoreboard.outstanding(STRICT, NAME)
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
  end

  # ------------------------------------------------------------------------------ live behaviour

  class StateGame < F::Game
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

    game = StateGame.new { |device| yield device }
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

  # `InitializeDeviceState` assigns three presets through the setters, so a device answers those
  # objects **by identity** and the two scalars come from them.
  def test_the_three_defaults_are_the_presets_by_identity
    values = with_device do |device|
      [device.BlendState.equal?(G::BlendState::Opaque),
       device.DepthStencilState.equal?(G::DepthStencilState::Default),
       device.RasterizerState.equal?(G::RasterizerState::CullCounterClockwise),
       device.BlendFactor.PackedValue, device.MultiSampleMask, device.ReferenceStencil]
    end
    assert_equal [true, true, true], values[0, 3]
    assert_equal 0xFFFFFFFF, values[3], "Opaque's own blend factor is opaque white"
    assert_equal(-1, values[4])
    assert_equal 0, values[5], "and Default's reference stencil is zero"
  end

  # Assigning a state carries its own two scalars onto the device -- which is what makes a later
  # scalar write leave the state *dirty*, so assigning the same object again really re-applies it.
  def test_a_state_carries_its_scalars_and_a_scalar_write_makes_it_dirty
    values = with_device do |device|
      device.BlendState = G::BlendState::AlphaBlend
      after_state = [device.BlendState.equal?(G::BlendState::AlphaBlend),
                     device.BlendFactor.PackedValue, device.MultiSampleMask]
      device.BlendFactor = F::Color.new(1, 2, 3, 4)
      device.MultiSampleMask = 7
      after_scalars = [device.BlendFactor.PackedValue, device.MultiSampleMask]
      # The same object again: a clean assignment would be a no-op, and this one is not.
      device.BlendState = G::BlendState::AlphaBlend
      reapplied = [device.BlendFactor.PackedValue, device.MultiSampleMask]
      # ...and now it *is* clean, so the scalars survive a redundant assignment.
      device.BlendFactor = F::Color.new(9, 9, 9, 9)
      device.BlendState = G::BlendState::AlphaBlend
      [after_state, after_scalars, reapplied, device.BlendFactor.PackedValue]
    end
    assert_equal [true, 0xFFFFFFFF, -1], values[0]
    assert_equal [0x04030201, 7], values[1]
    assert_equal [0xFFFFFFFF, -1], values[2], "the dirty flag forced a re-apply"
    assert_equal 0xFFFFFFFF, values[3], "and the re-apply restored the state's own factor again"
  end

  def test_the_depth_stencil_pair_behaves_the_same_way
    values = with_device do |device|
      device.DepthStencilState = G::DepthStencilState::None
      first = [device.DepthStencilState.equal?(G::DepthStencilState::None), device.ReferenceStencil]
      device.ReferenceStencil = 5
      after = device.ReferenceStencil
      device.DepthStencilState = G::DepthStencilState::None
      [first, after, device.ReferenceStencil]
    end
    assert_equal [true, 0], values[0]
    assert_equal 5, values[1]
    assert_equal 0, values[2], "the state's own reference stencil came back with it"
  end

  # The rasterizer state is the odd one out: its guard is the object alone, with no dirty flag,
  # because no scalar property shadows part of it. That is observable from the device's own
  # descriptor -- a mutated state object re-assigned is an early return, and nothing is re-applied
  # however dirty the *other* two states are.
  def test_the_rasterizer_state_has_no_dirty_flag
    values = with_device do |device|
      custom = G::RasterizerState.new
      custom.CullMode = G::CullMode::None
      device.RasterizerState = custom
      applied = device_cull_mode(device)
      custom.CullMode = G::CullMode::CullClockwiseFace
      # Both other states are dirty now, and neither has anything to do with this one.
      device.MultiSampleMask = 3
      device.ReferenceStencil = 3
      device.RasterizerState = custom
      [applied, device_cull_mode(device), device.instance_variables.include?(:@rasterizer_state_dirty),
       device.RasterizerState.equal?(custom)]
    end
    assert_equal G::CullMode::None.to_i, values[0]
    assert_equal G::CullMode::None.to_i, values[1],
                 "the same object again is an early return, so the mutated value was never applied"
    refute values[2], "and there is no such flag to keep"
    assert values[3]
  end

  # `CNA_RasterizerState`'s cull mode, read straight back from the device.
  def device_cull_mode(device)
    descriptor = CNA::Native::Layouts::RasterizerState.new
    CNA::Native.library.call("cna_graphics_device_get_rasterizer_state",
                             device.__send__(:native_handle), descriptor.pointer)
    descriptor.read_u32(8)
  end

  def test_the_refusals_are_the_ils_own
    values = with_device do |device|
      [error_of { device.BlendState = nil },
       error_of { device.DepthStencilState = nil },
       error_of { device.RasterizerState = nil },
       error_of { device.BlendState = G::DepthStencilState::Default },
       error_of { device.BlendFactor = 1 },
       error_of { device.MultiSampleMask = "7" },
       error_of { device.ReferenceStencil = 1.5 },
       error_of { device.ScissorRectangle = F::Point.new(1, 2) }]
    end
    assert_equal [[ArgumentError, "value"]] * 3, values[0, 3]
    assert_equal TypeError, values[3].first
    assert_equal TypeError, values[4].first
    assert_equal TypeError, values[5].first
    assert_equal TypeError, values[6].first
    assert_equal TypeError, values[7].first
  end

  # The scissor rectangle is read from the device rather than a cache, and the setter validates
  # against the back buffer -- the only bounds reachable while nothing can bind a render target.
  def test_the_scissor_rectangle_round_trips_and_is_validated_against_the_back_buffer
    values = with_device do |device|
      initial = device.ScissorRectangle
      device.ScissorRectangle = F::Rectangle.new(1, 2, 3, 4)
      written = device.ScissorRectangle
      [[initial.X, initial.Y, initial.Width, initial.Height],
       [written.X, written.Y, written.Width, written.Height],
       error_of { device.ScissorRectangle = F::Rectangle.new(0, 0, initial.Width + 1, 1) },
       error_of { device.ScissorRectangle = F::Rectangle.new(-1, 0, 1, 1) },
       error_of { device.ScissorRectangle = F::Rectangle.new(0, 0, initial.Width, initial.Height) }]
    end
    assert_equal 0, values[0][0]
    assert_operator values[0][2], :>, 0, "the back buffer has a width"
    assert_equal [1, 2, 3, 4], values[1], "the two-eightbyte by-value expansion carries all four"
    assert_equal [ArgumentError, "ScissorInvalid"], values[2]
    assert_equal [ArgumentError, "ScissorInvalid"], values[3]
    assert_equal :ok, values[4], "and the whole back buffer is inside itself"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_draw_target_or_presentation_member
    # `SetVertexBuffer` and `Indices` arrived with the binding slice that followed this one; what
    # this milestone claimed, and still claims, is that **it** added neither.
    # The render-target trio arrived two slices later; what this milestone claimed, and still
    # claims, is that **it** added none of it.
    # The three device-buffer draw calls left this list when the draw slice landed; what is
    # still absent is the user-primitive families, which take the vertices as an argument.
    # `PresentationParameters`, `GraphicsProfile` and `GraphicsDeviceStatus` left this list in
    # Foundation 90 and `Present`/`Reset` in Foundation 92; `DisplayMode` and `Adapter` did not, and
    # will not while CNA answers them with the no-display fallback. Reading the list from
    # `ReviewedScoreboard` is what stops it going stale a member at a time.
    ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING.each do |absent|
      next if absent == ".ctor"

      refute G::GraphicsDevice.public_method_defined?(absent.to_sym), absent
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # Every draw route left this list as its own slice landed, which is the same statement from the
    # other side; nothing *here* draws, and the indirect extensions XNA declares no member for are
    # still unbound.
    %w[cna_graphics_device_draw_primitives_indirect_ext
       cna_graphics_device_draw_indexed_primitives_indirect_ext].each { |absent| refute_includes symbols, absent }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
  end
end
