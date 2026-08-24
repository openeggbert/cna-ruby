# Runtime capabilities

| Capability | Category | Status | Evidence |
| --- | --- | --- | --- |
| `managed.mathhelper-point-gametime` | VERIFIED_MANAGED | verified | behavior corpus and structural verifier |
| `managed.geometry-transform` | VERIFIED_MANAGED | verified complete cluster | Vector2/3/4, Quaternion, Matrix, Plane, Ray, bounds/frustum and dependency enums locally strict-zero |
| `managed.rectangle-color` | VERIFIED_MANAGED | verified partial types | exact missing members reported; unchanged in Foundation 2 |
| `managed.binary32` | VERIFIED_MANAGED | verified selected operations | 88 PURE_XNA_DERIVED observations including signed zero, NaN sign, transform order and degenerate geometry |
| `native.abi-0.7` | VERIFIED_NATIVE | verified | 30 exports, 90 signatures, 158+158 layout measurements, 2 callbacks, 12 constants |
| `native.game-lifecycle` | VERIFIED_NATIVE | verified | Initialize/LoadContent/BeginRun/Update/Draw/EndRun/UnloadContent native ordering |
| `native.callback-exceptions` | VERIFIED_NATIVE | verified | Initialize, LoadContent, Update, Draw containment tests |
| `native.graphics-clear` | VERIFIED_NATIVE | verified HEADLESS | real callback-borrowed device Clear |
| `native.texture2d-stream` | VERIFIED_NATIVE | verified HEADLESS | project PNG decoded as measured 128x128 Texture2D |
| `native.spritebatch-draw` | VERIFIED_NATIVE | verified HEADLESS | real Begin/scaled Draw/End |
| `native.keyboard` | VERIFIED_NATIVE | verified HEADLESS | CNA state capture and typed key queries |
| `native.lifecycle-stress` | VERIFIED_NATIVE | verified | 20 Game/Texture/SpriteBatch/recreation cycles, zero observed crash/UAF/double-free |
| `renderer.visible-output` | BACKEND_BLOCKED | not verified | qualified artifact uses HEADLESS renderer |
| `graphics.viewport-setter` | UPSTREAM_CNA_BLOCKED | unbound | CNA prototype passes CNA_Viewport by value; Fiddle foundation declines unsafe declaration |
| `struct.assignment-copy` | LANGUAGE_MAPPING_LIMITATION | documented | Ruby assignment aliases; copies enforced at binding boundaries |
| `content.xnb` | UNIMPLEMENTED_CNA_RUBY | deferred | fake ContentManager removed |
| `effects.3d-model` | UNIMPLEMENTED_CNA_RUBY | deferred | managed Matrix is qualified; fake BasicEffect/cube support remains removed |
| `audio-media` | UNIMPLEMENTED_CNA_RUBY | deferred | outside Foundation 2 |
| `platform.windows` | PLATFORM_PENDING | not qualified | — |
| `platform.macos` | PLATFORM_PENDING | not qualified | — |
| `platform.browser-wasm` | PLATFORM_PENDING | unsupported | no CNA C-ABI Wasm/Ruby-Wasm architecture |
| `platform.android-mruby` | PLATFORM_PENDING | unsupported | not part of MRI desktop qualification |
| `hardware.visible-renderer` | HARDWARE_PENDING | not run | — |
| `assets.content-pipeline` | ASSET_PENDING | not started | only project-owned PNG stream path qualified |
