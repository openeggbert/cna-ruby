# `Graphics.VertexDeclaration` and `Graphics.IVertexType`

2 types, 6 Ruby member identities, both complete.

## The audit, which had two halves

`VertexDeclaration` is the only dependency-complete candidate this frontier has ever carried with
**two** blockers:

    blockers: ["NATIVE_RUNTIME", "INTERFACE_PRODUCER_MISSING"]
    nativeReachableMethods: ["Bind", "Unbind"]
    producerlessInterfaces: ["Microsoft.Xna.Framework.Graphics.IVertexType"]

Both name members the pinned contract never selects.

- `Bind` and `Unbind` are `assembly` and reach `DeclarationManager::CreateBinding` /
  `ReleaseBinding`. Neither is in `xna40-windows-runtime-contract.json`.
- The only caller of `IVertexType::get_VertexDeclaration` is the `assembly` **static** `FromType`,
  which builds a declaration from a vertex struct type through reflection. Also not in the contract.

The contract is five members: `.ctor(VertexElement[])`, `.ctor(Int32, VertexElement[])`,
`VertexStride`, `GetVertexElements` and `Dispose(Boolean)`. Every one is managed.

That makes this the **tenth** deferral retired for naming something outside the type's own public
surface, and the one that emptied `INTERFACE_PRODUCER_MISSING` off the dependency-complete list.

## What the IL says

    public VertexDeclaration(params VertexElement[] elements) {
        if (elements == null || elements.Length == 0)
            throw new ArgumentNullException("elements", FrameworkResources.NullNotAllowed);
        _elements = (VertexElement[])elements.Clone();
        _vertexStride = VertexElementValidator.GetVertexStride(_elements);
        VertexElementValidator.Validate(_vertexStride, _elements);
    }

The two-argument form is the same with the stride supplied rather than computed. Two details a
paraphrase loses, and both are asserted:

- an **empty** array is an `ArgumentNullException`, not an `ArgumentException` — the IL's `ldlen;
  brtrue` branch falls into the same throw as the null one;
- the elements are cloned on the way **in** and again on the way **out**, so neither the caller's
  array nor the one `GetVertexElements` returns is the declaration's own. XNA's `VertexElement` is a
  struct and `Array.Clone` copies it; Ruby's is an object, so both copies are element-wise.

`params` means `new VertexDeclaration(a, b)` and `new VertexDeclaration(array)` both compile in C#,
so both are accepted here, and the two overloads collapse on whether the first argument is the
stride. No `OVERLOAD_MAPPING_MISMATCH` entry names this type.

`Dispose(bool)` is `Unbind(); base.Dispose(disposing)`. Nothing binds here, so the base contract is
the whole of it and the member is selected rather than reimplemented — the same conclusion the
`GraphicsResource` milestone reached for `Texture2D` and `SpriteBatch`.

## `GetVertexStride`, and its cross-check

    max over the elements of (Offset + GetTypeSize(Format)), starting at zero

A **maximum**, not a sum: elements may be declared in any order, and holes between them are kept.
`GetTypeSize` is one `switch` over the twelve declared formats — 4, 8, 12, 16, 4, 4, 4, 8, 4, 8, 4,
8 — with `0` for anything else, which Ruby's enum projection makes unreachable.

Every stride, and all twelve format sizes, are asserted equal to CNA's own
`cna_vertex_declaration_create` + `cna_vertex_declaration_get_stride`. Those routes take **no device
and no game**, so the whole cross-check runs headless. Both authorities agree on every case,
including the out-of-order one where the *earlier* element sets the stride.

## `Validate`, in the IL's order

1. `vertexStride <= 0` → `ArgumentOutOfRangeException("vertexStride")`
2. `(vertexStride & 3) != 0` → `ArgumentException(VertexElementOffsetNotMultipleFour)`
3. per element: `usage < 0 || usage > 12` → `ArgumentException(VertexElementBadUsage)`
4. `offset < 0 || offset + size > vertexStride` → `ArgumentException(VertexElementOutsideStride)`
5. `(offset & 3) != 0` → `ArgumentException(VertexElementOffsetNotMultipleFour)`
6. against every **earlier** element: same usage *and* same usage index →
   `ArgumentException(DuplicateVertexElement)`
7. against an occupancy map of the stride: any byte already claimed →
   `ArgumentException(VertexElementsOverlap)`, naming both elements

Order matters and is asserted: an offset of 2 in a stride of 4 reaches rule 4, and the same offset
in a stride of 8 reaches rule 5.

Rule 3 is **unreachable from Ruby**. `VertexElementUsage` is a projected enum that refuses anything
outside its thirteen values, so no element carrying an out-of-range usage can be constructed. That
is recorded rather than reproduced, exactly as the state objects record their unvalidated setters.

## `IVertexType`, and why nothing conforms to it

Building the declaration uncovered the interface, and the frontier **selected** it — no blocker at
all, one member. It is projected as an abstract contract module whose reader raises
`NotImplementedError`, like `IEffectFog` and the rest.

Nothing in this binding conforms to it, and that is deliberate: XNA's implementers are the vertex
structs (`VertexPositionColor` and its three siblings), which this milestone does not build. A
completed interface is not a provider — Foundation 40's rule — and the frontier confirmed it by
listing those four structs as the first **consumable** candidates it has carried since Foundation
32, with `SELECTED_NEXT` naming `VertexPositionColor`.

## What this does not add

No `VertexBuffer`, `IndexBuffer`, `DeclarationManager` or vertex struct; no
`GraphicsDevice.SetVertexBuffer` and no draw call. `cna_vertex_declaration_create_with_stride`,
`create_empty`, `copy_type_name` and `get_type_name_byte_count` stay unbound: XNA computes nothing
in the explicit-stride case, declares no empty declaration, and has no type-name identity on this
type at all.
