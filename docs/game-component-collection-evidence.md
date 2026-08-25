# Foundation 35 — `GameComponentCollection`

`Microsoft.Xna.Framework.GameComponentCollection`, seven Ruby identities, complete.

The first shipped XNA type whose CLR base is a projected BCL generic, and the first concrete owner
of an event. Both of those had been proved only by verifier fixtures and abstract contracts until
now.

## Authority

The pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, disassembled with `ikdasm`,
plus the admitted mscorlib for everything the base class decides. No other binding's summary was
used as authority; where one was consulted it was a cross-check and the IL won.

## What the type is

```
.class public auto ansi sealed beforefieldinit Microsoft.Xna.Framework.GameComponentCollection
       extends [mscorlib]System.Collections.ObjectModel.Collection`1<class Microsoft.Xna.Framework.IGameComponent>
```

Sealed, two private delegate fields, one public parameterless constructor that is a single call to
the base, four `family virtual` overrides, two `private` raise helpers, two events. **It declares no
public member of its own.** Everything a consumer calls — `Count`, the indexer, `Add`, `Clear`,
`Contains`, `CopyTo`, `GetEnumerator`, `IndexOf`, `Insert`, `Remove`, `RemoveAt` — arrives from
`Collection<IGameComponent>`.

Ruby has class inheritance, so the projection is a real subclass of `CNA::Runtime::Collection` and
that surface really is inherited. The CLR type argument cannot live in the superclass expression, so
it is declared as `projects_elements "Microsoft.Xna.Framework.IGameComponent"` and the API verifier
measures it under `GENERIC_MAPPING_MISMATCH`. Foundation 29 could only prove that rule with
fixtures; `signatures.json` now contains exactly one type whose `baseType` starts with
`Collection`1`, and it is this one.

## The three orderings, each read out of the IL

This is the part a summary could not have supplied, because the three hooks disagree with each
other.

### `InsertItem(index, item)` — refuse, mutate, announce

```
IndexOf(item) != -1  ->  throw ArgumentException(CannotAddSameComponentMultipleTimes)
base.InsertItem(index, item)
item != null  ->  OnComponentAdded(new GameComponentCollectionEventArgs(item))
```

The duplicate check is `IndexOf`, so it is **element equality, not identity**. It runs before the
mutation and before any notification. The event fires **after** the component is already in the
collection — a handler reading `Count` sees the new value.

### `RemoveItem(index)` — read, mutate, announce

```
item = base[index]
base.RemoveItem(index)
item != null  ->  OnComponentRemoved(new GameComponentCollectionEventArgs(item))
```

The component is read **before** the removal, through the base indexer, so an out-of-range index
raises there and never reaches the mutation. The event fires **after**, so a handler reading `Count`
sees the component already gone.

### `ClearItems()` — announce everything, then mutate

```
for (i = 0; i < base.Count; i++)
    OnComponentRemoved(new GameComponentCollectionEventArgs(base[i]));
base.ClearItems();
```

The opposite of the other two. Every notification fires **before any mutation at all**, in index
order, and every handler sees the full `Count`. Two further details are in the IL and neither is
guessable:

- **`Count` is re-read on every iteration.** A handler that adds a component during `Clear` extends
  the loop, and that component is announced as removed too before being cleared with the rest.
- **There is no null check.** Unlike the other two hooks, `ClearItems` announces a null element,
  constructing a `GameComponentCollectionEventArgs` that carries null.

### `SetItem(index, item)` — refuse, unconditionally

Eleven bytes of IL with no branch: `newobj NotSupportedException; throw`. But it is reached
*through* `Collection<T>::set_Item`, which validates first, so the observable order is
read-only refusal, then range check, then this refusal. An out-of-range index answers `RangeError`
and never enters the hook.

## The null component

`Collection<IGameComponent>` admits null and the hooks' null checks guard the **notification**, not
the mutation. So:

| Operation | Result |
| --- | --- |
| `Add(nil)` | inserted, `Count` becomes 1, **no event** |
| `Add(nil)` again | `ArgumentError` — `IndexOf(null)` finds the first one, so it is a duplicate |
| `RemoveAt(0)` on a null | removed, **no event** |
| `Clear` with a null present | **event fires**, carrying null |

That last row is the one place the three hooks visibly disagree, and it falls out of `ClearItems`
having no null check where the other two do.

## Messages

Both refusals carry a localized `Resources` string in the CLR —
`CannotAddSameComponentMultipleTimes` and `CannotSetItemsIntoGameComponentCollection` — and neither
is reproduced. Neither names a parameter, so, exactly as `GameServiceContainer`'s assignability
failure does, the Ruby exception carries no message rather than an invented one.

## Events

The already-established projection, unchanged: one CLR public event, one public Ruby reader keeping
the XNA spelling, answering `CNA::Runtime::Event`. No `add_`/`remove_` pair, no writer, no consumer
-facing raise helper. `OnComponentAdded` and `OnComponentRemoved` are `private` in the CLR — not
`protected` — so neither is an identity a consumer or a subclass reaches, and raising stays internal
to the hooks.

