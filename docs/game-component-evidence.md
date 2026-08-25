# Foundation 38 — `GameComponent`

`Microsoft.Xna.Framework.GameComponent`, fourteen Ruby identities, complete.

The first concrete component this binding ships, so it is where the engine Foundation 37 built stops
being exercised by fixtures and starts being exercised by the type it was written for.

## Authority

The pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256 `b5dffdd8…`. Pure managed: the hash-admitted
IL inventory records the type `nativeReachable: false` with no native entry point anywhere in it.
**No CNA symbol was added and no CNA source was touched** — the ABI stays 39 / 124 / 290 / 290 / 2 /
59.

## Four facts a summary would have got wrong

**1. The constructor has no null check.** `.ctor(Game game)` is twenty-one bytes with no branch:
`enabled = true` as a field initialiser, `Object..ctor()`, then `game = game`. So a component with no
`Game` is legal, and `Dispose` is written for it. `updateOrder` is never assigned and keeps the CLR
default `0`.

**2. Both setters suppress before they do anything, and write before they raise.**

```
if (field == value) return;
field = value;
OnEnabledChanged(this, EventArgs.Empty);
```

So setting a property to what it already holds raises nothing at all, and a handler always observes
the *new* value.

**3. `OnEnabledChanged` and `OnUpdateOrderChanged` declare a `sender` and ignore it.** Both hooks
take `(object sender, EventArgs args)` and their IL loads `ldarg.0` — `this` — as the delegate's
sender, with `ldarg.1` never read. A subclass calling the base with some other sender still raises
the event with the component itself. Reproduced, not corrected.

**4. There is no disposed flag anywhere in the type.** Disposing twice removes twice — the second
`Remove` answers `false` and is discarded — and raises `Disposed` **twice**.

## Dispose, exactly

```
Dispose()             = Dispose(true); GC.SuppressFinalize(this);
Dispose(bool disposing):
    if (!disposing) return;
    lock (this) {
        if (Game != null) Game.Components.Remove(this);   // result popped
        if (Disposed != null) Disposed(this, EventArgs.Empty);
    }
```

The removal is **before** the notification, so a `Disposed` handler sees the component already out of
`Game.Components`. Because the removal goes through `GameComponentCollection.RemoveItem`, the
collection's own `ComponentRemoved` fires first, inside the `Remove` call — a three-event ordering
that falls out of Foundation 35 and is tested.

`lock (this)` is `Monitor.Enter`, which is **reentrant**: a `Disposed` handler that disposes the same
component re-enters rather than deadlocking. Ruby's `Mutex` is not reentrant and `::Monitor` is, so
`::Monitor` is the exact analogue and a test drives the nested case.

## `Finalize`, and why nothing was invented for it

`Finalize()` is `try { Dispose(false); } finally { base.Finalize(); }`, and `Dispose(false)` returns
at its first instruction. So **the CLR finalizer for this type does nothing observable**, and the
Ruby projection does the same nothing.

Ruby's garbage collector never calls it: no `ObjectSpace.define_finalizer` is registered anywhere in
this binding and none was invented — which is also why `GC.SuppressFinalize` in `Dispose()` needs no
analogue. There is nothing to suppress. Both absences are asserted by scanning the library source
for the two names outside comments.

## The one thing Ruby cannot express

`Dispose()` is `public` and `Dispose(bool)` is `protected`. Ruby cannot give one method name two
visibilities, so the two CLR overloads project to **one public method dispatching on arity** — the
rule `mapping-rules.json` already applies to every other overload set — and the static contract
retains both signature identities, so no `OVERLOAD_MAPPING_MISMATCH` arises.

**The widening is recorded rather than hidden**: the protected overload is publicly reachable here
and is not in the CLR. It costs less than it looks, because the two bodies differ only by
`GC.SuppressFinalize`, which has no analogue — so `Dispose` and `Dispose(true)` genuinely coincide,
and a subclass extends the type the XNA way:

```ruby
class MyComponent < GameComponent
  def Dispose(disposing = true)
    release_my_own_things if disposing
    super
  end
end
```

## The interface contracts are really included

`GameComponent` includes the `IGameComponent` and `IUpdateable` modules, which is what `Game`'s
engine tests with `is_a?`. That is the faithful analogue of the CLR's `isinst`: a nominal interface
test needs a nominal Ruby relation, and duck-typing on member names would answer true for a type
that never declared the contract. Every member either module declares is overridden, so no abstract
`NotImplementedError` survives on a concrete component.

`System.IDisposable` is the third declared interface and contributes **no inclusion**, because
Foundation 36 measured it as a structural collapse: it declares one member, `Dispose()`, which this
type declares publicly, so the contract survives as that member and there is no module to include.

## The collapse's first observable consequence

`Game.Dispose(bool)` opens with

```
array = new IGameComponent[gameComponents.Count];
gameComponents.CopyTo(array, 0);
foreach (x in array) if (x is IDisposable) x.Dispose();
```

The **snapshot array** is what makes it safe: each component's own `Dispose` removes it from
`Game.Components`, so iterating the live collection would skip every other one.

`x is IDisposable` has no nominal Ruby analogue — Foundation 36 decided there is no constant. Under
that decision's own rule, *the contract survives as the member*, so testing for the member is the
projection of testing for the interface. A component that declares no `Dispose` is simply skipped,
and that is tested. This is the first place the collapse has an observable consequence, and it is
recorded here rather than discovered later.

Only those three lines of `Game.Dispose` belong to this slice and only they were implemented. Game's
own `Dispose(Boolean)`, `Finalize` and `Disposed` event stay in its missing list, and the rest of
that method is the native ownership chain the binding already had.

## `DrawableGameComponent` was re-evaluated and stays deferred

The frontier was regenerated after this milestone. `DrawableGameComponent` is **not**
dependency-complete: it depends on `Microsoft.Xna.Framework.Graphics.GraphicsDevice`, one of the six
deferred partial runtime types, and `Game` being partial is no longer what holds it back. It was not
forced.

## Scoreboard

| Metric | Foundation 37 | **Foundation 38** |
| --- | --- | --- |
| `TARGET_TYPES` | 140 | **141** |
| `TARGET_MEMBERS` | 1754 | **1768** |
| `COMPLETE_TYPES` | 134 | **135** |
| `MISSING_TYPES` | 117 | **116** |
| `TOTAL_DIAGNOSTICS` | 299 | **298** |
| `EVENT_IDENTITIES` / owners | 6 / 3 | **9 / 4** |
| Behaviour observations | 458 | **466** |
| Capability rows / contradictions | 91 / 0 | **92** / 0 |
| `MISSING_MEMBER` | 130 | 130 — Game's remainder is untouched |
| `PARTIAL_TYPES` | 6 | 6 |
| CNA ABI | 39 / 124 / 290 / 290 / 2 / 59 | unchanged |

Every other structural category stays 0, the allowlist stays 0 and no structural category is
unmeasured.

## A corpus correction

`disposable_collapse.no_invented_conventions` counted a fixed list of names against every
`Dispose`-bearing type, which made a real XNA identity look invented as soon as one shipped:
`GameComponent` declares a protected `Finalize` in its own contract. The operation now exempts a name
the type's **own reference contract** declares — the same rule its test twin uses — so the row
measures the collapse rather than a list of names. No observation data changed; the row's expected
values are the ones Foundation 36 recorded, and the replay proved every row unchanged.

## What this milestone does not claim

`DrawableGameComponent` is deferred, on a blocker the graph measures. Nothing registers a service,
no graphics device is fabricated, and Game's timing, activation, window, content and native disposal
members were not chipped at.
