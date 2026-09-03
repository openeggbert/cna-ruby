# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `RenderTarget2D`, `RenderTargetCube` and the `RenderTargetBinding` that names one — the off-screen
# surfaces this binding could create at the C ABI since Native frontier 6 and could not project.
#
# The two classes are their texture bases with a different creator and a different destroyer, on both
# sides of the boundary: CNA's render-target handle answers `cna_texture2d_get_data`, which is what
# the renderer qualification has been reading back all along.
class RenderTargetsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAMES = %w[RenderTarget2D RenderTargetCube RenderTargetBinding].freeze

  # ------------------------------------------------------------------------------- the contract

  def test_all_three_are_complete_and_derive_from_their_texture_bases
    NAMES.each do |short|
      name = "Microsoft.Xna.Framework.Graphics.#{short}"
      assert_includes STRICT.fetch("completeTypeNames"), name, short
      assert_empty ReviewedScoreboard.partial_remainder(STRICT, name), short
    end
    assert_equal G::Texture2D, G::RenderTarget2D.superclass
    assert_equal G::TextureCube, G::RenderTargetCube.superclass
    # Neither class is sealed and the binding is a sealed struct.
    %w[RenderTarget2D RenderTargetCube].each do |short|
      refute REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.#{short}").fetch("sealed"), short
    end
    binding = REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.RenderTargetBinding")
    assert binding.fetch("sealed")
    assert_equal "struct", binding.fetch("kind")
    # Both classes declare IDynamicGraphicsResource, which is `assembly` and never selected.
    assert_equal ["Microsoft.Xna.Framework.Graphics.IDynamicGraphicsResource"],
                 REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.RenderTarget2D").fetch("directInterfaces")
    refute STRICT.fetch("completeTypeNames").include?("Microsoft.Xna.Framework.Graphics.IDynamicGraphicsResource")
  end

  # ------------------------------------------------------------------------------ live behaviour

  class TargetGame < F::Game
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

    game = TargetGame.new { |device| yield device }
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

  # The three constructors are one method with the IL's own literals as defaults: `(device, w, h)`
  # is mipMap false, Color, None, 0, DiscardContents.
  def test_the_short_constructor_carries_the_ils_own_defaults
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 4)
      result = [target.Width, target.Height, target.LevelCount, target.Format.to_s,
                target.DepthStencilFormat.to_s, target.MultiSampleCount,
                target.RenderTargetUsage.to_s, target.IsContentLost,
                [target.Bounds.X, target.Bounds.Y, target.Bounds.Width, target.Bounds.Height],
                target.GraphicsDevice.equal?(device), target.is_a?(G::Texture2D)]
      target.Dispose
      result
    end
    assert_equal [4, 4, 1, "Color", "None", 0, "DiscardContents", false,
                  [0, 0, 4, 4], true, true], values
  end

  # ...and the eight-argument form is asked for and answered. The values the three properties report
  # are what the target **got**, not what it was asked for: XNA stores GraphicsAdapter.QueryFormat's
  # answers in the RenderTargetHelper, and this projection reads CNA's negotiation back out of
  # cna_render_target_get_info for the same reason.
  def test_the_long_constructor_reports_what_the_target_got
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 8, 8, true, G::SurfaceFormat::Color,
                                     G::DepthFormat::Depth24Stencil8, 4,
                                     G::RenderTargetUsage::PreserveContents)
      result = [target.Width, target.Height, target.LevelCount, target.DepthStencilFormat.to_s,
                target.MultiSampleCount, target.RenderTargetUsage.to_s]
      target.Dispose
      result
    end
    assert_equal [8, 8, 4, "Depth24Stencil8", 4, "PreserveContents"], values,
                 "a mip-mapped 8x8 target has four levels"
  end

  def test_the_constructor_refusals_are_the_texture_bases_own
    values = with_device do |device|
      [error_of { G::RenderTarget2D.new(nil, 4, 4) },
       error_of { G::RenderTarget2D.new(device, 0, 4) },
       error_of { G::RenderTarget2D.new(device, 4, -1) },
       error_of { G::RenderTarget2D.new(device, 4, 4, 1) },
       error_of { G::RenderTarget2D.new(device, 4, 4, false, 99) },
       error_of { G::RenderTargetCube.new(nil, 4, false, G::SurfaceFormat::Color, G::DepthFormat::None) },
       error_of { G::RenderTargetCube.new(device, 0, false, G::SurfaceFormat::Color, G::DepthFormat::None) },
       error_of { G::RenderTargetCube.new(device, 4, false, G::SurfaceFormat::Color) }]
    end
    assert_equal [ArgumentError, "graphicsDevice"], values[0]
    assert_equal [RangeError, "width"], values[1]
    assert_equal [RangeError, "height"], values[2]
    assert_equal TypeError, values[3].first, "mipMap is a bool"
    assert_equal RangeError, values[4].first, "an undeclared SurfaceFormat value"
    assert_equal [ArgumentError, "graphicsDevice"], values[5]
    assert_equal [RangeError, "size"], values[6]
    assert_equal ArgumentError, values[7].first, "the cube has no five-argument-short form"
  end

  def test_a_cube_target_is_a_texture_cube
    values = with_device do |device|
      target = G::RenderTargetCube.new(device, 4, false, G::SurfaceFormat::Color, G::DepthFormat::None)
      result = [target.Size, target.LevelCount, target.Format.to_s, target.RenderTargetUsage.to_s,
                target.IsContentLost, target.is_a?(G::TextureCube)]
      target.Dispose
      result
    end
    assert_equal [4, 1, "Color", "DiscardContents", false, true], values
  end

  # The inherited texture surface is the point of deriving, and it works in one direction.
  #
  # UPSTREAM_CNA_DEFECT, reproduced at the C ABI with no Ruby in the path: `cna_texture2d_set_data`
  # over a **render-target** handle returns `CNA_RESULT_SUCCESS` and writes nothing, while the same
  # call over a plain `Texture2D` handle round-trips exactly. Readback itself is fine -- the renderer
  # qualification clears a target and reads the cleared colour back -- so what is lost is the upload,
  # silently. The projection reports what CNA does rather than inventing a refusal XNA does not have,
  # and this test pins the defect so the record stays honest if CNA changes.
  # See docs/render-target-upload-upstream-defect.md.
  def test_the_inherited_texture_transfer_reads_back_and_the_upload_is_dropped
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 2, 2)
      plain = G::Texture2D.new(device, 2, 2)
      pixels = [F::Color.new(1, 2, 3, 4), F::Color.new(5, 6, 7, 8),
                F::Color.new(9, 10, 11, 12), F::Color.new(13, 14, 15, 16)]
      target.SetData(F::Color, pixels)
      plain.SetData(F::Color, pixels)
      from_target = Array.new(4) { F::Color.new(0, 0, 0, 0) }
      from_plain = Array.new(4) { F::Color.new(0, 0, 0, 0) }
      result = [error_of { target.GetData(F::Color, from_target) }, from_target.map(&:PackedValue),
                error_of { plain.GetData(F::Color, from_plain) }, from_plain.map(&:PackedValue),
                pixels.map(&:PackedValue)]
      target.Dispose
      plain.Dispose
      result
    end
    unless RendererEnvironment.render_target_readback?
      # HEADLESS has no readback of any kind, and says so rather than answering zeros.
      assert_equal CNA::CapabilityError, values[0].first
      assert_includes values[0].last, "GetData"
      return
    end

    assert_equal :ok, values[0], "the readback itself works"
    assert_equal [0, 0, 0, 0], values[1], "and the upload was dropped -- the recorded upstream defect"
    assert_equal :ok, values[2]
    assert_equal values[4], values[3], "while the same upload over a plain texture round-trips"
  end

  # `_contentLost` latches in the IL: once true the getter returns the field without asking again.
  def test_is_content_lost_is_false_and_latches
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 2, 2)
      first = target.IsContentLost
      target.instance_variable_set(:@content_lost, true)
      latched = target.IsContentLost
      result = [first, latched, target.ContentLost.respond_to?(:add)]
      target.Dispose
      result
    end
    refute values[0], "no qualified renderer loses a device"
    assert values[1], "and once lost the getter answers the field"
    assert values[2], "ContentLost is subscribable, and never fires here"
  end

  # ------------------------------------------------------------------------------- the binding

  def test_the_binding_is_two_stores_and_two_reads
    values = with_device do |device|
      flat = G::RenderTarget2D.new(device, 2, 2)
      cube = G::RenderTargetCube.new(device, 2, false, G::SurfaceFormat::Color, G::DepthFormat::None)
      explicit = G::RenderTargetBinding.new(cube, G::CubeMapFace::NegativeZ)
      plain = G::RenderTargetBinding.new(flat)
      implicit = G::RenderTargetBinding.op_Implicit(flat)
      result = [[explicit.CubeMapFace.to_s, explicit.RenderTarget.equal?(cube)],
                [plain.CubeMapFace.to_s, plain.RenderTarget.equal?(flat)],
                implicit == plain, implicit.hash == plain.hash,
                explicit == plain,
                error_of { G::RenderTargetBinding.new(nil) },
                error_of { G::RenderTargetBinding.new(flat, G::CubeMapFace::NegativeZ) },
                error_of { G::RenderTargetBinding.new(G::Texture2D.new(device, 1, 1)) },
                G::RenderTargetBinding.public_method_defined?(:GetHashCode)]
      flat.Dispose
      cube.Dispose
      result
    end
    assert_equal ["NegativeZ", true], values[0]
    assert_equal ["PositiveX", true], values[1], "a 2D binding is face zero"
    assert values[2], "op_Implicit is the one-argument constructor"
    assert values[3]
    refute values[4]
    assert_equal [ArgumentError, "renderTarget"], values[5]
    assert_equal ArgumentError, values[6].first, "a 2D target takes no face"
    assert_equal TypeError, values[7].first, "and a plain texture is not a render target"
    refute values[8], "no GetHashCode identity is published, because XNA declares none"
  end

  def test_disposal_uses_the_render_target_destroyer
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 2, 2)
      handle = target.__send__(:native_handle)
      target.Dispose
      [target.IsDisposed,
       error_of { target.Dispose },
       error_of { CNA::Native.library.call("cna_render_target_destroy", handle) }]
    end
    assert values[0]
    assert_equal :ok, values[1], "Dispose is idempotent"
    assert_equal CNA::NativeError, values[2].first, "and the handle is already gone"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_device_binding_member_and_no_pool
    # Binding a target is GraphicsDevice.SetRenderTarget, which this binding does not project, so
    # the two device routes stay unbound and nothing here can make a target current.
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # `set_render_targets` left this list when the device's render-target slice landed -- which is
    # the same statement from the other side: a target that exists became a target that can be bound,
    # and **this** milestone bound none. The two single-target routes stay unbound because XNA's own
    # overloads forward to the array form.
    %w[cna_graphics_device_set_render_target2d cna_graphics_device_set_render_target_cube
       cna_graphics_device_get_render_target_count
       cna_render_target_pool_create cna_render_target_pool_acquire
       cna_render_target_subscribe_content_lost
       cna_render_target_usage_preserves_contents].each do |absent|
      refute_includes symbols, absent
    end
    # The three device-buffer draw calls left this list when the draw slice landed; what is
    # still absent is the user-primitive families, which take the vertices as an argument.
    %i[Adapter DisplayMode]
      .each { |absent| refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
  end
end
