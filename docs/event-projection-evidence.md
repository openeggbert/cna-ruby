# Foundation 20 — the general Ruby event projection

Establishes how a CLR event reaches Ruby, adds the smallest `System.EventArgs` projection needed to
represent one faithfully, teaches the API verifier the `event` member kind, and closes the two
event-bearing XNA interfaces that decision unblocks.

## The mapping rule

    A CLR public event   T.EventName : System.EventHandler`1[TArgs]
    projects to exactly one public Ruby event reader   object.EventName
    whose value is the generic CNA::Runtime::Event subscription primitive.

```ruby
handler = object.EventName.add { |sender, args| ... }
object.EventName.remove(handler)
```

One CLR event identity, one Ruby event-reader identity, XNA spelling preserved. Never an
`add_EventName`/`remove_EventName` pair, never a writer `EventName=`, never a Proc, Array, callback
property or fake method. Raising is internal to the declaring implementation, so no consumer-facing
`emit`, `fire`, `trigger` or `call` exists.

`tools/api_compat/mapping-rules.json` already promised `"events": "retain identity; explicit
subscription mapping when implemented"`. This is that subscription mapping.

## `CNA::Runtime::Event`

`lib/cna/runtime/event.rb`. Whole public surface: `add` and `remove`.

| Concern | Behaviour |
| --- | --- |
| `add(callable = nil, &block)` | one handler, given as a callable or as a block, never both |
| return value | the handler itself, which is the token `remove` takes back |
| invalid handler | `ArgumentError` for none/both/wrong arity, `TypeError` for a non-callable |
| arity | a lambda or `Method` must accept `(sender, args)`; an ordinary `Proc` keeps Ruby's lenient rules |
| duplicates | permitted, exactly as a CLR multicast invocation list permits them |
| order | invocation order is registration order |
| `remove(handler)` | removes the **last** matching occurrence, which is what `Delegate.Remove` does |
| handler equality | Ruby `==`, so a `Proc` matches by identity and a `Method` matches by receiver+method, the closest analogue of CLR delegate equality |
| absent handler | harmless; `remove` answers `nil` |
| dispatch | over a snapshot, so subscribing or unsubscribing inside a handler cannot corrupt the invocation in flight |
| exceptions | never swallowed; the first raised exception propagates and the handlers behind it are not invoked |
| raising | `dispatch(sender, args)` is private; the declaring implementation reaches it through `__send__` |

No `<<`, `>>`, `subscribe`, `unsubscribe`, `clear`, `fire` or `trigger` alias exists. Each owner
instance owns its own invocation list, created lazily by the reader.

`CNA::Runtime::EventOwner` is the only sanctioned way to declare an event identity
(`xna_event` for a concrete owner, `xna_abstract_event` for an XNA interface contract). That is what
makes selected event identities *measurable* instead of merely present: `xna_event_identities`
reports what a projection declares, including what it inherits, and the verifier compares that set
against the selected contract.

## `System.EventArgs`

`nil` is not an acceptable EventArgs representation, so `CNA::Runtime::EventArgs` projects the two
public CLR identities `System.EventArgs` actually has — the parameterless constructor and the shared
static `Empty` instance — and nothing else.

