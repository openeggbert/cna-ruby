# Continuation Evidence

## Exact current boundary

Foundation 5 adds the complete 19-type managed PackedVector family without changing the native manifest, ownership model, desktop canary, or starter template. Read `docs/generated/*.json` and `docs/packed-vector-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the dependency-contained Mouse input cluster: `Microsoft.Xna.Framework.Input.ButtonState`, `MouseState`, and `Mouse`. The regenerated reference closure is three public types and 20 CLR member identities (19 Ruby identities after the existing synthetic enum-storage exclusion). Treat button enum identity, the complete MouseState value contract, process-global Mouse behavior, pointer-sized `WindowHandle`, and any already-available CNA 0.7.0 input bridge needed by Mouse as one milestone.

Do not start GamePad, Touch, Design converters, native/runtime partial cleanup, Content/XNB, or Effects/3D rendering in that milestone. Preserve all diagnostics for deferred whole families and the seven remaining native partial types. Regenerate authoritative dependency and ABI evidence before implementation; do not assume the existing Ruby manifest already exposes Mouse functions.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
