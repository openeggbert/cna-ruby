# Continuation Evidence

## Exact current boundary

Foundation 10 closes exactly `Microsoft.Xna.Framework.Graphics.GraphicsDeviceStatus`: one non-flags Int32 enum, 4 CLR identities, and 3 Ruby XNA identities after excluding synthetic enum storage `value__`. It is completely managed and changes no CNA function, native manifest, Fiddle binding, layout, callback, or constant. The deferred `GraphicsDevice.GraphicsDeviceStatus` property remains absent. Read `docs/generated/*.json` and `docs/graphics-device-status-evidence.md` before changing status or counts.

The strict target is 76 types / 1460 member identities: 69 complete, the same seven partial native/runtime types, and 181 missing. The normal strict report retains 370 diagnostics solely for deferred work: 181 missing types, 135 missing members, one property mismatch, and 53 overload mismatches. Every other mismatch/leak/allowlist/unmeasured category is zero.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete exactly `Microsoft.Xna.Framework.Graphics.GraphicsProfile` as the next dependency-contained managed milestone. The regenerated pinned metadata gives one non-flags Int32 enum, 3 CLR identities, and 2 expected Ruby identities after excluding synthetic `value__`: `Reach=0` and `HiDef=1`. Its declared surface depends only on System primitives. In the regenerated graph it is the smallest remaining managed enum closure directly referenced by the existing partial surface, with reverse edges from the `GraphicsDevice` constructor and `GraphicsProfile` property plus `GraphicsDeviceManager.GraphicsProfile`.

Treat it only as the existing typed/frozen non-flags enum projection. Do not use it as permission to implement either `GraphicsProfile` property, a `GraphicsDevice` constructor, feature-level detection, device status, loss/reset behavior, `GraphicsDeviceManager` changes, or platform handling. This selection comes from the regenerated dependency graph, not merely namespace adjacency. Do not automatically start `DisplayMode`, `GraphicsAdapter`, `PresentationParameters`, `VertexDeclaration`, `IVertexType`, vertex structs, buffers, effects, models, or rendering. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

`SELECTED_ONLY=true`

`STARTED=false`

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse is process-global at the XNA surface but uses the current live Game internally to enter CNA. All four native operations are owner-thread checked; no current/initialized Game, ambiguity, shutdown, or a wrong thread raises before unsafe native access.
- GamePad follows the same current-Game selection policy without retaining a handle. The four canonical routes return actual CNA snapshots/results. No controller was attached during Foundation 10 regression qualification, so positive state, capability, and rumble rows remain hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`. On the qualified host it is 64 bits; the mapping itself uses `Fiddle::SIZEOF_VOIDP` and preserves negative values through a two's-complement `uint64_t` carrier.
