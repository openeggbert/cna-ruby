# The four vertex structs

`VertexPositionColor`, `VertexPositionTexture`, `VertexPositionColorTexture` and
`VertexPositionNormalTexture` — 4 types, 38 Ruby member identities.

## The first work queue this frontier has consumed

They are not an audit. The dependency frontier ranked all four **consumable** — no blocker, no
unmet dependency, no unmapped BCL identity — and `SELECTED_NEXT` named `VertexPositionColor`. That
had not happened since Foundation 32.

Building them took `dependencyCompleteCandidates` 8 → 4 and `consumableCandidates` 4 → 0, and
nothing arrived behind them, which is unusual: the several milestones before this one each uncovered
something. The reason is that these are **leaf value types**. Everything they name — `Color`,
`Vector2`, `Vector3`, `VertexDeclaration`, `IVertexType` — was already complete.

## The first real interface producers

Foundation 40's rule is that an interface has a producer when some type declares it in the pinned
contract, is complete in this projection, **and** whose live Ruby class really includes the projected
module. Until now no type in this binding satisfied the third clause for any interface: `IVertexType`
was projected one milestone earlier with nothing conforming to it, deliberately.

All four of these conform. `IGraphicsDeviceService` is now the only producerless interface anywhere
on the report, and it is the one `DrawableGameComponent` still waits on.

## The explicit interface implementation

XNA implements the interface member explicitly:

    .method private hidebysig newslot specialname virtual final
            Microsoft.Xna.Framework.Graphics.IVertexType.get_VertexDeclaration() cil managed
    { ldsfld VertexPositionColor::VertexDeclaration; ret }

`private` in the metadata. In C# `v.VertexDeclaration` does not compile on the concrete type;
`((IVertexType)v).VertexDeclaration` does. The Ruby analogue is a **private instance method**, and
the public name of the same spelling is the type's `static initonly` field, which projects to a
constant. The two never collide, and both halves are asserted — including that the public spelling
raises `NoMethodError`.

This is why the four add no `UNEXPECTED_MEMBER`: the verifier reads
`public_instance_methods(false) + protected_instance_methods(false)`, and an explicit
implementation is neither, in the IL or here.

## The static declarations, from each class constructor

| type | elements | stride |
| --- | --- | ---: |
| `VertexPositionColor` | `(0, Vector3, Position, 0)`, `(12, Color, Color, 0)` | 16 |
| `VertexPositionTexture` | `(0, Vector3, Position, 0)`, `(12, Vector2, TextureCoordinate, 0)` | 20 |
| `VertexPositionColorTexture` | `(0, Vector3, Position, 0)`, `(12, Color, Color, 0)`, `(16, Vector2, TextureCoordinate, 0)` | 24 |
| `VertexPositionNormalTexture` | `(0, Vector3, Position, 0)`, `(12, Vector3, Normal, 0)`, `(24, Vector2, TextureCoordinate, 0)` | 32 |

Each `.cctor` builds the array, constructs the declaration and then sets `Name` to
`"<TypeName>.VertexDeclaration"`. The strides are not written down twice: they are what the
`VertexDeclaration` built one milestone earlier computes from the elements, and the test asserts
them from the object rather than from a table.

## `GetHashCode`

`Helpers.SmartGetHashCode` over the sequential layout: XOR every complete 32-bit word of the boxed
struct, then substitute `Int32.MaxValue` when the result is zero. A `Vector` component contributes
its binary32 bits and a `Color` its packed value.

So all four all-default values answer **2147483647** — the zero case — and the XOR is asserted word
by word for a four-word layout and an eight-word one.

## Recorded deviations

- **Every field copies on the way in.** XNA's `Vector3` and `Color` are structs, so
  `new VertexPositionColor(position, colour)` copies them; Ruby's are objects, so the setters `dup`.
  Mutating the caller's vector afterwards leaves the vertex unchanged, which is asserted.
- **`Equals(object)` is exact-typed**, from the IL's `obj.GetType() != GetType()` — a
  `VertexPositionTexture` never equals a `VertexPositionColor`, even with matching values.
- **The helper module lives in `CNA::Runtime`, not the XNA namespace.** A helper module inside
  `Microsoft::Xna::Framework` is an `INTERNAL_TYPE_LEAK`, which the verifier measures and which this
  binding has got wrong before.

## What this does not add

No `VertexBuffer`, `IndexBuffer`, `Effect` or `BasicEffect`; no `GraphicsDevice.SetVertexBuffer` and
no draw call. A vertex struct describes a layout; nothing here submits one.
