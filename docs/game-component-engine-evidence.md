# Foundation 37 — `Game.Components`, `Game.Services` and the managed component engine

Two XNA identities closed on `Game`, and the private engine behind them implemented exactly.

These are the **first two members any of the six deferred partial runtime types has ever lost**.
Both are pure managed state, and that is the decision the milestone rests on.

## Authority

The pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256 `b5dffdd8…`, plus the admitted mscorlib for
`List<T>.BinarySearch`. The CNA callback order was measured against the reviewed
`libcna_c_api.so` rather than read out of its header.

## Why these two are managed, and where the boundary really is

CNA owns the native game host, the frame loop, the window and the device. It does **not** own the
component list. `get_Components` and `get_Services` are one `ldfld` each; the collection is a sealed
`Collection<IGameComponent>` and the container is a `Dictionary<Type, object>` wrapper. Nothing in
either reaches a native entry point, so routing them through the C ABI would invent a boundary the
IL does not have.

The consequence is testable and is tested: both work on a `Game` that has never been run, both
answer the same object every time, and using them creates no native host.

**The ABI is unchanged at 39 / 124 / 290 / 290 / 2 / 59.** No CNA symbol was added and no CNA source
was touched.

## The construction order

The `.ctor` is 338 bytes and its order is preserved exactly where this binding performs a step:

| # | XNA step | Here |
| --- | --- | --- |
| 1 | the five private component lists (field initialiser) | ✔ |
| 2 | `gameServices = new GameServiceContainer()` (field initialiser) | ✔ |
| 3 | `Object..ctor()` | ✔ |
| 4 | `FrameworkDispatcher.Update()` | recorded, see below |
| 5 | `EnsureHost()` | deferred — this binding creates the host lazily |
| 6 | `launchParameters = new LaunchParameters()` | `LaunchParameters` is missing |
| 7 | `gameComponents = new GameComponentCollection()` | ✔ |
| 8 | `gameComponents.ComponentAdded += GameComponentAdded` | ✔ |
| 9 | `gameComponents.ComponentRemoved += GameComponentRemoved` | ✔ |
| 10 | `content = new ContentManager(gameServices)` | `ContentManager` is missing |
| 11 | `host.Window.Paint += Paint` | `GameWindow` is missing |
| 12 | the clock and four `TimeSpan` fields | native timing |

So **`Services` exists before `Components`**, both exist by the time the constructor returns, and
every step this binding does not perform is blocked on a missing type or on lifecycle CNA owns.
None of them touches component state.

## The engine, member by member

All four handlers are `private` in the CLR and stay private here; none is an XNA identity. What a
consumer observes is the order `Update` and `Draw` visit components in.

### The comparers are not a total order, and that is load-bearing

`UpdateOrderComparer.Compare` and `DrawOrderComparer.Compare` are the same five branches:

```
x == null && y == null -> 0;   x == null -> 1;   y == null -> -1
x.Equals(y)            -> 0
x.Order < y.Order      -> -1
otherwise              -> 1
```

It answers `0` **only** for an equal object — never for two different components sharing an order.
So `Compare(existing, item)` is `-1` exactly while `existing.Order < item.Order` and `1` otherwise,
which makes `BinarySearch` a **lower bound** over the order rather than an arbitrary hit. That is
what the walk after it then converts into an upper bound. Had the comparer answered `0` for equal
orders, every insertion site would behave differently.

`List<T>.BinarySearch` itself was read rather than assumed:

```
lo = 0; hi = Count - 1
while (lo <= hi) {
    mid = lo + ((hi - lo) >> 1)
    order = comparer.Compare(array[mid], value)
    if (order == 0) return mid
    if (order  < 0) lo = mid + 1 else hi = mid - 1
}
return ~lo
```

wrapped in a `catch (Exception)` that rethrows `InvalidOperationException("InvalidOperation_
IComparerFailed", inner)`. A component whose order getter raises therefore surfaces as `RuntimeError`
with the original as its Ruby cause — measured, and tested.

### `GameComponentAdded`

1. `inRun ? component.Initialize() : notYetInitialized.Add(component)` — for **every** component,
   including one that is neither updateable nor drawable.
2. if `IUpdateable`: `i = BinarySearch(...)`; **if `i >= 0`, skip everything**, subscription
   included; else `i = ~i`, walk forward past every element with an equal `UpdateOrder`,
   `Insert(i, u)`, `u.UpdateOrderChanged += ...`.
