# Foundation 11 GraphicsProfile evidence

Foundation 11 closes exactly `Microsoft.Xna.Framework.Graphics.GraphicsProfile`. The pinned XNA
4.0 Windows runtime metadata contains one enum and three CLR identities. The established Ruby
exclusion of the synthetic `value__` storage field leaves exactly two Ruby XNA identities. No
constructor, method, property, event, or operator is declared by this selected type.

## Exact contract

| Type | CLR identities | Expected Ruby | Target | Local diagnostics | Kind |
| --- | ---: | ---: | ---: | ---: | --- |
| `GraphicsProfile` | 3 | 2 | 2 | 0 | non-flags enum, underlying `System.Int32` |

The exact namespace is `Microsoft::Xna::Framework::Graphics`. There is no root-framework alias and
no nested alias under `GraphicsDevice` or `GraphicsDeviceManager`. The two explicit pinned values
are:

| Name | Raw value |
| --- | ---: |
| `Reach` | 0 |
| `HiDef` | 1 |

Metadata records `kind=enum`, `underlyingType=System.Int32`, `baseType=System.Enum`, `sealed=true`,
and `flags=false`. `require "microsoft/xna/framework/graphics"` exposes the type without loading a
native library.

## Ordinary-enum Ruby mapping

The runtime uses the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType` policy. `Reach`
and `HiDef` are typed, frozen, canonical instances. `coerce(0)` and `coerce(1)` return the
corresponding named instances; coercing either existing profile returns that same object.

This is an ordinary enum, not a flags enum. The established Ruby projection rejects undefined raw
integers such as `-1` and `2` with `RangeError`, even though CLR enum storage can physically contain
an unnamed Int32. Nil, String, Float, Object, and cross-type enum values raise `TypeError` rather
than receiving implicit name or integer conversion. Values from `GraphicsDeviceStatus`,
`DisplayOrientation`, `SurfaceFormat`, `SpriteSortMode`, `PlayerIndex`, and `GamePadDeadZone`
neither coerce nor compare as a `GraphicsProfile`. Inherited `|` and `&` entry points reject
composition because the type is not flags.

Inherited Ruby `to_s`, `inspect`, and `to_i` are language support only. They do not add XNA
identities. No `ToString`, `HasFlag`, `FeatureLevel`, `SupportsHiDef?`, `Reach?`, `HiDef?`, alias,
or third enum value is declared. `constants(false)` contains exactly `Reach` and `HiDef`;
`value__` is absent. The RBS projection contains exactly those two constants, with no `untyped`,
catch-all, flags operator, device-property declaration, or constructor change.

## Structural strict-zero matrix

The selected type has zero local diagnostics in every measured category:

| Category | Count | Category | Count |
| --- | ---: | --- | ---: |
| `MISSING_MEMBER` | 0 | `UNEXPECTED_MEMBER` | 0 |
| `TYPE_KIND_MISMATCH` | 0 | `BASE_MAPPING_MISMATCH` | 0 |
| `INTERFACE_MAPPING_MISMATCH` | 0 | `FIELD_MAPPING_MISMATCH` | 0 |
| `PROPERTY_MAPPING_MISMATCH` | 0 | `METHOD_SIGNATURE_MAPPING_MISMATCH` | 0 |
| `PARAMETER_MAPPING_MISMATCH` | 0 | `RETURN_MAPPING_MISMATCH` | 0 |
| `OVERLOAD_MAPPING_MISMATCH` | 0 | `GENERIC_MAPPING_MISMATCH` | 0 |
| `ENUM_VALUE_MISMATCH` | 0 | `FLAGS_MAPPING_MISMATCH` | 0 |
| `EVENT_MAPPING_MISMATCH` | 0 | `OPERATOR_MAPPING_MISMATCH` | 0 |
| `LANGUAGE_MAPPING_MISMATCH` | 0 | `INTERNAL_TYPE_LEAK` | 0 |
| `RAW_HANDLE_LEAK` | 0 | `PUBLIC_NATIVE_FFI_LEAK` | 0 |
| `ALLOWLIST_ENTRIES` | 0 | `UNMEASURED_STRUCTURAL_CATEGORY` | 0 |

Focused verifier fixtures detect a missing type, wrong namespace, wrong kind, wrong Int32
underlying type, accidental flags metadata, each wrong raw value, missing `HiDef`, exposed
`value__`, an extra enum value, an unexpected public helper, and selected-surface leakage of both
deferred `GraphicsProfile` properties. Generic verifier logic remains unchanged and no allowlist
was introduced.

The global strict scoreboard moves exactly as derived: target types 76→77, target identities
1460→1462, diagnostics 370→369, missing types 181→180, and complete types 69→70. Reference and
expected totals do not change. Missing members remain 135; the same seven partial types, one
property mismatch, and 53 overload mismatches remain unchanged. Every previously-zero global
category stays zero.

## Behavior provenance and managed boundary

The compact `GRAPHICS_PROFILE` behavior group adds two observations. One `PURE_XNA_DERIVED`
observation records enum kind, non-flags metadata, Int32 underlying type, and both exact values.
One `RUBY_MAPPING_QUALIFICATION` observation covers typed/frozen instances, canonical coercion,
undefined and non-Integer rejection, cross-type safety, rejected flags operations, language
strings, and exact public constants. The complete corpus is 259 observations / 259 assertions with
zero failures: 256 XNA-derived facts and three Ruby-mapping qualifications.

The focused enum suite runs with `CNA_NATIVE_LIBRARY` unset and passes 5 runs / 69 assertions. It
does not construct `Game`, `GraphicsDevice`, `GraphicsDeviceManager`, a renderer, or a lifecycle
callback.

## Explicitly deferred scope

`GraphicsDevice.GraphicsProfile` and `GraphicsDeviceManager.GraphicsProfile` remain missing
properties, and their missing-member counts are unchanged. The existing internal
`GraphicsDevice` construction path is unchanged; no XNA constructor overload is selected or
implemented. No cached/default Reach or HiDef state, profile selection, renderer query, graphics
feature-level detection, shader-model inference, texture-limit check, or hardware capability
claim exists.

The milestone changes no CNA source, ABI function, native constant, manifest entry, Fiddle
signature, layout, callback, or native conversion. ABI verification remains 38 bound functions,
122 signature measurements, 290 C and 290 Ruby layout measurements, 2 callbacks, and 59 constants,
with zero missing header/library symbols and zero ABI mismatches. The capability classification is
only `VERIFIED_MANAGED` for the enum; it does not claim Reach or HiDef hardware support.

## Release qualification

RBS 3.4.0 validation passes, runtime/RBS consistency passes 11 runs / 1,701 assertions, and the
verifier mutation/self-test suite passes 63 runs / 116 assertions. Normal strict remains red only
for the 369 genuine deferred diagnostics; leak-only passes. The complete native-backed suite
passes 213 runs / 4,385 assertions with no failure, error, or skip. The focused native integration
suite passes 14 / 528 and covers Keyboard, Mouse, GamePad, lifecycle, and wrong-thread paths.

Stress retains 20 Game, Texture2D, SpriteBatch, and Game-recreation cycles; 50 Mouse and GamePad
state calls; and 20 GamePad capability calls. Crashes, observed use-after-free, and observed
double-free are all zero. Sanitizers were not run and remain honestly `NOT_RUN`. No controller was
connected, so positive controller state/capabilities and physical vibration remain
`HARDWARE_PENDING`.

The final package hash, isolated exact-gem consumer results, and unchanged-template results are
recorded in `docs/generated/package-report.json` and `docs/qualification-foundations-34-39.json`.
That second file was `docs/generated/qualification-report.json` when this was written; it was moved
out of `generated/` in Foundation 99, because it is the hand-authored record of one session rather
than something a tool produces, and nothing had regenerated it in sixty milestones. What lives at
the old path now is generated by `tools/run_qualification.rb`.
