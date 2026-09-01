# `cna_sprite_batch_begin_with_effect`: a documented null the route refuses

Classified **UPSTREAM_CNA_DEFECT**. Reproduced at the C ABI with no Ruby in the path, documented,
and left in place: no CNA source was changed.

## What the header promises

    @param blend_state Blend state, or null for AlphaBlend.
    @param sampler_state Sampler state, or null for LinearClamp.
    @param depth_stencil_state Depth-stencil state, or null for None.
    @param rasterizer_state Rasterizer state, or null for CullCounterClockwise.

Those four are exactly what XNA's `SpriteBatch.SetRenderState` substitutes for a null field, which is
why the mapping looked like a one-to-one reproduction of the seven-argument `Begin`.

## What was measured

`build-probe/spritebegin.c`, inside a real `Draw` callback with `CNA_GRAPHICS_RENDERER=HEADLESS`:

    all four NULL           -> INVALID_ARGUMENT   "The BlendState descriptor is invalid."
    blend set, rest NULL    -> INVALID_ARGUMENT   "The SamplerState descriptor is invalid."
    all four supplied       -> SUCCESS
    begin_with_states       -> SUCCESS
    begin_with_states NULL  -> INVALID_ARGUMENT   "The BlendState descriptor is invalid."

Every descriptor is validated and a null pointer fails that validation, one parameter at a time in
declaration order. The documented "or null for …" contract is not honoured by either route.

## Why this does not become a deviation in the projection

`SpriteBatch.Begin` still behaves exactly as XNA's does, because the substitution the route refuses
to perform is one **XNA performs itself**:

    if (blendState != null) GraphicsDevice.BlendState = blendState;
    else                    GraphicsDevice.BlendState = BlendState.AlphaBlend;
    …DepthStencilState.None, RasterizerState.CullCounterClockwise, SamplerState.LinearClamp

So `Begin(sortMode, blendState)` resolves the four nulls to those very objects and passes the
resolved descriptors. That is reproducing `SetRenderState`, not compensating for CNA; what the defect
costs is only that the substitution happens on this side of the boundary instead of the other, and
nothing observable distinguishes the two. The values are the projected presets, which the
state-object milestone already cross-checked against CNA's own `cna_*_state_init`.

## Scope

Only the null-descriptor path of `cna_sprite_batch_begin_with_effect` and
`cna_sprite_batch_begin_with_states` is affected. Supplying all four descriptors succeeds on both,
`cna_sprite_batch_begin` is unaffected, and so is every other route this manifest binds.
