# Continuation Evidence

## Exact current boundary

**Session start HEAD = `88e160e7`**, which was also `origin/develop`. That baseline already carries
Foundations 16 to 39, Native frontiers 1 to 3, and the evidence and publication-state corrections
that followed them — including the Foundations 34 to 39 publication sequence, which is published
history and no longer local to anything.

The sequence this session added on top of that baseline is **Foundations 40 to 43 plus the
associated producer-audit, defect-fix and handoff commits**. Resolve where it currently sits with

```sh
git rev-parse HEAD
git rev-parse origin/develop
git log --oneline origin/develop..HEAD    # empty once the sequence is published
```

rather than from a count written down here.

| Milestone | What it added | Types | Identities |
| --- | --- | --- | --- |
| 16–33, NF1–NF3 | see the published history | 51 | 268 |
| 34–39 | `Collection<T>`, `GameComponentCollection`, `IDisposable` collapse, the component engine, `GameComponent`, member-level dependency edges | 2 | 23 |
| 40 | `Graphics.IGraphicsDeviceService` + the interface-producer rule | 1 | 5 |
| — | `Game#Dispose` defect fix; `GraphicsDeviceManager` producer audit | 0 | 0 |
| 41 | the four canonical `Game` events + three raisers | 0 | 7 |
| 42 | `Game`'s four timing/presentation properties | 0 | 4 |
| 43 | `Game.SuppressDraw` and `Game.ResetElapsedTime` | 0 | 2 |

The rows are what each milestone added, not what is or is not published. Earlier revisions of this
file encoded publication state in the prose and in bolded rows, and it went stale twice — once
already corrected on `origin/develop` by the commit this session started from. A handoff outlives
the push that follows it, so state the **session-start baseline**, which never moves, and let git
answer everything that does.

Strict target **142 types / 1786 member identities**: **136 complete**, six partial native/runtime
types, 115 missing, **279 deferred diagnostics**. `MISSING_MEMBER` **117**, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1 (`GraphicsDevice::Viewport`, unrelated and pre-existing),
`OVERLOAD_MAPPING_MISMATCH` **46**, every other structural category 0, allowlist 0, unmeasured 0.
**17** event identities across **six** owner types.

CNA ABI **51 / 160 / 290 / 290 / 3 / 63** — up from 39/124/290/290/2/59, twelve additive bindings and
one new callback type, every symbol already exported by the reviewed library. Zero missing header
symbols, zero missing library symbols, zero mismatches. **No CNA source was changed and no new
native binary was built.**

## Foundation 40 — the contract, and the rule it forced

