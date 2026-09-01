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

The strict surface is **177 types / 2152 Ruby member identities**: 174 complete, 3 partial, 80 of the
257 reference types still missing, with 179 deferred diagnostics of which 67 are missing members and
28 are the overload category. Every structural category except `MISSING_TYPE`, `MISSING_MEMBER`,
`OVERLOAD_MAPPING_MISMATCH` and one long-standing `PROPERTY_MAPPING_MISMATCH`
(`GraphicsDevice::Viewport`) is zero, the allowlist is empty and `UNMEASURED_STRUCTURAL_CATEGORY` is
zero. **27** event identities are projected across **14** owner types with `EVENT_MAPPING_MISMATCH`
zero, and **22** BCL identities go through the measured `CNA::Runtime::BclProjection` register.

The three partial types are the graphics runtime: `GraphicsDeviceManager` (15 members outstanding),
`GraphicsDevice` (37) and `SpriteBatch` (1) — 53 of the 67
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
- **Media** — `VisualizationData`, `Video`, `MediaSource` and `VideoPlayer` over CNA's own player,
  whose optional video decoder is measured present. Nothing produces a `Video`, so `Play` has no
  legal argument; every other member is real.
- **Graphics** — `Texture2D` end to end (decode, construct, pixel round-trip, PNG and JPEG encode),
  `GraphicsResource` and its disposal contract, the four state objects `BlendState`,
  `DepthStencilState`, `RasterizerState` and `SamplerState` with every preset cross-checked against
  CNA's own, `SamplerStateCollection` over real sampler slots on both shader stages,
  `VertexDeclaration` with `VertexElementValidator` reproduced in the IL's order and every stride
  cross-checked against CNA's, `IVertexType` with the four vertex structs that really conform to
  it,
  `SpriteFont` over a real MonoGame font, `Viewport`, `TextureCollection`, `Texture`,
  `DisplayMode`, `DisplayModeCollection`, `PresentationParameters` and the enum closure, beside the
  three partial runtime types.

## Admission and safety

- The admitted encoded ABI versions are `0x00000700` and `0x00001500`, cross-verified across both
  header roots; `CROSS_VERSION_MISMATCHES` is zero over the whole bound surface.
- `CNA_NATIVE_LIBRARY` must be an absolute file path when used.
- All Fiddle functions come from one manifest: **229** functions, **5** callbacks, **84** constants
  and **29** struct layouts, each type-checked against the headers by a compiler-backed probe with
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

`tools/api_compat/analyze_dependencies.rb` classifies every dependency-complete missing type.
**Three remain**, none is consumable, and — for the first time — **every one of them has been
audited**. The count went 3 → 9 → 6 → 5 → 8 → 4 → 3 in six milestones:
completing `GraphicsResource` and `Texture2D` made six types behind them visible at once, auditing
four of those six found the blocker was not one, `SamplerStateCollection` turned out to have an
accurate `NATIVE_RUNTIME` that named a route CNA exports, `VertexDeclaration` plus the `IVertexType`
it uncovered put the four vertex structs on the queue with no blocker at all — and then those four
were **built**, which is the first work queue this frontier has ever produced and consumed, and
finally `Media.VideoPlayer`'s blocker was audited and turned out to be the eleventh that was not
one.

| type | reported blocker | status |
| --- | --- | --- |
| `Design.MathTypeConverter` | BCL_PROJECTION | **audited, deferred.** Scope, not authority: it inherits `ExpandableObjectConverter` and returns `PropertyDescriptorCollection`, so projecting it means projecting .NET's type-descriptor system |
| `Graphics.EffectAnnotation` | NATIVE_RUNTIME | **audited, deferred.** Not the renderer: its eight `GetValue*` members forward to a temporary `EffectParameter`, which is not projected, and nothing in the projected surface produces an annotation |
| `Graphics.GraphicsAdapter` | NATIVE_RUNTIME | **audited twice, deferred.** Not the ABI, and — measured in Native frontier 6 — **not the renderer either**: a second qualified artifact with a real X11 window still answers the same invented data, because the adapter list is cached before the video subsystem exists. `UPSTREAM_CNA_BLOCKED` |

