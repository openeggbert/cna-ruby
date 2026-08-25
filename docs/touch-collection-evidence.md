# Foundation 31 — `TouchCollection` and its nested `Enumerator`

Two types, 18 Ruby identities, closed **together** because neither can be closed alone.

## Why the pair, and not one of them

`TouchCollection.GetEnumerator` returns `TouchCollection+Enumerator`, and the enumerator's `Current`
and `MoveNext` call `TouchCollection`'s `Item` and `Count`. The dependency runs both ways, so the
frontier can never select either: each has an unmet XNA dependency that is the other. Native
frontier 2 taught the analyzer to treat a nested type's declaring type as a public-signature
dependency, which is what made the pair classify honestly instead of looking like one consumable
type and one blocked one. Closing a mutually-dependent pair is a decision, not a queue pop.

The last thing standing in the way was a mapping, not a dependency: six of the collection's fifteen
members throw `System.NotSupportedException`, and this binding had no projection for it. Foundation
30 decided that, so this milestone is pure IL reading.

## The struct is eight slots and a count

The measured fields are `isConnected`, `locationCount`, and `location0` through `location7` — eight
individual `TouchLocation` fields, never a list. That is the entire reason the type has a hard
eight-location ceiling and why its indexer is an eight-way `switch` rather than an array read. The
Ruby projection keeps the ceiling and the count as separate state for the same reason.

## Constructor

`.ctor(TouchLocation[] touches)`:

- null → `ArgumentNullException("touches")`, constructed in this method's own IL with the parameter
  name as the `ldstr` operand → Ruby `ArgumentError` with message `"touches"`
- `ldlen; ldc.i4.8; ble.s` — eight elements are accepted, nine throw
  `ArgumentOutOfRangeException("touches")` → Ruby `RangeError` with message `"touches"`
- `isConnected` is set to the literal `true`, `locationCount` to 0, and all eight slots are zeroed
- each element is expanded through `TouchLocation.TryGetPreviousLocation`: when it answers a
  previous location, the entry carries that location's state and position; when it does not, the
  previous state is the literal `0` — `TouchLocationState.Invalid` — with a zero previous position

`AddTouchLocation` reads the count, increments it, and the **old** value selects the slot. A value of
8 or more selects nothing and stores nothing while still leaving the count incremented. The
constructor's ceiling makes that unreachable from the public surface, and it is preserved anyway
rather than tidied into something the IL does not say.

## Reads

| Member | Measured behaviour |
| --- | --- |
| `Count` | the `locationCount` field |
| `IsConnected` | the `isConnected` field |
| `IsReadOnly` | `ldc.i4.1; ret` — a literal `true`, no backing field |
| `Item[Int32]` | `index < 0 \|\| index >= Count` throws `ArgumentOutOfRangeException("index")`, then an eight-way switch |
| `IndexOf` | forward scan over `0...Count` using `TouchLocation::op_Equality`, else -1 |
| `Contains` | `IndexOf(item) < 0` negated — the same scan, never a separate comparison |
| `CopyTo` | `ArgumentNullException("array")`, then `ArgumentOutOfRangeException("arrayIndex")` for a negative index and again when `array.Length < arrayIndex + Count` |
| `FindById` | scan by `Id`; the out value is filled on **both** branches, with `initobj` — the CLR default `TouchLocation` — on failure |
| `GetEnumerator` | `ldobj` copies the collection struct into a new enumerator |

`IndexOf` using `op_Equality` matters, and the test pins it: `TouchLocation.Equals` and
`TouchLocation.op_Equality` deliberately disagree — `Equals` ignores both state fields — so a
`TouchLocation` that `Equals` answers `true` for is still **not found** by `IndexOf`. That divergence
was measured in Foundation 23 and this is the first member that depends on it.

`FindById` follows the established ref/out rule: the out parameter follows the Boolean return as an
ordered `Array`, because the CLR fills it on every branch and neither half of the result may be
dropped. On failure it answers the CLR default `TouchLocation` — `Id` 0, `State` `Invalid`, zero
position — not `nil`.

## The refusal to mutate

`Insert`, `RemoveAt`, `Add`, `Clear`, `Remove` and the `Item` setter are each a two-instruction body:

```
IL_0000:  newobj  instance void [mscorlib]System.NotSupportedException::.ctor()
IL_0005:  throw
```

They project to `raise CNA::Runtime::NotSupportedError`. The parameterless CLR constructor fills its
message from the localized framework resource `Arg_NotSupportedException`, which no XNA member
exposes observably, so no message is fabricated.

This is where Foundation 30's decision earns itself. `TouchCollection` is a read-only collection a
caller will *routinely* try to mutate, and the obvious Ruby mapping, `NotImplementedError`, descends
from `ScriptError` — so the natural

```ruby
begin
  touches.Add(location)
rescue => error
  ...
end
```

would not catch it. `CNA::Runtime::NotSupportedError` is a `StandardError`, and the test asserts both
that an ordinary `rescue` catches it and that a refused mutation changes nothing.