`Graphics.IGraphicsDeviceService` re-derived from the pinned `Graphics.dll`: one get-only
`GraphicsDevice` property and four events, all four `EventHandler`1<EventArgs>`, every method
`public hidebysig newslot specialname abstract virtual`. The four `.event` declarations are in the
order `DeviceDisposing, DeviceReset, DeviceResetting, DeviceCreated`, which is not alphabetical, and
the projection follows metadata order.

It was projectable while `GraphicsDevice` stayed partial because its `externalMemberReferences` are
**empty** — it names the device in a return position and calls no member of it.

**Completing it broke the frontier, and closing that is the larger half of the milestone.**
`DrawableGameComponent` immediately reported `partialDependencySatisfied` with **no blocker**, while
its `Initialize` still throws `InvalidOperationException(MissingGraphicsDeviceService)`. A producer
is not a type dependency; it is an *object* that conforms, which a type-level graph cannot see.

So conformance is measured. An interface has a producer when some type declares it in the pinned
contract, **and** is complete here, **and** has a Ruby class that actually includes the projected
module — the third being the only half that proves a live object would answer `is_a?`, which is what
the `GameServiceContainer` projection of CLR assignability tests. A candidate whose own IL **calls a
member of** a producerless interface carries `INTERFACE_PRODUCER_MISSING`. Calling is the precise
test: naming an interface in a signature needs no instance, calling one does.

No allowlist, no named type, asked of every interface — and it independently caught a second,
unrelated pair, `VertexDeclaration` on `IVertexType`. `blockerSummary` is byte-identical to
Foundation 39's, dependency-complete is still 19, consumable still 0, `selectedNext` still nil.

## The producer audit: deferred, and not for the expected reason

Full evidence in `docs/graphics-device-service-producer-audit.md`.

`GraphicsDeviceManager` implements `IGraphicsDeviceService`, `IDisposable` and
`IGraphicsDeviceManager`. Its constructor registers **`IGraphicsDeviceManager` first, then
`IGraphicsDeviceService`**, both under `this`, after an `ArgumentNullException` on a null game and an
`ArgumentException` duplicate check that tests **only** `IGraphicsDeviceManager`.

The five service members are **public** — implicit implementations. Only `IGraphicsDeviceManager`'s
three and `IDisposable.Dispose` are explicit. **So the private-protocol precedent was not needed and
was not invented.**

`get_GraphicsDevice` is `ldfld device`: null from construction until the first creation, non-null
after, null across a re-creation, null after disposal. `DeviceCreated` is raised at the tail of
private `CreateDevice`; the other three are relays of `GraphicsDevice.Disposing`, `.DeviceResetting`
and `.DeviceReset`. In every case the sender is the **manager** and the args are `EventArgs.Empty`.

**Every CNA signal the producer needs already exists.** `cna_graphics_device_manager_subscribe`
carries all four device events, and `cna_graphics_device_manager_create` — which this binding already
calls — "registers it as the game's graphics device manager **and graphics device service**".
Measured from inside every lifecycle callback: both services are registered **before the first
callback** and unregistered by disposal. `PRODUCER_RUNTIME_MISSING` could not be recorded.

**The blocker is an architecture conflict.** CNA's native `Game` *is* the XNA `Game`; its hook table
documents that `initialize` runs, then the runtime creates the device, then `load_content`. So Ruby's
`Game.Initialize` is the *body of the override*, and CNA has already registered both services, run
its own `HookDeviceEvents` and performed the conditional `LoadContent`. There are two service
containers, and the C ABI closes the gap deliberately: *"A removal cannot be undone from here, and
there is deliberately no registration route."*

Restoring XNA's exact `Initialize` tail was measured, not predicted:

```
device at initialize [nil?, IsDisposed, has borrowed handle]: false, false, true
LoadContent calls = 2
```

XNA calls it once, CNA delivers once, Ruby delivers once; registering makes it **two**. No guard can
hide it, because XNA's lifecycle has no such guard. **Outcome B, taken in full**: unregistered,
conformance unclaimed, `HookDeviceEvents` still omitted, contract still complete. The four device
events were deliberately **not** projected onto the manager even though CNA would supply them
faithfully — that would let the type claim conformance to a service nothing registers.

## The defect this audit found

A `Game` that owned a `GraphicsDeviceManager` **and had actually run** raised
`CNA::DisposedObjectError` from `Dispose`. `Game#Dispose` releases the manager before destroying the
host — correctly, per `cna_graphics_device_manager_create`'s "release it before the game" — and
`cna_game_destroy` then delivers one last `unload_content` whose prologue borrowed the device through
the just-released handle. A disposed manager now attaches no device, which is the same answer it
already gave for CNA's `CNA_RESULT_INVALID_STATE`. Two regression tests, both asserting the final
`unload_content` is still delivered rather than merely that nothing raised.

## Foundations 41–43 — the native Game lifecycle surface

Three facts the IL settles that a summary would get wrong:

- **`OnExiting` loads `ldnull`.** XNA raises `Exiting` with a **null sender** while `OnActivated` and
  `OnDeactivated` raise with `this`. The projection dispatches `nil`.
- **`InactiveSleepTime` accepts zero.** Its setter compares with `op_LessThan` while
  `TargetElapsedTime`'s uses `op_LessThanOrEqual`, so one refuses zero and the other does not —
  despite the CLR resource being named `InactiveSleepTimeCannotBeZero`. CNA's two routes agree.
- **`TargetElapsedTime`'s default is `FromTicks(0x28b0b)` = 166667 ticks, which is not `1.0/60`.** A
  test asserts the two Floats differ so nobody later "simplifies" it.

**`CNA_GameCallbacks::exiting` is the wrong signal for `Exiting`**, and only measurement shows it: it
fires on every teardown, including `RunOneFrame` that never exited and a `Game` destroyed without
running, while `CNA_GAME_EVENT_EXITING` fires only on a real loop exit. The C ABI says the callback
"can stop the game by failing, while these handlers only observe"; XNA's event cannot veto.

**`Disposed` is raised by `Dispose` itself**, not relayed, because CNA's signal only exists once a
host does and XNA raises the event for every disposal.

