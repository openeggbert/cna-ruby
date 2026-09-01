# CNA-Ruby Foundation Plan

This file is the normative description of the **current** architecture and milestone state. Every
count in it is a measurement, and the generated reports take precedence over this prose whenever the
two disagree — `docs/generated/api-compat-report.json`,
`docs/generated/public-signature-dependency-report.json`,
`docs/generated/native-abi-report.json`, `docs/generated/behavior-corpus-report.json` and
`docs/runtime-capabilities.json` are the authorities. `NEXT.md` is the chronological record of how
the project reached this state; this file is what is true of it now.

## Boundary

The only native boundary is `Ruby XNA facade -> CNA private runtime -> CNA C ABI -> CNA`. The
binding never resolves C++ symbols and never loads another language binding. MRI Ruby and Fiddle are
the only qualified Ruby/native combination.

The admitted ABI is a **measured set**, not a single version and not a version range. The manifest
admits encoded `0x00000700` (CNA 0.7.0) and `0x00001500` (CNA 0.21.0), because CNA's own contract
rules out both easy policies: `0.x` is experimental, so a later minor may be incompatible — `0.20.0`
really was — and the incompatibility travels forward rather than backward, so neither "same major"
nor "minimum minor" is sound. Admission is qualified by measuring both header roots and requiring
them to agree over the whole bound surface; `docs/native-abi-migration-evidence.md` records the
derivation and `test/test_native_abi_gate.rb` carries sixteen mutation controls that prove the gate
fails when it should.

## Surface

The strict surface is **165 types / 1998 Ruby member identities**: 160 complete, 5 partial, 92 of the
257 reference types still missing, with 231 deferred diagnostics of which 96 are missing members and
40 are the overload category. Every structural category except `MISSING_TYPE`, `MISSING_MEMBER`,
`OVERLOAD_MAPPING_MISMATCH` and one long-standing `PROPERTY_MAPPING_MISMATCH`
(`GraphicsDevice::Viewport`) is zero, the allowlist is empty and `UNMEASURED_STRUCTURAL_CATEGORY` is
zero. **26** event identities are projected across **13** owner types with `EVENT_MAPPING_MISMATCH`
zero, and **22** BCL identities go through the measured `CNA::Runtime::BclProjection` register.

The five partial types are the graphics runtime: `GraphicsDeviceManager` (15 members outstanding),
`GraphicsDevice` (39), `GraphicsResource` (3), `Texture2D` (7) and `SpriteBatch` (4) — 68 of the 96
outstanding members between them, which is why a qualification artifact with a real renderer is the
single largest lever this project has left. `GraphicsDeviceManager`'s own remainder is no longer
about the renderer: eleven of its members were closed by projecting the preferred settings, and the
fifteen left are the four device events, their raisers, `PreparingDeviceSettings` and
`Dispose(Boolean)` — which `docs/graphics-device-service-producer-audit.md` defers — plus the three
that name the missing `GraphicsDeviceInformation`.

Complete clusters, by area:

- **Math and value types** — MathHelper, Vector2/3/4, Quaternion, Matrix, Plane, Ray, BoundingBox,
  BoundingSphere, BoundingFrustum, Rectangle, Color, Point, the Curve family, the 19-type
  `Graphics.PackedVector` closure and the `VertexElement` descriptor closure.
- **Game** — `Game`, `GameTime`, `GameComponent`, `GameComponentCollection`, `GameServiceContainer`,
  `GameWindow`, `LaunchParameters`, `FrameworkDispatcher`, `TitleContainer` and
  `GamerServices.GamerServicesComponent`, with a real component engine and real lifecycle events.
- **Content** — `ContentManager` over CNA's own content pipeline, `Game.Content` bound to the
  content manager CNA's game already owns, `ResourceContentManager`, and the five
  `ContentSerializer*` attributes.
- **Audio — complete.** Every XNA 4.0 `Audio` type is projected: `SoundEffect`,
  `SoundEffectInstance`, `DynamicSoundEffectInstance`, `Microphone`, `AudioEngine`, `AudioCategory`,
  `WaveBank`, `SoundBank`, `Cue`, the managed `AudioListener`/`AudioEmitter`/`RendererDetail`, the
  four enums and the three exception types.
