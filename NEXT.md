# Continuation Evidence

## Exact current boundary

Foundations 16 to 21 are complete and qualified, and all six are **uncommitted**.

- **Foundation 16 — PURE MANAGED BATCH A**: 24 pure managed enums, 109 Ruby identities.
  17 Graphics, four in the new `Audio` namespace, three in the new `Media` namespace.
- **Foundation 17 — Input.Touch closure**: `TouchLocationState` (4), `GestureType` (11, flags, mask
  `0x3FF`, declared `None=0`), `TouchPanelCapabilities` (2, get-only, CLR default struct value).
- **Foundation 18 — interface contracts**: `IGameComponent` (1), `IGraphicsDeviceManager` (3),
  `IEffectMatrices` (3), `IEffectFog` (4) as abstract Ruby modules raising `NotImplementedError`.
- **Foundation 19 — dependency frontier**: no XNA type; a tested blocker classifier replaces the
  enum-only milestone selector.
- **Foundation 20 — event projection**: the general Ruby event mapping, `CNA::Runtime::Event`,
  `CNA::Runtime::EventArgs`, verifier support for `kind: "event"`, and `IUpdateable` (5) and
  `IDrawable` (5) as abstract Ruby modules.
- **Foundation 21 — BCL projection**: no XNA type; a measured `CNA::Runtime::BclProjection` register
  and the general rule that a CLR exception base projects to a Ruby exception superclass rooted at
  `StandardError`.

Strict target is 113 types / 1623 member identities: 107 complete, six partial native/runtime types,
144 missing, 328 deferred diagnostics. `MISSING_MEMBER` is unchanged at 132 across all six
milestones, `PARTIAL_TYPES` 6, `PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, every
other structural category 0, allowlist 0, unmeasured 0. Four selected event identities across two
owner types, `EVENT_MAPPING_MISMATCH` 0; three BCL projected identities, two exception bases.

CNA ABI unchanged throughout: 38 / 122 / 290 / 290 / 2 / 59, zero missing symbols, zero mismatches.
`lib/cna/runtime/enum.rb` is byte-identical to Foundation 15.

Evidence: `docs/foundation-16-pure-managed-batch-evidence.md`, `docs/touch-closure-evidence.md`,
`docs/interface-contract-evidence.md`, `docs/foundation-19-dependency-frontier-evidence.md`,
`docs/event-projection-evidence.md`, `docs/bcl-projection-evidence.md`,
`docs/generated/dependency-frontier.md`.

## The frontier is blocked on proprietary input alone

`tools/api_compat/analyze_dependencies.rb` reports `SELECTED_NEXT=none`. 38 dependency-complete
types remain and **every one of them carries `BEHAVIOR_EVIDENCE`**.

| Blocker | Types | Nature |
| --- | --- | --- |
| `BEHAVIOR_EVIDENCE` | 23 | unavailable proprietary input |
| `BCL_PROJECTION` + `BEHAVIOR_EVIDENCE` | 15 | unavailable proprietary input, plus a BCL cluster no unblocked type needs |

`EVENT_PROJECTION` was retired in Foundation 20. No remaining candidate is blocked on a decision
this project has failed to make. **This is the material change since Foundation 19**: the two open
architecture questions are answered, and what is left is input, not judgement.

## What is actually missing

Retained **Microsoft XNA Framework 4.0 Windows assemblies**. Proprietary reference data, not a tool
and not a package; no Debian package can substitute for it. `tools/api_compat/reference/PROVENANCE.md`
pins public metadata only — `kind`, `name`, `access`, types, `get`/`set`, `add`/`remove` — with no
field values, no defaults and no method bodies.

`tools/touch_location_reference_probe.cs` is ready to run against a real Windows XNA runtime and
would settle `TouchLocation` (12 identities), the highest-value item in the group. Do not substitute
guessed values for its output.

The behaviour-corpus upstream source (SHA-256 `398d0201…`) is also absent, so corpus additions are
merged by the documented deterministic replay that refuses to write unless re-serialising the
pre-merge corpus reproduces its bytes exactly.

## What each blocked cluster still needs

- **XNA exception types (8)** — every declared member of every one is a constructor. Unknown: the
  `Message` the parameterless constructor produces, whether the message/`innerException` forms
  forward unchanged, and whether any validates its arguments. `ContentLoadException` and
  `StorageDeviceNotConnectedException` additionally need `SerializationInfo`/`StreamingContext`.
  The Ruby base mapping already exists and is measured, so these drop in the moment IL is available.
- **`GameComponent` family (3)** — not even dependency-complete: `GameComponent` needs
  `Game`; `DrawableGameComponent` needs `Game`, `GameComponent`, `GraphicsDevice`;
  `GameComponentCollection` needs `Game`, `GameComponent`, `GameComponentCollectionEventArgs`.
  `Game` and `GraphicsDevice` are two of the six deferred partial runtime types on the CNA native
  boundary. Independently, each needs constructor defaults, same-value emit suppression, mutation
  and event ordering, sender identity, the `EventArgs` instance, the `On*Changed` hooks, and
  `Dispose`/`Disposed` timing — all IL.
- **Value types and framework handles (`TouchLocation`, `PresentationParameters`, `DisplayMode`,
  `EffectAnnotation`, `AudioListener`, `AudioEmitter`, `AudioCategory`, `RendererDetail`,
  `GestureSample`, `MediaSource`, `Video`, `TextureCollection`, `FrameworkDispatcher`,
  `GameWindow`, `Microphone`)** — construction, comparison, string and lifecycle IL.
- **Constructor-free classes (`ResourceCreatedEventArgs`, `ResourceDestroyedEventArgs`,
  `TextureCollection`, `Video`)** — a class has no CLR default value, so unlike a struct it cannot
  be described by metadata alone. The struct exemption was deliberately **not** extended; projecting
  one would be a hollow identity that nothing can instantiate.
- **BCL clusters not designed** — `System.Attribute` (5 `ContentSerializer*` types), `System.Type` +
  `IServiceProvider` (`GameServiceContainer`), `System.IO.Stream` (`TitleContainer`,
  `ContentManager`), `SerializationInfo`, `StringBuilder`, `ReadOnlyCollection`, `Dictionary`,
  `ExpandableObjectConverter`. Each was left alone because no otherwise-unblocked type needs it, so
  none can be designed against a real consumer.

## Established general mappings

### Event projection

    A CLR public event   T.EventName : System.EventHandler`1[TArgs]
    projects to exactly one public Ruby event reader   object.EventName
    whose value is the generic CNA::Runtime::Event subscription primitive.

