# Continuation Evidence

## Exact current boundary

**Session start HEAD = `920b0db8`**, which was also `origin/develop`. That baseline carries
Foundations 16 to 43 and Native frontiers 1 to 3.

The sequence recorded below is **Foundations 44 onward, Native frontiers 4 to 6, and the CNA C ABI
0.7.0 -> 0.21.0 migration**, added over several sessions. Resolve where it currently sits with

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
| 79 | `Graphics.Texture3D` + `TextureCube`, the two types `EffectParameter` returns | **2** | 20 |
| 80 | the nine-type `Effect` cluster, and `SpriteBatch.Begin`'s last two overloads | **9** | 98 |
| 81 | the vertex and index buffers, and the `VertexBufferBinding` that names one | **5** | 43 |
| 82 | `DirectionalLight`, `EffectMaterial` and the `IEffectLights` they unblocked | **3** | 12 |
| 83 | `RenderTarget2D`, `RenderTargetCube`, `RenderTargetBinding`, and an upload CNA drops | **3** | 22 |
| 84 | `OcclusionQuery`, whose getter is what unblocks the next call | **1** | 6 |
| 85 | `GraphicsDevice`'s state slice, and two aggregates measured by value | **0** | 7 |
| 86 | `GraphicsDevice`'s binding slice: the vertex streams and the index buffer | **0** | 5 |
| 87 | `GraphicsDevice`'s render-target slice, and the display isolation it exposed | **0** | 4 |
| 88 | the first draw call this binding has ever made | **0** | 3 |

## Measured state

This section had gone stale for eleven milestones — it still described Foundation 69's 177 types
while the report said 193 — and correcting it by hand is what Foundation 89 stopped relying on. The
block below is **generated** by `tools/scoreboard.rb` from the reports, rewritten by
`tools/render_scoreboard.rb`, and compared against them on every suite run by
`test/test_document_scoreboard.rb`. It cannot go stale without the suite going red.

<!-- scoreboard:begin -->

<!-- Generated by tools/scoreboard.rb; edit the reports, never this block. -->

**Selected surface**

| count | what it measures |
| ---: | --- |
| 257 | XNA 4.0 Windows reference types |
| 200 | types this binding projects |
| 2375 | Ruby member identities |
| 198 | complete types |
| 2 | partial types |
| 57 | missing types |
| 31 | event identities |
| 18 | types owning an event |
| 22 | projected BCL identities |

**Strict diagnostics**

| count | what it measures |
| ---: | --- |
| 118 | strict diagnostics in total |
| 57 | `MISSING_TYPE` |
| 43 | `MISSING_MEMBER` |
| 18 | `OVERLOAD_MAPPING_MISMATCH` |
| 0 | `PROPERTY_MAPPING_MISMATCH` |
| 0 | every other structural category, summed |
| 0 | allowlist entries |
| 0 | `UNMEASURED_STRUCTURAL_CATEGORY` |

**Partial remainders**

| count | what it measures |
| ---: | --- |
| 17 | members `GraphicsDevice` still owes |
| 15 | members `GraphicsDeviceManager` still owes |

**Native ABI**

| count | what it measures |
| ---: | --- |
| 387 | bound C functions |
| 5 | callbacks |
| 133 | constants |
| 63 | struct layouts |
| 2 | admitted encoded ABI versions |
| 2 | header roots cross-verified |
| 0 | `ABI_MISMATCHES` |
| 0 | `CROSS_VERSION_MISMATCHES` |
| 0 | missing header symbols |
| 0 | missing library symbols |

**Behaviour corpus**

| count | what it measures |
| ---: | --- |
| 526 | behaviour-corpus observations |
| 0 | behaviour-corpus failures |

**Dependency frontier**

| count | what it measures |
| ---: | --- |
| 3 | dependency-complete frontier candidates |
| 0 | of them consumable now |

**Capability registry**

| count | what it measures |
| ---: | --- |
| 145 | runtime capability rows |

<!-- scoreboard:end -->

