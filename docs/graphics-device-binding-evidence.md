# Foundation 86 — `GraphicsDevice`'s binding slice

Five more of the twenty-six members the device still owed: `Indices`, `SetVertexBuffer`'s two
overloads, `SetVertexBuffers` and `GetVertexBuffers`. `MISSING_MEMBER` goes **58 → 53**,
`OVERLOAD_MAPPING_MISMATCH` 27 → **24** and `TOTAL_DIAGNOSTICS` 143 → **135**. These are the members
that make the buffers built two milestones ago reachable from the device that will draw with them.

## The getters answer the objects, and the reason is the same on both sides

`get_Indices` is one `ldfld`, and `GetVertexBuffers` is `newarr` plus `Array.Copy` over a cached
array — so XNA answers **the objects the caller bound**, in a fresh array each call.

CNA agrees by construction: `cna_graphics_device_get_index_buffer` hands back a *handle*, and this
ABI has no route from a native object back to a handle. That is the rule `TextureCollection` already
records, and it means the projection must cache what it binds. It does, and the test proves both
halves — the Ruby object comes back by identity, and the native side really holds something.

## What the two `SetVertexBuffer` overloads are

Both build a `VertexBufferBinding` and forward to the internal array form, so the binding's own
constructor is what validates the offset and frequency rather than a second copy of that rule. A
**null** buffer forwards `(null, 0)`, which unbinds every stream rather than raising — measured,
because it is the kind of rule a reader assumes the other way round.

`SetVertexBuffers(null)` and `SetVertexBuffers([])` are the same unbind, and a populated array is
validated binding by binding **before any of it is applied**: a null entry is
`ArgumentException(NullNotAllowed)` and a buffer belonging to another device is
`InvalidOperationException(InvalidDevice)`. The test asserts that a refused call left the previous
binding in place, which is what "validated before applied" means.

One `cna_graphics_device_set_vertex_buffers` call carries the whole array, because that route
validates the whole array before applying any of it too — the same guarantee, once.

## Three routes deliberately not bound

`cna_graphics_device_get_vertex_buffer_count`, `cna_graphics_device_copy_vertex_buffers` and
`cna_graphics_device_get_index_buffer` are **not** in the manifest. XNA's own getters are field
reads, so nothing in `lib/` would ever call them, and a route bound for a test is dead native
surface. `test/test_graphics_device_binding.rb` reaches all three through raw Fiddle, exactly as
`test/renderer_environment.rb` does and for exactly the same reason — and that is what lets it read
the bindings back as CNA holds them, which is the only way to see that the offset and the frequency
went into the right halves of `CNA_VertexBufferBinding`.

Seven routes were bound and three were taken back out again; the manifest is at **379**.

## Mutation

Seven planted defects, seven caught: a null buffer raising instead of unbinding, the array overload
applying before validating, the foreign-device check dropped, `GetVertexBuffers` handing out its own
array, the index buffer cached without being bound, a null index buffer refused instead of clearing,
and the binding's offset written into the frequency slot. The last of those is caught only because
the test reads the bindings back from CNA rather than from the cache.

## What this milestone does not do

`GraphicsDevice` still owes twenty-six members. Nothing here draws: the five draw families,
`SetRenderTarget` and its siblings, `Present`/`Reset`/`Dispose`/`GetBackBufferData`, the four
identity properties and the six events are all outstanding. A bound buffer is not a draw call.
