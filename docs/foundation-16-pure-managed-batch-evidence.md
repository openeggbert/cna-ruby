# Foundation 16 — PURE MANAGED BATCH A

One batch milestone that closes **24** dependency-complete pure managed XNA enums and **109**
Ruby XNA member identities through the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType`
policy. No production runtime change was required: `lib/cna/runtime/enum.rb` is byte-identical to
Foundation 15.

The batch adds no CNA C ABI function, constant, layout, callback or Fiddle binding; no renderer,
GPU, device, audio, media or touch behaviour; and no member on any of the six deferred partial
native/runtime types.

## Scope rule actually applied

A candidate was consumed only when the regenerated public-signature dependency report placed it in
`pureManagedEnumCandidates` — a missing type whose every XNA public-signature dependency is already
complete, whose pinned metadata fully determines it, and whose projection needs no native boundary.

At the start of the batch that set held **26** enums. The hard batch ceiling is 25 newly completed
types, so at least one had to be deferred. The only non-arbitrary deferral unit is the
`Microsoft.Xna.Framework.Input.Touch` closure, which is why exactly 24 were consumed.

## Completed types

| # | Type | Flags | CLR | Ruby | Literals | Deferred reverse consumers |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `Microsoft.Xna.Framework.Audio.AudioChannels` | false | 3 | 2 | Mono=1, Stereo=2 | 4: DynamicSoundEffectInstance..ctor, SoundEffect..ctor, SoundEffect.GetSampleDuration, … |
| 2 | `Microsoft.Xna.Framework.Audio.AudioStopOptions` | false | 3 | 2 | AsAuthored=0, Immediate=1 | 2: AudioCategory.Stop, Cue.Stop |
| 3 | `Microsoft.Xna.Framework.Audio.MicrophoneState` | false | 3 | 2 | Started=0, Stopped=1 | 1: Microphone.State |
| 4 | `Microsoft.Xna.Framework.Audio.SoundState` | false | 4 | 3 | Playing=0, Paused=1, Stopped=2 | 1: SoundEffectInstance.State |
| 5 | `Microsoft.Xna.Framework.Graphics.Blend` | false | 14 | 13 | One=0, Zero=1, SourceColor=2, InverseSourceColor=3, SourceAlpha=4, InverseSourceAlpha=5, DestinationColor=6, InverseDestinationColor=7, DestinationAlpha=8, InverseDestinationAlpha=9, BlendFactor=10, InverseBlendFactor=11, SourceAlphaSaturation=12 | 4: BlendState.AlphaDestinationBlend, BlendState.AlphaSourceBlend, BlendState.ColorDestinationBlend, … |
| 6 | `Microsoft.Xna.Framework.Graphics.BlendFunction` | false | 6 | 5 | Add=0, Subtract=1, ReverseSubtract=2, Min=3, Max=4 | 2: BlendState.AlphaBlendFunction, BlendState.ColorBlendFunction |
| 7 | `Microsoft.Xna.Framework.Graphics.BufferUsage` | true | 3 | 2 | None=0, WriteOnly=1 | 6: DynamicIndexBuffer..ctor, DynamicVertexBuffer..ctor, IndexBuffer..ctor, … |
| 8 | `Microsoft.Xna.Framework.Graphics.ColorWriteChannels` | true | 7 | 6 | None=0, Red=1, Green=2, Blue=4, Alpha=8, All=15 | 4: BlendState.ColorWriteChannels, BlendState.ColorWriteChannels1, BlendState.ColorWriteChannels2, … |
| 9 | `Microsoft.Xna.Framework.Graphics.CompareFunction` | false | 9 | 8 | Always=0, Never=1, Less=2, LessEqual=3, Equal=4, GreaterEqual=5, Greater=6, NotEqual=7 | 4: AlphaTestEffect.AlphaFunction, DepthStencilState.CounterClockwiseStencilFunction, DepthStencilState.DepthBufferFunction, … |
| 10 | `Microsoft.Xna.Framework.Graphics.CubeMapFace` | false | 7 | 6 | PositiveX=0, NegativeX=1, PositiveY=2, NegativeY=3, PositiveZ=4, NegativeZ=5 | 5: GraphicsDevice.SetRenderTarget, RenderTargetBinding..ctor, RenderTargetBinding.CubeMapFace, … |
| 11 | `Microsoft.Xna.Framework.Graphics.CullMode` | false | 4 | 3 | None=0, CullClockwiseFace=1, CullCounterClockwiseFace=2 | 1: RasterizerState.CullMode |
| 12 | `Microsoft.Xna.Framework.Graphics.EffectParameterClass` | false | 6 | 5 | Scalar=0, Vector=1, Matrix=2, Object=3, Struct=4 | 2: EffectAnnotation.ParameterClass, EffectParameter.ParameterClass |
| 13 | `Microsoft.Xna.Framework.Graphics.EffectParameterType` | false | 11 | 10 | Void=0, Bool=1, Int32=2, Single=3, String=4, Texture=5, Texture1D=6, Texture2D=7, Texture3D=8, TextureCube=9 | 2: EffectAnnotation.ParameterType, EffectParameter.ParameterType |
| 14 | `Microsoft.Xna.Framework.Graphics.FillMode` | false | 3 | 2 | Solid=0, WireFrame=1 | 1: RasterizerState.FillMode |
| 15 | `Microsoft.Xna.Framework.Graphics.IndexElementSize` | false | 3 | 2 | SixteenBits=0, ThirtyTwoBits=1 | 3: DynamicIndexBuffer..ctor, IndexBuffer..ctor, IndexBuffer.IndexElementSize |
| 16 | `Microsoft.Xna.Framework.Graphics.PresentInterval` | false | 5 | 4 | Default=0, One=1, Two=2, Immediate=3 | 1: PresentationParameters.PresentationInterval |
| 17 | `Microsoft.Xna.Framework.Graphics.RenderTargetUsage` | false | 4 | 3 | DiscardContents=0, PreserveContents=1, PlatformContents=2 | 5: PresentationParameters.RenderTargetUsage, RenderTarget2D..ctor, RenderTarget2D.RenderTargetUsage, … |
| 18 | `Microsoft.Xna.Framework.Graphics.SetDataOptions` | true | 4 | 3 | None=0, Discard=1, NoOverwrite=2 | 2: DynamicIndexBuffer.SetData, DynamicVertexBuffer.SetData |
| 19 | `Microsoft.Xna.Framework.Graphics.StencilOperation` | false | 9 | 8 | Keep=0, Zero=1, Replace=2, Increment=3, Decrement=4, IncrementSaturation=5, DecrementSaturation=6, Invert=7 | 6: DepthStencilState.CounterClockwiseStencilDepthBufferFail, DepthStencilState.CounterClockwiseStencilFail, DepthStencilState.CounterClockwiseStencilPass, … |
| 20 | `Microsoft.Xna.Framework.Graphics.TextureAddressMode` | false | 4 | 3 | Wrap=0, Clamp=1, Mirror=2 | 3: SamplerState.AddressU, SamplerState.AddressV, SamplerState.AddressW |
| 21 | `Microsoft.Xna.Framework.Graphics.TextureFilter` | false | 10 | 9 | Linear=0, Point=1, Anisotropic=2, LinearMipPoint=3, PointMipLinear=4, MinLinearMagPointMipLinear=5, MinLinearMagPointMipPoint=6, MinPointMagLinearMipLinear=7, MinPointMagLinearMipPoint=8 | 1: SamplerState.Filter |
| 22 | `Microsoft.Xna.Framework.Media.MediaSourceType` | false | 3 | 2 | LocalDevice=0, WindowsMediaConnect=4 | 1: MediaSource.MediaSourceType |
| 23 | `Microsoft.Xna.Framework.Media.MediaState` | false | 4 | 3 | Paused=2, Playing=1, Stopped=0 | 2: MediaPlayer.State, VideoPlayer.State |
| 24 | `Microsoft.Xna.Framework.Media.VideoSoundtrackType` | false | 4 | 3 | Music=0, Dialog=1, MusicAndDialog=2 | 1: Video.VideoSoundtrackType |

Totals: 133 CLR identities, 109 expected Ruby identities, 109 target Ruby identities, 109 mapped.
The synthetic `value__` storage field is excluded once per enum by the established rule
(24 enums × 1 = 24 excluded identities; 133 − 24 = 109).

Every row above is `kind = enum`, `underlyingType = System.Int32`, `baseType = System.Enum` in the
pinned contract and projects to a Ruby class whose superclass is `CNA::Runtime::EnumValue`.

Local diagnostics are zero for all 24 types, and each appears in `completeTypeNames`.

## Behavioural classification

All 24 are `PINNED_METADATA_COMPLETE`: the pinned XNA 4.0 Windows metadata fully determines the
type, so no runtime probe, no IL replay and no surrogate execution was needed or used. Nothing in
this batch required deterministic managed behaviour beyond the enum projection itself.

The behaviour corpus separates the two provenance classes strictly:

- `pure_managed_enum.<type>.contract` — `PURE_XNA_DERIVED`. Read from the pinned metadata: kind,
  underlying type, flags bit, declared literal/value pairs in CLR declaration order, the CLR member
  count including `value__`, and the selected member count excluding it.
- `pure_managed_enum.<type>.ruby_mapping` — `RUBY_MAPPING_QUALIFICATION`. The Ruby projection
  policy applied to that metadata: typed frozen canonical values, canonical `coerce`, `TypeError`
  for non-Integer and cross-enum input, `RangeError` for undefined raw values, flags composition
  only for declared flags enums, and the absence of any helper API.

Both rows were **derived from the pinned metadata and the documented policy**, not snapshotted from
the implementation, and they matched the runtime on the first execution.

## Facts worth pinning

- **`Blend.One = 0` and `Blend.Zero = 1`.** The names do not mirror the raw values. A verifier
  fixture mutates every literal of every batch enum by +1 and requires `ENUM_VALUE_MISMATCH`, so this
  inversion cannot silently drift.
- **`MediaState` is declared out of numeric order**: `Paused = 2`, `Playing = 1`, `Stopped = 0`.
  Declaration order is preserved in the Ruby class, the RBS block and the corpus, because CLR
  declaration order is the pinned fact; ascending raw order is not.
- **`AudioChannels` has no zero literal** (`Mono = 1`, `Stereo = 2`), so `coerce(0)` raises
  `RangeError` like any other undefined raw value.
- **`MediaSourceType` is sparse**: `LocalDevice = 0` and `WindowsMediaConnect = 4`. Raw values
  1, 2 and 3 are undefined and rejected.
- **Three enums are `[Flags]` in the pinned metadata** and only those three: `BufferUsage`
  (mask `0x1`), `SetDataOptions` (mask `0x3`) and `ColorWriteChannels` (mask `0xF`). Their named
  zero (`None`) and, for `ColorWriteChannels`, the named full mask (`All = 15`) are declared in the
  metadata — they were read, not invented. The remaining 21 enums are `flags = false`: `|` and `&`
  raise `TypeError`, `@enum_mask` is 0, and no composite value can be produced.
- **`EffectParameterType` declares `Texture2D`, `Texture3D` and `TextureCube` literals.** These are
  enum literals scoped inside the enum class. No `Graphics::TextureCube` or `Graphics::Texture3D`
  type is added, and `Graphics::Texture2D` is unrelated to `EffectParameterType::Texture2D`.

## Deliberately not implemented

Completing these enums implies nothing about the subsystems that name them. All of the following
remain absent and unmeasured:

- `GraphicsDevice.SetRenderTarget`, `RenderTarget2D`, `RenderTargetCube`, `TextureCube`, cube face
  mapping and every `GraphicsDevice` draw overload.
- `BlendState`, `DepthStencilState`, `RasterizerState`, `SamplerState`, `SamplerStateCollection`,
  `TextureCollection`, `VertexBuffer`, `IndexBuffer`, `VertexDeclaration`, `Effect`, `BasicEffect`,
  `EffectParameter`, `GraphicsAdapter`, `PresentationParameters`, `DisplayMode`.
- The entire `Audio` runtime — `SoundEffect`, `SoundEffectInstance`, `DynamicSoundEffectInstance`,
  `Microphone`, `AudioEngine`, `WaveBank`, `SoundBank`, `Cue`, `AudioCategory`.
- The entire `Media` runtime — `MediaPlayer`, `MediaLibrary`, `MediaSource`, `Song`, `Video`,
  `VideoPlayer`, `Playlist`.
- The `Input.Touch` namespace in full, including the two deferred enums below.

Both new namespaces exist **only** as enum metadata contracts. `Microsoft::Xna::Framework::Audio`
and `Microsoft::Xna::Framework::Media` declare their selected enums and nothing else; a dedicated
test pins their exact constant sets so no runtime type can appear there unnoticed.

## Examined and not consumed

| Candidate | Rank | Reason | Boundary category |
| --- | --- | --- | --- |
| `Microsoft.Xna.Framework.Input.Touch.TouchLocationState` | 25 of 26 (4 identities) | Batch ceiling is 25 newly completed types and 26 pure managed enum candidates existed; the `Input.Touch` closure is the only non-arbitrary deferral unit. Splitting it to fill the cap would leave a half-open namespace. | BLOCKED_FOR_THIS_BATCH — batch upper bound / namespace closure integrity |
| `Microsoft.Xna.Framework.Input.Touch.GestureType` | 26 of 26 (11 identities) | Same closure. It is also the only remaining flags enum, and its sibling `TouchPanelCapabilities` struct is dependency-complete too, so a dedicated Touch milestone can close all three at once. | BLOCKED_FOR_THIS_BATCH — batch upper bound / namespace closure integrity |

Both are genuinely safe by every one of the 14 criteria and remain the top-ranked candidates.

The remaining 42 dependency-complete missing types are not pure managed enum leaves. The ones that
rank highest all cross an explicit stop boundary — `TextureCollection` and `DisplayMode` require
renderer/adapter behaviour, `ContentManager` and `TitleContainer` require filesystem and XNB
services, `GameWindow` requires platform windowing, `SpriteFont` requires content pipeline output,
`AudioListener`/`AudioEmitter` require the audio engine, and the `Content.ContentSerializer*`
attributes require a BCL attribute projection framework that does not exist yet.

## Structural movement

| Counter | Before (Foundation 15) | After (Foundation 16) | Delta |
| --- | --- | --- | --- |
| REFERENCE_TYPES | 257 | 257 | 0 |
| REFERENCE_MEMBERS | 2964 | 2964 | 0 |
| EXPECTED_RUBY_TYPES | 257 | 257 | 0 |
| EXPECTED_RUBY_MEMBERS | 2915 | 2915 | 0 |
| TARGET_TYPES | 80 | 104 | +24 |
| TARGET_MEMBERS | 1476 | 1585 | +109 |
| TOTAL_DIAGNOSTICS | 361 | 337 | −24 |
| MISSING_TYPE | 177 | 153 | −24 |
| MISSING_MEMBER | 132 | 132 | 0 |
| COMPLETE_TYPES | 74 | 98 | +24 |
| PARTIAL_TYPES | 6 | 6 | 0 |
| MISSING_TYPES | 177 | 153 | −24 |
| PROPERTY_MAPPING_MISMATCH | 1 | 1 | 0 |
| OVERLOAD_MAPPING_MISMATCH | 51 | 51 | 0 |
| ALLOWLIST_ENTRIES | 0 | 0 | 0 |
| UNMEASURED_STRUCTURAL_CATEGORY | 0 | 0 | 0 |

Every other structural category was zero before and is zero after: `UNEXPECTED_TYPE`,
`UNEXPECTED_MEMBER`, `TYPE_KIND_MISMATCH`, `BASE_MAPPING_MISMATCH`, `INTERFACE_MAPPING_MISMATCH`,
`FIELD_MAPPING_MISMATCH`, `METHOD_SIGNATURE_MAPPING_MISMATCH`, `PARAMETER_MAPPING_MISMATCH`,
`RETURN_MAPPING_MISMATCH`, `GENERIC_MAPPING_MISMATCH`, `ENUM_VALUE_MISMATCH`,
`FLAGS_MAPPING_MISMATCH`, `EVENT_MAPPING_MISMATCH`, `OPERATOR_MAPPING_MISMATCH`,
`LANGUAGE_MAPPING_MISMATCH`, `INTERNAL_TYPE_LEAK`, `RAW_HANDLE_LEAK`, `PUBLIC_NATIVE_FFI_LEAK`.

## Tooling change

`tools/api_compat/analyze_dependencies.rb` previously selected only a dependency-complete managed
enum that a *selected partial remainder* still referenced. After `CubeMapFace` was completed that
route was exhausted and the tool aborted, because no remaining pure managed enum is named by a
deferred member of the six partial types.

The report is now schema version 2. The preferred route is unchanged and still wins when it
applies; when it is empty the tool falls back to the ranked global pure managed enum list and
records `selectionRoute`. It also emits `dependencyCompleteCandidates` for the full space and
`pureManagedEnumCandidates` for the safe subset. This keeps leaf progress possible without
requiring a partial-member expansion on a deferred native/runtime type.

## Behaviour corpus provenance limitation

The upstream behaviour-corpus source with SHA-256
`398d0201af0e3c719c152f8659a871cb59710a7dfafc079df6694d453c737855` is **absent** from this
reconstructed host, exactly as the previous milestone recorded. It was not fabricated and its
provenance was not rewritten.

`tools/import_behavior_corpus.rb` was extended with the Foundation 16 merge path so that a future
run against the real source reproduces the same observation set, but it was **not executed**.
The 48 new observations were merged by the documented deterministic replay method, which refuses to
write unless re-serialising the pre-merge corpus reproduces its bytes exactly. That proof passed
against pre-merge SHA-256
`2571dee5b6219f6532efc3a44fa46552b29628c4b2386e6aeace69bbb778176d`, and the merge is purely
additive: 277 → 325 observations, no existing observation altered.

## Verification

- Full Ruby suite: 473 runs / 14549 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 325 observations / 325 assertions / 0 failures.
- API verifier self-tests and mutations: 106 runs, including 9 batch fixtures that apply every
  mutation to all 24 types — missing type, relocated namespace, wrong kind, wrong underlying type,
  flipped flags bit, every individual raw value +1, dropped literal, renamed literal, invented
  literal, exposed `value__`, injected `Parse` helper, flipped runtime `@enum_flags`, and a widened
  runtime flags mask.
- RBS 3.4 validation passes; runtime/RBS consistency 18 runs / 2934 assertions.
- Strict leak-only mode passes.
- ABI: 38 / 122 / 290 / 290 / 2 / 59, zero missing header symbols, zero missing library symbols,
  zero mismatches — identical to Foundation 15.
- Native integration 14 runs / 528 assertions and the native stress canary both pass with zero
  crashes, zero observed UAF and zero observed double-free. Sanitizers remain `NOT_RUN`.
