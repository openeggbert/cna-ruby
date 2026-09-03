# frozen_string_literal: true

require "minitest/autorun"
require "fiddle"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `GraphicsDevice::Viewport`'s **setter**, and the end of the one `PROPERTY_MAPPING_MISMATCH` this
# project carried for its whole history.
#
# The mismatch was `selection.json`'s `"override": { "set": false }` on that property, and the
# reason recorded beside it had stopped being examined. It was never a Ruby language limitation:
# `cna_graphics_device_set_viewport` is exported by both admitted artifacts, and what stood in
# front of it is that `CNA_Viewport` is a **24-byte** aggregate passed by value. The System V
# x86-64 classification puts an aggregate larger than two eightbytes in MEMORY — it is pushed onto
# the stack — and Fiddle only ever fills argument registers, which is why the `by_value` expansion
# `CNA_StringView` uses cannot express it.
#
# `Manifest.by_value_memory` expands it the way the ABI really passes it: five integer-register
# fillers, then the three eightbytes that overflow onto the stack at exactly the offsets the callee
# reads. The disassembly says so — the function reads its handle from `%rdi` and its viewport from
# `0x10(%rbp)`, the first stack slot — the ABI gate re-derives both numbers from the struct's
# measured `sizeof`, and the two tests at the bottom of this file measure the call itself in both
# directions: the expansion round-trips exactly, and the register-class expansion a naive reading
# would produce is refused by CNA and changes nothing.
class GraphicsDeviceViewportTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  # ------------------------------------------------------------------ the scoreboard

  def test_the_property_mapping_mismatch_register_is_empty
    assert_equal ReviewedScoreboard::PROPERTY_MAPPING_MISMATCH, STRICT.fetch("PROPERTY_MAPPING_MISMATCH")
    assert_empty STRICT.fetch("details").fetch("PROPERTY_MAPPING_MISMATCH")
  end

  def test_the_selection_declares_no_override
    selection = JSON.parse(ROOT.join("tools", "api_compat", "selection.json").read)
    device = selection.fetch("types").find { |type| type.fetch("name") == NAME }
    viewport = device.fetch("include").find { |entry| entry["kind"] == "property" && entry["name"] == "Viewport" }
    refute_nil viewport
    refute viewport.key?("override"), "the setter is projected, so nothing is overridden"
  end

  def test_both_accessors_are_projected
    assert G::GraphicsDevice.public_method_defined?(:Viewport)
    assert G::GraphicsDevice.public_method_defined?(:Viewport=)
    assert_includes ReviewedScoreboard::GRAPHICS_DEVICE_SURFACE, :Viewport=
  end

  # ------------------------------------------------------------------ the measured expansion

  # The manifest's declaration, re-derived here from the same two facts the gate uses, so that a
  # future edit which "simplifies" the expansion fails this file as well as the ABI probe.
  def test_the_manifest_records_a_memory_class_expansion
    entry = CNA::Native::Manifest::FUNCTIONS.find { |item| item.symbol == "cna_graphics_device_set_viewport" }
    refute_nil entry, "the route must be in the manifest"
    layout = CNA::Native::Layouts::Viewport
    assert_operator layout.size, :>, 16, "an aggregate of at most two eightbytes would not be MEMORY class"
    aggregate = entry.value_aggregates.values.fetch(0)
    assert_equal "CNA_Viewport", aggregate.fetch(:c)
    assert_equal (layout.size + 7) / 8, aggregate.fetch(:members)
    # One integer argument precedes it — the handle — so five integer registers are left to fill.
    assert_equal 5, aggregate.fetch(:fillers)
    assert_equal [1, 2, 3, 4, 5], entry.abi_fillers
    assert_equal 9, entry.fiddle_arguments.length
  end

  # ------------------------------------------------------------------ the harness

  class ViewportGame < F::Game
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

    game = ViewportGame.new { |device| yield device }
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

  def viewport(x, y, width, height, min_depth = 0.0, max_depth = 1.0)
    value = G::Viewport.new(x, y, width, height)
    value.MinDepth = min_depth
    value.MaxDepth = max_depth
    value
  end

  def components(value) = [value.X, value.Y, value.Width, value.Height, value.MinDepth, value.MaxDepth]

  # ------------------------------------------------------------------ the round trip

  def test_a_valid_viewport_round_trips_exactly
    written = [[0, 0, 64, 48], [7, 11, 32, 24], [1, 2, 3, 4]]
    read = with_device do |device|
      written.map do |(x, y, width, height)|
        device.Viewport = viewport(x, y, width, height)
        components(device.Viewport)
      end
    end
    written.each_with_index do |(x, y, width, height), index|
      assert_equal [x, y, width, height, 0.0, 1.0], read.fetch(index)
    end
  end

  # The depths are `float32` on both sides, and a value that is not a power of two is what proves
  # the two stack eightbytes carrying them are not merely zero.
  def test_the_depth_pair_round_trips_including_fractions
    read = with_device do |device|
      device.Viewport = viewport(4, 5, 16, 16, 0.25, 0.75)
      first = components(device.Viewport)
      device.Viewport = viewport(4, 5, 16, 16, 0.5, 0.5)
      [first, components(device.Viewport)]
    end
    assert_equal [4, 5, 16, 16, 0.25, 0.75], read.fetch(0)
    assert_equal [4, 5, 16, 16, 0.5, 0.5], read.fetch(1)
  end

  def test_the_setter_answers_the_value_it_was_given
    answered = with_device do |device|
      value = viewport(2, 3, 8, 8)
      returned = (device.Viewport = value)
      returned.equal?(value)
    end
    assert answered, "an assignment answers its right-hand side"
  end

  # ------------------------------------------------------------------ the eleven guards

  # Every one raises `ArgumentException(ViewportInvalid, "value")`, and they are checked in the
  # IL's order. The bounds pair is measured against the back buffer while nothing is bound.
  def test_each_guard_refuses_with_viewport_invalid
    results = with_device do |device|
      width, height = device.__send__(:back_buffer_bounds)
      candidates = {
        negative_x: viewport(-1, 0, 4, 4),
        negative_y: viewport(0, -1, 4, 4),
        zero_width: viewport(0, 0, 0, 4),
        zero_height: viewport(0, 0, 4, 0),
        negative_width: viewport(0, 0, -4, 4),
        negative_height: viewport(0, 0, 4, -4),
        wider_than_bounds: viewport(1, 0, width, 4),
        taller_than_bounds: viewport(0, 1, 4, height),
        min_depth_below_zero: viewport(0, 0, 4, 4, -0.5, 1.0),
        min_depth_above_one: viewport(0, 0, 4, 4, 1.5, 1.0),
        max_depth_below_zero: viewport(0, 0, 4, 4, 0.0, -0.5),
        max_depth_above_one: viewport(0, 0, 4, 4, 0.0, 1.5),
        inverted_depths: viewport(0, 0, 4, 4, 0.75, 0.25)
      }
      candidates.transform_values { |value| error_of { device.Viewport = value } }
    end
    results.each do |name, outcome|
      assert_equal [ArgumentError, "ViewportInvalid"], outcome, name
    end
  end

  # Exactly at the bounds is legal; one past is not. The boundary is `<=`, which is what
  # `bgt` means in the IL.
  def test_the_bounds_guard_is_inclusive
    outcome = with_device do |device|
      width, height = device.__send__(:back_buffer_bounds)
      exact = error_of { device.Viewport = viewport(0, 0, width, height) }
      past = error_of { device.Viewport = viewport(1, 0, width, height) }
      [exact, past, [width, height], components(device.Viewport)]
    end
    assert_equal :ok, outcome.fetch(0)
    assert_equal [ArgumentError, "ViewportInvalid"], outcome.fetch(1)
    width, height = outcome.fetch(2)
    assert_equal [0, 0, width, height, 0.0, 1.0], outcome.fetch(3),
                 "the accepted assignment is the one that took effect"
  end

  # `MinDepth == MaxDepth` passes: the guard is `!(MaxDepth < MinDepth)`, not a strict ordering.
  def test_equal_depths_are_accepted
    outcome = with_device do |device|
      [error_of { device.Viewport = viewport(0, 0, 8, 8, 0.5, 0.5) }, components(device.Viewport)]
    end
    assert_equal :ok, outcome.fetch(0)
    assert_equal [0, 0, 8, 8, 0.5, 0.5], outcome.fetch(1)
  end

  # The one place the answer is CNA's rather than XNA's, and it is recorded rather than hidden.
  # XNA's last guard is `bge.un.s`, which is **unordered-true**, and the four range guards before
  # it are ordered comparisons a NaN fails — so a NaN depth passes every managed check and reaches
  # the device. CNA documents that both depths must be finite and refuses with
  # `CNA_RESULT_INVALID_ARGUMENT`, so the member still refuses; the exception is the translated
  # native one rather than `ArgumentException`.
  def test_a_nan_depth_passes_every_managed_guard_and_is_refused_by_cna
    outcome = with_device do |device|
      before = components(device.Viewport)
      raised = error_of { device.Viewport = viewport(0, 0, 8, 8, 0.0, Float::NAN) }
      [raised, before, components(device.Viewport)]
    end
    raised = outcome.fetch(0)
    refute_equal :ok, raised, "a NaN depth must not be accepted"
    refute_equal [ArgumentError, "ViewportInvalid"], raised,
                 "the managed guards do not catch it; CNA does"
    assert_operator raised.fetch(0), :<=, CNA::NativeError, "the refusal is the translated native one"
    assert_equal outcome.fetch(1), outcome.fetch(2), "a refused assignment changes nothing"
  end

  def test_a_non_viewport_is_a_type_error
    outcome = with_device do |device|
      [nil, 0, "0,0,4,4", G::Viewport, F::Rectangle.new(0, 0, 4, 4)]
        .map { |value| error_of { device.Viewport = value } }
    end
    outcome.each { |result| assert_equal [TypeError, "value must be a Viewport"], result }
  end

  # ------------------------------------------------------------------ the bounds source

  # XNA measures against `currentRenderTargets[0]` while one is bound and against the back buffer
  # otherwise, and this reads the same cached bindings the draw calls' instance-frequency guard
  # does.
  def test_the_bounds_follow_the_bound_render_target
    outcome = with_device do |device|
      target = G::RenderTarget2D.new(device, 32, 32)
      begin
        device.SetRenderTarget(target)
        bound = device.__send__(:viewport_bounds)
        inside = error_of { device.Viewport = viewport(0, 0, 32, 32) }
        outside = error_of { device.Viewport = viewport(0, 0, 33, 32) }
        device.SetRenderTarget(nil)
        [bound, inside, outside, device.__send__(:viewport_bounds)]
      ensure
        device.SetRenderTarget(nil)
        target.Dispose
      end
    end
    assert_equal [32, 32], outcome.fetch(0)
    assert_equal :ok, outcome.fetch(1)
    assert_equal [ArgumentError, "ViewportInvalid"], outcome.fetch(2)
    refute_equal [32, 32], outcome.fetch(3), "unbinding restores the back buffer's bounds"
  end

  # ------------------------------------------------------------------ the negative control
  #
  # The expansion is only evidence if the wrong one fails. This calls the very same symbol with the
  # three eightbytes in *registers* — which is what treating a 24-byte aggregate as register-class
  # would produce — and requires CNA to refuse it and the viewport to be unchanged.
  def test_the_register_class_expansion_is_refused_and_changes_nothing
    outcome = with_device do |device|
      device.Viewport = viewport(3, 4, 16, 16, 0.125, 0.875)
      before = components(device.Viewport)
      handle = CNA::Native.library.instance_variable_get(:@handle)
      naive = Fiddle::Function.new(
        handle["cna_graphics_device_set_viewport"],
        [Fiddle::TYPE_UINT64_T] * 4, Fiddle::TYPE_UINT32_T
      )
      eightbytes = ([9, 9, 8, 8].pack("l4") + [0.25, 0.75].pack("e2")).unpack("Q3")
      code = naive.call(device.__send__(:native_handle), *eightbytes)
      [before, code, components(device.Viewport)]
    end
    before, code, after = outcome
    refute_equal 0, code, "the register-class expansion is not how this aggregate is passed"
    assert_equal before, after
    assert_equal [3, 4, 16, 16, 0.125, 0.875], before
  end

  # ------------------------------------------------------------------ scope and disposal

  def test_the_setter_is_callback_scoped_and_disposal_bound
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    outside = error_of { device.Viewport = viewport(0, 0, 4, 4) }
    assert_equal CNA::InvalidBindingStateError, outside.fetch(0)
    game.Dispose
    disposed = error_of { device.Viewport = viewport(0, 0, 4, 4) }
    assert_equal CNA::DisposedObjectError, disposed.fetch(0)
  end
end
