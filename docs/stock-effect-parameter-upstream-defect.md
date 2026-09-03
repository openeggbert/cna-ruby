# Upstream CNA gap — `BasicEffect` alone declares no `EffectParameter`s

**Measured 2026-09-03 against all three qualified artifacts:
`~/deps/cna-c-abi-0.21.0` (`HEADLESS`), `~/deps/cna-c-abi-0.21.0-opengl33` and
`~/deps/cna-c-abi-0.21.0-opengles3-fx` (the last two under `xvfb-run` with `SDL_VIDEODRIVER=x11`,
on a live 1280×800 X display).** All three answer identically.

## What was measured

One `EffectParameterCollection` per stock effect, read straight back from
`cna_effect_get_parameters` on the handle each `cna_<name>_effect_create` returns:

| Effect | `Parameters.Count` | `Techniques.Count` |
| --- | --- | --- |
| `BasicEffect` | **0** | 1 |
| `SkinnedEffect` | 12 | 1 |
| `AlphaTestEffect` | 6 | 1 |
| `DualTextureEffect` | 5 | 1 |
| `EnvironmentMapEffect` | 12 | 1 |

The four non-empty collections are named and shaped, and every row is asserted by
`StockEffectsTest::STOCK_EFFECT_PARAMETERS` so a change upstream is caught rather than absorbed:

- `SkinnedEffect` — `DiffuseColor` (1×4), `EmissiveColor` (1×3), `SpecularColor` (1×3),
  `SpecularPower` (1×1), `EyePosition` (1×3), `FogColor` (1×3), `FogVector` (1×4), `World` (4×4),
  `WorldInverseTranspose` (4×4), `WorldViewProj` (4×4), `Bones` (72×4), `ShaderIndex` (1×1, `Int32`).
- `AlphaTestEffect` — `DiffuseColor` (1×4), `AlphaTest` (1×4), `FogColor`, `FogVector`,
  `WorldViewProj`, `ShaderIndex`.
- `DualTextureEffect` — `DiffuseColor`, `FogColor`, `FogVector`, `WorldViewProj`, `ShaderIndex`.
- `EnvironmentMapEffect` — `EnvironmentMapAmount` (1×1), `EnvironmentMapSpecular` (1×3),
  `FresnelFactor` (1×1), then the same `DiffuseColor`/`EmissiveColor`/`EyePosition`/`FogColor`/
  `FogVector`/`World`/`WorldInverseTranspose`/`WorldViewProj`/`ShaderIndex` tail.

Every parameter answers `EffectParameterType.Single` except `ShaderIndex`, which is `Int32`, and
every one answers `Elements.Count` zero — including `Bones`, which CNA flattens into a 72-row matrix
rather than an array of 72.

## Why this is a gap rather than a design

Two independent reasons, neither of them an interpretation:

1. **The four siblings.** If a stock effect were meant to carry no parameter metadata, none of them
   would. Four of five do, with the names XNA's own stock shaders use.
2. **Upstream has since fixed exactly this.** `cnanext`
   (`/rv/data/development/github.com/openeggbert/cnanext`, read-only here) carries
   `d5c5958ed` *fix(SAMPLE-152): expose authentic BasicEffect parameters* and `8cab5f32a`
   *fix(SAMPLE-152): match BasicEffect technique metadata*, both dated **2026-09-02** — after the
   0.21.0 pin. `modules/graphics/src/Xna/BasicEffect.cpp:69` now registers twenty-one parameters in
   `CacheEffectParameters`, including the three directional lights' nine and a `Texture` of
   `EffectParameterClass::Object`. The construction path is unchanged:
   `cna_basic_effect_create` (`modules/c-api/src/CnaCApiEffects.cpp:4656`) is one
   `std::make_shared<BasicEffect>` in both versions, so nothing about the C ABI shape is at issue.

## What is *not* wrong

- **The property values are right.** Every stock-effect property this binding projects reaches its
  own typed route (`cna_basic_effect_get_diffuse_color` and its kin), not the parameter collection,
  and each was measured equal to the constructor IL's default. An empty `Parameters` costs nothing
  a projected property answers.
- **`Techniques` is right on all five.** One technique each, and `CurrentTechnique` answers it.
- **`EffectParameterCollection` is right.** `test_effect_cluster.rb` exercises the collection, its
  indexers and its bounds against a compiled effect that declares real parameters.
- **It is not artifact-specific.** Unlike the render-target upload defect, this reproduces on the
  headless artifact and both real renderers alike.

## The exact affected behaviour

`Microsoft.Xna.Framework.Graphics.BasicEffect.Parameters` answers an empty collection where XNA's
answers one entry per shader parameter. `Parameters[0]` therefore raises the collection's own
out-of-range refusal, and `Parameters["DiffuseColor"]` answers nil. No other member of any of the
five is affected.

## What this binding does about it

Nothing is fabricated. `BasicEffect.Parameters` answers what CNA answers, the deviation is recorded
on the type, and two tests pin it from both sides:

- `BasicEffectTest#test_a_stock_effect_has_no_parameters_and_one_technique` — the empty one.
- `StockEffectsTest#test_the_parameter_collections_are_the_measured_ones` and
  `#test_basic_effect_is_the_only_one_with_an_empty_parameter_collection` — the other four, by name
  and shape, and the assertion that `BasicEffect` is the *only* empty one.

If a later CNA populates it, all three fail rather than silently changing what `Parameters` means.

## Correction to an earlier record

The `BasicEffect` type comment, `CNA::Native::Manifest` and `CNA::Runtime::StockEffectSupport` all
previously generalised the empty collection to the whole family — "stock effects expose zero
`EffectParameter`s". That was measured on `BasicEffect` only, and Foundation 98 measured the other
four. Each of the three claims now names the one type it is true of.
