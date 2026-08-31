# Continuation Evidence

## Exact current boundary

**Session start HEAD = `920b0db8`**, which was also `origin/develop`. That baseline carries
Foundations 16 to 43 and Native frontiers 1 to 3.

The sequence this session added on top of it is **Foundations 44 to 52 plus Native frontier 4**.
Resolve where it currently sits with

```sh
git rev-parse HEAD
git rev-parse origin/develop
git log --oneline origin/develop..HEAD    # empty once the sequence is published
```

rather than from a count written down here. A handoff outlives the push that follows it, so this
states the **session-start baseline**, which never moves, and lets git answer everything that does.

| Milestone | What it added | Types | Identities |
| --- | --- | --- | --- |
| 16–43, NF1–NF3 | see the published history | 136 | — |
| 44 | `Game.Tick` | 0 | 1 |
| 45 | `Game.IsActive` | 0 | 1 |
| 46 | `Dictionary`2` + `LaunchParameters` | 1 | 2 |
| 47 | `Game`'s protected remainder | 0 | 3 |
| 48 | `GameWindow` + `Game.Window` | 1 | 21 |
| 49 | the serialization carrier + two exception types | 2 | 8 |
| NF4 | the audio-playback audit | **0** | **0** |
| 50 | `Audio.RendererDetail` | 1 | 7 |
| 51 | `Media.VisualizationData` | 1 | 3 |
| 52 | `Media.Video` | 1 | 5 |

## Measured state

Strict target **149 types / 1837 member identities**: **143 complete**, six partial native/runtime
types, 108 missing, **261 deferred diagnostics**. `MISSING_MEMBER` **110**, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1 (`GraphicsDevice::Viewport`, unrelated and pre-existing),
`OVERLOAD_MAPPING_MISMATCH` **42**, every other structural category 0, allowlist 0, unmeasured 0.
**20** event identities across **seven** owner types. **13** projected BCL identities and **8**
measured thrown exceptions.

CNA ABI **68 / 219 / 300 / 300 / 3 / 66** — up from 51/160/290/290/3/63. Seventeen additive bindings,
three new constants, one new layout, every symbol already exported by the reviewed library. Zero
missing header symbols, zero missing library symbols, zero mismatches. **No CNA source was changed
and no new native binary was built.**

Behaviour corpus **526** observations, zero failures. Suite **1127 runs / 44590 assertions**, zero
failures, zero skips. Capability registry **103** rows, zero contradictions.

## Game is one member from complete

`Content` alone remains, blocked on the missing `ContentManager`. Foundation 44 took `Tick` off that
list, 45 `IsActive`, 46 `LaunchParameters`, 47 `Dispose(Boolean)`/`Finalize`/
`ShowMissingRequirementMessage`, and 48 `Window`.

## The one reasoning error this session corrected, three times over

Three deferrals were wrong in the same way, and each correction is recorded beside the register entry
it replaces:

- **`NATIVE_RUNTIME` means only "this type's IL reaches a native entry point".** It is not a blocker,
  because **the native runtime this binding has is CNA**. Native frontier 1 first corrected it for
  `FrameworkDispatcher`; Foundation 48 corrected it for `GameWindow`, whose every abstract member the
  canonical C ABI already supplies.
- **A `RUNTIME_DATA` deferral that names a producer is about the producer, not the type.**
  `RendererDetail` (50), `VisualizationData` (51) and `Video` (52) each had a justification naming
  the thing that would *fill* them; all three are pure managed and were completed under Foundation
  25's constructor-free rule. The register is down to two entries, and both are genuine.
- **A blocker can also be more specific than the register says.** Native frontier 4 measured the
  audio path rather than assuming it and found the opposite of the other three: the routes exist,
  execute and report success, but the behaviour is absent. That is `UPSTREAM_CNA_BLOCKED`, not
  `NATIVE_RUNTIME`.

## Native frontier 4 — an audit that completed nothing, deliberately

`docs/audio-playback-audit-evidence.md`, measured in `docs/generated/audio-native-report.json` by
`tools/run_audio_playback_evidence.rb`.

The canonical audio path is **complete** in the ABI — 74 routes, `create_pcm16` through
`create_instance` to play/pause/resume/stop, the four setters and both destroys — and
`cna_audio_get_capabilities` reports playback **available**. Driven end to end with one full second
of mono PCM16, every call reports success, and yet:

- `SoundState` **never leaves `Stopped`** through play, three frame steps, an explicit
  `cna_framework_dispatcher_update`, pause, resume and stop;
- one full second of PCM answers a **zero** duration, and `get_sample_duration_ticks` **fails**;
- `set_is_looped` is refused with `CNA_RESULT_INVALID_STATE` in **every** state.

Volume, pitch and pan do round-trip. **It is not the null backend**: the measurement is identical
with `CNA_AUDIO` unset and with `CNA_AUDIO=SDL`. Projecting `SoundEffect`/`SoundEffectInstance` on
this would give a constant `State`, an always-zero `Duration`, a `Play` that reports success and does
nothing and an `IsLooped` setter that always raises — so both stay deferred.

Audited with them, each with a distinct reason: **`Audio.Cue`** needs an XACT engine opened from an
`.xgs` settings file plus two missing XNA types; **`Graphics.EffectAnnotation`** needs a compiled
effect with parameters, and `cna_effect_create_empty` builds one with none; **`Graphics.TextureCollection`**
has **no CNA route at all**, the one case where `NATIVE_RUNTIME` was the right word.

## Facts a summary would get wrong

- **`Tick` and `RunOneFrame` are two XNA operations, not one.** `WindowsGameHost.RunOneFrame` is
  `gameWindow.Tick()`, then `OnIdle()` whose only subscriber is `Game.HostIdle` whose whole body is
  `this.Tick()`, then the `Guide.IsVisible` relay. The C ABI documents the identical split.
- **`exitRequested` is written once in the whole assembly and never cleared**, so `Exit()` disables
  `Tick` permanently. Projected in managed state, because CNA's step after `cna_game_request_exit`
  still delivers one `Update`.
- **`Game.IsActive` is not a field read.** It is
  `isActive && !(GamerServicesDispatcher.IsInitialized && Guide.IsVisible)`, and all three terms have
  a canonical route. The guide term is *asked*; in this artifact it answers false and
  `cna_guide_set_is_visible` is accepted without being reflected, so the branch is proved wired by a
  truth table rather than exercised.
- **Twenty-two of `Dictionary`2`'s methods are explicit interface implementations** and project to
  nothing; its `SerializationInfo` constructor is `family`. That is why the serialization question
  was smaller than it looked.