- **Input** — Keyboard, Mouse, the ten-type GamePad family and the `Input.Touch` closure.
- **Media** — `VisualizationData`, `Video` and `MediaSource`.
- **Graphics** — `SpriteFont` over a real MonoGame font, `Viewport`, `TextureCollection`, `Texture`,
  `DisplayMode`, `DisplayModeCollection`, `PresentationParameters` and the enum closure, beside the
  five partial runtime types.

## Admission and safety

- The admitted encoded ABI versions are `0x00000700` and `0x00001500`, cross-verified across both
  header roots; `CROSS_VERSION_MISMATCHES` is zero over the whole bound surface.
- `CNA_NATIVE_LIBRARY` must be an absolute file path when used.
- All Fiddle functions come from one manifest: **224** functions, **5** callbacks, **71** constants
  and **27** struct layouts, each type-checked against the headers by a compiler-backed probe with
  `_Static_assert(__builtin_types_compatible_p(...))`, and each Ruby layout compared field by field
  with the C one. `ABI_MISMATCHES` is zero.
- Native errors cross one translation boundary.
- Handles and values have one of OWNED, BORROWED, PARENT_OWNED, PROCESS_GLOBAL, MANAGED_VALUE, or
  BORROWED_EXTERNAL_SCALAR ownership, and the manifest records which for every route.
- Game generations bind children to one owner thread and one native Game lifetime.
- Destruction is explicit; **no GC finalizer destroys native state**. Where CNA requires an order
  XNA does not — a sound bank's cues before the bank, an engine's banks before the engine — the
  parent cascades, and that is recorded as a deviation rather than presented as XNA behaviour.
- Callback closures are retained for the registration lifetime. Ruby exceptions are captured in the
  callback and re-raised after the C call returns.
- Fiddle cannot pass a struct by value, so `CNA_StringView` is decomposed into the eightbytes the
  System V x86-64 ABI really puts in registers; the decomposition is recorded in the manifest and
  reconstructed and checked by the probe rather than performed silently.

## Behaviour authority

Pinned Microsoft XNA 4.0 IL first, FNA/MonoGame for comparison only, intuition last. The reference
contract is a hash-pinned artifact; the assemblies are pinned by SHA-256 in
`tools/api_compat/reference/XNA_IL_PROVENANCE.md`; the BCL authority is the authentic Microsoft .NET
Framework 4.0 `mscorlib` (SHA-256 `5634668d…`).

**Nothing measured from CNA enters the behaviour corpus**, which is `never CNA output` by
construction. Native measurements go to `docs/generated/*-native-report.json`. The corpus holds 526
observations with zero failures; its upstream source is absent, so additions and corrections are
made by documented deterministic replay or by surgical byte edit, and every one of them is recorded
with the pre-correction SHA-256.

## Dependency frontier

`tools/api_compat/analyze_dependencies.rb` classifies every dependency-complete missing type. Five
remain, and **none is consumable**:

| type | reported blocker | what is actually missing |
| --- | --- | --- |
| `Design.MathTypeConverter` | BCL_PROJECTION | scope, not authority: it **inherits** `ExpandableObjectConverter` and **returns** `PropertyDescriptorCollection`, so projecting it means projecting .NET's type-descriptor system |
| `Graphics.EffectAnnotation` | NATIVE_RUNTIME | not the renderer: its eight `GetValue*` members forward to a temporary `EffectParameter`, which is not projected, and nothing in the projected surface produces an annotation |
| `Graphics.GraphicsAdapter` | NATIVE_RUNTIME | not the ABI: the qualified artifact compiles only the HEADLESS renderer, and with it every adapter route answers invented data |

