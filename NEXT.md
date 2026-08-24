# Continuation Evidence

## Exact current boundary

Foundation 8 closes exactly `Microsoft.Xna.Framework.Graphics.VertexElement`, `VertexElementFormat`, and `VertexElementUsage`: 3 public XNA types, 37 CLR identities, and 35 Ruby XNA identities after excluding the two synthetic enum `value__` fields. It is completely managed and changes no CNA function, native manifest, Fiddle binding, layout, callback, or constant. Read `docs/generated/*.json` and `docs/vertex-element-evidence.md` before changing status or counts.

The strict target is 74 types / 1453 member identities: 67 complete, the same seven partial native/runtime types, and 183 missing. The normal strict report retains 372 diagnostics solely for deferred work: 183 missing types, 135 missing members, one property mismatch, and 53 overload mismatches. Every other mismatch/leak/allowlist/unmeasured category is zero.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete exactly `Microsoft.Xna.Framework.DisplayOrientation` as the next dependency-contained managed milestone. The regenerated pinned metadata gives one flags enum, 5 CLR identities, and 4 expected Ruby identities after excluding synthetic `value__`: `Default=0`, `LandscapeLeft=1`, `LandscapeRight=2`, and `Portrait=4`. Its declared surface depends only on System primitives, and it is an actual public signature dependency of the deferred framework/graphics-device-management surface.

Treat it only as the existing typed/frozen flags-enum projection. Do not use it as permission to expand `GraphicsDeviceManager`, orientation/device reset behavior, GameWindow, or platform handling. This choice comes from the regenerated dependency graph, not from adjacency to VertexElement. In particular, do not automatically start `VertexDeclaration`, `IVertexType`, vertex structs, buffers, effects, models, or rendering. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse is process-global at the XNA surface but uses the current live Game internally to enter CNA. All four native operations are owner-thread checked; no current/initialized Game, ambiguity, shutdown, or a wrong thread raises before unsafe native access.
- GamePad follows the same current-Game selection policy without retaining a handle. The four canonical routes return actual CNA snapshots/results. No controller was attached during Foundation 8 regression qualification, so positive state, capability, and rumble rows remain hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`. On the qualified host it is 64 bits; the mapping itself uses `Fiddle::SIZEOF_VOIDP` and preserves negative values through a two's-complement `uint64_t` carrier.