3. the same for `IDrawable`, `DrawOrder` and `DrawOrderChanged`.

Insertion is therefore **stable**: components sharing an order run in the order they were added.

### `GameComponentRemoved`

1. `if (!inRun) notYetInitialized.Remove(component)` — the result is popped, so removing something
   never queued is harmless, and once the game is running the queue is not touched at all.
2. remove from `updateableComponents`, unsubscribe `UpdateOrderChanged`.
3. the same for the drawable list.

### `UpdateableUpdateOrderChanged` / `DrawableDrawOrderChanged`

The component is taken from **`sender`**, not from the args. Remove, then the same search-and-walk,
so a component whose order changes lands after everything that already has the new order.

The `i >= 0` early return would drop the component from the list. It is reachable only when the
search finds a component the removal did not, which needs an equality that is not identity. XNA's
behaviour, reproduced rather than corrected.

### `Game.Initialize`

```
HookDeviceEvents();
while (notYetInitialized.Count != 0) { notYetInitialized[0].Initialize(); notYetInitialized.RemoveAt(0); }
if (graphicsDeviceService != null && graphicsDeviceService.GraphicsDevice != null) LoadContent();
```

The drain loop is exact: `Initialize` is called **before** the removal and `Count` is re-read every
iteration. So a component added by another component's `Initialize` is picked up by the same loop,
and a component whose `Initialize` raises stays at the head of the queue and the drain resumes there.
Both are tested.

The first and third lines are the graphics/device lifecycle this binding does not have.
`HookDeviceEvents` reads `Services.GetService(typeof(IGraphicsDeviceService))` — a missing type with
no Ruby key, so nothing can register one — and the third line is guarded by the same field. They are
separable from the drain loop, which sits between them and touches nothing they touch, so the
managed part is implemented in its exact position with nothing faked.

### `Game.Update` and `Game.Draw`

```
for (i = 0; i < updateableComponents.Count; i++) currentlyUpdating.Add(updateableComponents[i]);
for (j = 0; j < currentlyUpdating.Count; j++) { u = currentlyUpdating[j]; if (u.Enabled) u.Update(gameTime); }
currentlyUpdating.Clear();
FrameworkDispatcher.Update();
doneFirstUpdate = true;
```

The **snapshot copy** is what makes mutation during the pass safe: a component added or removed by
another component's `Update` takes effect from the next frame. `Enabled` is **not** snapshotted — it
is read immediately before each call, so a component disabled earlier in the same pass is skipped in
that pass. There is **no try/finally** around the `Clear`, so a raising component leaves the snapshot
populated and the next pass appends to it; that is XNA's behaviour and it is reproduced rather than
corrected. `Draw` is the same shape over `drawableComponents` and `Visible`, with no dispatcher pump
and no first-frame flag.

Two steps of `Update` are deliberately not performed, and both are recorded:

- **`FrameworkDispatcher.Update()`.** The canonical CNA C ABI documents
  `cna_framework_dispatcher_update` as pumping "the framework-wide per-frame work **the game loop
  normally drives**", and the CNA host this `Game` delegates its loop to already drives it every
  frame — so a managed call here would pump the same queue a second time. It would also impose this
  binding's recorded `FrameworkDispatcher` deviation (a live CNA `Game` on its owner thread) on
  `Game.Update`, which XNA's does not have, so `super` would start failing on a `Game` that has never
  run. The identity itself stays projected and callable exactly as Native frontier 1 qualified it.
- **`doneFirstUpdate = true`.** A private field whose only readers, `Tick` and `DrawFrame`, are the
  native timing loop CNA owns here. Carrying it would be state nothing reads.

`Draw` needs no device: the base decides *which* components are visited and each component's own
`Draw` decides what, if anything, it renders. No `GraphicsDevice` behaviour is fabricated and none
is required to observe the ordering.

## The GameHost callback-order audit

Measured against the reviewed CNA library, not read out of the header.

| | Order |
| --- | --- |
| **XNA `RunGame`** | `CreateDevice` → `Initialize()` *(→ `LoadContent()` when a device service exists)* → `inRun = true` → `BeginRun()` → `Update()` → loop → `EndRun()` |
| **CNA, measured** | `initialize` → `load_content` → `begin_run` → `update` → `begin_draw` → `draw` → `end_draw` → … → `exiting` → `end_run`; `unload_content` at destroy |

