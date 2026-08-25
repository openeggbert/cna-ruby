# Foundation 40 — `Graphics.IGraphicsDeviceService`, and the producer it does not imply

Two things happen here and they must not be confused with each other. The first is a contract:
`Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService` is projected as an abstract Ruby module,
exactly as the four interface contracts before it were. The second is a measurement: completing
that contract made the dependency graph start reporting a type as satisfied that **cannot be used**,
because a contract is not a provider. Closing that gap is the larger half of this milestone.

## The exact CLR surface

Re-derived from the pinned `Microsoft.Xna.Framework.Graphics.dll`, SHA-256
`560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`, disassembled with `ikdasm`.

```
.class interface public abstract auto ansi beforefieldinit
       Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService
```

No base, no other interface, and **nine methods**, every one of them
`public hidebysig newslot specialname abstract virtual` with an empty body:

| CLR member | Kind | Type |
| --- | --- | --- |
| `GraphicsDevice` | property, **get only**, `public` | `Graphics.GraphicsDevice` |
| `DeviceDisposing` | event, add + remove | `System.EventHandler`1<System.EventArgs>` |
| `DeviceReset` | event, add + remove | `System.EventHandler`1<System.EventArgs>` |
| `DeviceResetting` | event, add + remove | `System.EventHandler`1<System.EventArgs>` |
| `DeviceCreated` | event, add + remove | `System.EventHandler`1<System.EventArgs>` |

All four events are the same closed generic delegate, which the prompt asked to be verified rather
than assumed — the IL confirms it. Five public identities, one property and four events; the eight
accessor methods are the events' own `.addon`/`.removeon`, and one CLR event projects to one Ruby
reader, so they contribute no separate identity.

Two details worth recording because they matter to a future producer and to nothing else here:

- The add/remove accessors are `cil managed **synchronized**` — the CLR's `[MethodImpl(Synchronized)]`,
  which is `lock(this)`. On an abstract declaration there is no body to synchronise, so it costs the
  projection nothing; a concrete producer would need `::Monitor`, the reentrant analogue this
  binding already established for `GameComponent.Dispose`.
- The `.event` declaration order is `DeviceDisposing`, `DeviceReset`, `DeviceResetting`,
  `DeviceCreated`, which is **not** alphabetical and not the order the prose usually lists them in.
  The projection declares them in metadata order.

## The Ruby projection

`Microsoft::Xna::Framework::Graphics::IGraphicsDeviceService`, beside `IEffectMatrices` and
`IEffectFog`, which is where the `Graphics`-namespaced interface contracts already live.

```ruby
module IGraphicsDeviceService
  extend CNA::Runtime::EventOwner

  def GraphicsDevice = raise(NotImplementedError, "IGraphicsDeviceService#GraphicsDevice")
  xna_abstract_event :DeviceDisposing, "IGraphicsDeviceService#DeviceDisposing"
  xna_abstract_event :DeviceReset,     "IGraphicsDeviceService#DeviceReset"
  xna_abstract_event :DeviceResetting, "IGraphicsDeviceService#DeviceResetting"
  xna_abstract_event :DeviceCreated,   "IGraphicsDeviceService#DeviceCreated"
end
```

Five public instance methods and nothing else: no constant, no singleton method, no protected or
private member, no setter, no `add_`/`remove_` pair. `xna_abstract_event` is the same declaration
`IUpdateable` and `IDrawable` use — it registers the event *identity* with the verifier so the
projection is measured rather than trusted, and defines a reader that raises. **The module owns no
invocation list.** An interface declares an event; it never holds one.

Nothing fabricates a `GraphicsDevice`. The property raises like every other member.

## Why a partial dependency did not block it

The interface's only type dependency is `GraphicsDevice`, one of the six deferred partial runtime
types. Foundation 39's member-level graph is what makes it projectable anyway:

```
Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService
  externalMemberReferences: []          <- no edges at all; every method body is empty
  partialTypeDependencies:
    Graphics.GraphicsDevice  reachedMembers: []  reachedButMissing: []
```

The interface **names** `GraphicsDevice` in a return position and **calls** no member of it. Naming
a type is not calling one, and that distinction is the whole content of `partialDependencySatisfied`.
Foundation 39 reported this type as the single candidate that satisfied it; Foundation 40 built it.
The regression tests re-derive both halves from the IL inventory rather than recalling them, so the
rule cannot quietly regress to *any reference to a partial type blocks*.

## What completing it broke, and the general rule that fixes it

The moment the interface became a complete type, `DrawableGameComponent` reported:

```
partialDependencySatisfied: true
blockers: []
```

Every structural test passed. And the type is unusable: its `Initialize` is

```csharp
if (deviceService == null)
    throw new InvalidOperationException(Resources.MissingGraphicsDeviceService);
```

The graph could not see that, and the reason is structural rather than accidental: **a producer is
not a type dependency.** It is an *object* that conforms. Every type the graph knows about was
present; what was absent was an instance.

So conformance is now measured. An interface has a producer when some type

1. declares it in the pinned reference contract, **and**
2. is complete in this projection, **and**
3. has a Ruby class that actually `include`s the projected module.

All three are required. The third is the only one that proves a live object would answer `is_a?`,
which is exactly what the `GameServiceContainer` projection of CLR type assignability tests. A
candidate whose own IL **calls a member of** an interface with no producer carries the new
`INTERFACE_PRODUCER_MISSING` blocker. Calling is the precise test: naming an interface in a
signature needs no instance, while calling one does.

The rule names no type and carries no allowlist, and it is asked of every interface. That it is
general is not asserted — it independently caught a second, unrelated pair:

| Candidate | Producerless interface |
| --- | --- |
| `Microsoft.Xna.Framework.DrawableGameComponent` | `Graphics.IGraphicsDeviceService` |
| `Microsoft.Xna.Framework.Graphics.VertexDeclaration` | `Graphics.IVertexType` |

No existing conclusion moved: `blockerSummary` is byte-identical to Foundation 39's, the
dependency-complete count is still 19, `consumableCandidates` is still 0, and `selectedNext` is
still nil.

## The scoreboard

| | Before | After |
| --- | --- | --- |
| `TARGET_TYPES` | 141 | **142** |
| `TARGET_MEMBERS` | 1768 | **1773** |
| `COMPLETE_TYPES` | 135 | **136** |
| `MISSING_TYPES` | 116 | **115** |
| `TOTAL_DIAGNOSTICS` | 298 | **297** |
| `EVENT_IDENTITIES` | 9 | **13** |
| `EVENT_OWNER_TYPES` | 4 | **5** |
| `PARTIAL_TYPES` | 6 | 6 |
| `MISSING_MEMBER` | 130 | 130 |

Every other structural counter stayed 0, `ALLOWLIST_ENTRIES` stayed 0 and
`UNMEASURED_STRUCTURAL_CATEGORY` stayed 0. The CNA ABI is untouched at
**39 / 124 / 290 / 290 / 2 / 59**: no native symbol was bound and no CNA source was changed.

## What this milestone does *not* claim

It registers nothing. `Game.Services` holds no key for the service and answers `nil` for it, no
projected type includes the module, none of the four events is ever raised by anything, and
`DrawableGameComponent` remains a missing type. The contract exists; the service does not.
