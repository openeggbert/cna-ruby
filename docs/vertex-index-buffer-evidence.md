# Foundation 81 — the vertex and index buffers

Five types, forty-three identities, and the first geometry storage this binding has. The strict
scoreboard goes **186 complete / 69 missing to 191 / 64**, `TARGET_MEMBERS` 2270 to 2313 and
`TOTAL_DIAGNOSTICS` 162 to **157**. The partial register does not move: it is still
`GraphicsDeviceManager` and `GraphicsDevice`, and `MISSING_MEMBER` is unchanged at 65, because every
one of the five types is complete on arrival.

| Type | Identities | Shape |
| --- | --- | --- |
| `VertexBuffer` | 12 | `GraphicsResource`, two public ctors, `SetData`/`GetData` ×3 each |
| `DynamicVertexBuffer` | 6 | derives, adds `IsContentLost`, `ContentLost` and two `SetData` |
| `IndexBuffer` | 12 | `GraphicsResource`, two public ctors, `SetData`/`GetData` ×3 each |
| `DynamicIndexBuffer` | 6 | derives, the same additions |
| `VertexBufferBinding` | 7 | sealed struct, three ctors, `op_Implicit`, three getters |

## The declaration a buffer has to own

XNA's `VertexBuffer` holds a `VertexDeclaration`, and CNA's `cna_vertex_buffer_create` wants a
`CNA_VertexDeclarationHandle`. This binding's `VertexDeclaration` has neither: it was built as a
**managed-only** type — its whole projected surface is `VertexStride` and `GetVertexElements`, and
it never allocated a native object, because nothing needed one.

So the buffer builds one. `create_native_declaration` packs the managed declaration's elements into
the four-int record `CNA_VertexElement` is, calls `cna_vertex_declaration_create_with_stride` with
the declaration's **own** stride, and keeps the handle; `Dispose` destroys it after the buffer. That
is why `cna_vertex_declaration_create_with_stride` is bound now and was not before — the vertex
declaration milestone used it as a stride cross-check with a raw Fiddle call in its test, and it is
production surface only once something creates a buffer.

The alternative — giving `VertexDeclaration` a native handle of its own — was rejected: it would
change a complete type's disposal semantics to serve a consumer, and XNA's declaration is shareable
between buffers while a CNA handle is owned by whoever destroys it. One buffer, one declaration, one
owner.

## The two size rules, read out of `CopyData` rather than invented

All five `SetData`/`GetData` overloads forward to `VertexBuffer::CopyData`, and its IL carries
exactly two rules:

```
elementSize = sizeof(T)
if vertexStride != 0:
    gap = vertexStride - elementSize
    if gap < 0: throw ArgumentOutOfRangeException("vertexStride", VertexStrideTooSmall)
else:
    gap = 0
span = elementCount * elementSize + max(elementCount - 1, 0) * gap
if offsetInBytes + span > _size: throw InvalidOperationException(ResourceDataMustBeCorrectSize)
```

A zero stride is **tightly packed**, not "the declaration's stride": the gap is zero and the copy
touches `elementCount * sizeof(T)` bytes. `IndexBuffer::CopyData` has the simpler half of the same
rule — `sizeof(T) * elementCount + offsetInBytes` must fit — because an index buffer has no stride.

Both were **wrong in the first cut of this milestone** and were corrected before it landed. The
projection had invented a rule the IL does not have (`elementCount * sizeof(T)` must divide by the
stride, raising `ArgumentError`) and had substituted the declaration's stride for a `String`'s zero
— which under the real rule would compute a span of `1 + (count - 1) * 16` and refuse a byte array
that XNA copies without complaint. What found it was writing a test for the element types the code
already claimed to carry.

The index overloads had a second defect from the same source: `(offsetInBytes, data, startIndex,
elementCount)` and `(data, startIndex, elementCount, options)` are both four arguments, and the
dispatch was telling them apart by **counting**, so a static four-argument call read its
`elementCount` as a `SetDataOptions` and raised a bit-mask `RangeError`. The CLR tells them apart by
the first parameter's type, and so does this projection now. `SetDataOptions` is also refused
outright on a static buffer, which has no such overload.

## `SetDataOptions` and the route the two-version admission chose

`DynamicVertexBuffer` adds the two option-bearing `SetData` overloads. CNA has exactly one raw route
that carries both a byte offset and the options — `cna_vertex_buffer_set_data_raw_at_with_options` —
and it exists **only in 0.21.0**. Binding it would make the retired 0.7.0 headers report a missing
symbol and end their admission, and a buffer milestone does not get to retire an admitted ABI
version on its own.

The typed `cna_vertex_buffer_set_data` is declared by both versions and its `CNA_VertexBufferTransfer`
carries the options. It costs the element type: the transfer names one of CNA's seven built-in vertex
layouts, so the option-bearing overloads accept only the four this binding projects a type for.

DEVIATION, recorded: XNA accepts any struct there. `CNA::Runtime::NotSupportedError` names the
reason, the inherited overloads keep the raw route and every element type, and the typed route
replaces the whole buffer — so an option-bearing call with a non-zero `offsetInBytes` is refused
rather than silently dropping the offset.

`cna_index_buffer_set_data_at` needs no such choice: both versions declare it and its transfer has
always carried the options. It does refuse a non-`None` option — "a windowed upload preserves the
rest" — so a zero offset, which is XNA's whole-contents replacement, dispatches to
`cna_index_buffer_set_data` instead. Both routes are production; neither is a workaround.

## `ContentLost` is subscribable and never fires

Both dynamic buffers declare the event, and `cna_vertex_buffer_subscribe_content_lost` is
deliberately **unbound**. `CNA_VertexBufferInfo::is_content_lost` is documented false on every
renderer family that cannot lose a device, which is all three qualified artifacts, and it measures
false on each. A bound callback would be native surface with nothing to deliver, which this project
does not carry. `IsContentLost` reads the flag for real on every call.

