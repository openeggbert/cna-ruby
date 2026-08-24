# Color and Rectangle Evidence

This document records the managed-only Foundation Milestone 3 closure. The pinned Microsoft XNA Framework 4.0 Windows runtime metadata and implementation are authoritative. CNA and the sibling language bindings were used only as engineering references; no CNA ABI member was added or called by either value type.

The reference assembly is `Microsoft.Xna.Framework.dll` with SHA-256 `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`.

## Color

### Construction and packing

The public Ruby dispatcher retains all six XNA constructors and the established parameterless struct-default projection:

- three or four `Integer` arguments select the Int32 family; each argument must be in the Int32 domain and is then clamped to a byte;
- three or four `Float` arguments select the Single family;
- mixed Integer/Float channels are rejected rather than selecting an accidental overload;
- `Vector3` and `Vector4` are accepted as the two vector families, with `Vector3` supplying alpha `1.0`;
- vectors are read and packed at construction, so later source mutation cannot affect the Color.

Single channels are narrowed at each XNA binary32 boundary. Packing performs binary32 `value * 255.0f`, handles NaN as zero and infinities as the appropriate endpoint, clamps to `[0, 255]`, and applies `Math.Round` ties-to-even. Tests retain zero, one, half, just-outside range values, binary32 midpoint cases, subnormals, NaN, and both infinities.

`PackedValue` has the XNA layout `R | (G << 8) | (B << 16) | (A << 24)`. Its setter accepts only the mapped UInt32 domain and never truncates an out-of-range Ruby Integer. Channel setters retain the mapped Byte domain. `Transparent` is explicitly the XNA value `0x00000000`, or R:0 G:0 B:0 A:0.

### Vector and non-premultiplied conversions

`ToVector3` and `ToVector4` divide each byte by `255.0f` at a binary32 boundary and return fresh vectors. The corpus and unit tests retain exact bits for channels 0, 1, 127, 128, 254, and 255.

`FromNonPremultiplied(Vector4)` first multiplies each RGB Single by W in binary32 order and then uses the same XNA UNorm packer; W itself supplies alpha. `FromNonPremultiplied(Int32, Int32, Int32, Int32)` uses signed 64-bit-equivalent products, truncating integer division by 255, and clamps the results and alpha to bytes. These are separate retained overload identities and are not routed through one approximate floating-point path.

### Palette, arithmetic, and value semantics

All 141 public predefined XNA Color properties are implemented, closing the 137 that were previously absent. The production packed constants were transcribed from the pinned XNA property bodies. A separate golden table in `test/test_color.rb`, independently retained with the reference assembly digest, checks every name and packed value. Every property constructs a new mutable Color; representative mutation tests prove later calls and sibling results remain independent.

`Lerp` uses XNA's 16.16 fixed-point fraction produced by `PackUNorm(65536.0f, amount)`, including clamping and non-finite behavior. `Multiply` and `operator *` use XNA's binary32 scale-to-fixed conversion, unsigned saturation, shift, and per-channel byte saturation. The retained tests cover negative, zero, half, one, values above one, NaN, and infinities.

Equality compares the exact four channel values, equivalent to packed-value identity. `GetHashCode` returns the packed UInt32 reinterpreted as a signed Int32; it does not use Ruby's randomized hash. `ToString` is the mapped XNA form `{R:r G:g B:b A:a}`. `dup`, `clone`, vector conversions, and static properties produce independent values under `CNA::Runtime::ValueSemantics`; Ruby assignment aliasing remains the documented language limitation.

## Rectangle

### Complete contract and ref/out mapping

The complete Rectangle contract was re-audited: construction; X/Y/Width/Height; Left/Right/Top/Bottom; Location/Center; Empty/IsEmpty; both Offset forms; Inflate; all Contains forms; Intersects; Intersect; Union; equality/operators; hash; and string formatting.

The five previously missing CLR identities are retained separately in generated signatures and RBS:

- `Contains(ref Point, out Boolean)`;
- `Contains(ref Rectangle, out Boolean)`;
- `Intersects(ref Rectangle, out Boolean)`;
- `Intersect(ref Rectangle, ref Rectangle, out Rectangle)`;
- `Union(ref Rectangle, ref Rectangle, out Rectangle)`.

Under the established mapping, a `ref` input is an ordinary typed Ruby value and one `out` value is the ordinary Ruby return. These identities therefore collapse onto the same runtime shapes as their value forms. No Color/Rectangle-specific ref convention or public `*Ref` method was introduced.

### Boundaries, degeneracy, and overflow

Point containment is left/top inclusive and right/bottom exclusive. A zero-width or zero-height rectangle contains no point. Rectangle values are never normalized: negative dimensions, zero-area rectangles, and wrapped edges participate in the exact four comparisons used by XNA. Consequently an interior zero- or negative-extent rectangle can satisfy `Intersects`, while mere edge contact does not.

`Intersect` returns `Rectangle.Empty` unless both derived overlap extents are strictly positive. `Union` applies the raw XNA edge extrema even to empty, negative, and wrapped rectangles. Tests retain separation, edge contact, one-unit overlap, containment, identity, Empty, degenerate extents, and Int32 boundary cases.

All observable Rectangle arithmetic is unchecked Int32 arithmetic: Right, Bottom, Center, Offset, Inflate, and the derived Intersect/Union dimensions wrap at 32 bits. Center also reproduces CLR integer division's truncation toward zero for negative odd extents. The dedicated tests retain both Int32 endpoints and cross-boundary results.

Location and Center return fresh Points. Location assignment copies the Point fields; `dup`, `clone`, and `Empty` return independent values.

## Structural and behavioral closure

- structural target: 33 types / 1053 members;
- Color: 165 expected / 165 target members / zero local diagnostics;
- Rectangle: 33 expected / 33 target members / zero local diagnostics;
- complete target types: 26; partial target types: 7; missing reference types: 224;
- behavior corpus: 104 PURE_XNA_DERIVED observations / 104 assertions / zero failures, including 13 Color and 13 Rectangle observations;
- generated presentation RBS: 2 types / 40 XNA constructor and method identities, plus the established two parameterless default-value projections;
- no `untyped` or catch-all signature remains for either type;
- native ABI inventory remains unchanged.
