# Audio.WaveBank, Audio.SoundBank and Audio.Cue — evidence

Behaviour authority: the pinned `Microsoft.Xna.Framework.Xact.dll` (SHA-256 `a14d5364…`). Fixtures
are the XNA Spacewar sample's real XACT project, referenced by path through `CNA_TEST_XACT_DIR` and
never copied into this repository. Nothing measured from CNA is in the behaviour corpus.

Completing these three completes the **whole XNA 4.0 `Audio` namespace** and takes the last audio
type off the dependency frontier.

## 1. Three magic numbers, all checked in managed code

Each container validates its own file before XACT is asked for anything, and each refuses a file of
four bytes or fewer before the comparison:

| type | IL | bytes |
| --- | --- | --- |
| `AudioEngine` | constructor | `X G S F` |
| `WaveBank` | `CheckWaveBankHeader` | `W B N D` — `ldc.i4.s 87, 66, 78, 68` |
| `SoundBank` | constructor | `S D B K` — `ldc.i4.s 83, 68, 66, 75` |

The fixtures really carry those bytes, which the test asserts rather than assumes, and handing any
of the three the wrong one of the three files raises `ArgumentError` without the engine being asked.

The shared helpers live in `CNA::Runtime::Audio`, not beside the projected types. A support module
in the XNA namespace would be an identity XNA does not declare — which is exactly what the API
verifier reports as `INTERNAL_TYPE_LEAK`, and did, on the first draft of this milestone.

## 2. One native failure, two exception types

`SoundBank.GetCue` and `SoundBank.PlayCue` reach the same XACT error for an unknown cue name and
report it differently:

    GetCue :  E_INVALIDARG  ->  ArgumentException(string.Format(CueNotFound, name))
    PlayCue:  anything but the cue-instance limit -> InvalidOperationException(CueNotFound)

So the same mistake is an **argument** problem when you ask for a cue and an **operation** problem
when you ask for one to be played. Both are the IL's and both are reproduced.

## 3. The cue state machine

XNA's seven status properties are one XACT bitmask, each getter calling `GetStatus` afresh:

    IsCreated 1   IsPreparing 2   IsPrepared 4   IsPlaying 8
    IsStopping 0x10   IsStopped 0x20   IsPaused 0x40

CNA answers all seven at once in `CNA_CueInfo`, whose 16-byte layout the ABI gate now measures, and
each projected property reads it once — the same number of native reads XNA makes. Measured: a cue
that has been asked for and not played is `IsPrepared` and nothing else; after `Play` and one
`AudioEngine.Update` it is `IsPlaying`.

`Apply3D` carries the guard `SoundEffectInstance.Apply3D` carries:

    if (!applied3D && played) throw new InvalidOperationException(Apply3DBeforePlay);

so the **first** apply must precede the first play and every later one is free. Both directions are
measured: apply → play → apply succeeds; play → apply on a fresh cue is refused.

## 4. Destruction order is CNA's requirement, not XNA's

    cna_sound_bank_destroy failed with CNA result 3:
    All C Cue children must be destroyed before their SoundBank.

XNA's `SoundBank.Dispose` releases the bank and leaves a live `Cue` to the CLR; CNA refuses. The
same holds one level up — the engine will not be destroyed while a bank of its own is alive.

**DEVIATION, recorded**: a sound bank disposes the cues it produced before releasing itself, and an
engine disposes its banks before releasing itself. That is the enforced parent/child destruction the
`SoundEffect` cluster already records, and it is CNA's requirement rather than a rule this binding
invented. The cascade is asserted end to end, including that a cue which disposes itself first
leaves its bank's list, and that the bank's own `Disposing` fires before the cues it then disposes.

## 5. The one thing XNA tolerates that cannot be told apart here

`Cue.Play` compares the native result with `0x8ac70008` — XACT's cue-instance limit — and only calls
`ThrowExceptionFromResult` when it differs. So that one failure is swallowed and every other raises.

`CNA_Result` has no code for the cue-instance limit, so the tolerated failure is indistinguishable
from a real one. **Nothing is swallowed on a guess**: every native failure raises. A first draft
matched on the error message text, which would have been guessing, and it was removed.

The exemption was also measured **unreachable** on this artifact: thirty consecutive plays of one
cue all succeeded. So no behaviour this artifact can produce is lost by not implementing it, and the
test asserts that measurement rather than asserting the exemption exists.

## 6. What is not claimed

Nothing about what is audible. The mixer really opens — `[AudioMixer] Requested format=0x0
channels=2 freq=44100; application format=0x8010 channels=2 freq=44100` — and the cue's own state
machine really moves, and that is the whole of the claim.
