# CNA-Ruby

CNA-Ruby is implementing a formally measured Ruby projection of the selected Microsoft XNA Framework 4.0 Windows runtime API over the CNA C ABI.

Foundation 8 is functional on the qualified Linux x86-64 desktop MRI runtime, but the selected XNA profile is intentionally incomplete. The strict scoreboard targets 74 types and 1453 members from the 257-type / 2915-member Ruby projection; it remains red for genuine deferred work. See `docs/generated/api-compat-report.json` for authoritative counts.

## Qualified foundation

- MRI Ruby 3.3.8 and Fiddle 1.1.2
- exact CNA C ABI 0.7.0 admission
- centralized native resolver, signature manifest, layouts, result translation, ownership, generation/thread checks, and callback exception containment
- complete mapped MathHelper, Vector2/3/4, Quaternion, Matrix, Plane, Ray, BoundingBox, BoundingSphere, BoundingFrustum, Rectangle, Color, Curve family, the full 19-type `Graphics.PackedVector` family, the managed three-type `VertexElement` descriptor closure, ContainmentType, PlaneIntersectionType, Point, GameTime, PlayerIndex, SpriteSortMode, SpriteEffects, SurfaceFormat, KeyState, Keys, KeyboardState, Keyboard, ButtonState, MouseState, Mouse, the exact ten-type GamePad family, and Texture contract types
- 253 green PURE_XNA_DERIVED managed observations, including exact binary32 geometry, Color, Rectangle, Curve, packed integer bits, XNA half conversion, normalized formats, explicit packed-interface behavior, ButtonState, MouseState, GamePad values, and VertexElement equality/hash/string behavior
- measured partial Game, GraphicsDeviceManager, Viewport, GraphicsDevice, GraphicsResource, Texture2D, and SpriteBatch types
- real native Game lifecycle and GameTime callbacks
- real HEADLESS-qualified viewport, Clear, PNG Texture2D stream decode, SpriteBatch scaled draw, keyboard state capture, canonical Mouse state/position/window-handle routes, and all four canonical GamePad state/capability/vibration routes

HEADLESS proves native execution and command submission, not visible renderer output. Managed Matrix support does not claim Effects, BasicEffect, Model, or 3D rendering. Content/XNB and Effects/3D remain deferred. The old fake ContentManager, BasicEffect, Matrix behavior, no-op Game/graphics/input methods, and synthetic texture behavior are gone.

## Install and load

Build locally without publishing:

```sh
gem build cna-ruby.gemspec
gem install ./cna-ruby-0.1.0.dev0.gem
```

Provide a reviewed CNA C ABI 0.7.0 library by absolute path:

```sh
export CNA_NATIVE_LIBRARY=/absolute/path/to/libcna_c_api.so
ruby -e 'require "cna"; puts CNA::VERSION'
```

The installed gem never searches sibling repositories and contains no CNA native library. Existing legitimate require forms remain available:

```ruby
require "microsoft/xna/framework"
require "microsoft/xna/framework/graphics"
require "microsoft/xna/framework/input"
```

There is intentionally no `microsoft/xna/framework/content` implementation in Foundation 8.

## Evidence

- `plan.md` — normative architecture/status
- `NEXT.md` — exact continuation boundary
- `docs/xna-ruby-mapping.md` — formal language mapping
- `docs/native-abi.md` — reviewed artifact and ABI policy
- `docs/placeholder-audit.md` — every original fake member and disposition
- `docs/geometry-transform-evidence.md` — Foundation 2 managed geometry closure
- `docs/color-rectangle-evidence.md` — Foundation 3 managed presentation-value closure
- `docs/curve-evidence.md` — Foundation 4 managed Curve-family closure
- `docs/packed-vector-evidence.md` — Foundation 5 packed-bit, half, interface, and exhaustive evidence
- `docs/mouse-evidence.md` — Foundation 6 managed MouseState and canonical native Mouse evidence
- `docs/gamepad-evidence.md` — Foundation 7 managed GamePad-family and canonical native controller evidence
- `docs/vertex-element-evidence.md` — Foundation 8 managed vertex-element descriptor closure
- `tools/api_compat/verify.rb` — structural report/strict/leak-only modes
- `tools/native_abi/verify.rb` — compiler-backed header/manifest/export verification
- `tools/run_behavior_corpus.rb` — PURE_XNA_DERIVED managed observations
- `tools/run_native_stress.rb` — explicit lifecycle/GC/thread stress

No physical controller was attached to the qualified host. Disconnected native paths are qualified; positive state/capability flags and physical vibration remain hardware-pending rather than simulated. VertexElement support is managed descriptor behavior only and does not claim vertex declarations, buffers, shaders, or drawing.

Not qualified: Windows, macOS, JRuby, TruffleRuby, MRuby, Opal/browser/Wasm, Android, visible rendering, connected-controller positive paths, Content/XNB, Effects/3D/Model, audio, media, and the remaining XNA families.
