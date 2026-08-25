# Continuation Evidence

## Exact current boundary

Foundations 16 to 27 are complete and qualified and published on `origin/develop`. **Native
frontier 1** is the first milestone of the native/CNA expansion sequence and is local only.

| Milestone | What it added | Types | Identities |
| --- | --- | --- | --- |
| 16 | pure managed enum batch A | 24 | 109 |
| 17 | Input.Touch managed closure | 3 | 17 |
| 18 | event-free interface contracts | 4 | 11 |
| 19 | dependency frontier register | 0 | 0 |
| 20 | general event projection, IUpdateable/IDrawable | 2 | 10 |
| 21 | BCL projection register, exception base mapping | 0 | 0 |
| 22 | **XNA IL provenance** + six exception types | 6 | 18 |
| 23 | TouchLocation, GestureSample, measured TimeSpan | 2 | 19 |
| 24 | AudioListener, AudioEmitter, PresentationParameters, GameComponentCollectionEventArgs | 4 | 26 |
| 25 | constructor-free class rule, DisplayMode, the two resource EventArgs | 3 | 9 |
| 26 | DisplayModeCollection, generic-definition blind spot | 1 | 2 |
| 27 | System.Attribute projection, five ContentSerializer attributes | 5 | 16 |
| NF1 | **GraphicsAdapter architecture audit** + FrameworkDispatcher | 1 | 1 |

Strict target 135 types / 1714 member identities: 129 complete, six partial native/runtime types,
122 missing, 306 deferred diagnostics. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other structural category 0,
allowlist 0, unmeasured 0. Four event identities across two owner types, five projected BCL
identities, two exception bases.

CNA ABI 38 / 122 / 290 / 290 / 2 / 59 through Foundation 27, and **39 / 124 / 290 / 290 / 2 / 59**
after Native frontier 1 bound `cna_framework_dispatcher_update`. Zero missing header symbols, zero
missing library symbols, zero ABI mismatches throughout; every Foundation 7 measurement is
byte- and signature-identical. No CNA source was changed and no new native binary was built.

## The correction Native frontier 1 makes

This file previously recorded, of the six `NATIVE_RUNTIME` types, that "each reaches a native entry
point in its own IL. Crossing that boundary means new CNA ABI, which this managed sequence
deliberately does not do."

**That is false, and it was the premise the whole native sequence was waiting on.** The retained
qualification artifact exports **2861** `cna_*` functions. This binding's measured manifest binds
**39**. The canonical C ABI already carries, in full, the surface every one of those six types
needs — including `GraphicsAdapter`, for which `modules/c-api/include/CNA/C/display.h` provides
adapter count, info, description, device name, current display mode, supported display modes,
device preferences, profile support and both format negotiations.

The native frontier was never gated on canonical ABI that does not exist. It is gated on three
other things, and naming them correctly is what this milestone contributes:

1. **Ruby binding work.** 39 of 2861.
2. **Undesigned BCL projections**, above all `ReadOnlyCollection`1`.
3. **The six deferred partial runtime types**, which own most of the producers.

Full evidence: `docs/graphics-adapter-audit-evidence.md`.

## Why GraphicsAdapter is still not projected

The audit derived the complete 18-identity contract from the pinned Graphics assembly and mapped
every identity onto CNA. Four independent blockers remain; any one would be sufficient.

1. **`ReadOnlyCollection`1` has no decided projection and no reference authority.**
   `mapping-rules.json` already lists it under `bclProjection.notYetDesigned`. Two materially
   different public Ruby designs are plausible and no rule chooses between them. Worse, the pinned
   inventory admits the ten XNA assemblies and no mscorlib, so unlike every BCL identity projected
   so far — each with an empty or scalar surface — this one has no measured member surface at all.
   It blocks `GraphicsAdapter`, `SpriteFont`, `Microphone` and `Media.VisualizationData`.
2. **The qualified artifact cannot supply truthful adapter data.** `libcna_c_api.so` 0.7.0 was
   linked with `CNA_PLATFORM=HEADLESS` — `nm` finds `HeadlessPlatform` and `TerminalPlatform` and
   no SDL platform, and it does not link SDL. `HeadlessPlatform::GetDisplays()` returns `nullptr`,
   so CNA's adapter falls back to a fabricated entry: one adapter described as `Default Display`,
   device name `\\.\DISPLAY1`, a single 800x480 `SurfaceFormat.Color` mode, and zeroed revision and
   subsystem id. Publishing that as `GraphicsAdapter` would be invented hardware. This is a
   property of the artifact's build configuration, not of CNA — a build carrying the SDL3 platform
   would answer truthfully.
3. **The C ABI is device-scoped and XNA's contract is not.** Every adapter route validates a
   callback-scoped `CNA_Handle graphics_device`; XNA's `Adapters` and `DefaultAdapter` are statics
   usable before any device exists, which is their purpose.
