# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Audio.AudioEngine` and `Audio.AudioCategory` — the XACT engine, measured against a real XACT
# project rather than a synthetic one.
#
# `AudioCategory` sat in the frontier's `RUNTIME_DATA` register with the reasoning "an XACT
# AudioEngine category handle; SetVolume/Pause/Resume/Stop act on a live engine this binding does
# not have". The second half stopped being true once it was measured: CNA 0.21.0 loads the XNA
# Spacewar sample's `SpaceWar.xgs` — six categories, eight variables — and answers a real
# `SDL3_mixer` renderer. The fixtures are referenced by path through `CNA_TEST_XACT_DIR`, never
# copied here, exactly as the MonoGame XNB fixtures are.
class AudioEngineTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = Microsoft::Xna::Framework::Audio
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  ENGINE = "Microsoft.Xna.Framework.Audio.AudioEngine"
  CATEGORY = "Microsoft.Xna.Framework.Audio.AudioCategory"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_both_contracts_are_projected_whole
    engine = REFERENCE.fetch(ENGINE)
    assert_equal 13, engine.fetch("members").length
    assert_includes engine.fetch("interfaces"), "System.IDisposable"
    assert_equal 39, A::AudioEngine::ContentVersion
    assert_equal "ContentVersion",
                 engine.fetch("members").find { |m| m.fetch("kind") == "field" }.fetch("name")

    category = REFERENCE.fetch(CATEGORY)
    assert_equal "struct", category.fetch("kind")
    assert category.fetch("sealed")
    assert_equal 11, category.fetch("members").length
    assert_includes category.fetch("interfaces"), "System.IEquatable`1[#{CATEGORY}]"
    # The category constructor is `assembly`, so a consumer reaches one only through the engine.
    assert_raises(NoMethodError) { A::AudioCategory.new(nil, "x", 0) }
    assert A::AudioCategory.include?(CNA::Runtime::ValueSemantics)
  end

  def test_the_scoreboard_records_both_complete_and_the_register_lost_an_entry
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    assert_includes STRICT.fetch("completeTypeNames"), ENGINE
    assert_includes STRICT.fetch("completeTypeNames"), CATEGORY
    refute_includes FRONTIER.fetch("runtimeDataRegister").keys, CATEGORY
    # And what arrived behind the engine, which is what completing a type does.
    assert_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") },
                    "Microsoft.Xna.Framework.Audio.WaveBank"
  end

  def test_the_engine_declares_the_one_event_and_the_category_declares_none
    assert_equal %i[Disposing], A::AudioEngine.xna_event_identities
    refute A::AudioCategory.respond_to?(:xna_event_identities)
    assert_equal 1, REFERENCE.fetch(ENGINE).fetch("members").count { |m| m.fetch("kind") == "event" }
    assert_equal 0, REFERENCE.fetch(CATEGORY).fetch("members").count { |m| m.fetch("kind") == "event" }
  end

  # A category handle is `PARENT_OWNED`: XNA's `AudioCategory` is a value type with no `Dispose` and
  # no finalizer, so nothing but the engine can release one.
  def test_the_ownership_the_manifest_records
    by_symbol = CNA::Native::Manifest::FUNCTIONS.to_h { |e| [e.symbol, e.ownership] }
    assert_match(/OWNED engine/, by_symbol.fetch("cna_audio_engine_create_with_renderer"))
    assert_match(/PARENT_OWNED category/, by_symbol.fetch("cna_audio_engine_get_category"))
    assert_match(/consumes PARENT_OWNED category/, by_symbol.fetch("cna_audio_category_destroy"))
    refute A::AudioCategory.public_method_defined?(:Dispose)
  end

  # ------------------------------------------------------------------------------ live behaviour

  class HostGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
    end

    def Update(_gameTime)
      @result = @body.call
    ensure
      self.Exit
    end
  end

  def settings_path = File.join(ENV.fetch("CNA_TEST_XACT_DIR", ""), "SpaceWar.xgs")

  def with_engine
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_XACT_DIR not supplied" unless File.file?(settings_path)

    game = HostGame.new do
      engine = A::AudioEngine.new(settings_path)
      begin
        yield engine
      ensure
        engine.Dispose
      end
    end
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # `AudioEngine(settingsFile)` is `AudioEngine(settingsFile, TimeSpan.FromMilliseconds(250), null)`,
  # and the file is validated by **magic number** in managed code before XACT is asked: four bytes
  # `X G S F`, and anything four bytes or shorter is refused too.
  def test_the_constructor_refuses_what_xna_refuses_before_xact_sees_it
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_XACT_DIR not supplied" unless File.file?(settings_path)

    directory = ENV.fetch("CNA_TEST_XACT_DIR")
    assert_equal "XGSF", File.open(settings_path, "rb") { |io| io.read(4) },
                 "the fixture really carries the magic the IL checks"

    outcome = HostGame.new do
      attempt = lambda do |argument|
        engine = A::AudioEngine.new(argument)
        engine.Dispose
        :accepted
      rescue StandardError => error
        error.class
      end
      [attempt.call(nil), attempt.call(""),
       attempt.call(File.join(directory, "spacewar.xsb")),
       attempt.call(settings_path)]
    end
    game = outcome
    game.Run
    values = game.result
    game.Dispose

    assert_equal [ArgumentError, ArgumentError, ArgumentError, :accepted], values
  end

  def test_the_renderer_details_are_real_and_the_null_case_is_the_ils
    values = with_engine do |engine|
      details = engine.RendererDetails
      [details.class, details.Count, details[0].FriendlyName, details[0].RendererId,
       details[0].instance_of?(A::RendererDetail), engine.RendererDetails.Count]
    end
    assert_equal CNA::Runtime::ReadOnlyCollection, values[0]
    assert_operator values[1], :>=, 1
    refute_empty values[2]
    refute_empty values[3]
    assert_equal true, values[4]
    assert_equal values[1], values[5], "a fresh collection each call, as the IL builds one each time"
    # `get_RendererDetails` starts its answer as `ldnull` and only replaces it when the count is
    # positive, so zero renderers answers null rather than an empty collection. This host has one,
    # so what is asserted is the branch that was taken, not a fabricated empty case.
    assert_operator values[1], :>, 0
  end

  # `if (string.IsNullOrEmpty(name)) throw new ArgumentNullException("name")` on both, then the
  # native call. `SpeedOfSound` is the settings file's one global variable; the other seven names it
  # contains are cue-instance variables, so XACT refuses them here — its refusal, not this binding's.
  def test_the_global_variable_round_trips_and_a_cue_scoped_name_is_refused_by_xact
    values = with_engine do |engine|
      before = engine.GetGlobalVariable("SpeedOfSound")
      engine.SetGlobalVariable("SpeedOfSound", 400.0)
      after = engine.GetGlobalVariable("SpeedOfSound")
      engine.SetGlobalVariable("SpeedOfSound", before)
      err = ->(&block) { begin; block.call; nil; rescue => e; e.class; end }
      [before, after, engine.GetGlobalVariable("SpeedOfSound"),
       err.call { engine.GetGlobalVariable(nil) },
       err.call { engine.GetGlobalVariable("") },
       err.call { engine.SetGlobalVariable(nil, 1.0) },
       err.call { engine.SetGlobalVariable("", 1.0) },
       err.call { engine.GetGlobalVariable("Distance") },
       err.call { engine.GetGlobalVariable("NoSuchVariable") }]
    end
    assert_in_delta 343.5, values[0], 0.001, "XACT's own default speed of sound"
    assert_in_delta 400.0, values[1], 0.001
    assert_in_delta values[0], values[2], 0.001, "and it restores"
    assert_equal [ArgumentError] * 4, values[3..6]
    assert_equal CNA::NativeError, values[7], "Distance is cue-scoped, not global"
    assert_equal CNA::NativeError, values[8]
  end

  # `GetCategory` is `new AudioCategory(this, name)`, whose constructor throws
  # `InvalidOperationException(CouldNotCreateResource)` when XACT does not know the name.
  def test_every_named_category_resolves_and_an_unknown_one_is_refused
    values = with_engine do |engine|
      err = ->(&block) { begin; block.call; nil; rescue => e; e.class; end }
      names = %w[Global Default Music Weapons Ships].map do |name|
        category = engine.GetCategory(name)
        [name, category.Name, category.ToString, category.__send__(:native_name)]
      end
      [names,
       err.call { engine.GetCategory("NoSuchCategory") },
       err.call { engine.GetCategory(nil) },
       err.call { engine.GetCategory("") }]
    end
    values[0].each do |asked, name, string, native|
      assert_equal asked, name, "Name is the string the consumer passed, never normalised"
      assert_equal asked, string
      assert_equal asked, native, "and XACT agrees about what it is called"
    end
    assert_equal ::RuntimeError, values[1]
    assert_equal [ArgumentError, ArgumentError], values[2..]
  end

  # XNA's `Equals` compares the `uint16` category value and the parent reference. CNA hands out a
  # fresh handle per call, so `GetCategory` caches by name — and the control for that cache is CNA's
  # own `cna_audio_category_equals`, which must agree with it in both directions.
  def test_category_equality_matches_cnas_own_and_the_cache_is_what_makes_it_so
    values = with_engine do |engine|
      music = engine.GetCategory("Music")
      again = engine.GetCategory("Music")
      other = engine.GetCategory("Default")
      [music == again, music == other, music.Equals(again), music.Equals(other), music.Equals("Music"),
       music != other, music.GetHashCode == again.GetHashCode, music.GetHashCode == other.GetHashCode,
       music.__send__(:native_equals?, again), music.__send__(:native_equals?, other),
       music.instance_variable_get(:@handle) == again.instance_variable_get(:@handle),
       music.equal?(again), engine.instance_variable_get(:@categories).length]
    end
    assert_equal [true, false, true, false, false, true], values[0..5]
    assert_equal [true, false], values[6..7], "equal categories hash equally, unequal ones do not"
    assert_equal [true, false], values[8..9], "and CNA's own comparison agrees in both directions"
    assert_equal true, values[10], "because the engine caches the handle by name"
    assert_equal false, values[11], "though each call still answers a fresh value, as the IL does"
    assert_equal 2, values[12], "two names asked, two handles held"
  end

  # `if (!(volume >= 0f)) throw new ArgumentException(InvalidXactVolume)`, and the comparison is
  # `bge.un` — **unordered** — so NaN takes the *accepting* branch. That is the exact opposite of
  # `SoundEffectInstance.Volume`, whose `blt.un`/`bgt.un` make NaN throw, and both are the IL's.
  def test_set_volume_refuses_the_negative_and_lets_nan_through_the_managed_check
    values = with_engine do |engine|
      music = engine.GetCategory("Music")
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { music.SetVolume(0.0) }, err.call { music.SetVolume(1.0) },
       err.call { music.SetVolume(2.5) }, err.call { music.SetVolume(-0.001) },
       err.call { music.SetVolume(Float::NAN) }, err.call { music.SetVolume("1") }]
    end
    assert_equal %i[ok ok ok], values[0..2], "XNA has no upper bound here"
    assert_equal ArgumentError, values[3]
    # DEVIATION, recorded: XNA's managed check admits NaN and hands it to XACT, whose behaviour is
    # unknowable from the IL. CNA refuses it at the boundary, so the managed contract is reproduced
    # exactly and CNA's own refusal is what surfaces.
    assert_equal CNA::NativeError, values[4]
    assert_equal TypeError, values[5]
  end

  # `Pause()` and `Resume()` are one native entry point with a flag — `Engine::Pause(handle, cat, 1)`
  # and `(…, 0)` — which CNA splits into two routes.
  def test_the_transport_members_reach_the_engine
    values = with_engine do |engine|
      music = engine.GetCategory("Music")
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { music.Pause }, err.call { music.Resume },
       err.call { music.Stop(A::AudioStopOptions::Immediate) },
       err.call { music.Stop(A::AudioStopOptions::AsAuthored) },
       err.call { music.Stop(:immediate) }, err.call { music.Stop(nil) },
       err.call { engine.Update }]
    end
    assert_equal %i[ok ok ok ok], values[0..3]
    assert_equal [TypeError, TypeError], values[4..5]
    assert_equal :ok, values[6]
  end

  # `Dispose` raises `Disposing` and then releases — and it releases every category handle the
  # engine handed out first, because a category outliving its engine is a handle into a destroyed
  # XACT engine and XNA declares nothing that would release one.
  def test_disposal_raises_the_event_releases_the_categories_and_is_idempotent
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_XACT_DIR not supplied" unless File.file?(settings_path)

    game = HostGame.new do
      engine = A::AudioEngine.new(settings_path)
      seen = []
      engine.Disposing.add(->(sender, args) { seen << [sender.equal?(engine), args] })
      music = engine.GetCategory("Music")
      held = engine.instance_variable_get(:@categories).length
      engine.Dispose
      after = [engine.IsDisposed, engine.instance_variable_get(:@categories).length]
      engine.Dispose
      dead = ->(&block) { begin; block.call; nil; rescue => e; e.class; end }
      [seen, held, after, seen.length,
       dead.call { engine.Update }, dead.call { engine.GetCategory("Music") },
       dead.call { music.SetVolume(1.0) }, dead.call { music.Pause }]
    end
    game.Run
    values = game.result
    game.Dispose

    assert_equal [[true, CNA::Runtime::EventArgs::Empty]], values[0]
    assert_equal 1, values[1]
    assert_equal [true, 0], values[2], "the engine holds no category handle afterwards"
    assert_equal 1, values[3], "and a second Dispose raises nothing"
    assert_equal [CNA::DisposedObjectError] * 4, values[4..7]
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_the_banks_and_the_cue_are_not_projected_yet
    %i[WaveBank SoundBank Cue].each { |absent| refute A.const_defined?(absent, false), absent.to_s }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |s| s.start_with?("cna_wave_bank_", "cna_sound_bank_", "cna_cue_") })
    # `cna_audio_engine_create` is deliberately unbound: XNA's one-argument constructor delegates to
    # the three-argument one with an explicit 250 ms look-ahead, so the projection always has one.
    refute_includes symbols, "cna_audio_engine_create"
    assert_includes symbols, "cna_audio_engine_create_with_renderer"
  end
end
