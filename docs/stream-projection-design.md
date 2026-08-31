# `System.IO.Stream` — the projection derivation

`NEXT.md` named `System.IO.Stream` the highest-value remaining BCL decision: it blocks
`TitleContainer` outright and is half of `ContentManager`. The register's standing rule is
**project what the XNA surface can actually reach**, and this file is that rule applied — the
measurement first, then the reach, then the producer audit, then what the projection has to be.

Nothing here is projected yet. This is the derivation the implementation is built from.

## 1. The type is measured, not remembered

`System.IO.Stream` is the fourth family in `docs/generated/bcl-inventory.json`, read from the pinned
Microsoft .NET Framework 4.0 mscorlib (`5634668d…`) by `tools/api_compat/build_bcl_inventory.rb`.
The measurement:

```
class System.IO.Stream : System.MarshalByRefObject, System.IDisposable   abstract, not sealed
```

| group | members |
| --- | --- |
| state properties | `CanRead`, `CanSeek`, `CanWrite`, `CanTimeout` (get); `Length` (get); `Position` (get/set) |
| timeout properties | `ReadTimeout`, `WriteTimeout` (get/set) — both throw on the base |
| reading | `Read(Byte[], Int32, Int32) -> Int32`, `ReadByte() -> Int32` |
| writing | `Write(Byte[], Int32, Int32)`, `WriteByte(Byte)`, `Flush()`, `SetLength(Int64)` |
| positioning | `Seek(Int64, SeekOrigin) -> Int64` |
| copying | `CopyTo(Stream)`, `CopyTo(Stream, Int32)` |
| lifetime | `Close()`, `Dispose()`, protected `Dispose(Boolean)` |
| asynchronous | `BeginRead`, `EndRead`, `BeginWrite`, `EndWrite` |
| static | `Null` field, `Synchronized(Stream) -> Stream` |
| protected plumbing | `CreateWaitHandle()`, `ObjectInvariant()`, protected `.ctor()` |

Adding the family also grew the derived exception closure by one — `System.ObjectDisposedException`,
which this family throws and which the previous three did not reach.

## 2. What the XNA surface can actually reach

Seventeen members of the pinned XNA 4.0 Windows profile name a `System.IO.*` type. Nothing else
does, so this list is the whole reach.

**Stream-producing** (XNA hands one out; a consumer reads it):

| member | access |
| --- | --- |
| `TitleContainer.OpenStream(String)` | public static |
| `ContentManager.OpenStream(String)` | protected |
| `ResourceContentManager.OpenStream(String)` | protected |
| `StorageContainer.CreateFile(String)` | public |
| `StorageContainer.OpenFile(String, FileMode)` and its `FileAccess` / `FileShare` overloads | public |
| `Media.Album.GetAlbumArt()`, `Album.GetThumbnail()` | public |
| `Media.Picture.GetImage()`, `Picture.GetThumbnail()` | public |

**Stream-consuming** (XNA takes one in and reads it):

| member | access |
| --- | --- |
| `Audio.SoundEffect.FromStream(Stream)` | public static |
| `Graphics.Texture2D.FromStream(GraphicsDevice, Stream)` and the five-argument overload | public static |
| `Graphics.Texture2D.SaveAsPng(Stream, Int32, Int32)`, `SaveAsJpeg(…)` | public |
| `Media.MediaLibrary.SavePicture(String, Stream)` | public |

Three consequences follow directly.

- **Both directions are real.** A projection that only *returns* something stream-shaped is not
  enough: `SoundEffect.FromStream` and `Texture2D.FromStream` have to *consume* one, and a
  consumer will hand back whatever `TitleContainer.OpenStream` gave it.
- **The reached surface is small.** Nothing in XNA calls `BeginRead`, `Synchronized`, `CanTimeout`,
  `ReadTimeout`, `CreateWaitHandle` or `ObjectInvariant`. They exist on the CLR base; no XNA member
  reaches them, and a *consumer* of a stream XNA produced reaches only what a stream reader needs.
- **`System.IO` brings three enums and two exception identities with it.** `SeekOrigin` is named by
  `Seek`; `FileMode`, `FileAccess` and `FileShare` are named by `StorageContainer.OpenFile`;
  `FileNotFoundException` and `DirectoryNotFoundException` are named by `TitleContainer.OpenStream`'s
  own IL. Each is a separate, smaller decision and none is settled here.

## 3. Producer audit — the part `NEXT.md` recorded as not done

> `storage.h` exposes container routes that may or may not be the right producer; that has **not**
> been audited.

It is audited now, against the current 4054-route ABI, and the answer is that there are **two
different producers and they are not interchangeable**.

### `storage.h` — a real native stream, but not for title content

`storage.h` has a complete stream surface over `CNA_StorageStreamHandle`:

```
cna_storage_stream_read / write / seek / get_position / get_length / set_length
cna_storage_stream_get_can_read / get_can_write / get_can_seek / flush / close
```

