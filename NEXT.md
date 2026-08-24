# Continuation Evidence

## Exact current boundary

Foundation 6 closes exactly `ButtonState`, `MouseState`, and `Mouse`: 3 public XNA types, 20 CLR identities, and 19 Ruby identities. It adds four already-existing CNA 0.7.0 Mouse symbols, one fully measured native layout, five button constants, and a signed native-width `System.IntPtr -> Integer` mapping. Read `docs/generated/*.json` and `docs/mouse-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the dependency-contained GamePad input family, and only that family. The regenerated XNA reference dependency graph contains ten currently missing input types: `Buttons`, `GamePad`, `GamePadButtons`, `GamePadCapabilities`, `GamePadDPad`, `GamePadDeadZone`, `GamePadState`, `GamePadThumbSticks`, `GamePadTriggers`, and `GamePadType`. Their already-complete external XNA dependencies are `ButtonState`, `PlayerIndex`, `Vector2`, and the existing geometry closure. The ten missing types contain 129 CLR member identities before the established enum-storage exclusions.

Regenerate canonical CNA capability and dependency evidence before implementation. Do not assume GamePad symbols used by another binding are public in the exact loaded CNA artifact. Do not start Touch, Design converters, native/runtime partial cleanup, Content/XNB, or Effects/3D rendering. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
- Mouse is process-global at the XNA surface but uses the current live Game internally to enter CNA. All four native operations are owner-thread checked; no current/initialized Game, ambiguity, shutdown, or a wrong thread raises before unsafe native access.
- `System.IntPtr` maps to a signed native-width Ruby `Integer`. On the qualified host it is 64 bits; the mapping itself uses `Fiddle::SIZEOF_VOIDP` and preserves negative values through a two's-complement `uint64_t` carrier.
