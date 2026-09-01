# Foundation 82 — `DirectionalLight`, `EffectMaterial`, and the contract they unblocked

Three types, twelve identities, and the twelfth and thirteenth `NATIVE_RUNTIME` deferral this
project has retired. The strict scoreboard goes **191 complete / 64 missing to 194 / 61**,
`TARGET_MEMBERS` 2313 to 2325 and `TOTAL_DIAGNOSTICS` 157 to **154**. No route was bound: everything
these types need was bound by the `Effect` cluster.

| Type | Identities | Shape |
| --- | --- | --- |
| `DirectionalLight` | 5 | sealed, one public ctor, four properties |
| `IEffectLights` | 6 | interface: one method, five properties |
| `EffectMaterial` | 1 | `Effect` subclass, one public ctor, nothing else |

## The blocker named `SetValue`, which is projected

The frontier reported `DirectionalLight` as `NATIVE_RUNTIME` on `.ctor`, `set_Enabled`,
`set_Direction` and `set_DiffuseColor`, and `EffectMaterial` as `NATIVE_RUNTIME` on `.ctor`. Read as
"this type needs a native runtime this binding does not have", both are wrong, and for the same
reason the register has been wrong eleven times before: the reachability is real but it goes through
a **projected** member.

- Every native edge `DirectionalLight` has is `EffectParameter::SetValue(Vector3)`. The type itself
  is three `EffectParameter` fields, a `bool` and three cached `Vector3`s, and every one of its
  identities is a field read, a field write, or a null-guarded call to that setter. It touches no
  device, holds no handle, and has no `Dispose`.
- `EffectMaterial`'s single constructor is `ldarg.0; ldarg.1; call Effect::.ctor(Effect); ret`. Its
  native edge is the clone constructor, which the `Effect` cluster built.

## What the IL actually says, and it is not symmetric

```
set_Direction(v):      if directionParam != null: directionParam.SetValue(v)
                       cachedDirection = v
set_DiffuseColor(v):   if enabled && diffuseColorParam != null: diffuseColorParam.SetValue(v)
                       cachedDiffuseColor = v
set_Enabled(value):    if value == enabled: return
                       enabled = value
                       if enabled:  diffuseColorParam?.SetValue(cachedDiffuseColor)
                                    specularColorParam?.SetValue(cachedSpecularColor)
                       else:        diffuseColorParam?.SetValue(Vector3.Zero)
                                    specularColorParam?.SetValue(Vector3.Zero)
```

Three rules a reader would not guess and all three are asserted from the parameter's side:

1. **The direction is written whether the light is enabled or not; the two colours are not.** A
   disabled light remembers its colours and the shader sees `Vector3.Zero`, which is how XNA turns a
   light off without losing what it was set to.
2. **An unchanged `Enabled` write does nothing at all** — `beq.s` before anything else — so writing
   `false` over `false` does not push zero into a parameter something else has since written.
3. **The constructor's two paths differ in kind.** With no `cloneSource` it goes through its own
   three setters with `Vector3.Down`, `Vector3.One` and `Vector3.Zero`, and because `enabled` is
   still `false` at that moment only the direction reaches a parameter. With a `cloneSource` it
   copies the **fields**, so a clone writes nothing at all — which is what lets `BasicEffect.Clone`
   hand three lights to a new effect without disturbing the shader it is cloning into.

Every parameter may be null and every call site checks: a `BasicEffect` whose shader declares no
specular parameter really does construct a light with `specularColorParam` null, and each write to
it is skipped rather than raised on.

## Measured against FNA's own `BasicEffect.fxb`

`CNA_TEST_FX_BASIC` points at
`cnacnb/modules/renderers/fna3d/effects/BasicEffect.fxb` — referenced by path, never copied into
this repository, exactly as the XACT, XNB and conformance-effect fixtures are. It is the authentic
fixture for this type: `BasicEffect` is where XNA constructs a `DirectionalLight`, and this shader
declares exactly the three `float3` parameters it constructs one over —
`DirLight0Direction`, `DirLight0DiffuseColor`, `DirLight0SpecularColor`, and the same trio for lights
1 and 2.

The conformance effect this project already used could not test any of it: its only vector parameter
has four columns, and `GetValueVector3` on a four-column parameter is an `InvalidCastException` in
XNA and a `TypeError` here. Choosing a fixture that can express the type's own shape is the
difference between a test and a skip.

Measured, in one frame, over a real compiled effect on the `OPENGLES3` artifact:

- the constructor writes `Vector3.Down` into the direction parameter and leaves both colour
  parameters at zero;
- setting a colour while disabled reaches no parameter, enabling pushes both cached colours in, and
  disabling again pushes `Vector3.Zero` into both while the cached values survive;
- a redundant `Enabled = false` leaves a value another writer put there untouched;
- a clone built over live parameters writes none of them.

## `IEffectLights`, and nothing conforms to it

The third effect contract, and the one that could not be projected until something produced a
`DirectionalLight`: three of its six members return one. Like `IEffectMatrices`, `IEffectFog`,
`IVertexType` and `IGraphicsDeviceService`, it is an **abstract contract** — every member raises
`NotImplementedError`, and `DirectionalLight` deliberately does not include it, because the light is
what an implementer hands out rather than an implementer itself. XNA's implementers are
`BasicEffect`, `SkinnedEffect` and `EnvironmentMapEffect`, none of which is projected yet.

## The frontier fell to three, its lowest ever

`dependencyCompleteCandidates` **5 → 3**, and nothing arrived on that list behind the two that left.
What they uncovered went to `partialDependencySatisfiedCandidates` instead — four entries to seven,
with `BasicEffect`, `SkinnedEffect` and `EnvironmentMapEffect` joining `AlphaTestEffect` and
`DualTextureEffect` — because every one of them also reaches the partial `GraphicsDevice`.

What is left on the candidate list is `MathTypeConverter` (`BCL_PROJECTION`, the converter family),
`GraphicsAdapter` (`UPSTREAM_CNA_BLOCKED`, see
`docs/graphics-adapter-ordering-upstream-defect.md`) and `ModelMeshPart`, whose `Draw` reaches
`GraphicsDevice.SetVertexBuffer`, `set_Indices` and `DrawIndexedPrimitives` — three members this
binding does not project. That is the first `NATIVE_RUNTIME` on this frontier in a long while that
names something genuinely absent.

## Mutation

Nine planted defects, nine caught: the unchanged-write guard dropped, disabling forgetting instead of
pushing zero, the diffuse setter writing while disabled, the direction setter writing only while
enabled, the clone constructor going through the setters, a changed constructor default, a null
parameter raising instead of being skipped, the incoming `Vector3` retained rather than copied, and
the material no longer deriving from `Effect`.

## What this milestone does not do

It builds no stock effect. `BasicEffect`, `SkinnedEffect`, `EnvironmentMapEffect`, `AlphaTestEffect`
and `DualTextureEffect` are all still missing, and all five need
`cna_effect_matrices_set_world`/`_view`/`_projection`, which take `CNA_Matrix` **by value** — a
64-byte MEMORY-class aggregate that Fiddle cannot pass and no pointer variant exists for. It binds no
route, adds no constant and no layout.
