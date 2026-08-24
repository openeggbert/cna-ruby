# Continuation Evidence

## Exact current boundary

Foundation 13 closes exactly `Microsoft.Xna.Framework.Graphics.ClearOptions` as one complete
managed flags enum. The pinned contract contains four CLR identities: synthetic `value__` plus
`Target=1`, `DepthBuffer=2`, and `Stencil=4`. The established enum-storage exclusion leaves three
Ruby XNA identities, all present with local diagnostics zero.

ClearOptions declares no zero-valued name and no `All`. Ruby's established controlled flags
mapping nevertheless represents raw zero and combinations through mask `0x7` as typed, frozen,
cached values. No `None`, `Default`, `Empty`, or `All` constant is invented.

The strict target is 78 types / 1468 member identities: 72 complete, six partial native/runtime
types, and 179 missing. Normal strict retains 363 genuine deferred diagnostics: 179 missing types,
132 missing members, one property mismatch, and 51 overload mismatches. Every unexpected-surface,
other mismatch, leak, allowlist, and unmeasured category is zero. The two four-argument
`GraphicsDevice.Clear` overloads remain deferred, so the selected device still exposes only the
existing `Clear(Color)` route. The one property mismatch remains the deliberately deferred
`GraphicsDevice.Viewport` setter.

Foundation 13 changes no CNA function, native manifest, Fiddle binding, layout, callback, or
constant. The six remaining partial types are `Game`, `GraphicsDeviceManager`, `GraphicsDevice`,
`GraphicsResource`, `Texture2D`, and `SpriteBatch`.

## Next dependency-complete milestone

Select exactly `Microsoft.Xna.Framework.Graphics.DepthFormat` next. The regenerated public-
signature dependency report identifies it as a missing managed enum with no unmet XNA public-
signature dependency, four expected Ruby identities, and a direct reverse edge from the deferred
`GraphicsDeviceManager.PreferredDepthStencilFormat` property. It wins the established policy after
ClearOptions completion.

This is selection evidence only. Do not infer permission to implement `DepthFormat`, the manager
property, either deferred ClearOptions-based `GraphicsDevice.Clear` overload, `PrimitiveType`,
`CubeMapFace`, or any native rendering work. Do not start the selected milestone automatically.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. The deferred native Viewport setter remains unbound until CNA exposes an audited pointer form or another bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse and GamePad use the current live Game to enter CNA, retain no stale handle, and reject wrong-thread, ambiguous, and shut-down contexts.
- No controller was attached during Foundation 13 qualification, so positive state, capability, and rumble evidence remains hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`; the qualified host is 64-bit.
