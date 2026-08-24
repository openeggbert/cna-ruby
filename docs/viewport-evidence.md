# Foundation 12 Viewport evidence

Foundation 12 closes exactly the three remaining identities of
`Microsoft.Xna.Framework.Graphics.Viewport`: `Project`, `Unproject`, and read-only
`TitleSafeArea`. The existing constructors, mutable `X`, `Y`, `Width`, `Height`, `MinDepth`,
`MaxDepth`, and `Bounds`, read-only `AspectRatio`, `ToString`, and internal `from_native` copy path
remain unchanged. The closure is pure managed value mathematics and adds no CNA route.

## Exact closure

| State | Reference identities | Expected Ruby identities | Target identities | Local diagnostics | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| Before | 14 | 14 | 11 | 5 | `PARTIAL` |
| After | 14 | 14 | 14 | 0 | `COMPLETE` |

The five removed diagnostics are three `MISSING_MEMBER` rows and the single-overload count
mismatch for each method. The exact added signatures are:

```text
Vector3 Project(Vector3 source, Matrix projection, Matrix view, Matrix world)
Vector3 Unproject(Vector3 source, Matrix projection, Matrix view, Matrix world)
Rectangle TitleSafeArea { get; }
```

There is no `TitleSafeArea=` and no lowercase alias. Each method accepts exactly four positional
arguments. The runtime rejects a non-`Vector3` source and any non-`Matrix` projection, view, or
world argument instead of coercing arrays, tuples, hashes, or duck-typed values.

## Pinned reference and derivation

The implementation was derived from the hash-matched XNA 4.0 Windows assemblies, not another
framework or binding:

| Assembly | Version | SHA-256 |
| --- | --- | --- |
| `Microsoft.Xna.Framework.dll` | 4.0.0.0 | `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130` |
| `Microsoft.Xna.Framework.Graphics.dll` | 4.0.0.0 | `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55` |

The retained source probe is `tools/viewport_reference_probe.cs`. It is compiled by the XNA-era
.NET 4 C# compiler and executed against the exact assemblies in the XNA 4.0 Windows GAC under
Wine. The repository retains only probe source and derived observations; it does not package or
copy Microsoft binaries.

Disassembly of the pinned graphics assembly establishes the operation order below. Direct probe
results then qualify the x86 CLR evaluation-stack behavior and every retained golden. A
differentiating case gives transformed clip bits `405B3E15/BF294FCD/3FF353D7` for
`(world * view) * projection`, versus `405B3E16/BF294FD2/3FF353D6` for the alternate association.

## Project algorithm

The reference performs these operations in this exact order:

1. `combined = Matrix.Multiply(Matrix.Multiply(world, view), projection)`.
2. `result = Vector3.Transform(source, combined)`.
3. Using the original source, calculate
   `w = source.X*M14 + source.Y*M24 + source.Z*M34 + M44`, left to right.
4. Call the private `WithinEpsilon(w, 1.0f)`. It subtracts and accepts the inclusive interval
   `[-1.4012984643248171e-45f, +1.4012984643248171e-45f]`. At the representable values adjacent to
   `1.0f`, this is effectively exact Binary32 equality.
5. If the comparison is false, calculate one reciprocal `1.0f / w`, then multiply each transformed
   component by that reciprocal.
6. Map X as `((result.X + 1.0f) * 0.5f * Width) + X`.
7. Map Y as `((-result.Y + 1.0f) * 0.5f * Height) + Y`.
8. Map Z as `result.Z * (MaxDepth - MinDepth) + MinDepth`.

The Y negation is XNA managed viewport mathematics and is independent of the renderer backend.
There is no clamp in X, Y, Z, or depth. Nonzero origin and nondefault depth are therefore visible
in the retained cases.

