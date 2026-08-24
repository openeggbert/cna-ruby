# Foundation 8 VertexElement evidence

Foundation 8 closes exactly `Microsoft.Xna.Framework.Graphics.VertexElement`,
`VertexElementFormat`, and `VertexElementUsage`. The pinned XNA 4.0 Windows runtime metadata contains
3 types and 37 CLR identities: 10, 13, and 14 respectively. The established Ruby exclusion of each
enum's synthetic `value__` storage field leaves exactly 35 Ruby XNA identities: 10, 12, and 13.

The public signatures depend only on these three types and System primitives. `IVertexType`,
`VertexDeclaration`, the four built-in vertex structs, vertex/index buffers, `GraphicsDevice`, and
draw/rendering paths are not dependencies and remain absent. The `Byte4`, `Short2`, `HalfVector2`,
and `HalfVector4` enum labels are names, not dependencies on the PackedVector types.

## Authorities and reference behavior

The public contract is the pinned metadata snapshot at SHA-256
`7207908eb7926cc90a156d0370c907add4dda465421cea1cbec51afba2f97fdc`. Behavior was derived from
the retained original XNA assemblies and direct IL inspection:

| Assembly | SHA-256 |
| --- | --- |
| `Microsoft.Xna.Framework.dll` | `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130` |
| `Microsoft.Xna.Framework.Graphics.dll` | `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55` |

`tools/vertex_element_reference_probe.cs` retains the direct public observation fixture. CNA and
other language bindings are not behavior authorities.

## Enum contracts

Both enums are typed, frozen `CNA::Runtime::EnumValue` instances, use `System.Int32`, and are not
flags. No enum-specific helper surface was added.

| `VertexElementFormat` | Value | `VertexElementUsage` | Value |
| --- | ---: | --- | ---: |
| `Single` | 0 | `Position` | 0 |
| `Vector2` | 1 | `Color` | 1 |
| `Vector3` | 2 | `TextureCoordinate` | 2 |
| `Vector4` | 3 | `Normal` | 3 |
| `Color` | 4 | `Binormal` | 4 |
| `Byte4` | 5 | `Tangent` | 5 |
| `Short2` | 6 | `BlendIndices` | 6 |
| `Short4` | 7 | `BlendWeight` | 7 |
| `NormalizedShort2` | 8 | `Depth` | 8 |
| `NormalizedShort4` | 9 | `Fog` | 9 |
| `HalfVector2` | 10 | `PointSize` | 10 |
| `HalfVector4` | 11 | `Sample` | 11 |
| — | — | `TessellateFactor` | 12 |

The existing formal enum bridge is unchanged: typed instances are accepted, and a named raw
Integer passed through `coerce` resolves to its typed frozen instance. Arbitrary unnamed Integers
are rejected. CLR can physically carry unnamed Int32 enum values, but Ruby does not expose public
construction for them; this retained language restriction adds no new mismatch. Private enum-name
tables were unnecessary because the frozen instances already retain exact XNA names. Neither enum
exposes `SizeInBytes`, `ComponentCount`, `Normalized?`, `String`, or `ToString`.

## VertexElement value behavior

`VertexElement` is a managed Ruby value object with four private scalar/immutable-enum components.
It has no native handle, Fiddle call, runtime state, or native layout. The sole CLR constructor is
the exact four-argument `(Int32, VertexElementFormat, VertexElementUsage, Int32)` identity. The
project-wide struct-default language projection also permits `VertexElement.new`, producing
`(0, Single, Position, 0)`; generated signatures still count one CLR constructor, while RBS
documents the zero-argument Ruby branch separately.

The constructor IL consists only of the four field stores. Offset and usage index therefore accept
every Int32 value, including negative values and both boundaries, without clamp, normalization, or
nonnegative validation. Ruby Integers outside `-2147483648..2147483647` are rejected. The exact
mutable properties are `Offset`, `VertexElementFormat`, `VertexElementUsage`, and `UsageIndex`, each
with its corresponding Ruby setter. No backing field, `Format`, or `Usage` alias is public.

`dup` and `clone` construct independent values. Mutating all four properties on either copy leaves
the original unchanged. Ruby assignment still aliases and remains the existing documented struct
language limitation.

`Equals(Object)` returns false for nil and unrelated objects and compares all four components for
another exact `VertexElement`. There is no typed `Equals(VertexElement)` identity. `==` retains
`op_Equality`, and `!=` independently retains `op_Inequality`; one-field-difference fixtures cover
every property.

### GetHashCode

XNA boxes the 16-byte sequential struct and calls `Helpers.SmartGetHashCode`. That helper XORs each
complete 32-bit word and substitutes `Int32.MaxValue` when the result is zero. Field order is
Offset, format, usage, usage index:

