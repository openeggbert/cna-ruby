# CNA-Ruby

CNA-Ruby is implementing a formally measured Ruby projection of the selected Microsoft XNA Framework 4.0 Windows runtime API over the CNA C ABI.

Foundation 3 is functional on the qualified Linux x86-64 desktop MRI runtime, but the selected XNA profile is intentionally incomplete. The strict scoreboard targets 33 types and 1053 members from the 257-type / 2915-member Ruby projection; it remains red for genuine deferred work. See `docs/generated/api-compat-report.json` for authoritative counts.

## Qualified foundation

- MRI Ruby 3.3.8 and Fiddle 1.1.2
- exact CNA C ABI 0.7.0 admission
- centralized native resolver, signature manifest, layouts, result translation, ownership, generation/thread checks, and callback exception containment
- complete mapped MathHelper, Vector2/3/4, Quaternion, Matrix, Plane, Ray, BoundingBox, BoundingSphere, BoundingFrustum, Rectangle, Color, ContainmentType, PlaneIntersectionType, Point, GameTime, PlayerIndex, SpriteSortMode, SpriteEffects, SurfaceFormat, KeyState, Keys, KeyboardState, Keyboard, and Texture contract types
- 104 green PURE_XNA_DERIVED managed observations, including exact binary32 geometry, Color, and Rectangle evidence
- measured partial Game, GraphicsDeviceManager, Viewport, GraphicsDevice, GraphicsResource, Texture2D, and SpriteBatch types
- real native Game lifecycle and GameTime callbacks
- real HEADLESS-qualified viewport, Clear, PNG Texture2D stream decode, SpriteBatch scaled draw, and keyboard state capture

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

There is intentionally no `microsoft/xna/framework/content` implementation in Foundation 3.

## Evidence

- `plan.md` — normative architecture/status
- `NEXT.md` — exact continuation boundary
- `docs/xna-ruby-mapping.md` — formal language mapping
- `docs/native-abi.md` — reviewed artifact and ABI policy
- `docs/placeholder-audit.md` — every original fake member and disposition
- `docs/geometry-transform-evidence.md` — Foundation 2 managed geometry closure
- `docs/color-rectangle-evidence.md` — Foundation 3 managed presentation-value closure
- `tools/api_compat/verify.rb` — structural report/strict/leak-only modes
- `tools/native_abi/verify.rb` — compiler-backed header/manifest/export verification
- `tools/run_behavior_corpus.rb` — PURE_XNA_DERIVED managed observations
- `tools/run_native_stress.rb` — explicit lifecycle/GC/thread stress

Not qualified: Windows, macOS, JRuby, TruffleRuby, MRuby, Opal/browser/Wasm, Android, visible rendering, Content/XNB, Effects/3D/Model, audio, media, and the remaining XNA families.
