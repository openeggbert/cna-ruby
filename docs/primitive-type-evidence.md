# Foundation 15 PrimitiveType evidence

Foundation 15 closes exactly one managed type:
`Microsoft.Xna.Framework.Graphics.PrimitiveType`. It implements no `GraphicsDevice` draw member,
no vertex or index buffer, no vertex declaration, no renderer topology mapping, and no native
route.

## Exact contract

The authority is the pinned Microsoft XNA Framework 4.0 Windows runtime metadata from
`Microsoft.Xna.Framework.Graphics.dll` 4.0.0.0, SHA-256
`560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`, as recorded in
`tools/api_compat/reference/xna40-windows-runtime-contract.json`.

| Type | Reference identities | Expected Ruby identities | Target Ruby identities | Local diagnostics |
| --- | ---: | ---: | ---: | ---: |
| `Microsoft.Xna.Framework.Graphics.PrimitiveType` | 5 | 4 | 4 | 0 |

Metadata records `kind=enum`, `underlyingType=System.Int32`, `baseType=System.Enum`, `sealed=true`,
`flags=false`, and no direct interface. The inherited interface set is `System.IComparable`,
`System.IConvertible`, and `System.IFormattable`, exactly as for every other selected XNA enum.
The five declared CLR fields are:

| Field | Raw value | Ruby XNA identity |
| --- | ---: | --- |
| `value__` | synthetic Int32 storage | excluded by the established enum-storage mapping |
| `TriangleList` | 0 | `PrimitiveType::TriangleList` |
| `TriangleStrip` | 1 | `PrimitiveType::TriangleStrip` |
| `LineList` | 2 | `PrimitiveType::LineList` |
| `LineStrip` | 3 | `PrimitiveType::LineStrip` |

There is no declared constructor, method, property, event, or operator. The exact runtime namespace
is `Microsoft::Xna::Framework::Graphics`; there is no root-framework or `GraphicsDevice` alias.
`require "microsoft/xna/framework/graphics"` exposes the enum without initializing a CNA native
library.

## The raw values are the XNA 4.0 renumbering, not the Direct3D 9 ordering

The raw values were taken from the pinned metadata rather than assumed, because the obvious guesses
are wrong. XNA 3.1 declared six literals in Direct3D 9 order — `PointList=0`, `LineList=1`,
`LineStrip=2`, `TriangleList=3`, `TriangleStrip=4`, `TriangleFan=5`. XNA 4.0 dropped `PointList`
and `TriangleFan` and **renumbered the four survivors from zero with the triangle topologies
first**:

| Literal | XNA 3.1 raw value | XNA 4.0 raw value (pinned, authoritative) |
| --- | ---: | ---: |
| `TriangleList` | 3 | **0** |
| `TriangleStrip` | 4 | **1** |
| `LineList` | 1 | **2** |
| `LineStrip` | 2 | **3** |
| `PointList` | 0 | *not declared* |
| `TriangleFan` | 5 | *not declared* |

A binding that copied the Direct3D 9 / XNA 3.1 ordering, or that copied a renderer topology
enumeration, would produce four silently wrong integers with the correct names. A dedicated
verifier fixture applies the complete XNA 3.1 ordering to the target contract and requires
`ENUM_VALUE_MISMATCH`, and two further fixtures reject an invented `PointList=4` and
`TriangleFan=5`. `PrimitiveType.coerce(4)` and `PrimitiveType.coerce(5)` raise `RangeError`, so
neither dropped literal can re-enter through a raw value.

## `LineStrip = 3` is not a flags composition

`FLAGS=false`. As with `DepthFormat`, the declared values `1`, `2`, and `3` look bitwise related and
`1 | 2 == 3` numerically, but XNA declares `LineStrip` as one ordinary enum literal with raw
value 3. It is not `TriangleStrip | LineList`, and `PrimitiveType` has no flag semantics at all:

- the pinned reference records `flags=false`;
- the selected signature records `flags=false`;
- the runtime `@enum_flags` is `false` and `@enum_mask` is `0`;
- `PrimitiveType::TriangleStrip | PrimitiveType::LineList` raises `TypeError` instead of returning
  `PrimitiveType::LineStrip`;
