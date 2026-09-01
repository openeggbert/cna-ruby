# Audio.Microphone — evidence

Behaviour authority: the pinned `Microsoft.Xna.Framework.dll` (SHA-256 `38e7093f…`), whose
`Audio.Microphone`, `Audio.AudioFormat`, `Audio.AudioHelper` and `Audio.MicrophoneCollection` carry
the whole contract, together with `System.TimeSpan` from the pinned Microsoft .NET Framework 4.0
`mscorlib` (SHA-256 `5634668d…`). Everything measured from CNA is here or in
`docs/generated/*-native-report.json`; none of it is in the behaviour corpus.

## 1. The deferral, and why it was wrong for the sixth time

Native frontier 4 recorded `Audio.Microphone` as `NATIVE_RUNTIME`, later joined by a
`System.Byte[]` BCL blocker that the `ContentManager` milestone decided (a CLR `byte[]` projects to
a binary Ruby `String`). Measuring the host:

    microphone_get_count      -> SUCCESS count=3
    default_index             -> SUCCESS index=0 available=1
      [0] name=Default Device                                   sample_rate 44100
      [1] name=Ryzen HD Audio Controller Stereo Microphone      sample_rate 44100
      [2] name=Ryzen HD Audio Controller Digital Microphone     sample_rate 44100
    out-of-range index        -> INVALID_ARGUMENT
    check_all_buffers         -> SUCCESS

Three real devices, named from the hardware. The ABI gate's cross-version check then reports
`CROSS_VERSION_MISMATCHES=0` and `MISSING_HEADER_SYMBOLS=0` over the sixteen `cna_microphone_*`
routes, so the **retired 0.7.0 headers declare them identically** — no version difference explains
the deferral either. It was about neither the ABI nor the host.

## 2. Identity: CNA has no microphone handle

XNA wraps a `uint32` from `CreateMicrophone(index, out handle)` and frees it in `Finalize`. Every
CNA route is `(CNA_Handle game, uint64_t index, …)`; `audio.h` says the runtime owns the device. So
the projection carries a `BORROWED_EXTERNAL_SCALAR` index, destroys nothing, and projects `Finalize`
as the member that does nothing — registering no Ruby finalizer, as everywhere in this binding.

`MicrophoneCollection` is a CLR static built in a static constructor; `get_All` re-enumerates and
answers the same `ReadOnlyCollection` wrapping a `List` that only grows, throwing
`InvalidOperationException` if the device count ever **falls**. `get_Default` selects the first
device whose native `IsDefault` is positive and falls back to index 0, so it is null only on a
machine with no capture device. All of that is reproduced; the one **deviation** is that CNA's
routes are game-scoped, so `All` and `Default` need a live `Game` where XNA's need nothing. That is
the asymmetry `FrameworkDispatcher` and the `SoundEffect` statics already record.

## 3. The arithmetic is managed, because CNA's disagrees with XNA

`Microphone`'s format is fixed by its constructor: `AudioFormat.Create(GetSampleRate(), 1, 16)`, and
`AudioHelper.MakeFormat` writes `BlockAlign = channels * bits / 8`. Mono PCM16, block align 2, so
the IL's `samples + samples % Channels` is always `samples`.

    AudioFormat.SizeFromDuration(d) = (int)(d.TotalMilliseconds * ((float)SampleRate / 1000f))
                                      then (samples + samples % Channels) * BlockAlign
    AudioFormat.DurationFromSize(n) = TimeSpan.FromMilliseconds(
                                        (float)(n / BlockAlign) * 1000f / (float)SampleRate)

and the pinned mscorlib's `TimeSpan.Interval(value, 1)` is
`(long)(value + (value >= 0 ? 0.5 : -0.5)) * 10000` — **rounded to whole milliseconds**.

Measured against CNA's own two routes on the default device at 44 100 Hz:

| call                          | XNA (projected) | CNA route |
|-------------------------------|-----------------|-----------|
| `GetSampleSizeInBytes(100 ms)`| 8818            | 8820      |
| `GetSampleSizeInBytes(50 ms)` | 4408            | 4410      |
| `GetSampleSizeInBytes(1 s)`   | 88198           | 88200     |
| `GetSampleDuration(46)`       | 1 ms            | 0 ms      |
| `GetSampleDuration(8818)`     | 100 ms          | 99 ms     |
| `GetSampleDuration(8820)`     | 100 ms          | 100 ms    |

XNA truncates in binary32 — `100 × 44.099998474…` is `4409.9998…`, so 4409 samples, not 4410 — and
rounds the other direction; CNA computes exactly and truncates. They are not edge cases: 100 ms is
the ordinary value. So the projection does the arithmetic itself, in the IL's order, and the two CNA
routes stay bound and reachable through the private `native_sample_size_in_bytes` and
`native_sample_duration_ticks` so a test asserts the divergence rather than this file describing it.

`cna_microphone_get_sample_size_in_bytes_at` also answers **43** for 4988 ticks — a size that is not
a multiple of the block align, and so not a size `get_data` can use. Recorded, not relied upon.

## 4. BufferDuration: a domain CNA narrows by one point

XNA: `100 ≤ TotalMilliseconds ≤ 1000` and `TotalMilliseconds % 10 == 0`, else
`ArgumentOutOfRangeException("value", InvalidMicrophoneBufferDuration)`. The three literals are
`ldc.r8 100`, `ldc.r8 1000` and `ldc.r8 10`.

