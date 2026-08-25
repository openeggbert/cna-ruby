# Foundation 23 — the Input.Touch value types

Completes `TouchLocation` and `GestureSample` from the pinned
`Microsoft.Xna.Framework.Input.Touch.dll` IL (SHA-256 `b0585224…`), and makes the
`System.TimeSpan` projection measured. 19 Ruby identities, local diagnostics zero on both.

`tools/touch_location_reference_probe.cs` was written for a world where this behaviour was
unavailable. It is unnecessary: the IL settles every question it was going to ask, and no runtime
probe is needed to confirm what the instructions plainly say. The file is preserved.

## Why these two and not the rest of Input.Touch

`TouchPanel` and `TouchCollection` are what read a touch device. Neither is dependency-complete —
`TouchCollection+Enumerator` has no IL under a name the disassembler emits, so it is the frontier's
only `IL_UNAVAILABLE` entry — and nothing in this binding pumps touch input. Both stay absent.

`TouchLocation` and `GestureSample` are different: both are **publicly constructible** XNA value
types, both are pure managed with zero native reachability, and both have complete IL. A consumer
can construct and compare them without any device existing, which is exactly the contract this
binding can carry.

## TouchLocation

Seven private fields — `id`, `state`, `x`, `y`, `prevState`, `prevX`, `prevY`. Positions are stored
as four separate `Single` values, never as `Vector2` fields, so `Position` builds a fresh `Vector2`
on every read.

| Member | What the IL does |
| --- | --- |
| `.ctor(id, state, position)` | stores id, state, `position.X`, `position.Y`; then `prevState` = literal `0` (which is `Invalid`), `prevX` = `prevY` = `0`. No validation. |
| `.ctor(id, state, position, previousState, previousPosition)` | the same, with the previous triple stored. No validation. |
| `Id`, `State` | single field reads |
| `Position` | `new Vector2(x, y)` — a fresh value every call |
| `TryGetPreviousLocation(out)` | `brtrue` on `prevState`: when it is `Invalid`, fills the out value with id `-1` and everything else zero and returns **false**; otherwise fills it with this id, this `prevState` as its state, this `prevX`/`prevY` as its position, and an empty previous location of its own, and returns **true** |
| `ToString()` | `String.Format(CurrentCulture, "{{Position:{0}}}", Position)` → `{Position:{X:… Y:…}}` |
| `Equals(TouchLocation)` | compares **id, x, y, prevX, prevY** |
| `Equals(object)` | type test, then the typed overload |
| `GetHashCode()` | `id.GetHashCode() + x.GetHashCode() + y.GetHashCode()`, unchecked |
| `op_Equality` | compares **all seven fields**, including both states |
| `op_Inequality` | the same chain, negated |

### The quirk that is preserved rather than normalised

**`Equals` and `op_Equality` deliberately disagree.** `Equals` ignores `state` and `prevState`;
`op_Equality` compares them. Two locations differing only in state are `Equals` but not `==`. That
is what the IL says, so that is what the projection does, and the behaviour corpus pins both
answers side by side.

Every comparison is `bne.un`, so an unordered operand is never equal: a NaN coordinate makes a value
unequal to its own copy under both `Equals` and `==`. `GetHashCode` covers only id, x and y, so the
previous location and both states are outside the hash — equal values still hash equally, which is
what a Ruby `Hash` requires.

`TryGetPreviousLocation` answers `[found, previousLocation]`. The CLR fills its out parameter on
**both** branches, so returning only the location or only the flag would drop half the result. This
is the first selected member with one `out` and a non-void return; `mapping-rules.json` gains the
explicit rule, which is the same shape `Matrix#Decompose` already uses.

`==`, `eql?`, `hash` and `dup` come from `CNA::Runtime::ValueSemantics` over
`[Id, State, Position, previousState, previousPosition]`, which is exactly `op_Equality`'s seven
fields; `Equals` is defined separately because it is not.

The internal seven-argument constructor is `assembly`-scoped, is not part of the public contract,
and is not projected. Nothing needs it: both `TryGetPreviousLocation` branches are expressible
through the public three-argument form.

## GestureSample

Six `assembly` fields, one public constructor that is six assignments and a `ret`, and six get-only
property reads. No validation, no derived state, and **no declared `Equals`, `GetHashCode`,
`ToString` or operator** — so none is projected. Inventing one would claim a contract XNA does not
declare, and `ValueType.GetHashCode` is explicitly unspecified. This follows the
`TouchPanelCapabilities` precedent exactly. Struct-valued reads answer fresh copies, and `dup` /
`clone` carry the repository's struct value-copy policy.

## System.TimeSpan is now a measured projection

`GestureSample.Timestamp` is a `System.TimeSpan`. `GameTime` has projected that type as a Ruby
`Float` of seconds since Foundation 1, but only implicitly; the register now carries
`"System.TimeSpan" => "Float"` with a single shared validation, so a second consumer cannot drift
from the first. A tick count is not a binary64 `Float`, so the projection is exact only within
Float's 53-bit significand — documented as a `LANGUAGE_MAPPING_LIMITATION`, not hidden.

That is the whole BCL step: narrow, driven by a real otherwise-safe consumer, measured in the
verifier, and nothing else designed.

## Corpus correction

`bcl_projection.register` snapshotted the entire BCL register, so it could not survive the register
legitimately growing. It now pins only the three identities Foundation 21 established, passed as
arguments, and Foundation 23 adds its own row for `System.TimeSpan`. The replay proved each of those
three still maps exactly as recorded, that `System.Type` stays unprojected, and that no `::System`
namespace exists.

## Structural movement

TARGET_TYPES 119 → 121, TARGET_MEMBERS 1641 → 1660, TOTAL_DIAGNOSTICS 322 → 320, MISSING_TYPE
138 → 136, COMPLETE_TYPES 113 → 115. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6, every structural
mismatch category unchanged, allowlist 0, unmeasured 0. `BCL_PROJECTED_IDENTITIES` 3 → 4.

Frontier: 5 consumable, 26 blocked. CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59.

## What this claims nothing about

No `TouchPanel`, `TouchCollection`, gesture recognition, touch device, touch route or native touch
constant. No path in this binding produces a `TouchLocation` or a `GestureSample`, and
`TouchPanelCapabilities` still projects the CLR default struct value because nothing queries a
device.

## Verification

- Full Ruby suite: 596 runs / 20334 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 391 observations / 391 assertions / 0 failures; 9 additive rows in the new
  `TOUCH_VALUE` group.
- API verifier strict: 320 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