## `VertexBufferBinding` is CNA's own

The three values a consumer reads are not assembled in Ruby: `cna_vertex_buffer_binding_init` fills
`CNA_VertexBufferBinding` and the getters read it back, so what a consumer sees is what the C ABI
holds. `op_Implicit` is the one-argument constructor, which is what the IL's implicit conversion is.

It is the only value type in this projection that declares **no** `Equals` and no `GetHashCode` —
XNA's struct inherits `ValueType`'s, whose hash the CLR documents as unspecified. Publishing a
`GetHashCode` identity the pinned contract never selects would be inventing one, so `hash` is
answered over the same three components equality uses and nothing is claimed about its value.

## The strided window CNA has no route for

CNA's raw routes take a `vertex_stride` and, measured at the C ABI with no Ruby in the path, accept
only the buffer's **own declaration stride**: anything else is
`The vertex stride does not match this VertexBuffer's VertexDeclaration (Parameter 'stride')`. They
address whole vertices from a vertex-aligned offset.

A tightly packed window that starts on a vertex boundary and covers whole vertices is that transfer
under a different name — `SetData<Color>(0, colours, 0, 8, 4)` over a 16-byte declaration writes the
same 32 contiguous bytes as two vertices at stride 16 — so it is passed through as one, and the
element-type test proves the `Int32` view and the `String` view see the same bytes.

MAPPING LIMITATION, recorded: a **strided** window is not. XNA's `SetData<Color>(0, colours, 0, 3,
16)` rewrites one component of every vertex and leaves the other twelve bytes of each alone; no CNA
route expresses it, and read-modify-write is not available for the `WriteOnly` buffers the pattern
exists for. It raises `CNA::Runtime::NotSupportedError` naming the stride, and the IL's own size rule
is still checked **first**, so a strided window that overruns the buffer gets XNA's
`ResourceDataMustBeCorrectSize` rather than this projection's refusal.

## Measured, not asserted

`test/test_vertex_index_buffers.rb` runs against a real device, inside `Draw`: a three-vertex
`VertexPositionColor` round trip through `SetData`/`GetData` returns every field of every vertex; a
windowed upload at a byte offset changes only the vertex it names and leaves the ones on either side
alone; `Color`, `Single`, `Int32` and `String` elements each survive a round trip at their own
element size, and the `String` view reads back the bytes the `Int32` view wrote; sixteen- and
thirty-two-bit indices both round-trip and a value above `0xFFFF` is refused for the narrow one; the
dynamic pair uploads under `Discard`; and disposal destroys the native declaration, which is proved
by the second destroy of that handle being refused.

Fourteen runs, 120 assertions, and a mutation pass beside them.

Ten planted defects, and the suite catches **nine**: a stride floor that admits a stride below
`sizeof(T)`, a span that forgets the gaps, either buffer's size rule dropped, a window that starts
inside a vertex, the index overloads told apart by counting, a static buffer accepting
`SetDataOptions`, the sixteen-bit index range check dropped, and the native declaration never
destroyed. The survivor is `VertexBufferBinding` reading its offset from the Ruby argument instead of
from the structure `cna_vertex_buffer_binding_init` filled: the two agree by construction, so the row
asserts provenance rather than a value, and only a CNA that transformed what it was given could tell
them apart.

## The frontier, and what the buffers uncovered

`Graphics.VertexBuffer` leaves `partialDependencySatisfiedCandidates` — five entries to four — where
it sat because its one unmet dependency was the partial `GraphicsDevice`, whose members it reaches
are already projected. `Graphics.ModelMeshPart` arrives on `dependencyCompleteCandidates`, 4 to 5:
the two buffers were its last unmet signature dependencies. It joins the il-only blocked list in the
same moment, 2 to 3, and is the only entry there with no unmet dependency at all, so that list's
dependency-complete subset rises 0 to 1.

`ModelMeshPart`'s blocker is `NATIVE_RUNTIME` on `Draw`, and here the word looks like it is about
the **type** rather than its producer, which most of this register's retired entries were not:
`Draw`'s IL reaches `GraphicsDevice.SetVertexBuffer`, `GraphicsDevice.set_Indices` and
`GraphicsDevice.DrawIndexedPrimitives`, none of which this binding projects. Holding vertices is not
drawing them, and this milestone does not claim to. The audit that decides it belongs to whichever
milestone takes `ModelMeshPart`, not to this one.

## Native surface

Fifteen routes bring the manifest to **349**, four constants to **133** and seven layouts to **57** —
`CNA_VertexBufferCreateInfo`, `CNA_VertexBufferInfo`, `CNA_VertexBufferTransfer`,
`CNA_VertexBufferBinding`, `CNA_IndexBufferCreateInfo`, `CNA_IndexBufferInfo` and
`CNA_IndexBufferTransfer`, every field offset compiler-checked against both admitted header roots.
`ABI_MISMATCHES=0`, `MISSING_HEADER_SYMBOLS=0`, `CROSS_VERSION_MISMATCHES=0`.

Two layout sizes were **guessed wrong and caught by the gate** rather than by a test:
`CNA_VertexBufferCreateInfo` is 32 bytes and not 24, `CNA_VertexBufferInfo` is 32 and not 40. That is
what the compiled probe is for.

Deliberately unbound: `cna_vertex_buffer_set_data_raw_at_with_options` (0.21.0 only, above),
`cna_vertex_buffer_subscribe_content_lost` and its index twin (nothing to deliver, above), and
`cna_vertex_declaration_create_empty` and `cna_vertex_declaration_copy_type_name`, which have no XNA
identity here.
