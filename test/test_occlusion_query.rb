# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `OcclusionQuery` — five fields, a state machine, and the one member in this binding whose *getter*
# is what unblocks the next call.
class OcclusionQueryTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.OcclusionQuery"

  # ------------------------------------------------------------------------------- the contract

  def test_it_is_complete_and_derives_from_graphics_resource
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, NAME)
    assert_equal G::GraphicsResource, G::OcclusionQuery.superclass
    refute REFERENCE.fetch(NAME).fetch("sealed")
    # IGraphicsResource is `assembly` and never selected, so nothing here conforms to it.
    assert_equal ["Microsoft.Xna.Framework.Graphics.IGraphicsResource"],
                 REFERENCE.fetch(NAME).fetch("directInterfaces")
    refute G.const_defined?(:IGraphicsResource, false)
  end

  # ------------------------------------------------------------------------------ live behaviour

  class QueryGame < F::Game
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

    game = QueryGame.new { |device| yield device }
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

  def test_a_fresh_query_answers_false_without_asking_the_device
    values = with_device do |device|
      query = G::OcclusionQuery.new(device)
      # The `_hasCalledBegin` short-circuit is XNA's, and every qualified artifact agrees with it
      # anyway: the raw route answers "not complete" for a query that has never run. That is why a
      # mutation removing the guard survives, and it is recorded here rather than left unexplained.
      raw = CNA::Native.library.pointer_for("L", 0)
      CNA::Native.library.call("cna_occlusion_query_get_is_complete",
                               query.__send__(:native_handle), raw)
      result = [query.IsComplete, error_of { query.PixelCount },
                query.GraphicsDevice.equal?(device), query.IsDisposed,
                raw[0, 4].unpack1("L")]
      query.Dispose
      result << query.IsDisposed
    end
    refute values[0], "no Begin has happened, so IsComplete short-circuits on _hasCalledBegin"
    assert_equal [RuntimeError, "DataNotAvailable"], values[1]
    assert values[2]
    refute values[3]
    assert_equal 0, values[4], "and the route beneath it says the same thing"
    assert values[5]
  end

  # The IL's own sequencing, and the rule a reader would not guess: the constructor sets
  # `_hasIsCompleteBeenQueried` true so the **first** Begin is allowed, and every later one needs an
  # IsComplete read in between -- which `Begin` itself clears.
  def test_the_begin_end_sequencing_is_the_ils_own
    values = with_device do |device|
      query = G::OcclusionQuery.new(device)
      first = error_of { query.Begin }
      second = error_of { query.Begin }
      ended = error_of { query.End }
      again = error_of { query.End }
      # `Begin` cleared _hasIsCompleteBeenQueried, so the next one is refused until IsComplete runs.
      before_read = error_of { query.Begin }
      query.IsComplete
      after_read = error_of { query.Begin }
      query.End
      result = [first, second, ended, again, before_read, after_read]
      query.Dispose
      result
    end
    assert_equal :ok, values[0], "the constructor allows the first Begin"
    assert_equal [RuntimeError, "EndMustBeCalledBeforeBegin"], values[1]
    assert_equal :ok, values[2]
    assert_equal [RuntimeError, "BeginMustBeCalledBeforeEnd"], values[3]
    assert_equal [RuntimeError, "IsCompleteMustBeCalled"], values[4]
    assert_equal :ok, values[5], "and one IsComplete read is what lets the next Begin through"
  end

  # An empty interval draws nothing, so a completed query counts nothing. **When** it completes is
  # the renderer's business: the real GL backends answer asynchronously and may still be pending on
  # the first read, while HEADLESS answers immediately.
  def test_an_empty_interval_completes_and_counts_what_was_drawn
    values = with_device do |device|
      query = G::OcclusionQuery.new(device)
      query.Begin
      query.End
      # Read until it settles, bounded: this is a measurement of a real GPU query, not a spin.
      completed = 32.times.find { query.IsComplete } ? true : query.IsComplete
      result = [completed, completed ? query.PixelCount : nil]
      query.Dispose
      result
    end
    assert values[0], "a submitted query completes within thirty-two reads"
    assert_operator values[1], :>=, 0
    assert_operator values[1], :<=, 1, "nothing was drawn, so the count is zero or the boolean one"
  end

  def test_the_constructor_refusals_are_the_ils_own
    values = with_device do |device|
      [error_of { G::OcclusionQuery.new(nil) },
       error_of { G::OcclusionQuery.new(Object.new) },
       error_of { G::OcclusionQuery.new(device, 1) }]
    end
    assert_equal [ArgumentError, "graphicsDevice"], values[0]
    assert_equal TypeError, values[1].first
    assert_equal ArgumentError, values[2].first, "one parameter, and no overload"
  end

  def test_disposal_consumes_the_native_query
    values = with_device do |device|
      query = G::OcclusionQuery.new(device)
      handle = query.__send__(:native_handle)
      query.Dispose
      [query.IsDisposed, error_of { query.Dispose },
       error_of { CNA::Native.library.call("cna_occlusion_query_destroy", handle) },
       error_of { query.Begin }]
    end
    assert values[0]
    assert_equal :ok, values[1], "Dispose is idempotent"
    assert_equal CNA::NativeError, values[2].first, "and the handle is already gone"
    assert_equal CNA::DisposedObjectError, values[3].first
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_draw_surface_and_leaves_the_ext_route_unbound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # XNA has no identity for the precision question, so the route stays unbound however useful it
    # is -- a coverage ratio from a boolean count is 1/area, and CNA says so in its own header.
    refute_includes symbols, "cna_occlusion_query_get_is_pixel_count_precise_ext"
    assert_includes symbols, "cna_occlusion_query_has_renderer"
    %i[DrawPrimitives DrawIndexedPrimitives SetRenderTarget]
      .each { |absent| refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
    # A query holds no layout of its own: every route it uses takes scalars.
    refute CNA::Native::Layouts::STRUCTURES.any? { |structure| structure.to_s.include?("Occlusion") }
  end
end
