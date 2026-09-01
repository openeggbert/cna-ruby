# Foundation 80 — the `Effect` cluster, and the type it completed

Nine types, ninety-six identities, and the one that closes `SpriteBatch`. The strict scoreboard goes
**176 complete / 78 missing to 186 / 69**, `TOTAL_DIAGNOSTICS` 174 to 162, and the partial register
falls from three types to **two**: `GraphicsDeviceManager` and `GraphicsDevice`.

| Type | Identities | Shape |
| --- | --- | --- |
| `EffectParameter` | 51 | sealed, `assembly` ctor |
| `EffectAnnotation` | 14 | sealed, `assembly` ctor |
| `EffectParameterCollection` | 5 | sealed, `assembly` ctor |
| `EffectAnnotationCollection` | 4 | sealed, `assembly` ctor |
| `EffectPassCollection` | 4 | sealed, `assembly` ctor |
| `EffectTechniqueCollection` | 4 | sealed, `assembly` ctor |
| `EffectPass` | 3 | sealed, `assembly` ctor |
| `EffectTechnique` | 3 | sealed, `assembly` ctor |
| `Effect` | 8 | **not** sealed, one public ctor and one `family` one |

## The producer, and the artifact that has one

`Effect`'s public constructor takes compiled Effect Framework bytecode, and
`cna_effect_create_compiled` accepts it only where
`CNA_GRAPHICS_CAPABILITY_COMPILED_EFFECTS` is true. That capability needs the MojoShader runtime,
which is a **fetched dependency** the EasyGL, SDL_GPU and Vulkan renderer families carry only when
their build option is on — so the capability never claims more than the binary contains.

Of the three qualified artifacts, exactly one has it: `cmake-build-debug`'s `OPENGLES3` build with
`-DCNA_EASYGL_COMPILED_EFFECTS=ON`, staged as
`~/deps/cna-c-abi-0.21.0-opengles3-fx/libcna_c_api.so`, SHA-256
`ab055b5e9c10b57d9755445951b118406bc065ca9eaa3fe4c0851a2352bb3e6e`. It passes the same ABI gate as
the other two — 334 functions, 5 callbacks, 129 constants, 50 layouts, `ABI_MISMATCHES=0`. **No CNA
source was changed and no CNA build was run**; the artifact already existed.

The fixture is FNA's own `CnaConformanceEffect.fxb`, referenced **by path** through `CNA_TEST_FX`
the way the XACT and XNB fixtures are referenced, and never copied into this repository. It is a
deliberately complete specimen: six parameters covering every `EffectParameterClass` — a `Scalar`
with a semantic and an annotation, a four-column `Vector`, a `Matrix`, a two-element array, a
three-member `Struct` and an `Object` texture — and two techniques with three passes between them.

Under that artifact the cluster's own suite is **21 tests / 187 assertions / 0 skips**. Under the
other two the *structure* is still fully asserted and every behavioural test skips with the reason.

## Ownership: a fresh handle is not a new object

Measured, not assumed. Every getter in CNA's effect surface returns an **owned view**:

- two `cna_effect_get_parameters` calls answer two different collection handles;
- two `cna_effect_parameter_collection_get_at(0)` calls answer two different parameter handles that
  name the same parameter;
- every one of them must be destroyed — the game refuses to be destroyed while any child lives,
  which is CNA's own strongest statement about it;
- `cna_effect_destroy` succeeds **while element views are still alive**, and those views can still
  be destroyed afterwards.

XNA is the opposite: `Effect`'s constructor builds one `List<EffectParameter>` and `get_Parameters`
is a single `ldfld`, so `effect.Parameters[0]` is the *same object* every time and reference
equality is observable. So the projection builds the whole graph once — parameters, their elements,
structure members and annotations, techniques, their passes and annotations — holds one Ruby object
per logical child, and releases every view when the `Effect` is disposed, in reverse order. Seven
identity assertions state that directly, `Parameters[name]` included.

## What the IL says, member by member

- **`Effect(GraphicsDevice, byte[])`** checks the **bytecode before the device**, which is not the
  order a reader would guess: null-or-empty `effectCode` is
  `ArgumentNullException("effectCode", NullNotAllowed)`, a length that is not a multiple of four is
  `ArgumentException`, and only then is a null device
  `ArgumentNullException("graphicsDevice", …)`. The fourth check — fewer than eight bytes or a
  first dword that is not `0xBCF00BCF` — is `InvalidOperationException(MustUserShaderCode)` and is
  left to the route, which is the one that knows which containers this build accepts.
- **`Clone()`** is `newobj Effect::.ctor(Effect); ret` and nothing else. The `family` clone
  constructor refuses a null source, a disposed source and a source with no device, in that order.
- **`CurrentTechnique`**'s getter is one `ldfld`. Its setter checks disposal, refuses null with
  `ArgumentNullException("value")`, **returns without touching anything** when handed the value it
  already holds, and raises a **parameterless** `InvalidOperationException` for a technique
  belonging to another effect.
