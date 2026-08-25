# Continuation Evidence

## Exact current boundary

Foundations 16 to 27 and Native frontiers 1 and 2 are published on `origin/develop`.
**Foundations 28 to 39, Native frontier 3, one evidence fix and this handoff are local only** —
fifteen commits ahead of `origin/develop`, none pushed.

| Milestone | What it added | Types | Identities |
| --- | --- | --- | --- |
| 16–27 | see the published history | 45 | 231 |
| NF1 | GraphicsAdapter architecture audit + FrameworkDispatcher | 1 | 1 |
| NF2 | nested/generic IL extraction, declaring-type dependency | 0 | 0 |
| 28 | mscorlib admitted as a separate BCL authority | 0 | 0 |
| 29 | `ReadOnlyCollection<T>` projection | 0 | 0 |
| 30 | `NotSupportedException` → `CNA::Runtime::NotSupportedError` | 0 | 0 |
| 31 | `TouchCollection` + nested `Enumerator` | 2 | 18 |
| 32 | `TouchPanel`, closing `Input.Touch` | 1 | 14 |
| 33 | `GameServiceContainer`, `System.Type`, structural collapse | 1 | 4 |
| NF3 | `modopt` blind spot in the native-boundary measurement | 0 | 0 |
| **34** | **`Collection<T>` projected as the mutable BCL base** | 0 | 0 |
| **35** | **`GameComponentCollection`; signature-graph correction** | **1** | **7** |
| **36** | **`System.IDisposable` structural collapse** | 0 | 0 |
| **37** | **`Game.Components`, `Game.Services`, the component engine** | 0 | **2** |
| **38** | **`GameComponent`** | **1** | **14** |
| **39** | **member-level dependency edges** | 0 | 0 |

Strict target 141 types / 1768 member identities: **135 complete**, six partial native/runtime
types, 116 missing, **298 deferred diagnostics**. `MISSING_MEMBER` **130**, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other structural category 0,
allowlist 0, unmeasured 0. **Nine** event identities across **four** owner types, **ten** projected
BCL identities, two exception bases, six thrown-exception mappings, **two** structural collapses.

CNA ABI **39 / 124 / 290 / 290 / 2 / 59** throughout, byte- and signature-identical to Native
frontier 1. Zero missing header symbols, zero missing library symbols, zero mismatches. **No CNA
source was changed and no new native binary was built** in any of these milestones.

## What this sequence built

One coherent slice: the managed XNA component lifecycle, on top of the existing CNA native host.

