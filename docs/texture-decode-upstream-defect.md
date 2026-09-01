# `cna_texture2d_create_from_encoded_memory`: an asymmetric crop failure

Classified **UPSTREAM_CNA_DEFECT**. Reproduced, documented, and left in place: nothing in this
binding works around it, and no CNA source was changed.

## What was measured

`CNA_Texture2DDecodeInfo` documents `zoom` as "True to cover-and-crop; false to fit while preserving
aspect ratio". Decoding the 128×128 test PNG through `cna_texture2d_create_from_encoded_memory`, at
the **C ABI directly** with no Ruby in the path (`build-probe/decode.c`):

    64x64  zoom=0 -> SUCCESS 64x64
    64x64  zoom=1 -> SUCCESS 64x64
    64x32  zoom=0 -> SUCCESS 32x32
    64x32  zoom=1 -> INVALID_ARGUMENT
    32x64  zoom=1 -> SUCCESS 32x64
    200x100 zoom=1 -> INVALID_ARGUMENT

with the error text `ImageLoader: crop rectangle lies outside the source image`.

## The defect

The `zoom` (cover-and-crop) path is **asymmetric**. From a square source:

- a target that is **taller than wide** (`32x64`) crops and scales correctly;
- a target that is **wider than tall** (`64x32`, `200x100`) fails with `INVALID_ARGUMENT`.

Cover-and-crop is symmetric by definition — a 128×128 source covering a 64×32 target should crop to
128×64 and scale — so one of the two orientations is computing its crop rectangle wrongly. The
`zoom=false` path handles the same aspect mismatch correctly, fitting 128×128 into 64×32 as 32×32.

## Why the binding does not work around it

`Texture2D.FromStream(device, stream, width, height, zoom)` passes the three values through and lets
CNA answer. Substituting a fitted decode for a failed zoom would be this binding inventing a result
XNA does not produce and CNA did not give, which is the line every deviation in this project stays
on the right side of. `test_texture2d_save.rb` asserts the measured behaviour — both the successful
orientations and the failing one — so if the upstream path is fixed, the test will say so.

## Scope

Only the `zoom=true` decode is affected. The two-argument `FromStream`, the `zoom=false` decode, the
two constructors, `SetData`/`GetData` and both `SaveAs*` members are unaffected and are measured
green.