- **`Dictionary.Clear` returns at its first branch when empty**, so an empty `Clear` does not bump
  the version and does not invalidate an enumeration.
- **`LaunchParameters` keeps a colonless argument** with `String.Empty` as its value; the canonical
  CNA route skips it. That, plus an upserting `add` and a name-sorted enumeration, is why those
  routes are deliberately unbound.
- **Two XNA exception types have two two-argument constructors.** Ruby has no overload by parameter
  type, which is what forces the serialization carrier to be a nominal identity.
- **`GameWindow`'s `Title` is the host's**, not a managed shadow: the abstract constructor sets
  `String.Empty` but `WindowsGameWindow` immediately calls `set_Title(GetDefaultTitleName())`.
- **`CNA_StringView` is the first aggregate passed by value.** Fiddle cannot pass one, so the
  manifest expands it into the two System V x86-64 eightbytes and **records the expansion**, which
  the ABI probe reconstructs and compares against the header.
- **`Media.Video`'s duration argument is milliseconds**, stored as `new TimeSpan(0, 0, 0, 0, ms)`.
- **`RendererDetail.ToString` comes from `ValueType`** — the first such case here — and answers the
  type's own fully-qualified CLR name.

## Recorded deviations added by this sequence

- `cna_game_tick` is refused from inside a lifecycle callback; XNA has no guard but no usable
  behaviour there either, so the refusal surfaces as CNA's own translated error.
- `Game.IsActive` and `Game.Window` are owner-thread bound where XNA's getters are not, and a
  disposed Game raises where XNA answers a stale field.
- `Game.Dispose` is still idempotent, so `Disposed` is raised once where XNA raises it per call. The
  `Monitor.Enter(this)` that Foundation 41 recorded as *not taken* **is now taken**.
- `GameWindow.SetSupportedOrientations` refuses: the ABI has no route, and orientation is readable
  there and not settable.