The sender is the collection and the args are freshly constructed per notification, so no two
notifications share an args object. `GameComponentCollectionEventArgs` was reused exactly as
Foundation 24 completed it; its public API was not altered to suit this type.

Snapshot dispatch, registration order, last-occurrence removal and unswallowed exceptions are the
qualified semantics and this type inherits all of them. The consequence of the orderings is
testable: a handler that raises during `Add` leaves the component **in** the collection, one that
raises during `Remove` leaves it **out**, and one that raises during `Clear` leaves the collection
**untouched**.

## The element type

`Collection<IGameComponent>`'s type argument is a static CLR constraint. A Ruby class is not
statically generic, so it is carried as `projects_elements` metadata for the verifier *and* enforced
at the one point every insertion passes through, raising `TypeError` — the same boundary check
`GameComponentCollectionEventArgs` already ships, on the same type. Null is admitted because
`Collection<IGameComponent>` admits it.

## A frontier measurement correction

`GameComponentCollection` was reported as blocked on `Game` and `GameComponent`. It never depended
on either.

`analyze_dependencies.rb` decided whether a signature named a type with an **unbounded prefix**
test:

```ruby
signature.include?("[#{name}")
```

Any *longer* type name that merely starts with a shorter one matched it, and the Game family is full
of those. The signature

```
System.EventHandler`1[Microsoft.Xna.Framework.GameComponentCollectionEventArgs]
```

was therefore read as naming `Microsoft.Xna.Framework.Game` and
`Microsoft.Xna.Framework.GameComponent` as well.

This is the same class of blind spot Native frontiers 2 and 3 closed in the IL extractor — a scanner
anchored on one side of a token — seen in the signature graph, and it ran in **both** directions:

| | Edges | Types |
| --- | --- | --- |
| Spurious, removed | 18 | 15 |
| Missed entirely, now detected | 21 | 20 |

The missed half is the mirror image: a name followed by `[` matched nothing, so
`VertexElement[]` never named `VertexElement` and `IPackedVector`1[Alpha8]` never named
`IPackedVector`1`. A name is now required to be bounded on both sides by the delimiters a signature
really uses — `[`, `,`, `]`, `&` — with a nested `Parent+Child` deliberately still not matched by
its parent's name, because `type_dependencies` adds that edge separately.

**No frontier conclusion changed at the current state**: `dependencyCompleteCandidates` stays 19,
`consumableCandidates` stays 0, the blocker summary is identical and no candidate's dependency list
moved, because every type carrying a spurious edge was genuinely blocked by something else anyway.
What changed is that the graph is now right. Re-run against the Foundation 34 state, the corrected
analyzer reports `GameComponentCollection` with **zero blockers, zero unmet dependencies, as the
single consumable candidate and as `selectedNext`** — so this milestone was selected by the
frontier rather than in spite of it.

## Scoreboard

| Metric | Foundation 34 | **Foundation 35** |
| --- | --- | --- |
| `TARGET_TYPES` | 139 | **140** |
| `TARGET_MEMBERS` | 1745 | **1752** |
| `COMPLETE_TYPES` | 133 | **134** |
| `MISSING_TYPES` | 118 | **117** |
| `TOTAL_DIAGNOSTICS` | 302 | **301** |
| `EVENT_IDENTITIES` / owners | 4 / 2 | **6 / 3** |
| Behaviour observations | 435 | **445** |
| Capability rows / contradictions | 88 / 0 | **89** / 0 |
| `PARTIAL_TYPES` | 6 | 6 |
| `MISSING_MEMBER` | 132 | 132 |
| CNA ABI | 39 / 124 / 290 / 290 / 2 / 59 | unchanged |

Every other structural category stays 0, the allowlist stays 0 and no structural category is
unmeasured.

## A corpus correction

Two Foundation 20 rows censused this binding's own selection, which this milestone legitimately
grew. `event_projection.deferred_family.contract` carried, per type, one slot asserting the type was
not selected — the same over-reach the Foundation 22, 32 and 33 corrections removed — so that slot
was dropped, leaving only the pure XNA metadata about each type's events.
`event_projection.support_type.contract` snapshotted the whole selected event census, so like
Foundation 23's `bcl_projection.register` it could not survive that census growing; it now pins the
four identities Foundation 20 established, passed as args, plus the standing shape rule that every
selected event is an `EventHandler`1`. The deterministic replay proved every other element of those
rows, and every other row, unchanged, against pre-merge SHA-256
`08d3a3f5aff4a5fd08bbb78ef3d572b9ef97622dd7dfccb29f6eaae62f2eb6f2` / 435 observations.

## What this milestone does not claim

**Nothing puts a component in one.** No concrete `IGameComponent` type exists yet — `GameComponent`
is a later milestone — so every collection this binding can build is empty unless a consumer
supplies its own implementation of the contract. `Game.Components` does not exist yet either.

No CNA source was changed, no native symbol was added and the ABI is unchanged.
