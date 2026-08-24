# Continuation Evidence

## Exact current boundary

Foundation 7 closes exactly `Buttons`, `GamePad`, `GamePadButtons`, `GamePadCapabilities`, `GamePadDPad`, `GamePadDeadZone`, `GamePadState`, `GamePadThumbSticks`, `GamePadTriggers`, and `GamePadType`: 10 public XNA types, 129 CLR identities, and 126 Ruby identities. It adds four already-existing CNA 0.7.0 GamePad symbols, four fully measured native layouts, and 42 measured constants. Read `docs/generated/*.json` and `docs/gamepad-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the dependency-contained vertex-element value family, and only that family: `Microsoft.Xna.Framework.Graphics.VertexElement`, `VertexElementFormat`, and `VertexElementUsage`. A fresh query of the pinned reference metadata gives 3 types, 37 CLR identities, and 35 expected Ruby identities after excluding the two synthetic enum `value__` fields. `VertexElement` has 10 identities; `VertexElementFormat` has 13 CLR / 12 Ruby identities; `VertexElementUsage` has 14 CLR / 13 Ruby identities. Public signatures depend only on these three types and System primitives, so no further XNA type enters the closure.

Treat this as a managed value/enum milestone: derive constructor, mutable property, equality, hash, and string behavior from the pinned XNA assembly before implementation. Do not expand into `VertexDeclaration`, vertex buffers, effects, models, or rendering. Do not start Touch, Design converters, native/runtime partial cleanup, Content/XNB, or another family. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse is process-global at the XNA surface but uses the current live Game internally to enter CNA. All four native operations are owner-thread checked; no current/initialized Game, ambiguity, shutdown, or a wrong thread raises before unsafe native access.
- GamePad follows the same current-Game selection policy without retaining a handle. The four canonical routes return actual CNA snapshots/results. No controller was attached during Foundation 7 qualification, so positive state, capability, and rumble rows remain hardware-pending.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`. On the qualified host it is 64 bits; the mapping itself uses `Fiddle::SIZEOF_VOIDP` and preserves negative values through a two's-complement `uint64_t` carrier.
