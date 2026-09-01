# The four graphics state objects

`Graphics.BlendState`, `Graphics.DepthStencilState`, `Graphics.RasterizerState` and
`Graphics.SamplerState` — 4 types, 65 Ruby member identities, all four complete.

## The audit that had to come first

All four arrived on the dependency frontier the moment `GraphicsResource` completed, and all four
reported `NATIVE_RUNTIME`. The standing rule of this project is that such a word is not a finding
until it is measured, and here it was wrong for the ninth time:

    BlendState          nativeReachable=true  nativeReachableMethods=["Apply"]
    DepthStencilState   nativeReachable=true  nativeReachableMethods=["Apply"]
    RasterizerState     nativeReachable=true  nativeReachableMethods=["Apply"]
    SamplerState        nativeReachable=true  nativeReachableMethods=["Apply"]

`Apply` is `assembly`-visible in the pinned IL. It is not in
`xna40-windows-runtime-contract.json`, no consumer of this binding could call it, and no identity
is lost by not projecting it. Every member the contract *does* select — a constructor, an inherited
`Dispose`, the properties and the static presets — is managed.

This is the shape the register has now recorded nine times: **the blocker named the thing that
would fill the type, not the type.** Here it named a member the public surface does not have.

## What the IL says

The four are the same type written four times:

    .ctor()                  { Object::.ctor(); SetDefaults(); isBound = false; }
    .ctor(…, string name)    { Object::.ctor(); SetDefaults(); …; Name = name; isBound = true; }
    get_X()                  { return cachedX; }                   // one ldfld, no more
    set_X(value)             { ThrowIfBound(); cachedX = value; }  // and no validation at all
    ThrowIfBound()           { if (isBound) throw new InvalidOperationException(
                                 Format(FrameworkResources.BoundStateObject, GetType().Name)); }

`SetDefaults`, read instruction by instruction:

| type | defaults |
| --- | --- |
| `BlendState` | colour and alpha source `One`, destination `Zero`, both functions `Add`; all four `ColorWriteChannels` `All`; `BlendFactor` `Color.White`; `MultiSampleMask` `-1` (`ldc.i4.m1`) |
| `DepthStencilState` | depth enable and write `true`, function `LessEqual`; stencil disabled, both functions `Always`, all six operations `Keep`, two-sided off; both masks `-1`; reference `0` |
| `RasterizerState` | cull `CullCounterClockwiseFace`, fill `Solid`, scissor off, MSAA **on**, both biases `0f` |
| `SamplerState` | filter `Linear`, all three addresses `Wrap`, anisotropy `4`, max mip `0`, bias `0f` |

Each preset is one private constructor, so a preset differs from a fresh state **only** where its
own constructor assigns — which the test asserts property by property rather than describing:

- `BlendState(source, destination, name)` assigns the pair to the colour *and* the alpha channels:
  `Opaque(One, Zero)`, `AlphaBlend(One, InverseSourceAlpha)`, `Additive(SourceAlpha, One)`,
  `NonPremultiplied(SourceAlpha, InverseSourceAlpha)`.
- `DepthStencilState(depthEnable, depthWriteEnable, name)`: `None(false,false)`,
  `Default(true,true)`, `DepthRead(true,false)`.
- `RasterizerState(cullMode, name)`: the three cull modes.
- `SamplerState(filter, address, name)` assigns the one address to **all three** coordinates, which
  is why the six presets are a filter × wrap/clamp grid and nothing finer.

So `new BlendState()` is value-identical to `BlendState.Opaque`, `new DepthStencilState()` to
`Default`, `new RasterizerState()` to `CullCounterClockwise` and `new SamplerState()` to
`LinearWrap`. That is XNA's own arithmetic, not a coincidence of this projection, and it is
asserted in both directions.

## The cross-check against CNA

CNA exports `cna_blend_state_init`, `cna_depth_stencil_state_init`, `cna_rasterizer_state_init` and
`cna_sampler_state_init`. Each takes a preset identity and a caller-owned POD — **no handle, no
device, no renderer** — which is why the whole cross-check runs headless without a `Game`.

Every projected preset is asserted equal to CNA's own, field by field. Two independent authorities
— the pinned XNA IL and the qualified CNA 0.21.0 artifact — agree on **63 of the 65 values**.

## UPSTREAM_CNA_DIVERGENCE: the two stencil masks

They disagree on exactly two:

    XNA SetDefaults:  cachedStencilMask = cachedStencilWriteMask = ldc.i4.m1   ->  -1
    CNA *_state_init: stencil_mask = stencil_write_mask = 2147483647           ->  Int32.MaxValue

`-1` is every bit of the D3D9 stencil mask DWORD; `0x7FFFFFFF` drops the top one. On any stencil
buffer XNA can create — 8 bits — the two mask the same bits, so nothing a program *renders* differs.
What differs is the value a consumer reads back from `StencilMask`, and that is an observable of the
managed type.

The pinned IL is this binding's authority, so the projection answers `-1`. The divergence is
asserted in both directions — CNA's value *and* the projection's — so it is reproduced rather than
reconciled, and if CNA changes, the test says so. No CNA source was changed.

## Recorded deviations

- **The setters refuse by type.** The IL validates nothing: `set_ColorSourceBlend` is
  `ThrowIfBound; stfld`, so XNA stores an undeclared enum value happily. This projection refuses it,
  because that is what its enum projection is. The refusal is this binding's, not XNA's.
- **`InvalidOperationException` → `RuntimeError`**, through the measured BCL register.
  `FrameworkResources.BoundStateObject` is a localized resource string this binding does not ship;
  what is reproduced is the exception type and that the message names the type's own name.
- **No instance is ever `freeze`d.** A frozen Ruby object would refuse the inherited mutable members
  too — `Tag`, and disposal — which XNA's bound state objects still accept. `Name` is likewise still
  settable on a preset, because `GraphicsResource::set_Name` carries no bound check.
- **`isBound` is only ever set by a preset.** XNA's other setter of that flag is `Apply`, which is
  not projected, so on this artifact the presets are the only bound instances that exist.

## What this does not add

No `GraphicsDevice` state property, no `SamplerStateCollection`, no `SpriteBatch.Begin` overload
that takes states. `cna_graphics_device_get/set_*_state` and `cna_sprite_batch_begin_with_states`
are deliberately unbound: applying a state to a device is `GraphicsDevice`'s surface and its own
milestone. Nothing here draws anything.
