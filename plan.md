# CNA-Ruby Foundation Plan

This file is the normative description of the current architecture and milestone state. Evidence in generated reports takes precedence over prose counts.

## Boundary

The only native boundary is `Ruby XNA facade -> CNA private runtime -> CNA C ABI 0.7.0 -> CNA`. The binding never resolves C++ symbols and never loads another language binding. MRI Ruby and Fiddle are the only qualified Ruby/native combination.

## Foundation 13 surface

The runtime exposes real, measured implementations for the types recorded by `tools/api_compat/signatures.json`. Missing XNA types and overloads remain absent. ContentManager, BasicEffect, and the old 3D demo surface remain absent rather than simulated. Matrix is a complete managed XNA value type and does not imply 3D rendering support.

Managed work covers complete MathHelper, Vector2, Vector3, Vector4, Quaternion, Matrix, Plane, Ray, BoundingBox, BoundingSphere, BoundingFrustum, Rectangle, Color, Point, GameTime, ContainmentType, PlaneIntersectionType, and selected enum dependencies. Color includes all XNA constructors and conversions, exact packed/fixed-point behavior, and all 141 predefined properties. Rectangle includes all five collapsed ref/out projections and unchecked Int32 behavior. Foundation 4 completes Curve, CurveKey, CurveKeyCollection, CurveContinuity, CurveLoopType, and CurveTangent. Foundation 5 completes both PackedVector interfaces and all 17 packed structs as one managed closure. Foundation 6 completes ButtonState and the managed MouseState value contract, and exposes the process-global Mouse facade through four reviewed CNA 0.7.0 routes. Foundation 7 completes the ten-type GamePad family through four additional reviewed CNA 0.7.0 routes. Foundation 8 completes the managed `VertexElement`, `VertexElementFormat`, and `VertexElementUsage` descriptor closure with exact XNA construction, mutation, equality, hash, and string behavior. Foundation 9 completes only the root `DisplayOrientation` flags enum through the unchanged controlled Ruby enum policy. Foundation 10 completes only the Graphics-namespace `GraphicsDeviceStatus` non-flags enum. Foundation 11 completes only the Graphics-namespace `GraphicsProfile` non-flags enum with `Reach=0` and `HiDef=1`, again through the unchanged ordinary Ruby enum policy. Foundation 12 completes the managed `Viewport` value contract with exact Windows XNA Project/Unproject Single-domain arithmetic and read-only TitleSafeArea value-copy behavior. Foundation 13 completes only the Graphics-namespace `ClearOptions` flags enum with `Target=1`, `DepthBuffer=2`, and `Stencil=4`; it deliberately has no named zero and adds no `GraphicsDevice.Clear` overload. Mouse and GamePad snapshots are copied out of measured native POD layouts; neither facade caches or synthesizes input state.

The strict surface is now 78 types / 1468 Ruby member identities. `ClearOptions` is locally strict-zero and complete. Exactly six partial native/runtime types remain, with 132 missing members; the normal strict report has 363 genuine deferred diagnostics.

## Admission and safety

- Only encoded ABI `0x00000700` is admitted.
- `CNA_NATIVE_LIBRARY` must be an absolute file path when used.
- All Fiddle functions come from one manifest.
- Native errors cross one translation boundary.
- Handles and values have one of OWNED, BORROWED, PARENT_OWNED, PROCESS_GLOBAL, MANAGED_VALUE, or BORROWED_EXTERNAL_SCALAR ownership.
- Game generations bind children to one owner thread and one native Game lifetime.
- Destruction is explicit; no GC finalizer destroys native state.
- Callback closures are retained for the registration lifetime. Ruby exceptions are captured in the callback and re-raised after the C call returns.

## Qualification policy

Normal API strict mode is expected to remain red until the full selected XNA profile is implemented. Leak-only mode, verifier self-tests, the behavior corpus, the ABI probe, unit tests, gem audit, and native canaries must be green for a milestone claim. HEADLESS qualifies execution and native calls, not visible output. The qualified host had no connected controller, so only real disconnected GamePad results and route safety are native-qualified; connected state, positive capabilities, and physical rumble remain `HARDWARE_PENDING`.

## Deferred boundaries

Managed `ClearOptions` completion does not imply the two deferred four-argument `GraphicsDevice.Clear` overloads, depth or stencil clearing, a native clear mask, or renderer support. Managed Viewport completion does not imply the deferred `GraphicsDevice.Viewport` setter, native projection, camera behavior, 3D rendering, GPU state, or renderer capability. `GraphicsProfile` support does not imply either deferred `GraphicsProfile` property, a `GraphicsDevice` constructor, graphics-profile selection, hardware capability detection, feature-level logic, or renderer compatibility. `GraphicsDeviceStatus` support does not imply the deferred `GraphicsDevice.GraphicsDeviceStatus` property, device-loss polling, reset transitions, or device-reset behavior. `DisplayOrientation` support does not imply `GraphicsDeviceManager.SupportedOrientations`, `GameWindow`, orientation events, display rotation, or mobile/platform orientation. `VertexElement` support does not imply `IVertexType`, `VertexDeclaration`, built-in vertex structs, vertex/index buffers, GPU input formats, or draw support. Content/XNB, Effects/BasicEffect, 3D rendering/Model, audio, media, Touch, Design converters, Windows, macOS, browser/Wasm, Android, JRuby, TruffleRuby, MRuby, and Opal are not Foundation 13 support. HEADLESS qualifies the canonical Mouse routes and the returned backend state, but not a physical cursor, visible cursor movement, or a nonzero desktop window handle. Canonical GamePad routes remain qualified with no hardware attached, not positive controller or rumble behavior.
