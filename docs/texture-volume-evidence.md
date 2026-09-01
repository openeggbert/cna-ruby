# Foundation 79 — `Texture3D` and `TextureCube`

The two texture types `EffectParameter.GetValueTexture3D` and `GetValueTextureCube` return, and the
reason the `Effect` cluster could not have been strictly complete without them. Twenty identities
over two types; the strict scoreboard goes 174 complete / 80 missing to **176 complete / 78
missing**, and `TOTAL_DIAGNOSTICS` 176 to 174.

They are also **the first two types in this binding whose behaviour depends on which qualified
artifact is loaded**, which is what Native frontier 6 made measurable a milestone earlier.

## The contract, from the pinned IL

`Microsoft.Xna.Framework.Graphics.dll`, SHA-256 `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`,
disassembled with `ikdasm`. Both are `public auto ansi beforefieldinit` over `Texture`, **not
sealed** — `RenderTarget2D` and `RenderTargetCube` derive from them — with one public constructor
each and a `family` `Dispose(bool)`.

| | `Texture3D` | `TextureCube` |
| --- | --- | --- |
| Constructor | `(GraphicsDevice, int width, int height, int depth, bool mipMap, SurfaceFormat)` | `(GraphicsDevice, int size, bool mipMap, SurfaceFormat)` |
| Properties | `Width`, `Height`, `Depth` | `Size` |
| `SetData<T>` | `(T[])`, `(T[], int, int)`, `(int level, int left, int top, int right, int bottom, int front, int back, T[], int, int)` | `(CubeMapFace, T[])`, `(…, T[], int, int)`, `(CubeMapFace, int level, Nullable<Rectangle>, T[], int, int)` |
| `GetData<T>` | same three | same three |

Each type's public constructor forwards to a private `CreateTexture` whose validation is, in order:

1. `if (graphicsDevice == null) throw new ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)`
2. for `Texture3D`, `width`, then `height`, then `depth` — each
   `ArgumentOutOfRangeException(name, ResourcesMustBeGreaterThanZeroSize)` when not positive; for
   `TextureCube`, `size`, in `ValidateCreationParameters`
3. everything after that reads `GraphicsDevice._profileCapabilities` — `ValidVolumeFormats` and
   `MaxVolumeExtent`, `ValidCubeFormats` and `MaxCubeSize` — which is a **device** fact rather than
   a managed rule, so it is CNA's to refuse, exactly as `Texture2D`'s is.

All six data members forward to one private `CopyData`, which calls the same four helpers
`Texture2D`'s does — `Helpers.ValidateCopyParameters`, `Texture.GetAndValidateSizes`,
`Texture.ValidateTotalSize`, and `Texture.GetAndValidateRect` for the cube or
`Texture3D.GetAndValidateBox` for the volume. Those helpers are `static` members of `Texture` in
XNA, and they are private class methods of `Texture` here for the same reason: three types call
them.

**`GetAndValidateBox` compares unsigned.** Its six tests are `bgt.un`/`bge.un`, so a negative
coordinate wraps to a huge value and is refused by the same `left >= right` test rather than by a
sign check of its own. The refusal is `ArgumentException(InvalidRectangle, "box")` — the *rectangle*
resource string, with `"box"` as the parameter name.

## A defect this milestone fixed in `Texture2D`

`CopyData` opens

```
if (data == null || data.Length == 0)
    throw new ArgumentNullException("data", NullNotAllowed);
```

so an **empty** array is the same refusal as a null one, in all three texture types. The `Texture2D`
projection handled only the null case; an empty array fell through to
`Helpers.ValidateCopyParameters` and came back as `RangeError("elementCount")`, which is that
helper's answer to a different question. All three types now share the one rule.

## What CNA carries, and the one shape it does not

Ten canonical routes, five per type — `create`, `set_data`, `get_data`, `get_info`, `destroy` — and
six layouts. `ABI_MISMATCHES=0`; the manifest goes 260 to **270** routes and 37 to **43** layouts.
Two available routes stay unbound because neither has an XNA identity here:
`cna_texture3d_set_data_bytes` uploads a raw tightly packed pointer, and
`cna_texturecube_create_from_dds_memory` decodes a DDS cube map, which XNA reaches through the
content pipeline.

**DEVIATION, recorded.** Both transfer routes take `const CNA_Color*`, not the tagged
`CNA_TextureDataType` the `Texture2D` routes take. XNA's `SetData<T>` accepts any `T : struct` whose
size equals or divides the format's byte size, so a `Bgra4444[]` upload into a `Color` volume is
legal in XNA and has **no C route here**. The managed validation still runs first and in XNA's
order — measured: three `Bgra4444` elements into a one-texel `Color` face are refused with
`invalid total size` before the element type is looked at, and two are refused by the route's own
limit — and that refusal is `CNA::Runtime::NotSupportedError`, the projection of the exception XNA
itself raises when a profile cannot carry a request.

## The two artifacts answer differently, and both answers are recorded

| | HEADLESS | OPENGL33 |
| --- | --- | --- |
| `CNA_GRAPHICS_CAPABILITY_TEXTURE_3D` | false | true |
| `Texture3D.new` | refused: "this renderer does not support real volume (3D) texture storage" | succeeds |
| `TextureCube.new` | succeeds | succeeds |
| `TextureCube.SetData` | refused: "did not store the complete requested cube face region" | succeeds |
| voxels round-trip | — | 16 of 16, byte for byte |
| cube faces round-trip | — | six distinct faces, plus a one-texel sub-rectangle |

`test/renderer_environment.rb` measures both by *using* them — a one-texel round trip through the
same public members a consumer would call — rather than by reading a flag, and the volume
measurement is asserted equal to the capability the renderer reports. The **managed** contract is
asserted against both artifacts; the **storage** claim is made only where it was measured. Under
`HEADLESS` four tests skip and say why; under `OPENGL33` none does.

That is the difference Native frontier 6 bought. Before it, the honest options were to skip the data
path entirely or to record a refusal as though it were the type's behaviour.

## What they unblock

`Texture3D` leaves the frontier's `partialDependencySatisfied` list — its one unmet dependency was
the partial `GraphicsDevice`, whose members it reaches were already projected — and `TextureCube`
leaves the `ilOnlyBlocked` list, where its unmet dependency was `GraphicsAdapter` through
`Texture2D`'s IL. `Graphics.RenderTarget2D` takes `TextureCube`'s place on that list, behind the
`Texture2D` it derives from.

The `EffectParameter` surface they were built for now has every return type it names:
`GetValueTexture2D`, `GetValueTexture3D` and `GetValueTextureCube` all answer a projected type.
