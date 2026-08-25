# Foundation 24 — the managed descriptors

Completes `Audio.AudioListener`, `Audio.AudioEmitter`, `Graphics.PresentationParameters` and
`GameComponentCollectionEventArgs` from pinned XNA 4.0 Windows IL. 26 Ruby identities, local
diagnostics zero on all four. Every one is publicly constructible, pure managed and native-free.

## AudioListener and AudioEmitter

Both keep their state inside a native-**layout** XACT struct, but neither calls into native code:
the IL inventory reports `nativeReachable: false` and `declaresNativeEntryPoint: false` for both.
The struct is a storage shape that XACT would read; no audio engine exists here, so nothing a
consumer sets is ever heard.

Every `Vector3` property passes through `UnsafeNativeStructures::FlipHandedness`, which the IL shows
is exactly `(X, Y, -Z)`, on **both** the getter and the setter. That cancellation is reproduced
literally rather than optimised away, because it is not quite symmetric:

| Property | Constructor stores | First read answers |
| --- | --- | --- |
| `Position` | `Vector3.Zero` **unflipped** | `(0, 0, -0.0)` — a negative-zero Z |
| `Velocity` | `Vector3.Zero` **unflipped** | `(0, 0, -0.0)` — a negative-zero Z |
| `Forward` | `Flip(Vector3.Forward)` | `Vector3.Forward` exactly, `Z` bits `bf800000` |
| `Up` | `Flip(Vector3.Up)` | `Vector3.Up` exactly, `Z` bits `00000000` |

The negative zero is invisible to `==` and to `ToString`, and visible through `f32_bits`; the
corpus pins the bit pattern of every default. A round trip through any setter is exact, because
`Z` is negated twice.

`AudioEmitter` adds `DopplerScale`, which the constructor sets to `1`, alongside the internal
`ChannelCount`, `ChannelRadius` and `CurveDistanceScaler` that XNA does not expose and this
projection therefore does not add. Its setter guard is

```
ldarg.1; ldc.r4 0.0; bge.un.s <past the throw>
```

`bge.un` branches when the value is greater than or equal to zero **or unordered**, so:

- `0.0`, `-0.0`, any positive value and `+Infinity` are accepted;
- **`NaN` is accepted**, because it is unordered;
- only an ordered negative value — including `-Infinity` — raises, which the projection maps to
  Ruby's `RangeError`, this repository's mapping for a value outside its allowed range.

Guessing "reject anything not >= 0" would have rejected NaN and been wrong. This is the ordered
versus unordered floating comparison the IL had to settle.

## PresentationParameters

The XNA type keeps every value in a nested internal `Settings` struct, and **every public setter is
a single field store with no validation whatsoever**; the only checks in the projection are this
repository's ordinary CLR-type boundary checks.

The constructor is `base()` followed by exactly one store — `set_IsFullScreen(true)`. Every other
field keeps its CLR default of zero:

| Property | Default |
| --- | --- |
| `BackBufferWidth`, `BackBufferHeight`, `MultiSampleCount` | `0` |
| `BackBufferFormat` | `SurfaceFormat.Color` |
| `DepthStencilFormat` | `DepthFormat.None` |
| `DisplayOrientation` | `DisplayOrientation.Default` |
| `PresentationInterval` | `PresentInterval.Default` |
| `RenderTargetUsage` | `RenderTargetUsage.DiscardContents` |
| `DeviceWindowHandle` | `IntPtr.Zero` |
| **`IsFullScreen`** | **`true`** |

`IsFullScreen` defaulting to `true` is the IL's answer, not a convention — several XNA
reimplementations default it to false. `IsFullScreen` is stored as an `int32` the setter normalises
to 0 or 1 and the getter reads back as `field != 0`, so the observable value is always exactly
`true` or `false`.

`Bounds` is get-only and derived: `new Rectangle(0, 0, BackBufferWidth, BackBufferHeight)`, a fresh
rectangle on every read, negative back-buffer values included because nothing rejects them.
`Clone` constructs a new instance and copies the whole settings struct, so the clone's own
constructor default for `IsFullScreen` is overwritten along with everything else.

`DeviceWindowHandle` is a `System.IntPtr`, which keeps the mapping already pinned in
`mapping-rules.json`: a signed native-pointer-width Ruby `Integer`, range-validated from
`Fiddle::SIZEOF_VOIDP`, never a `Fiddle::Pointer`. **No new IntPtr policy was invented.** The scalar
is externally owned and nothing dereferences, frees or closes it.

This is a managed descriptor and nothing else. It creates no `GraphicsDevice`, looks up no native
window, enumerates no adapter, builds no swap chain and presents nothing; `GraphicsAdapter`,
`DisplayMode`, `DisplayModeCollection`, `RenderTarget2D`, `RenderTargetCube` and
`DepthStencilState` all remain absent, and `GraphicsDevice` still exposes exactly `IsDisposed`,
`Viewport` and `Clear`.

## GameComponentCollectionEventArgs

`base()` then one field store, and one get-only property. XNA validates nothing, so `nil` is
accepted; a value that is neither `nil` nor an `IGameComponent` is rejected with `TypeError`, which
is this binding's boundary check for a CLR-typed parameter. It is the first projected subclass of
`CNA::Runtime::EventArgs`, which the Foundation 21 register already mapped.

Nothing raises it: `GameComponentCollection` is still absent, and `GameComponent`,
`DrawableGameComponent` and `GameComponentCollection` all remain missing.

## Corpus corrections

`depth_format.ruby_enum_mapping` asserted that five Graphics types were absent, one of which was
`PresentationParameters`. That type arrived from its own IL rather than from anything `DepthFormat`
implies, so the slot was dropped and the row now asserts only the device and render-target surface
`DepthFormat` still does not imply. The replay proved every other element of that row, and every
other row, unchanged.

## Structural movement

TARGET_TYPES 121 → 125, TARGET_MEMBERS 1660 → 1686, TOTAL_DIAGNOSTICS 320 → 316, MISSING_TYPE
136 → 132, COMPLETE_TYPES 115 → 119. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6, every structural
mismatch category unchanged, allowlist 0, unmeasured 0.

Frontier: 29 dependency-complete candidates, 1 consumable (`Graphics.DisplayMode`).
`Audio.Cue` became dependency-complete when `AudioEmitter` and `AudioListener` closed its
dependencies, and is blocked on `NATIVE_RUNTIME` plus `BCL_PROJECTION`.

CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59.

## Verification

- Full Ruby suite: 613 runs / 20480 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 402 observations / 402 assertions / 0 failures; 11 additive rows in the new
  `MANAGED_DESCRIPTOR` group.
- API verifier strict: 316 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
