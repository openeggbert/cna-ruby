# Foundation 83 — `RenderTarget2D`, `RenderTargetCube` and the binding that names one

Three types, twenty-two identities, and the off-screen surfaces this project has been *measuring*
since Native frontier 6 without being able to project. The strict scoreboard goes **194 complete /
61 missing to 197 / 58**, `TARGET_MEMBERS` 2325 to 2347 and `TOTAL_DIAGNOSTICS` 154 to **151**.
Event identities go 29 to 31 across 18 owner types.

| Type | Identities | Shape |
| --- | --- | --- |
| `RenderTarget2D` | 9 | `Texture2D` subclass, three ctors, four properties, an event |
| `RenderTargetCube` | 8 | `TextureCube` subclass, two ctors, the same four and the event |
| `RenderTargetBinding` | 5 | sealed struct, two ctors, `op_Implicit`, two getters |

## A render target is a texture on both sides of the boundary

XNA derives `RenderTarget2D` from `Texture2D` and `RenderTargetCube` from `TextureCube`. CNA agrees
without saying so: `cna_texture2d_get_data` accepts a render-target handle, which is exactly what
`tools/run_renderer_qualification.rb` has been doing since Native frontier 6 — bind, clear to
0.25/0.5/0.75, unbind, read `64/128/191` back. So each type here is its texture base with a different
creator and a different destroyer, and the whole inherited surface keeps working.

## The constructor negotiates, so the properties report what was *got*

`CreateRenderTarget` passes the caller's **preferred** format, depth format and sample count through
`GraphicsAdapter.QueryFormat`, which answers what the adapter can actually give, and the
`RenderTargetHelper` it then builds stores those answers — which is what `DepthStencilFormat`,
`MultiSampleCount` and `RenderTargetUsage` read. CNA negotiates in the same place, inside its create
route, and reports the result through `cna_render_target_get_info`.

This projection therefore reads all four values back from the info rather than storing what was
asked for. It is the same structure XNA has, and it is why **the missing `GraphicsAdapter` did not
block these types**: the adapter's job here is to answer a question CNA already answers.

Both were `ilOnlyBlockedCandidates` with two unresolved halves — native-blocked *and* reaching a
missing type — and both were built with neither half resolved. That is a new resolution shape for
this frontier's register, and `test_member_level_dependencies.rb` now records it: a dependency that
exists only to answer a question something else already answers is not a dependency this binding
has.

## An upload that reports success and is dropped

UPSTREAM_CNA_DEFECT, reproduced at the C ABI with no Ruby in the path: `cna_texture2d_set_data` over
a render-target handle returns `CNA_RESULT_SUCCESS` and writes nothing, while the same call over a
plain `Texture2D` handle round-trips exactly. Readback is unaffected. Full measurement and the
suggested upstream fix are in `docs/render-target-upload-upstream-defect.md`; the test pins both
halves so the record stays honest if CNA changes.

The projection passes the call through rather than refusing it: XNA declares `SetData` on the base
and `RenderTarget2D` does not override it, so a refusal here would be an invented rule.

## `IsContentLost` latches, and `ContentLost` never fires

`get_IsContentLost` returns `_contentLost` once it is true and otherwise re-reads the device's lost
state into it. CNA's `is_content_lost` is the same fact from the renderer's side — true from a real
device reset until the target is next bound — so the latch is kept and a second read answers the
field.

DEVIATION, recorded: `ContentLost` is subscribable and never fires, for the reason the dynamic
buffers' does. `is_content_lost` is false on every renderer family that cannot lose a device, which
is all three qualified artifacts, and `cna_render_target_subscribe_content_lost` exists only in
0.21.0 — so binding it would both deliver nothing and end the retired 0.7.0 headers' admission.

## The binding is assembled here, and that is the difference from the vertex one

`VertexBufferBinding` reads its three values back from the structure `cna_vertex_buffer_binding_init`
fills. There is no `cna_render_target_binding_init`: the C structure is only ever consumed by
`cna_graphics_device_set_render_targets`, a `GraphicsDevice` member this binding has not projected.
So this one is assembled in Ruby, which is what XNA's own constructor does — two stores, and the
only validation is a null check with `NullNotAllowed`. A 2D binding is face zero, and `RenderTarget`
is declared as `Texture`, which is why a cube binding answers the cube.

## Native surface

Four routes bring the manifest to **353** and three layouts to **60** —
`CNA_RenderTarget2DCreateInfo`, `CNA_RenderTargetCubeCreateInfo` and `CNA_RenderTargetInfo`, every
field offset compiler-checked against both admitted header roots. No new constant.
`ABI_MISMATCHES=0`.

`CNA_RenderTargetInfo` carries a two-byte `reserved` tail in 0.21.0 that the retired 0.7.0 headers do
not declare; nothing here reads it, so the layout stops at `renderer_available` and both roots agree
on every field it does declare.

Deliberately unbound: `cna_graphics_device_set_render_target2d`, `..._cube`, `..._set_render_targets`
and `..._get_render_target_count`, which are `GraphicsDevice` members — a target that exists is not a
target that can be bound; the whole `cna_render_target_pool_*` family, which is 0.21.0-only and has
no XNA identity at all; `cna_render_target_subscribe_content_lost` and its unsubscribe; and
`cna_render_target_usage_preserves_contents`, which answers a question no XNA member asks.

## Mutation

Eight planted defects, seven caught: the properties reporting what was asked for rather than what was
got, the content-lost latch dropped, the 2D width and height read from the wrong offsets, the target
destroyed with the texture destroyer, the short constructor's usage default changed, a 2D binding
accepting a cube face, and the binding accepting any texture. The survivor reads a cube target's
`Size` from the info's `height` instead of its `width`, and is an **equivalent mutant**: CNA sets
both to the edge length for a cube, which the surviving run itself demonstrates.