**The orders agree.** The one structural difference is *who* calls `LoadContent`: XNA's base
`Initialize` does, CNA delivers it as its own callback. It costs nothing here, because XNA's call is
guarded by an `IGraphicsDeviceService` this binding cannot register — so the guard is false, the
base calls nothing, and the host's callback is the only one. **Nothing is called twice and nothing
is skipped.**

That is a recorded future boundary rather than a permanent fact: a milestone that registers an
`IGraphicsDeviceService` would make the guard true and would then have to resolve the double call.

`RunOneFrame` delivers no `begin_run`, which matches XNA — `RunOneFrame` calls `host.RunOneFrame()`
directly and never enters `RunGame`, where `BeginRun` lives.

### Where the in-run flag is raised

XNA raises `inRun` in `RunGame`, **outside** `Initialize`, and clears it in a `finally`. Keeping it
in the driver is what makes it survive a subclass that overrides `Initialize` without calling
`super`, so `CNA::Runtime::GameHost` owns it here for the same reason.

Its position is measured, not transcribed. In XNA both managed steps — `Initialize` and, inside it,
`LoadContent` — run while `inRun` is still false. CNA delivers `load_content` as a separate callback
right after `initialize`, so the faithful place to raise the flag is **after `LoadContent` returns**.
A component added during either step is then queued rather than initialised on the spot, exactly as
in XNA, and one added afterwards is initialised immediately.

## Ruby `super` is the base-call mechanism, and nothing else is

Ruby has real class inheritance, so `super` **is** `base.Update(gameTime)`. No `GameBaseUpdate`,
`GameBaseDraw` or `GameBaseInitialize` helper exists and none was invented; a test asserts that.

The host invokes the virtual Ruby method **once** and never runs the base itself, so a subclass
chooses whether, when and how many times the base component pass happens:

```ruby
class MyGame < Game
  def Update(game_time)
    tick_my_own_state          # before
    super(game_time)           # the base component pass
    read_what_components_did   # after
  end
end
```

Three cases are proved, twice each — once by calling the protected hook directly and once by
running the real native loop:

| Subclass | Base component pass |
| --- | --- |
| overrides and omits `super` | **does not run** |
| overrides and calls `super` | runs once, between the subclass's own work |
| calls `super` twice | runs twice, a complete pass each time |

The nine lifecycle hooks keep the CLR's `protected` visibility, so a consumer cannot drive the loop
by hand.

## The hooks that stay no-ops, because their IL is

`BeginRun`, `EndRun`, `LoadContent` and `UnloadContent` are each `{ ret }` — one instruction — in the
pinned assembly. They stay no-ops because that is what they are, not because nothing better was
available. `BeginDraw` answers `true` and `EndDraw` does nothing, both because their only other
branch depends on a `GraphicsDeviceManager` whose `IGraphicsDeviceManager.BeginDraw`/`EndDraw` are
explicit interface implementations and so project to no member.

## Scoreboard

| Metric | Foundation 36 | **Foundation 37** |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1752 | **1754** |
| `MISSING_MEMBER` | 132 | **130** |
| `TOTAL_DIAGNOSTICS` | 301 | **299** |
| Game's missing members | 23 → 21 | **21** |
| Behaviour observations | 449 | **458** |
| Capability rows / contradictions | 90 / 0 | **91** / 0 |
| `COMPLETE_TYPES` / `PARTIAL_TYPES` | 134 / 6 | 134 / 6 |
| CNA ABI | 39 / 124 / 290 / 290 / 2 / 59 | unchanged |

### Game's remaining 21

`Tick`, `SuppressDraw`, `ResetElapsedTime`, `OnActivated`, `OnDeactivated`, `OnExiting`,
`Dispose(Boolean)`, `Finalize`, `ShowMissingRequirementMessage`, `LaunchParameters`,
`InactiveSleepTime`, `IsMouseVisible`, `TargetElapsedTime`, `IsFixedTimeStep`, `Window`, `IsActive`,
`Content`, `Activated`, `Deactivated`, `Exiting`, `Disposed`.

Every one is timing, activation, window, content or native disposal — none belongs to the component
slice, and none was chipped at.

## What this milestone does not claim

**No component type ships yet.** `GameComponent` is the next milestone; everything above is exercised
with fixtures that implement `IGameComponent`, `IUpdateable` and `IDrawable` directly. **Nothing
registers a service**: a freshly constructed `Game`'s container is empty and no member of this
binding calls `AddService` anywhere.
