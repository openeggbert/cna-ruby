# The remaining surface, classified member by member

**Measured 2026-09-04 at Foundation 102**, against the strict report
(`docs/generated/api-compat-report.json`), the pinned XNA IL, the pinned mscorlib and the qualified
CNA C ABI 0.21.0 artifacts. 220 target types, **218 complete**, 2 partial, 37 missing.

Every entry below is one of the classifications the session's stop condition admits, and each names
the evidence rather than a judgement. Nothing here is deferred for being large.

## The two partial types — eight members, one upstream defect

| Member | Classification | Why |
| --- | --- | --- |
| `Graphics.GraphicsDevice::.ctor` | `BLOCKED_UPSTREAM_CNA` | its first parameter is a `GraphicsAdapter` |
| `Graphics.GraphicsDevice::Adapter` | `BLOCKED_UPSTREAM_CNA` | answers the adapter, which is invented hardware |
| `Graphics.GraphicsDevice::DisplayMode` | `BLOCKED_UPSTREAM_CNA` | measured identical to the adapter's fallback on every artifact |
| `GraphicsDeviceManager::FindBestDevice` | `BLOCKED_UPSTREAM_CNA` | returns `GraphicsDeviceInformation`, whose `Adapter` is one |
| `GraphicsDeviceManager::CanResetDevice` | `BLOCKED_UPSTREAM_CNA` | takes one |
| `GraphicsDeviceManager::RankDevices` | `BLOCKED_UPSTREAM_CNA` | takes a `List<GraphicsDeviceInformation>` |
| `GraphicsDeviceManager::OnPreparingDeviceSettings` | `BLOCKED_UPSTREAM_CNA` | takes `PreparingDeviceSettingsEventArgs`, which carries one |
| `GraphicsDeviceManager::PreparingDeviceSettings` | `BLOCKED_UPSTREAM_CNA` | its handler carries the same args |

**All eight trace to one measured defect.** `docs/graphics-adapter-audit-evidence.md` and
`docs/graphics-adapter-ordering-upstream-defect.md` record it: CNA's adapter list is built before
the video subsystem exists, so every adapter value is fabricated, and a second qualified artifact
with a real X11 window answers the same invented data. `Revision` and `SubSystemId` are hardcoded
zero and `display.h` documents them as such. Projecting `GraphicsAdapter` would ship a type whose
every property is a fiction, and the seven members above would carry that fiction into the device
and the manager.

`MISSING_MEMBER` is therefore **8**, and there is no ninth.

## The 37 missing types

### 3 blocked on the same adapter defect

`Graphics.GraphicsAdapter`, `GraphicsDeviceInformation`, `PreparingDeviceSettingsEventArgs` —
`BLOCKED_UPSTREAM_CNA`. The second's `Adapter` property is a `GraphicsAdapter` and the third's whole
surface is a `GraphicsDeviceInformation`, so neither can be honest while the first is not.

### 13 `BCL_PROJECTION_SCOPE` — the `Design` converters

`MathTypeConverter` and the twelve converters that derive from it. The blocker is not authority and
not CNA: it is the reach of `System.ComponentModel`.

- `MathTypeConverter` extends **`ExpandableObjectConverter`**, and its `CanConvertFrom`/`CanConvertTo`
  fall through to `TypeConverter`'s own implementations rather than answering for themselves.
- `GetProperties` returns a **`PropertyDescriptorCollection`**, and the field it answers it from is
  built by `MemberPropertyDescriptor`, `FieldPropertyDescriptor` and `PropertyPropertyDescriptor` —
  three `private` XNA classes over `System.ComponentModel.PropertyDescriptor`.
- Every member takes an **`ITypeDescriptorContext`**, and `CanConvertTo` special-cases
  **`InstanceDescriptor`**, which is what `CreateInstance` exists to feed.

That is four `System.ComponentModel` identities plus a descriptor system, none of them in the BCL
register, and the register's rule is to project what the XNA surface can reach. What a Ruby consumer
would reach here is a .NET designer-serialisation facility that has no Ruby analogue at all.

### 4 locally actionable — the `ContentReader` family

`ContentReader`, `ContentTypeReader`, ``ContentTypeReader`1`` and `ContentTypeReaderManager`. CNA
carries the routes: `cna_content_reader_create`, `_read_object_tag`, `_read_shared_resources`,
`_read_vector2`/`3`/`4`, `_read_matrix`, `_read_quaternion`, `_read_color`,
`_read_bounding_sphere`, `_read_bytes_exact`, `_get_asset_name_size`/`_copy_asset_name`,
`_get_content_manager`, `_get_platform`, `_get_version`, `_initialize_type_readers` and two
validation helpers — twenty in all.

**The decision the milestone has to make first** is `System.IO.BinaryReader`: `ContentReader`
extends it, `ReadSingle` and `ReadDouble` **override** it, and the register does not carry it. That
is the same shape of decision `System.IO.Stream` was, and it is a decision rather than a blocker.

### 17 locally actionable — the `Media` namespace

`MediaLibrary`, `MediaPlayer`, `MediaQueue`, `Song`, `SongCollection`, `Album`, `AlbumCollection`,
`Artist`, `ArtistCollection`, `Genre`, `GenreCollection`, `Playlist`, `PlaylistCollection`,
`Picture`, `PictureAlbum`, `PictureCollection`, `PictureAlbumCollection` — 196 members.

**Measured, on the `HEADLESS` artifact, with no Ruby projection in the path:**
`cna_media_library_create` succeeds against a plain `Game`; `get_songs`, `get_albums`, `get_artists`,
`get_genres`, `get_playlists`, `get_pictures` and `get_saved_pictures` all succeed; the music
collections are empty on this host and **`pictures` answers 35** — the picture family has real data
to project against. `get_media_source_type` answers 0 and the library disposes and destroys cleanly.

166 of CNA's media routes have a production call site in that surface, one per XNA member, and a
generated manifest of exactly those 166 passes the ABI gate with `ABI_MISMATCHES` 0 against both
admitted header roots. That work was generated, verified and then **reverted** rather than left in
the tree: a bound route with no call site does not stay, and the Ruby side is where the remaining
effort is.

**One recorded blocker inside it.** `Song.Album`, `Song.Artist` and `Song.Genre` have **no CNA route
at all** — the song surface is name, duration, rating, play count, track number, protection,
disposal, equality and hash, and nothing that reaches the three navigation properties. Every other
member of every one of the seventeen types has one. So the family completes with `Song` **partial**
on exactly those three, `BLOCKED_UPSTREAM_CNA`, and sixteen types complete.

`MediaPlayer` is a static XNA class and CNA's routes take the **Game handle** rather than a player
handle, which is the same shape: one player per process, reached through the game. Its two events
are process-global `_ext` subscriptions because XNA's own raisers are private.

## What this leaves

| Classification | Types | Members |
| --- | ---: | ---: |
| `BLOCKED_UPSTREAM_CNA` (the adapter defect) | 3 | 8 partial members |
| `BCL_PROJECTION_SCOPE` (`System.ComponentModel`) | 13 | — |
| locally actionable — `Media` | 17 | 196, of which 3 are `BLOCKED_UPSTREAM_CNA` |
| locally actionable — `ContentReader` | 4 | 30, behind one `System.IO.BinaryReader` decision |