That is very close to the reached `Stream` surface, member for member. But every route that
*produces* one of those handles — `cna_storage_container_create_file`,
`cna_storage_container_open_file`, `…_open_file_access`, `…_open_file_share` — takes a
`CNA_StorageContainerHandle`, which comes from `cna_storage_container_open(device, …)`, which comes
from a storage-device selector. That is XNA's **`StorageContainer`**, the save-game API. It is the
right producer for `StorageContainer.OpenFile`/`CreateFile` and the wrong one for
`TitleContainer.OpenStream`, which reads read-only content shipped beside the title.

### `runtime.h` — the title producer, and it hands back bytes, not a stream

The title routes are `cna_title_location_get_path_size` / `copy_path` / `set_path_ext`, and:

```c
CNA_Result cna_title_container_read_ext(
    CNA_Handle game, CNA_StringView name,
    uint8_t* destination, uint64_t capacity, uint64_t* out_bytes);
```

whose own documentation states the narrowing rather than hiding it:

> The canonical operation hands back an open stream. This ABI has no stream handle for title
> content, and a title asset is read to use it, so the count/copy pair delivers the **whole file**
> instead. That is a deliberate narrowing: incremental reads over a title stream are not available.

So `TitleContainer.OpenStream` has a truthful producer that delivers **all the bytes at once**. This
is a fact about the ABI, confirmed by exhaustive search: the only routes in the whole 4054-route
surface that yield a `CNA_StorageStreamHandle` are the four `storage_container_*` file routes.

`cna_title_container_read_ext` also settles the missing-file contract: `CNA_RESULT_IO` "when the file
cannot be opened", chosen deliberately so a missing file does not surface as an internal failure.

### What that means for the projection

`Stream` needs at least two backings, and they differ in where the bytes live, not in what the
surface promises:

| backing | bytes | `CanRead` | `CanWrite` | `CanSeek` | producer |
| --- | --- | --- | --- | --- | --- |
| in-memory | one owned Ruby byte string | true | false | true | `TitleContainer.OpenStream`, and anything else CNA answers whole |
| native storage stream | CNA-owned, incremental | route | route | route | `StorageContainer.OpenFile`/`CreateFile` |

The in-memory backing is a **recorded deviation**, not a simplification: XNA's
`TitleContainer.OpenStream` returns a `FileStream` that reads lazily, and this reads eagerly. Every
observable of the reached surface — `Length`, `Position`, `Read`, `Seek`, `CanWrite = false`,
`Close` — is identical; what differs is *when* the I/O happens and therefore when an I/O failure
is raised. That belongs in the deviation register, and the alternative — opening the file with
Ruby's own `File` — is worse, because it would bypass the runtime that owns title location and
would answer a different path than `cna_title_location_*` reports.

## 4. `TitleContainer.OpenStream`, derived from its own IL

`Microsoft.Xna.Framework.dll`, `Microsoft.Xna.Framework.TitleContainer` — a public abstract sealed
(static) class over `System.Object` with one public member, one private static field and three
non-public statics. `OpenStream` is 213 bytes and every branch is derivable:

```
if (String.IsNullOrEmpty(name)) throw new ArgumentNullException("name");
name = GetCleanPath(name);
if (IsCleanPathAbsolute(name)) throw new ArgumentException(InvalidTitleContainerName);
try   { new Uri(name.Replace('\\', '/'), UriKind.Relative); }        // validation only; result popped
catch (Exception e) { throw new ArgumentException(InvalidTitleContainerName, e); }
try   { return File.OpenRead(Path.Combine(TitleLocation.Path, name)); }
catch (Exception e)
{
    if (e is FileNotFoundException || e is DirectoryNotFoundException || e is ArgumentException)
        throw new FileNotFoundException(Format(OpenStreamNotFound, name));
    throw new InvalidOperationException(Format(OpenStreamError, name), e);
}
```

Two details a summary would lose. The `Uri` is constructed and **immediately discarded** — it is a
validation call, not a value. And the `catch` maps three different CLR exception types onto one
`FileNotFoundException`, so a directory that does not exist and a name the platform rejects are
reported identically to a file that is simply absent.

### `GetCleanPath(string path)` — exact

```
path = path.Replace('/', '\\');
path = path.Replace("\\.\\", "\\");
while (path.StartsWith(".\\"))  path = path.Substring(2);
while (path.EndsWith("\\."))    path = path.Length > 2 ? path.Substring(0, path.Length - 2) : "\\";
for (int i = 1; i < path.Length; i = path.IndexOf("\\..\\", i))
{
    if (i < 0) break;
    i = CollapseParentDirectory(ref path, i, 4);
}
if (path.EndsWith("\\.."))
{
    int i = path.Length - 3;
    if (i > 0) CollapseParentDirectory(ref path, i, 3);
}
if (path == ".") path = String.Empty;
return path;
```

