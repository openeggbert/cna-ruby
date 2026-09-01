# `Audio.SoundEffect` and `Audio.SoundEffectInstance`

The cluster Native frontier 4 recorded as `UPSTREAM_CNA_BLOCKED`, reopened by the CNA C ABI
migration's re-measurement and built here. Two types, 33 identities, 35 bound routes.

The re-measurement is in `docs/audio-playback-audit-evidence.md`; the short version is that the
retired artifact had been built `CNA_AUDIO_PLATFORM=NULL`, a build-time CMake choice, and the
audit's control variable `CNA_AUDIO` is read by nothing at all. Nothing was built on the reopened
capability until that had been established.

## What the IL settles that no signature does

Every bound below is a literal in `Microsoft.Xna.Framework.dll`, not a documented range.

| member | rule | IL |
| --- | --- | --- |
| `SoundEffect..ctor` | `sampleRate` in `[8000, 48000]` | `ldc.i4 0x1f40` / `ldc.i4 0xbb80` |
| `SoundEffect..ctor` | `channels` in `[1, 2]` | `ldc.i4.1` / `ldc.i4.2` |
| `SoundEffect..ctor` | null or empty buffer | `ArgumentException(InvalidAudioBuffer)` |
| `SoundEffect.FromStream` | null stream | `ArgumentNullException("stream")` |
| `MasterVolume` | `[0, 1]` | `blt.un` / `bgt.un` |
| `DopplerScale` | `>= 0` | `blt.un` |
| `DistanceScale` | `>= 0`, then clamped up to `Single.Epsilon` | `bge.un`, then `ble` |
| `SpeedOfSound` | `> 0` | `ble.un` |
| `Instance.Volume` | `[0, 1]` | `blt.un` / `bgt.un` |
| `Instance.Pitch` | `[-1, 1]` | `blt.un` / `bgt.un` |
| `Instance.Pan` | `[-1, 1]`, and refused once 3D | `blt.un` / `bgt.un` |
| `Instance.IsLooped` | refused once a packet has been submitted | `isPacketSubmitted` |

**Every one of those comparisons is unordered.** `blt.un`/`bgt.un`/`ble.un` are true for NaN, so a
NaN argument takes the throw branch. `bge.un` is true for NaN too — which means it takes the branch
*past* the throw. So `DopplerScale = NaN` raises and `DistanceScale = NaN` does **not**, and that
asymmetry is the IL's rather than this projection's. Both are asserted.

### Three rules a summary would lose

**`set_Pan` clears the 3D flag.**

```csharp
if (!isPacketSubmitted) is3d = false;
if (is3d) throw new InvalidOperationException(InvalidPanCall);
```

So `Apply3D` **before the first play** does not lock `Pan` out, and after it does. A reimplementation
that simply latched `is3d` on `Apply3D` would be wrong in the common case of positioning a sound
before starting it.

**`UnsafeApply3D` is the mirror image.**

```csharp
if (!isPacketSubmitted) is3d = true;
if (!is3d) throw new InvalidOperationException(InvalidApply3DCall);
```

So a first 3D call is allowed before playback and refused after; a *second* one on an instance
already positioned in 3D is allowed at any time. CNA enforces the identical rule natively —
"Apply3D cannot be called on a playing instance that is not using 3D audio" — which is how the
projection's first draft was caught: the test asserted the wrong thing and CNA disagreed with it,
correctly.

**`SoundEffectInstance.Dispose(bool)` has no `if (!disposing) return` guard**, unlike
`GameComponent`'s. It marks disposed, tells its `SoundEffect` and deallocates the voice whichever way
it is called, so the CLR finalizer path really would release the voice.

## Where the validation lives, and why it is not a preference

CNA's three instance setters disagree with each other and with XNA — measured:

| | XNA | CNA |
| --- | --- | --- |
| `set_volume(2.0)` | `ArgumentOutOfRangeException` | accepted, unclamped |
| `set_pitch(3.0)` | `ArgumentOutOfRangeException` | accepted, clamped to `1.0` |
| `set_pan(5.0)` | `ArgumentOutOfRangeException` | `CNA_RESULT_INVALID_ARGUMENT` |

Validating managed-side is the only arrangement under which the three behave alike, which is what
XNA's contract says they do. It is also what keeps CNA from ever seeing an out-of-range value.

The same reasoning applies in the other direction to `IsLooped` and `Apply3D`: CNA enforces both
rules natively and correctly, and the managed guard is kept anyway so the refusal carries XNA's
identity — `InvalidOperationException`, projected as `RuntimeError` — rather than a translated
`CNA::NativeError`.

## Ownership

`SoundEffect` is OWNED and parented to the Game; an instance is OWNED and parented to its effect,
and CNA enforces the order. Measured: destroying an effect that still has a live instance answers
`CNA_RESULT_INVALID_STATE`, which surfaces as `CNA::NativeError` and is asserted rather than
papered over. `SoundEffect.Dispose` after the instance is gone succeeds.

## Recorded deviations

- **The four global settings are game-scoped**, where XNA's are CLR statics: every canonical CNA
  route takes a game handle. This is the same asymmetry `FrameworkDispatcher` records, and it is why
  those four Ruby properties need a live Game on its owner thread where XNA's need nothing.
- **A `SoundEffect` needs a live CNA Game to exist at all**, because
  `cna_sound_effect_create_pcm16` is game-parented and XNA's constructor is not. The two static
  computations, `GetSampleDuration` and `GetSampleSizeInBytes`, are the exception: they take no
  handle in CNA either, so they are the only two members that work with no Game.
- **`Dispose` and `Dispose(Boolean)` are one Ruby method** with a default argument, the rule `Game`,
  `GameComponent` and `ContentManager` already follow. The protected overload is publicly reachable
  here, which it is not in the CLR.
- **The two constructor overloads are one Ruby method.** The seven-argument loop-region form differs
  from the three-argument one by four optional trailing parameters, so the collapsed overload rule
  applies unchanged.
- **`State` is CNA's, not XACT's.** XNA maps an XACT `VoiceState` bitfield onto `SoundState`;
  CNA answers `SoundState` directly. Re-deriving XNA's mapping from CNA's answer would invent a
  bitfield that does not exist here, and CNA is the audio runtime this binding has.

## What is measured, and what is not

Measured: duration from real PCM (22 050 mono frames at 44 100 Hz answer exactly half a second, where
the retired artifact answered zero), the full state machine, every range and NaN refusal, the
`IsLooped` and `Apply3D` state rules, `Stop(false)` leaving a playing instance playing where
`Stop(true)` stops it, both static computations, all four global settings, the name round-trip,
fire-and-forget `Play`, and the parent/child destruction order.

**Not measured, and not claimed: audible output.** No listener and no capture device took part in
any of this, and no automated measurement on this host can establish it either way. The capability
row says so.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_TYPES` | 151 | 153 |
| `TARGET_MEMBERS` | 1849 | 1882 |
| `COMPLETE_TYPES` | 146 | 148 |
| `PARTIAL_TYPES` | 5 | 5 |
| `MISSING_TYPES` | 106 | 104 |
| `MISSING_MEMBER` | 109 | 109 |
| `TOTAL_DIAGNOSTICS` | 258 | 256 |
| `ALLOWLIST_ENTRIES` | 0 | 0 |
| bound native functions | 80 | 115 |
| measured C layouts | 19 | 23 |

`DynamicSoundEffectInstance` arrived on the frontier as `SoundEffectInstance` left it — it derives
from it — so `dependencyCompleteCandidates` stayed at 12. Completing a type uncovers what was
behind it, which is the third time this session that has happened.