`GraphicsDevice` and `GraphicsDeviceManager` are the two partial types, and
`docs/graphics-runtime-member-audit.md` enumerates every member each still owes together with what
that member actually needs. The single `PROPERTY_MAPPING_MISMATCH` is `GraphicsDevice::Viewport`.

CNA ABI counts above are measured on **two admitted encoded versions** cross-verified across both
header roots. **No CNA source was changed and no new native binary was built.**

Suite **1573 runs / 50620 assertions**, zero failures, and 22 skips under the default HEADLESS
artifact at Foundation 88 — every one a renderer capability or fixture that artifact does not have:
compiled effects, volume storage and cube-face storage. The same runs are green under both real
renderer artifacts, 18 skips on `OPENGL33` and **one** on the compiled-effects build, with
`SDL_VIDEODRIVER=x11` — which Foundation 81 measured to be load-bearing rather than decorative.
Suite totals are the one measurement here that no report writes, so they are quoted as a dated
observation rather than as current state.

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

Volume, pitch and pan do round-trip. Projecting `SoundEffect`/`SoundEffectInstance` on that would
have given a constant `State`, an always-zero `Duration`, a `Play` that reports success and does
nothing and an `IsLooped` setter that always raises — so both were deferred.

**Every conclusion in this section was later overturned, which is why it is kept.** The audit
recorded "it is not the null backend: the measurement is identical with `CNA_AUDIO` unset and with
`CNA_AUDIO=SDL`" — and Native frontier 5 found that neither variable is read by anything, that the
backend is a **build-time** CMake choice, and that the retired artifact had been built
`CNA_AUDIO_PLATFORM=NULL`. The whole `Audio` namespace has since been projected against a real
44100 Hz mixer. The three types audited beside it went the same way: `Audio.Cue` was built against
the Spacewar sample's real XACT banks, `Graphics.EffectAnnotation` when the `Effect` cluster gave it
both a producer and the `EffectParameter` its getters forward to, and
`Graphics.TextureCollection` — recorded here as "no CNA route at all, the one case where
`NATIVE_RUNTIME` was the right word" — turned out to have had `cna_graphics_device_get_texture` and
`cna_graphics_device_set_texture` exported by the *retired* artifact too. The standing lesson is
that an `UPSTREAM_CNA_BLOCKED` finding is a statement about **one artifact**, and it expires when the
artifact changes.

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

**The type frontier is at rest and the member frontier is not.** `docs/generated/dependency-frontier.md`
carries the dependency-complete candidates and the scoreboard counts them; each has been audited and
each measurement stands. What is actually available is the members the two partial graphics types
still owe, and Foundation 89's audit — `docs/graphics-runtime-member-audit.md` — measured every one
of them family by family against CNA 0.21.0's real exports rather than against the blanket "graphics
runtime" word this handoff used to carry.

**The reusable finding is the one that keeps recurring.** All four graphics state objects reported
`NATIVE_RUNTIME`, and in all four the reachability was `Apply` — one `assembly`-visible member that
is not in the pinned contract, so no consumer could call it and nothing was lost by not projecting
it. `SamplerStateCollection`, audited straight after, is the counter-case worth keeping beside it:
there the word was **accurate** — `set_Item` really does call `SamplerState::Apply` — and being
accurate is exactly what made it buildable, because the route that apply needs is one CNA exports.
So the audit is not a search for wrong blockers; it is a search for *what* the blocker names.

The `RUNTIME_DATA` register is **empty**. Every entry it ever held described a producer rather than
the type, and eleven `NATIVE_RUNTIME` deferrals went the same way — the ninth being the four state
objects at once and the tenth `VertexDeclaration`, whose reachability was in every case an
`assembly`-visible member the contract never selects. `INTERFACE_PRODUCER_MISSING` emptied off the
dependency-complete list with it, for exactly the same reason. The audit is the rule that survived:
re-measure a deferral before trusting it, especially one that names the thing which would *fill* a
type.

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
