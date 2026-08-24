# Runtime capabilities

| Capability | Category | Status | Evidence |
| --- | --- | --- | --- |
| `managed.mathhelper-point-gametime` | VERIFIED_MANAGED | verified | behavior corpus and structural verifier |
| `managed.geometry-transform` | VERIFIED_MANAGED | verified complete cluster | Vector2/3/4, Quaternion, Matrix, Plane, Ray, bounds/frustum and dependency enums locally strict-zero |
| `managed.rectangle-color` | VERIFIED_MANAGED | verified complete cluster | Color and Rectangle locally strict-zero with packed/fixed-point and unchecked Int32 evidence |
| `managed.curve` | VERIFIED_MANAGED | verified complete cluster | Curve, CurveKey, collection and enum closure locally strict-zero |
| `managed.packed-vector` | VERIFIED_MANAGED | verified complete cluster | 19 types / 171 XNA identities, 68 golden observations and 262400 exhaustive iterations |
| `managed.vertex-element` | VERIFIED_MANAGED | verified complete descriptor cluster | VertexElement, VertexElementFormat and VertexElementUsage: 37 CLR / 35 Ruby identities, exact Int32 mutation, equality, smart-memory hash and string behavior |
| `managed.button-state` | VERIFIED_MANAGED | verified complete type | Released=0, Pressed=1; typed frozen non-flags enum; locally strict-zero |
| `managed.mouse-state` | VERIFIED_MANAGED | verified complete type | 14/14 identities; exact constructor, properties, equality, XOR hash, string, Int32 extremes, and independent copies |
| `managed.gamepad.enums` | VERIFIED_MANAGED | verified complete types | Buttons 25/25 Ruby identities with flags composition; GamePadDeadZone 3/3; GamePadType 10/10 including BigButtonPad=768 |
| `managed.gamepad-buttons` | VERIFIED_MANAGED | verified complete type | 17/17 identities; eleven physical properties only; XNA equality, smart-memory hash, string, copy semantics |
| `managed.gamepad-dpad` | VERIFIED_MANAGED | verified complete type | 10/10 identities; asymmetric constructor/property ordering; equality, smart-memory hash, string |
| `managed.gamepad-triggers` | VERIFIED_MANAGED | verified complete type | 8/8 identities; binary32 Math.Min/Max clamp, NaN/infinity/signed-zero, equality/hash/string |
| `managed.gamepad-thumbsticks` | VERIFIED_MANAGED | verified complete type | 8/8 identities; XNA square component clamp, NaN/infinity, nested Vector2 copies, equality/hash/string |
| `managed.gamepad-state` | VERIFIED_MANAGED | verified complete type | 15/15 identities; both constructors, Buttons[] projection, all-flags query, exact virtual thresholds, nested copies, equality/hash/string |
| `managed.gamepad-capabilities` | VERIFIED_MANAGED | verified complete type | 26/26 read-only properties, no public constructor, private independent native snapshots |
| `managed.intptr` | VERIFIED_MANAGED | verified signed native-width mapping | System.IntPtr maps to Integer; Fiddle::SIZEOF_VOIDP=8 on the qualified host; exact signed range and two's-complement native carrier |
| `managed.binary32` | VERIFIED_MANAGED | verified selected operations | 253 PURE_XNA_DERIVED observations including signed zero, NaN sign, transforms, Curve, packed bits, XNA half behavior, MouseState, GamePad values, and VertexElement |
| `native.abi-0.7` | VERIFIED_NATIVE | verified | 38 exports, 122 signatures, 290+290 layout measurements, 2 callbacks, 59 constants |
| `native.game-lifecycle` | VERIFIED_NATIVE | verified | Initialize/LoadContent/BeginRun/Update/Draw/EndRun/UnloadContent native ordering |
| `native.callback-exceptions` | VERIFIED_NATIVE | verified | Initialize, LoadContent, Update, Draw containment tests |
| `native.graphics-clear` | VERIFIED_NATIVE | verified HEADLESS | real callback-borrowed device Clear |
| `native.texture2d-stream` | VERIFIED_NATIVE | verified HEADLESS | project PNG decoded as measured 128x128 Texture2D |
| `native.spritebatch-draw` | VERIFIED_NATIVE | verified HEADLESS | real Begin/scaled Draw/End |
| `native.keyboard` | VERIFIED_NATIVE | verified HEADLESS | CNA state capture and typed key queries |
| `native.mouse.get-state` | VERIFIED_NATIVE | verified HEADLESS | real cna_mouse_get_state snapshots copied into distinct managed MouseState values; 50 stress calls |
| `native.mouse.set-position` | VERIFIED_NATIVE | verified canonical route | real cna_mouse_set_position call with exact Int32 validation; HEADLESS does not qualify physical cursor movement or round trip |
| `native.mouse.window-handle.get` | VERIFIED_NATIVE | verified canonical route | real cna_mouse_get_window_handle call; zero/null and signed IntPtr conversion qualified |
| `native.mouse.window-handle.set` | VERIFIED_NATIVE | verified canonical route | real cna_mouse_set_window_handle call; safe same-token/zero operation qualified; CNA never owns or frees the external token |
| `native.mouse.thread-generation` | VERIFIED_NATIVE | verified | owner-thread rejection and retry; shutdown rejection; Game-1 to Game-2 context reselection; central native error propagation |
| `native.gamepad.get-state.basic` | VERIFIED_NATIVE_ROUTE | verified canonical route | real cna_gamepad_get_state for all four player slots; HEADLESS returned CNA disconnected snapshots with real packet field; connected positive path HARDWARE_PENDING |
| `native.gamepad.get-state.none` | VERIFIED_NATIVE_ROUTE | verified canonical route | real cna_gamepad_get_state_with_dead_zone(None); exact XNA clamping algorithm reviewed; nonzero analog hardware evidence HARDWARE_PENDING |
| `native.gamepad.get-state.independent-axes` | VERIFIED_NATIVE_ROUTE | verified canonical route | default and explicit IndependentAxes routes executed; XNA thresholds left=7849/32767, right=8689/32767, trigger=30/255; boundary behavior managed-verified |
| `native.gamepad.get-state.circular` | VERIFIED_NATIVE_ROUTE | verified canonical route | real Circular route executed; exact radial XNA algorithm reviewed; nonzero analog hardware evidence HARDWARE_PENDING |
| `native.gamepad.get-capabilities` | VERIFIED_NATIVE_ROUTE | verified canonical route | real cna_gamepad_get_capabilities for all four slots; each of 26 properties explicitly mapped; positive flags HARDWARE_PENDING |
| `native.gamepad.set-vibration` | VERIFIED_NATIVE_ROUTE | verified canonical route | real cna_gamepad_set_vibration all-off request returned backend false; XNA UInt16 conversion retained; positive motor actuation HARDWARE_PENDING |
| `native.gamepad.thread-generation` | VERIFIED_NATIVE | verified | all three routes reject wrong thread before native entry; shutdown/ambiguity rejection; Game-1 to Game-2 reselection; central error propagation |
| `native.lifecycle-stress` | VERIFIED_NATIVE | verified | 20 Game/Texture/SpriteBatch/recreation cycles, 50 Mouse and 50 GamePad state calls, 20 GamePad capability calls; zero observed crash/UAF/double-free |
| `mouse.physical-cursor` | BACKEND_BLOCKED | not verified | qualified artifact uses HEADLESS; no visible cursor or SetPosition/GetState physical round trip is claimed |
| `mouse.nonzero-window-handle` | PLATFORM_PENDING | not exercised | HEADLESS safely qualifies zero and same-token get/set, not an arbitrary real desktop window |
| `gamepad.connected-state` | HARDWARE_PENDING | not exercised | no controller connected on the qualified host; disconnected native-negative routes are verified |
| `gamepad.positive-capabilities` | HARDWARE_PENDING | not exercised | HEADLESS/no-controller snapshots honestly report Unknown and false; no positive device flags claimed |
| `gamepad.physical-vibration` | HARDWARE_PENDING | not exercised | canonical route returned false with no controller; no nonzero or looping rumble request was issued |
| `gamepad.voice-support-positive` | PLATFORM_PENDING | not exercised | CNA exposes the real per-device voice capability; qualified Linux platform returned false with no controller |
| `renderer.visible-output` | BACKEND_BLOCKED | not verified | qualified artifact uses HEADLESS renderer |
| `graphics.viewport-setter` | UPSTREAM_CNA_BLOCKED | unbound | CNA prototype passes CNA_Viewport by value; Fiddle foundation declines unsafe declaration |
| `struct.assignment-copy` | LANGUAGE_MAPPING_LIMITATION | documented | Ruby assignment aliases; copies enforced at binding boundaries |
| `content.xnb` | UNIMPLEMENTED_CNA_RUBY | deferred | fake ContentManager removed |
| `effects.3d-model` | UNIMPLEMENTED_CNA_RUBY | deferred | managed Matrix is qualified; fake BasicEffect/cube support remains removed |
| `audio-media` | UNIMPLEMENTED_CNA_RUBY | deferred | outside Foundation 8 |
| `platform.windows` | PLATFORM_PENDING | not qualified | — |
| `platform.macos` | PLATFORM_PENDING | not qualified | — |
| `platform.browser-wasm` | PLATFORM_PENDING | unsupported | no CNA C-ABI Wasm/Ruby-Wasm architecture |
| `platform.android-mruby` | PLATFORM_PENDING | unsupported | not part of MRI desktop qualification |
| `hardware.visible-renderer` | HARDWARE_PENDING | not run | — |
| `assets.content-pipeline` | ASSET_PENDING | not started | only project-owned PNG stream path qualified |
