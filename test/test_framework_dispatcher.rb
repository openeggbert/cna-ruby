# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Microsoft.Xna.Framework.FrameworkDispatcher, derived from the pinned
# Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…): a `public abstract sealed` static class
# whose whole public surface is `static void Update()`.
#
# The structural half of this file runs everywhere. The native half proves the Ruby projection
# reaches the canonical CNA dispatcher and honours its documented preconditions; it needs a real
# library and says so rather than asserting anything when one is absent.
class FrameworkDispatcherTest < Minitest::Test
  F = Microsoft::Xna::Framework

  # --- Structural contract -------------------------------------------------------------------

  def test_type_is_a_class_named_exactly_as_xna_spells_it
    assert_instance_of Class, F::FrameworkDispatcher
    assert_equal "Microsoft::Xna::Framework::FrameworkDispatcher", F::FrameworkDispatcher.name
    assert_equal Object, F::FrameworkDispatcher.superclass
  end

  # `abstract sealed` in the IL is C#'s static class: XNA exposes no constructor at all, so the
  # Ruby projection is not constructible either. This mirrors MathHelper, the binding's other
  # static XNA class.
  def test_static_class_is_not_constructible
    refute_includes F::FrameworkDispatcher.singleton_class.public_instance_methods(false), :new
    error = assert_raises(TypeError) { F::FrameworkDispatcher.__send__(:new) }
    assert_equal "FrameworkDispatcher is static", error.message
  end

  def test_update_is_a_class_method_taking_no_arguments
    assert_respond_to F::FrameworkDispatcher, :Update
    assert_equal 0, F::FrameworkDispatcher.method(:Update).arity
  end

  # The one public identity and nothing else. A static class must not grow a Ruby-only
  # convenience surface that XNA never had.
  def test_public_surface_is_exactly_update
    surface = F::FrameworkDispatcher.singleton_class.public_instance_methods(false)
    assert_equal [:Update], surface
    assert_empty F::FrameworkDispatcher.public_instance_methods(false)
  end

  # --- Native behaviour ----------------------------------------------------------------------

  def native
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
  end

  # XNA's dispatcher is a pure static usable with no Game. The canonical CNA C ABI takes a game
  # handle for thread affinity, so this projection needs a live Game and refuses honestly rather
  # than silently doing nothing and returning as though it had pumped.
  def test_update_without_a_live_game_refuses_rather_than_pretending
    native
    assert_raises(CNA::InvalidBindingStateError) { F::FrameworkDispatcher.Update }
  end

  def test_update_returns_nil_outside_a_callback_with_a_live_game
    native
    game = F::Game.new
    begin
      game.RunOneFrame
      assert_nil F::FrameworkDispatcher.Update
    ensure
      game.Dispose
    end
  end

  # The canonical header states that calling the dispatcher while the loop runs is harmless and
  # simply does the work twice. Repetition must therefore neither fail nor accumulate state.
  def test_repeated_updates_are_harmless
    native
    game = F::Game.new
    begin
      game.RunOneFrame
      5.times { assert_nil F::FrameworkDispatcher.Update }
    ensure
      game.Dispose
    end
  end

  class PumpingGame < Microsoft::Xna::Framework::Game
    attr_reader :results

    def initialize
      super()
      @results = []
      @updates = 0
    end

    protected

    def Update(_time)
      @results << Microsoft::Xna::Framework::FrameworkDispatcher.Update
      @updates += 1
      self.Exit if @updates == 2
    end

    def Draw(_time)
      @results << Microsoft::Xna::Framework::FrameworkDispatcher.Update
    end
  end

  def test_update_works_inside_the_native_lifecycle_callbacks
    native
    game = PumpingGame.new
    begin
      game.Run
    ensure
      game.Dispose
    end
    refute_empty game.results
    assert(game.results.all?(&:nil?))
  end

  def test_update_off_the_owner_thread_raises_rather_than_pumping
    native
    game = F::Game.new
    begin
      game.RunOneFrame
      error = Thread.new do
        begin
          F::FrameworkDispatcher.Update
          nil
        rescue StandardError => exception
          exception
        end
      end.value
      assert_kind_of CNA::InvalidBindingStateError, error
    ensure
      game.Dispose
    end
  end

  def test_update_after_dispose_refuses
    native
    game = F::Game.new
    game.RunOneFrame
    game.Dispose
    assert_raises(CNA::InvalidBindingStateError) { F::FrameworkDispatcher.Update }
  end

  # --- Frontier ------------------------------------------------------------------------------

  # The type sat in the dependency frontier's RUNTIME_DATA register until this milestone, on the
  # reasoning that Update "would be a no-op pretending to be a pump". A completed type must not
  # still be registered as deferred, and the register must not silently keep a retired row.
  def test_the_runtime_data_deferral_is_retired
    report = JSON.parse(
      Pathname(__dir__).join("..", "docs", "generated", "public-signature-dependency-report.json").read
    )
    refute_includes report.fetch("runtimeDataRegister").keys,
                    "Microsoft.Xna.Framework.FrameworkDispatcher"
    strict = JSON.parse(
      Pathname(__dir__).join("..", "docs", "generated", "api-compat-report.json").read
    )
    assert_includes strict.fetch("completeTypeNames"), "Microsoft.Xna.Framework.FrameworkDispatcher"
    assert_equal 0,
                 strict.fetch("localDiagnostics").fetch("Microsoft.Xna.Framework.FrameworkDispatcher")
  end

  # Native frontier 1 recorded that "PollForEvents is `{ ret }` in the pinned assembly, so Update
  # reaches no native entry point at all". The first half is true and the conclusion was not:
  # Native frontier 3 fixed a `modopt(...)` blind spot in the extractor, and the drain reaches
  # native through `SoundEffect.RecycleStoppedFireAndForgetInstances`, which XACT owns. So XNA's own
  # Update really does end in native work, and this projection forwarding to a native pump is the
  # closer analogue rather than the looser one.
  def test_the_pinned_il_records_the_drain_as_native_reachable_through_xact
    inventory = JSON.parse(
      Pathname(__dir__).join("..", "docs", "generated", "xna-il-inventory.json").read
    )
    entry = inventory.fetch("types").fetch("Microsoft.Xna.Framework.FrameworkDispatcher")
    assert entry.fetch("nativeReachable")
    assert_equal ["Update"], entry.fetch("nativeReachableMethods")
    # It declares no native entry point of its own; the reachability is transitive.
    refute entry.fetch("declaresNativeEntryPoint")
    assert_empty entry.fetch("nativeInteropMarkers")
    assert_empty entry.fetch("constructors")
  end

  # --- Manifest ------------------------------------------------------------------------------

  # The identity is bound through the measured manifest, not an ad-hoc Fiddle lookup, so the ABI
  # verifier covers it like every other native route.
  def test_dispatcher_route_is_declared_in_the_measured_native_manifest
    entry = CNA::Native::Manifest::FUNCTIONS.find do |signature|
      signature.symbol == "cna_framework_dispatcher_update"
    end
    refute_nil entry
    assert_equal "CNA_Result", entry.c_return
    assert_equal ["CNA_Handle"], entry.c_arguments
    assert_equal [0], entry.pointer_depths
    assert_equal [false], entry.const_arguments
  end
end
