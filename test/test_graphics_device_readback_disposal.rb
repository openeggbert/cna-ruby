# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GetBackBufferData`'s three overloads and the device's own disposal — the last members
# `GraphicsDevice` owed that anything could build.
#
# What is left after this is three, and all three are the same upstream defect: `.ctor`, `Adapter`
# and `DisplayMode` each need `Graphics.GraphicsAdapter`, whose every route answers invented
# display data (`docs/graphics-adapter-ordering-upstream-defect.md`).
class GraphicsDeviceReadbackDisposalTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_what_the_device_still_owes_is_only_the_adapter_defect
    assert_equal %w[.ctor Adapter DisplayMode], ReviewedScoreboard.outstanding(STRICT, NAME).sort
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING,
                 ReviewedScoreboard.outstanding(STRICT, NAME)
    refute G.const_defined?(:GraphicsAdapter, false),
           "all three are blocked by the type this binding does not project"
  end

  def test_the_six_overloads_are_selected
    signatures = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    device = signatures.fetch("types").find { |type| type.fetch("name") == NAME }
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
                    .fetch("types").find { |type| type.fetch("name") == NAME }
    %w[GetBackBufferData Dispose Finalize].each do |member|
      selected = device.fetch("members").select { |entry| entry.fetch("name") == member }
                       .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      expected = reference.fetch("members").select { |entry| entry.fetch("name") == member }
                          .map { |entry| entry.fetch("parameters").map { |p| p.fetch("type") } }
      assert_equal expected.sort, selected.sort, member
    end
  end

  # One route carries all three readback overloads, because `has_source_rectangle` false is the
  # whole buffer — and the whole-buffer route has no call site, so it is not bound.
  def test_only_the_window_route_is_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_graphics_device_get_backbuffer_data_window"
    refute_includes symbols, "cna_graphics_device_get_backbuffer_data_rgba8"
    # CNA refuses to dispose the game's device through a borrowed handle, by design, so the route
    # has no call site either.
    refute_includes symbols, "cna_graphics_device_dispose"
  end

  class ReadbackGame < F::Game
    attr_reader :result

    def initialize(width = nil, height = nil, &body)
      @body = body
      super()
      manager = F::GraphicsDeviceManager.new(self)
      return if width.nil?

      manager.PreferredBackBufferWidth = width
      manager.PreferredBackBufferHeight = height
      manager.ApplyChanges
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device(width = nil, height = nil, &body)
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = ReadbackGame.new(width, height, &body)
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

  def colours(count) = Array.new(count) { F::Color.new(0, 0, 0, 0) }

  # ------------------------------------------------------------------ the managed guards

  def test_the_argument_guards
    outcomes = with_device do |device|
      data = colours(4)
      {
        nil_data: error_of { device.GetBackBufferData(nil) },
        empty_data: error_of { device.GetBackBufferData([]) },
        not_an_array: error_of { device.GetBackBufferData("abcd") },
        negative_index: error_of { device.GetBackBufferData(data, -1, 1) },
        index_past_end: error_of { device.GetBackBufferData(data, 4, 1) },
        zero_count: error_of { device.GetBackBufferData(data, 0, 0) },
        count_past_end: error_of { device.GetBackBufferData(data, 0, 5) },
        bad_rect: error_of { device.GetBackBufferData(5, data, 0, 4) },
        wrong_arity: error_of { device.GetBackBufferData(data, 0) }
      }
    end
    # `data?.Length ?? 0` in the one-argument overload is what makes a null `data` reach the same
    # `ArgumentNullException` rather than a `NoMethodError`.
    assert_equal [ArgumentError, "data"], outcomes.fetch(:nil_data)
    assert_equal [ArgumentError, "data"], outcomes.fetch(:empty_data)
    assert_equal TypeError, outcomes.fetch(:not_an_array).fetch(0)
    assert_equal [RangeError, "startIndex"], outcomes.fetch(:negative_index)
    assert_equal [RangeError, "startIndex"], outcomes.fetch(:index_past_end)
    assert_equal [RangeError, "elementCount"], outcomes.fetch(:zero_count)
    assert_equal [RangeError, "elementCount"], outcomes.fetch(:count_past_end)
    assert_equal [TypeError, "rect must be a Rectangle or nil"], outcomes.fetch(:bad_rect)
    assert_equal ArgumentError, outcomes.fetch(:wrong_arity).fetch(0)
  end

  # `CannotGetBackBufferActiveRenderTargets` — and it is a managed guard, so it fires on every
  # artifact, including the one that could not read a pixel back anyway.
  def test_a_bound_render_target_refuses_the_read
    outcome = with_device do |device|
      target = G::RenderTarget2D.new(device, 8, 8)
      begin
        device.SetRenderTarget(target)
        bound = error_of { device.GetBackBufferData(colours(4)) }
        device.SetRenderTarget(nil)
        [bound, error_of { device.GetBackBufferData(colours(4)) }.fetch(0)]
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal [RuntimeError, "CannotGetBackBufferActiveRenderTargets"], outcome.fetch(0)
    refute_equal RuntimeError, outcome.fetch(1), "unbinding lets the read reach the renderer again"
  end

  # ------------------------------------------------------------------ what the renderer answers

  # XNA refuses this member on a **Reach** device — it is a HiDef feature and
  # `ProfileCapabilities.GetBackBufferDataSupported` is what says so. `ProfileCapabilities` is not
  # projected, the same decision the draw calls' `ProfileMaxPrimitiveCount` records, so the refusal
  # is CNA's; and CNA refuses for a renderer reason instead. Same shape, different reason, and both
  # are recorded rather than blurred.
  def test_an_artifact_without_honest_readback_refuses
    skip "this artifact reads the back buffer back" if RendererEnvironment.render_target_readback?

    outcome = with_device(8, 4) { |device| error_of { device.GetBackBufferData(colours(32)) } }
    assert_equal CNA::CapabilityError, outcome.fetch(0)
  end

  # The read is real: an 8x4 back buffer cleared to one colour comes back as thirty-two pixels of
  # exactly that colour, through all three overloads.
  def test_all_three_overloads_read_the_cleared_back_buffer
    skip "this artifact has no honest back-buffer readback" unless RendererEnvironment.render_target_readback?

    outcome = with_device(8, 4) do |device|
      device.Clear(F::Color.new(64, 128, 191, 255))
      whole = colours(32)
      device.GetBackBufferData(whole)
      counted = colours(32)
      device.GetBackBufferData(counted, 0, 32)
      window = colours(4)
      device.GetBackBufferData(F::Rectangle.new(0, 0, 2, 2), window, 0, 4)
      [whole, counted, window].map { |data| data.map { |colour| [colour.R, colour.G, colour.B, colour.A] }.uniq }
    end
    outcome.each { |pixels| assert_equal [[64, 128, 191, 255]], pixels }
  end

  # `startIndex` is where the copy begins **in the destination**, so what is before it is untouched.
  def test_the_start_index_writes_into_the_middle_of_the_array
    skip "this artifact has no honest back-buffer readback" unless RendererEnvironment.render_target_readback?

    pixels = with_device(8, 4) do |device|
      device.Clear(F::Color.new(64, 128, 191, 255))
      data = Array.new(6) { F::Color.new(1, 2, 3, 4) }
      device.GetBackBufferData(F::Rectangle.new(0, 0, 2, 2), data, 2, 4)
      data.map { |colour| [colour.R, colour.G, colour.B, colour.A] }
    end
    assert_equal [[1, 2, 3, 4], [1, 2, 3, 4]], pixels.first(2)
    assert_equal Array.new(4) { [64, 128, 191, 255] }, pixels.last(4)
  end

  # "No partial pixel array is written" on `CNA_RESULT_BUFFER_TOO_SMALL`, which is what XNA's own
  # capacity guard means — asking for the whole 8x4 buffer with room for four pixels.
  def test_a_destination_too_small_for_the_whole_buffer_is_refused
    skip "this artifact has no honest back-buffer readback" unless RendererEnvironment.render_target_readback?

    outcome = with_device(8, 4) do |device|
      data = Array.new(4) { F::Color.new(1, 2, 3, 4) }
      [error_of { device.GetBackBufferData(data) },
       data.map { |colour| [colour.R, colour.G, colour.B, colour.A] }.uniq]
    end
    assert_equal CNA::NativeError, outcome.fetch(0).fetch(0)
    assert_equal [[1, 2, 3, 4]], outcome.fetch(1), "and nothing partial was written"
  end

  # ------------------------------------------------------------------ disposal

  # `Dispose()` is `Dispose(true)`, which is `~GraphicsDevice()` — the release plus `Disposing`.
  def test_dispose_releases_the_device_and_raises_disposing_once
    log = []
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    device.Disposing.add(->(sender, _args) { log << sender.equal?(device) })
    refute device.IsDisposed
    device.Dispose
    assert device.IsDisposed
    device.Dispose
    game.Dispose
    assert_equal [true], log, "both destructors return early once the flag is set"
  end

  # `Finalize()` is `Dispose(false)`, which is `!GraphicsDevice()` alone: the release without the
  # event. It is `family` in XNA, so it is protected here.
  def test_finalize_releases_without_raising_disposing
    log = []
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    device.Disposing.add(->(_s, _a) { log << :disposing })
    refute G::GraphicsDevice.public_method_defined?(:Finalize)
    assert G::GraphicsDevice.protected_method_defined?(:Finalize)
    device.__send__(:Finalize)
    assert device.IsDisposed
    assert_empty log
    game.Dispose
    assert_empty log, "and the flag is what stops the later disposal raising it too"
  end

  def test_dispose_false_is_the_same_release_without_the_event
    log = []
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    device.Disposing.add(->(_s, _a) { log << :disposing })
    device.Dispose(false)
    assert device.IsDisposed
    assert_empty log
    game.Dispose
  end

  # A disposed device refuses everything that needs a handle, which is the observable half of the
  # release this binding can perform.
  def test_a_disposed_device_refuses_every_native_member
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    device.Dispose
    %i[Viewport GraphicsProfile GraphicsDeviceStatus PresentationParameters Present Reset].each do |name|
      assert_equal CNA::DisposedObjectError, error_of { device.__send__(name) }.fetch(0), name.to_s
    end
    game.Dispose
  end

  # The declaration cache and the native event registrations go with the device, whichever way it
  # is released.
  def test_disposal_releases_the_declaration_cache_and_the_subscriptions
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = ReadbackGame.new do |device|
      device.DrawUserPrimitives(G::PrimitiveType::TriangleList,
                                Array.new(3) { G::VertexPositionColor.new }, 0, 1)
    rescue StandardError
      nil
    end
    game.Run
    device = game.GraphicsDevice
    refute_nil device.__send__(:instance_variable_get, :@declaration_cache)
    refute_empty device.__send__(:instance_variable_get, :@event_registrations)
    device.Dispose
    assert_nil device.__send__(:instance_variable_get, :@declaration_cache)
    assert_empty device.__send__(:instance_variable_get, :@event_registrations)
    game.Dispose
  end
end