Note the loop shape: the index starts at **1**, the `IndexOf` is evaluated as the loop's *increment*,
and the `< 0` test happens at the top of the body — so a `"\\..\\"` at index 0 is never collapsed,
which is what makes a leading `..\` survive into `IsCleanPathAbsolute` and be rejected there.

### `CollapseParentDirectory(ref string path, int position, int removeLength)` — exact

```
int start = path.LastIndexOf('\\', position - 1) + 1;
path = path.Remove(start, position - start + removeLength);
return Math.Max(start - 1, 1);
```

### `IsCleanPathAbsolute(string path)` — exact

```
if (path.IndexOfAny(badCharacters) >= 0) return true;
if (path.StartsWith("\\"))    return true;
if (path.StartsWith("..\\"))  return true;
if (path.Contains("\\..\\"))  return true;
if (path.EndsWith("\\.."))    return true;
if (path == "..")             return true;
return false;
```

`badCharacters` is a seven-element `char[]` initialised from a fourteen-byte static blob, read
directly out of the disassembly:

```
3A 00 2A 00 3F 00 22 00 3C 00 3E 00 7C 00     ->   : * ? " < > |
```

Note what is **not** in it: `\` and `/` are not bad characters, and neither is `:`-less drive
syntax — the absoluteness test is the leading-backslash rule plus the parent-directory rules, and
the bad-character list exists to reject Windows path metacharacters. The method is named
"IsCleanPathAbsolute" but answers true for a *rejectable* path, which is why `OpenStream` raises
`ArgumentException` on it rather than treating it as a rooted path.

## 5. Ruby mapping questions this derivation settles

- **Not Ruby `IO`, and not `StringIO`.** Ownership, close semantics and the error vocabulary all
  differ, and the storage backing is a CNA handle with an owner thread and an explicit destroy.
  A dedicated `CNA::Runtime::Stream` in the BCL projection register is the shape the existing rules
  already imply — the same place `ReadOnlyCollection`, `Collection`, `Dictionary` and `EventArgs`
  live.
- **`Close` and `Dispose` are two identities with one behaviour.** Both are public, parameterless and
  measured; Ruby can carry both names, and the disposal-collapse rule that removed `IDisposable`
  does not remove a type's own public `Dispose`.
- **`Read(Byte[], Int32, Int32)` needs the `System.Byte[]` decision**, which `Microphone` also waits
  on. It is the one genuinely open sub-decision and is made separately.
- **The four asynchronous members and `Synchronized` are out of reach**, so they are not projected;
  `CanTimeout`/`ReadTimeout`/`WriteTimeout` are reachable only as properties whose CLR base throws,
  which is a behaviour rather than a runtime.

## 6. `System.Byte[]` — the sub-decision `Stream.Read` forces

`Stream.Read(Byte[], Int32, Int32)` writes into the **caller's** buffer, so the projection cannot be
settled without deciding what a CLR `byte[]` is in Ruby. Measured reach across the selected XNA
profile: `System.Byte[]` appears in eight signatures over five public members —
`SoundEffect..ctor` (both overloads), `Microphone.GetData`,
`DynamicSoundEffectInstance.SubmitBuffer`, `Effect..ctor` and `MediaLibrary.SavePicture` — plus
`Stream.Read`/`Write` reached through a produced stream.

**It projects to a Ruby `String` in `Encoding::BINARY`.** The candidates and why the other loses:

| candidate | verdict |
| --- | --- |
| binary `String` | Ruby's own byte buffer. Mutable in place (`setbyte`, equal-length `[]=`), `bytesize` is the CLR `Length`, and it is already what every native boundary in this binding produces and consumes — `pack`/`unpack`, `Fiddle::Pointer[]`, `cna_texture2d_create_from_encoded_memory`, `cna_sound_effect_create_pcm16`. |
| `Array` of Integers | needs a conversion at every native boundary, and its `length` equals the byte count only by coincidence of the element type rather than by construction. It reads like a faithful array and behaves like a slower one. |

Two CLR properties a Ruby `String` does not have, which the projection guards rather than ignores:

- **A `byte[]` cannot be resized.** `String#[]=` with a differing length silently resizes, so a
  write that would change `bytesize` is refused.
- **A `byte[]` is never frozen.** A frozen string is refused before the write rather than raising
  `FrozenError` from inside the copy.

Both are falsifiable and both get a mutation control.

## 7. `Texture2D.FromStream` already has an informal contract to reconcile

`Texture2D.FromStream` is implemented today and duck-types its second argument:
`stream.respond_to?(:read)`, then `stream.read` must return a `String`. That is a **Ruby** stream
contract, not the projected one, and it predates this decision.

When `CNA::Runtime::Stream` lands, that member becomes the first place the projection is *consumed*,
and the two contracts have to be one. The reconciliation is not a free choice: the strict verifier
measures the declared parameter type, and the repository rule is not to Ruby-ify away an XNA
identity. So the projected type is what the signature names, and accepting a bare Ruby `IO` beside
it is a separate, explicitly recorded convenience — not the contract.

