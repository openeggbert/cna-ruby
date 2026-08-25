# Continuation Evidence

## Exact current boundary

Foundations 16 to 27 are complete and qualified. Foundations 16–21 are one checkpoint commit;
Foundations 22–27 are one commit each; a final documentation commit records the qualified state.
**Eight local commits ahead of `origin/develop`, nothing pushed.**

| Foundation | What it added | Types | Identities |
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

Strict target 134 types / 1713 member identities: 128 complete, six partial native/runtime types,
123 missing, 307 deferred diagnostics. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other structural category 0,
allowlist 0, unmeasured 0. Four event identities across two owner types, five projected BCL
identities, two exception bases.

CNA ABI unchanged throughout: 38 / 122 / 290 / 290 / 2 / 59, zero missing symbols, zero mismatches.

## The reference assemblies are on this host

Every earlier "the retained original assemblies are not on this reconstructed host" statement was
**wrong** and has been removed. A hash-driven sweep found both assemblies the behaviour corpus had
cited since Milestone 3, byte-identical in several places:

- `Microsoft.Xna.Framework.dll` — `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`
- `Microsoft.Xna.Framework.Graphics.dll` — `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`

The durable copy is the sibling repository `openeggbert/xna4-decomp` at
`reference/xna4/original/windows/`, which carries all seventeen Windows assemblies plus ILSpy
reconstructions. The same bytes appear in the XNA Game Studio 4.0 refresh tree and in every built
sample's `bin/`. `ikdasm` and `monodis` are installed at `/usr/bin`.

`tools/api_compat/reference/XNA_IL_PROVENANCE.md` pins ten assemblies by SHA-256, size and version
and records the authority order: exact original binary plus `ikdasm` IL is the only implementation
authority; hash-proven ILSpy C# is readability only; FNA, MonoGame, CNA and the other CNA bindings
are comparators only. **No Microsoft binary is stored here or packaged into the gem** — the gem
audit asserts zero.

Regenerate the derived inventory with:

```sh
XNA_REFERENCE_ASSEMBLIES=<dir> ruby tools/api_compat/build_il_inventory.rb
```

It admits each assembly by exact SHA-256, never by filename, and refuses to run on any mismatch.

## The frontier: 22 dependency-complete, 0 consumable

| Blocker | Types | Nature |
| --- | --- | --- |
| `BCL_PROJECTION` | 8 | a BCL cluster no otherwise-unblocked type needs |
| `BCL_PROJECTION` + `NATIVE_RUNTIME` | 4 | both |
| `RUNTIME_DATA` | 5 | device, driver, codec or media values not queried |
| `NATIVE_RUNTIME` | 2 | its own IL reaches a native entry point |
| `BCL_PROJECTION` + `RUNTIME_DATA` | 2 | both |
| `IL_UNAVAILABLE` | 1 | `TouchCollection+Enumerator`, which `ikdasm` does not emit under an addressable name |

`EVENT_PROJECTION` was retired in Foundation 20 and `BEHAVIOR_EVIDENCE` in Foundation 22. Nothing is
blocked on a decision this project has failed to make, and nothing is blocked on missing IL except
the one nested enumerator.

### What each remaining cluster needs

- **`System.Runtime.Serialization` (`ContentLoadException`, `StorageDeviceNotConnectedException`,
  8 identities)** — both list the protected `(SerializationInfo, StreamingContext)` constructor as a
  selected member. .NET binary serialization has no Ruby analogue and no other consumer, so a
  marker projection would give the identity a body that does nothing — exactly the hollow
  implementation this project refuses.
- **`System.Type` + `System.IServiceProvider` (`GameServiceContainer`, 4 identities)** — designable
  in principle (`System.Type` → Ruby `Module`), but two BCL identities for one four-identity
  consumer, and the consumer's reason to exist is `Game.Services`, which is a deferred partial type.
- **`System.IO.Stream` (`TitleContainer`, 1 identity)** — `OpenStream` performs real file I/O
  relative to a title root this binding does not establish.
- **`Dictionary`2` (`LaunchParameters`, 1 identity)** — the type *derives from*
  `Dictionary<string,string>`, so it needs a whole generic-collection projection for one identity.
- **`System.IDisposable` (`Audio.Cue`, `SoundEffectInstance`, 35 identities)** — even projected,
  `Play`/`Pause`/`Resume`/`Stop` act on a live XACT engine that does not exist here.
- **`Design.MathTypeConverter`** — six BCL identities including `ExpandableObjectConverter`;
  `plan.md` records Design converters as out of Foundation scope.
- **`RUNTIME_DATA` (`AudioCategory`, `RendererDetail`, `FrameworkDispatcher`, `GameWindow`,
  `Media.Video`)** — the IL settles every one of them; what is missing is an audio engine, an
  enumerated renderer, a live service pump, a platform window, and a content pipeline.
- **`NATIVE_RUNTIME` (`EffectAnnotation`, `TextureCollection`, `Microphone`, `ContentManager`,
  `GraphicsAdapter`, `SpriteFont`)** — each reaches a native entry point in its own IL. Crossing
  that boundary means new CNA ABI, which this managed sequence deliberately does not do.

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

## Recommended next architectural frontier

1. **Native/CNA expansion.** Six types and the 132 partial-type members are behind the CNA ABI. This
   is now the largest remaining category and the only one whose blocker is capability rather than
   choice. `GraphicsAdapter` (18 identities) would unlock `DisplayMode`/`DisplayModeCollection` as
   *produced* rather than merely projected types.
2. **`System.Runtime.Serialization`**, only if a consumer beyond the two exception types appears.
3. **`TouchCollection+Enumerator`** — the single `IL_UNAVAILABLE` entry. `ikdasm` does not emit the
   nested enumerator under a name the inventory can address; a different disassembler or a nested-
   type-aware extractor would settle it and unblock `TouchCollection` and then `TouchPanel`, though
   `TouchPanel` would still need a device.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`, not bare `Position`).
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`: a bare `rescue` does not catch an abstract contract member.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI. Native work is mostly an indirect `calli` through an unmanaged calling convention, not a classic P/Invoke; any native-boundary analysis must count both.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are merged by documented deterministic replay, which refuses to write unless re-serialising the pre-merge corpus reproduces its bytes exactly. Four corrections have been made this way, each proving every retained element unchanged.
