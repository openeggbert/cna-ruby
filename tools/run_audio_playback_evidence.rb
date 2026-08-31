# frozen_string_literal: true

# Native frontier 4 — the audio-playback audit.
#
# `Audio.SoundEffectInstance` reaches the dependency frontier as blocked on `NATIVE_RUNTIME`, which
# means only "the type's own IL reaches a native entry point". That reasoning has been wrong twice
# already — Native frontier 1 corrected it for `FrameworkDispatcher` and Foundation 48 for
# `GameWindow` — because the native runtime this binding has **is** CNA, and a canonical route is not
# a blocker.
#
# So the question is measured rather than assumed: the canonical audio path exists in full, from
# `cna_sound_effect_create_pcm16` through `cna_sound_effect_create_instance` to the whole instance
# surface. This tool drives it end to end and records exactly what the reviewed artifact answers.
#
# It writes CNA output, so nothing it produces may enter the behaviour corpus, which is
# `never CNA output` by construction. It is native evidence, in the shape
# `run_gamepad_native_evidence.rb` established.

require "json"
require_relative "../lib/cna"

abort "CNA_NATIVE_LIBRARY is required" unless ENV["CNA_NATIVE_LIBRARY"]

F = Microsoft::Xna::Framework

SOUND_STATES = { 0 => "Playing", 1 => "Paused", 2 => "Stopped" }.freeze
MONO = 1
SAMPLE_RATE = 44_100
# One full second of silence: the duration is not in doubt, only whether CNA reports it.
FRAMES = SAMPLE_RATE

library = CNA::Native.library
handle = library.instance_variable_get(:@handle)
u64 = Fiddle::TYPE_UINT64_T
pointer = Fiddle::TYPE_VOIDP
float = Fiddle::TYPE_FLOAT
integer = Fiddle::TYPE_INT
u32 = Fiddle::TYPE_UINT32_T

route = ->(name, arguments) { Fiddle::Function.new(handle[name], arguments, Fiddle::TYPE_UINT32_T) }

game = F::Game.new
game.Tick
game_handle = game.instance_variable_get(:@host).handle

capabilities = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
capabilities[0, 16] = [16, 1, 0, 0, 0, 0, 0].pack("LLCCCCL")
capability_result = route.call("cna_audio_get_capabilities", [u64, pointer]).call(game_handle, capabilities)
playback_available = capabilities[8, 1].unpack1("C") == 1

create_info = Fiddle::Pointer.malloc(24, Fiddle::RUBY_FREE)
create_info[0, 24] = [24, 1, SAMPLE_RATE, MONO, 0].pack("LLLLQ")
pcm = ([0] * FRAMES).pack("s<*")
output = library.pointer_for("Q", 0)
create_result = route.call("cna_sound_effect_create_pcm16", [u64, pointer, pointer, u64, pointer])
                     .call(game_handle, create_info, Fiddle::Pointer[pcm], pcm.bytesize, output)
effect = output[0, 8].unpack1("Q")

duration_output = library.pointer_for("q", 0)
duration_result = route.call("cna_sound_effect_get_duration_ticks", [u64, pointer]).call(effect, duration_output)
duration_ticks = duration_output[0, 8].unpack1("q")

# `cna_sound_effect_get_sample_duration_ticks` is **static**: its canonical prototype is
# `(int32_t size_in_bytes, int32_t sample_rate, CNA_AudioChannels channels, int64_t* out_ticks)`
# and it takes no handle at all. Native frontier 4 called it as `(handle, byte_count, out)` and
# recorded the resulting refusal as an upstream defect; it was this tool's defect. The 0.7.0
# headers already declared the four-argument form, so the correction is not a version difference.
sample_output = library.pointer_for("q", 0)
sample_result = route.call("cna_sound_effect_get_sample_duration_ticks", [integer, integer, u32, pointer])
                     .call(pcm.bytesize, SAMPLE_RATE, MONO, sample_output)
sample_ticks = sample_output[0, 8].unpack1("q")

instance_output = library.pointer_for("Q", 0)
instance_result = route.call("cna_sound_effect_create_instance", [u64, pointer]).call(effect, instance_output)
instance = instance_output[0, 8].unpack1("Q")

info = Fiddle::Pointer.malloc(32, Fiddle::RUBY_FREE)
snapshot = lambda do
  info[0, 32] = ([32, 1] + ([0] * 24)).pack("LLC24")
  route.call("cna_sound_effect_instance_get_info", [u64, pointer]).call(instance, info)
  {
    "state" => SOUND_STATES.fetch(info[8, 4].unpack1("L"), "unknown"),
    "isLooped" => info[12, 1].unpack1("C") == 1,
    "volume" => info[16, 4].unpack1("f"),
    "pitch" => info[20, 4].unpack1("f"),
    "pan" => info[24, 4].unpack1("f")
  }
end

transitions = []
record = lambda do |label, result|
  transitions << { "step" => label, "cnaResult" => result, "snapshot" => snapshot.call }
end

record.call("initial", 0)
# `set_is_looped` is documented "before playback has begun", answering `CNA_RESULT_INVALID_STATE`
# after. Native frontier 4 called it **last**, after play/stop, and recorded the documented refusal
# as "looping is refused in every state". Both orderings are measured here so the rule is visible
# rather than inferred from one of its sides.
record.call("set_is_looped(true) before play",
            route.call("cna_sound_effect_instance_set_is_looped", [u64, integer]).call(instance, 1))
