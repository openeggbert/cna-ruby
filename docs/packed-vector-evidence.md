# PackedVector Family Evidence

This document records the managed-only Foundation Milestone 5 closure. The authority is the pinned Microsoft XNA Framework 4.0 Windows runtime metadata and the original `Microsoft.Xna.Framework.dll`, SHA-256 `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`. Direct public-API observations were captured by `tools/packed_vector_reference_probe.cs` against that assembly. CNA output was never treated as XNA truth, and this milestone adds no CNA or Fiddle function.

## Exact 19-type closure

The regenerated reference family contains 19 public types and 171 XNA member identities. Properties remain one XNA identity each even though their RBS reader and writer are two callable projections.

| Type | Reference members | Target members | Local diagnostics | Packed type | Interface status | Behavior status |
| --- | ---: | ---: | ---: | --- | --- | --- |
| `IPackedVector` | 2 | 2 | 0 | — | Ruby module | PASS |
| `IPackedVectorOfT` | 1 | 1 | 0 | `TPacked` | generic module; includes `IPackedVector` | PASS |
| `Alpha8` | 9 | 9 | 0 | `Byte` | `IPackedVectorOfT[Byte]` | PASS |
| `Bgr565` | 10 | 10 | 0 | `UInt16` | `IPackedVectorOfT[UInt16]` | PASS |
| `Bgra4444` | 10 | 10 | 0 | `UInt16` | `IPackedVectorOfT[UInt16]` | PASS |
| `Bgra5551` | 10 | 10 | 0 | `UInt16` | `IPackedVectorOfT[UInt16]` | PASS |
| `Byte4` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `HalfSingle` | 9 | 9 | 0 | `UInt16` | `IPackedVectorOfT[UInt16]` | PASS |
| `HalfVector2` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `HalfVector4` | 10 | 10 | 0 | `UInt64` | `IPackedVectorOfT[UInt64]` | PASS |
| `NormalizedByte2` | 10 | 10 | 0 | `UInt16` | `IPackedVectorOfT[UInt16]` | PASS |
| `NormalizedByte4` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `NormalizedShort2` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `NormalizedShort4` | 10 | 10 | 0 | `UInt64` | `IPackedVectorOfT[UInt64]` | PASS |
| `Rg32` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `Rgba1010102` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `Rgba64` | 10 | 10 | 0 | `UInt64` | `IPackedVectorOfT[UInt64]` | PASS |
| `Short2` | 10 | 10 | 0 | `UInt32` | `IPackedVectorOfT[UInt32]` | PASS |
| `Short4` | 10 | 10 | 0 | `UInt64` | `IPackedVectorOfT[UInt64]` | PASS |

Every concrete type directly retains `IPackedVector<TPacked>` and `IEquatable<T>` in structural metadata; `IPackedVector` is transitive. The runtime generic-collision module is `Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVectorOfT`, while RBS declares `IPackedVectorOfT[TPacked]`. The reusable CLR name mapper converts an arity-one generic definition `Name` to `NameOfT`, preserves the `TPacked` verifier object at position zero, and rejects constructed generic identities as runtime constants. No alias collapses the generic and non-generic identities.

All local type-kind, base, interface, field, property, signature, parameter, return, overload, generic, enum/flags, event, operator, and language categories are zero. Unexpected types/members, internal/native leaks, allowlist entries, and unmeasured structural categories are also zero.

## Component domains, rounding, and layouts

Every public numeric input first narrows to XNA `Single`. Finite conversions clamp to the format domain and use round-to-nearest, ties-to-even. Unsigned normalized conversion performs a binary32 multiply by the positive integer maximum before rounding; signed normalized conversion multiplies by 127 or 32767. Ruby's arbitrary-width integers are masked deliberately, and `PackedValue=` rejects non-Integer, negative, and one-above-width inputs instead of truncating.

