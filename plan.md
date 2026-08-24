# CNA-Ruby Foundation Plan

This file is the normative description of the current architecture and milestone state. Evidence in generated reports takes precedence over prose counts.

## Boundary

The only native boundary is `Ruby XNA facade -> CNA private runtime -> CNA C ABI 0.7.0 -> CNA`. The binding never resolves C++ symbols and never loads another language binding. MRI Ruby and Fiddle are the only qualified Ruby/native combination.

## Foundation 4 surface

The runtime exposes real, measured implementations for the types recorded by `tools/api_compat/signatures.json`. Missing XNA types and overloads remain absent. ContentManager, BasicEffect, and the old 3D demo surface remain absent rather than simulated. Matrix is a complete managed XNA value type and does not imply 3D rendering support.

Managed work covers complete MathHelper, Vector2, Vector3, Vector4, Quaternion, Matrix, Plane, Ray, BoundingBox, BoundingSphere, BoundingFrustum, Rectangle, Color, Point, GameTime, ContainmentType, PlaneIntersectionType, and selected enum dependencies. Color includes all XNA constructors and conversions, exact packed/fixed-point behavior, and all 141 predefined properties. Rectangle includes all five collapsed ref/out projections and unchecked Int32 behavior. Foundation 4 also completes Curve, CurveKey, CurveKeyCollection, CurveContinuity, CurveLoopType, and CurveTangent, including XNA reference identity, sorted collection behavior, binary32 interpolation, loop modes, and tangent generation. Native work is unchanged from Foundation 1: Game callbacks, GraphicsDeviceManager, callback-borrowed GraphicsDevice, Viewport, Texture2D encoded-stream loading, SpriteBatch's qualified scaled-draw subset, and Keyboard state.

## Admission and safety

- Only encoded ABI `0x00000700` is admitted.
- `CNA_NATIVE_LIBRARY` must be an absolute file path when used.
- All Fiddle functions come from one manifest.
- Native errors cross one translation boundary.
- Handles have one of OWNED, BORROWED, PARENT_OWNED, PROCESS_GLOBAL, or MANAGED_VALUE ownership.
- Game generations bind children to one owner thread and one native Game lifetime.
- Destruction is explicit; no GC finalizer destroys native state.
- Callback closures are retained for the registration lifetime. Ruby exceptions are captured in the callback and re-raised after the C call returns.

## Qualification policy

Normal API strict mode is expected to remain red until the full selected XNA profile is implemented. Leak-only mode, verifier self-tests, the behavior corpus, the ABI probe, unit tests, gem audit, and native canaries must be green for a milestone claim. HEADLESS qualifies execution and native calls, not visible output.

## Deferred boundaries

Content/XNB, Effects/BasicEffect, 3D rendering/Model, audio, media, packed vectors, Design converters, Windows, macOS, browser/Wasm, Android, JRuby, TruffleRuby, MRuby, and Opal are not Foundation 4 support.
