# Foundation 14 DepthFormat evidence

Foundation 14 closes exactly one managed type:
`Microsoft.Xna.Framework.Graphics.DepthFormat`. It implements no `GraphicsDeviceManager`
property, no presentation or render-target type, no depth/stencil state, and no native route.

## Exact contract

The authority is the pinned Microsoft XNA Framework 4.0 Windows runtime metadata from
`Microsoft.Xna.Framework.Graphics.dll` 4.0.0.0, SHA-256
`560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`.

| Type | Reference identities | Expected Ruby identities | Target Ruby identities | Local diagnostics |
| --- | ---: | ---: | ---: | ---: |
| `Microsoft.Xna.Framework.Graphics.DepthFormat` | 5 | 4 | 4 | 0 |

Metadata records `kind=enum`, `underlyingType=System.Int32`, `baseType=System.Enum`, `sealed=true`,
`flags=false`, and no direct interface. The five declared CLR fields are:

| Field | Raw value | Ruby XNA identity |
| --- | ---: | --- |
| `value__` | synthetic Int32 storage | excluded by the established enum-storage mapping |
| `None` | 0 | `DepthFormat::None` |
| `Depth16` | 1 | `DepthFormat::Depth16` |
| `Depth24` | 2 | `DepthFormat::Depth24` |
| `Depth24Stencil8` | 3 | `DepthFormat::Depth24Stencil8` |

There is no declared constructor, method, property, event, or operator. The exact runtime namespace
is `Microsoft::Xna::Framework::Graphics`; there is no root-framework, `GraphicsDevice`, or
`DepthStencilState` alias. `require "microsoft/xna/framework/graphics"` exposes the enum without
initializing a CNA native library.

## `Depth24Stencil8 = 3` is not a flags composition

`FLAGS=false`. The declared values `1`, `2`, and `3` look bitwise related, and `1 | 2 == 3`
numerically, but XNA declares `Depth24Stencil8` as one ordinary enum literal with raw value 3. It is
not `Depth16 | Depth24`, and DepthFormat has no flag semantics at all:

- the pinned reference records `flags=false`;
- the selected signature records `flags=false`;
- the runtime `@enum_flags` is `false` and `@enum_mask` is `0`;
- `DepthFormat::Depth16 | DepthFormat::Depth24` raises `TypeError` instead of returning
  `DepthFormat::Depth24Stencil8`;
- `DepthFormat::Depth24Stencil8 & DepthFormat::Depth24` raises `TypeError`;
- `DepthFormat.coerce(4)` raises `RangeError` rather than being accepted as an unnamed
  combination, which a mask-based reading would allow.

A dedicated verifier regression pins this distinction so a later refactor cannot silently
reclassify the type as a flags enum.

## Ruby ordinary enum projection

