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

## Re-measured against CNA C ABI 0.21.0 — the cluster is reopened

The ABI migration re-ran this audit against the current artifact and against the retired one with
corrected prototypes. **Three of the four negative findings above do not survive re-measurement**,
and the fourth has a cause the audit missed.

### Two were defects in this tool, not upstream

- **`cna_sound_effect_get_sample_duration_ticks` is static.** Its canonical prototype is
  `(int32_t size_in_bytes, int32_t sample_rate, CNA_AudioChannels channels, int64_t* out_ticks)` and
  it takes **no handle**. The audit called it as `(handle, byte_count, out)`; the refusal it recorded
  was its own argument error. The **0.7.0 headers already declared the four-argument form**, so this
  is not a version difference.
- **`IsLooped` is documented "before playback has begun"**, answering `CNA_RESULT_INVALID_STATE`
  after. The audit set it **last**, after play and stop, and reported "refused in every state" from
  that single sample. The tool now measures both orderings: accepted and round-tripping before play,
  `CNA_RESULT_INVALID_STATE` after — which is the header's rule, not a defect.

### The control that proved "not the null backend" was inert

The audit concluded "**It is not the null backend**: the measurement is identical with `CNA_AUDIO`
unset and with `CNA_AUDIO=SDL`." **CNA never reads `CNA_AUDIO`.** The audio platform is a build-time
CMake selection (`cmake/AudioPlatformSelection.cmake`, `CNA_AUDIO_PLATFORM=SDL3|SDL2|NULL`), exactly
like the renderer platform, and the retired artifact was built `CNA_AUDIO_PLATFORM=NULL`. Setting an
unread variable to two values and getting the same answer twice is not a control. This is the same
class of mistake as the scanner anchored on one side of a token: a control has to be able to move the
thing it controls.

Re-measured against that same 0.7.0 artifact with the corrected prototypes,
`cna_audio_get_capabilities` answers `is_playback_available = 0`, and both duration routes report
`CNA_RESULT_SUCCESS` **without writing their output**. So the artifact really did have no audio — for
the reason the audit ruled out.

### What the current artifact answers

Measured on the CNA `0.21.0` `SDL3`-platform / `SDL3`-audio artifact, one full second of mono PCM16:

| measurement | 0.7.0 artifact | 0.21.0 artifact |
| --- | --- | --- |
| `is_playback_available` | 0 | 1 |
| `cna_sound_effect_get_duration_ticks` | success, output unwritten | 10000000 ticks |
| `cna_sound_effect_get_sample_duration_ticks` (static, 4-arg) | success, output unwritten | 10000000 ticks |
| `SoundState` through play/pause/resume/stop | `Stopped` throughout | `Stopped -> Playing -> Paused -> Playing -> Stopped` |
| `set_is_looped` before play | success, round-trips | success, round-trips |
| `set_is_looped` after play | — | `CNA_RESULT_INVALID_STATE`, as documented |
| volume / pitch / pan | round-trip | round-trip |

`SoundEffect` and `SoundEffectInstance` are therefore **reopened**. The `UPSTREAM_CNA_BLOCKED`
classification is retired; what remains unproven is audible output, which no automated measurement on
this host can establish either way.

The three types audited alongside them are re-examined separately: `Audio.Cue` still needs an XACT
engine opened from an `.xgs` settings file, `Graphics.EffectAnnotation` still needs a compiled effect
with parameters, and `Graphics.TextureCollection` is re-checked against the current 4054-route ABI
rather than against the retired one.
