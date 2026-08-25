# Continuation Evidence

## Exact current boundary

Foundation 14 closes exactly `Microsoft.Xna.Framework.Graphics.DepthFormat` as one complete managed
ordinary (non-flags) enum. The pinned contract contains five CLR identities: synthetic `value__`
plus `None=0`, `Depth16=1`, `Depth24=2`, and `Depth24Stencil8=3`. The established enum-storage
exclusion leaves four Ruby XNA identities, all present with local diagnostics zero.

`DepthFormat` is `flags=false`. The declared values look bitwise related and `1 | 2 == 3`
numerically, but `Depth24Stencil8` is one ordinary XNA enum literal, not `Depth16 | Depth24`. The
runtime `@enum_flags` is false, `@enum_mask` is 0, `|` and `&` raise `TypeError`, and
`coerce(4)` raises `RangeError`. A dedicated verifier regression pins that distinction.

The strict target is 79 types / 1472 member identities: 73 complete, six partial native/runtime
types, and 178 missing. Normal strict retains 362 genuine deferred diagnostics: 178 missing types,
132 missing members, one property mismatch, and 51 overload mismatches. Every unexpected-surface,
other mismatch, leak, allowlist, and unmeasured category is zero. `GraphicsDeviceManager` still
exposes only its four selected identities, so `PreferredDepthStencilFormat` remains deferred. The
two four-argument `GraphicsDevice.Clear` overloads remain deferred, and the one property mismatch
remains the deliberately deferred `GraphicsDevice.Viewport` setter.

Foundation 14 changes no CNA function, native manifest, Fiddle binding, layout, callback, or
constant. The six remaining partial types are `Game`, `GraphicsDeviceManager`, `GraphicsDevice`,
`GraphicsResource`, `Texture2D`, and `SpriteBatch`.

## Next dependency-complete milestone

Select exactly `Microsoft.Xna.Framework.Graphics.PrimitiveType` next. The regenerated public-
signature dependency report identifies it as a missing managed enum with no unmet XNA public-
signature dependency, four expected Ruby identities, and five direct reverse edges from the deferred
`GraphicsDevice` draw members (`DrawIndexedPrimitives`, `DrawInstancedPrimitives`,
`DrawPrimitives`, `DrawUserIndexedPrimitives`, `DrawUserPrimitives`). It wins the established policy
after DepthFormat completion; `CubeMapFace` is the only other eligible candidate and loses the
fewest-expected-identities tiebreak with six.

This is selection evidence only. Do not infer permission to implement `PrimitiveType`, any
`GraphicsDevice` draw member, `GraphicsDeviceManager.PreferredDepthStencilFormat`, either deferred
ClearOptions-based `GraphicsDevice.Clear` overload, `CubeMapFace`, or any native rendering work.
Do not start the selected milestone automatically.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. The deferred native Viewport setter remains unbound until CNA exposes an audited pointer form or another bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse and GamePad use the current live Game to enter CNA, retain no stale handle, and reject wrong-thread, ambiguous, and shut-down contexts.
- No controller was attached during Foundation 14 qualification, so positive state, capability, and rumble evidence remains hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`; the qualified host is 64-bit.
- Ordinary (non-flags) Ruby enums reject every undefined raw value. `DepthFormat` deliberately does not preserve unnamed CLR `Int32` values, unlike bindings that expose arbitrary raw enum integers.
- The Foundation 14 host had no system Ruby. The qualified interpreter was reconstructed from the pinned Debian `ruby3.3` 3.3.8-2 packages under `~/deps/ruby-3.3-debian`, and the reviewed CNA library and its revision-`a09196a6` headers were preserved out of disposable `/tmp` into `~/deps/cna-c-abi-0.7.0`. The library SHA-256 is unchanged.
