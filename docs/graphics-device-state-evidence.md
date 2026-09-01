# Foundation 85 — `GraphicsDevice`'s state slice, and two aggregates measured by value

Seven of the thirty-seven members `GraphicsDevice` still owed: the three state objects it holds, the
three scalars two of them carry, and the scissor rectangle. `MISSING_MEMBER` goes **65 → 58** and
`TOTAL_DIAGNOSTICS` 150 → **143**. The device is still partial, and this is the first slice of it.

## The three states are cached objects, not descriptors read back

`get_BlendState` is one `ldfld`, so XNA answers the **object that was assigned** and reference
identity is observable. A state read back from CNA would be a different object with the same values,
so each getter here answers what the setter stored.

`InitializeDeviceState` nulls the three fields and then assigns `BlendState.Opaque`,
`DepthStencilState.Default` and `RasterizerState.CullCounterClockwise` *through the setters*, so a
fresh device answers those three presets by identity. It runs during device creation; the earliest
reachable moment here is the first touch inside a lifecycle callback, because nothing can reach the
device outside one — and no observer can tell the two apart, since the first read or write is what
would notice.

## The dirty flags, which are what make a redundant assignment matter

```
set_BlendState(value)         null                                  -> ArgumentNullException("value")
                              same object && !blendStateDirty       -> return untouched
                              apply; cache; **device.BlendFactor = value.BlendFactor**;
                              **device.MultiSampleMask = value.MultiSampleMask**; dirty = false
set_BlendFactor(value)        apply; cache; **blendStateDirty = true**
set_MultiSampleMask(value)    apply; cache; **blendStateDirty = true**
set_DepthStencilState(value)  the same shape, carrying ReferenceStencil across
set_ReferenceStencil(value)   apply; cache; **depthStencilStateDirty = true**
set_RasterizerState(value)    null -> throw; same object -> return; apply; cache -- and **no flag**
```

So a state assignment takes the state's own scalars with it, and writing either scalar afterwards
makes the state *stale* — which is exactly why assigning the same object again re-applies it and
restores the state's values. The test measures the whole cycle: `AlphaBlend`, then a blend factor and
mask of its own, then `AlphaBlend` again, and the factor is back to opaque white.

The rasterizer state is the odd one out and has no flag, because no scalar property shadows part of
it. That is measured rather than asserted: a mutated state object re-assigned is an early return, and
reading `cna_graphics_device_get_rasterizer_state` shows the device never took the new value.

CNA's `CNA_BlendState` descriptor carries `blend_factor` and `multi_sample_mask`, and its
`CNA_DepthStencilState` carries the reference stencil, so one `set_*_state` call moves exactly what
XNA's setter moves.

## Two aggregates passed by value, and both classifications measured

`cna_graphics_device_set_blend_factor` takes `CNA_Color` **by value** and
`cna_graphics_device_set_scissor_rectangle` takes `CNA_Rectangle` by value. Fiddle cannot pass an
aggregate, so each expands into the eightbytes the System V x86-64 classification really puts in
registers, and the expansion is recorded on the signature and reconstructed by the ABI gate against
the header:

| Aggregate | Size | Classification | Expansion | Measured |
| --- | --- | --- | --- | --- |
| `CNA_Color` | 4 bytes, 4×`uint8_t` | one INTEGER eightbyte | one `uint32_t` — the packed RGBA | written and read back identical on HEADLESS and OPENGL33 |
| `CNA_Rectangle` | 16 bytes, 4×`int32_t` | two INTEGER eightbytes | `x \| y << 32` and `width \| height << 32` | all four fields round-trip on both |

Neither was assumed. The `CNA_Matrix` rule still stands and is untouched: 64 bytes is MEMORY class,
which no expansion can reach, and it is why the stock effects are still missing.

## The scissor rule, and the branch that cannot be reached

`set_ScissorRectangle` validates against the **current render target's** bounds, or the back
buffer's when none is bound, and throws `ArgumentException(ScissorInvalid, "value")` otherwise.
Only the back-buffer branch is reachable here, and that is not a partial implementation: binding a
render target is `GraphicsDevice.SetRenderTarget`, which this binding does not project, so no other
bounds exist. `cna_graphics_device_get_backbuffer_info` supplies them.

`get_ScissorRectangle` asks the device rather than a cache, as the IL does.

## Native surface

Fifteen routes bring the manifest to **375** and one layout to **61** — `CNA_BackBufferInfo`, whose
fields are identical in both admitted header roots. `ABI_MISMATCHES=0`.

The three descriptor mappings now have **three** callers each: the state object that writes one, the
sampler collection that applies one, and the device property that assigns one. That is one mapping
rather than three, which is what `test_graphics_state_objects.rb` and
`test_sampler_state_collection.rb` now record from their side.

## Mutation

Eight planted defects, eight caught: a state not carrying its scalars (either one), a scalar write
not marking its state dirty, a rasterizer dirty flag that should not exist, the device skipping its
three initial states, a dropped null guard, a dropped scissor bounds check, and the scissor's two
eightbytes swapped.

## What this milestone does not do

`GraphicsDevice` still owes thirty members: the five draw families, `SetRenderTarget` and its
siblings, `SetVertexBuffer`/`Indices`, `Present`/`Reset`/`Dispose`/`GetBackBufferData`, the four
identity properties — `Adapter` among them, which stays `UPSTREAM_CNA_BLOCKED` — and its six events.
Nothing here draws, binds or presents.
