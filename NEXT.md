# Continuation Evidence

## Exact current boundary

Foundation 12 closes exactly the remaining managed contract of
`Microsoft.Xna.Framework.Graphics.Viewport`. The type moves from 11/14 selected identities and
five local diagnostics to 14/14 and local strict zero by adding only `Project`, `Unproject`, and
read-only `TitleSafeArea`. The direct Windows XNA IL and result-bit evidence is retained in
`docs/viewport-evidence.md` and `behavior/xna40-viewport-values.json`.

The strict target is 77 types / 1465 member identities: 71 complete, six partial native/runtime
types, and 180 missing. Normal strict retains 364 genuine deferred diagnostics: 180 missing types,
132 missing members, one property mismatch, and 51 overload mismatches. Every unexpected-surface,
other mismatch, leak, allowlist, and unmeasured category is zero. The one property mismatch is
still the deliberately deferred `GraphicsDevice.Viewport` setter.

Viewport completion is pure managed XNA value mathematics. It changes no CNA function, native
manifest, Fiddle binding, layout, callback, or constant and claims no camera, 3D, GPU, or renderer
capability. The six remaining partial types are `Game`, `GraphicsDeviceManager`, `GraphicsDevice`,
`GraphicsResource`, `Texture2D`, and `SpriteBatch`.

## Next dependency-complete milestone

Select exactly `Microsoft.Xna.Framework.Graphics.ClearOptions` next. The regenerated public-
signature dependency report gives one flags Int32 enum, four CLR identities, and three expected
Ruby identities after excluding synthetic `value__`: `Target=1`, `DepthBuffer=2`, and `Stencil=4`.
It has no XNA public-signature dependency and is the smallest remaining dependency-complete managed
enum directly referenced by the selected partial remainder, through the two deferred
`GraphicsDevice.Clear` overloads.

This selection is enum completion only. Do not infer permission to implement either deferred Clear
overload, change the already-selected `Clear(Color)` native route, add a `GraphicsDevice`
constructor, implement `GraphicsDevice.Viewport=`, or start rendering/device state. The other
eligible dependency-complete managed enums recorded by the graph are `DepthFormat`,
`PrimitiveType`, and `CubeMapFace`; they are not selected. Do not start this milestone
automatically.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. The deferred native Viewport setter remains unbound until CNA exposes an audited pointer form or another bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse and GamePad use the current live Game to enter CNA, retain no stale handle, and reject wrong-thread, ambiguous, and shut-down contexts.
- No controller was attached during Foundation 12 qualification, so positive state, capability, and rumble evidence remains hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`; the qualified host is 64-bit.
