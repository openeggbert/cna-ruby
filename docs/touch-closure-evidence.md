# Foundation 17 — Input.Touch managed closure

Closes `Microsoft.Xna.Framework.Input.Touch` as three managed value contracts, 17 Ruby XNA member
identities, with local diagnostics zero on each. No CNA ABI, native binding, touch device, gesture
recognition or partial-type member is added.

| Type | Kind | CLR | Ruby | Flags | Detail |
| --- | --- | --- | --- | --- | --- |
| `TouchLocationState` | enum | 5 | 4 | false | `Invalid=0`, `Released=1`, `Pressed=2`, `Moved=3` |
| `GestureType` | enum | 12 | 11 | true | mask `0x3FF`; declared `None=0` through `PinchComplete=512` |
| `TouchPanelCapabilities` | struct | 2 | 2 | — | `IsConnected` and `MaximumTouchCount`, both get-only |

The two enums go through the unchanged `CNA::Runtime::EnumValue` / `EnumType` policy and share the
pure managed enum battery in `test/test_pure_managed_enum_batch.rb`.

## Why this closure was deferred from Foundation 16 and taken whole here

Foundation 16 found 26 dependency-complete pure managed enums against a hard ceiling of 25 newly
completed types. The `Input.Touch` closure was the only non-arbitrary deferral unit, so it was held
back entire rather than split. Foundation 17 closes it together with its sibling struct.

## TouchPanelCapabilities is the CLR default value, not a device answer

The pinned contract declares two get-only properties and **no public constructor**. In CLR a struct
always has an implicit parameterless default, so `default(TouchPanelCapabilities)` — `IsConnected`
false, `MaximumTouchCount` 0 — is the entire reachable contract. That is what the Ruby class
projects.

This is not a fabricated capability answer. `TouchPanel.GetCapabilities` is the only thing that
populates the struct in XNA and it is deliberately absent, so nothing in this binding queries or
claims to query a touch device. The `input.touch` capability row records the subsystem as
`UNIMPLEMENTED_CNA_RUBY`, and a test asserts that row is never a `VERIFIED_NATIVE*` category.

`dup` and `clone` are the established language-only value-copy projections, matching
`GamePadCapabilities`; the verifier's allowlist covers exactly those and the two declared readers.

## GestureType flags shape

`None = 0` is declared in the pinned metadata, so the named zero was read rather than invented, and
XNA declares no `All`, `Drag` or `Complete` aggregate. The valid mask is the OR of the eleven
literals, `0x3FF`. `HorizontalDrag | VerticalDrag | FreeDrag` is the typed frozen composite 56 and
`coerce(56)` returns that same object; `coerce(0x400)` and `coerce(-1)` raise `RangeError`.

## Deliberately not implemented

`TouchPanel`, `TouchCollection`, `TouchLocation`, `GestureSample` and any gesture recognition,
touch input route or touch hardware claim. All four remain in `missingTypeNames`.

`TouchLocation` became dependency-complete *because of* this milestone — `TouchLocationState` and
`Vector2` are both complete and its signature names no unmapped BCL type. It is still blocked on
`BEHAVIOR_EVIDENCE`: `Equals`, `GetHashCode`, `ToString` and `TryGetPreviousLocation` are XNA IL,
and this host carries only the pinned public metadata snapshot. `tools/touch_location_reference_probe.cs`
is the fixture that would settle those semantics on a real XNA host; it must not be substituted by
guesswork.

## Structural movement

TARGET_TYPES 104 → 107, TARGET_MEMBERS 1585 → 1602, TOTAL_DIAGNOSTICS 334 ← 337, MISSING_TYPE
153 → 150, COMPLETE_TYPES 98 → 101. `MISSING_MEMBER` stays 132, `PARTIAL_TYPES` stays 6,
`PROPERTY_MAPPING_MISMATCH` stays 1, `OVERLOAD_MAPPING_MISMATCH` stays 51, every other category 0.

Suite 497 runs / 17844 assertions / 0 failures. Behaviour corpus 331 observations / 0 failures.