Each of the three has now been **measured** rather than accepted, and each is deferred for a reason
its reported blocker word does not name. Three earlier entries of this table were removed the same
way, by being built: `Graphics.SpriteFont` once `System.Char`, `Nullable`1` and `StringBuilder` were
decided, `Content.ResourceContentManager` once `System.Resources.ResourceManager` was collapsed to
the one member it reaches, and `Media.MediaSource` once its IL was read at all.

The `RUNTIME_DATA` register is **empty**. Every entry it ever held — `FrameworkDispatcher`,
`Audio.RendererDetail`, `Media.VisualizationData`, `Media.Video`, `Audio.AudioCategory`,
`Media.MediaSource` — turned out to describe a *producer* rather than the type, and the same has now
been true of eight `NATIVE_RUNTIME` deferrals. The rule that survived is the audit itself: a
deferral that names the thing which would *fill* a type says nothing about the type, and must be
re-measured before it is trusted.

Two deferrals are now measured rather than assumed, and both stand:

- **`GraphicsAdapter`.** The 0.21.0 artifact does contain `Sdl3Platform` and links SDL3 and X11 —
  the retired 0.7.0 one had only Headless and Terminal — but the only renderer compiled in is
  `HEADLESS`. With it every `cna_graphics_adapter_*` route answers `SUCCESS` with invented values:
  one adapter, `"Default Display"`, `\\.\DISPLAY1`, a single 800x480 mode, and
  `cna_graphics_adapters_refresh` answering `NOT_SUPPORTED`. Projecting the type would mean
  reporting invented hardware, so it is not projected.
- **`EffectAnnotation`.** Its six properties are one `ldfld` each and CNA can build one standalone —
  `cna_effect_annotation_create` takes no game, device or effect — so the *renderer* does not block
  it. What blocks it is that all eight `GetValue*` members construct a temporary `EffectParameter`
  and forward to it, so their behaviour — including what a type mismatch does — is
  `EffectParameter`'s, and that type is not projected. Nothing in the projected surface produces an
  annotation either: no `Effect`, no `EffectParameterCollection`, no `EffectAnnotationCollection`.
- **`MathTypeConverter`.** The authority is not missing: the authentic Microsoft .NET Framework 4.0
  `System.dll` (SHA-256 `c3182e40…`) is in the same Wine prefix as the pinned `mscorlib` and could be
  admitted the same way. What blocks it is **shape and scope**. Its `CanConvertFrom` and
  `CanConvertTo` each end in `call instance … TypeConverter::CanConvertFrom`, so part of its
  behaviour really is the base's; it returns a `PropertyDescriptorCollection` it would have to
  produce; and it compares against `InstanceDescriptor`, a fourth `ComponentModel` type. The
  structural collapse that unblocked `ResourceContentManager` cannot apply, because that rule is for
  a type whose *reachable surface is one member* — not for a base class one inherits from and a
  collection one returns. Projecting it means projecting .NET's type-descriptor system for ten
  design-time converters that nothing in this binding consumes.

## Qualification policy

Normal API strict mode is expected to remain red until the full selected XNA profile is implemented;
what must be green for a milestone claim is: the full test suite, the structural verifier in
leak-only mode, verifier self-tests, the RBS/runtime consistency check, the behaviour corpus, the
ABI probe with zero findings, the capability registry with zero contradictions, the gem audit and
the native canaries.

`HEADLESS` qualifies execution and native calls, not visible output. Specific hardware limits are
recorded rather than papered over:

- No connected controller was attached, so only disconnected GamePad results and route safety are
  qualified; connected state, positive capabilities and physical rumble are `HARDWARE_PENDING`.
- Audio playback is real — a real mixer opens at 44100 Hz stereo and state machines move — but
  **nothing claims audible output**.
- The machine has three real capture devices and `Microphone` is complete, but the suite never
  starts a capture: doing so would record audio from whoever runs it. That is a decision, and the
  whole managed contract is reachable without it.
- The XACT fixtures are the XNA Spacewar sample's, referenced by path through `CNA_TEST_XACT_DIR`
  and never copied into this repository; the XNB fixtures are MonoGame's, referenced the same way.

## Deferred boundaries

Completing a managed type implies nothing about the subsystem it names. The graphics runtime is the
large remaining area: no `Effect`, `EffectParameter`, `BasicEffect`, `Model`, `VertexBuffer`,
`IndexBuffer`, `VertexDeclaration`, `RenderTarget2D`, `TextureCube`, `Texture3D`, `BlendState`,
`DepthStencilState`, `RasterizerState`, `SamplerState`, `GraphicsAdapter` or `SpriteFont`, and none
of the nine deferred `GraphicsDevice` draw overloads. The Media *runtime* is deferred whole:
`MediaPlayer`, `MediaLibrary`, `MediaQueue`, `Song`, `Album`, `Artist`, `Genre`, `Playlist`,
`Picture`, `VideoPlayer` and their collections. `Content.ContentReader`, `ContentTypeReader` and
`ResourceContentManager` are absent, as is the whole `Design` converter family and the `Storage`
runtime. The nine XNA exception types this binding projects are never raised by it.
`AudioListener` and `AudioEmitter` remain managed descriptors whose settings are never heard.
Windows, macOS, browser/Wasm, Android, JRuby, TruffleRuby, MRuby and Opal are not supported targets.