All incoming Single fields are already Binary32. Matrix and Vector3 result-field stores narrow to
Binary32. The pinned 32-bit CLR retains eligible IL evaluation-stack chains at native floating
precision between those stores, including the W chain, reciprocal, and screen-map expressions.
The implementation models those chains explicitly and narrows at the same struct-field storage
points. This is why Viewport uses private IL-grouped multiplication, transform, division, and
inverse helpers: calling the binding's already-qualified public Matrix/Vector3 helpers was not
bit-equivalent for the differentiating Windows x86 observations. Their public behavior was not
changed.

Representative direct result bits are:

| Case | X bits | Y bits | Z bits |
| --- | --- | --- | --- |
| identity, origin `(13,-7)`, extent `(641,479)`, depth `[0.2,0.85]` | `437D6000` | `42E18000` | `3F300000` |
| asymmetric world/view/projection | `44420EED` | `43942FD4` | `3F32C1C2` |
| W exactly `1.0f` | `43536000` | `431E7000` | `3F200000` |
| W immediately below `1.0f` | `43536000` | `431E7000` | `3F200001` |
| W immediately above `1.0f` | `43536000` | `431E7000` | `3F1FFFFF` |
| W `2.0f` | `433FF000` | `430BF800` | `3EA00000` |

The nontrivial fixture simultaneously distinguishes matrix order, association, row-vector
convention, W division, viewport origin, Y inversion, and nondefault depth. With the qualified
viewport, input Z values `0`, `1`, `0.3`, and `1.5` produce Z bits `3E4CCCCD`, `3F59999A`,
`3ECA3D71`, and `3F966667`; the final value proves the absence of clamping.

## Unproject algorithm

The reference performs:

1. `combined = Matrix.Multiply(Matrix.Multiply(world, view), projection)`.
2. `inverse = Matrix.Invert(combined)`.
3. Normalize input X as `((source.X - X) / Width) * 2.0f - 1.0f`.
4. Normalize input Y as `-(((source.Y - Y) / Height) * 2.0f - 1.0f)`.
5. Normalize input Z as `(source.Z - MinDepth) / (MaxDepth - MinDepth)`.
6. `result = Vector3.Transform(normalized, inverse)`.
7. Calculate W from the normalized pre-transform vector and inverse matrix using
   `X*M14 + Y*M24 + Z*M34 + M44`, in the same left-to-right grouping.
8. Apply the same `WithinEpsilon(w, 1.0f)` decision and reciprocal-multiply division.

The private inverse is an exact transcription of the pinned `Matrix.Invert` IL storage grouping;
it does not add singularity detection or an exception. Representative independent XNA goldens
are:

| Case | X bits | Y bits | Z bits |
| --- | --- | --- | --- |
| identity, nonzero origin/nondefault depth | `BE800000` | `3F000000` | `3F400000` |
| asymmetric matrices and direct screen source | `C01F32F5` | `BEF8831C` | `3F55D950` |
| inverse W exactly `1.0f` | `3E800000` | `BEC00000` | `3F200000` |
| inverse W immediately below `1.0f` | `3E7FFFFE` | `BEBFFFFF` | `3F1FFFFF` |
| inverse W immediately above `1.0f` | `3E800001` | `BEC00002` | `3F200001` |
| inverse W `0.5f` | `3E000000` | `BE400000` | `3EA00000` |

The independent direct goldens are behavioral authority. Additional regression round trips yield
`3EC00003/BFA00001/40200001` for object→Project→Unproject and
`43CDDFFE/42A63FFC/3ED70A3D` for screen→Unproject→Project.

## Edge behavior

No new validation was introduced for viewport field values. Negative width/height and reversed
depth work by the same formulas; one direct Project result is
`C2A4CCCC/40A26666/BF133334`, and the corresponding direct Unproject result is
`BEE718E7/3DC6731A/3F1D1746`. Width or height zero, equal MinDepth/MaxDepth, and a singular
combined matrix flow through Single division and inverse arithmetic to nonfinite results rather
than Ruby `ZeroDivisionError` or a custom singular-matrix exception. NaN and infinities propagate
without `Math` domain exceptions or artificial validation.