```
System.Collections.ObjectModel.Collection`1  ->  CNA::Runtime::Collection      (F34)
GameComponentCollection < Collection<IGameComponent>                           (F35)
System.IDisposable                           ->  no Ruby constant             (F36)
Game.Components / Game.Services + the private engine                           (F37)
GameComponent                                                                  (F38)
```

`Components`, `Services` and the four private lists behind them are **pure managed state**. CNA owns
the native host, the frame loop, the window and the device; it does not own the component list, and
nothing added here routes a component through the C ABI. Both getters are one `ldfld` in the IL, so
both answer the same object for the life of the `Game` and both work on a `Game` that has never run.

### Ruby `super` is the whole base-call mechanism

Ruby has real class inheritance, so `super` **is** `base.Update(gameTime)`. No `GameBaseUpdate`,
`GameBaseDraw` or `GameBaseInitialize` helper exists, and none was invented. The native host invokes
the virtual Ruby method **once** and never runs the base itself, so:

| Subclass | Base component pass |
| --- | --- |
| overrides and omits `super` | **does not run** |
| overrides and calls `super` | runs once, between the subclass's own work |
| calls `super` twice | runs twice, a complete pass each time |

Each is proved three times: through the protected hook directly, through the real native loop, and
in the isolated-gem consumer canary.

## The GameHost callback-order audit

Measured against the reviewed CNA library, not read out of its header.

| | Order |
| --- | --- |
| **XNA `RunGame`** | `CreateDevice` → `Initialize()` *(→ `LoadContent()` when a device service exists)* → `inRun = true` → `BeginRun()` → `Update()` → loop → `EndRun()` |
| **CNA, measured** | `initialize` → `load_content` → `begin_run` → `update` → `begin_draw` → `draw` → `end_draw` → … → `exiting` → `end_run`; `unload_content` at destroy |

**The orders agree.** The one structural difference is *who* calls `LoadContent`, and it costs
nothing: XNA's base `Initialize` calls it only when `Services` holds an `IGraphicsDeviceService`, a
missing type with no Ruby key, so the guard is false and the host's callback is the only one.
Nothing is called twice and nothing is skipped. `RunOneFrame` delivers no `begin_run`, matching XNA.

**Recorded future boundary:** a milestone that registers an `IGraphicsDeviceService` makes that
guard true and must then resolve the double call.

The in-run flag lives in `CNA::Runtime::GameHost`, as XNA keeps it in `RunGame` rather than in
`Initialize`, so it survives a subclass that overrides `Initialize` without calling `super`. It is
raised after **`LoadContent`** — the measured position, because in XNA both managed steps run before
the assignment — and cleared after `EndRun`.

## What was deliberately not implemented, and why

- **`FrameworkDispatcher.Update()` in `Game.Update`'s base.** The canonical CNA C ABI documents
  `cna_framework_dispatcher_update` as pumping "the framework-wide per-frame work **the game loop
  normally drives**", so the host already does it every frame. Calling it here would pump the same
  queue twice *and* impose this binding's recorded dispatcher deviation — a live CNA `Game` on its
  owner thread — on `Game.Update`, which XNA's does not have, so `super` would start failing on a
  `Game` that has never run. The identity itself stays projected exactly as Native frontier 1
  qualified it.
- **`doneFirstUpdate`.** A private field whose only readers, `Tick` and `DrawFrame`, are the native
  timing loop CNA owns here.
- **`HookDeviceEvents` and the conditional `LoadContent` in `Game.Initialize`.** Both guarded by an
  `IGraphicsDeviceService` this binding cannot register. They are separable from the drain loop that
  sits between them, so the managed part is implemented in its exact position with nothing faked.
- **`LaunchParameters`, `ContentManager`, `GameWindow`, the clock** in the constructor — each blocked
  on a missing type or on lifecycle CNA owns, and none touches component state.

## The two mapping limitations this sequence records

- **`GameComponent.Dispose`.** `Dispose()` is `public` and `Dispose(bool)` is `protected`; Ruby
  cannot give one name two visibilities, so the two overloads project to one public arity-dispatching
  method and the protected one is publicly reachable here. The static contract retains both signature
  identities. It costs little: the bodies differ only by `GC.SuppressFinalize`, which has no analogue.
- **`GraphicsDeviceManager` has no `Dispose()`.** It is the one of twenty-nine `IDisposable`
  implementers that implements the member *explicitly*, and an explicit interface implementation
  projects to no member — the rule `ReadOnlyCollection`'s twelve and `Collection`'s fourteen already
  follow.

## The BCL register, as it now stands

| Register | Entries | What an entry is |
| --- | --- | --- |
| `TYPES` | 6 | a BCL type the XNA public surface declares |
| `EXCEPTION_BASES` | 2 | a CLR base an XNA exception type derives from |
| `THROWN_EXCEPTIONS` | 6 | a CLR exception a projected member's own IL constructs |
| `STRUCTURAL_COLLAPSE` | **2** | an identity that projects to **no Ruby constant**, and why |

```
System.EventArgs                                    -> CNA::Runtime::EventArgs
System.TimeSpan                                     -> Float
System.Attribute                                    -> CNA::Runtime::Attribute
System.Collections.ObjectModel.ReadOnlyCollection`1 -> CNA::Runtime::ReadOnlyCollection
System.Collections.ObjectModel.Collection`1         -> CNA::Runtime::Collection
System.Type                                         -> Module

System.IServiceProvider                             -> (no constant, deliberately)
System.IDisposable                                  -> (no constant, deliberately)
```

`bclProjection.notYetDesigned` is still four: `System.IO.Stream`, `System.Text.StringBuilder`,
`System.Runtime.Serialization.SerializationInfo`, `System.Collections.Generic.Dictionary`2`.

### `Collection<T>`, in one paragraph

