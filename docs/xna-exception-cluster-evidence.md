# Foundation 22 — the XNA exception cluster, and real IL provenance

Locates the original Microsoft XNA Framework 4.0 Windows assemblies **by hash** on this host,
pins them, derives a Microsoft-free IL inventory from them, retires the `BEHAVIOR_EVIDENCE`
blocker that was built on their supposed absence, and completes six of the eight XNA exception
types from that IL.

## The assemblies were here all along

Foundations 19 to 21 recorded "the retained original assemblies are not on this reconstructed
host". That was wrong. A hash-driven sweep of `/rv` and `$HOME` found both pinned assemblies in
several places, all byte-identical:

| Assembly | SHA-256 |
| --- | --- |
| `Microsoft.Xna.Framework.dll` | `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130` |
| `Microsoft.Xna.Framework.Graphics.dll` | `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55` |

Those are exactly the two hashes the behaviour corpus had been citing as `sourceAssemblySha256`
since Milestone 3, so every earlier provenance claim is now verifiable rather than asserted. The
durable copy is the sibling repository `openeggbert/xna4-decomp` at
`reference/xna4/original/windows/`, which carries all seventeen Windows assemblies plus ILSpy
reconstructions; the same bytes also appear in the XNA Game Studio 4.0 refresh tree and in every
built sample's `bin/`. `ikdasm` and `monodis` are both installed, so no tooling was missing either.

`tools/api_compat/reference/XNA_IL_PROVENANCE.md` pins ten assemblies by SHA-256, size and version,
and states the authority order: exact original binary plus `ikdasm` IL is the only implementation
authority; hash-proven ILSpy C# is for readability; FNA, MonoGame, CNA and the other CNA bindings
are comparators only. No Microsoft binary is stored in this repository or packaged into the gem.

## The IL inventory

`tools/api_compat/build_il_inventory.rb` reads `XNA_REFERENCE_ASSEMBLIES`, admits each assembly
**by exact SHA-256 rather than by filename**, refuses to run on any mismatch, disassembles with
`ikdasm`, and writes `docs/generated/xna-il-inventory.json`. That file contains measured structure
only — no Microsoft-owned bytes and no machine-local path, both asserted by a test.

Per reference type it records the declaring assembly and its hash, IL size, declared field count,
declared non-constructor method count, per-constructor access, and — for each constructor — whether
its entire body is a pure forward to the base constructor. 250 of the 257 reference types have IL;
the seven that do not are nested enumerators and generic definitions the disassembler names
differently.

### Native reachability is now measured, not assumed

XNA 4.0's Framework and Graphics assemblies are mixed-mode C++/CLI: most native work is an indirect
`calli` through an unmanaged calling convention, not a classic P/Invoke. Both forms count as a
native entry point. A type is native-reachable when any method it declares is a native entry point
or transitively calls one, following only call edges that land inside the pinned assembly set.

205 native entry-point methods make **55 of 250** reference types native-reachable. The rule
validates against what this binding already knows:

- every partial runtime type except the pure-managed `GraphicsResource` contract is native-reachable;
- of the 113 complete types, exactly three are — `Input.Mouse`, `Input.GamePad` and
  `Graphics.Texture`, the three whose native routes this binding really implements. Every other
  complete type comes out pure managed.

## Blocker changes

`BEHAVIOR_EVIDENCE` is retired. "Behaviour lives in IL" is now a statement about work to do, not
about missing input, and is reported as the informational `ilDerivationRequired` flag. It is
replaced by three blockers that name what is genuinely absent:

| Blocker | Meaning |
| --- | --- |
| `IL_UNAVAILABLE` | declares behaviour but no pinned assembly carries its IL |
| `NATIVE_RUNTIME` | its own IL reaches a native entry point, so faithful behaviour needs CNA or platform support this managed sequence does not add |
| `RUNTIME_DATA` | the IL settles its semantics, but its values come only from a device, driver, codec or media library that has not been queried |

`RUNTIME_DATA` is a register in which every entry must name the exact missing input; a test enforces
that, and that no complete type appears in it. It currently holds nine types — `RendererDetail`,
`AudioCategory`, `MediaSource`, `Media.Video`, `VisualizationData`, `ResourceCreatedEventArgs`,
`ResourceDestroyedEventArgs`, `GameWindow` and `FrameworkDispatcher`. IL availability proves
behaviour; it never proves the availability of hardware or runtime data, and this project does not
fabricate capability values.

The frontier changed from **0 consumable / 38 blocked** to **7 consumable / 25 blocked**.

## What the IL established about the exceptions

All eight XNA exception types are structurally identical, and the IL is unambiguous:

