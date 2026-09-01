# Continuation Evidence

## Exact current boundary

**Session start HEAD = `920b0db8`**, which was also `origin/develop`. That baseline carries
Foundations 16 to 43 and Native frontiers 1 to 3.

The sequence this session added on top of it is **Foundations 44 to 69, Native frontiers 4 and 5,
and the CNA C ABI 0.7.0 -> 0.21.0 migration**. Resolve where it currently sits with

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
| ABI | migration to CNA C ABI **0.21.0**, admitted as a measured set | **0** | **0** |
| NF5 | re-measuring the audio path: the retired artifact was built `CNA_AUDIO_PLATFORM=NULL` | **0** | **0** |
| 53 | `System.IO.Stream` + `SeekOrigin` + `TitleContainer` | 1 | 1 |
| 54 | `System.Action`1` + the generic `!!0` + `ContentManager`, completing `Game` | 1 | 15 |
| 55 | the audio cluster: `SoundEffect` + `SoundEffectInstance` | 2 | 33 |
| 56 | `Graphics.TextureCollection` + two `GraphicsDevice` members | 1 | 3 |
| 57 | `GamerServices.GamerServicesComponent`, a new namespace | 1 | 3 |
| 58 | `Audio.DynamicSoundEffectInstance` | 1 | 10 |
| 59 | `Audio.Microphone` | 1 | 15 |
| 60 | `Audio.AudioEngine` + `Audio.AudioCategory` | 2 | 24 |
| 61 | `Audio.WaveBank` + `SoundBank` + `Cue`, completing the namespace | 3 | 38 |
| 62 | `Media.MediaSource`, emptying the `RUNTIME_DATA` register | 1 | 4 |
| 63 | `Graphics.SpriteFont` + the `Char`/`Nullable`/`StringBuilder` decisions | 1 | 6 |
| 64 | `Content.ResourceContentManager` + the `ResourceManager` collapse | 1 | 2 |
| 65 | `GraphicsDeviceManager`'s nine preferred settings + `ApplyChanges`/`ToggleFullScreen` | **0** | 20 |
| 66 | `Graphics.GraphicsResource`'s disposal contract, completing it | 1 | 5 |
| 67 | `Texture2D.SaveAsPng` and `SaveAsJpeg` | **0** | 2 |
| 68 | `Texture2D`'s two public constructors | **0** | 2 |
| 69 | `Texture2D.SetData` and `GetData`, six overloads | **0** | 6 |
| 70 | `Texture2D.FromStream`'s five-argument overload, completing the type; the upstream zoom defect; the frontier and corpus staleness guards | **0** | 1 |
| 71 | the four graphics state objects, and the ninth `NATIVE_RUNTIME` deferral that was not one | **4** | 65 |
| 72 | `Graphics.SamplerStateCollection` + `GraphicsDevice.SamplerStates`/`VertexSamplerStates` | **1** | 4 |
| 73 | `Graphics.VertexDeclaration` + the `IVertexType` contract it uncovered | **2** | 6 |
| 74 | the four vertex structs, the frontier's first consumed work queue | **4** | 38 |
| 75 | `Media.VideoPlayer`, and the eleventh `NATIVE_RUNTIME` that was not one | **1** | 15 |
| 76 | `SpriteBatch.DrawString`, six overloads over two arities | **0** | 6 |
| 77 | `SpriteBatch.Begin`'s two state-bearing overloads, and the null-descriptor defect | **0** | 2 |
| 78 | `SpriteBatch.Draw`'s three destination-rectangle overloads, completing the member | **0** | 3 |
| NF6 | the real-renderer qualification artifact, and the adapter defect it found | **0** | **0** |

## Measured state

Strict target **177 types / 2152 member identities**: **174 complete**, three partial graphics
runtime types, 80 missing, **179 deferred diagnostics**. `MISSING_MEMBER` **67**, `PARTIAL_TYPES` 3,
`PROPERTY_MAPPING_MISMATCH` 1 (`GraphicsDevice::Viewport`, unrelated and pre-existing),
`OVERLOAD_MAPPING_MISMATCH` **28**, every other structural category 0, allowlist 0, unmeasured 0.
**27** event identities across **14** owner types. **22** projected BCL identities.

CNA ABI **260 functions / 5 callbacks / 101 constants / 37 layouts**, on **two admitted encoded
versions** cross-verified across both header roots. Zero missing header symbols, zero missing library
symbols, zero cross-version mismatches, zero ABI mismatches. **No CNA source was changed and no new
native binary was built.**

Behaviour corpus **526** observations, zero failures. Suite **1448 runs / 48719 assertions**, zero
failures, zero skips. Capability registry **130** rows, zero contradictions.

The dependency frontier carries **three** candidates, none is consumable, and **every one has been
audited**. It went 3 → 9 → 6 → 5 → 8 → 4 → 3 in six milestones — see `plan.md`. The eight-candidate
step is the only time this frontier has ever produced a work queue, and the step after it consumed
the whole thing.

## Game is complete, and so is the whole Audio namespace

`Game`'s last member, `Content`, was closed by Foundation 54 — bound to the content manager CNA's own
game already owns, because one XNA `ContentManager` must be one CNA content manager. Foundations 55
to 61 then completed every XNA 4.0 `Audio` type, ending with the XACT cluster measured against the
XNA Spacewar sample's real banks. No audio type is left on the frontier.

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

**Five** dependency-complete candidates remain. The count went 3 → 9 → 6 → 5 across three
milestones: completing `GraphicsResource` and `Texture2D` made six types behind them visible at
once, the audit the frontier's own rule demands then found four of those six were not blocked at
all, and the fifth turned out to be blocked by something CNA already exports. Three of the five left
have been *measured* rather than accepted; two have not, and they are the recommended next work.

**What the audit found, because it is the reusable part.** All four graphics state objects reported
`NATIVE_RUNTIME`, and in all four the reachability was `Apply` — one `assembly`-visible member that
is not in the pinned contract, so no consumer could call it and nothing was lost by not projecting
it. That is the ninth deferral this register has retired for naming something outside the type's
public surface. `SamplerStateCollection`, audited straight after, is the counter-case worth keeping
beside it: there the word was **accurate** — `set_Item` really does call `SamplerState::Apply` — and
being accurate is exactly what made it buildable, because the route that apply needs is one CNA
exports. So the audit is not a search for wrong blockers; it is a search for *what* the blocker
names. The same question is the first one to ask of the two that remain.

**Every candidate on the frontier has now been audited.** The type frontier is at rest in the
strongest sense this project has had: not "nothing looks buildable" but "each of the three left has
been measured and the measurement stands".

**The recommended next work is therefore outside the frontier: the 67 members the three partial
graphics types still owe.** `SpriteBatch` is finished except for `Begin`'s two `Effect`-taking
overloads, and those wait on `Graphics.Effect` -- which nothing projects, and which
`EffectAnnotation`'s own audit already found is what stands behind that candidate too. So `Effect`
is now the single type that would unblock the most: two `SpriteBatch` overloads and a frontier
candidate. `GraphicsDeviceManager`'s fifteen are the producer audit's and unchanged;
`GraphicsDevice`'s thirty-seven are the renderer's.

The three, all audited:

- **`Graphics.GraphicsAdapter`** — blocked by the **renderer selection**. The 0.21.0 artifact
  contains `Sdl3Platform` and links SDL3 and X11 (the retired 0.7.0 one had only Headless and
  Terminal, which is what the old note recorded), but the only renderer compiled in is `HEADLESS`:
  `CNA_GRAPHICS_RENDERER=BGFX` and `=VULKAN` both abort with "not compiled into this build.
  Available: HEADLESS". With it every `cna_graphics_adapter_*` route answers `SUCCESS` with invented
  values — one adapter, `"Default Display"`, `\\.\DISPLAY1`, a single 800x480 mode,
  `adapters_refresh` answering `NOT_SUPPORTED`. All eighteen of its identities *are* display values,
  so nothing survives removing them.
- **`Graphics.EffectAnnotation`** — not blocked by the renderer at all. `cna_effect_annotation_create`
  takes no game, device or effect, and its six properties are one `ldfld` each. What blocks it is
  that all eight `GetValue*` members forward to a temporary `EffectParameter`, so their behaviour is
  that type's, and nothing in the projected surface produces an annotation. The cheapest of the
  three to unblock: derive `EffectParameter`'s eight getters from the pinned Graphics IL. Its
  numeric guard is `if (ParameterClass != Scalar && StructureMembers.Count == 0) throw
  InvalidCastException`, and `GetValueString`'s is `if (ParameterType != String) throw`.
- **`Design.MathTypeConverter`** — blocked by **scope, not authority**. The authentic .NET Framework
  4.0 `System.dll` (SHA-256 `c3182e40…`) is in the same Wine prefix as the pinned `mscorlib` and
  could be admitted the same way, so `TypeConverter`'s IL is available. But `CanConvertFrom` and
  `CanConvertTo` each end in `call instance … TypeConverter::…`, so part of the behaviour really is
  the base's; `GetProperties` returns a `PropertyDescriptorCollection` this binding would have to
  produce; and `CanConvertTo` compares against `InstanceDescriptor`, a fourth `ComponentModel` type.
  The collapse that unblocked `ResourceContentManager` does not apply — that rule is for a type
  whose reachable surface is *one member*, not a base class one inherits from. Projecting it means
  projecting .NET's type-descriptor system for ten design-time converters nothing here consumes.

So the type frontier **is** at rest, and for the right reason: every remaining candidate was
measured rather than accepted, and each measurement found something the blocker word does not
name.

**The single largest lever is still a qualification artifact with a real renderer.** It would
unblock `GraphicsAdapter` directly and the three partial graphics types behind it —
`GraphicsDevice`, `GraphicsDeviceManager` and `SpriteBatch` — which between them owe 55 of the 78
outstanding members. `GraphicsResource` left that list when its disposal contract was projected and
`Texture2D` when its five-argument `FromStream` landed. `GraphicsDeviceManager`'s own share fell
from 26 to 15 when its preferred settings were projected, and what is left there is the producer
audit's, not the renderer's.

The `RUNTIME_DATA` register is **empty**. Every entry it ever held described a producer rather than
the type, and **eleven** `NATIVE_RUNTIME` deferrals went the same way — the ninth being the four state
objects at once and the tenth `VertexDeclaration`, whose reachability was in every case an
`assembly`-visible member the contract never selects. `INTERFACE_PRODUCER_MISSING` emptied off the
dependency-complete list with it, for exactly the same reason. The audit is the rule that
survived: re-measure a deferral before trusting it, especially one that names the thing which would
*fill* a type.

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
  pre-merge corpus reproduces its bytes exactly; corrections to existing rows are made as **surgical
  byte edits**, which is a stronger guarantee than a replay proof because every other byte of the
  file is provably untouched. Each one records its pre-correction SHA-256. A corpus row that
  censuses this binding's own selection *will* need correcting later:
  `member_level_dependency.frontier_effect` says so in its own note and has now moved seventeen
  times, and `disposable_collapse.frontier_effect` has needed its **operation** corrected three
  times for one reason — it read a type's blockers out of the candidate list, and the type kept
  being built.
- Nothing measured from CNA may enter the behaviour corpus, which is `never CNA output` by
  construction. Native measurements go to `docs/generated/*-native-report.json` under
  `CNA_NATIVE_EVIDENCE`.
- The reconstructed Debian Ruby defaults `GEM_HOME` to the unwritable `/var/lib/gems/3.3.0`, so the
  template's `bundle install` needs one set; `~/deps/cna-ruby-template-bundle` is the standing one.
