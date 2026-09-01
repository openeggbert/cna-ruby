# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Audio.DynamicSoundEffectInstance` — the streaming instance, and the first type here whose event
# is raised by CNA rather than by this binding.
class DynamicSoundEffectInstanceTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = Microsoft::Xna::Framework::Audio
  D = Microsoft::Xna::Framework::Audio::DynamicSoundEffectInstance
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  RATE = 44_100
  # 4410 mono frames = 8820 bytes = a tenth of a second, and a whole number of 2-byte blocks.
  def pcm = ([0] * 4_410).pack("s<*")

  # ------------------------------------------------------------------- the contract, from metadata

  def test_it_is_the_sealed_streaming_subclass_the_reference_declares
    contract = REFERENCE.fetch("Microsoft.Xna.Framework.Audio.DynamicSoundEffectInstance")
    assert contract.fetch("sealed")
    assert_equal "Microsoft.Xna.Framework.Audio.SoundEffectInstance", contract.fetch("baseType")
    assert_equal 10, contract.fetch("members").length
    assert D < A::SoundEffectInstance

    # It is the one SoundEffectInstance with a public constructor, because it has no SoundEffect
    # behind it -- which is also why CNA's create route is game-parented.
    assert_raises(NoMethodError) { A::SoundEffectInstance.new }
    assert_respond_to D, :new
    assert_equal 1, CNA::Native::Manifest::FUNCTIONS
                    .count { |entry| entry.symbol == "cna_dynamic_sound_effect_instance_create" }
  end

  def test_the_scoreboard_and_the_event_census
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Audio.DynamicSoundEffectInstance"
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal ReviewedScoreboard::EVENT_OWNER_TYPES, STRICT.fetch("EVENT_OWNER_TYPES")
    assert_includes STRICT.fetch("eventIdentities"),
                    "Microsoft.Xna.Framework.Audio.DynamicSoundEffectInstance::BufferNeeded"
  end

  # `update_ext` is the per-instance half of a pump `FrameworkDispatcher.Update` already drives.
  # Binding it would give this binding two pumps for one queue.
  def test_the_second_pump_is_not_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_framework_dispatcher_update"
    refute_includes symbols, "cna_dynamic_sound_effect_instance_update_ext"
    refute_includes symbols, "cna_dynamic_sound_effect_instance_clear_buffers_ext"
    refute_includes symbols, "cna_dynamic_sound_effect_instance_submit_float_buffer_ext"
  end

  # ------------------------------------------------------------------------ managed validation

  def test_the_constructor_bounds_are_the_same_literals_sound_effect_carries
    [7_999, 48_001, 0, -1].each do |rate|
      assert_raises(RangeError, rate.to_s) { D.new(rate, A::AudioChannels::Mono) }
    end
    [0, 3, -1].each { |c| assert_raises(RangeError, c.to_s) { D.new(RATE, c) } }
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

  def test_it_starts_empty_stopped_and_unlooped
    values = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      out = [instance.PendingBufferCount, instance.State.to_s, instance.IsLooped, instance.IsDisposed]
      instance.Dispose
      out
    end
    assert_equal [0, "Stopped", false, false], values
  end

  # The two per-instance computations use the instance's own format rather than arguments, which is
  # what makes them instance members here where `SoundEffect`'s two are statics.
  def test_the_two_computations_use_the_instances_own_format
    values = with_audio do
      mono = D.new(RATE, A::AudioChannels::Mono)
      stereo = D.new(RATE, A::AudioChannels::Stereo)
      out = [mono.GetSampleDuration(88_200), stereo.GetSampleDuration(88_200),
             mono.GetSampleSizeInBytes(1.0), stereo.GetSampleSizeInBytes(1.0),
             (begin; mono.GetSampleDuration(-1); nil; rescue => e; e.class; end)]
      mono.Dispose
      stereo.Dispose
      out
    end
    assert_in_delta 1.0, values[0], 1e-9
    assert_in_delta 0.5, values[1], 1e-9, "the same bytes are half as long in stereo"
    assert_equal 88_200, values[2]
    assert_equal 176_400, values[3]
    assert_equal ArgumentError, values[4]
  end

  # Submitting really queues: `PendingBufferCount` is the count the runtime keeps, not a managed
  # tally, so a submission that failed would show here.
  def test_submitting_queues_and_the_pending_count_is_the_runtimes
    values = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      before = instance.PendingBufferCount
      instance.SubmitBuffer(pcm)
      one = instance.PendingBufferCount
      instance.SubmitBuffer(pcm, 0, pcm.bytesize)
      two = instance.PendingBufferCount
      instance.SubmitBuffer(pcm, 2, pcm.bytesize - 2)
      three = instance.PendingBufferCount
      instance.Dispose
      [before, one, two, three]
    end
    assert_equal [0, 1, 2, 3], values
  end

  # Block alignment is the rule a summary would lose: length, offset and count must each be a whole
  # number of frames, which for PCM16 mono is two bytes. Three different messages for what looks
  # like one rule.
  def test_every_argument_must_be_block_aligned
    kinds = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      out = {
        nil_buffer: (begin; instance.SubmitBuffer(nil); nil; rescue => e; e.class; end),
        empty: (begin; instance.SubmitBuffer(""); nil; rescue => e; e.class; end),
        odd_length: (begin; instance.SubmitBuffer("abc"); nil; rescue => e; e.class; end),
        odd_offset: (begin; instance.SubmitBuffer(pcm, 1, 100); nil; rescue => e; e.class; end),
        odd_count: (begin; instance.SubmitBuffer(pcm, 0, 3); nil; rescue => e; e.class; end),
        zero_count: (begin; instance.SubmitBuffer(pcm, 0, 0); nil; rescue => e; e.class; end),
        past_end: (begin; instance.SubmitBuffer(pcm, 0, pcm.bytesize + 2); nil; rescue => e; e.class; end),
        offset_past_end: (begin; instance.SubmitBuffer(pcm, pcm.bytesize, 2); nil; rescue => e; e.class; end),
        wrong_type: (begin; instance.SubmitBuffer([0, 1]); nil; rescue => e; e.class; end),
        still_empty: instance.PendingBufferCount
      }
      instance.Dispose
      out
    end
    assert_equal TypeError, kinds.fetch(:wrong_type)
    kinds.reject { |k, _| %i[wrong_type still_empty].include?(k) }
         .each { |name, kind| assert_equal ArgumentError, kind, name.to_s }
    assert_equal 0, kinds.fetch(:still_empty), "not one refused submission reached the runtime"
  end

  # A stereo instance's block is four bytes, so a two-byte count is aligned for mono and not for
  # stereo. Same code, different format, different answer.
  def test_alignment_follows_the_channel_count
    kinds = with_audio do
      stereo = D.new(RATE, A::AudioChannels::Stereo)
      out = [(begin; stereo.SubmitBuffer(pcm, 0, 2); nil; rescue => e; e.class; end),
             (begin; stereo.SubmitBuffer(pcm, 0, 4); :ok; rescue => e; e.class; end)]
      stereo.Dispose
      out
    end
    assert_equal [ArgumentError, :ok], kinds
  end

  # `set_IsLooped` throws `InvalidOperationException(InvalidDynamicIsLoopedCall)` for true and
  # accepts false: a streaming instance has nothing fixed to loop over. The getter is inherited.
  def test_is_looped_narrows_to_false_only
    values = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      refused = begin; instance.IsLooped = true; nil; rescue => e; e.class; end
      instance.IsLooped = false
      out = [refused, instance.IsLooped]
      instance.Dispose
      out
    end
    assert_equal [RuntimeError, false], values
  end

  # `Play` primes the queue before starting, which is what makes a streaming instance different
  # from an ordinary one.
  def test_play_primes_the_queue_and_the_state_machine_still_works
    states = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      instance.SubmitBuffer(pcm)
      seen = [instance.State.to_s]
      instance.Play
      seen << instance.State.to_s
      instance.Pause
      seen << instance.State.to_s
      instance.Resume
      seen << instance.State.to_s
      instance.Stop
      seen << instance.State.to_s
      instance.Dispose
      seen
    end
    assert_equal %w[Stopped Playing Paused Playing Stopped], states
  end

  # The event is raised by **CNA**, from whichever thread advances the queue, and what advances it
  # here is `FrameworkDispatcher.Update` — the member this binding already projects. So this is the
  # first projected event whose raiser is the native runtime rather than this binding.
  def test_buffer_needed_is_raised_by_the_canonical_pump
    values = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      seen = []
      instance.BufferNeeded.add(->(sender, args) { seen << [sender.equal?(instance), args] })
      instance.SubmitBuffer(pcm)
      instance.Play
      before = seen.length
      5.times { F::FrameworkDispatcher.Update }
      after = seen.length
      registered = instance.instance_variable_get(:@buffer_registration) != 0
      instance.Dispose
      [before, after, registered, seen.first]
    end
    assert_equal 0, values[0], "nothing fires before the pump runs"
    assert_operator values[1], :>, 0, "and the canonical pump really raises it"
    assert values[2]
    assert_equal [true, CNA::Runtime::EventArgs::Empty], values[3],
                 "the sender is the instance and the argument is EventArgs.Empty"
  end

  # The registration is released before the base releases the instance, so the callback can never be
  # raised against a handle that is already gone.
  def test_disposal_releases_the_registration_first
    values = with_audio do
      instance = D.new(RATE, A::AudioChannels::Mono)
      before = instance.instance_variable_get(:@buffer_registration) != 0
      instance.Dispose
      after = instance.instance_variable_get(:@buffer_registration)
      instance.Dispose # idempotent
      [before, after, instance.IsDisposed,
       (begin; instance.PendingBufferCount; nil; rescue => e; e.class; end),
       (begin; instance.SubmitBuffer(pcm); nil; rescue => e; e.class; end)]
    end
    assert_equal [true, 0, true, CNA::DisposedObjectError, CNA::DisposedObjectError], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_engine_or_microphone
    # `Microphone` arrived in the milestone after this one; what this claims is that the streaming
    # instance built no capture surface of its own.
    %i[SoundBank WaveBank Cue].each do |absent|
      refute A.const_defined?(absent, false), absent.to_s
    end
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:callbacks), CNA::Native::Manifest::CALLBACKS.length
  end
end
