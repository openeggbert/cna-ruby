# Continuation Evidence

## Exact current boundary

Foundations 16 to 27 and Native frontiers 1 and 2 are published on `origin/develop`.
**Foundations 28 to 33, Native frontier 3 and one evidence fix are local only** — eight commits
ahead of `origin/develop`, none pushed.

| Milestone | What it added | Types | Identities |
| --- | --- | --- | --- |
| 16–27 | see the published history | 45 | 231 |
| NF1 | GraphicsAdapter architecture audit + FrameworkDispatcher | 1 | 1 |
| NF2 | nested/generic IL extraction, declaring-type dependency | 0 | 0 |
| 28 | **mscorlib admitted as a separate BCL authority** | 0 | 0 |
| 29 | `ReadOnlyCollection<T>` projection | 0 | 0 |
| 30 | `NotSupportedException` → `CNA::Runtime::NotSupportedError` | 0 | 0 |
| 31 | `TouchCollection` + nested `Enumerator` | 2 | 18 |
| 32 | `TouchPanel`, closing `Input.Touch` | 1 | 14 |
| 33 | `GameServiceContainer`, `System.Type`, structural collapse | 1 | 4 |
| NF3 | **`modopt` blind spot in the native-boundary measurement** | 0 | 0 |

Strict target 139 types / 1745 member identities: **133 complete**, six partial native/runtime types,
118 missing, **302 deferred diagnostics**. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other structural category 0,
allowlist 0, unmeasured 0. Four event identities across two owner types, **eight** projected BCL
identities, two exception bases, **six** thrown-exception mappings.

CNA ABI **39 / 124 / 290 / 290 / 2 / 59** throughout, byte- and signature-identical to Native
frontier 1. Zero missing header symbols, zero missing library symbols, zero mismatches. **No CNA
source was changed and no new native binary was built** in any of these milestones.

## The third reference authority

Until Foundation 28 this binding had two: the XNA public-metadata contract and the XNA IL
provenance register. Every BCL identity it had projected — `EventArgs`, `TimeSpan`, `Attribute` —
has an empty or scalar surface, so "measured" and "obvious" coincided and no measurement was ever
needed. `ReadOnlyCollection<T>` is the first with real behaviour, and the frontier register named
the obstacle exactly: no mscorlib was admitted, so the type had no measured surface at all.

Foundation 28 admits one, as a **separate** authority:

| Field | Value |
| --- | --- |
| Assembly | `mscorlib` 4.0.0.0, file version 4.0.30319.1 (RTMRel) |
| Public key token | `b77a5c561934e089`, **derived** from the assembly's own `.publickey` |
| Bytes / SHA-256 | 5196112 / `5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63` |
| Origin | `Microsoft Corporation` / `Microsoft Common Language Runtime Class Library` |

Deliberately not the .NET Compact Framework mscorlib XNA Game Studio ships for Xbox 360, not Mono,
not `System.Private.CoreLib`, not a NuGet reference assembly. Pinned by
`tools/api_compat/reference/BCL_PROVENANCE.md`; located by hash, never by path.

Two properties matter and both are checked on every run. **The identity is derived** — the token is
computed from the manifest blob by the CLR's own rule rather than compared against a constant.
**The pairing is proved** — all ten pinned XNA assemblies declare an `AssemblyRef` to `mscorlib`,
and each must name exactly the version and token the admitted binary derives. That is what makes it
*the* mscorlib rather than *an* mscorlib.

It moves no XNA metric: `REFERENCE_TYPES` 257, `REFERENCE_MEMBERS` 2964, `TYPES_WITH_IL` 257,
`TYPES_WITHOUT_IL` 0. Its own metrics are separate: `BCL_FAMILIES` 3, `BCL_TYPES` 17,
`BCL_MEMBERS` 246, `BCL_EXCEPTION_TYPES` 9. The inventory is demand-driven and aborts on a family
the XNA contract does not name.

## The BCL register, as it now stands

| Register | Entries | What an entry is |
| --- | --- | --- |
| `TYPES` | 5 | a BCL type the XNA public surface declares |
| `EXCEPTION_BASES` | 2 | a CLR base an XNA exception type derives from |
| `THROWN_EXCEPTIONS` | 6 | a CLR exception a projected member's own IL constructs |
| `STRUCTURAL_COLLAPSE` | 1 | an identity that projects to **no Ruby constant**, and why |

```
System.EventArgs                                    -> CNA::Runtime::EventArgs
System.TimeSpan                                     -> Float
System.Attribute                                    -> CNA::Runtime::Attribute
System.Collections.ObjectModel.ReadOnlyCollection`1 -> CNA::Runtime::ReadOnlyCollection
System.Type                                         -> Module

