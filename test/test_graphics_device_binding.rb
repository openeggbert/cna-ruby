# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s binding slice — the vertex streams and the index buffer. Five more of the
# thirty the device still owed, and the first members that make the buffers reachable from the
# device that draws with them.
class GraphicsDeviceBindingTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"

  def test_the_slice_left_the_partial_remainder
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" ")
    %w[SetVertexBuffer SetVertexBuffers GetVertexBuffers Indices]
      .each { |member| refute_includes remainder, "::#{member} ", member }
    %w[DrawPrimitives SetRenderTarget Present].each { |member| assert_includes remainder, "::#{member} ", member }
  end

  class BindGame < F::Game
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

    game = BindGame.new { |device| yield device }
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

  # What the device really holds, read through **raw Fiddle**. These three read-back routes are
  # deliberately not in the manifest: XNA's own getters are field reads, so nothing in `lib/` would
  # call them, and a route bound for a test is dead native surface. `test/renderer_environment.rb`
  # measures the same way and for the same reason.
  def route(name, arguments)
    handle = CNA::Native.library.instance_variable_get(:@handle)
    Fiddle::Function.new(handle[name], arguments, Fiddle::TYPE_UINT32_T)
  end

  def native_vertex_count(device)
    output = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    output[0, 8] = "\0" * 8
    route("cna_graphics_device_get_vertex_buffer_count",
          [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP]).call(device.__send__(:native_handle), output)
    output[0, 8].unpack1("Q")
  end

  # The bindings as CNA holds them: handle, offset, frequency -- which is the only way to see that
  # the two int32s went into the right halves of the structure.
  def native_bindings(device)
    count = native_vertex_count(device)
    return [] if count.zero?

    buffer = Fiddle::Pointer.malloc(16 * count, Fiddle::RUBY_FREE)
    buffer[0, 16 * count] = "\0" * (16 * count)
    written = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    written[0, 8] = "\0" * 8
    route("cna_graphics_device_copy_vertex_buffers",
          [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP])
      .call(device.__send__(:native_handle), buffer, count, written)
    Array.new(written[0, 8].unpack1("Q")) do |index|
      handle, offset, frequency = buffer[16 * index, 16].unpack("Ql2")
      { handle: handle, offset: offset, frequency: frequency }
    end
  end

  def native_index_handle(device)
    output = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    output[0, 8] = "\0" * 8
    route("cna_graphics_device_get_index_buffer",
          [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP]).call(device.__send__(:native_handle), output)
    output[0, 8].unpack1("Q")
  end

  # Both `SetVertexBuffer` overloads build a binding and forward, and the getter answers the **Ruby
  # object** that was bound -- CNA has no route from a native object back to a handle, and XNA's own
  # getter is a field read, so both sides agree that the answer is what the caller passed.
  def test_a_bound_buffer_comes_back_as_the_object_that_was_bound
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 4, G::BufferUsage::None)
      empty = [device.GetVertexBuffers.length, native_vertex_count(device)]
      device.SetVertexBuffer(buffer)
      one = [device.GetVertexBuffers.length, native_vertex_count(device),
             device.GetVertexBuffers[0].VertexBuffer.equal?(buffer),
             device.GetVertexBuffers[0].VertexOffset]
      device.SetVertexBuffer(buffer, 2)
      offset = device.GetVertexBuffers[0].VertexOffset
      # ...and the device really holds it, in the half of the structure it belongs in.
      native = native_bindings(device)
      # A fresh array every call, over the same bindings.
      copies = [device.GetVertexBuffers.equal?(device.GetVertexBuffers),
                device.GetVertexBuffers[0].equal?(device.GetVertexBuffers[0])]
      device.SetVertexBuffer(nil)
      cleared = [device.GetVertexBuffers.length, native_vertex_count(device)]
      buffer.Dispose
      [empty, one, offset, copies, cleared, native]
    end
    assert_equal [0, 0], values[0]
    assert_equal [1, 1, true, 0], values[1]
    assert_equal 2, values[2], "the two-argument overload carries the offset"
    assert_equal [false, true], values[3], "a new array, the same bindings"
    assert_equal [0, 0], values[4], "a null buffer unbinds every stream rather than raising"
    assert_equal 1, values[5].length
    assert_equal 2, values[5][0].fetch(:offset), "the offset is in the offset field"
    assert_equal 0, values[5][0].fetch(:frequency), "and the frequency in the frequency field"
    assert values[5][0].fetch(:handle).positive?
  end

  def test_the_array_overload_binds_and_validates_before_it_applies
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 4, G::BufferUsage::None)
      device.SetVertexBuffers([G::VertexBufferBinding.new(buffer, 1, 0)])
      bound = [device.GetVertexBuffers.length, device.GetVertexBuffers[0].VertexOffset,
               native_vertex_count(device)]
      refusals = [error_of { device.SetVertexBuffers([nil]) },
                  error_of { device.SetVertexBuffers([buffer]) },
                  error_of { device.SetVertexBuffers(buffer) }]
      # ...and a refused call changed nothing.
      after = [device.GetVertexBuffers.length, device.GetVertexBuffers[0].VertexOffset]
      device.SetVertexBuffers(nil)
      emptied = [device.GetVertexBuffers.length, native_vertex_count(device)]
      buffer.Dispose
      [bound, refusals, after, emptied]
    end
    assert_equal [1, 1, 1], values[0]
    assert_equal [ArgumentError, "NullNotAllowed"], values[1][0]
    assert_equal TypeError, values[1][1].first, "a buffer is not a binding"
    assert_equal TypeError, values[1][2].first
    assert_equal [1, 1], values[2], "validation happens before anything is applied"
    assert_equal [0, 0], values[3], "and a null array is the same unbind"
  end

  # `Indices` is one field read, and its setter binds or clears -- a null is `SetIndices(null)`
  # rather than a refusal.
  def test_the_index_buffer_binds_clears_and_answers_the_object_it_was_given
    values = with_device do |device|
      buffer = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 6, G::BufferUsage::None)
      initial = [device.Indices, native_index_handle(device)]
      device.Indices = buffer
      bound = [device.Indices.equal?(buffer), native_index_handle(device).positive?]
      device.Indices = nil
      cleared = [device.Indices, native_index_handle(device)]
      dynamic = G::DynamicIndexBuffer.new(device, G::IndexElementSize::ThirtyTwoBits, 4,
                                          G::BufferUsage::WriteOnly)
      device.Indices = dynamic
      derived = device.Indices.equal?(dynamic)
      device.Indices = nil
      result = [initial, bound, cleared, derived,
                error_of { device.Indices = buffer.GraphicsDevice }]
      buffer.Dispose
      dynamic.Dispose
      result
    end
    assert_equal [nil, 0], values[0]
    assert_equal [true, true], values[1]
    assert_equal [nil, 0], values[2]
    assert values[3], "a DynamicIndexBuffer is an IndexBuffer"
    assert_equal TypeError, values[4].first
  end

  # `InvalidDevice`: a resource belongs to the device that made it, and XNA refuses a foreign one
  # before it reaches the driver. Two devices in one process is two games, which CNA does not allow,
  # so the rule is asserted against the only foreign owner reachable here.
  def test_a_resource_from_another_device_is_refused
    values = with_device do |device|
      buffer = G::VertexBuffer.new(device, G::VertexPositionColor, 4, G::BufferUsage::None)
      stranger = G::VertexBufferBinding.new(buffer)
      buffer.instance_variable_set(:@GraphicsDevice, Object.new)
      result = [error_of { device.SetVertexBuffers([stranger]) },
                error_of { device.Indices = foreign_index_buffer(device) }]
      buffer.instance_variable_set(:@GraphicsDevice, device)
      buffer.Dispose
      result
    end
    assert_equal [RuntimeError, "InvalidDevice"], values[0]
    assert_equal [RuntimeError, "InvalidDevice"], values[1]
  end

  def foreign_index_buffer(device)
    buffer = G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None)
    buffer.instance_variable_set(:@GraphicsDevice, Object.new)
    buffer
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_draws_nothing_and_binds_no_render_target
    %i[DrawPrimitives DrawIndexedPrimitives DrawUserPrimitives SetRenderTarget SetRenderTargets
       GetRenderTargets Present Reset].each do |absent|
      refute G::GraphicsDevice.public_method_defined?(absent), absent.to_s
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[cna_graphics_device_draw_primitives cna_graphics_device_draw_indexed_primitives
       cna_graphics_device_set_render_target2d cna_graphics_device_set_render_targets]
      .each { |absent| refute_includes symbols, absent }
    # And the three read-back routes this file measures through raw Fiddle stay out of the manifest,
    # because nothing in `lib/` would call them: XNA's own getters are field reads.
    %w[cna_graphics_device_get_vertex_buffer_count cna_graphics_device_copy_vertex_buffers
       cna_graphics_device_get_index_buffer].each { |absent| refute_includes symbols, absent }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