4. **`MonitorHandle` has no truthful producer.** The C ABI refuses it by design with
   `CNA_RESULT_NOT_SUPPORTED`, and CNA's own value is a display id cast to `uintptr_t` rather than
   an `HMONITOR`. The Ruby mapping is not the obstacle — `System.IntPtr` already maps to `Integer`.

Five CNA-side divergences from XNA were found and deliberately **not** changed, because each has
consequences beyond this binding and none unblocks the Ruby type: the `IsWideScreen` threshold
(CNA 4/3, XNA strictly > 1.6), the static-vs-instance device flags, display modes hardcoded to
`SurfaceFormat.Color` where `CNA::Platform::DisplayMode` carries no format field at all,
`Revision`/`SubSystemId` hardcoded to zero, and `IsProfileSupported` answering unconditional
`true` on every renderer without a descriptor hook. All five are written up in the audit evidence.

## The frontier: 21 dependency-complete, 0 consumable

| Blocker | Types | Nature |
| --- | --- | --- |
| `BCL_PROJECTION` | 8 | a BCL cluster no otherwise-unblocked type needs |
| `BCL_PROJECTION` + `NATIVE_RUNTIME` | 4 | both |
| `RUNTIME_DATA` | 4 | device, driver, codec or media values not queried |
| `NATIVE_RUNTIME` | 2 | its own IL reaches a native entry point |
| `BCL_PROJECTION` + `RUNTIME_DATA` | 2 | both |
| `IL_UNAVAILABLE` | 1 | `TouchCollection+Enumerator`, which `ikdasm` does not emit under an addressable name |

`EVENT_PROJECTION` was retired in Foundation 20, `BEHAVIOR_EVIDENCE` in Foundation 22, and
`FrameworkDispatcher` left `RUNTIME_DATA` in Native frontier 1 — the first entry retired because
its recorded reason was *wrong* rather than merely unresolved. It had been deferred on the ground
that `Update` "would be a no-op pretending to be a pump"; the canonical
`cna_framework_dispatcher_update` is the same drain CNA's own game loop runs, so forwarding to it
is a real pump. What is absent is the managed fan-out, because none of the five sinks the IL
dispatches to has a Ruby projection — and an absent subscriber is not a missing runtime value.

### The two candidates with no BCL blocker

Both were surveyed by the audit and both need a producer this milestone may not add:

- **`EffectAnnotation`** (14 identities) — every member is a `GetValueX()` on a native annotation.
  The C ABI has the full `cna_effect_annotation_*` family, but the producer is
  `EffectParameter.Annotations`, and no `Effect` type exists in this binding. Projecting it now
  would give fourteen members nothing to read from.
- **`TextureCollection`** (1 identity, `Item[Int32]`) — `cna_graphics_device_get_texture` /
  `set_texture` / `unbind_texture` cover it, but the producer is `GraphicsDevice.Textures`, and
  `GraphicsDevice` is one of the six deferred partials.

### What each remaining cluster needs

Unchanged from Foundation 27 except as noted above:

- **`System.Runtime.Serialization` (`ContentLoadException`, `StorageDeviceNotConnectedException`,
  8 identities)** — both list the protected `(SerializationInfo, StreamingContext)` constructor.
  .NET binary serialization has no Ruby analogue and no other consumer.
- **`System.Type` + `System.IServiceProvider` (`GameServiceContainer`, 4 identities)** — two BCL
  identities for one four-identity consumer whose reason to exist is `Game.Services`.
- **`System.IO.Stream` (`TitleContainer`, 1 identity)** — real file I/O relative to a title root
  this binding does not establish. Note that `cna_title_location_copy_path` exists in the C ABI.
- **`Dictionary`2` (`LaunchParameters`, 1 identity)** — the type *derives from*
  `Dictionary<string,string>`.
- **`System.IDisposable` (`Audio.Cue`, `SoundEffectInstance`, 35 identities)** — a live XACT engine.
- **`Design.MathTypeConverter`** — six BCL identities; `plan.md` records Design converters as out
  of scope.
- **`RUNTIME_DATA` (`AudioCategory`, `RendererDetail`, `GameWindow`, `Media.Video`)** — the IL
  settles every one; what is missing is an audio engine, an enumerated renderer, a platform window
  and a content pipeline. `GameWindow` additionally needs `Game.Window`, and `Game` is a deferred
  partial.

## Decision boundaries handed upward

None of these was taken autonomously.

1. **The `ReadOnlyCollection`1` public mapping.** Unblocks four types. Two plausible incompatible
   designs, no rule choosing between them.
2. **Whether to admit mscorlib to the pinned reference inventory.** This is what would make (1)
   measurable rather than a guess, and it changes the measurement basis of the whole binding.
3. **Whether to rebuild the qualification artifact with the SDL3 platform.** It would turn the
   fabricated adapter into a real one, at the cost of making the qualified suite depend on the
   host's displays.