Same shape as its read-only sibling with the opposite intent: one `IList<T>` field, every read
forwarded, nothing copied. What differs is that **every mutation runs through one of four protected
hooks**, and that indirection *is* the type — so the projection declares no `<<`, no `push`, no
`delete`, because any of those would be a second path a subclass's hook never sees. It is also the
first type where both halves of `whoConstructsItDecides` are visible at once: the indexer forwards
and raises `IndexError`, while `set_Item`, `Insert` and `RemoveAt` construct
`ArgumentOutOfRangeException` in their own bodies and raise `RangeError`.

### `System.IDisposable`, in one paragraph

Four lines of mscorlib IL: **one member, `void Dispose()`, and nothing else**. No `Close`, no
`IsDisposed`, no finalizer contract, no ownership protocol — every one of those is a convention built
on top of it. Twenty-nine XNA types declare it, twenty-eight declare a public parameterless `Dispose`
of their own. Mapping the identity claims nothing about any type's disposal and makes no native
runtime available: `Audio.SoundEffectInstance` and `Audio.Cue` lost their BCL blocker and kept
`NATIVE_RUNTIME`, so `consumableCandidates` stayed 0.

## Two measurement corrections this sequence made

**Foundation 35 — the signature graph matched an unbounded prefix.**
`analyze_dependencies.rb` tested `signature.include?("[#{name}")`, so any longer type name starting
with a shorter one matched:
`System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]` was read as naming
`Game` and `GameComponent` too. Same class of blind spot Native frontiers 2 and 3 closed in the IL
extractor, and it ran both ways — **18 spurious edges across 15 types, and 21 edges missed entirely**
because a name followed by `[` matched nothing, so `VertexElement[]` never named `VertexElement`. A
name is now bounded on both sides. No frontier conclusion moved at the time, and with the fix applied
to the Foundation 34 state `GameComponentCollection` reports zero blockers as the single consumable
candidate — selected by the frontier rather than in spite of it.

**Foundation 39 — the signature graph is type-level, and two conclusions needed member-level.**
The IL inventory now records, per type, every call edge landing on a pinned reference type other than
its owner: **3271 edges across 257 types**, from the operands the native-reachability fixpoint already
collected. Purely additive — `TYPES_NATIVE_REACHABLE` stays 77, `NATIVE_ENTRY_POINT_METHODS` stays
254, no prior per-type fact moved — and the candidate policy is **not relaxed**: 19 / 0 candidates,
identical blocker summary, `selectedNext` still nil. What it settles:

- `GameComponent` reaches **exactly one** `Game` member, `get_Components`, which Foundation 37
  completed. Foundation 38's selection is proved rather than asserted.
- `DrawableGameComponent` reaches **nine** members of `IGraphicsDeviceService`, which no public
  signature of that type names — see below.
- **Six** candidates the signature graph called fully dependency-complete are blocked by a type only
  their IL reaches: `TextureCollection`, `SpriteFont`, `ContentManager`, `EffectAnnotation`,
  `SoundEffectInstance`, `Cue`. The last two *strengthen* Foundation 36: both were blocked twice over
  and only one reason was visible.

## `DrawableGameComponent`: re-evaluated and deliberately deferred

```
Microsoft.Xna.Framework.Game::get_Services                  (complete)
Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::…  (nine members, MISSING TYPE)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::…          (none — zero edges)
```

It reaches **no member of `GraphicsDevice` at all**: it obtains the device from
`IGraphicsDeviceService.GraphicsDevice` and republishes it. Its `Draw`, `LoadContent` and
`UnloadContent` are each a bare `ret`. So the entire type *is* the device-service handshake, and its
`Initialize` is guarded by

```
if (deviceService == null) throw new InvalidOperationException(Resources.MissingGraphicsDeviceService);
```

Nothing here can register one: `IGraphicsDeviceService` is missing, so no Ruby key exists, and
`GraphicsDeviceManager` implements the interface explicitly. **Completing the type would ship one
that raises the moment `Game.Initialize` reaches it.** It was not forced.

`GamerServicesComponent` is blocked twice: it reaches `Game::get_Window`, still one of Game's 21
deferred members and itself blocked on the `RUNTIME_DATA` `GameWindow`, *and* the whole
`GamerServicesDispatcher` runtime.

## The frontier: 19 dependency-complete, 0 consumable

