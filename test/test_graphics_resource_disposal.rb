# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Graphics.GraphicsResource`'s disposal contract — the three members it still owed, which completes
# it and takes the partial count from five to four.
#
# The pinned Graphics assembly is mixed-mode C++/CLI, so the contract is spread over four methods
# and a paraphrase loses two things: `isDisposed` is set **before** `Disposing` is raised, and the
# finalizer path raises **nothing**.
class GraphicsResourceDisposalTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsResource"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_it_is_complete_and_the_partial_count_fell
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    assert_equal 3, STRICT.fetch("PARTIAL_TYPES"), "GraphicsResource was the fifth; Texture2D the fourth"
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    refute_includes STRICT.fetch("partialTypes").keys, NAME
  end

  # One name cannot have two visibilities in Ruby, so the public `Dispose()` and the protected
  # `Dispose(Boolean)` project to one method with a default argument.
  def test_the_three_members_and_the_collapsed_overloads
    contract = REFERENCE.fetch(NAME)
    disposes = contract.fetch("members").select { |m| m.fetch("name") == "Dispose" }
    assert_equal %w[protected public].sort, disposes.map { |m| m.fetch("access") }.sort
    assert_equal [["System.Boolean"], []], disposes.map { |m| m.fetch("parameters").map { |p| p.fetch("type") } }
    assert_equal 1, G::GraphicsResource.instance_method(:Dispose).arity.abs
    assert_includes G::GraphicsResource.private_instance_methods(false), :Finalize
    assert_equal %i[Disposing], G::GraphicsResource.xna_event_identities
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal ReviewedScoreboard::EVENT_OWNER_TYPES, STRICT.fetch("EVENT_OWNER_TYPES")
  end

  # `Texture2D` and `SpriteBatch` each override `Dispose(bool)`, and each override does real extra
  # work in XNA — releasing the native texture and cleaning saved data, or disposing the batch's own
  # `Effect` and platform data — before calling the base. Every piece of that extra work is over
  # state this binding does not have: neither type keeps saved image data or an `Effect`, and the
  # native handle is already released by its own `NativeResource` lambda. So the base behaviour is
  # the whole of what remains, which is why both members are selected rather than reimplemented.
  def test_the_two_subclass_overrides_are_selected_because_the_base_is_all_that_remains
    %w[Microsoft.Xna.Framework.Graphics.Texture2D
       Microsoft.Xna.Framework.Graphics.SpriteBatch].each do |name|
      remainder = ReviewedScoreboard.partial_remainder(STRICT, name)
                                    .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
      refute_includes remainder, "Dispose", name
      type = name.split(".").last
      assert_equal G::GraphicsResource,
                   G.const_get(type).instance_method(:Dispose).owner,
                   "#{type} inherits the base implementation rather than reimplementing it"
    end
    refute G::SpriteBatch.public_method_defined?(:Effect), "no Effect to dispose"
    # `SaveAsPng` exists now and still cleans nothing: XNA's `CleanupSavedData` frees a cached
    # bitmap the saving path keeps, and this projection keeps none -- each save asks CNA to encode
    # afresh, so there is no saved data for a Dispose override to clean.
    refute G::Texture2D.private_instance_methods(false).include?(:CleanupSavedData)
  end

  # ------------------------------------------------------------------------------ live behaviour

  class Host < F::Game
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

  def with_texture
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_PNG not supplied" unless ENV["CNA_TEST_PNG"] && File.file?(ENV["CNA_TEST_PNG"])

    game = Host.new do |device|
      texture = File.open(ENV.fetch("CNA_TEST_PNG"), "rb") { |s| G::Texture2D.FromStream(device, s) }
      yield texture, device
    end
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # `~GraphicsResource` sets `isDisposed` and *then* raises, so a handler observes a disposed
  # resource. That ordering is the IL's and it is asserted rather than assumed.
  def test_dispose_raises_disposing_once_after_marking_disposed
    values = with_texture do |texture, _device|
      seen = []
      texture.Disposing.add(->(sender, args) { seen << [sender.equal?(texture), sender.IsDisposed, args] })
      before = texture.IsDisposed
      texture.Dispose
      after = texture.IsDisposed
      texture.Dispose
      [before, after, seen]
    end
    assert_equal [false, true], values[0..1]
    assert_equal 1, values[2].length, "idempotent: a second Dispose raises nothing"
    assert_equal [true, true, CNA::Runtime::EventArgs::Empty], values[2].first,
                 "the handler sees the resource already disposed, which is the IL's order"
  end

  # `Dispose(false)` is the finalizer path: it marks disposed and raises **nothing**.
  def test_the_finalizer_path_disposes_without_announcing_it
    values = with_texture do |texture, _device|
      seen = []
      texture.Disposing.add(->(_s, _a) { seen << :raised })
      texture.Dispose(false)
      [texture.IsDisposed, seen]
    end
    assert_equal true, values[0]
    assert_empty values[1], "only an explicit Dispose announces itself"
  end

  # `SpriteBatch` inherits the same contract, so the event reaches it too.
  def test_the_contract_is_inherited_by_every_graphics_resource
    values = with_texture do |_texture, device|
      batch = G::SpriteBatch.new(device)
      seen = []
      batch.Disposing.add(->(_s, _a) { seen << :raised })
      batch.Dispose
      [batch.IsDisposed, seen.length, batch.is_a?(G::GraphicsResource)]
    end
    assert_equal [true, 1, true], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  # No Ruby finalizer is registered, which is this binding's standing rule and why the CLR's
  # `GC.SuppressFinalize` needs no analogue.
  def test_no_ruby_finalizer_is_registered
    assert_includes G::GraphicsResource.private_instance_methods(false), :Finalize
    # The check is on **code**, not on the word: `GC.SuppressFinalize` is discussed in comments all
    # over this binding, and what must be absent is a registration.
    code = File.read(ROOT.join("lib", "microsoft", "xna", "framework", "graphics.rb"))
               .lines.reject { |line| line.strip.start_with?("#") }.join
    refute_includes code, "define_finalizer"
    refute_includes code, "ObjectSpace"
  end

  def test_it_adds_no_draw_surface
    # Pixel access arrived in a later milestone, and `DrawString` in one later still. What this
    # milestone claims is that the disposal contract added no draw surface of its own, which the
    # members still outstanding on `SpriteBatch` measure.
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Graphics.SpriteBatch")
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    assert_equal %w[Begin], remainder.sort
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
  end
end