It lives in the CNA runtime rather than a fabricated Ruby `::System` namespace, which is the rule
`mapping-rules.json` already applies to the enumerable projection ("without a fake System
namespace"). A test asserts no `::System` constant exists. This decision is deliberately narrow: no
`System.Type`, `IServiceProvider`, `Stream`, `TimeSpan`, `Dictionary`, `ReadOnlyCollection`,
`StringBuilder` or `SerializationInfo` mapping is implied or begun.

## Verifier projection

`ruby_projections` now answers `["instance:EventName"]` for `kind: "event"` — previously it answered
nothing, which is what let an event-bearing type have counted as complete while some of its public
identities projected to nothing at all. Three consequences follow automatically: a missing reader is
a `MISSING_MEMBER`, a runtime event identity nothing selects is an `UNEXPECTED_MEMBER`, and the
generic `Event#add`/`Event#remove` methods are never miscounted as XNA members.

`verify_runtime_events` adds the event-specific rules under `EVENT_MAPPING_MISMATCH`:

- the declared event set and the set registered through `CNA::Runtime::EventOwner` must be equal;
- no `add_EventName`, `remove_EventName` or `EventName=` identity may exist beside the reader;
- the reader's value, probed on an uninitialised instance, must be a `CNA::Runtime::Event` — or, on
  an abstract XNA interface, the same `NotImplementedError` every other member of that contract
  raises;
- `CNA::Runtime::Event`'s own public surface must stay exactly `add`/`remove`, checked once, so no
  consumer-facing raise helper can appear behind an event.

The strict report gained measured counters: `EVENT_IDENTITIES=4`, `EVENT_OWNER_TYPES=2`,
`EVENT_SUPPORT_TYPE=CNA::Runtime::Event`, plus an `eventIdentities` list naming each one.
`EVENT_MAPPING_MISMATCH` is 0.

### Mutation coverage

`test/test_event_projection.rb` applies every mutation and requires each to be reported: missing
event, renamed event, event projected as an ordinary mutable property, event projected as a writer
only, wrong support type (a `Proc`, an `Array`, `nil` and an `add`/`remove` lookalike), duplicate
extra event identity, `add_EventName` leakage, `remove_EventName` leakage, a public
`emit`/`fire`/`trigger`/`call`/`invoke`/`broadcast`/`notify`/`publish`/`raise_event`/`dispatch`
surface on the primitive, an event omitted from the verifier's expectations, and an event reader
declared outside the generic primitive.

The Foundation 18 safety assertion "no selected type declares an event" was correct while events had
no projection. It is replaced by the measured policy above.

## Completed types

| Interface | Ruby identities | Members |
| --- | --- | --- |
| `Microsoft.Xna.Framework.IUpdateable` | 5 | `Update`, `Enabled`, `UpdateOrder`, `EnabledChanged`, `UpdateOrderChanged` |
| `Microsoft.Xna.Framework.IDrawable` | 5 | `Draw`, `Visible`, `DrawOrder`, `VisibleChanged`, `DrawOrderChanged` |

Both project as abstract Ruby modules whose every member raises `NotImplementedError` naming its own
contract, exactly like the four Foundation 18 contracts. An interface declares an event identity and
never owns an invocation list, so its event readers raise like the rest. Local diagnostics zero on
each; no concrete type includes either module.

## The `EVENT_PROJECTION` blocker is retired

`tools/api_compat/analyze_dependencies.rb` no longer treats "declares a CLR event" as a reason to
defer a type. What remains of that blocker is measured elsewhere: whether the event's
`System.EventHandler`1[TArgs]` support type is projected by a complete type is `BCL_PROJECTION`, and
for a class the IL that decides *when* the event is raised is `BEHAVIOR_EVIDENCE`.

Completing `IUpdateable`/`IDrawable` made `System.EventHandler`1[System.EventArgs]` a mapped BCL
type, which removed the last event-related blocker from `GameWindow` (now `BEHAVIOR_EVIDENCE` only)
and from `Audio.Microphone` (now `BCL_PROJECTION` on `System.Byte[]` plus `BEHAVIOR_EVIDENCE`).

## Why the GameComponent family is still not implemented

Event projection was expected to unlock `GameComponent`, `DrawableGameComponent` and
`GameComponentCollection`. It does not, and the reason is measured rather than argued:

| Type | Unmet XNA dependencies |
| --- | --- |
| `GameComponent` | `Game` |
| `DrawableGameComponent` | `Game`, `GameComponent`, `Graphics.GraphicsDevice` |
| `GameComponentCollection` | `Game`, `GameComponent`, `GameComponentCollectionEventArgs` |

`Game` and `GraphicsDevice` are two of the six deferred partial runtime types: they sit on the
CNA native boundary and their selected surface is deliberately a fraction of the CLR type. None of
the three is even dependency-complete, so none appears on the frontier.

Independently, each is a class whose behaviour lives in XNA IL. The pinned reference contract is
public metadata only — `name`, `kind`, `access`, types, `get`/`set`, `add`/`remove` — and carries no
field values, no defaults and no method bodies. The exact facts a faithful `GameComponent` needs,
**none of which is available on this host**, are:

1. the constructor's default `Enabled` and `UpdateOrder` values;
2. whether the constructor rejects a null `Game`;
3. whether assigning a property its current value still raises the change event;
4. the order of the field write relative to the raise;
5. the `sender` a raise passes;
6. the `EventArgs` instance a raise passes;
7. what `OnEnabledChanged`/`OnUpdateOrderChanged`/`OnVisibleChanged`/`OnDrawOrderChanged` do beyond
   raising, and whether they are the only raise path;
8. when `Dispose(bool)` raises `Disposed`, and what `Dispose()`/`Finalize()` do around it;
9. `GameComponentCollection`'s `InsertItem`/`RemoveItem`/`SetItem`/`ClearItems` overrides and
   whether `ClearItems` raises `ComponentRemoved` per item.

Guessing these from conventional .NET patterns is exactly what this project refuses. The required
input is retained XNA 4.0 Windows IL, not a tool and not a package.

`behavior/xna40-event-projection-values.json` records the family's pinned event metadata as
`PURE_XNA_DERIVED` evidence so the deferral stays attributable.

## Structural movement

TARGET_TYPES 111 → 113, TARGET_MEMBERS 1613 → 1623, TOTAL_DIAGNOSTICS 330 → 328, MISSING_TYPE
146 → 144, COMPLETE_TYPES 105 → 107. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6,
`PROPERTY_MAPPING_MISMATCH` 1, `OVERLOAD_MAPPING_MISMATCH` 51, `EVENT_MAPPING_MISMATCH` 0, every
other category 0, allowlist 0, unmeasured 0.

Dependency-complete but blocked 40 → 38, consumable 0.

CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59, zero missing symbols, zero mismatches. This
milestone is pure Ruby and touches no native surface.

## Behaviour corpus

339 → 355 observations, 0 failures. Sixteen additive rows: six `EVENT_PROJECTION`, six
`EVENT_RUNTIME`, four extending the existing `INTERFACE_CONTRACT` group to the two new interfaces.
Six are `PURE_XNA_DERIVED` metadata, ten are `RUBY_MAPPING_QUALIFICATION`.

The upstream behaviour-corpus source (SHA-256 `398d0201…`) is still **absent** from this
reconstructed host. `tools/import_behavior_corpus.rb` gained the Foundation 20 merge path so a
future run against the real source reproduces the same observation set, but it was **not executed**.
The merge used the documented deterministic replay method, which refuses to write unless
re-serialising the pre-merge corpus reproduces its bytes exactly. That proof passed against
pre-merge SHA-256 `fc87b85cebf2c09de2b0a2ca33051d466f16c87ed57119165ba717c9ff2e3b21` (339
observations), and the merge is purely additive — no existing observation was altered.

## Verification

- Full Ruby suite: 547 runs / 19302 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 355 observations / 355 assertions / 0 failures.
- API verifier strict: 328 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean; the runtime/RBS consistency suite pins one event reader per CLR event,
  returning `::CNA::Runtime::Event`, with no writer and no `add_`/`remove_` pair declared.
- Native ABI: unchanged.
