# Continuation Evidence

## Exact current boundary

Foundation 3 adds complete managed Color and Rectangle value types without changing the loader, native manifest, ownership model, or desktop canary. Read `docs/generated/*.json`, `docs/geometry-transform-evidence.md`, and `docs/color-rectangle-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the dependency-contained managed Curve cluster: `Curve`, `CurveKey`, `CurveKeyCollection`, `CurveContinuity`, `CurveLoopType`, and `CurveTangent`. Treat the six types as one all-or-nothing milestone, derive interpolation, tangent, loop, collection, copy, equality, and exceptional behavior from the pinned XNA 4.0 Windows runtime, and require every included type to finish locally strict-clean.

Do not start PackedVector, Design converters, native ABI expansion, Content/XNB, or Effects/3D rendering in that milestone. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
