# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Audio.Microphone` — the sixth frontier candidate whose `NATIVE_RUNTIME` classification was wrong,
# and the first projected type that addresses a device by **index** rather than by handle.
#
# What this file does not do: start a capture. Every managed behaviour `Microphone` declares is
# reachable without opening the device — `GetData`'s whole validation ladder ends in
# `if (State != Started) return 0`, which a stopped microphone answers — so the suite measures the
# contract in full and never records from the machine it runs on. `Start`/`Stop` are implemented and
# left unexercised deliberately; `docs/microphone-evidence.md` §7 says so rather than reporting an
# untested path as measured.
class MicrophoneTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = Microsoft::Xna::Framework::Audio
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Audio.Microphone"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_the_whole_contract_is_projected_including_the_public_field
    contract = REFERENCE.fetch(NAME)
    assert contract.fetch("sealed")
    assert_equal "System.Object", contract.fetch("baseType")
    assert_equal 15, contract.fetch("members").length

    # `Name` is a **field**, not a property: one reader, no writer.
    field = contract.fetch("members").find { |m| m.fetch("kind") == "field" }
    assert_equal "Name", field.fetch("name")
    assert A::Microphone.public_method_defined?(:Name)
    refute A::Microphone.public_method_defined?(:Name=), "a readonly field projects no writer"

    # `BufferDuration` is the one settable property; `State`, `SampleRate` and `IsHeadset` are not.
    %w[State SampleRate IsHeadset].each do |readonly|
      assert A::Microphone.public_method_defined?(readonly), readonly
      refute A::Microphone.public_method_defined?("#{readonly}="), readonly
    end
    assert A::Microphone.public_method_defined?(:BufferDuration=)

    # The constructor is `assembly`, so `new` is private under Foundation 25's rule and a consumer
    # reaches a device only through `All` or `Default`.
    assert_raises(NoMethodError) { A::Microphone.new(nil, 0) }
    assert_equal %i[All Default], (A::Microphone.singleton_methods(false) & %i[All Default]).sort
  end

  # `protected Finalize` is projected as the member the contract declares, and it registers no Ruby
  # finalizer: nothing in this binding is destroyed by the garbage collector.
  def test_finalize_is_protected_and_registers_nothing
    assert_includes A::Microphone.protected_instance_methods(false), :Finalize
    refute_includes A::Microphone.public_instance_methods(false), :Finalize
    refute_includes A::Microphone.instance_methods(false), :Dispose
    # There is no handle to release, so the type declares no native-resource machinery at all.
    refute A::Microphone.include?(CNA::Runtime::NativeResource)
  end

  def test_the_event_is_the_one_the_contract_declares
    contract = REFERENCE.fetch(NAME)
    events = contract.fetch("members").select { |m| m.fetch("kind") == "event" }.map { |m| m.fetch("name") }
    assert_equal %w[BufferReady], events
    assert_equal %i[BufferReady], A::Microphone.xna_event_identities
    assert_equal "System.EventHandler`1[System.EventArgs]",
                 contract.fetch("members").find { |m| m.fetch("kind") == "event" }.fetch("type")
  end

  def test_the_scoreboard_records_it_complete_and_the_frontier_loses_a_candidate
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }, NAME
  end

  # ------------------------------------------------------------------------- the routes, and 0.7.0

  # Native frontier 4 called this cluster `NATIVE_RUNTIME`. The sixteen routes it needs are declared
  # by the **retired 0.7.0 headers** identically — the ABI gate's cross-version check proves it — so
  # the classification was never about the ABI.
  def test_the_sixteen_routes_are_bound_and_none_of_them_carries_a_handle
    symbols = CNA::Native::Manifest::FUNCTIONS.select { |e| e.symbol.start_with?("cna_microphone_") }
    assert_equal 16, symbols.length
    symbols.each do |entry|
      next if entry.symbol == "cna_microphone_check_all_buffers_ext"

      assert_equal "CNA_Handle", entry.c_arguments.first, entry.symbol
      next if entry.symbol.end_with?("_get_count", "_get_default_index_ext")

      assert_equal "uint64_t", entry.c_arguments[1],
                   "#{entry.symbol} addresses a device by index, because CNA has no microphone handle"
    end
    refute_includes symbols.map(&:symbol), "cna_microphone_destroy"
    assert_equal({ "CNA_MICROPHONE_STATE_STARTED" => 0, "CNA_MICROPHONE_STATE_STOPPED" => 1,
                   "CNA_MICROPHONE_STATE_MAXIMUM" => 1 },
                 CNA::Native::Manifest::CONSTANTS.slice("CNA_MICROPHONE_STATE_STARTED",
                                                        "CNA_MICROPHONE_STATE_STOPPED",
                                                        "CNA_MICROPHONE_STATE_MAXIMUM"))
  end

  # CNA's identities and XNA's agree, which is why `State` passes the value through where XNA's own
  # managed getter has to invert it (`native == 1 ? Started : Stopped` over a native 1-is-started).
  def test_the_state_identities_line_up_with_xnas
    assert_equal 0, A::MicrophoneState::Started.to_i
    assert_equal 1, A::MicrophoneState::Stopped.to_i
    assert_equal CNA::Native::Manifest::CONSTANTS.fetch("CNA_MICROPHONE_STATE_STARTED"),
                 A::MicrophoneState::Started.to_i
    assert_equal CNA::Native::Manifest::CONSTANTS.fetch("CNA_MICROPHONE_STATE_STOPPED"),
                 A::MicrophoneState::Stopped.to_i
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

  def with_game
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = HostGame.new { yield }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def with_default_microphone
    with_game do
      device = A::Microphone.Default
      skip "this machine reports no capture device" if device.nil?

      yield device
    end
  end

  # `get_All` re-enumerates and answers the **same** ReadOnlyCollection every time, because the
  # wrapper holds the List rather than a copy. `Default` falls back to index 0 when the platform
  # names no default, so it is nil only on a machine with no capture device at all.
  def test_all_is_one_stable_read_only_collection_and_default_comes_from_it
    values = with_game do
      all = A::Microphone.All
      [all.class, all.equal?(A::Microphone.All), all.Count,
       A::Microphone.Default.equal?(A::Microphone.Default),
       all.Count.zero? || A::Microphone.Default.equal?(A::Microphone.All[0]),
       all.respond_to?(:Add), all.respond_to?(:Clear)]
    end
    assert_equal CNA::Runtime::ReadOnlyCollection, values[0]
    assert_equal true, values[1], "the same collection object, exactly as XNA's static wrapper is"
    assert_operator values[2], :>=, 0
    assert_equal true, values[3]
    assert_equal true, values[4], "Default is the platform default, or index 0 when none says so"
    assert_equal [false, false], values[5..], "a ReadOnlyCollection publishes no mutator"
  end

  # Every device answers a frozen name, a positive rate, a stopped state and XNA's constant headset
  # flag. The names themselves are the machine's, so nothing here asserts a device count.
  def test_every_enumerated_device_answers_a_whole_identity
    rows = with_game do
      A::Microphone.All.map do |m|
        [m.Name, m.Name.frozen?, m.SampleRate, m.State, m.IsHeadset, m.BufferDuration]
      end
    end
    skip "this machine reports no capture device" if rows.empty?

    rows.each do |name, frozen, rate, state, headset, duration|
      assert_kind_of ::String, name
      refute_empty name
      assert_equal true, frozen, "a CLR string is immutable, so the field's projection is frozen"
      assert_operator rate, :>, 0
      assert_equal A::MicrophoneState::Stopped, state, "nothing has started this device"
      assert_equal true, headset
      assert_operator duration, :>, 0.0
    end
  end

  # ------------------------------------------------------------- the arithmetic, and CNA's own

  # A second, independent implementation of `AudioFormat.SizeFromDuration` and `DurationFromSize`
  # straight from the IL, so the projection is compared with the contract rather than with itself.
  def xna_size_from_duration(rate, milliseconds)
    scale = CNA::Runtime::Numeric.f32(CNA::Runtime::Numeric.f32(rate) / 1000.0)
    samples = (milliseconds * scale).truncate
    (samples + (samples % 1)) * 2
  end

  def xna_duration_from_size_ticks(rate, size)
    samples = size / 2
    scaled = CNA::Runtime::Numeric.f32(CNA::Runtime::Numeric.f32(samples) * 1000.0)
    ms = CNA::Runtime::Numeric.f32(scaled / CNA::Runtime::Numeric.f32(rate))
    (ms + 0.5).truncate * 10_000
  end

  def test_the_projection_reproduces_xnas_float32_arithmetic_rather_than_cnas
    values = with_default_microphone do |m|
      rate = m.SampleRate
      sizes = [0.0, 0.001, 0.05, 0.1, 0.5, 1.0].to_h do |seconds|
        [seconds, [m.GetSampleSizeInBytes(seconds),
                   m.__send__(:native_sample_size_in_bytes, (seconds * 10_000_000).round)]]
      end
      durations = [0, 2, 44, 46, 100, 4410, 8818, 8820].to_h do |size|
        [size, [(m.GetSampleDuration(size) * 10_000_000).round,
                m.__send__(:native_sample_duration_ticks, size)]]
      end
      [rate, sizes, durations]
    end
    rate, sizes, durations = values

    sizes.each do |seconds, (projected, _native)|
      expected = seconds.zero? ? 0 : xna_size_from_duration(rate, seconds * 1000.0)
      assert_equal expected, projected, "GetSampleSizeInBytes(#{seconds})"
    end
    durations.each do |size, (projected, _native)|
      expected = size.zero? ? 0 : xna_duration_from_size_ticks(rate, size)
      assert_equal expected, projected, "GetSampleDuration(#{size})"
    end

    # And the divergence itself, which is the reason the arithmetic is managed. CNA is exact where
    # XNA rounds in binary32, so the two disagree on ordinary values rather than on edge cases.
    divergent_sizes = sizes.reject { |_seconds, (projected, native)| projected == native }
    divergent_durations = durations.reject { |_size, (projected, native)| projected == native }
    refute_empty divergent_sizes, "the whole point of the managed arithmetic"
    refute_empty divergent_durations
  end

  # The concrete numbers, asserted only on the rate this machine reports, so the file stays honest
  # on a device that runs at some other rate.
  def test_the_measured_divergence_at_44100_hz
    values = with_default_microphone do |m|
      next nil unless m.SampleRate == 44_100

      { size_100ms: [m.GetSampleSizeInBytes(0.1), m.__send__(:native_sample_size_in_bytes, 1_000_000)],
        size_1s: [m.GetSampleSizeInBytes(1.0), m.__send__(:native_sample_size_in_bytes, 10_000_000)],
        duration_8818: [(m.GetSampleDuration(8818) * 1000).round, m.__send__(:native_sample_duration_ticks, 8818) / 10_000],
        duration_46: [(m.GetSampleDuration(46) * 1000).round, m.__send__(:native_sample_duration_ticks, 46) / 10_000] }
    end
    skip "this machine's default device does not run at 44100 Hz" if values.nil?

    assert_equal [8818, 8820], values.fetch(:size_100ms), "100 ms: XNA truncates 4409.9998 samples"
    assert_equal [88_198, 88_200], values.fetch(:size_1s)
    assert_equal [100, 99], values.fetch(:duration_8818), "TimeSpan.FromMilliseconds rounds; CNA truncates"
    assert_equal [1, 0], values.fetch(:duration_46)
  end

  # `if (sizeInBytes < 0) throw new ArgumentException(InvalidBufferSize)` and
  # `if (ms < 0 || ms > int.MaxValue) throw new ArgumentOutOfRangeException("duration")`, with zero
  # answering zero on both sides before the format is consulted.
  def test_the_two_conversions_refuse_exactly_what_xna_refuses
    values = with_default_microphone do |m|
      [(begin; m.GetSampleDuration(-1); nil; rescue => e; e.class; end),
       (begin; m.GetSampleDuration(-2); nil; rescue => e; e.class; end),
       m.GetSampleDuration(0),
       (begin; m.GetSampleSizeInBytes(-0.001); nil; rescue => e; e.class; end),
       (begin; m.GetSampleSizeInBytes(Float::NAN); nil; rescue => e; e.class; end),
       (begin; m.GetSampleSizeInBytes(1.0e9); nil; rescue => e; e.class; end),
       m.GetSampleSizeInBytes(0.0),
       (begin; m.GetSampleDuration("4410"); nil; rescue => e; e.class; end)]
    end
    assert_equal [ArgumentError, ArgumentError], values[0..1]
    assert_equal 0.0, values[2]
    assert_equal [RangeError, RangeError, RangeError], values[3..5]
    assert_equal 0, values[6]
    assert_equal TypeError, values[7]
  end

  # ------------------------------------------------------------------------- BufferDuration

  # XNA: `100 <= ms <= 1000 && ms % 10 == 0`. CNA's own accepted domain, measured tick by tick, is
  # `[100, 990]` on the same 10 ms boundary — so the single value XNA admits that CNA refuses is
  # 1000 ms, and it is also the device's own initial value.
  def test_the_setter_validates_as_xna_does_and_the_getter_answers_the_request
    values = with_default_microphone do |m|
      initial = m.BufferDuration
      accepted = [0.1, 0.25, 0.99, 1.0].map do |seconds|
        m.BufferDuration = seconds
        [m.BufferDuration, m.__send__(:native_buffer_duration_ticks)]
      end
      refused = [0.099, 0.101, 1.001, 0.0, -0.1, 1.0005].map do |seconds|
        begin; m.BufferDuration = seconds; nil; rescue => e; e.class; end
      end
      [initial, accepted, refused, (begin; m.BufferDuration = "1"; nil; rescue => e; e.class; end)]
    end
    initial, accepted, refused, wrong_type = values

    # Not a snapshot: the device is process-wide and outlives a Game, so what the suite's own order
    # left behind decides the number. What is asserted is that whatever it reports is a duration the
    # setter's rule admits — which is exactly what the next test shows is not guaranteed upstream.
    assert_includes 0.1..1.0, initial
    assert_equal 0, (initial * 1000).round % 10
    assert_equal [[0.1, 1_000_000], [0.25, 2_500_000], [0.99, 9_900_000]], accepted[0..2],
                 "inside CNA's domain the property and the device agree exactly"
    assert_equal [1.0, 9_900_000], accepted[3],
                 "at 1000 ms the property answers the request and the device holds 990 ms"
    assert_equal [RangeError] * 6, refused
    assert_equal TypeError, wrong_type
  end

  # The upstream inconsistency, reproduced rather than described: one second is a duration
  # `cna_microphone_get_buffer_duration_ticks_at` reports — it is the value a device that nothing has
  # reconfigured answers, which `docs/microphone-evidence.md` §4 records from a cold probe — and it
  # is outside `cna_microphone_set_buffer_duration_ticks_at`'s accepted domain, so `set(get())` fails
  # at the C ABI. Classified UPSTREAM_CNA_CONTRACT there; it changes nothing here, because the
  # projection never forwards a value CNA refuses.
  #
  # The assertion is written on the **property**, not on a one-shot initial reading, because the
  # device is process-wide and the suite's own order would otherwise decide the answer.
  def test_one_second_is_reportable_but_not_settable_at_the_c_abi
    outcome = with_default_microphone do |m|
      library = CNA::Native.library
      host = CNA::Runtime::Context.native_host("microphone round-trip probe")
      attempt = lambda do |ticks|
        library.call("cna_microphone_set_buffer_duration_ticks_at", host.handle, 0, ticks)
        :accepted
      rescue CNA::Error => error
        error.class
      end
      # The round trip is measured on whatever the device currently holds, before anything here
      # changes it, so this reads the defect on a cold device without depending on being first.
      entry = m.__send__(:native_buffer_duration_ticks)
      [entry, attempt.call(entry), attempt.call(10_000_000), attempt.call(9_900_000),
       m.__send__(:native_buffer_duration_ticks)]
    end
    entry, entry_round_trip, one_second, ninety_nine_hundredths, after = outcome

    assert_equal(entry <= 9_900_000 ? :accepted : CNA::NativeError, entry_round_trip,
                 "set(get()) round-trips exactly when the getter's value is inside the setter's " \
                 "domain — and on a device nothing has reconfigured it is not")
    assert_equal CNA::NativeError, one_second, "one second — XNA's maximum — is refused"
    assert_equal :accepted, ninety_nine_hundredths, "990 ms, ten milliseconds less, is accepted"
    assert_equal 9_900_000, after
  end

  # --------------------------------------------------------------------------------- GetData

  # The validation ladder, in the IL's order, every stage reachable on a stopped device. The last
  # clause of stage 4 is the one that surprises: an aligned count that rounds to zero milliseconds
  # is refused, so below 46 bytes at 44 100 Hz nothing is accepted at all.
  def test_get_data_refuses_exactly_what_xna_refuses_and_answers_zero_when_stopped
    values = with_default_microphone do |m|
      buffer = +"\0".b * 4410
      err = ->(&block) { begin; block.call; nil; rescue => e; e.class; end }
      [err.call { m.GetData(nil) },
       err.call { m.GetData(+"") },
       err.call { m.GetData(+"\0".b * 3) },
       err.call { m.GetData(buffer, -2, 4) },
       err.call { m.GetData(buffer, 4410, 4) },
       err.call { m.GetData(buffer, 1, 4) },
       err.call { m.GetData(buffer, 0, 0) },
       err.call { m.GetData(buffer, 0, -2) },
       err.call { m.GetData(buffer, 0, 4412) },
       err.call { m.GetData(buffer, 0, 3) },
       err.call { m.GetData(buffer, 0, 44) },
       err.call { m.GetData((+"\0".b * 4410).freeze) },
       m.SampleRate == 44_100 ? m.GetData(buffer, 0, 46) : 0,
       m.GetData(buffer),
       m.GetData(buffer, 2, 4408),
       buffer.bytesize,
       m.State]
    end
    assert_equal [ArgumentError] * 12, values[0..11]
    assert_equal 0, values[12], "46 bytes is the first count whose duration does not round to zero"
    assert_equal [0, 0], values[13..14], "a stopped microphone answers zero rather than raising"
    assert_equal 4410, values[15], "and never resizes the caller's buffer"
    assert_equal A::MicrophoneState::Stopped, values[16]
  end

  # `GetData(byte[])` is `GetData(buffer, 0, buffer.Length)`, so the one-argument form must refuse a
  # buffer whose whole length rounds to zero milliseconds exactly as the three-argument form does.
  def test_the_one_argument_form_delegates_with_the_whole_buffer
    values = with_default_microphone do |m|
      next nil unless m.SampleRate == 44_100

      [(begin; m.GetData(+"\0".b * 44); nil; rescue => e; e.class; end),
       m.GetData(+"\0".b * 46)]
    end
    skip "this machine's default device does not run at 44100 Hz" if values.nil?

    assert_equal ArgumentError, values[0]
    assert_equal 0, values[1]
  end

  # ------------------------------------------------------------------------------- the event

  # The registration is real and owned; nothing in this binding raises `BufferReady` on a stopped
  # device, so what is asserted is the subscription and the dispatch mechanism, not a capture.
  def test_the_buffer_ready_subscription_is_a_real_owned_registration
    values = with_default_microphone do |m|
      seen = []
      m.BufferReady.add(->(sender, args) { seen << [sender.equal?(m), args] })
      m.BufferReady.__send__(:dispatch, m, CNA::Runtime::EventArgs::Empty)
      [m.instance_variable_get(:@registration) != 0,
       m.instance_variable_get(:@callback).nil?,
       seen]
    end
    assert_equal true, values[0], "cna_microphone_subscribe_buffer_ready_at answered a registration"
    assert_equal false, values[1], "and the closure is retained for its lifetime"
    assert_equal [[true, CNA::Runtime::EventArgs::Empty]], values[2]
  end

  # ------------------------------------------------------- and exactly what it does not project

  def test_no_capture_is_started_and_the_neighbouring_types_stay_absent
    %i[MicrophoneCollection AudioFormat AudioHelper MicrophoneUnsafeNativeMethods].each do |absent|
      refute A.const_defined?(absent, false), absent.to_s
    end
    # `Start`/`Stop` exist and are deliberately never called by this suite: exercising them would
    # record audio from the machine running the tests.
    assert A::Microphone.public_method_defined?(:Start)
    assert A::Microphone.public_method_defined?(:Stop)
    assert_equal 0, File.read(__FILE__).scan(/^\s*[^#\n]*\bm\.(?:Start|Stop)\b/).length,
                 "no test in this file starts a capture"
  end
end
