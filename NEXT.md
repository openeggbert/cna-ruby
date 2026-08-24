# Continuation Evidence

## Exact current boundary

Foundation 2 adds a dependency-complete, managed-only geometry/transform cluster without changing the loader, native manifest, ownership model, or desktop canary. Read `docs/generated/*.json` and `docs/geometry-transform-evidence.md` before changing status or counts.

The exact qualified library is supplied externally with `CNA_NATIVE_LIBRARY`; it is never copied into the gem. Its qualification record is in `docs/native-abi.md` and `docs/runtime-capabilities.json`.

## Next dependency-complete milestone

Complete the remaining small managed presentation-value boundary: `Color` and `Rectangle`. Color now has its complete Vector3/Vector4 dependencies available, so its constructors, vector conversions, non-premultiplied conversion, full predefined palette, operators, hash, and formatting can be qualified without native work. Rectangle's five retained ref/out overload identities can be closed in the same value-only boundary.

Do not add unrelated value families, native ABI functions, Content/XNB, or Effects/3D rendering in that milestone. Both types must finish locally strict-clean; preserve all diagnostics for deferred whole families.

## Known engineering constraints

- Ruby assignment aliases value objects; copying is enforced only at binding boundaries and through `dup`/`clone`.
- Uppercase XNA instance methods require an explicit receiver in Ruby source (`self.Exit`, not bare `Exit`).
- Fiddle does not portably pass C structures by value. A C ABI member with such a prototype remains unbound until CNA exposes an audited pointer form or a different bridge is deliberately reviewed.
- HEADLESS proves command execution, lifecycle, and ownership but cannot prove visible pixels.
