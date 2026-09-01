# Upstream CNA defect — an upload into a render target reports success and is dropped

**Measured 2026-09-01 against `~/deps/cna-c-abi-0.21.0-opengl33/libcna_c_api.so`
(`CNA_PLATFORM=SDL3`, `CNA_GRAPHICS_RENDERER=OPENGL33`), on a live 1280×800 X display, and again
against `~/deps/cna-c-abi-0.21.0-opengles3-fx/libcna_c_api.so`.** Recorded here because
`Microsoft.Xna.Framework.Graphics.RenderTarget2D` inherits `Texture2D.SetData`, so the projection
carries a member whose upload the runtime beneath it silently discards.

## What was measured

In one frame, with one device, two handles and the **same** two routes:

| Handle | `cna_texture2d_set_data` | `cna_texture2d_get_data` | Pixels read back |
| --- | --- | --- | --- |
| `cna_render_target2d_create` | `CNA_RESULT_SUCCESS` | `CNA_RESULT_SUCCESS`, 4 written | `[0, 0, 0, 0]` |
| `cna_texture2d_create` | `CNA_RESULT_SUCCESS` | `CNA_RESULT_SUCCESS`, 4 written | the four pixels uploaded |

No Ruby validation is in that path: the probe calls both routes through raw `Fiddle::Function`s with
a hand-built `CNA_Texture2DTransfer`, and the plain texture proves the transfer descriptor is right.

## What is *not* wrong

- **Readback works.** `tools/run_renderer_qualification.rb` has been binding a target, clearing it to
  0.25/0.5/0.75/1 and reading `64/128/191/255` back through `cna_texture2d_get_data` since Native
  frontier 6. The route reads a render target's real contents.
- **Creation works.** Width, height, level count, negotiated format, depth format, sample count and
  usage all come back from `cna_render_target_get_info` and match what was asked for where the
  adapter can give it.
- **It is not the headless artifact.** On `HEADLESS` the readback route answers
  `CNA_RESULT_NOT_SUPPORTED` — an honest refusal — so the defect is only observable where readback
  exists, which is both real-renderer artifacts.

## The exact affected behaviour

`RenderTarget2D.SetData` — every overload, since they share `Texture2D`'s — reports success and
changes nothing. `GetData` is unaffected, and so is every other inherited member. `RenderTargetCube`
inherits `TextureCube.SetData`, whose route is `cna_texturecube_set_data`; that path was not measured
here because no qualified artifact has cube-face storage at all.

## What this binding does about it

Nothing, deliberately. XNA declares `SetData` on the base and `RenderTarget2D` does not override it,
so refusing the call here would invent a rule the pinned IL does not have, and returning an error
would be a worse lie than CNA's. The projection passes the call through, and
`test/test_render_targets.rb` pins **both** halves of the measurement — the render target's zeros and
the plain texture's exact round trip — so the day CNA fixes this, the test says so.

Classified `UPSTREAM_CNA_DEFECT`. The capability row is `graphics.render-targets`.

## Suggested upstream fix, stated without taking it

Either honour the upload against the render target's colour attachment — the same surface
`cna_texture2d_get_data` already reads — or refuse it with `CNA_RESULT_NOT_SUPPORTED`, which is what
the same runtime does for readback on a renderer that cannot do it. Reporting success for a transfer
that does not happen is the one option that leaves a caller unable to tell.