The direct Windows probe records signed NaN bit patterns for these edge cases. MRI may canonicalize
the sign of an otherwise equivalent quiet NaN during host floating operations, so the retained
Ruby edge assertions require NaN classification while ordinary finite compatibility is asserted
by exact Binary32 bits. Positive and negative zero otherwise follow ordinary Single arithmetic.

Neither method mutates source, projection, view, or world. Each call creates a new independent
managed `Vector3`; it never returns source, a shared singleton, or cached state.

## TitleSafeArea

The Windows XNA implementation calls its internal `GetTitleSafeArea(x, y, width, height)`, whose
entire pinned implementation constructs `Rectangle(x, y, width, height)`. It therefore equals
`Bounds` on Windows, including nonzero origin, odd dimensions, zero dimensions, and negative
dimensions. Direct cases `(13,-7,641,479)`, `(-11,23,5,7)`, `(3,4,0,1)`, and
`(7,-8,-9,-10)` return those exact rectangles.

The getter returns a fresh managed Rectangle every time. Mutating it cannot mutate the Viewport
or another getter result. It changes none of `X`, `Y`, `Width`, `Height`, `MinDepth`, `MaxDepth`, or
`Bounds`; it performs no platform, display, graphics-device, renderer, Fiddle, or CNA call.

## Structural and scope gates

The completed Viewport has zero local diagnostics in every structural, unexpected-surface, leak,
allowlist, and unmeasured category. Focused mutations cover missing and malformed Project and
Unproject signatures, TitleSafeArea type and mutability, a lowercase alias, a native/handle
parameter, accidental partial selection, and accidental `GraphicsDevice.Viewport=` exposure.

`GraphicsDevice.Viewport` remains getter-only in the selected runtime surface. Its intentionally
deferred setter remains the sole global `PROPERTY_MAPPING_MISMATCH`. No graphics-profile property,
adapter, display mode, presentation parameter, device constructor, renderer state, 3D capability,
or GPU projection work is included.

Foundation 12 changes no CNA ABI function, manifest entry, Fiddle binding, native struct,
constant, callback, or layout. The existing native `GraphicsDevice.Viewport` getter still copies
the unchanged CNA viewport POD through `Viewport.from_native`. The managed closure is classified
only as `VERIFIED_MANAGED`.

## Release qualification

The cumulative suite passes 231 runs / 4,565 assertions with zero failures, errors, or skips. The
focused Viewport suite passes 9 / 128 with the native library unset; verifier mutation/self-tests
pass 71 / 138; RBS 3.4.0 validation and runtime consistency pass 12 / 1,731. The behavior corpus
passes 271 observations / 271 assertions: 267 `PURE_XNA_DERIVED` and four
`RUBY_MAPPING_QUALIFICATION`, including 5 Project, 5 Unproject, and 2 TitleSafeArea observations.

Normal strict is expected-red only for the 364 deferred diagnostics; leak-only passes. The native
ABI remains exactly 38 bound functions, 122 signature measurements, 290 C and 290 Ruby layout
measurements, two callbacks, and 59 constants, with no missing symbol or mismatch. Twenty
Game/Texture2D/SpriteBatch/recreation stress cycles, 50 Mouse and GamePad state cycles, and 20
GamePad capability cycles complete with no crash, observed UAF, or observed double-free.
Sanitizers were not run and remain `NOT_RUN`.

The final `cna-ruby-0.1.0.dev0.gem` has SHA-256
`25ad81c7bc205bbac1a837ea233866c45bc9be71b26cb62c7d8ec6099ff8b8c0`, 37 entries, and no
forbidden entry, bundled native library, or developer path. A fresh exact-GEM_HOME install passes
all 28 installed-source syntax checks, native-unset Viewport goldens, and the unchanged template
at 60 and 600 frames. The maintained source-path template also passes 60 and 600 frames and stays
clean at `42ae209b8b4fd175b7b1e5de43d895083b81877b`.
