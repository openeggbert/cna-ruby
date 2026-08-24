# Geometry and Transform Evidence

This document records the managed-only Foundation Milestone 2 closure. The pinned XNA 4.0 Windows runtime contract is authoritative; sibling bindings are engineering evidence only.

## Pre-implementation dependency table

Counts exclude only the synthetic CLR enum storage field `value__`. `Array` counts member identities accepting a CLR array, not the number of array parameters.

| Type | Reference members | Ruby-mapped members | Initial status | Direct XNA dependencies | Ref/out | Array | Operators | Static methods | Static properties |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| Vector2 | 77 | 77 | partial 44/77 | Matrix, Quaternion | 29 | 6 | 10 | 52 | 4 |
| Vector3 | 88 | 88 | missing | Matrix, Quaternion, Vector2 | 30 | 6 | 10 | 54 | 11 |
| Vector4 | 85 | 85 | missing | Matrix, Quaternion, Vector2, Vector3 | 29 | 4 | 10 | 54 | 6 |
| Quaternion | 55 | 55 | missing | Matrix, Vector3 | 16 | 0 | 8 | 32 | 1 |
| Matrix | 107 | 107 | missing | Plane, Quaternion, Vector3 | 34 | 0 | 10 | 66 | 1 |
| Plane | 30 | 30 | missing | BoundingBox, BoundingFrustum, BoundingSphere, Matrix, PlaneIntersectionType, Quaternion, Vector3, Vector4 | 8 | 0 | 2 | 6 | 0 |
| Ray | 16 | 16 | missing | BoundingBox, BoundingFrustum, BoundingSphere, Plane, Vector3 | 3 | 0 | 2 | 0 | 0 |
| BoundingBox | 33 | 33 | missing | BoundingFrustum, BoundingSphere, ContainmentType, Plane, PlaneIntersectionType, Ray, Vector3 | 9 | 1 | 2 | 5 | 0 |
| BoundingSphere | 33 | 33 | missing | BoundingBox, BoundingFrustum, ContainmentType, Matrix, Plane, PlaneIntersectionType, Ray, Vector3 | 10 | 0 | 2 | 6 | 0 |
| BoundingFrustum | 33 | 33 | missing | BoundingBox, BoundingSphere, ContainmentType, Matrix, Plane, PlaneIntersectionType, Ray, Vector3 | 7 | 1 | 2 | 0 | 0 |
| ContainmentType | 3 | 3 | missing | none | 0 | 0 | 0 | 0 | 0 |
| PlaneIntersectionType | 3 | 3 | missing | none | 0 | 0 | 0 | 0 | 0 |

The two enums are dependency-complete additions. No unrelated enum or native ABI function is part of this closure.

## Qualification record

All twelve rows above are complete in the generated target contract. Each has zero local missing members, overload mismatches, property mismatches, signature/parameter/return mismatches, operator mismatches, and language-mapping mismatches. `BoundingFrustum` is an XNA reference class; the other nine geometry records are XNA structs, and the two dependencies are enums.

### Value and binary32 policy

The structs use mutable Ruby value-object classes with no handle or public backing Array. Constructors, struct-valued getters/setters, returned corners, and destination-array writes copy values. `dup` and `clone` create independent state. Ruby assignment remains the already-documented CLR assignment-copy limitation.

Every public Single is narrowed through `CNA::Runtime::Numeric`. Arithmetic helpers narrow operands and intermediate operation results in XNA evaluation order. The retained bit corpus covers signed zero, subnormal/overflow behavior, negative quiet NaN from invalid Single arithmetic, infinities, zero normalization, singular inversion, and non-finite intersection cases. MRI cannot retain a signed binary32 NaN by unpacking it directly, so the helper carries the equivalent signed binary64 NaN and the bit corpus verifies its binary32 projection.

### Transform conventions

- Vectors are row vectors. `Vector3.Transform(v, a * b)` applies `a`, then `b`.
- Matrix translation is `M41`, `M42`, `M43`; `Forward` is the negated third row and XNA forward is negative Z.
- Matrix multiplication is ordinary row-by-column multiplication in that convention.
- Perspective matrices use XNA's right-handed view convention and Direct3D-style depth coefficients. Invalid FOV and near/far arguments raise the mapped Ruby range error; no clamping is added.
- A singular inverse returns non-finite components (the retained XNA observation is all negative quiet NaNs), not a Ruby exception.
- Quaternion multiplication and `Concatenate` preserve XNA order: `Concatenate(first, second) == second * first`. Slerp uses shortest-path sign correction and the near-parallel fallback.

### Ref/out and arrays

`ref` inputs are ordinary typed Ruby values. One `out` becomes the return value; multiple outputs form an ordered Array after any leading CLR return. Thus `Matrix#Decompose` returns `[Boolean, Vector3, Quaternion, Vector3]`. The static contract and generated RBS retain all original CLR identities even when two identities share one Ruby call shape.

Vector2/3/4 transforms implement both caller-owned destination forms. Arrays, indices, length, capacity, and element type are checked; values are copied. Writes proceed forward, matching XNA overlap behavior. Negative length is a no-op, while an invalid index raises when a positive length requires access.

### Plane, ray, and bounds

Plane normalization uses XNA's tolerance and degenerate non-finite behavior. Matrix plane transforms use the inverse matrix; quaternion plane transforms rotate only the normal. Ray intersections map `Nullable<Single>` to `Float?`, with `nil` for no forward hit and `0.0` for an origin already inside.

Bounding volumes implement creation, containment, plane classification, nullable ray hits, merging, and non-uniform sphere scaling. Frustum planes are extracted and normalized in XNA matrix order. Its eight corners are retained in exact observable order: near top-left, near top-right, near bottom-right, near bottom-left, then the corresponding far corners. Convex volume intersection uses a private GJK helper that is not exposed under the public XNA namespace.

### Evidence totals

- structural target: 33 types / 903 members; all geometry rows locally zero
- complete target types: 24; partial target types: 9; missing reference types: 224
- behavior corpus: 88 PURE_XNA_DERIVED observations / 88 assertions / 0 failures
- dedicated geometry tests: Vector2, Vector3, Vector4, Quaternion, Matrix, Plane, Ray, BoundingBox, BoundingSphere, BoundingFrustum
- generated geometry RBS: 12 types / 481 constructor and method identities
- RBS validation: pass; RBS/runtime/identity consistency: 643 assertions
- native ABI: unchanged at 30 functions, 90 signature measurements, 158 C and 158 Ruby layout measurements, 2 callbacks, 12 constants, zero missing symbols/mismatches