The implementation uses the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType` policy
with `define_values(...)` and no `flags:` argument. No new enum machinery, no DepthFormat-specific
coercion, and no new general mapping rule are introduced.

All four named values are typed `DepthFormat` instances, frozen, and canonical. Repeated access to
each Ruby constant returns the same object:

```text
DepthFormat.coerce(0).equal?(DepthFormat::None)            = true
DepthFormat.coerce(1).equal?(DepthFormat::Depth16)         = true
DepthFormat.coerce(2).equal?(DepthFormat::Depth24)         = true
DepthFormat.coerce(3).equal?(DepthFormat::Depth24Stencil8) = true
```

Coercing an existing typed value returns that object unchanged.

Undefined raw values are rejected. `4`, `-1`, `12345`, and `2147483647` raise `RangeError`; the
ordinary Ruby enum policy deliberately does not preserve unnamed CLR values, and no arbitrary raw
`Int32` semantics from another binding is adopted. Non-Integer inputs `nil`, `true`, `false`,
`Float`, `String`, `Symbol`, and arbitrary `Object` raise `TypeError`; no `to_i`, `to_int`, name, or
symbol conversion is accepted.

Coercion rejects values of `SurfaceFormat`, `GraphicsProfile`, `GraphicsDeviceStatus`,
`ClearOptions`, `DisplayOrientation`, `VertexElementFormat`, and `GamePadType` with `TypeError`.
Cross-type equality remains `false` and cross-type comparison returns `nil`. Raw-value-based
cross-enum coercion is not permitted.

Inherited `to_s`, `inspect`, and `to_i` are Ruby language support, not XNA declared identities:

```text
DepthFormat::None.to_s               = "None"
DepthFormat::Depth16.to_s            = "Depth16"
DepthFormat::Depth24Stencil8.to_s    = "Depth24Stencil8"
DepthFormat::Depth24.inspect         = "Microsoft::Xna::Framework::Graphics::DepthFormat::Depth24"
DepthFormat::Depth24Stencil8.to_i    = 3
```

No `ToString`, `HasFlag`, `HasStencil`, `DepthBits`, `StencilBits`, `IsDepthOnly`,
`IsDepthStencil`, `NativeFormat`, `Parse`, or `FromInt32` helper is added, and no alias such as
`Default`, `Depth32`, `Stencil8`, `Depth24Stencil`, `D16`, `D24`, or `D24S8` is invented. The exact
target identity count is 4.

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

Nineteen focused DepthFormat mutations detect a missing type, wrong namespace, wrong type kind,
wrong underlying type, contract `flags=true`, each of the four raw-value mutations, a missing
middle value, a missing final value, exposed `value__`, an invented `Depth32=4`, a
renamed/misspelled `Depth24Stencil8`, an unexpected XNA member, runtime public helper leakage, a
runtime flags-classification mutation, a full flags-confusion contract, and accidental addition of
`GraphicsDeviceManager.PreferredDepthStencilFormat`. Every expected enum raw value is validated
mechanically by the existing generic verifier machinery. No manual allowlist and no
DepthFormat-specific verifier rule is used.

## Behavior provenance

The compact `DEPTH_FORMAT` corpus group has two observations. One `PURE_XNA_DERIVED` observation
records enum kind, `System.Int32` underlying type, `flags=false`, the exact values 0/1/2/3, the
presence of a declared zero-valued XNA name (`None`, unlike `ClearOptions`), and the absence of a
declared `Default`. One `RUBY_MAPPING_QUALIFICATION` observation covers typed/frozen named values,
canonical coercion of 0/1/2/3, typed coercion identity, undefined raw rejection, non-Integer
rejection, cross-type coercion/equality/comparison safety, `|` and `&` rejection, the numeric
`1 | 2 == 3` contrast, exact constants and strings, absent helpers, and the unchanged deferred and
native boundary.

The cumulative corpus is 275 observations / 275 assertions with zero failures: 269
`PURE_XNA_DERIVED` and six `RUBY_MAPPING_QUALIFICATION`. Ruby coercion restrictions are deliberately
classified as mapping qualification, not XNA runtime behavior or CNA evidence.

## Dependency boundary

The regenerated public-signature dependency report identified `DepthFormat` as a missing managed
enum with no unmet XNA public-signature dependency, four expected Ruby identities, and exactly one
direct reverse edge from the selected partial remainder:

```text
Microsoft.Xna.Framework.GraphicsDeviceManager::PreferredDepthStencilFormat (1 overload)
```

That edge is selection evidence only. The property is **not** implemented: there is no getter,
setter, managed field, dirty state, `ApplyChanges` integration, or device recreation.
`GraphicsDeviceManager` remains partial with its unchanged four selected identities, and global
`MISSING_MEMBER` stays at 132.

The remaining reference users of `DepthFormat` — `GraphicsAdapter.QueryBackBufferFormat`,
`GraphicsAdapter.QueryRenderTargetFormat`, `PresentationParameters.DepthStencilFormat`, both
`RenderTarget2D` constructors and `RenderTarget2D.DepthStencilFormat`, and both `RenderTargetCube`
constructors and `RenderTargetCube.DepthStencilFormat` — belong to missing types outside the
selected closure and are untouched.

## Runtime boundary

Completing `DepthFormat` proves managed enum metadata only. The capability is classified narrowly
as `managed.depth-format` / `VERIFIED_MANAGED`. Explicitly:

- GPU depth-format support for `Depth16`, `Depth24`, or `Depth24Stencil8` is **not claimed**;
- stencil support is **not claimed**;
- native mapping is **not implemented**;
- `GraphicsDeviceManager.PreferredDepthStencilFormat` is **not implemented**;
- `GraphicsAdapter`, `PresentationParameters`, `RenderTarget2D`, and `RenderTargetCube` are **not
  implemented**;
- `DepthStencilState` and every GPU depth/stencil state member (`DepthBufferEnable`,
  `DepthBufferWriteEnable`, `DepthBufferFunction`, `StencilEnable`, `StencilFunction`,
  `StencilPass`) are **not implemented**;
- no depth-buffer or stencil-buffer allocation, backbuffer configuration, or renderer depth format
  is added.

No CNA enum, constant, function, Fiddle argument, manifest entry, or native conversion table is
added. There is no `CNA_DEPTH_FORMAT_NONE`, `CNA_DEPTH_FORMAT_DEPTH16`,
`CNA_DEPTH_FORMAT_DEPTH24`, or `CNA_DEPTH_FORMAT_DEPTH24_STENCIL8`. No selected Foundation 14 API
crosses the native boundary using `DepthFormat`. ABI verification remains exactly 38 bound
functions, 122 signature measurements, 290 C and 290 Ruby layout measurements, two callbacks, and
59 constants, with zero missing symbol or mismatch.

## Qualification

The focused native-unset DepthFormat suite passes 9 runs / 151 assertions with
`CNA_NATIVE_LIBRARY` unset and no `Game`, `GraphicsDevice`, `GraphicsDeviceManager`, Fiddle, native
loader, or renderer involvement. Verifier mutation and self-tests pass 88 / 199; runtime/RBS
consistency passes 14 / 1829; RBS 3.4.0 validation passes. The cumulative source suite passes
267 / 5034 with zero failure, error, or skip.

`ClearOptions` remains complete and unchanged at `Target=1`, `DepthBuffer=2`, `Stencil=4`,
`flags=true`, mask `0x7`, with no named zero and both four-argument `GraphicsDevice.Clear`
overloads still deferred. `Viewport` remains complete at 14/14 with its Project/Unproject bit
goldens. `GraphicsProfile`, `GraphicsDeviceStatus`, `SurfaceFormat`, `SpriteSortMode`,
`VertexElementFormat`, `VertexElementUsage`, `PlayerIndex`, `GamePadDeadZone`, `GamePadType`,
`DisplayOrientation`, `SpriteEffects`, and `Buttons` all retain their qualified tests. No
production `EnumType` or `EnumValue` change was required.

Native integration passes 14 / 528. Stress retains 20 Game, Texture2D, SpriteBatch, and Game
recreation cycles; 50 Mouse and GamePad state cycles; and 20 GamePad capability cycles. Crashes,
observed UAF, and observed double-free are zero. Sanitizers were not run and remain `NOT_RUN`.