```text
hash = Offset XOR int32(VertexElementFormat) XOR int32(VertexElementUsage) XOR UsageIndex
hash = 2147483647 when hash == 0
```

| Fixture | Hash |
| --- | ---: |
| `(0, Single, Position, 0)` | 2147483647 |
| `(12, Vector3, TextureCoordinate, 7)` | 11 |
| `(-16, HalfVector4, Tangent, -3)` | 3 |
| `(Int32.MinValue, HalfVector4, TessellateFactor, Int32.MaxValue)` | -8 |
| `(1, Vector3, Normal, 0)` | 2147483647 |
| `(Int32.MaxValue, Single, Position, Int32.MinValue)` | -1 |

The collision fallback is intentional XNA behavior, including for the nonzero collision fixture.

### ToString

The IL uses `CultureInfo.CurrentCulture` and the exact composite format
`{{Offset:{0} Format:{1} Usage:{2} UsageIndex:{3}}}`. Representable Ruby values therefore render,
for example:

```text
{Offset:12 Format:Vector3 Usage:TextureCoordinate UsageIndex:7}
{Offset:-2147483648 Format:HalfVector4 Usage:TessellateFactor UsageIndex:2147483647}
```

Labels, ordering, spaces, punctuation, signed Int32 rendering, and enum casing are exact. No Ruby
`inspect` or object hash/string fallback participates.

## Structural and behavioral qualification

| Type | CLR identities | Expected Ruby | Target | Local diagnostics | Kind |
| --- | ---: | ---: | ---: | ---: | --- |
| `VertexElement` | 10 | 10 | 10 | 0 | struct/value object |
| `VertexElementFormat` | 13 | 12 | 12 | 0 | non-flags Int32 enum |
| `VertexElementUsage` | 14 | 13 | 13 | 0 | non-flags Int32 enum |

Every local category is zero, including missing/unexpected member; kind/base/interface;
field/property/method/parameter/return/overload/generic; enum/flags/event/operator/language;
internal/native leak; allowlist; and unmeasured structural categories. Mutation fixtures detect a
wrong kind, missing or reordered constructor, wrong enum parameters, property-as-field, read-only
or wrongly typed properties, missing setters, typed Equals, missing operators, wrong enum values,
flags mistakes, and an unexpected helper.

The managed-only focused suite runs without `CNA_NATIVE_LIBRARY` and passes 11 runs / 286
assertions. The PURE_XNA_DERIVED corpus grows from 239 to 253 observations/assertions with zero
failures: `VERTEX_ELEMENT=11` and `VERTEX_ELEMENT_ENUMS=3`. It covers all 25 named values,
construction/defaults, all getters/setters, Int32 boundaries, copies, object equality, operators,
six hashes, four exact strings, validation, and strict surface absence.

RBS 3.4.0 validates the exact 35-identity closure. `VertexElement` has 14 callable projections
after its four writable properties expand to getter/setter pairs, plus the separately documented
zero-argument language constructor branch. The file has no `untyped` or catch-all signature, and
runtime/RBS consistency passes.

This milestone changes no CNA source, C ABI function, native manifest, Fiddle table, native layout,
renderer capability, or template source. The managed capability is narrowly
`VERIFIED_MANAGED`; it does not claim vertex declarations, buffers, GPU format support, vertex
shader input, or drawing.

## Release qualification

The complete native-backed regression suite passes 180 runs / 4,135 assertions with no failures,
errors, or skips. Native ABI verification remains exactly unchanged at 38 bound functions, 122
signature measurements, 290 C and 290 Ruby layout measurements, 2 callbacks, and 59 constants,
with zero missing header/library symbols and zero ABI mismatches. Stress retains 20 game, texture,
SpriteBatch, and game-recreation cycles; 50 Mouse and GamePad-state cycles; and 20 GamePad
capability cycles, with zero crashes, observed use-after-free, or observed double-free. Sanitizers
were not run and remain reported as `NOT_RUN`.

The final `cna-ruby-0.1.0.dev0.gem` has 37 entries and SHA-256
`122d34535f6035ef3bd494c85be2d6b48918ed10d8f454dcc062bde3a2e8d48a`. Its audit finds zero
forbidden entries, bundled native libraries, or developer-path leaks. A fresh gem home installs
only that exact gem, validates all 28 installed Ruby source files, requires `cna`, and passes the
unchanged template at 60 and 600 frames. Maintained-source template runs pass the same frame counts;
the template source remains unchanged at commit `42ae209b8b4fd175b7b1e5de43d895083b81877b`.