- **`OnApply()`**'s whole body is `ret`. It is `famorassem` virtual and exists to be overridden.
- **`EffectPass.Apply`** is `CheckDisposed`, then
  `if (effect.CurrentTechnique != _technique) throw new InvalidOperationException(NotCurrentTechnique)`,
  then `effect.OnApply()`, then the native apply — in that order, so an override observes the check
  having passed and the native apply not yet having happened. CNA enforces the same rule itself:
  measured, a pass outside the current technique answers `CNA_RESULT_INVALID_STATE` with "Applied a
  pass not in the current technique!". The managed check is what puts the failure in XNA's exception
  class and lets `OnApply` run where XNA runs it.
- **All four collections** answer **null**, not an exception, for an index outside their range;
  `Item[String]` scans by name with `String::op_Equality`; and
  `EffectParameterCollection.GetParameterBySemantic` scans with
  `String.Compare(…, OrdinalIgnoreCase)` — the one **case-insensitive** member in the cluster, which
  is exactly why CNA's `cna_effect_parameter_collection_find_name` and `find_semantic` are **not
  bound**: both match exactly, and binding the second would change this member's answer.

### `EffectParameter`'s guards, and the one the earlier audit got wrong

The numeric getters share one guard, and it reads **`Elements`**, not `StructureMembers`:

```
if (_paramClass != Scalar && pElementCollection.Count == 0)
    throw new InvalidCastException();
```

`pElementCollection` is what `get_Elements` returns and `pParamCollection` is what
`get_StructureMembers` returns. A previous handoff recorded this guard as
`StructureMembers.Count == 0`; the IL is unambiguous and it is `Elements`.

The vector getters are a different shape again:

```
result = default;
if (Elements.Count == 0) {
    if (ParameterClass == Scalar) { f = GetFloat(); broadcast f to every component; return result; }
    if (ParameterClass != Vector) throw new InvalidCastException();
    if (!(ColumnCount == N && RowCount == 1)) throw new InvalidCastException();
}
v = GetVector();   // a float4 whatever the declared width
```

The scalar branch really does broadcast — `GetValueVector3` on a `Scalar` answers `(f, f, f)`, and
`GetValueMatrix` sets all sixteen fields — and that is asserted against a real effect, not argued.
`GetValueMatrix` has **no** row or column test, only the class one. `GetValueString` checks
`ParameterType != String`, and each texture getter accepts `Texture` **or** its own dimension.

`System.InvalidCastException` is the first of its kind this binding raises. It maps to Ruby's
`TypeError`, which is what a failed conversion raises there.

## `EffectAnnotation` is `EffectParameter`, one instruction at a time

Every one of its eight `GetValue*` members is three instructions: construct a temporary
`EffectParameter(pEffect, null, _handle, -1)` and forward. So an annotation's value semantics **are**
the parameter's, guards included, and the projection applies the same rules to the annotation's own
metadata while taking the values from CNA's annotation routes — the standard split, CNA for runtime
data and XNA IL for the contract.

**DEVIATION, recorded.** XNA's temporary parameter builds an element collection from the same D3DX
descriptor, so its `Elements.Count` guard reads whatever that descriptor says. CNA's annotation
surface exposes no element collection, and an HLSL annotation is a scalar, vector, matrix or string
literal — never an array — so the guard is applied with a count of zero. That is the one place this
type is not a mechanical re-reading of the IL.

## `SpriteBatch` is complete

`Begin`'s six- and seven-argument overloads were the type's whole remainder. The six-argument form
is `Begin(…, effect, Matrix.Identity)` — one `call Matrix::get_Identity` and a forward — and the
seven-argument one stores its arguments, **nulls included**, and lets `SetRenderState` substitute
defaults at apply. A null `Effect` selects the stock sprite effect, which is exactly what
`CNA_INVALID_HANDLE` selects on `cna_sprite_batch_begin_with_effect`, and a null `CNA_Matrix*` is the
identity the route documents — so the two agree without this projection choosing anything. Measured
end to end: a sprite really draws through a compiled effect with a scale transform.

That leaves `GraphicsDevice` and `GraphicsDeviceManager` as the only partial types.

## The frontier rose, which is what advancing looks like

`dependencyCompleteCandidates` went **3 → 4**. `EffectAnnotation` left it by being built, and
`Graphics.EffectMaterial` and `Graphics.DirectionalLight` arrived behind the `Effect` base — the same
uncovering a completed base always causes. `AlphaTestEffect` and `DualTextureEffect` joined
`partialDependencySatisfiedCandidates`, and `RenderTargetCube` joined `RenderTarget2D` on the
il-only blocked list. Every one of those is new work the cluster made visible.

## Native surface

Sixty-four routes bring the manifest to **334**, twenty-eight constants to **129** and seven layouts
to **50** — `CNA_Vector3`, `CNA_Vector4`, `CNA_Quaternion`, `CNA_Matrix`, `CNA_Color`,
`CNA_EffectParameterInfo` and `CNA_EffectAnnotationInfo`, every field offset compiler-checked.
`ABI_MISMATCHES=0`.

Deliberately unbound, each because it has no XNA identity here: `cna_effect_create_empty`,
`cna_sprite_effect_create`, `cna_effect_parameter_create`, `cna_effect_annotation_create`,
`cna_effect_pass_create`, `cna_effect_technique_create_named`, `cna_effect_technique_create_default`,
every `*_collection_create`/`add*`, and the two `find` routes whose matching rule is not XNA's.
Nothing public makes a bare parameter, annotation, pass, technique or collection, and a route bound
only for a test is native surface this project does not carry.