The four timing properties are **managed state** — every getter is one `ldfld` — so they answer on a
Game that never ran, and `CNA_GameCreateInfo` is now built from that state instead of a hardcoded
pair. `SuppressDraw`/`ResetElapsedTime` are the mirror image: operations on state CNA owns, so they
forward; before a host exists `ResetElapsedTime` is a *genuine* no-op and `SuppressDraw` is a pending
request delivered at creation.

Measured order over a real HEADLESS run:

```
initialize  load_content  begin_run  Activated  update  draw  update  Exiting  end_run
unload_content  Disposed
```

`Deactivated` never fires on this host and nothing fabricates one.

## Recorded deviations added by this sequence

- `Game#Dispose` is idempotent because native destruction is not repeatable, so `Disposed` is raised
  **once** where XNA's unguarded `Dispose(Boolean)` raises it per call. XNA's `Monitor.Enter(this)`
  belongs to `Dispose(Boolean)`, still missing, and is not taken.
- TimeSpan seconds are rounded to the nearest whole tick on the way down, not truncated.
- The native push routes are owner-thread bound where XNA's setters are not, so a timing setter
  raises off the owner thread once a host exists and does not before.

## Game's remaining one

`Content`, blocked on the missing `ContentManager`. Foundation 44 took `Tick` off this list, 45
`IsActive`, 46 `LaunchParameters`, 47 the three protected members and 48 `Window`.

## Recommended next frontier

1. **`Game.Tick` — a public architecture decision, not a binding.** `cna_game_tick` exists, but it is
   documented as "the canonical frame step `cna_game_run_one_frame` wraps; it **does not process host
   events**", and is refused from inside a lifecycle callback. Projecting it adds a second public
   frame-step entry point whose semantics differ from `RunOneFrame` in a way a consumer must be told
   about, plus a re-entrancy contract this binding has no precedent for.
2. **`Game.IsActive`.** `cna_game_get_is_active` answers the *field*; XNA's property is
   `isActive && !Guide.IsVisible`. On a host with no GamerServices they agree, but the projection
   would claim a property whose defining subtlety it cannot observe. Decide explicitly.
3. **The `Dictionary`2` decision**, unchanged and still the last purely-decisional BCL blocker. It
   now unblocks something concrete: `LaunchParameters` has a canonical CNA route for every operation
   and is blocked only on the type.
4. **The two-container question**, if a graphics-device producer is ever wanted. It cannot be
   resolved additively: the managed `Game`/`GameServiceContainer` and CNA's native pair are two
   objects playing the same role, and only CNA's is the one the lifecycle logic runs against.
5. **A qualification artifact carrying the SDL3 platform**, unchanged and still needing a CNA
   checkout at `a09196a6…`.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Position`).
- Setter methods cannot use Ruby's endless method definition syntax.
- `NotImplementedError` is a `ScriptError`: a bare `rescue` does not catch an abstract contract member.
- **Ruby cannot give one method name two visibilities.**
- **`::Monitor`, not `Mutex`, is the analogue of `lock (this)`.**
- `ikdasm` indents nested types, closes with the short name, quotes non-identifier names, wraps long
  operands, and puts a `modopt(...)` return modifier before the method name.
- **A scanner anchored on one side of a token loses something.** Bound a name on both sides.
- An IL reference spells a nested type `Parent/Child`; this binding spells it `Parent+Child`.
- An `implements` list is comma-separated; split only at depth zero.
- XNA's Framework and Graphics assemblies are mixed-mode C++/CLI; native work is mostly an indirect
  `calli`, not a classic P/Invoke.
- CNA's platform is a **build-time** selection.
- **A completed interface is not a provider.** The structural graph cannot see producers; that is
  what `INTERFACE_PRODUCER_MISSING` measures.
- **CNA's native `Game` is the XNA `Game`.** The Ruby `Game` is a callback façade over it, so any
  managed step CNA already performs would be performed twice.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still absent. Corpus additions are
  merged by documented deterministic replay, which refuses to write unless re-serialising the
  pre-merge corpus reproduces its bytes exactly. **Fifteen** corrections/merges have been made this
  way, each proving every retained element unchanged.
- The reconstructed Debian Ruby defaults `GEM_HOME` to the unwritable `/var/lib/gems/3.3.0`, so the
  template's `bundle install` needs one set; `~/deps/cna-ruby-template-bundle` is the standing one.
