# Foundation 18 — managed interface contracts

Closes four event-free XNA interfaces as Ruby modules, 11 Ruby XNA member identities, local
diagnostics zero on each.

| Interface | Ruby identities | Members |
| --- | --- | --- |
| `Microsoft.Xna.Framework.IGameComponent` | 1 | `Initialize` |
| `Microsoft.Xna.Framework.IGraphicsDeviceManager` | 3 | `CreateDevice`, `BeginDraw`, `EndDraw` |
| `Microsoft.Xna.Framework.Graphics.IEffectMatrices` | 3 | `World`, `View`, `Projection` (get+set, `Matrix`) |
| `Microsoft.Xna.Framework.Graphics.IEffectFog` | 4 | `FogEnabled`, `FogStart`, `FogEnd`, `FogColor` (get+set) |

XNA interfaces project to Ruby modules whose members raise `NotImplementedError` naming their own
contract, exactly as the `IPackedVector` / `IPackedVectorOfT` contracts already do. Get-only
properties project a reader; get+set properties project reader and writer; a test asserts the
projected accessors match the declared `get`/`set` pair in both directions.

`IEffectMatrices` and `IEffectFog` are the two highest fan-out dependency-complete types in the
whole remaining reference surface — five deferred types each name them — so this is dependency-first
work rather than leaf work.

## Why only four interfaces

`IUpdateable` and `IDrawable` are dependency-complete and otherwise safe, but each declares two CLR
events (`EnabledChanged`/`UpdateOrderChanged`, `VisibleChanged`/`DrawOrderChanged`) of type
`System.EventHandler`1[System.EventArgs]`.

**No selected type in this binding has ever contained an event member.** The verifier's projection
table returns no Ruby projection for `kind: "event"`, so selecting an event-bearing type would let
it count as complete while two of its five public identities projected to nothing at all. That is
precisely the "complete because diagnostics disappeared" failure this project rejects, so both were
deferred and a test asserts no selected type anywhere declares an event.

Deciding how a Ruby consumer subscribes to and unsubscribes from an XNA event is a new public-API
architecture, not something inferable from existing policy. It is recorded as the
`EVENT_PROJECTION` blocker and needs an explicit decision.

## No partial runtime type includes a contract

`GraphicsDeviceManager` implements `IGraphicsDeviceManager` in XNA, but it is one of the six
deferred partial runtime types and its selected surface declares only four identities. Including
the module would add `CreateDevice`, `BeginDraw` and `EndDraw` as public members that surface does
not declare. A test asserts none of the six partial types includes any interface contract, and
`MISSING_MEMBER` stays 132.

## Deliberately not implemented

`GameComponent`, `DrawableGameComponent`, `GameComponentCollection`, `GameServiceContainer`,
`GameWindow`, `Effect`, `BasicEffect`, `EffectParameter`, `DirectionalLight`, `IEffectLights`,
`IEffectSkinning`, `IVertexType`, `VertexDeclaration`. Projecting an abstract contract implies no
implementation of it.

## Structural movement

TARGET_TYPES 107 → 111, TARGET_MEMBERS 1602 → 1613, TOTAL_DIAGNOSTICS 334 → 330, MISSING_TYPE
150 → 146, COMPLETE_TYPES 101 → 105. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every other category 0.

Suite 510 runs / 18422 assertions / 0 failures. Behaviour corpus 339 observations / 0 failures.
