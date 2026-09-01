# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s render-target binding slice — `SetRenderTarget`'s two overloads,
# `SetRenderTargets` and `GetRenderTargets`. Four more of the twenty-six the device owed, and the
# members that make a render target *current* rather than merely allocated.
class GraphicsDeviceRenderTargetsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_the_slice_left_the_partial_remainder
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[SetRenderTarget SetRenderTargets GetRenderTargets]
      .each { |member| refute_includes remainder, "::#{member} ", member }
    %w[DrawUserPrimitives Present Reset Adapter].each { |member| assert_includes remainder, "::#{member} ", member }
  end

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

  # Read through raw Fiddle, for the reason the vertex read-backs are: `GetRenderTargets` is an
  # `Array.Copy` over a cached array, so nothing in `lib/` would ever call these two routes.
  def route(name, arguments)
    handle = CNA::Native.library.instance_variable_get(:@handle)
    Fiddle::Function.new(handle[name], arguments, Fiddle::TYPE_UINT32_T)
  end

  def native_target_count(device)
    output = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    output[0, 8] = "\0" * 8
    route("cna_graphics_device_get_render_target_count",
          [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP]).call(device.__send__(:native_handle), output)
    output[0, 8].unpack1("Q")
  end

  def native_bindings(device)
    count = native_target_count(device)
    return [] if count.zero?

    buffer = Fiddle::Pointer.malloc(24 * count, Fiddle::RUBY_FREE)
    buffer[0, 24 * count] = "\0" * (24 * count)
    written = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    written[0, 8] = "\0" * 8
    route("cna_graphics_device_copy_render_targets",
          [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP])
      .call(device.__send__(:native_handle), buffer, count, written)
    Array.new(written[0, 8].unpack1("Q")) do |index|
      handle, slice, face = buffer[(24 * index) + 8, 16].unpack("Ql2")
      { handle: handle, slice: slice, face: face }
    end
  end

  def test_a_bound_target_is_current_and_a_null_restores_the_back_buffer
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 4)
      empty = [device.GetRenderTargets.length, native_target_count(device)]
      device.SetRenderTarget(target)
      bound = [device.GetRenderTargets.length, native_target_count(device),
               device.GetRenderTargets[0].RenderTarget.equal?(target),
               device.GetRenderTargets[0].CubeMapFace.to_s]
      native = native_bindings(device)
      device.SetRenderTarget(nil)
      restored = [device.GetRenderTargets.length, native_target_count(device)]
      target.Dispose
      [empty, bound, native, restored,
       error_of { device.SetRenderTarget(nil, G::CubeMapFace::PositiveY) }]
    end
    assert_equal [0, 0], values[0]
    assert_equal [1, 1, true, "PositiveX"], values[1]
    assert_equal 1, values[2].length
    assert values[2][0].fetch(:handle).positive?
    assert_equal 0, values[2][0].fetch(:slice), "this binding sets no array slice"
    assert_equal [0, 0], values[3], "a null target restores the back buffer rather than raising"
    assert_equal ArgumentError, values[4].first
  end

  def test_a_cube_face_is_carried_through_to_the_binding
    values = with_device do |device|
      cube = G::RenderTargetCube.new(device, 4, false, G::SurfaceFormat::Color, G::DepthFormat::None)
      device.SetRenderTarget(cube, G::CubeMapFace::NegativeY)
      result = [device.GetRenderTargets[0].CubeMapFace.to_s,
                native_bindings(device)[0].fetch(:face),
                device.GetRenderTargets[0].RenderTarget.equal?(cube)]
      device.SetRenderTarget(nil)
      cube.Dispose
      result
    end
    assert_equal "NegativeY", values[0]
    assert_equal G::CubeMapFace::NegativeY.to_i, values[1], "and the face reaches the C structure"
    assert values[2]
  end

  # `SetRenderTargets` is `params`, so the three shapes a caller can write are the same call.
  def test_the_array_overload_validates_before_it_applies
    values = with_device do |device|
      first = G::RenderTarget2D.new(device, 4, 4)
      second = G::RenderTarget2D.new(device, 4, 4)
      small = G::RenderTarget2D.new(device, 2, 2)
      device.SetRenderTargets(G::RenderTargetBinding.new(first), G::RenderTargetBinding.new(second))
      two = [device.GetRenderTargets.length, native_target_count(device)]
      refusals = [error_of { device.SetRenderTargets(G::RenderTargetBinding.new(first), nil) },
                  error_of { device.SetRenderTargets(G::RenderTargetBinding.new(first), G::RenderTargetBinding.new(first)) },
                  error_of { device.SetRenderTargets(G::RenderTargetBinding.new(first), G::RenderTargetBinding.new(small)) },
                  error_of { device.SetRenderTargets(first) }]
      unchanged = [device.GetRenderTargets.length, native_target_count(device)]
      # The array form and the varargs form are the same call, and so is a null one.
      device.SetRenderTargets([G::RenderTargetBinding.new(first)])
      single = device.GetRenderTargets.length
      device.SetRenderTargets(nil)
      cleared = [device.GetRenderTargets.length, native_target_count(device)]
      device.SetRenderTargets
      still_cleared = device.GetRenderTargets.length
      [first, second, small].each(&:Dispose)
      [two, refusals, unchanged, single, cleared, still_cleared]
    end
    assert_equal [2, 2], values[0]
    assert_equal [ArgumentError, "NullNotAllowed"], values[1][0]
    assert_equal [ArgumentError, "CannotSetAlreadyUsedRenderTarget"], values[1][1]
    assert_equal [ArgumentError, "RenderTargetsMustMatch"], values[1][2]
    assert_equal TypeError, values[1][3].first, "a target is not a binding"
    assert_equal [2, 2], values[2], "and a refused call changed nothing"
    assert_equal 1, values[3]
    assert_equal [0, 0], values[4]
    assert_equal 0, values[5], "no argument at all is the same restore"
  end

  # The IL's early-out, and it matters rather than being an optimisation: re-binding a
  # DiscardContents target is what discards its contents.
  def test_an_identical_binding_array_is_not_re_applied
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 4)
      device.SetRenderTarget(target)
      first = device.GetRenderTargets
      device.SetRenderTarget(target)
      second = device.GetRenderTargets
      # A different binding object naming the same target and face is still the same binding.
      device.SetRenderTargets(G::RenderTargetBinding.new(target))
      third = device.GetRenderTargets
      device.SetRenderTarget(nil)
      target.Dispose
      [first[0].equal?(second[0]), second[0].equal?(third[0])]
    end
    assert values[0], "the same call twice keeps the binding it already had"
    assert values[1], "and so does an equal one built separately"
  end

  # `GetRenderTargets` is `newarr` + `Array.Copy`: a fresh array each call, over the same bindings.
  def test_get_render_targets_hands_out_a_fresh_array_each_call
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 4)
      device.SetRenderTarget(target)
      first = device.GetRenderTargets
      second = device.GetRenderTargets
      first << :appended
      result = [first.equal?(second), second.length, device.GetRenderTargets.length,
                first[0].equal?(second[0])]
      device.SetRenderTarget(nil)
      target.Dispose
      result
    end
    refute values[0], "a new array every call"
    assert_equal 1, values[1]
    assert_equal 1, values[2], "so a caller mutating one cannot change what the device holds"
    assert values[3], "and the bindings inside it are the same objects"
  end

  # `RenderTargetsMustMatch` measures a cube by its edge, which is both of its dimensions -- so a
  # cube and a 2D target of the same edge match, and one of a different edge does not.
  def test_a_cube_edge_counts_as_both_dimensions
    values = with_device do |device|
      flat = G::RenderTarget2D.new(device, 4, 4)
      cube = G::RenderTargetCube.new(device, 4, false, G::SurfaceFormat::Color, G::DepthFormat::None)
      other = G::RenderTargetCube.new(device, 2, false, G::SurfaceFormat::Color, G::DepthFormat::None)
      matched = error_of do
        device.SetRenderTargets(G::RenderTargetBinding.new(flat),
                                G::RenderTargetBinding.new(cube, G::CubeMapFace::PositiveX))
      end
      mismatched = error_of do
        device.SetRenderTargets(G::RenderTargetBinding.new(flat),
                                G::RenderTargetBinding.new(other, G::CubeMapFace::PositiveX))
      end
      device.SetRenderTarget(nil)
      [flat, cube, other].each(&:Dispose)
      [matched, mismatched]
    end
    # The managed rule passes -- a 4x4 target and a 4-edge cube are the same shape -- and what
    # happens next is the renderer's business: HEADLESS refuses a cube face alongside another target
    # with CNA_RESULT_NOT_SUPPORTED, which is a capability rather than an XNA rule. Either answer is
    # correct here; an `ArgumentError` would not be.
    if values[0] != :ok
      assert_equal CNA::NativeError, values[0].first
      assert_includes values[0].last, "cube face"
    end
    assert_equal [ArgumentError, "RenderTargetsMustMatch"], values[1],
                 "while the mismatched pair is refused by the managed rule on every artifact"
  end

  def test_a_foreign_target_is_refused
    values = with_device do |device|
      target = G::RenderTarget2D.new(device, 4, 4)
      binding = G::RenderTargetBinding.new(target)
      target.instance_variable_set(:@GraphicsDevice, Object.new)
      result = error_of { device.SetRenderTargets(binding) }
      target.instance_variable_set(:@GraphicsDevice, device)
      target.Dispose
      result
    end
    assert_equal [RuntimeError, "InvalidDevice"], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_draws_nothing_and_binds_no_single_target_route
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # XNA's two single-target overloads forward to the array form, so this projection does too and
    # CNA's two single-target routes have no production caller.
    %w[cna_graphics_device_set_render_target2d cna_graphics_device_set_render_target_cube
       cna_graphics_device_get_render_target_count cna_graphics_device_copy_render_targets
       cna_graphics_device_draw_user_primitives].each { |absent| refute_includes symbols, absent }
    assert_includes symbols, "cna_graphics_device_set_render_targets"
    # The three device-buffer draw calls left this list when the draw slice landed; what is
    # still absent is the user-primitive families, which take the vertices as an argument.
    %i[DrawUserPrimitives DrawUserIndexedPrimitives Present Reset]
      .each { |absent| refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
  end
end
