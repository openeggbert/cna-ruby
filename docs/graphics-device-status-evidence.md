# Foundation 10 GraphicsDeviceStatus evidence

Foundation 10 closes exactly `Microsoft.Xna.Framework.Graphics.GraphicsDeviceStatus`. The pinned
XNA 4.0 Windows runtime metadata contains one enum and four CLR identities. The established Ruby
exclusion of the synthetic `value__` storage field leaves exactly three Ruby XNA identities. No
constructor, method, property, event, or operator is declared by this selected type.

## Exact contract

| Type | CLR identities | Expected Ruby | Target | Local diagnostics | Kind |
| --- | ---: | ---: | ---: | ---: | --- |
| `GraphicsDeviceStatus` | 4 | 3 | 3 | 0 | non-flags enum, underlying `System.Int32` |

The exact namespace is `Microsoft::Xna::Framework::Graphics`. There is no root-framework alias and
no nested alias under `GraphicsDevice` or `GraphicsDeviceManager`. The three explicit pinned values
are:

| Name | Raw value |
| --- | ---: |
| `Normal` | 0 |
| `Lost` | 1 |
| `NotReset` | 2 |

Metadata records `kind=enum`, `underlyingType=System.Int32`, `baseType=System.Enum`, `sealed=true`,
and `flags=false`. `require "microsoft/xna/framework/graphics"` exposes the type without loading a
native library.

## Ordinary-enum Ruby mapping

The runtime uses the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType` policy.
`Normal`, `Lost`, and `NotReset` are typed and frozen. `coerce(0)`, `coerce(1)`, and `coerce(2)`
return their corresponding canonical named instances; coercing an existing status returns that
same typed value.

This is an ordinary enum, not a flags enum. The established Ruby mapping rejects undefined raw
integers such as `3` with `RangeError`, even though CLR enum storage can physically contain an
unnamed Int32. Non-Integer and cross-type enum coercion raises `TypeError`. Values from
`DisplayOrientation`, `SpriteEffects`, `Buttons`, `SurfaceFormat`, and `PlayerIndex` neither coerce
nor compare as a `GraphicsDeviceStatus`. Inherited `|` and `&` entry points reject composition
because the type is not flags; they never produce a combined status.

Inherited Ruby `to_s`, `inspect`, and `to_i` are language support only. They do not add XNA
identities. No `ToString`, `HasFlag`, alias (`OK`, `DeviceLost`, or `NeedsReset`), or helper is
declared. `constants(false)` contains exactly `Normal`, `Lost`, and `NotReset`; `value__` is absent.
The RBS projection contains exactly those three constants, with no `untyped`, catch-all, flags
operator, or device-property declaration.

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
underlying type, accidental flags metadata, each wrong raw value, missing `NotReset`, exposed
`value__`, an extra enum identity, and selected-surface leakage of the deferred
`GraphicsDevice.GraphicsDeviceStatus` property. Generic verifier logic remains unchanged and no
allowlist was introduced.

The global strict scoreboard moves exactly as derived: target types 75→76, target identities
1457→1460, diagnostics 371→370, missing types 182→181, and complete types 68→69. Reference and
expected totals do not change. Missing members remain 135; the same seven partial types and their
one property plus 53 overload mismatches remain unchanged. Every previously-zero global category
stays zero.

## Behavior provenance and managed boundary

The compact `GRAPHICS_DEVICE_STATUS` behavior group adds two observations. One
`PURE_XNA_DERIVED` observation records enum kind, non-flags metadata, Int32 underlying type, and
the three exact values. One `RUBY_MAPPING_QUALIFICATION` observation covers typed/frozen instances,
canonical coercion, undefined-value rejection, cross-type safety, rejected flags operations,
language strings, and exact public constants. The complete corpus is 257 observations / 257
assertions with zero failures: 255 XNA-derived facts and two Ruby-mapping qualifications.

The focused enum suite runs with `CNA_NATIVE_LIBRARY` unset and passes 5 runs / 70 assertions. It
does not construct `Game`, `GraphicsDevice`, a renderer, or any lifecycle callback.

## Explicitly deferred scope

`GraphicsDevice.GraphicsDeviceStatus` remains a missing read-only property and the
`GraphicsDevice` missing-member count is unchanged. No fake `Normal` return, device status cache,
status polling, lost-device transition, not-reset transition, reset lifecycle, `Reset`, or
`Present` behavior exists. `GraphicsDeviceManager`, `GraphicsProfile`, `GraphicsAdapter`,
`PresentationParameters`, `DeviceLostException`, and `DeviceNotResetException` are unchanged and
unimplemented.

The milestone changes no CNA source, ABI function, native constant, manifest entry, Fiddle
signature, layout, callback, or native conversion. ABI verification remains 38 bound functions,
122 signature measurements, 290 C and 290 Ruby layout measurements, 2 callbacks, and 59 constants,
with zero missing header/library symbols and zero ABI mismatches. The capability classification is
only `VERIFIED_MANAGED` for the enum; it does not claim device-loss detection or reset support.

## Release qualification

RBS 3.4.0 validation passes, runtime/RBS consistency passes 10 runs / 1,669 assertions, and the
verifier mutation/self-test suite passes 57 runs / 102 assertions. Normal strict remains red only
for the 370 genuine deferred diagnostics; leak-only passes. The complete native-backed suite
passes 201 runs / 4,270 assertions with no failure, error, or skip. The focused native integration
suite passes 14 / 528 and covers Keyboard, Mouse, GamePad, lifecycle, and wrong-thread paths.

Stress retains 20 Game, Texture2D, SpriteBatch, and Game-recreation cycles; 50 Mouse and GamePad
state calls; and 20 GamePad capability calls. Crashes, observed use-after-free, and observed
double-free are all zero. Sanitizers were not run and remain honestly `NOT_RUN`. No controller was
connected, so positive controller state/capabilities and physical vibration remain
`HARDWARE_PENDING`.

The new exact `cna-ruby-0.1.0.dev0.gem` has 37 entries and SHA-256
`45f65ec9ab8e6419ebf3605bdfa77ec4326c2f3e3a1eb336ce742c928f77b348`. Audit results are zero
for forbidden entries, bundled native libraries, and developer-path leaks. A fresh gem home
installs only that exact gem, validates all 28 installed Ruby sources, requires `cna`, qualifies
the enum without a native library, and passes the unchanged template at 60 and 600 frames.
Maintained-source template runs pass the same frame counts; the template stays clean at commit
`42ae209b8b4fd175b7b1e5de43d895083b81877b`.