4. **Whether CNA should stop fabricating an adapter when no display service exists.** Zero
   adapters is the honest answer and `getDefaultAdapterProperty` already throws in that case, but
   headless CNA games depend on the current fallback.

## The capability registry is a measured artifact

`tools/capability_consistency.rb` derives its assertions from measured state — the strict
verifier's complete-type list, the hash-admitted IL inventory, and the namespaces actually present
under `Microsoft::Xna::Framework`. `tools/generate_capabilities.rb` runs the check first and
refuses to write the Markdown on any finding. The gate is proved by
`test/fixtures/capability-registry-foundation-27-prefix.json`: 11 findings against the defective
Foundation 27 prefix, 0 against the corrected registry.

Native frontier 1 changed four rows: `native.abi-0.7` to 39/124, a new
`native.framework-dispatcher` (`VERIFIED_NATIVE_ROUTE`, because no managed sink observes the
drain yet), a corrected `audio-media` — it had claimed "no CNA audio or media route" and there is
now exactly one — and two new unresolved rows, `mapping.readonly-collection` and
`display.adapter-enumeration`. 83 rows, 0 contradictions.

Two capability assertions were themselves corrected: `test_capability_consistency.rb` asserted
that the string `UNRESOLVED_MAPPING_DECISION` may never appear anywhere. That was true at
Foundation 27 and is a category the checker deliberately classifies, so the assertion now names
the two retired blockers and the one decision that legitimately stands.

## Established general mappings

### Event projection (Foundation 20)

One CLR public event maps to exactly one public Ruby event reader keeping the XNA spelling, whose
value is `CNA::Runtime::Event`. `add(callable | &block)` answers the removal token; duplicates
permitted; registration-order dispatch over a snapshot; unswallowed exceptions; `remove` deletes the
last matching occurrence as `Delegate.Remove` does. Public surface is exactly `add`/`remove` and
raising is private. On an abstract contract the reader raises `NotImplementedError`. **No event in
this binding is ever raised.**

### BCL projection (Foundations 21, 23, 27)

`CNA::Runtime::BclProjection` is the measured register the verifier resolves and the frontier
consumes:

| CLR identity | Ruby |
| --- | --- |
| `System.EventArgs` | `CNA::Runtime::EventArgs` |
| `System.TimeSpan` | `Float` seconds |
| `System.Attribute` | `CNA::Runtime::Attribute` |
| `System.Exception` | `StandardError` |
| `System.Runtime.InteropServices.ExternalException` | `StandardError` |

Plus a thrown-exception table in `mapping-rules.json`: `ArgumentNullException` → `ArgumentError`,
`ArgumentOutOfRangeException` → `RangeError`, `ArgumentException` → `ArgumentError`,
`IndexOutOfRangeException` → `IndexError`. No fabricated Ruby `::System` namespace.

### Constructor-free classes (Foundation 25)

A CLR class whose only constructor is internal projects with `new` made private, as
`GraphicsResource` and `Texture` already did. Public non-constructibility is part of the contract;
the internal path stays reachable through `__send__`; no producer is fabricated.

### Static classes

A CLR `abstract sealed` class — C#'s `static class` — projects to a Ruby class whose `new` is
defined to raise `TypeError` and made private, and whose CLR static members are Ruby class
methods. `MathHelper` established it and `FrameworkDispatcher` follows it.

## Recommended next architectural frontier

1. **The `ReadOnlyCollection`1` decision**, if a maintainer will take it. Highest leverage of
   anything remaining: four types, and it is the last purely-decisional blocker in the register.
2. **A qualification artifact carrying the SDL3 platform**, if the project is willing to separate
   architecture qualification from environment-dependent integration observation. That is what
   turns `GraphicsAdapter`, and real `DisplayMode`/`DisplayModeCollection` production, from
   fabricated into measured.
3. **`TouchCollection+Enumerator`** — the single `IL_UNAVAILABLE` entry. A nested-type-aware
   extractor would settle it and unblock `TouchCollection`, then `TouchPanel`, though `TouchPanel`
   would still need a device.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`, not bare `Position`).
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`: a bare `rescue` does not catch an abstract contract member.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI. Native work is mostly an indirect `calli` through an unmanaged calling convention, not a classic P/Invoke; any native-boundary analysis must count both. Note the converse trap too: `FrameworkDispatcher.Update` looks native and is not — its `PollForEvents` is an empty method in the Windows assembly, and the measured inventory correctly reports the type as not native-reachable.
- CNA's platform is a **build-time** selection (`cmake/PlatformSelection.cmake`), not a runtime one. `CNA_RENDERER` selects the renderer and cannot change which platform a given `libcna_c_api.so` carries.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are merged by documented deterministic replay, which refuses to write unless re-serialising the pre-merge corpus reproduces its bytes exactly. Four corrections have been made this way, each proving every retained element unchanged.
