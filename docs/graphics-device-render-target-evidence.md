# Foundation 87 — `GraphicsDevice`'s render-target slice, and the display isolation it exposed

Four more of the twenty-six members the device owed: `SetRenderTarget`'s two overloads,
`SetRenderTargets` and `GetRenderTargets`. `MISSING_MEMBER` goes **53 → 49**,
`OVERLOAD_MAPPING_MISMATCH` 24 → **21** and `TOTAL_DIAGNOSTICS` 135 → **128**. A render target that
exists is now a render target that can be made **current**.

## Everything forwards to the array form, on both sides

XNA's two `SetRenderTarget` overloads build one `RenderTargetBinding` and call the internal array
form; a null target calls it with `(null, 0)`, which restores the back buffer rather than raising.
This projection does the same, which is why CNA's two single-target routes —
`cna_graphics_device_set_render_target2d` and `..._cube` — have **no production caller** and stay
unbound. One route, `cna_graphics_device_set_render_targets`, carries every shape.

`GetRenderTargets` is `newarr` + `Array.Copy`: a fresh array each call over the same binding
objects, so a caller mutating what it was handed cannot change what the device holds.

## The four managed rules, and the one early-out that is not an optimisation

```
count > profile max render targets -> ProfileMaxRenderTargets      (CNA's answer; see below)
a null binding                     -> ArgumentException(NullNotAllowed)
a target from another device       -> InvalidOperationException(InvalidDevice)
the same target twice              -> ArgumentException(CannotSetAlreadyUsedRenderTarget)
targets of different shapes        -> ArgumentException(RenderTargetsMustMatch)
an array equal to the current one  -> return untouched, before anything else
```

The early-out matters rather than saving work: re-binding a `DiscardContents` target is what
**discards its contents**, so a redundant `SetRenderTarget` that re-applied would silently throw a
frame away. The test asserts it by identity — the same call twice keeps the binding object it
already had, and so does an equal binding built separately.

`RenderTargetsMustMatch` measures a cube by its **edge**, which is both of its dimensions: a 4×4
target and a 4-edge cube are the same shape, and a 2-edge cube is not. That is asserted from both
sides, and it is what makes the mismatch rule a real rule rather than a size comparison that happens
to pass.

The profile limit is CNA's to answer, as the occlusion query's was: no profile table is invented
here. What the measurement did find is that `HEADLESS` refuses a **cube face alongside another
target** with `CNA_RESULT_NOT_SUPPORTED` — a renderer capability rather than an XNA rule, so the
test accepts either the native refusal or success and requires only that the *managed* answer is not
an `ArgumentError`.

## Native surface

One route brings the manifest to **380** and one layout to **62** —
`CNA_RenderTargetBinding`, identical in both admitted header roots. `array_slice` is a 3D/array
subresource this binding never sets, because XNA's `RenderTargetBinding` carries a cube face and
nothing else. `ABI_MISMATCHES=0`.

`get_render_target_count` and `copy_render_targets` stay unbound for the reason the vertex
read-backs do, and the test reaches them through raw Fiddle.

## Mutation

Seven planted defects, seven caught: a null target raising instead of restoring the back buffer, the
duplicate check dropped, the matching-shape check dropped, the identical-array early-out dropped,
the cube face not carried into the C structure, `GetRenderTargets` handing out its own array, and a
cube's edge no longer counting as both dimensions.

## The display isolation this milestone exposed, and the rule it added

While this slice was being built the developer reported windows opening on their desktop. They were
this project's: **`xvfb-run` alone is not isolation on this host.** It sets `DISPLAY` but leaves
`WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` alone, and SDL prefers Wayland when it can reach it — so a
windowed artifact run without `SDL_VIDEODRIVER=x11` ignores the virtual display entirely and opens a
real window per `Game`. A churn or a suite run makes that hundreds.

The rule is now in `docs/real-renderer-qualification-evidence.md` and in this session's environment:
a windowed artifact runs under `xvfb-run` **and** `SDL_VIDEODRIVER=x11`, with `WAYLAND_DISPLAY`
unset. It also explains the `OPENGL33` crash Foundation 81 measured: that artifact was crashing on
Wayland, not on X11.

## What this milestone does not do

`GraphicsDevice` still owes twenty-three members. Nothing here draws.