- `RendererDetail.GetHashCode` reproduces the empty-contributes-zero rule and the XOR exactly, but
  not `System.String.GetHashCode`.

## Measured CNA loop deviations that were **not** re-implemented

Both belong to the native host, and re-implementing either would double a step CNA performs — the
rule the `GraphicsDeviceManager` producer audit established:

- **`doneFirstUpdate`.** XNA sets it at the end of the *base* `Game.Update`, and `DrawFrame` returns
  early while it is false, so a subclass that overrides `Update` without `super` never draws. Here it
  does. `RunGame` also sets the flag unconditionally after its priming Update, so a `Run`-driven Game
  is unaffected either way.
- **The priming `Update`.** XNA's `RunGame` calls `Update(gameTime)` once with
  `ElapsedGameTime = TimeSpan.Zero` between `BeginRun()` and the host loop. CNA's `Run` does not.

## Recommended next frontier

Twelve dependency-complete candidates remain and **none is consumable**. Four are audited dead ends
(`SoundEffectInstance`, `Cue`, `EffectAnnotation`, `TextureCollection`), one is `GraphicsAdapter`
with Native frontier 1's four standing blockers, and `AudioCategory`/`MediaSource` are genuine
`RUNTIME_DATA`. What is left is three real BCL decisions, in rising order of cost:

1. **`System.IO.Stream`**, which blocks `TitleContainer` (one member, `OpenStream`) and is half of
   `ContentManager`. The register's rule — project to what the XNA surface can reach — would have to
   be applied to a base class with a large surface and a real I/O runtime behind it. `storage.h`
   exposes container routes that may or may not be the right producer; that has **not** been audited.
2. **`System.Action`1` and the generic `!!0`**, the other half of `ContentManager`, which is also the
   last member of `Game`.
3. **`System.ComponentModel`** (`ExpandableObjectConverter`, `ITypeDescriptorContext`,
   `PropertyDescriptorCollection`), which blocks the whole `Design` converter family.

`SpriteFont` and `Microphone` each keep a small BCL blocker (`System.Char`/`Nullable`1`/
`StringBuilder`, and `System.Byte[]`) *and* a native one, so neither is unblocked by a BCL decision
alone.

A qualification artifact carrying the SDL3 platform is unchanged and still needs a CNA checkout at
`a09196a6…`.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`), and a
  bare uppercase name in an expression parses as a **constant** — `GetEnumerator.each` is a NameError.
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`: a bare `rescue` does not catch an abstract contract member.
- **Ruby cannot give one method name two visibilities**, and it cannot overload by parameter type.
- **`::Monitor`, not `Mutex`, is the analogue of `lock (this)`.**
- `ValueSemantics#dup` builds through `new`; a type with private construction must override it.
- **Fiddle cannot pass a struct by value.** The manifest's `by_value` helper expands one into its
  eightbytes and records the expansion so the ABI probe can check it.
- `ikdasm` indents nested types, closes with the short name, quotes non-identifier names, wraps long
  operands, and puts a `modopt(...)` return modifier before the method name.
- **A scanner anchored on one side of a token loses something.** Bound a name on both sides.
- An `implements` list is comma-separated; split only at depth zero.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI; native work is mostly an indirect
  `calli`, not a classic P/Invoke.
- CNA's platform is a **build-time** selection.
- **A completed interface is not a provider.** `INTERFACE_PRODUCER_MISSING` measures that.
- **CNA's native `Game` is the XNA `Game`.** The Ruby `Game` is a callback façade over it, so any
  managed step CNA already performs would be performed twice.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are
  merged by documented deterministic replay, which refuses to write unless re-serialising the
  pre-merge corpus reproduces its bytes exactly. **Twenty-four** merges/corrections have been made
  this way. A corpus row that censuses this binding's own selection *will* need correcting later;
  `member_level_dependency.frontier_effect` says so in its own note and moved four times this session.
- Nothing measured from CNA may enter the behaviour corpus, which is `never CNA output` by
  construction. Native measurements go to `docs/generated/*-native-report.json` under
  `CNA_NATIVE_EVIDENCE`.
- The reconstructed Debian Ruby defaults `GEM_HOME` to the unwritable `/var/lib/gems/3.3.0`, so the
  template's `bundle install` needs one set; `~/deps/cna-ruby-template-bundle` is the standing one.
