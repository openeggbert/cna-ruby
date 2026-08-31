# Native frontier 4 — the audio-playback audit

Full measurement in `docs/generated/audio-native-report.json`, produced by
`tools/run_audio_playback_evidence.rb` against the reviewed CNA C ABI 0.7.0 library.

**No type is completed by this milestone.** It converts a guessed blocker into a measured one, which
is the shape `docs/graphics-adapter-audit-evidence.md` established and the reason both are worth
committing: the next session does not have to re-derive it.

## The question

`Audio.SoundEffectInstance` reaches the dependency frontier as blocked on `NATIVE_RUNTIME`, which
means only "the type's own IL reaches a native entry point". That reasoning has now been wrong twice:
Native frontier 1 corrected it for `FrameworkDispatcher` and Foundation 48 for `GameWindow`, both
times because **the native runtime this binding has is CNA**, and a canonical route is not a blocker.

The canonical audio path is not partial. `audio.h` exposes 74 routes, and the whole chain exists:

```
cna_sound_effect_create_pcm16  ->  cna_sound_effect_create_instance
    ->  play / pause / resume / stop / get_info
    ->  set_volume / set_pitch / set_pan / set_is_looped
    ->  instance_destroy / destroy
```

So the deferral had to be tested rather than assumed.

## What the artifact answers

Driven end to end with one full second of mono PCM16 at 44 100 Hz:

| step | CNA result | `State` |
| --- | --- | --- |
| initial | — | `Stopped` |
| `play` | success | `Stopped` |
| three frame steps | — | `Stopped` |
| `cna_framework_dispatcher_update` | success | `Stopped` |
| `pause` | success | `Stopped` |
| `resume` | success | `Stopped` |
| `stop(immediate)` | success | `Stopped` |

- **`cna_audio_get_capabilities` reports `is_playback_available = true`.**
- **`SoundState` never leaves `Stopped`** — through play, three frame steps, an explicit dispatcher
  pump, pause, resume and stop. Every one of those calls reports `CNA_RESULT_SUCCESS`.
- **Duration is zero.** One full second of PCM answers 0 ticks, and
  `cna_sound_effect_get_sample_duration_ticks` *fails* and answers 0.
- **Looping cannot be enabled.** `cna_sound_effect_instance_set_is_looped` is refused with
  `CNA_RESULT_INVALID_STATE` in every state, including a freshly created one and a stopped one.
- Volume, pitch and pan **do** round-trip through the real routes.

## It is not the null backend

The obvious explanation would be `CNA_AUDIO=NULL`, which the qualified environment sets. It is not:
the measurement is byte-identical with `CNA_AUDIO` unset and with `CNA_AUDIO=SDL`. The behaviour
belongs to the reviewed artifact in every configuration, and the capability probe reporting playback
*available* while nothing plays is part of the finding rather than a contradiction of it.

## The conclusion, and why the types stay deferred

The canonical routes exist, are reachable and report success, but the reviewed artifact does not
implement the observable behaviour they document. Projecting `SoundEffect` and
`SoundEffectInstance` on top would give:

- a `State` property that is a constant masquerading as a query,
- a `Duration` that is always zero,
- a `Play()` that reports success and does nothing,
- an `IsLooped` setter that always raises.

Every one of those is on this project's standing list of what a completion may never be: an
unconditional capability claim, a swallowed unavailable runtime, a no-op that pretends to act. **A
smaller truthful surface is preferable**, so both types stay deferred — and the blocker is now
`UPSTREAM_CNA_BLOCKED`, which is a different and much more precise statement than `NATIVE_RUNTIME`.

## The rest of the cluster, audited with it

- **`Audio.Cue`** needs an XACT `AudioEngine`, and `cna_audio_engine_create` opens one **from a
  settings file** — an `.xgs` asset this binding does not have — after which a `SoundBank` must be
  loaded before `cna_sound_bank_get_cue` can produce anything. Two missing XNA types and a missing
  asset stand between the frontier and a `Cue`, which is a producer absence rather than a backend
  one, and a different reason from the above.
- **`Graphics.EffectAnnotation`** comes from `EffectParameter.Annotations`. The ABI can build an
  effect — `cna_effect_create_empty` is documented as "the minimal concrete adapter for the native
  abstract Effect base class" — but an empty effect has no parameters and therefore no annotations,
  and `cna_effect_create_compiled` needs shader bytecode this binding has none of. Producer absence
  again.
- **`Graphics.TextureCollection`** has **no CNA route at all**: no header in the reviewed 59 mentions
  it. Genuinely absent, which is the one case where `NATIVE_RUNTIME` was the right word.

## Structural movement

None. `TARGET_TYPES` 146, `COMPLETE_TYPES` 140, `MISSING_TYPES` 111, `MISSING_MEMBER` 110,
`TOTAL_DIAGNOSTICS` 264, ABI 68 / 219 / 300 / 300 / 3 / 66 and 520 behaviour observations are all
unchanged — deliberately. What moved is the accuracy of four frontier justifications and one new
capability row.

Nothing measured here entered the behaviour corpus, and nothing could: that corpus is
`never CNA output` by construction, and every number above is CNA output. It lives in
`docs/generated/audio-native-report.json` under `CNA_NATIVE_EVIDENCE`, the same provenance the
GamePad native report carries.