CNA's domain was measured, not read: every whole millisecond in `[95, 1005]`, then every tick in
`[1 000 000, 1 000 020]`, then a 0.05 ms grid across `[100, 102]` ms. The predicate is

    ms = ticks / 10000            (integer division)
    accepted iff ms % 10 == 0 and 100 <= ms <= 990

So CNA accepts `1 005 000` ticks (100.5 ms, which truncates into the 100 ms bucket) and refuses
`1 010 000` (101 ms). Its maximum is **990 ms**, ten milliseconds below XNA's.

The single value XNA admits and CNA refuses is exactly 1000 ms — and that is also the value
`cna_microphone_get_buffer_duration_ticks_at` reports for a device nothing has reconfigured
(`10 000 000` ticks). **`set(get())` therefore fails at the C ABI**:

    initial read-back 10000000
    set 10000000 -> INVALID_ARGUMENT
    set  9900000 -> SUCCESS

Classified `UPSTREAM_CNA_CONTRACT`: a getter reporting a value outside its own setter's domain. It
is reproduced by `test_one_second_is_reportable_but_not_settable_at_the_c_abi`, written as a
property — the round trip succeeds exactly when the reported value is `≤ 9 900 000` — so it reads
the defect on a cold device without depending on test order.

**DEVIATION**: the projection validates managed-side exactly as XNA does, so CNA never sees a value
outside its own domain; at the one divergent point it sends 990 ms and caches the requested 1000 ms.
XNA's getter is a cached field rather than a device read, so the property answers what XNA's would.
The device holding ten milliseconds less is visible through `native_buffer_duration_ticks` and is
asserted.

## 5. IsHeadset is a constant

`isHeadset` has exactly one writer in the whole assembly:

    IL_004a:  ldarg.0
    IL_004b:  ldc.i4.1
    IL_004c:  stfld      bool Microsoft.Xna.Framework.Audio.Microphone::isHeadset

XNA 4.0 on Windows answers `true` for every device. CNA answers the platform truth, and for all
three devices on this machine that is `false`.

**DEVIATION**: the projection answers XNA's constant, because a consumer's `if (mic.IsHeadset)` has
to branch the way it branches under XNA — that is the whole point of the binding. The device's own
answer stays reachable through the private `native_is_headset`, and the test asserts both values, so
the disagreement is measured rather than hidden.

## 6. GetData, and the clause that surprises

The validation ladder, in the IL's order, each stage naming XNA's own resource string:

1. buffer null, empty, or `length % BlockAlign != 0` → `InvalidAudioBuffer`
2. `offset < 0`, `offset >= length`, or `offset % BlockAlign != 0` → `InvalidAudioBufferOffset`
3. `offset + count` overflowing int32 (`add.ovf` inside a `try`) → `InvalidOffsetCountLength`
4. `count <= 0`, `end <= 0`, `end > length`, `count % BlockAlign != 0`, **or
   `DurationFromSize(count) == TimeSpan.Zero`** → `InvalidOffsetCountLength`

Stage 4's last clause is a consequence of §3: after `TimeSpan.FromMilliseconds` rounds, a count
whose duration is below half a millisecond is zero. At 44 100 Hz that refuses every aligned count
below **46 bytes** — `44` bytes is 22 samples, 0.4988 ms, which rounds to 0. Measured and asserted.

`if (State != Started) return 0;` is the last step before the native read, so a stopped microphone
answers zero rather than raising.

The Ruby buffer rule is the one `CNA::Runtime::Stream` set: a CLR `byte[]` is never frozen and
cannot be resized, so a frozen String is refused and the buffer is never grown.

## 7. What is deliberately not measured

`Start`, `Stop` and a `GetData` that actually reads are implemented and **left unexercised by the
suite**, because running them would open the machine's microphone and record audio from whoever is
running the tests. That is a decision, not a limitation, and it costs almost nothing: every managed
behaviour the type declares is reachable on a stopped device, because the validation ladder above
ends in the `State != Started` early return. What is not covered is the native read itself and the
Started/Stopped transition, which are one `cna_microphone_start_at` / `cna_microphone_stop_at` call
each with no managed state of their own.

`BufferReady` is subscribed for real — `cna_microphone_subscribe_buffer_ready_at` answers an owned
registration, released with `cna_audio_unsubscribe_ext` — and the dispatch path is asserted directly.
Nothing raises it on a stopped device, and no firing is claimed.

## 8. Infrastructure this forced

`Microphone::Name` is a **public `initonly` field**, and the reference contract records a field's
type, staticness and constant value but not its readonlyness — so the verifier required a writer for
it. Scanning every `.field` declaration in the pinned assemblies against the reference's own
inventory: of **105** non-constant instance fields, exactly **one** is `initonly`, and it is this
one. `CNAApiCompat::READONLY_INSTANCE_FIELDS` records it with that measurement, and
`test_api_verifier.rb` carries the controls proving the register excuses that field and nothing else
— not by prefix, not by suffix, not for a different member of the same type.

## 9. A measurement defect, again on the same side

Four earlier occurrences of reading an out-parameter unsequenced against the call that writes it are
recorded in `docs/content-manager-evidence.md` §7. It happened again here:

    printf("sample_rate %s %d\n", R(cna_microphone_get_sample_rate_at(g,0,&rate)), rate);

which reported `sample_rate SUCCESS 0` for a device that really answers 44100, and equally
fabricated a `state` of 99 and a `bytes` of 999. Every measurement in this file was re-taken with
each call sequenced into its own statement. The rule stands: a measurement that contradicts a
documented contract is a reason to doubt the measurement first.
