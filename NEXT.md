# Continuation Evidence

## Exact current boundary

Foundation 15 closes exactly `Microsoft.Xna.Framework.Graphics.PrimitiveType` as one complete
managed ordinary (non-flags) enum. The pinned contract contains five CLR identities: synthetic
`value__` plus `TriangleList=0`, `TriangleStrip=1`, `LineList=2`, and `LineStrip=3`. The established
enum-storage exclusion leaves four Ruby XNA identities, all present with local diagnostics zero.

Those raw values are the XNA 4.0 renumbering taken from the pinned metadata, not the XNA 3.1 /
Direct3D 9 ordering (`PointList=0`, `LineList=1`, `LineStrip=2`, `TriangleList=3`,
`TriangleStrip=4`, `TriangleFan=5`). XNA 4.0 dropped `PointList` and `TriangleFan` and renumbered
the four survivors from zero, triangles first. A dedicated verifier fixture applies the complete
XNA 3.1 ordering and requires `ENUM_VALUE_MISMATCH`; two further fixtures reject an invented
`PointList=4` and `TriangleFan=5`.

`PrimitiveType` is `flags=false`. As with `DepthFormat`, the declared values look bitwise related
and `1 | 2 == 3` numerically, but `LineStrip` is one ordinary XNA enum literal, not
`TriangleStrip | LineList`. The runtime `@enum_flags` is false, `@enum_mask` is 0, `|` and `&` raise
`TypeError`, and `coerce(4)` raises `RangeError`. A dedicated verifier regression pins that
distinction.

The strict target is 80 types / 1476 member identities: 74 complete, six partial native/runtime
types, and 177 missing. Normal strict retains 361 genuine deferred diagnostics: 177 missing types,
132 missing members, one property mismatch, and 51 overload mismatches. Every unexpected-surface,
other mismatch, leak, allowlist, and unmeasured category is zero. `GraphicsDevice` still exposes
only `IsDisposed`, `Viewport`, and `Clear`, so all nine draw overloads across `DrawPrimitives`,
`DrawIndexedPrimitives`, `DrawInstancedPrimitives`, `DrawUserPrimitives`, and
`DrawUserIndexedPrimitives` remain deferred. `GraphicsDeviceManager` still exposes only its four
selected identities, so `PreferredDepthStencilFormat` remains deferred. The two four-argument
`GraphicsDevice.Clear` overloads remain deferred, and the one property mismatch remains the
deliberately deferred `GraphicsDevice.Viewport` setter.

Foundation 15 changes no CNA function, native manifest, Fiddle binding, layout, callback, or
constant. The six remaining partial types are `Game`, `GraphicsDeviceManager`, `GraphicsDevice`,
`GraphicsResource`, `Texture2D`, and `SpriteBatch`.

## Next dependency-complete milestone

Select exactly `Microsoft.Xna.Framework.Graphics.CubeMapFace` next. The regenerated public-signature
dependency report identifies it as the only remaining eligible candidate: a missing managed enum
with no unmet XNA public-signature dependency, six expected Ruby identities
(`PositiveX=0`, `NegativeX=1`, `PositiveY=2`, `NegativeY=3`, `PositiveZ=4`, `NegativeZ=5`), and one
direct reverse edge from the deferred `GraphicsDevice.SetRenderTarget` (2 overloads). It wins the
established policy by default now that `PrimitiveType` is complete.

This is selection evidence only. Do not infer permission to implement `CubeMapFace`, any
`GraphicsDevice` draw member, `GraphicsDevice.SetRenderTarget`, `RenderTargetCube`,
`GraphicsDeviceManager.PreferredDepthStencilFormat`, either deferred ClearOptions-based
`GraphicsDevice.Clear` overload, or any native rendering work. Do not start the selected milestone
automatically.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. The deferred native Viewport setter remains unbound until CNA exposes an audited pointer form or another bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse and GamePad use the current live Game to enter CNA, retain no stale handle, and reject wrong-thread, ambiguous, and shut-down contexts.
- No controller was attached during Foundation 15 qualification, so positive state, capability, and rumble evidence remains hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`; the qualified host is 64-bit.
- Ordinary (non-flags) Ruby enums reject every undefined raw value. `PrimitiveType` deliberately does not preserve unnamed CLR `Int32` values, so the two XNA 3.1 literals XNA 4.0 dropped cannot re-enter as raw `4` or `5`.
- Enum raw values must be read from the pinned metadata rather than inferred from a renderer, from Direct3D, or from an earlier XNA version. `PrimitiveType` is the first selected type whose XNA 4.0 values differ from the widely reproduced legacy ordering.
- Every `PrimitiveType` raw value 0..3 also exists in `DepthFormat`, `SurfaceFormat`, and `SpriteSortMode`, so cross-enum coercion by raw value stays rejected.
- The Foundation 14 host had no system Ruby. The qualified interpreter was reconstructed from the pinned Debian `ruby3.3` 3.3.8-2 packages under `~/deps/ruby-3.3-debian`, and the reviewed CNA library and its revision-`a09196a6` headers were preserved out of disposable `/tmp` into `~/deps/cna-c-abi-0.7.0`. Foundation 15 reused that toolchain unchanged; the library SHA-256 and all 59 headers re-verified identical.
- The upstream behavior-corpus import source (SHA-256 `398d0201…`) is not present on this reconstructed host, and `tools/import_behavior_corpus.rb` refuses to run without it. The Foundation-15 corpus merge replayed the importer's identical merge and formatting tail over the already-merged corpus; the importer itself was updated so a future run with the real source produces the same file.
