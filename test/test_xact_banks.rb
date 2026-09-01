# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Audio.WaveBank`, `Audio.SoundBank` and `Audio.Cue` — the rest of the XACT cluster, measured
# against the XNA Spacewar sample's real banks through `CNA_TEST_XACT_DIR`.
#
# Completing these completes the `Audio` namespace: every XNA 4.0 audio type is projected.
class XactBanksTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = Microsoft::Xna::Framework::Audio
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  CUE = "Microsoft.Xna.Framework.Audio.Cue"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_all_three_contracts_are_projected_whole
    { "Microsoft.Xna.Framework.Audio.WaveBank" => 9,
      "Microsoft.Xna.Framework.Audio.SoundBank" => 10,
      CUE => 19 }.each do |name, count|
      contract = REFERENCE.fetch(name)
      assert_equal count, contract.fetch("members").length, name
      assert_includes contract.fetch("interfaces"), "System.IDisposable", name
      assert_includes STRICT.fetch("completeTypeNames"), name
    end
    assert REFERENCE.fetch(CUE).fetch("sealed")
    # `Cue` has no public constructor: SoundBank.GetCue and the three-argument PlayCue are its only
    # producers, so `new` is private under Foundation 25's rule.
    assert_empty REFERENCE.fetch(CUE).fetch("members").select { |m| m.fetch("kind") == "constructor" }
    assert_raises(NoMethodError) { A::Cue.new(nil, "x", 0) }
    # Both banks do have public constructors, and WaveBank has two.
    assert_equal 2, REFERENCE.fetch("Microsoft.Xna.Framework.Audio.WaveBank")
                            .fetch("members").count { |m| m.fetch("kind") == "constructor" }
  end

  def test_the_audio_namespace_is_complete_and_the_frontier_lost_three
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    audio = REFERENCE.keys.select { |name| name.start_with?("Microsoft.Xna.Framework.Audio.") }
    refute_empty audio
    audio.each { |name| assert_includes STRICT.fetch("completeTypeNames"), name, name }
    names = FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }
    refute(names.any? { |name| name.start_with?("Microsoft.Xna.Framework.Audio.") },
           "no audio type is left on the frontier")
  end

  # Each of the three declares its own `Disposing`, which is what took the event census from 23 to 26
  # across three more owner types.
  def test_each_declares_its_own_disposing_event
    [A::WaveBank, A::SoundBank, A::Cue].each do |type|
      assert_equal %i[Disposing], type.xna_event_identities, type.name
    end
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

  def directory = ENV.fetch("CNA_TEST_XACT_DIR", "")
  def settings = File.join(directory, "SpaceWar.xgs")
  def waves = File.join(directory, "spacewar.xwb")
  def sounds = File.join(directory, "spacewar.xsb")

  def with_banks
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_XACT_DIR not supplied" unless File.file?(settings)

    game = HostGame.new do
      engine = A::AudioEngine.new(settings)
      begin
        yield engine, A::WaveBank.new(engine, waves), A::SoundBank.new(engine, sounds)
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

  # `CheckWaveBankHeader` compares four bytes with `W B N D` and the sound bank's constructor with
  # `S D B K`, each refusing a file of four bytes or fewer first. Both checks are managed, so the
  # wrong file is refused before XACT is asked anything.
  def test_each_bank_checks_its_own_magic_number_in_managed_code
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_XACT_DIR not supplied" unless File.file?(settings)

    assert_equal "WBND", File.open(waves, "rb") { |io| io.read(4) }
    assert_equal "SDBK", File.open(sounds, "rb") { |io| io.read(4) }

    game = HostGame.new do
      engine = A::AudioEngine.new(settings)
      attempt = lambda do |type, argument|
        value = type.new(engine, argument)
        value.Dispose
        :accepted
      rescue StandardError => error
        error.class
      end
      values = [attempt.call(A::WaveBank, waves), attempt.call(A::WaveBank, sounds),
                attempt.call(A::WaveBank, settings), attempt.call(A::WaveBank, nil),
                attempt.call(A::WaveBank, ""),
                attempt.call(A::SoundBank, sounds), attempt.call(A::SoundBank, waves),
                attempt.call(A::SoundBank, settings),
                (begin; A::SoundBank.new(nil, sounds); :accepted; rescue => e; e.class; end),
                (begin; A::SoundBank.new("engine", sounds); :accepted; rescue => e; e.class; end)]
      engine.Dispose
      values
    end
    game.Run
    values = game.result
    game.Dispose

    assert_equal [:accepted, ArgumentError, ArgumentError, ArgumentError, ArgumentError], values[0..4]
    assert_equal [:accepted, ArgumentError, ArgumentError], values[5..7]
    assert_equal [ArgumentError, TypeError], values[8..9]
  end

  # `(GetStatus() & 4) != 0` and `(GetStatus() & 0x80) != 0` — the wave bank's two status bits.
  def test_the_wave_bank_reports_its_own_status
    values = with_banks do |_engine, bank, _sounds|
      [bank.IsDisposed, bank.IsPrepared, bank.IsInUse]
    end
    assert_equal [false, true, false], values,
                 "a freshly loaded bank is prepared and not yet in use"
  end

  # `GetCue` refuses an unknown name as an **argument** problem — XNA turns XACT's `E_INVALIDARG`
  # into `ArgumentException(CueNotFound)` — while `PlayCue` reports the same underlying error as an
  # **operation** problem. Two exception types for one native failure, and both are the IL's.
  def test_get_cue_and_play_cue_report_the_same_failure_differently
    values = with_banks do |_engine, _waves, bank|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { bank.GetCue("no_such_cue") }, err.call { bank.PlayCue("no_such_cue") },
       err.call { bank.GetCue(nil) }, err.call { bank.GetCue("") },
       err.call { bank.PlayCue(nil) }, err.call { bank.PlayCue("") },
       err.call { bank.PlayCue("menu_scroll") },
       err.call { bank.PlayCue("menu_scroll", A::AudioListener.new, A::AudioEmitter.new) },
       err.call { bank.PlayCue("menu_scroll", nil, A::AudioEmitter.new) },
       bank.IsDisposed, bank.IsInUse]
    end
    assert_equal ArgumentError, values[0], "GetCue reports an argument problem"
    assert_equal ::RuntimeError, values[1], "PlayCue reports an operation problem"
    assert_equal [ArgumentError] * 4, values[2..5]
    assert_equal %i[ok ok], values[6..7]
    assert_equal ArgumentError, values[8]
    assert_equal false, values[9]
  end

  # The seven status properties are one XACT bitmask, and CNA answers all seven in `CNA_CueInfo`.
  # A cue that has been asked for but not played is prepared and nothing else.
  def test_the_cue_state_machine_moves_the_way_the_status_bits_say
    values = with_banks do |engine, _waves, bank|
      cue = bank.GetCue("menu_scroll")
      before = %i[IsCreated IsPreparing IsPrepared IsPlaying IsStopping IsStopped IsPaused]
              .to_h { |name| [name, cue.public_send(name)] }
      cue.Play
      engine.Update
      after = %i[IsCreated IsPreparing IsPrepared IsPlaying IsStopping IsStopped IsPaused]
             .to_h { |name| [name, cue.public_send(name)] }
      [cue.Name, cue.__send__(:native_name), before, after, cue.IsDisposed]
    end
    assert_equal "menu_scroll", values[0]
    assert_equal values[0], values[1], "and XACT agrees about what the cue is called"
    assert_equal true, values[2].fetch(:IsPrepared), "asked for, not yet played"
    assert_equal false, values[2].fetch(:IsPlaying)
    assert_equal true, values[3].fetch(:IsPlaying), "and after Play plus a pump, it really plays"
    assert_equal false, values[4]
  end

  # `if (!applied3D && played) throw new InvalidOperationException(Apply3DBeforePlay)` — so the
  # **first** apply has to precede the first play, and every later one is allowed. It is the same
  # rule `SoundEffectInstance.Apply3D` carries and it is reproduced managed-side for the same
  # reason: it is a managed rule, not XACT's.
  def test_apply3d_must_come_before_the_first_play_and_is_free_afterwards
    values = with_banks do |_engine, _waves, bank|
      listener = A::AudioListener.new
      emitter = A::AudioEmitter.new
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }

      early = bank.GetCue("menu_scroll")
      first = err.call { early.Apply3D(listener, emitter) }
      second = err.call { early.Play }
      third = err.call { early.Apply3D(listener, emitter) }

      late = bank.GetCue("menu_scroll")
      played = err.call { late.Play }
      refused = err.call { late.Apply3D(listener, emitter) }

      [first, second, third, played, refused,
       err.call { early.Apply3D(nil, emitter) }, err.call { early.Apply3D(listener, nil) }]
    end
    assert_equal %i[ok ok ok], values[0..2], "apply, play, apply again"
    assert_equal :ok, values[3]
    assert_equal ::RuntimeError, values[4], "but a first apply after a play is refused"
    assert_equal [ArgumentError, ArgumentError], values[5..6]
  end

  def test_the_transport_and_variables_reach_xact
    values = with_banks do |_engine, _waves, bank|
      cue = bank.GetCue("menu_scroll")
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { cue.Play }, err.call { cue.Pause }, err.call { cue.Resume },
       err.call { cue.Stop(A::AudioStopOptions::Immediate) },
       err.call { cue.Stop(A::AudioStopOptions::AsAuthored) },
       err.call { cue.Stop(:immediate) },
       cue.GetVariable("Distance"),
       err.call { cue.SetVariable("Distance", 5.0) },
       err.call { cue.GetVariable(nil) }, err.call { cue.GetVariable("") },
       err.call { cue.SetVariable(nil, 1.0) }, err.call { cue.SetVariable("", 1.0) }]
    end
    assert_equal %i[ok ok ok ok ok], values[0..4]
    assert_equal TypeError, values[5]
    assert_kind_of Float, values[6], "Distance is cue-scoped, which is why the *engine* refuses it"
    assert_equal :ok, values[7]
    assert_equal [ArgumentError] * 4, values[8..11]
  end

  # DEVIATION, recorded: CNA refuses `cna_sound_bank_destroy` while any cue of that bank is alive --
  # "All C Cue children must be destroyed before their SoundBank" -- and refuses the engine while a
  # bank is alive. XNA leaves both to the CLR. So the bank disposes its cues first and the engine
  # disposes its banks first, which is the enforced parent/child destruction the SoundEffect cluster
  # already records.
  def test_disposal_cascades_because_cna_requires_it
    values = with_banks do |engine, wave_bank, bank|
      first = bank.GetCue("menu_scroll")
      second = bank.GetCue("menu_scroll")
      held = bank.instance_variable_get(:@cues).length
      second.Dispose
      after_one = bank.instance_variable_get(:@cues).length

      seen = []
      first.Disposing.add(->(_s, _a) { seen << :cue })
      bank.Disposing.add(->(_s, _a) { seen << :bank })
      bank.Dispose
      cascaded = [first.IsDisposed, bank.IsDisposed, seen]

      engine_banks = engine.instance_variable_get(:@banks).length
      engine.Dispose
      [held, after_one, cascaded, engine_banks,
       [wave_bank.IsDisposed, engine.IsDisposed],
       (begin; first.Play; :ok; rescue => e; e.class; end),
       (begin; bank.GetCue("menu_scroll"); :ok; rescue => e; e.class; end)]
    end
    assert_equal 2, values[0]
    assert_equal 1, values[1], "a cue that disposes itself leaves its bank's list"
    assert_equal [true, true], values[2][0..1]
    assert_equal %i[bank cue], values[2][2], "the bank's own event first, then the cue it disposes"
    assert_equal 1, values[3], "only the wave bank is left for the engine to cascade to"
    assert_equal [true, true], values[4]
    assert_equal [CNA::DisposedObjectError, CNA::DisposedObjectError], values[5..6]
  end

  # ------------------------------------------------------------------- and exactly what it does not

  # XNA's `Play` tolerates exactly `0x8ac70008`, XACT's cue-instance limit. `CNA_Result` has no code
  # for it, so nothing is swallowed on a guess — and the exemption was measured unreachable here.
  def test_nothing_is_swallowed_in_place_of_the_cue_instance_limit
    refute_match(/rescue/, File.read(ROOT.join("lib", "microsoft", "xna", "framework", "audio.rb"))
                               .split("def Play\n").last.split("\n          end").first.to_s)
    values = with_banks do |engine, _waves, bank|
      outcomes = Hash.new(0)
      30.times do
        cue = bank.GetCue("menu_scroll")
        begin
          cue.Play
          outcomes[:ok] += 1
        rescue StandardError => error
          outcomes[error.class] += 1
        end
        engine.Update
      end
      outcomes
    end
    assert_equal({ ok: 30 }, values.transform_keys(&:to_sym),
                 "thirty consecutive plays, no instance limit reached on this artifact")
  end
end
