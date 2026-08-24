# Continuation Evidence

## Exact current boundary

Foundation 11 closes exactly `Microsoft.Xna.Framework.Graphics.GraphicsProfile`: one non-flags Int32 enum, 3 CLR identities, and 2 Ruby XNA identities after excluding synthetic enum storage `value__`. It is completely managed and changes no CNA function, native manifest, Fiddle binding, layout, callback, or constant. The deferred `GraphicsDevice.GraphicsProfile` and `GraphicsDeviceManager.GraphicsProfile` properties remain absent, as do constructor and hardware-detection work. Read `docs/generated/*.json` and `docs/graphics-profile-evidence.md` before changing status or counts.

The strict target is 77 types / 1462 member identities: 70 complete, the same seven partial native/runtime types, and 180 missing. The normal strict report retains 369 diagnostics solely for deferred work: 180 missing types, 135 missing members, one property mismatch, and 53 overload mismatches. Every other mismatch/leak/allowlist/unmeasured category is zero.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete exactly the remaining contract of `Microsoft.Xna.Framework.Graphics.Viewport` as the next dependency-contained managed milestone. The regenerated pinned metadata gives 14 CLR/Ruby identities. Eleven are already selected; the exact remainder is `Project`, `Unproject`, and read-only `TitleSafeArea`. `Project` and `Unproject` depend only on the already-complete `Vector3` and `Matrix`; `TitleSafeArea` depends only on the already-complete `Rectangle`. The current type-local diagnostics are the three missing identities plus the two corresponding overload mismatches.

Treat this as completion of the managed Viewport value contract only. Do not use it as permission to implement the mismatched `GraphicsDevice.Viewport` setter, either `GraphicsProfile` property, a `GraphicsDevice` constructor, display-adapter or presentation types, feature-level detection, hardware profile selection, or renderer functionality. The regenerated dependency comparison selects Viewport because its missing public-signature dependencies are already complete and its remainder is the smallest pure managed closure among current partial types; it does not select another namespace-adjacent enum. Do not automatically start `DisplayMode`, `GraphicsAdapter`, `PresentationParameters`, `VertexDeclaration`, `IVertexType`, vertex structs, buffers, effects, models, or rendering. Preserve deferred whole-family diagnostics and the six other partial native/runtime types.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse is process-global at the XNA surface but uses the current live Game internally to enter CNA. All four native operations are owner-thread checked; no current/initialized Game, ambiguity, shutdown, or a wrong thread raises before unsafe native access.
- GamePad follows the same current-Game selection policy without retaining a handle. The four canonical routes return actual CNA snapshots/results. No controller was attached during Foundation 11 regression qualification, so positive state, capability, and rumble rows remain hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`. On the qualified host it is 64 bits; the mapping itself uses `Fiddle::SIZEOF_VOIDP` and preserves negative values through a two's-complement `uint64_t` carrier.
