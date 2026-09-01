# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Audio.SoundEffect` and `Audio.SoundEffectInstance` — the cluster Native frontier 4 recorded as
# `UPSTREAM_CNA_BLOCKED` and the ABI migration reopened by measurement.
#
# Every range assertion here is a literal read out of the pinned IL, not a documented range: the
# sample-rate bounds are `0x1f40`/`0xbb80`, and each comparison is `blt.un`/`bgt.un`, which is
# **unordered** — so NaN takes the throw branch, and that is asserted rather than assumed.
class SoundEffectTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = Microsoft::Xna::Framework::Audio
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  CAPABILITIES = JSON.parse(ROOT.join("docs", "runtime-capabilities.json").read).freeze

  RATE = 44_100
  FRAMES = 22_050 # exactly half a second of mono PCM16

  def pcm = ([0] * FRAMES).pack("s<*")

  # ------------------------------------------------------------------- the contract, from metadata

  def test_both_types_are_the_shapes_the_reference_declares
    effect = REFERENCE.fetch("Microsoft.Xna.Framework.Audio.SoundEffect")
    assert effect.fetch("sealed")
    assert_equal ["System.IDisposable"], effect.fetch("directInterfaces")
    assert_equal 17, effect.fetch("members").length

    instance = REFERENCE.fetch("Microsoft.Xna.Framework.Audio.SoundEffectInstance")
    refute instance.fetch("sealed"), "SoundEffectInstance is the base of DynamicSoundEffectInstance"
    assert_equal ["System.IDisposable"], instance.fetch("directInterfaces")
    assert_equal 16, instance.fetch("members").length
  end

  def test_the_scoreboard_records_both_complete
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    %w[SoundEffect SoundEffectInstance].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Audio.#{name}"
    end
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") },
                    "Microsoft.Xna.Framework.Audio.SoundEffectInstance"
  end

  # The capability row this milestone rests on: the blocker was measured away before anything was
  # built on it, and the registry has to still say so.
  def test_the_reopened_capability_row_is_the_one_this_rests_on
    row = CAPABILITIES.fetch("capabilities").find { |entry| entry.fetch("id") == "audio.sound-effect-playback" }
    refute_nil row
    refute_equal "UPSTREAM_CNA_BLOCKED", row.fetch("category")
    assert_includes row.fetch("evidence"), "CNA never reads CNA_AUDIO"
  end

  # ------------------------------------------------------------------------ managed validation

  # These need no Game: the constructor validates its arguments before it reaches the native
  # creation, so every one of these refusals happens with no CNA call at all.
  def test_the_constructor_bounds_are_the_literals_the_il_carries
    [7_999, 48_001, 0, -1].each do |rate|
      assert_raises(RangeError, rate.to_s) { A::SoundEffect.new(pcm, rate, A::AudioChannels::Mono) }
    end
    [0, 3, -1].each do |channels|
      assert_raises(RangeError, channels.to_s) { A::SoundEffect.new(pcm, RATE, channels) }
    end
    assert_raises(ArgumentError) { A::SoundEffect.new(nil, RATE, A::AudioChannels::Mono) }
    assert_raises(ArgumentError) { A::SoundEffect.new("", RATE, A::AudioChannels::Mono) }
    assert_raises(TypeError) { A::SoundEffect.new([0, 1], RATE, A::AudioChannels::Mono) }
    assert_raises(ArgumentError) { A::SoundEffect.FromStream(nil) }
  end

  # `MIN`/`MAX` are `0x1f40` and `0xbb80` in the IL. Naming them here as decimals proves the
  # transcription rather than restating it.
  def test_the_sample_rate_bounds_are_8000_and_48000
    assert_equal [8_000, 48_000], [A::SoundEffect::MIN_SAMPLE_RATE, A::SoundEffect::MAX_SAMPLE_RATE]
    assert_equal 0x1f40, A::SoundEffect::MIN_SAMPLE_RATE
    assert_equal 0xbb80, A::SoundEffect::MAX_SAMPLE_RATE
  end

  # ---------------------------------------------------------------------------- native behaviour

  class AudioGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
    end

    def LoadContent
      @result = @body.call
    ensure
      self.Exit
    end
  end

  def with_audio
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = AudioGame.new { yield }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def test_a_sound_effect_reports_the_duration_its_pcm_really_carries
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      out = [effect.Duration, effect.IsDisposed, effect.Name]
      effect.Dispose
      out + [effect.IsDisposed]
    end
    # 22050 mono frames at 44100 Hz is exactly half a second. Native frontier 4 measured this as
    # zero against the retired artifact, which is the finding this milestone rests on.
    assert_in_delta 0.5, values[0], 1e-9
    assert_equal [false, "", true], values[1..]
  end

  def test_the_name_round_trips_and_refuses_nil
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      effect.Name = "tone"
      out = [effect.Name, (begin; effect.Name = nil; nil; rescue => e; e.class; end)]
      effect.Dispose
      out
    end
    assert_equal ["tone", ArgumentError], values
  end

  # The state machine Native frontier 4 measured as never leaving `Stopped`.
  def test_the_state_machine_moves_through_every_transition
    states = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      seen = [instance.State]
      instance.Play
      seen << instance.State
      instance.Pause
      seen << instance.State
      instance.Resume
      seen << instance.State
      instance.Stop
      seen << instance.State
      instance.Dispose
      effect.Dispose
      seen.map(&:to_s)
    end
    assert_equal %w[Stopped Playing Paused Playing Stopped], states
  end

  # `if (isPacketSubmitted) throw new InvalidOperationException(InvalidIsLoopedCall)`, then one
  # `stfld`. CNA enforces the same rule natively; the managed guard is what gives the refusal XNA's
  # identity rather than a translated native error.
  def test_is_looped_is_settable_before_play_and_refused_after
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      before = instance.IsLooped
      instance.IsLooped = true
      set = instance.IsLooped
      instance.Play
      after = begin; instance.IsLooped = false; nil; rescue => e; e.class; end
      still = instance.IsLooped
      instance.Dispose
      effect.Dispose
      [before, set, after, still]
    end
    assert_equal [false, true, RuntimeError, true], values
  end

  # Each of the three setters range-checks in managed code with an **unordered** comparison, so NaN
  # throws. CNA's three disagree with each other -- volume unclamped, pitch clamped, pan refused --
  # which is exactly why the check has to be here for all three to behave alike.
  def test_the_three_setters_round_trip_and_refuse_out_of_range_and_nan
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      instance.Volume = 0.25
      instance.Pitch = -0.5
      instance.Pan = 0.75
      round_trip = [instance.Volume, instance.Pitch, instance.Pan]
      refusals = {
        volume_high: (begin; instance.Volume = 1.5; nil; rescue => e; e.class; end),
        volume_low: (begin; instance.Volume = -0.1; nil; rescue => e; e.class; end),
        volume_nan: (begin; instance.Volume = Float::NAN; nil; rescue => e; e.class; end),
        pitch_high: (begin; instance.Pitch = 1.5; nil; rescue => e; e.class; end),
        pitch_nan: (begin; instance.Pitch = Float::NAN; nil; rescue => e; e.class; end),
        pan_low: (begin; instance.Pan = -1.5; nil; rescue => e; e.class; end),
        pan_nan: (begin; instance.Pan = Float::NAN; nil; rescue => e; e.class; end)
      }
      unchanged = [instance.Volume, instance.Pitch, instance.Pan]
      instance.Dispose
      effect.Dispose
      [round_trip, refusals, unchanged]
    end
    assert_equal [0.25, -0.5, 0.75], values[0]
    values[1].each { |name, kind| assert_equal RangeError, kind, name.to_s }
    assert_equal values[0], values[2], "a refused setter must leave the value alone"
  end

  # The rule a summary would lose: `set_Pan` clears `is3d` again unless a packet has been submitted,
  # so `Apply3D` **before the first play** does not lock `Pan` out, and after it does.
  def test_apply3d_locks_pan_only_once_playback_has_begun
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      before = effect.CreateInstance
      before.Apply3D(A::AudioListener.new, A::AudioEmitter.new)
      before.Pan = 0.5
      allowed = before.Pan

      # 3D first, then play: `is3d` stays set because a packet has now been submitted, so `Pan` is
      # refused from here on.
      after = effect.CreateInstance
      after.Apply3D(A::AudioListener.new, A::AudioEmitter.new)
      after.Play
      refused = begin; after.Pan = 0.5; nil; rescue => e; e.class; end
      # And a *second* 3D call on an instance already positioned in 3D is allowed at any time.
      again = (after.Apply3D(A::AudioListener.new, A::AudioEmitter.new); :ok)

      # Play first, then 3D, on an instance that was never 3D: `if (!is3d) throw`. CNA refuses the
      # identical case natively, so the two agree and the managed guard only supplies the identity.
      plain = effect.CreateInstance
      plain.Play
      never = begin; plain.Apply3D(A::AudioListener.new, A::AudioEmitter.new); nil; rescue => e; e.class; end

      before.Dispose
      after.Dispose
      plain.Dispose
      effect.Dispose
      [allowed, refused, again, never]
    end
    assert_equal [0.5, RuntimeError, :ok, RuntimeError], values
  end

  def test_apply3d_accepts_one_listener_or_many_and_refuses_neither
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      one = (instance.Apply3D(A::AudioListener.new, A::AudioEmitter.new); :ok)
      many = (instance.Apply3D([A::AudioListener.new, A::AudioListener.new], A::AudioEmitter.new); :ok)
      empty = begin; instance.Apply3D([], A::AudioEmitter.new); nil; rescue => e; e.class; end
      wrong = begin; instance.Apply3D(A::AudioListener.new, A::AudioListener.new); nil; rescue => e; e.class; end
      instance.Dispose
      effect.Dispose
      [one, many, empty, wrong]
    end
    assert_equal [:ok, :ok, ArgumentError, TypeError], values
  end

  # `Stop()` is `Stop(true)`. The Boolean chooses an immediate stop over one that runs to the end of
  # the authored sound, and CNA really distinguishes them: measured, `stop(false)` on a playing
  # instance leaves it Playing.
  def test_stop_distinguishes_immediate_from_as_authored
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      instance.Play
      instance.Stop(false)
      as_authored = instance.State.to_s
      instance.Stop(true)
      immediate = instance.State.to_s
      instance.Dispose
      effect.Dispose
      [as_authored, immediate]
    end
    assert_equal %w[Playing Stopped], values
  end

  # ------------------------------------------------------------------------------ the statics

  # Both are pure computations in XNA and take no handle in CNA either, so these are the only two
  # members of the type that work with no Game at all.
  def test_the_two_static_computations_need_no_game
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    assert_in_delta 1.0, A::SoundEffect.GetSampleDuration(88_200, RATE, A::AudioChannels::Mono), 1e-9
    assert_in_delta 0.5, A::SoundEffect.GetSampleDuration(88_200, RATE, A::AudioChannels::Stereo), 1e-9
    assert_equal 88_200, A::SoundEffect.GetSampleSizeInBytes(1.0, RATE, A::AudioChannels::Mono)
    assert_equal 0, A::SoundEffect.GetSampleDuration(0, RATE, A::AudioChannels::Mono)
    assert_raises(RangeError) { A::SoundEffect.GetSampleDuration(1, 7_999, A::AudioChannels::Mono) }
    assert_raises(ArgumentError) { A::SoundEffect.GetSampleDuration(-1, RATE, A::AudioChannels::Mono) }
    assert_raises(RangeError) { A::SoundEffect.GetSampleSizeInBytes(1.0, RATE, 3) }
  end

  # The four global settings, each with its own IL-derived rule. The asymmetry between DopplerScale
  # and DistanceScale over NaN is the IL's, not this projection's.
  def test_the_four_global_settings_keep_their_four_different_rules
    values = with_audio do
      A::SoundEffect.MasterVolume = 0.5
      A::SoundEffect.DopplerScale = 2.0
      A::SoundEffect.SpeedOfSound = 100.0
      A::SoundEffect.DistanceScale = 0.0
      {
        master: A::SoundEffect.MasterVolume,
        doppler: A::SoundEffect.DopplerScale,
        speed: A::SoundEffect.SpeedOfSound,
        distance: A::SoundEffect.DistanceScale,
        master_high: (begin; A::SoundEffect.MasterVolume = 1.5; nil; rescue => e; e.class; end),
        master_nan: (begin; A::SoundEffect.MasterVolume = Float::NAN; nil; rescue => e; e.class; end),
        doppler_negative: (begin; A::SoundEffect.DopplerScale = -1.0; nil; rescue => e; e.class; end),
        doppler_nan: (begin; A::SoundEffect.DopplerScale = Float::NAN; nil; rescue => e; e.class; end),
        distance_negative: (begin; A::SoundEffect.DistanceScale = -1.0; nil; rescue => e; e.class; end),
        distance_nan: (begin; A::SoundEffect.DistanceScale = Float::NAN; nil; rescue => e; e.class; end),
        speed_zero: (begin; A::SoundEffect.SpeedOfSound = 0.0; nil; rescue => e; e.class; end)
      }
    end
    assert_in_delta 0.5, values.fetch(:master), 1e-6
    assert_in_delta 2.0, values.fetch(:doppler), 1e-6
    assert_in_delta 100.0, values.fetch(:speed), 1e-6
    # `if (value <= Single.Epsilon) value = Single.Epsilon` — zero is accepted and clamped up,
    # never refused.
    assert_operator values.fetch(:distance), :>, 0.0
    assert_operator values.fetch(:distance), :<, 1e-40

    assert_equal RangeError, values.fetch(:master_high)
    assert_equal RangeError, values.fetch(:master_nan)
    assert_equal RangeError, values.fetch(:doppler_negative)
    assert_equal RangeError, values.fetch(:speed_zero)
    # `blt.un` throws for NaN; `bge.un` does not. The two scale properties really do disagree.
    assert_equal RangeError, values.fetch(:doppler_nan)
    assert_nil values.fetch(:distance_nan), "DistanceScale's bge.un accepts NaN where DopplerScale's blt.un rejects it"
  end

  # ---------------------------------------------------------------------------- ownership

  # The instance is a child of its effect and CNA enforces the order: destroying an effect with a
  # live instance answers CNA_RESULT_INVALID_STATE. The Ruby side must not paper over that.
  def test_an_instance_is_a_child_and_the_destruction_order_is_enforced
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      refused = begin; effect.Dispose; nil; rescue => e; e.class; end
      instance.Dispose
      effect.Dispose
      [refused, instance.IsDisposed, effect.IsDisposed]
    end
    assert_equal CNA::NativeError, values[0]
    assert_equal [true, true], values[1..]
  end

  def test_every_member_refuses_a_disposed_object
    kinds = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      instance = effect.CreateInstance
      instance.Dispose
      instance.Dispose # idempotent
      effect.Dispose
      [
        (begin; instance.State; nil; rescue => e; e.class; end),
        (begin; instance.Play; nil; rescue => e; e.class; end),
        (begin; instance.Volume = 0.5; nil; rescue => e; e.class; end),
        (begin; effect.Duration; nil; rescue => e; e.class; end),
        (begin; effect.CreateInstance; nil; rescue => e; e.class; end),
        (begin; effect.Play; nil; rescue => e; e.class; end)
      ]
    end
    kinds.each { |kind| assert_equal CNA::DisposedObjectError, kind }
  end

  def test_fire_and_forget_play_answers_a_boolean
    values = with_audio do
      effect = A::SoundEffect.new(pcm, RATE, A::AudioChannels::Mono)
      out = [effect.Play, effect.Play(0.5, 0.25, -0.25),
             (begin; effect.Play(2.0, 0.0, 0.0); nil; rescue => e; e.class; end)]
      effect.Dispose
      out
    end
    assert_equal [true, true, RangeError], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_engine_microphone_or_dynamic_instance
    # DynamicSoundEffectInstance was added by the milestone after this one; what this claims is
    # that the SoundEffect cluster built neither an engine nor a streaming instance of its own.
    %i[AudioEngine SoundBank WaveBank Cue Microphone AudioCategory].each do |absent|
      refute A.const_defined?(absent, false), absent.to_s
    end
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end

  # Nothing here claims anything was heard.
  def test_no_audible_output_is_claimed
    row = CAPABILITIES.fetch("capabilities").find { |entry| entry.fetch("id") == "audio.sound-effect-playback" }
    assert_includes row.fetch("evidence"), "NO AUDIBLE OUTPUT IS CLAIMED"
  end
end