| Blocker | Types |
| --- | --- |
| `BCL_PROJECTION` | 5 |
| `BCL_PROJECTION` + `NATIVE_RUNTIME` | 3 |
| `NATIVE_RUNTIME` | 5 |
| `NATIVE_RUNTIME` + `RUNTIME_DATA` | 1 |
| `RUNTIME_DATA` | 5 |
| `IL_UNAVAILABLE` | 0 |

Two new reports sit beside the policy without changing it: `partialDependencySatisfiedCandidates`
(1 entry) and `ilOnlyBlockedCandidates` (13, six of them signature-complete).

## Game's remaining 21 missing members

`Tick`, `SuppressDraw`, `ResetElapsedTime`, `OnActivated`, `OnDeactivated`, `OnExiting`,
`Dispose(Boolean)`, `Finalize`, `ShowMissingRequirementMessage`, `LaunchParameters`,
`InactiveSleepTime`, `IsMouseVisible`, `TargetElapsedTime`, `IsFixedTimeStep`, `Window`, `IsActive`,
`Content`, `Activated`, `Deactivated`, `Exiting`, `Disposed`.

Every one is timing, activation, window, content or native disposal. None belongs to the component
slice and none was chipped at. Only the three-line component pass of `Game.Dispose` was implemented.

## Recommended next frontier

1. **`Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService`** — the frontier's own
   `partialDependencySatisfiedCandidates` entry, and the only one. An interface with **zero
   blockers**, no IL-only unmet dependency, whose single unmet signature dependency is the partial
   `GraphicsDevice` of which it reaches **no member**. Same abstract-contract shape `IGameComponent`,
   `IUpdateable`, `IDrawable` and `IGraphicsDeviceManager` already have: one property and four
   events. It would **not** make `DrawableGameComponent` completable — nothing implements or
   registers the service — but it is the precondition that type names.
2. **The producer decision for `IGraphicsDeviceService`.** This is the real architecture question and
   it is not covered by any prompt so far: `GraphicsDeviceManager` is one of the six deferred partial
   runtime types, its interface implementation is explicit, and registering it in `Game.Services`
   would make XNA's base `Initialize` call `LoadContent` — which the CNA host also delivers. Both
   halves must be resolved together.
3. **The `Dictionary`2` decision**, unchanged since Foundation 33 and still the last purely-decisional
   BCL blocker.
4. **A qualification artifact carrying the SDL3 platform, built from the pinned CNA commit** —
   unchanged and still needing a CNA checkout at `a09196a6…` that no other session is using.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`, not bare `Position`).
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`: a bare `rescue` does not catch an abstract contract member.
- **Ruby cannot give one method name two visibilities.** A CLR type with a public and a protected overload of the same name projects to one public arity-dispatching method, and the widening is recorded.
- **`::Monitor`, not `Mutex`, is the analogue of `lock (this)`.** `Monitor.Enter` is reentrant and Ruby's `Mutex` is not, so a handler that re-enters would deadlock.
- `ikdasm` indents a nested type inside its declaring type and closes it with the **short** name, quotes a name that is not a plain identifier, appends a generic parameter list it omits from the closing comment, wraps a long operand onto continuation lines, and declares a mixed-mode C++/CLI thunk with a `modopt(...)` return modifier **before** the method name. Any IL scanner anchored on column zero, on the full declared name, on a single operand line, or on the first identifier before a parenthesis will silently lose something.
- **A scanner anchored on one side of a token loses something too.** Native frontiers 2 and 3 hit this in the IL extractor; Foundation 35 hit it in the signature graph, where an unbounded prefix test both over- and under-matched. Bound a name on both sides.
- An IL reference spells a nested type `Parent/Child`; the reference contract and this binding spell it `Parent+Child`.
- An `implements` list is comma-separated, but a constructed generic carries commas of its own: split only at depth zero.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI. Native work is mostly an indirect `calli` through an unmanaged calling convention, not a classic P/Invoke.
- CNA's platform is a **build-time** selection, not a runtime one.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are merged by documented deterministic replay, which refuses to write unless re-serialising the pre-merge corpus reproduces its bytes exactly. **Twelve** corrections have been made this way, each proving every retained element unchanged.