- `PrimitiveType::LineStrip & PrimitiveType::LineList` raises `TypeError`;
- `PrimitiveType.coerce(4)` raises `RangeError` rather than being accepted as an unnamed
  combination, which a mask-based reading would allow.

A dedicated verifier regression pins this distinction so a later refactor cannot silently
reclassify the type as a flags enum.

## Ruby ordinary enum projection

The implementation uses the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType` policy
with `define_values(...)` and no `flags:` argument. No new enum machinery, no PrimitiveType-specific
coercion, and no new general mapping rule are introduced; `docs/xna-ruby-mapping.md` is unchanged
because no genuinely new general rule is needed.

All four named values are typed `PrimitiveType` instances, frozen, and canonical. Repeated access to
each Ruby constant returns the same object:

```text
PrimitiveType.coerce(0).equal?(PrimitiveType::TriangleList)  = true
PrimitiveType.coerce(1).equal?(PrimitiveType::TriangleStrip) = true
PrimitiveType.coerce(2).equal?(PrimitiveType::LineList)      = true
PrimitiveType.coerce(3).equal?(PrimitiveType::LineStrip)     = true
```

Coercing an existing typed value returns that object unchanged.

Undefined raw values are rejected. `4`, `5`, `-1`, `12345`, and `2147483647` raise `RangeError`; the
ordinary Ruby enum policy deliberately does not preserve unnamed CLR values, and no arbitrary raw
`Int32` semantics from another binding is adopted. Non-Integer inputs `nil`, `true`, `false`,
`Float`, `String`, `Symbol`, and arbitrary `Object` raise `TypeError`; no `to_i`, `to_int`, name, or
symbol conversion is accepted.

Coercion rejects values of `DepthFormat`, `SurfaceFormat`, `SpriteSortMode`, `GraphicsProfile`,
`GraphicsDeviceStatus`, `ClearOptions`, `DisplayOrientation`, `VertexElementFormat`, and
`GamePadType` with `TypeError`. Cross-type equality remains `false` and cross-type comparison
returns `nil`. This matters more here than for most enums: every `PrimitiveType` raw value 0..3 also
exists in `DepthFormat`, `SurfaceFormat`, and `SpriteSortMode`, so raw-value-based cross-enum
coercion is explicitly not permitted.

Inherited `to_s`, `inspect`, and `to_i` are Ruby language support, not XNA declared identities:

```text
PrimitiveType::TriangleList.to_s   = "TriangleList"
PrimitiveType::TriangleStrip.to_s  = "TriangleStrip"
PrimitiveType::LineList.to_s       = "LineList"
PrimitiveType::LineStrip.to_s      = "LineStrip"
PrimitiveType::LineList.inspect    = "Microsoft::Xna::Framework::Graphics::PrimitiveType::LineList"
PrimitiveType::LineStrip.to_i      = 3
```

No `ToString`, `HasFlag`, `VertexCount`, `PrimitiveCount`, `GetElementCount`, `IndexCount`,
`NativeTopology`, `ToTopology`, `GlEnum`, `D3DPrimitiveType`, `IsStrip`, `IsList`, `Parse`, or
`FromInt32` helper is added, and no alias such as `PointList`, `TriangleFan`, `LineLoop`, `Patches`,
`QuadList`, `Triangles`, `Lines`, `Default`, `None`, or `Unknown` is invented. Deliberately, there
is **no primitive-count or vertex-count helper**: converting a primitive count to a vertex count is
draw-call arithmetic, and draw calls are not part of this milestone. The exact target identity count
is 4.

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

Twenty-five focused PrimitiveType mutations across nine test methods detect a missing type, wrong
namespace, wrong type kind, wrong underlying type, contract `flags=true`, each of the four
raw-value mutations, the complete XNA 3.1 / Direct3D 9 ordering, a missing middle value
(`LineList`), a missing final value (`LineStrip`), exposed `value__`, an invented `PointList=4`, an
invented `TriangleFan=5`, a renamed final value, an unexpected XNA member, runtime public helper
leakage, a runtime flags-classification mutation, a full flags-confusion contract, and accidental
selection of each of the five `GraphicsDevice` draw member names. Every expected enum raw value is
validated mechanically by the existing generic verifier machinery. No manual allowlist and no
PrimitiveType-specific verifier rule is used.

## Behavior provenance

The compact `PRIMITIVE_TYPE` corpus group has two observations. One `PURE_XNA_DERIVED` observation
records enum kind, `System.Int32` underlying type, `flags=false`, the exact values 0/1/2/3, the
declared member count, the presence of a declared zero-valued XNA name (`TriangleList`), and the
absence of `PointList` and `TriangleFan`. One `RUBY_MAPPING_QUALIFICATION` observation covers
typed/frozen named values, canonical coercion of 0/1/2/3, typed coercion identity, undefined raw
rejection (including both dropped XNA 3.1 raw values), non-Integer rejection, nine-way cross-type
coercion/equality/comparison safety, `|` and `&` rejection, the numeric `1 | 2 == 3` contrast, exact
constants and strings, absent helpers, absent `GraphicsDevice` draw members, absent buffer/
declaration types, and the unchanged native boundary.

The cumulative corpus is 277 observations / 277 assertions with zero failures: 270
`PURE_XNA_DERIVED` and seven `RUBY_MAPPING_QUALIFICATION`. Ruby coercion restrictions are
deliberately classified as mapping qualification, not XNA runtime behavior or CNA evidence.

## Dependency boundary — every draw member remains deferred

The regenerated public-signature dependency report identified `PrimitiveType` as a missing managed
enum with no unmet XNA public-signature dependency, four expected Ruby identities, and exactly five
direct reverse edges from the selected partial remainder:

```text
Microsoft.Xna.Framework.Graphics.GraphicsDevice::DrawPrimitives (1 overload)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::DrawIndexedPrimitives (1 overload)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::DrawInstancedPrimitives (1 overload)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::DrawUserIndexedPrimitives (4 overloads)
Microsoft.Xna.Framework.Graphics.GraphicsDevice::DrawUserPrimitives (2 overloads)
```

Those edges are **selection evidence only**. None of the nine draw overloads is implemented. There
is no `DrawPrimitives`, `DrawIndexedPrimitives`, `DrawInstancedPrimitives`, `DrawUserPrimitives`, or
`DrawUserIndexedPrimitives` public, protected, or private method on `GraphicsDevice`; its public
instance surface remains exactly `IsDisposed`, `Viewport`, and `Clear`. `GraphicsDevice` remains
partial, and global `MISSING_MEMBER` stays at 132 while `OVERLOAD_MAPPING_MISMATCH` stays at 51.

Unusually, `GraphicsDevice` is the *only* reference user of `PrimitiveType` in the entire pinned
257-type profile. The complete list of the nine deferred reference signatures is:

| Deferred member | Signature |
| --- | --- |
| `DrawPrimitives` | `(PrimitiveType, Int32, Int32)` |
| `DrawIndexedPrimitives` | `(PrimitiveType, Int32, Int32, Int32, Int32, Int32)` |
| `DrawInstancedPrimitives` | `(PrimitiveType, Int32, Int32, Int32, Int32, Int32, Int32)` |
| `DrawUserPrimitives` | `(PrimitiveType, T[], Int32, Int32)` |
| `DrawUserPrimitives` | `(PrimitiveType, T[], Int32, Int32, VertexDeclaration)` |
| `DrawUserIndexedPrimitives` | `(PrimitiveType, T[], Int32, Int32, Int32[], Int32, Int32)` |
| `DrawUserIndexedPrimitives` | `(PrimitiveType, T[], Int32, Int32, Int16[], Int32, Int32)` |
| `DrawUserIndexedPrimitives` | `(PrimitiveType, T[], Int32, Int32, Int32[], Int32, Int32, VertexDeclaration)` |
| `DrawUserIndexedPrimitives` | `(PrimitiveType, T[], Int32, Int32, Int16[], Int32, Int32, VertexDeclaration)` |

Four of these are generic over the user vertex type and four take a `VertexDeclaration`, which is
itself a missing type. Implementing any of them would require `IVertexType`, `VertexDeclaration`,
vertex/index buffer state, and a real renderer path — none of which is Foundation 15 work.

## Runtime boundary

Completing `PrimitiveType` proves managed enum metadata only. The capability is classified narrowly
as `managed.primitive-type` / `VERIFIED_MANAGED`. Explicitly:

- no `GraphicsDevice` draw member is implemented;
- renderer primitive topology mapping is **not implemented**;
- GPU support for triangle lists, triangle strips, line lists, or line strips is **not claimed**;
- `VertexBuffer`, `IndexBuffer`, `DynamicVertexBuffer`, `DynamicIndexBuffer`, `VertexDeclaration`,
  `IVertexType`, `RasterizerState`, `Effect`, and `BasicEffect` are **not implemented**;
- `GraphicsDevice.SetVertexBuffer` and `GraphicsDevice.Indices` are **not implemented**;
- no primitive-count, vertex-count, or index-count arithmetic is added.

No CNA enum, constant, function, Fiddle argument, manifest entry, or native conversion table is
added. There is no `CNA_PRIMITIVE_TYPE_*` or `CNA_TOPOLOGY_*` constant, no `cna_*_draw_*` binding,
and no SDL, OpenGL, Vulkan, or Direct3D topology translation. No selected Foundation 15 API crosses
the native boundary using `PrimitiveType`. ABI verification remains exactly 38 bound functions, 122
signature measurements, 290 C and 290 Ruby layout measurements, two callbacks, and 59 constants,
with zero missing symbol or mismatch. CNA itself is unmodified.

## Qualification

The focused native-unset PrimitiveType suite passes 11 runs / 205 assertions with
`CNA_NATIVE_LIBRARY` unset and no `Game`, `GraphicsDevice`, `GraphicsDeviceManager`, Fiddle, native
loader, or renderer involvement. Verifier mutation and self-tests pass 97 / 252; runtime/RBS
consistency passes 15 / 1891; RBS 3.4.0 validation passes. The cumulative source suite passes
288 / 5354 with zero failure, error, or skip.

`DepthFormat` remains complete and unchanged at `None=0`, `Depth16=1`, `Depth24=2`,
`Depth24Stencil8=3` with `flags=false`. `ClearOptions` remains complete at `Target=1`,
`DepthBuffer=2`, `Stencil=4`, `flags=true`, mask `0x7`, with no named zero and both four-argument
`GraphicsDevice.Clear` overloads still deferred. `Viewport` remains complete at 14/14 with its
Project/Unproject bit goldens. `GraphicsProfile`, `GraphicsDeviceStatus`, `SurfaceFormat`,
`SpriteSortMode`, `VertexElementFormat`, `VertexElementUsage`, `PlayerIndex`, `GamePadDeadZone`,
`GamePadType`, `DisplayOrientation`, `SpriteEffects`, and `Buttons` all retain their qualified
tests. No production `EnumType` or `EnumValue` change was required.

Native integration passes 14 / 528. Stress retains 20 Game, Texture2D, SpriteBatch, and Game
recreation cycles; 50 Mouse and GamePad state cycles; and 20 GamePad capability cycles. Crashes,
observed UAF, and observed double-free are zero. Sanitizers were not run and remain `NOT_RUN`.

## The corpus correction Foundation 94 required

`primitive_type.ruby_enum_mapping` recorded which of `GraphicsDevice`'s five draw members this
binding projects. Three were true when Foundation 88 built the device-buffer draws; Foundation 94
built the two user-primitive families, so all five are. Corrected as a **surgical byte edit** — two
`false` tokens inside one nested element — in the aggregate and in this milestone's authoring
record alike, so the closed supersession register in `test_behavior_corpus_integrity.rb` still holds
seven.

| file | element | pre-correction SHA-256 | post-correction SHA-256 |
| --- | ---: | --- | --- |
| `behavior/xna40-foundation-values.json` | 19 | `680a009dbaa6cf1fba6e1722a0caa5ba1b08fbe7d34913b2d3959e7b149f08d1` | `663dafa2f214af35d5fd047354bc55d386f126d4caf5bccded41e6921f4be655` |
| `behavior/xna40-primitive-type-values.json` | 19 | `54044473a26608f7cbaade6784bdbd8026832c92d439d64b2ace75266bd86bc4` | `75244bb7f3c5f7d6783231647e9fa33d17538af3b3df46299bf225c67d908a87` |

Four lines moved. The observation is `RUBY_MAPPING_QUALIFICATION` — it records what this projection
exposes, not an XNA fact and not a CNA measurement — and the corpus replays 526 observations with
zero failures afterwards.