`add(callable | &block)` answers the token `remove` takes back; duplicates permitted; invocation
order is registration order; dispatch runs over a snapshot; exceptions are never swallowed;
`remove` deletes the last matching occurrence as `Delegate.Remove` does; the public surface is
exactly `add`/`remove` and raising is private. Never `add_EventName`/`remove_EventName`, never a
writer. On an abstract contract the reader raises `NotImplementedError`.

**No event in this binding is ever raised.** The only owners are `IUpdateable` and `IDrawable`.

### BCL projection

`CNA::Runtime::BclProjection` is the measured register. `System.EventArgs` →
`CNA::Runtime::EventArgs`; `System.Exception` and `System.Runtime.InteropServices.ExternalException`
→ `StandardError`. The verifier resolves and shape-checks every entry; the frontier consumes the
same register. No fabricated Ruby `::System` namespace. An intermediate BCL exception class the XNA
surface never names collapses to the nearest projected ancestor.

## Recommended next architectural frontier

There is no safe managed XNA work left on this host. In priority order:

1. **Supply retained XNA 4.0 Windows assemblies.** Everything else is downstream of this. With them,
   the eight exception types are the cheapest cluster (24 identities, base mapping already in place),
   then `TouchLocation` via the existing probe.
2. **Native/CNA expansion** if the goal is the `Game` component family or any partial-type
   remainder. Each remaining member of the six partial types needs real lifecycle, timing, device or
   drawing behaviour; a `Game.Activated` event that never fires would be fake lifecycle.
3. **`System.Attribute`** is the largest BCL cluster by type count (5), but every one of those types
   also needs constructor IL, so it unlocks nothing on its own.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Setter methods cannot use Ruby's endless method definition syntax; abstract writers use a normal body.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`: a bare `rescue` does not catch an abstract contract member.
- The upstream behaviour-corpus source (SHA-256 `398d0201…`) is absent. Corpus additions are merged by documented deterministic replay, which refuses to write unless re-serialising the pre-merge corpus reproduces its bytes exactly.