| Type | Input domain | Numeric bit layout, low to high |
| --- | --- | --- |
| `Alpha8` | alpha UNorm `[0,1]` | alpha 8; interface consumes `W` |
| `Bgr565` | XYZ UNorm `[0,1]` | Z 5, Y 6, X 5 |
| `Bgra4444` | XYZW UNorm `[0,1]` | Z 4, Y 4, X 4, W 4 |
| `Bgra5551` | XYZW UNorm `[0,1]` | Z 5, Y 5, X 5, W 1 |
| `Byte4` | raw unsigned `[0,255]` | X, Y, Z, W: 8 each |
| `HalfSingle` | XNA half from `Single` | X 16; interface consumes `X` |
| `HalfVector2` | two XNA halves | X 16, Y 16 |
| `HalfVector4` | four XNA halves | X, Y, Z, W: 16 each |
| `NormalizedByte2/4` | SNorm `[-1,1]` | X, Y, Z, W: 8 each where present |
| `NormalizedShort2/4` | SNorm `[-1,1]` | X, Y, Z, W: 16 each where present |
| `Rg32` | XY UNorm `[0,1]` | X 16, Y 16 |
| `Rgba1010102` | XYZW UNorm `[0,1]` | X 10, Y 10, Z 10, W 2 |
| `Rgba64` | XYZW UNorm `[0,1]` | X, Y, Z, W: 16 each |
| `Short2/4` | raw signed `[-32768,32767]` | X, Y, Z, W: two's-complement 16 each |

One-hot XNA goldens qualify every position. In particular Bgr565 is numerically `X<<11 | Y<<5 | Z`; BGRA does not imply low-bit B; and packed integer semantics are independent of host endianness. Bgra5551 alpha uses the same tie-to-even UNorm conversion as other lanes: exactly 0.5 rounds to zero, while the next observed binary32 value above it packs bit 15. Byte4 and Short formats use raw numeric domains, not normalized inputs.

Signed normalized packing emits `-127` for byte `-1` (`0x81`) and `-32767` for short `-1` (`0x8001`), never the most-negative endpoint. Unpacking the reserved most-negative encodings `0x80` and `0x8000` also returns exactly `-1`; other negative encodings use explicit sign extension. This asymmetric endpoint behavior and tie-to-even conversion are covered by packed-bit fixtures.

## XNA half behavior

The helper operates from the source Single bit pattern; Ruby binary64 arithmetic never changes that input first. It retains sign, performs XNA's exponent rebias/subnormal shift, and adds the discarded-bit tie correction for round-to-nearest-even. Magnitudes above Single bits `0x47FFEFFF`, including positive infinity and every positive NaN payload, pack to `0x7FFF`; negative infinity and negative NaNs pack to `0xFFFF`. Payloads are therefore canonicalized by sign.

This XNA encoding is not IEEE binary16 at its top exponent. Every one of the 65,536 packed patterns decodes to a finite Single. Conventional bit-field classes still count 2 zero, 2,046 subnormal, 61,440 normal, 2 infinity-coded, and 2,046 NaN-coded patterns, but the exponent-31 classes decode as ordinary finite XNA values. For example `0x7FFF` becomes Single bits `0x47FFE000` (131008), and `0xFFFF` becomes `0xC7FFE000` (-131008).

The goldens cover signed zero, smallest positive subnormal, largest subnormal, smallest normal, maximum finite input, overflow boundary, both infinities, positive/negative NaNs with distinct payloads, and halfway cases. Examples include `0x3F801000 -> 0x3C00` and `0x3F803000 -> 0x3C02`, proving even-lower-bit selection at ties. All 65,536 packed values decode finite and decode/re-encode to the original 16-bit pattern with zero failures.

## Interface and value projection

`IPackedVector` and `IPackedVectorOfT` are Ruby modules. `PackFromVector4` and explicit `ToVector4` implementations are private protocol methods. Alpha8 publicly declares only `ToAlpha`; Bgr565 only `ToVector3`; HalfSingle only `ToSingle`; the two-component formats only `ToVector2`. Four-component formats publicly declare `ToVector4`. This matches the metadata and leaves `UNEXPECTED_MEMBER=0`.