Note the contrast with `ReadOnlyCollection<T>` from Foundation 29, which refuses in the same way and
needs no Ruby exception at all: there the twelve refusals are *explicit interface implementations*,
so the projection of "the caller cannot mutate through this interface" is that no such member
exists. Here the six refusals are on the type's own **public** surface, declared by the reference
contract, so they must exist and must throw.

## Which exception the indexer raises

`TouchCollection`'s `get_Item` constructs `ArgumentOutOfRangeException("index")` in its own IL, so
the thrown-exception table applies and it raises `RangeError`. `ReadOnlyCollection<T>` and
`CurveKeyCollection` *forward* their indexer to a backing `IList<T>` and construct nothing, so the
condition belongs to this binding's own Ruby `Array` backing and raises `IndexError`. Who constructs
it decides; the rule is `bclProjection.thrownExceptions.whoConstructsItDecides`, added in
Foundation 30.

## The Enumerator

`assembly .ctor(TouchCollection collection)` stores the collection and sets `position` to `-1`. Its
only constructor is internal, so `new` is private under the constructor-free class rule Foundation 25
established, and the reference contract lists no constructor member for it.

- `Current` → `collection[position]` with **no guard of its own**. Reading it before the first
  `MoveNext` (`position` −1) or after exhaustion (`position == Count`) therefore raises exactly what
  the indexer raises — `RangeError` with message `"index"`.
- `MoveNext` → `position += 1`; `true` while below `Count`, otherwise **clamp** `position` to `Count`
  and answer `false`. The clamp is what stops a repeated `MoveNext` walking past the end.
- `Dispose` → the IL body is a bare `ret`. It releases nothing, resets nothing and does not stop
  enumeration; the test asserts that enumeration continues normally after it.
- `IEnumerator.Reset` exists in the IL as a **private explicit interface implementation**, outside the
  selected surface, so it is deliberately not projected.

`GetEnumerator` copies the collection struct, so two enumerators from the same collection advance
independently.

## Ruby language support, and how the verifier tells it apart

The class declares one Ruby identity of its own, `each`, and includes `Enumerable` — the same
arrangement `CNA::Runtime::ReadOnlyCollection` uses, and for the same reason: Ruby derives every
`Enumerable` method from `each` alone, and `each` is the single Ruby identity that carries CLR
`GetEnumerator`.

That needed a real rule rather than an exemption, because `verify_public_leaks` reported
`TouchCollection::each` as an `UNEXPECTED_MEMBER` — correctly, on the rules as they stood. The new
register `CNA::Runtime::LanguageSupport` maps a Ruby identity to the CLR identity it is derived from,
and the verifier admits it **only on a type that also projects that CLR identity**. `each` is
permitted where `GetEnumerator` is projected and nowhere else, so it can never quietly stand in for a
missing XNA member. It is a rule, not an allowlist of names.

## Nested-type naming

`TouchCollection+Enumerator` projects to
`Microsoft::Xna::Framework::Input::Touch::TouchCollection::Enumerator` — `NameMapper` splits a CLR
identity on both `.` and `+`, so the nested type lives inside its declaring type's Ruby constant.
The test asserts it does not leak into the `Touch` namespace and that no flattened
`TouchCollectionEnumerator` is invented.

## What moved

| Metric | Before | After |
| --- | --- | --- |
| `TARGET_TYPES` | 135 | **137** |
| `TARGET_MEMBERS` | 1714 | **1732** |
| `COMPLETE_TYPES` | 129 | **131** |
| `MISSING_TYPES` | 122 | **120** |
| `TOTAL_DIAGNOSTICS` | 306 | **304** |
| `UNEXPECTED_MEMBER` | 0 | 0 |
| Behaviour observations | 420 | **429** |
| Capability rows / contradictions | 85 / 0 | 86 / 0 |

And the frontier moved for the first time since Foundation 27:

| Frontier | Before | After |
| --- | --- | --- |
| dependency-complete | 20 | **21** |
| consumable | 0 | **1** |
| selection route | `none-consumable` | `global-consumable-rank` |
| selected next | none | **`Input.Touch.TouchPanel`** |

`TouchPanel`'s only unmet XNA dependencies were `TouchCollection` and its enumerator. With the pair
complete it is dependency-complete, its own IL reaches no native entry point, and no BCL type it
names is unmapped — so the frontier reports it consumable, which is the honest reading of its own
rule. Whether that reading survives contact with the IL is the next milestone's question, not this
one's.

## What this milestone does not claim

Nothing produces a `TouchCollection`. There is no `TouchPanel`, no gesture recognition, no touch
device and no touch route; the internal `Update` that XNA's input layer drives takes a native touch
state struct and is not projected. `TouchPanelCapabilities` still answers the CLR default struct
value rather than a device, and the CNA ABI is unchanged at 39 / 124 / 290 / 290 / 2 / 59 — no touch
symbol was bound and no CNA source was touched.