System.Exception                                    -> StandardError
System.Runtime.InteropServices.ExternalException    -> StandardError

System.ArgumentNullException                        -> ArgumentError
System.ArgumentOutOfRangeException                  -> RangeError
System.ArgumentException                            -> ArgumentError
System.IndexOutOfRangeException                     -> IndexError
System.NotSupportedException                        -> CNA::Runtime::NotSupportedError
System.InvalidOperationException                    -> RuntimeError

System.IServiceProvider                             -> (no constant, deliberately)
```

`bclProjection.notYetDesigned` is down to four: `System.IO.Stream`, `System.Text.StringBuilder`,
`System.Runtime.Serialization.SerializationInfo`, `System.Collections.Generic.Dictionary`2`.

Three rules were added along the way, each measured rather than documented:

- **`whoConstructsItDecides`.** A CLR exception the projected member's own IL constructs is mapped by
  the thrown-exception table. A condition that arises in this binding's own Ruby backing container,
  because the CLR member merely forwards, is governed by `collections.indexErrors` and raises
  `IndexError`. `TouchCollection`'s indexer constructs `ArgumentOutOfRangeException("index")` itself
  and raises `RangeError`; `ReadOnlyCollection` and `CurveKeyCollection` forward and raise
  `IndexError`. The one-to-one policy holds.
- **`languageSupport`.** A projected type may declare Ruby identities beside its CLR ones, and
  `CNA::Runtime::LanguageSupport` maps each to the CLR identity it derives from. The verifier admits
  one **only on a type that also projects that CLR identity** — `each` where `GetEnumerator` is
  projected and nowhere else. A rule, not an allowlist of names.
- **`structuralCollapse`.** Recording a decision *not* to invent a constant, and asserting it holds.

## What the mscorlib settled about `ReadOnlyCollection<T>`

Three facts, each of which rules out a design that was plausible before:

1. **A view, not a snapshot.** The constructor stores the `IList<T>` *reference* and all six public
   read members forward one call to it. A frozen Ruby copy would be a different type.
2. **It validates nothing of its own.** Not one of the six carries a throw; bounds, equality,
   ordering and enumeration all belong to the backing list.
3. **Read-only is a property of the interface.** Twelve explicit interface implementations throw
   `NotSupportedException` unconditionally. Ruby has no explicit interface implementation, so the
   faithful projection is that **no mutating member exists** — nothing to call, nothing to throw
   from, and no exception mapping needed. `TouchCollection` needed one because *its* six refusals
   are on its own public surface.

`Collection`1` was measured beside it: also a view, publishing mutation, throwing only when its
backing list is itself read-only.

**It unblocked no XNA type**, and separating that out was part of the milestone.
`GraphicsAdapter` dropped to `NATIVE_RUNTIME` alone and `Media.VisualizationData` to `RUNTIME_DATA`
alone; `Microphone` kept `System.Byte[]` and `SpriteFont` kept `System.Char`,
`Nullable`1[System.Char]` and `StringBuilder`. The four types that take it as a CLR base —
`ModelBoneCollection`, `ModelEffectCollection`, `ModelMeshCollection`, `ModelMeshPartCollection` —
are not on the frontier at all, because `ModelBone`, `Effect`, `ModelMesh` and `ModelMeshPart` are
missing. So no shipped type inherits from the support class yet and the inheritance rule is proved
by verifier fixtures.

## The correction Native frontier 3 makes

`Audio.SoundEffectInstance` was the last `BCL_PROJECTION`-only frontier entry that was neither out
of scope nor already declined — 16 identities, reported `nativeReachable: false`, which would have
made it pure managed work. **It is not.** Its own IL calls
`SoundEffectUnsafeNativeMethods::Play`, whose body is `calli unmanaged thiscall` into XACT.

The extractor read a method name as the first identifier before a parenthesis, having stripped the
two header forms known to carry one. A mixed-mode C++/CLI thunk carries a third:

```
.method public hidebysig static int32 modopt([mscorlib]...IsLong) Play(uint32)
```

so every such declaration was recorded as `modopt` while every call site resolved to `::Play`, and
every edge into XNA's native-methods classes dangled.

| Metric | F22 | NF2 | **NF3** |
| --- | --- | --- | --- |
| Native entry-point methods | 205 | 214 | **254** |
| Native-reachable reference types | 55 of 250 | 61 of 257 | **77 of 257** |

Sixteen types gained reachability, **none lost it**, and no other measured number moved.
`NATIVE_ENTRY_POINT_METHODS` is now written into the inventory rather than only printed.

