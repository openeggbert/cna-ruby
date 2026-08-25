# Foundation 39 — the member-level half of the dependency graph

The frontier's signature graph can only see the **types** a public signature names. It answers
"`GameComponent` depends on `Game`" and stops. Two things follow that it structurally cannot see,
and both changed a conclusion this session had already acted on.

## What was wrong, in both directions

**A dependency on a partial type may already be met.** A partial type is a real Ruby class with a
real surface; what a dependent needs is the members it actually calls, not all of them.
`GameComponent`'s entire IL reaches **exactly one** `Game` member — `get_Components` — which
Foundation 37 completed. So Foundation 38 selected it against the letter of the candidate policy and
was right to; this milestone is where that stops being an assertion.

**A dependency may be invisible to a signature entirely.** `DrawableGameComponent`'s whole
device-service handshake lives in a **private field**, so the signature graph never saw
`IGraphicsDeviceService` at all. Read only through signatures the type looks blocked on `Game` and
`GraphicsDevice`, both of which are partial and both of whose reached members are complete — which
would have made it look ready. It is not: its `Initialize` throws
`InvalidOperationException(MissingGraphicsDeviceService)` unless a producer has registered the
service, and this binding has none.

## The measurement

`build_il_inventory.rb` already collects every `call` / `callvirt` / `newobj` / `ldftn` /
`ldvirtftn` / `jmp` operand to drive the native-reachability fixpoint. This milestone keeps the ones
that land on a pinned reference type **other than the owner** and records them per type as
`externalMemberReferences`. No new parsing, and the same normalisation the fixpoint already relies
on — a nested type spelled `Parent+Child`, a quoted name stripped.

```
MEMBER_LEVEL_EDGES = 3271   across 257 types
```

**Purely additive.** `TYPES_NATIVE_REACHABLE` stays 77, `NATIVE_ENTRY_POINT_METHODS` stays 254,
`TYPES_WITHOUT_IL` stays 0, and a diff proves **no prior per-type fact moved**.

## What the frontier does with it, and what it deliberately does not

The candidate policy is **not relaxed**. `dependencyComplete` still means every dependency is
complete, `selectedNext` still comes from `consumableCandidates`, and after the change:

| | Before | After |
| --- | --- | --- |
| `dependencyCompleteCandidates` | 19 | 19 |
| `consumableCandidates` | 0 | 0 |
| `blockerSummary` | — | identical |
| `selectedNext` | none | none |

What is added is two reports a maintainer can act on:

- **`partialDependencySatisfiedCandidates`** — every unmet dependency is a partial type, every
  member of it the candidate's own IL reaches is complete, and the IL reaches no unmet type the
  signature graph missed.
- **`ilOnlyBlockedCandidates`** — the other half: a candidate held back by a type only its IL
  reaches. Reported so the near-miss is visible instead of silently absent from the first list.

## The three verdicts that matter

### `GameComponent` — sound

```
Microsoft.Xna.Framework.Game::get_Components
```

One edge, and Foundation 37 completed it. Nothing else in the type touches `Game`.

### `DrawableGameComponent` — deferred, and now for the right reason

```
Microsoft.Xna.Framework.Game::get_Services                       (complete)
Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::…       (nine members, missing type)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::…               (none — zero edges)
```

It reaches **no member of `GraphicsDevice` at all**: it obtains the device from
`IGraphicsDeviceService.GraphicsDevice` and republishes it through its own property. Its `Draw`,
`LoadContent` and `UnloadContent` are each a bare `ret`. So the entire type *is* the device-service
handshake, and its `Initialize` is nine lines of subscription guarded by

```
if (deviceService == null) throw new InvalidOperationException(Resources.MissingGraphicsDeviceService);
```

Nothing in this binding can register one: `IGraphicsDeviceService` is a missing type, so no Ruby key
for it exists, and `GraphicsDeviceManager` is a deferred partial whose implementation of the
interface is explicit and therefore projects to no member. **Completing the type would ship one that
raises the moment `Game.Initialize` reaches it.** It was not forced.

### `GamerServicesComponent` — deferred, on two counts

```
Microsoft.Xna.Framework.Game::Exit           (complete)
Microsoft.Xna.Framework.Game::get_Services   (complete)
Microsoft.Xna.Framework.Game::get_Window     (still one of Game's 21 deferred members)
```

plus the whole `GamerServicesDispatcher`, which is the GamerServices runtime. So even the managed
half is blocked, and `Window` is itself blocked on `GameWindow`, a `RUNTIME_DATA` type.

## Six candidates that looked ready and are not

`ilOnlyBlockedCandidates` holds thirteen entries, and **six of them the signature graph called fully
dependency-complete**:

| Candidate | Blocked by, IL-only |
| --- | --- |
| `Graphics.TextureCollection` | `EffectPass`, `GraphicsResource`, `Texture2D`, `Texture3D`, `TextureCube` |
| `Graphics.SpriteFont` | `SpriteBatch` |
| `Content.ContentManager` | `ContentLoadException`, `ContentReader`, `TitleContainer` |
| `Graphics.EffectAnnotation` | `EffectParameter` |
| `Audio.SoundEffectInstance` | `SoundEffect` |
| `Audio.Cue` | `AudioEngine` |

The last two **strengthen Foundation 36 rather than contradict it**. That milestone reported both as
down to `NATIVE_RUNTIME` alone once `System.IDisposable` was collapsed; they were in fact blocked
twice over, and only one reason was visible. Both stay deferred either way.

## The one candidate the refinement clears

`Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService` — an **interface**, zero blockers, no
IL-only unmet dependency, and its single unmet signature dependency is the partial `GraphicsDevice`,
of which it reaches **no member**: it names the device as a property type and calls nothing on it.

That makes it the frontier's exact next step, and it is the same abstract-contract shape
`IGameComponent`, `IUpdateable`, `IDrawable` and `IGraphicsDeviceManager` already have. It would
**not** make `DrawableGameComponent` completable — nothing implements or registers the service — but
it is the precondition that type names, and it is now measured rather than guessed.

## Scoreboard

| Metric | Foundation 38 | **Foundation 39** |
| --- | --- | --- |
| `MEMBER_LEVEL_EDGES` | — | **3271** |
| Frontier reports | 5 lists | **7** |
| Behaviour observations | 466 | **473** |
| Capability rows / contradictions | 92 / 0 | **93** / 0 |
| `TYPES_NATIVE_REACHABLE` | 77 | 77 |
| `NATIVE_ENTRY_POINT_METHODS` | 254 | 254 |
| `dependencyCompleteCandidates` / consumable | 19 / 0 | 19 / 0 |
| `COMPLETE_TYPES` / `TOTAL_DIAGNOSTICS` | 135 / 298 | 135 / 298 |
| CNA ABI | 39 / 124 / 290 / 290 / 2 / 59 | unchanged |

No type was completed, no member was closed, no CNA source was changed. This milestone is
measurement, and its whole value is that two conclusions it touched were wrong in opposite
directions.