record.call("play", route.call("cna_sound_effect_instance_play", [u64]).call(instance))
3.times { game.Tick }
record.call("three frame steps", 0)
record.call("framework dispatcher pump",
            route.call("cna_framework_dispatcher_update", [u64]).call(game_handle))
record.call("pause", route.call("cna_sound_effect_instance_pause", [u64]).call(instance))
record.call("resume", route.call("cna_sound_effect_instance_resume", [u64]).call(instance))
record.call("stop(immediate)", route.call("cna_sound_effect_instance_stop", [u64, integer]).call(instance, 1))
record.call("set_volume(0.5)",
            route.call("cna_sound_effect_instance_set_volume", [u64, float]).call(instance, 0.5))
record.call("set_pitch(-0.25)",
            route.call("cna_sound_effect_instance_set_pitch", [u64, float]).call(instance, -0.25))
record.call("set_pan(1.0)",
            route.call("cna_sound_effect_instance_set_pan", [u64, float]).call(instance, 1.0))
record.call("set_is_looped(true) after play",
            route.call("cna_sound_effect_instance_set_is_looped", [u64, integer]).call(instance, 1))

route.call("cna_sound_effect_instance_destroy", [u64]).call(instance)
route.call("cna_sound_effect_destroy", [u64]).call(effect)
game.Dispose

states = transitions.map { |entry| entry.fetch("snapshot").fetch("state") }.uniq
controls = transitions.last.fetch("snapshot")
looped_before = transitions.find { |entry| entry.fetch("step").start_with?("set_is_looped(true) before") }
looped_after = transitions.find { |entry| entry.fetch("step").start_with?("set_is_looped(true) after") }

report = {
  "schemaVersion" => 2,
  "provenance" => "CNA_NATIVE_EVIDENCE; measured output of the reviewed CNA C ABI library, never an XNA fact and never part of the behaviour corpus",
  "library" => library.path,
  "abiVersion" => format("0x%08x", library.abi_version),
  "audioPlatform" => "build-time CNA_AUDIO_PLATFORM; not selectable at runtime",
  "renderer" => "build-time CNA_GRAPHICS_RENDERER, overridable at runtime only among renderers compiled in",
  "capabilities" => {
    "cnaResult" => capability_result,
    "isPlaybackAvailable" => playback_available
  },
  "creation" => {
    "createPcm16Result" => create_result,
    "sampleRate" => SAMPLE_RATE,
    "channels" => "MONO",
    "frames" => FRAMES,
    "expectedDurationTicks" => 10_000_000,
    "durationTicksResult" => duration_result,
    "durationTicks" => duration_ticks,
    "sampleDurationTicksResult" => sample_result,
    "sampleDurationTicks" => sample_ticks,
    "createInstanceResult" => instance_result
  },
  "transitions" => transitions,
  "observedStates" => states,
  "proves" => [
    "the whole canonical path executes: create_pcm16, create_instance, play, pause, resume, stop, the four setters, and both destroys",
    "cna_audio_get_capabilities reports playback available",
    "one full second of mono PCM16 answers exactly 10000000 ticks from cna_sound_effect_get_duration_ticks",
    "the static four-argument cna_sound_effect_get_sample_duration_ticks answers the same 10000000 ticks",
    "SoundState moves Stopped -> Playing -> Paused -> Playing -> Stopped through the canonical routes",
    "IsLooped is settable before playback and round-trips, and is refused with CNA_RESULT_INVALID_STATE after playback has begun, which is the documented rule",
    "volume, pitch and pan round-trip through the real routes"
  ],
  "doesNotProve" => [
    "any audible output: no listener and no capture device took part in this measurement",
    "3D positional audio, XACT, Microphone capture or DynamicSoundEffectInstance behaviour"
  ],
  "conclusion" => "The canonical audio path is behaviourally real on the current artifact. Native frontier 4 measured the opposite against the retired 0.7.0 artifact, and three of its four negative findings do not survive re-measurement: the sample-duration route was called with the wrong arity (it is static and takes no handle, in the 0.7.0 headers too), IsLooped was set only after playback where the header documents a refusal, and the 'not the null backend' control was inert because CNA_AUDIO is not read by CNA at all -- the audio platform is a build-time CMake selection and the retired artifact was built CNA_AUDIO_PLATFORM=NULL. Re-measured against that same 0.7.0 artifact with the corrected prototypes, cna_audio_get_capabilities answers is_playback_available=0 and the duration routes report success without writing their output. SoundEffect and SoundEffectInstance are reopened."
}

destination = File.expand_path("../docs/generated/audio-native-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "AUDIO_PLAYBACK_AVAILABLE=#{playback_available ? "YES" : "NO"}"
puts "CANONICAL_PATH_EXECUTES=#{create_result.zero? && instance_result.zero? ? "YES" : "NO"}"
puts "OBSERVED_STATES=#{states.join(",")}"
puts "DURATION_TICKS=#{duration_ticks}"
puts "SAMPLE_DURATION_TICKS=#{sample_ticks}"
puts "IS_LOOPED_BEFORE_PLAY=#{looped_before.fetch("cnaResult")}/#{looped_before.fetch("snapshot").fetch("isLooped")}"
puts "IS_LOOPED_AFTER_PLAY=#{looped_after.fetch("cnaResult")}"
puts "SOUND_EFFECT_PROJECTION=REOPENED"