It also corrects a conclusion about a **shipped** type. Native frontier 1 recorded that
`PollForEvents` is `{ ret }`, "so `Update` reaches no native entry point at all". The premise is
right and the conclusion was not: `Update`'s last call before returning is
`SoundEffect.RecycleStoppedFireAndForgetInstances`, which reaches XACT through exactly the thunks
this defect hid. That **strengthens** Native frontier 1's decision — XNA's own `Update` ends in
native work, so forwarding to the canonical CNA pump is the closer analogue, not the looser one.

The shipped-boundary rule the classifier is validated against now names four complete native types
rather than three: `Input.Mouse`, `Input.GamePad`, `Graphics.Texture` and `FrameworkDispatcher`,
each a type whose native route this binding really implements. Every partial runtime type but
`GraphicsResource` is native, unchanged.

## The frontier: 19 dependency-complete, 0 consumable

| Blocker | Types | Notes |
| --- | --- | --- |
| `BCL_PROJECTION` | 5 | see below — every one is declined, out of scope, or a stop boundary |
| `BCL_PROJECTION` + `NATIVE_RUNTIME` | 5 | `SoundEffectInstance` joined here in NF3 |
| `NATIVE_RUNTIME` | 3 | `EffectAnnotation`, `GraphicsAdapter`, `TextureCollection` |
| `NATIVE_RUNTIME` + `RUNTIME_DATA` | 1 | `Audio.AudioCategory` |
| `RUNTIME_DATA` | 5 | `RendererDetail`, `GameWindow`, `MediaSource`, `Media.Video`, `VisualizationData` |
| `IL_UNAVAILABLE` | **0** | emptied by Native frontier 2 |

The five `BCL_PROJECTION`-only entries, and why none of them is safe managed work:

- **`ContentLoadException`, `StorageDeviceNotConnectedException`** — the protected
  `(SerializationInfo, StreamingContext)` constructor. .NET binary serialization has no Ruby
  analogue and no other consumer; declined since Foundation 22.
- **`Design.MathTypeConverter`** — `System.ComponentModel`. `plan.md` records Design converters as
  out of scope.
- **`TitleContainer`** — `System.IO.Stream`, and real file I/O relative to a title root this
  binding does not establish. A platform decision, not a mapping one. Note
  `cna_title_location_copy_path` exists in the C ABI.
- **`LaunchParameters`** — `Dictionary`2`. **This is where the managed sequence stops**; see below.

## Why `Dictionary`2` is a stop boundary and not the next milestone

`LaunchParameters` is one identity — a public parameterless constructor — and it *derives from*
`Dictionary<string,string>`, so its entire public surface is inherited. Projecting it faithfully
means projecting `Dictionary<K,V>`, and the admitted mscorlib says exactly what that costs:

- **27 public/protected members**, against `ReadOnlyCollection`'s six.
- **Five nested public types**: `Enumerator`, `KeyCollection`, `ValueCollection` and the two nested
  enumerators of those.
- The public surface names **`IEqualityComparer`1`** (via `Comparer`) and
  **`SerializationInfo`/`StreamingContext`** (via the public `GetObjectData` and
  `OnDeserialization`) — one BCL family with no projection and no entry on any list, and one this
  project has already declined.

Foundation 29's own rule is that the support class exposes only what the measured projection
requires; but here the consumer inherits *everything*, so any narrowing changes what
`LaunchParameters` publicly is. And the cheap alternative — `class LaunchParameters < Hash` — is
the `frozen Array` of this decision: `Hash#[]` answers nil where the CLR indexer throws
`KeyNotFoundException`, and `Hash#store` overwrites where `Dictionary.Add` throws
`ArgumentException`.

So closing one XNA identity, whose producer `Game.LaunchParameters` does not exist because `Game`
is a deferred partial, would mean taking a cluster of new BCL decisions this prompt did not take.
That is designing a chunk of the .NET Framework, which is exactly what the demand-driven rule
exists to prevent. **Recorded as a decision for a maintainer, not taken autonomously.**

## The SDL3 experiment was not run, and why

Every precondition the instruction set was met except one, and that one is decisive:

- SDL3 **3.4.0** is installed at `/usr/local` — no new user-installed dependency. ✔
- The environment **does** have a display: `XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-0`,
  `DISPLAY=:0`. ✔
- CNA's default `CNA_PLATFORM` is already `SDL3`, and the existing `cmake-build-debug` is configured
  `CNA_PLATFORM=SDL3` / `CNA_GRAPHICS_RENDERER=OPENGLES3`, so **no source change** would be needed. ✔
- **The build could not come from the pinned commit.** The qualification artifact is CNA revision
  `a09196a6477f69a7a57c8364f990658d31531a5b`; the CNA working tree is on `develop` at
  `1bb2145d99ed572dd4eb15009c34e2e5f410fcf0`, **18 commits ahead**, with two worktrees already
  registered and an untracked file present. The instruction requires "the exact same CNA source
  commit", and reaching it means moving a shared checkout that shows active use. ✘