Interface expansion is exact: Alpha8 returns `(0,0,0,alpha)`; Bgr565 returns `(x,y,z,1)`; HalfSingle returns `(x,0,0,1)`; every two-component format returns `(x,y,0,1)`; four-component formats return all lanes. `PackFromVector4` consumes W for Alpha8, XYZ for Bgr565, X for HalfSingle, XY for two-component formats, and XYZW for four-component formats. It mutates packed state and returns nil. The verifier checks module ancestry and also rejects concrete types that only inherit abstract protocol stubs.

All structs store one independent Integer. Constructors semantically copy vector inputs, conversion results are fresh vectors, and `dup`/`clone` copy packed state. Ruby assignment aliasing remains the existing documented language limitation; no new limitation was introduced.

Equality, typed/object `Equals`, `==`, and `!=` compare type plus exact packed bits, never unpacked floats. Distinct exponent-31 half payloads remain unequal even though both decode to finite values. Byte/UInt16 hashes are the packed integer; UInt32 hashes are its signed Int32 interpretation; UInt64 hashes fold low and high UInt32 halves with XOR and then interpret the result as signed Int32. The boundary fixture `0xFEDCBA9876543210` hashes to `-2004318072`.

Non-half `ToString` is the uppercase, zero-padded packed hexadecimal value at its exact width. HalfSingle and HalfVector formats print their unpacked scalar/vector using the selected XNA Single formatting projection; examples are `0.333252`, `{X:1 Y:-2}`, and `{X:1 Y:-2 Z:0.5 W:0}`.

## Independent behavior and exhaustive evidence

`behavior/xna40-packed-vector-values.json` contains 68 direct XNA-derived observations, appended to the 125 retained observations for 193 total assertions and zero failures. Group totals are PACKED_ALPHA 6, PACKED_UNSIGNED 16, PACKED_SIGNED 3, PACKED_NORMALIZED 6, PACKED_HALF 20, PACKED_RGBA 10, and PACKED_INTERFACE 7. Fixtures cover every concrete type, packed bits, one-hot lanes, clamps, ties, signed endpoints, half special inputs, explicit-interface mutation/expansion, hash, string, equality, and copy semantics. Expected tables are literal observations from the original XNA runtime and are not generated by the production helper.

`tools/qualify_packed_vector.rb` separately performs semantic sweeps recorded in `docs/generated/packed-vector-exhaustive-report.json`:

| Sweep | Iterations | Failures | Seconds |
| --- | ---: | ---: | ---: |
| Alpha8 | 256 | 0 | 0.001972 |
| Bgr565 | 65,536 | 0 | 2.144460 |
| Bgra4444 | 65,536 | 0 | 3.012282 |
| Bgra5551 | 65,536 | 0 | 2.952966 |
| HalfSingle | 65,536 | 0 | 0.345209 |
| **Total** | **262,400** | **0** | **8.456889** |

RBS 3.4.0 validates 19 declarations, all 171 XNA member identities, and 189 callable projections after property readers/writers are expanded. `IPackedVectorOfT[TPacked]`, its inheritance, constructor overloads, conversion methods, packed accessors, equality, and operators are explicit. The file has zero `untyped` and zero catch-all signatures. Runtime/RBS consistency passes 1,260 assertions.

The full regression with the qualified native library passes 116 runs / 2,578 assertions with zero failures, errors, or skips. The managed-only invocation passes 2,563 assertions and skips six native-only tests. ABI qualification remains 30 functions, 90 signatures, 158 C and 158 Ruby layout measurements, 2 callbacks, and 12 constants with zero missing symbols or mismatches. Native stress remains 20 Game, Texture2D, SpriteBatch, and Game-recreation cycles with zero crashes, observed UAF, or observed double-free; sanitizer status remains NOT_RUN.
