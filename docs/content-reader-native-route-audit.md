# `ContentReader`: CNA exports thirty-one routes for it, and none is bound

**Measured 2026-09-04 at Foundation 104**, against the qualified `cna-c-abi-0.21.0` headers and the
pinned `Microsoft.Xna.Framework.dll` IL (SHA-256 `38e7093f…`).

This project's standing rule is that a CNA route supporting the exact XNA behaviour is bound and
qualified, and that a blocker is recorded only when it is measured. The `ContentReader` family is
the first case where the measurement points the other way: CNA exports a complete content-reader
surface, the behaviour matches, and **binding it is still impossible**, for a reason that has
nothing to do with the reader.

## What CNA exports

`CNA/C/content_readers.h` declares thirty-one `cna_content_reader_*` and
`cna_content_type_reader*` routes. The ones that would answer for an XNA member are:

| route | XNA member |
| --- | --- |
| `cna_content_reader_create` | `ContentReader.Create` |
| `cna_content_reader_get_content_manager` | `get_ContentManager` |
| `cna_content_reader_get_asset_name_size` / `_copy_asset_name` | `get_AssetName` |
| `cna_content_reader_read_matrix` | `ReadMatrix` |
| `cna_content_reader_read_quaternion` | `ReadQuaternion` |
| `cna_content_reader_read_vector2` / `_vector3` / `_vector4` | `ReadVector2` / `3` / `4` |
| `cna_content_reader_read_color` | `ReadColor` |
| `cna_content_reader_read_bytes_exact` | every fixed-width `BinaryReader` read |
| `cna_content_reader_destroy` | `Dispose` |

Beside them, `cna_content_type_reader_manager_register` and
`cna_content_manager_load_foreign_ext` are a real extension point: a caller supplies a create/read/
destroy table under a canonical reader name, and a compiled asset naming that reader reaches it.

## The one measurement that blocks all of it

`cna_content_reader_create` takes a **`CNA_StorageStreamHandle`**:

```c
CNA_StorageStreamHandle stream;   /* CNA_ContentReaderCreateInfo, content_readers.h */
```

The whole ABI produces a `CNA_StorageStreamHandle` from exactly two routes, both in `storage.h`:
`cna_storage_container_open_file` and `cna_storage_container_create_file`. Both require a
`CNA_StorageContainerHandle`, which comes from `cna_storage_device_open_container` — the *save-game*
device.

An XNA `ContentReader` reads a **title** asset. `TitleContainer.OpenStream` is the source, and
`cna_title_container_read_ext` — the only title route in the ABI — answers **bytes into a
caller-supplied buffer**, not a stream handle:

```c
CNA_C_API CNA_Result cna_title_container_read_ext(
    CNA_Handle game, CNA_StringView name, uint8_t* destination, uint64_t capacity,
    uint64_t* out_bytes);
```

So there is no route by which a title asset becomes a `CNA_StorageStreamHandle`, and therefore no
route by which a native `ContentReader` can be pointed at the asset an XNA `ContentReader` reads.
Writing the asset's bytes into a storage container first would put a title asset into the player's
save-game area to read it back, which is not the same operation and is not one this binding will
perform.

## Why that is not a gap in the projection

Every member of `ContentReader` is derivable from the pinned IL and from `BinaryReader`, and this
binding already projects the stream those reads run over:

- `ReadVector2` is two `ReadSingle`s, `ReadVector3` three, `ReadVector4` and `ReadQuaternion` four,
  `ReadMatrix` sixteen in row order, and `ReadColor` one `ReadUInt32` into `Color.PackedValue`.
  Those are the IL's own call sequences, not approximations of them.
- `ReadSingle` and `ReadDouble` **override** the base to read an unsigned integer and reinterpret
  its bits; `test_content_reader.rb` asserts the two paths agree byte for byte rather than assuming
  a little-endian host.
- The object protocol — the type manifest, the one-based type identifier, the shared-resource
  fixups, the external-reference path and `InvokeReader`'s four rules — is pure managed logic in
  XNA too. There is no native anything to bind.

`docs/generated/xna-il-inventory.json` records `ContentReader` as native-reachable through exactly
two methods, `Create` and `PrepareStream`, and what they reach is the BCL's own LZX decompression
for a compressed container. This projection refuses a compressed container by name rather than
pretending to decompress one, so even that reachability is not a dependency.

## The one thing that is genuinely replaced

XNA resolves a reader-type name out of the `.xnb` with `Type.GetType` and constructs it with
`Activator.CreateInstance`. Ruby has no CLR type resolver, so that single step is replaced by
`CNA::Runtime::ContentTypeReaderRegistry` — a name, a factory and a process-wide table, which is the
same substitution CNA's own `cna_content_type_reader_manager_register` makes. Everything after the
resolution is the IL's: the three caches, their keys, the duplicate rule, the instance sharing and
the rollback.

## Conclusion

`BLOCKED_UPSTREAM_CNA` would be the wrong classification, because nothing about the family is
blocked: all four types are **complete** and the whole protocol runs against a compiled asset. What
is recorded here is narrower and is a route decision rather than a member one — no
`cna_content_reader_*` route has a production call site, so under this project's manifest rule none
of them is bound, and the bound-function count is unchanged at 757.
