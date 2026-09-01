# Foundation 88 — the first draw call this binding has ever made

`GraphicsDevice.DrawPrimitives`, `DrawIndexedPrimitives` and `DrawInstancedPrimitives`: three more of
the twenty-three members the device owed, and the point at which everything built since the vertex
structs becomes a picture. `MISSING_MEMBER` goes **49 → 46**, `OVERLOAD_MAPPING_MISMATCH` 21 → **18**
and `TOTAL_DIAGNOSTICS` 128 → **122**.

## What the IL validates, and what it leaves to the device

```
primitiveCount <= 0   -> ArgumentOutOfRangeException("primitiveCount", MustDrawSomething)
numVertices <= 0      -> ArgumentOutOfRangeException("numVertices", NumberVerticesMustBeGreaterZero)
instanceCount <= 0    -> ArgumentOutOfRangeException("instanceCount", MustDrawSomething)
primitiveCount > the profile's maximum -> ProfileMaxPrimitiveCount
a bound stream with a non-zero InstanceFrequency, on the two non-instanced calls
                      -> InvalidOperationException(NonZeroInstanceFrequency)
```

The profile maximum is a capability rather than a managed rule and stays CNA's to refuse, exactly as
the occlusion query's profile check does. The instance-frequency guard **is** a managed rule, and
this projection has the fact it needs because the binding slice cached the bindings when they were
set: `instanceStreamMask` is XNA's record of the same thing.

`DrawInstancedPrimitives` deliberately carries **no** such guard — a non-zero frequency is what it
is for — and the test asserts that from both sides, because a guard added there would be invisible
to any test that only checks the two calls that must have it.

## A real draw, measured

The first three attempts failed, and each failure is worth recording because each is a real
precondition rather than a defect:

1. Without an applied effect, every draw is refused: *"GraphicsDevice::DrawPrimitives: no effect has
   been applied"* (`CNA_RESULT_NOT_SUPPORTED`). A draw needs a program, and CNA says so instead of
   drawing nothing quietly.
2. With the conformance effect applied, the draw is refused again: *"this compiled effect's vertex
   shader requires attribute 'vs_v1' (usage 5, index 0), but none of the 1 vertex stream(s) supplied
   to this draw declares an element with that usage and usage index"* — usage 5 is `Tangent`, which
   none of the four projected vertex structs declares.
3. With **FNA's own `BasicEffect.fxb`** — the fixture the `DirectionalLight` milestone already
   references by path through `CNA_TEST_FX_BASIC` — and a `VertexPositionColor` buffer, all three
   draw calls **succeed**.

So the measured sequence is: build a vertex buffer and an index buffer, bind both, compile an effect,
apply a pass, and draw. Every one of those steps is a member this project built, and the last one
returns `CNA_RESULT_SUCCESS` on the compiled-effects artifact. A second pass over the same geometry
is asserted too, because multi-pass is the ordinary shape and it is what `EffectPass.Apply` exists
for.

Nothing is claimed about what the picture *looks* like: no readback is asserted, because the draw's
own contract is that it submits.

## Native surface

Three routes bring the manifest to **383**. Every parameter is a scalar, so nothing here is passed
by value and nothing is allocated. The topology parameter is declared as the enum it is —
`CNA_PrimitiveType` rather than a bare `uint32_t` — which the ABI gate insisted on: it failed with
three signature mismatches until the manifest spelled the C type the header really declares.

`cna_graphics_device_draw_user_primitives` and `..._draw_user_indexed_primitives` stay unbound: the
two user-primitive families are the draw calls that remain, and they take the vertices as an
argument rather than reading the device's own bound buffers.

## Mutation

Six planted defects, six caught: each of the three count guards accepting zero, the
instance-frequency guard dropped, that same guard *added* to the instanced call, and the indexed
draw passing `startIndex` and `numVertices` in each other's places.

## What this milestone does not do

`GraphicsDevice` still owes twenty members: `DrawUserPrimitives` and `DrawUserIndexedPrimitives`,
`Present`, `Reset`, `Dispose`, `GetBackBufferData`, the four identity properties — `Adapter` among
them, still `UPSTREAM_CNA_BLOCKED` — and its six events.