The three blocked entries have been **measured** rather than accepted, and each is deferred for a
reason its reported blocker word does not name. Four entries left this table in one milestone by
being audited and built — `BlendState`, `DepthStencilState`, `RasterizerState` and `SamplerState`,
whose `NATIVE_RUNTIME` was the `assembly`-visible `Apply` the contract never selects, the ninth
deferral this project has retired that way — and `VertexDeclaration` was the tenth, the only
candidate that ever carried **two** blockers, both naming members outside its public surface.
`SamplerStateCollection` left it for the opposite reason: its blocker was accurate, and being
accurate is what made it buildable. Three left it before them: `Graphics.SpriteFont` once
`System.Char`, `Nullable`1` and `StringBuilder` were decided, `Content.ResourceContentManager` once
`System.Resources.ResourceManager` was collapsed to the one member it reaches, and
`Media.MediaSource` once its IL was read at all.

The generated frontier report is produced by a tool the suite does not run, and it **had gone
stale**: for one whole milestone it still described `SamplerState` as waiting on `GraphicsResource`
after `GraphicsResource` completed, and nothing failed, because every assertion was pinned to the
stale file. `test/test_dependency_frontier.rb` now carries a staleness guard — the report's
type-level header must agree with the strict scoreboard, and no candidate may name a complete type
as an unmet dependency — and `test/test_behavior_corpus_integrity.rb` measures the corresponding
gap in the corpus: the per-milestone value files are authoring records, only the aggregate is
replayed, and the seven rows where they disagree are named supersessions rather than drift.

The `RUNTIME_DATA` register is **empty**. Every entry it ever held — `FrameworkDispatcher`,
`Audio.RendererDetail`, `Media.VisualizationData`, `Media.Video`, `Audio.AudioCategory`,
`Media.MediaSource` — turned out to describe a *producer* rather than the type, and the same has now
been true of eight `NATIVE_RUNTIME` deferrals. The rule that survived is the audit itself: a
deferral that names the thing which would *fill* a type says nothing about the type, and must be
re-measured before it is trusted.

Two deferrals are now measured rather than assumed, and both stand:

- **`GraphicsAdapter`.** Every `cna_graphics_adapter_*` route answers `SUCCESS` with invented
  values: one adapter, `"Default Display"`, `\\.\DISPLAY1`, a single 800x480 mode, and
  `cna_graphics_adapters_refresh` answering `NOT_SUPPORTED`. Projecting the type would mean
  reporting invented hardware, so it is not projected. **The recorded reason for that was wrong, and
  Native frontier 6 measured it.** It said the cause was the renderer selection — "the only renderer
  compiled in is `HEADLESS`" — and a second qualified artifact with `CNA_GRAPHICS_RENDERER=OPENGL33`,
  a real X11 window, a real GL 4.5 context and a live 1280x800 display answers *exactly the same
  invented values*. The cause is ordering: `GraphicsAdapter::getAdaptersProperty()` fills a static
  cache, `GraphicsDevice`'s default constructor evaluates `getDefaultAdapterProperty()` as a
  delegated-constructor argument — before `createOrAttachWindow()` acquires the video subsystem — and
  `cna_graphics_adapters_refresh` refuses by design, so no consumer can correct it. In one frame with
  one device, `cna_game_window_copy_screen_device_name` answers the display's real name while
  `cna_graphics_adapter_copy_description` answers the no-display fallback. See
  `docs/graphics-adapter-ordering-upstream-defect.md`; the blocker is `UPSTREAM_CNA_BLOCKED`, not the
  renderer.
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

**Two artifacts are qualified**, the same CNA source and the same C ABI differing in one CMake
variable: `CNA_GRAPHICS_RENDERER=HEADLESS` and `=OPENGL33`. Both pass the whole suite, both pass the
native ABI gate with `ABI_MISMATCHES=0`, and both are run to 60 and 600 frames by
`tools/run_renderer_qualification.rb`. `HEADLESS` qualifies execution and native calls and creates
no window at all — its descriptor sets `needsWindow = false`, as `SOFTWARE`, `STUB` and `PORTABLEGL`
do, so "a renderer that is not HEADLESS" is not the same question as "a renderer that has a window".
`OPENGL33` creates a real X11 window and a real GL 4.5 context, and reads a cleared render target
back exactly; it runs against `Xvfb`, so **rasterisation is verified and visibility on a physical
monitor is not**. A test whose expectation depends on which artifact is loaded measures the
difference through `test/renderer_environment.rb` rather than pinning either answer.

Specific hardware limits are recorded rather than papered over:

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

Completing a managed type implies nothing about the subsystem it names. **This section had gone
stale** — it listed `VertexDeclaration`, the four graphics state objects, `SpriteFont`,
`ResourceContentManager` and `VideoPlayer` as absent for milestones after each was complete, which is
the same defect the dependency frontier and the behaviour corpus's authoring files each had once:
prose stating measured facts with nothing comparing it to the measurement. The list below is now
delimited and checked against `docs/generated/missing-type-inventory.md` by
`test/test_plan_boundaries.rb`, so every name in it is a type the strict report really calls missing.

<!-- absent-types:begin -->
`BasicEffect`, `SkinnedEffect`, `AlphaTestEffect`, `DualTextureEffect`, `EnvironmentMapEffect`,
`GraphicsAdapter`, `GraphicsDeviceInformation`, `PreparingDeviceSettingsEventArgs`,
`DrawableGameComponent`, `Model`, `ModelBone`, `ModelMesh`, `ModelMeshPart`,
`ModelBoneCollection`, `ModelMeshCollection`, `ModelMeshPartCollection`,
`ModelEffectCollection`, `MediaPlayer`, `MediaLibrary`, `MediaQueue`, `Song`, `SongCollection`,
`Album`, `AlbumCollection`, `Artist`, `ArtistCollection`, `Genre`, `GenreCollection`,
`Playlist`, `PlaylistCollection`, `Picture`, `PictureAlbum`, `PictureAlbumCollection`,
`PictureCollection`, `ContentReader`, `ContentTypeReader`, `ContentTypeReaderManager`,
`StorageDevice`, `StorageContainer`, `MathTypeConverter`, `ColorConverter`, `MatrixConverter`,
`PlaneConverter`, `PointConverter`, `QuaternionConverter`, `RayConverter`, `RectangleConverter`,
`Vector2Converter`, `Vector3Converter`, `Vector4Converter`, `BoundingBoxConverter`,
`BoundingSphereConverter`
<!-- absent-types:end -->

The graphics runtime is the large remaining area. `GraphicsDevice` still owes thirty members and
`GraphicsDeviceManager` fifteen, and they are the only two partial types left. `SetRenderTarget`
is one of the thirty, which is why this binding can create a render target and not bind one: `SpriteBatch`
completed when the `Effect` cluster gave `Begin` its last two overloads.

Types a reader might expect on that list and will not find, because they are **complete**: the
whole nine-type `Effect` graph -- `Effect`, `EffectParameter`, `EffectAnnotation`, `EffectPass`,
`EffectTechnique` and their four collections --
`VertexDeclaration` and the four vertex structs, the four buffer types and the
`VertexBufferBinding` that names one, `DirectionalLight`, `EffectMaterial` and the `IEffectLights`
contract they unblocked, `RenderTarget2D`, `RenderTargetCube`, `RenderTargetBinding`, `OcclusionQuery`,
the four graphics state objects,
`SamplerStateCollection`, `TextureCollection`, `SpriteFont`, `Texture2D`, `Texture3D`,
`TextureCube`, `GraphicsResource`, `ResourceContentManager`, and the whole `Audio` namespace including the XACT cluster. In `Media`,
`Video`, `VideoPlayer`, `MediaSource` and `VisualizationData` are complete while the media *library*
and *player* runtime above is not.

The nine XNA exception types this binding projects are never raised by it. `AudioListener` and
`AudioEmitter` are complete managed descriptors whose settings are never heard. Windows, macOS,
browser/Wasm, Android, JRuby, TruffleRuby, MRuby and Opal are not supported targets.