Separately, it could not have changed the conclusion. All four `GraphicsAdapter` blockers are
properties of the C ABI's shape and of XNA's contract, not of which platform is linked: the adapter
routes are callback-scoped where XNA's are statics, `MonitorHandle` is refused by design with
`CNA_RESULT_NOT_SUPPORTED`, `CNA::Platform::DisplayMode` carries no `SurfaceFormat` field, and
`IsProfileSupported` answers unconditional `true`. **SDL3 ≠ GraphicsAdapter complete**, exactly as
recorded.

## GraphicsAdapter: still deferred, now on one blocker

`ReadOnlyCollection`1` cleared its BCL blocker, so it is down to `NATIVE_RUNTIME` alone. The four
audit blockers stand unchanged and are written up in `docs/graphics-adapter-audit-evidence.md`:
fabricated headless adapter data, callback-scoped adapter routes versus XNA statics, no truthful
`MonitorHandle`, and the five CNA/XNA semantic divergences. Nothing here hardcodes a `Color`,
exposes a fake monitor handle, publishes "Default Display" as real hardware or claims unconditional
profile support.

## Established general mappings (added this sequence)

### BCL language projection (Foundations 29, 30, 33)

`System.Collections.ObjectModel.ReadOnlyCollection`1` → `CNA::Runtime::ReadOnlyCollection`, a live
view over its backing Array with no mutating member. A projected CLR **generic definition** answers
for every constructed form of itself; because a Ruby class is not statically generic, a subclass
declares its CLR type argument with `projects_elements` and the verifier measures it under
`GENERIC_MAPPING_MISMATCH`, with no allowlist.

`System.NotSupportedException` → `CNA::Runtime::NotSupportedError < StandardError`. Ruby's
`NotImplementedError` is refused because it descends from `ScriptError`, so a bare `rescue` — the
analogue of a CLR `catch (Exception)` — would not catch it.

`System.Type` → `Module`, the type token Ruby has, which is what it is in all 24 places the XNA
surface names it. `System.IServiceProvider` → no constant at all, recorded and checked.

### Language support (Foundation 31)

`CNA::Runtime::LanguageSupport` maps a Ruby identity to the CLR identity it derives from. A
projected type may declare one **only if it also projects that CLR identity**. `each` carries
`GetEnumerator`; `Enumerable` is derived in its entirety from `each`, so including it adds no
independent behaviour. CLR identities are PascalCase or operators; language support is not, so the
two can never be confused.

## Recommended next frontier

1. **The `Dictionary`2` decision**, if a maintainer will take it. One XNA identity, and the cost is
   set out above. It is the last purely-decisional blocker left.
2. **A qualification artifact carrying the SDL3 platform, built from the pinned CNA commit.** The
   host now demonstrably has a display, so this would produce real measurements — but it needs a
   CNA checkout at `a09196a6…` that no other session is using.
3. **`System.IDisposable`**, which `SoundEffectInstance` and `Audio.Cue` both need. Native frontier 3
   makes clear it is not managed work: both reach XACT.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`, not bare `Position`).
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`: a bare `rescue` does not catch an abstract contract member. That is why it is correct for `IUpdateable`/`IDrawable` and wrong for `NotSupportedException`.
- `ikdasm` indents a nested type inside its declaring type and closes it with the **short** name, quotes a name that is not a plain identifier, and appends a generic parameter list it omits from the closing comment. It also wraps a long operand onto continuation lines, and declares a mixed-mode C++/CLI thunk with a `modopt(...)` return modifier **before** the method name. Any IL scanner anchored on column zero, on the full declared name, on a single operand line, or on the first identifier before a parenthesis will silently lose something — which has now happened three times.
- An IL reference spells a nested type `Parent/Child`; the reference contract and this binding spell it `Parent+Child`.
- An `implements` list is comma-separated, but a constructed generic carries commas of its own: split only at depth zero.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI. Native work is mostly an indirect `calli` through an unmanaged calling convention, not a classic P/Invoke; any native-boundary analysis must count both. **The pinned `Input.Touch` assembly is the converse case: it is a stub, with no native entry point anywhere in it, because XNA 4.0's touch support was for Windows Phone.**
- CNA's platform is a **build-time** selection (`cmake/PlatformSelection.cmake`), not a runtime one. `CNA_RENDERER` selects the renderer and cannot change which platform a given `libcna_c_api.so` carries.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are merged by documented deterministic replay, which refuses to write unless re-serialising the pre-merge corpus reproduces its bytes exactly. **Seven** corrections have been made this way, each proving every retained element unchanged. Contrary to what the Native frontier 2 note recorded, the replay *is* byte-preserving on the current corpus and was used for both of this sequence's corrections.
