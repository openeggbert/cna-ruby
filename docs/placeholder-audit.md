# Original Placeholder Audit

This is the Phase 1 audit of every original public member. `REAL` means the old implementation already represented real behavior (none did at the native boundary). Removed members remain verifier-visible as missing.

| Public type | Public member | Original implementation | Classification | Action |
| --- | --- | --- | --- | --- |
| Vector2 | constructor/X/Y/+/-/* | tiny binary64 object | wrong/incomplete XNA shape | replaced with validated binary32 value subset |
| Vector3 | constructor/X/Y/Z | tiny partial value | incomplete XNA shape | removed until dependency-complete geometry milestone |
| Color | constructor/R/G/B/A | simplistic channels | wrong/incomplete XNA shape | replaced with measured partial value type |
| Matrix | constructor/Identity/CreateRotationX/CreateRotationY/CreateTranslation/CreateLookAt/CreatePerspectiveFieldOfView/* | nested arrays and fabricated identity results | placeholder | removed entirely |
| GameTime | elapsed/total readers | non-XNA naming/shape | wrong XNA shape | replaced with exact strict property names and native timing |
| Game | GraphicsDevice/Content setters, Run, Exit | synthetic fields and no-op Run/Exit | placeholder/wrong ownership | removed or replaced by native CNA Game lifecycle |
| Viewport | constructor/Width/Height/AspectRatio | partly constant semantics | incomplete | replaced with real value subset and native device query |
| GraphicsDevice | Viewport/Clear | hard-coded 1280x720 and no-op | placeholder | replaced with callback-borrowed device and real CNA calls |
| GraphicsDeviceManager | constructor/GraphicsDevice | synthetic Ruby device assignment | placeholder/wrong ownership | replaced with Game-owned native manager/device facade |
| SpriteBatch | Begin/End/Draw/DrawRect | all no-op | placeholder | removed DrawRect; replaced selected exact Draw overloads with native CNA work |
| Texture2D | constructor/Width/Height/SetData | synthetic dimensions/no-op | placeholder | removed constructor/SetData; real FromStream subset only |
| BasicEffect | constructor/World/View/Projection/Apply | identity values/no-op | placeholder | removed entirely |
| Keys | Escape | unverified integer module | wrong enum shape | replaced by typed, verified enum values |
| KeyboardState | constructor/IsKeyDown/GetPressedKeys | Ruby array only | incomplete shape | replaced by CNA-compatible measured value snapshot |
| Keyboard | GetState | fabricated empty state | placeholder | replaced by actual CNA input capture |
| ContentManager | constructor/Load | fabricated 256x256 Texture2D | placeholder | removed entirely; Content/XNB deferred |

No known original fake implementation remains callable on the selected public surface.
