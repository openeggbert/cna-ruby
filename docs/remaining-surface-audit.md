# The remaining surface, classified member by member

**Measured 2026-09-04 at Foundation 103**, against the strict report
(`docs/generated/api-compat-report.json`), the pinned XNA IL, the pinned mscorlib and the qualified
CNA C ABI 0.21.0 artifacts. 237 target types, **234 complete**, 3 partial, 20 missing.

Every entry below is one of the classifications the session's stop condition admits, and each names
the evidence rather than a judgement. Nothing here is deferred for being large.

## The three partial types — eleven members, two upstream defects

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

### The third partial type — `Media.Song`, three members, a different upstream defect

| Member | Classification | Why |
| --- | --- | --- |
| `Media.Song::Album` | `BLOCKED_UPSTREAM_CNA` | no `cna_song_get_album` exists |
| `Media.Song::Artist` | `BLOCKED_UPSTREAM_CNA` | no `cna_song_get_artist` exists |
| `Media.Song::Genre` | `BLOCKED_UPSTREAM_CNA` | no `cna_song_get_genre` exists |

This is a gap rather than a design: every **reverse** navigation is exported and works —
`cna_album_get_songs`, `cna_artist_get_songs`, `cna_artist_get_albums`, `cna_genre_get_songs`,
`cna_genre_get_albums` and `cna_playlist_get_songs` — so CNA models the graph, just not from the
song outwards. Nineteen `cna_song_*` routes are bound and every other member of the type has one.

`MISSING_MEMBER` is therefore **11**, and there is no twelfth.

## The 20 missing types

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

### 17 built at Foundation 103 — the `Media` namespace

`MediaLibrary`, `MediaPlayer`, `MediaQueue`, `Song`, `SongCollection`, `Album`, `AlbumCollection`,
`Artist`, `ArtistCollection`, `Genre`, `GenreCollection`, `Playlist`, `PlaylistCollection`,
`Picture`, `PictureAlbum`, `PictureCollection`, `PictureAlbumCollection` — 182 identities, over 167
CNA routes each with a production call site, `ABI_MISMATCHES` 0 against both admitted header roots.
Sixteen are complete; `Song` is partial on the three members recorded above.

**Measured end to end on the `HEADLESS` artifact**, not merely projected: 35 real pictures with
names, dimensions, albums, image bytes and thumbnails; a root picture album with three sub-albums,
each naming the root back; the player's state, volume clamping, mute, queue and
`GetVisualizationData` filling both 256-element collections in place; and library disposal, after
which every member refuses. The music collections are empty on this host, which the header calls an
ordinary result rather than a failure, so `test/test_media.rb` asserts their shape and skips the
population assertions with a message naming what it gave up.

`MediaPlayer` is a static XNA class — `abstract sealed` in the CLR — and CNA's routes take the
**Game handle** rather than a player handle, which is the same shape: one player per process,
reached through the game. It projects to a Ruby class whose `new` is private, because a module
would be a `TYPE_KIND_MISMATCH` against the reference contract. Its two events are process-global
`_ext` subscriptions because XNA's own raisers are private, and they are the second and third
static events in the selected surface after `Storage.StorageDevice::DeviceChanged`.

**One measured C deviation.** CNA answers a picture's `Date` in 100-nanosecond ticks from the Unix
epoch rather than in seconds — a factor of 10^7 — which was found by comparing the answer against
the file's own mtime rather than by reading the header.

## What this leaves

| Classification | Types | Members |
| --- | ---: | ---: |
| `BLOCKED_UPSTREAM_CNA` (the adapter defect) | 3 | 8 partial members |
| `BCL_PROJECTION_SCOPE` (`System.ComponentModel`) | 13 | — |
| built at Foundation 103 — `Media` | 17 | 182, of which 3 are `BLOCKED_UPSTREAM_CNA` |
| locally actionable — `ContentReader` | 4 | 30, behind one `System.IO.BinaryReader` decision |