- **zero declared fields, zero declared methods**, four constructors each;
- `.ctor()` → `ldarg.0; call base::.ctor(); ret`
- `.ctor(string)` → `ldarg.0; ldarg.1; call base::.ctor(string); ret`
- `.ctor(string, Exception)` → `ldarg.0; ldarg.1; ldarg.2; call base::.ctor(string, Exception); ret`
- `.ctor(SerializationInfo, StreamingContext)` → the same pure forward, `private` on six of the
  eight and `protected` on `ContentLoadException` and `StorageDeviceNotConnectedException`, exactly
  matching which of them the pinned public metadata lists as a member.

**No message synthesis, no argument validation, no state of its own, in any of the twenty-four
constructors.** That is what could not be assumed before and is now measured.

## The Ruby projection

Six types, three Ruby identities each, local diagnostics zero on every one:

| Type | CLR base | Ruby superclass |
| --- | --- | --- |
| `Audio.InstancePlayLimitException` | `ExternalException` | `StandardError` |
| `Audio.NoAudioHardwareException` | `ExternalException` | `StandardError` |
| `Audio.NoMicrophoneConnectedException` | `System.Exception` | `StandardError` |
| `Graphics.DeviceLostException` | `System.Exception` | `StandardError` |
| `Graphics.DeviceNotResetException` | `System.Exception` | `StandardError` |
| `Graphics.NoSuitableGraphicsDeviceException` | `System.Exception` | `StandardError` |

The Foundation 21 base mapping applies unchanged, including its documented collapse of
`ExternalException` to the nearest projected ancestor. `CNA::Runtime::XnaExceptionConstruction`
supplies the one shared `initialize` and adds no public identity: each class's
`public_instance_methods(false)` is empty.

Constructor semantics, each derived from the IL rather than from a .NET convention:

- **`new`** — forwards with no message, so the message is the language runtime's own default naming
  the type, exactly as `System.Exception()` produces one naming the CLR type. `cause` is nil.
- **`new(message)`** — forwards the message unchanged.
- **`new(nil)`** — reaches the base as null and falls back to the same default, in both runtimes.
- **`new(message, inner)`** — forwards both. `System.Exception`'s inner-exception slot maps to
  Ruby's `Exception#cause`, which only `raise` can fill, and which `raise` fills *on this very
  object*: `CNA::Runtime::ExceptionSupport.bind_cause` raises the exception, immediately re-catches
  it and clears the backtrace. A constructed-but-unraised XNA exception therefore has `cause` set
  and `backtrace` nil — precisely the CLR's `InnerException` set and `StackTrace` null before a
  throw. A cause bound this way survives being raised later and is not displaced by an ambient
  `$!`. A non-exception inner value is rejected with Ruby's own `TypeError`.

Each type is an ordinary Ruby exception: a bare `rescue` catches it, and `full_message` shows the
inner exception.

## Why two stay deferred

`Content.ContentLoadException` and `Storage.StorageDeviceNotConnectedException` list the
`(SerializationInfo, StreamingContext)` constructor as a **protected member of their selected
public surface**, so completing them means projecting that BCL cluster. No otherwise-unblocked type
needs it, so it is deliberately not designed. Their IL is available and their blocker is exactly
`BCL_PROJECTION`; the moment `SerializationInfo`/`StreamingContext` gains a projection, both drop in.

Completing these six claims no audio engine, `SoundEffect`, `Microphone` or XACT support, no
`GraphicsAdapter`, `DisplayModeCollection`, render target or `Effect`, and no `Content` or `Storage`
namespace at all. Nothing in this binding raises any of them.

## Corpus correction

The nine Foundation 21 `bcl_projection.exception.*` rows are `PURE_XNA_DERIVED`, but each carried
one *mapping* fact: whether the binding had selected the type. That element was removed. The replay
proved, element by element, that every retained value of every corrected row is unchanged and that
no other row was touched, and the corpus records the correction as `milestone22CorpusCorrection`.
Selection is now recorded by the Foundation 22 `RUBY_MAPPING_QUALIFICATION` rows where it belongs.

## Structural movement

TARGET_TYPES 113 → 119, TARGET_MEMBERS 1623 → 1641, TOTAL_DIAGNOSTICS 328 → 322, MISSING_TYPE
144 → 138, COMPLETE_TYPES 107 → 113. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other category 0, allowlist 0,
unmeasured 0.

CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59, zero missing symbols, zero mismatches.

## Verification

- Full Ruby suite: 577 runs / 20190 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 382 observations / 382 assertions / 0 failures; 16 additive rows in the new
  `XNA_EXCEPTION` and `IL_PROVENANCE` groups, merged by deterministic replay against pre-merge
  SHA-256 `33968ec017e5cd7427765aefac23db0fa82ccb53ebadbe4209bab1466381430b`.
- API verifier strict: 322 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
