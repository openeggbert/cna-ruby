# Continuation Evidence

## Exact current boundary

Foundation 4 adds the complete managed Curve family without changing the loader, native manifest, ownership model, desktop canary, or starter template. Read `docs/generated/*.json`, `docs/geometry-transform-evidence.md`, `docs/color-rectangle-evidence.md`, and `docs/curve-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the dependency-contained managed `Microsoft.Xna.Framework.Graphics.PackedVector` cluster: all 17 packed value structs plus `IPackedVector` and `IPackedVector<T>`. Treat packing, half conversion, normalization, interfaces, constructors, equality/hash/operators, and binary32 edge behavior as one all-or-nothing milestone derived from the pinned XNA 4.0 Windows runtime.

Do not start Design converters, native ABI expansion, Content/XNB, or Effects/3D rendering in that milestone. Preserve all diagnostics for deferred whole families and the seven remaining native partial types.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
