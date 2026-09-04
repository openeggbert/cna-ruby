# The remaining surface, classified member by member

**Measured 2026-09-04 at Foundation 104**, against the strict report
(`docs/generated/api-compat-report.json`), the pinned XNA IL, the pinned mscorlib and the qualified
CNA C ABI 0.21.0 artifacts. 241 target types, **239 complete**, 2 partial, 16 missing.

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
with a real X11 window answers the same invented data. **Re-measured at Foundation 104 across all
three qualified artifacts**, from `docs/generated/renderer-native-report.json`: `HEADLESS`,
`OPENGL33` and `OPENGLES3` each answer one adapter, `"Default Display"`, `\\.\DISPLAY1`, a single
800x480 mode and `refreshResult` 6 — `CNA_RESULT_NOT_SUPPORTED` — on a machine whose real display
is 1280x800. Three artifacts, three identical fictions. `Revision` and `SubSystemId` are hardcoded
zero and `display.h` documents them as such. Projecting `GraphicsAdapter` would ship a type whose
every property is a fiction, and the seven members above would carry that fiction into the device
and the manager.

`MISSING_MEMBER` is therefore **8**, and there is no ninth.

### The third partial type that was not — `Media.Song`, and a blocker that was wrong

Foundation 103 recorded `Song.Album`, `Song.Artist` and `Song.Genre` as `BLOCKED_UPSTREAM_CNA` with
the reason "no `cna_song_get_album`, `cna_song_get_artist` or `cna_song_get_genre` exists". **That
was false.** Foundation 104 re-measured it the way this project requires every blocker to be
re-measured — against the shipped artifact rather than against the note — and found all three:

```
$ nm -D --defined-only ~/deps/cna-c-abi-0.21.0/libcna_c_api.so | grep -oE 'cna_song_get_[a-z_]+'
… cna_song_get_album … cna_song_get_artist … cna_song_get_genre …
```

Both admitted header roots declare all three, at `media_library.h:1217`, `:1230` and `:1243`, under
the heading *"Song members that name a library entity"*. Each answers a **borrowed** handle plus an
availability flag, and the header says what false means: *"Only a song obtained from a media library
has one. A song a caller created from a file path has no library context, so this reports
`CNA_FALSE` — an ordinary answer, not a failure."* All three are bound now, the ABI gate type-checks
them against both roots, and `Song` is **complete**: `MISSING_MEMBER` falls 11 to 8 and
`PARTIAL_TYPES` 3 to 2.

**How the error happened, and what stops the next one.** The Foundation 103 audit searched the
manifest and the Ruby surface for the three names, found nothing, and wrote the blocker — it never
searched the header or the library. That is the same shape as every scanner defect this project has
recorded: a search anchored on one side only. `test/test_media.rb` now asserts the three routes are
**present** in the shipped library through `Fiddle::Handle#sym`, so the claim is measured in the
direction that can fail.

What is *not* measurable on this host is the positive answer: this machine's media library holds no
songs, so every reachable `Song` is one `FromUri` built and all three navigations correctly answer
nil. The test asserts that case and skips the other with a message naming what it gave up, which is
the same decision `Microphone` records for capture.

## The 16 missing types

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

**Re-measured at Foundation 104**, from the IL rather than from this page, because the standing rule
is that a blocker is measured before it is trusted. Four things were checked and all four hold:

1. `propertyDescriptions` and `supportStringConvert` are `.field family` — protected, not
   `assembly` — so they *are* in the projected surface and the first of them is typed
   `PropertyDescriptorCollection`. A protected field of an unprojectable type is not a member a
   subclass can be given.
2. `CanConvertFrom`'s fallback really is `call instance bool
   [System]System.ComponentModel.TypeConverter::CanConvertFrom`, at `IL_001f`, and `CanConvertTo`'s
   at `IL_0017`. Half of each member's observable answer is the base class's, so projecting the
   type without the base would be inventing behaviour rather than deriving it.
3. `CanConvertTo`'s special case is `ldtoken
   [System]System.ComponentModel.Design.Serialization.InstanceDescriptor` at `IL_0001` — a fifth
   identity, and in a fourth namespace.
4. **The authority would have to be a second one.** Every identity above lives in `System.dll`, not
   in `mscorlib`. `tools/api_compat/build_bcl_inventory.rb` is pinned to one assembly by SHA-256,
   derives its public key token from that assembly's own `.publickey`, and proves the pairing
   through each XNA assembly's `AssemblyRef` to **mscorlib**. Admitting `System.dll` means a second
   pinned authority and a second pairing proof — which is a decision about what this binding's BCL
   floor is, not a member to write.

The reach, counted rather than described: `TypeConverter` alone declares about thirty public
identities, `PropertyDescriptor` about twenty, `PropertyDescriptorCollection` about twenty, and
`CultureInfo` far more than all of them together. Projecting fifty-three design-time identities that
nothing in this binding consumes would cost well over a hundred BCL ones. The classification is
`BCL_PROJECTION_SCOPE`, and it is a scope decision with a measured price rather than a deferral.

### 4 built at Foundation 104 — the `ContentReader` family

`ContentReader`, `ContentTypeReader`, `ContentTypeReader`1` and `ContentTypeReaderManager` — 30
identities, over **zero** new native routes, so the bound-function count is unchanged at 757.

**One BCL register decision, and it is one line.** `ContentReader` extends
`System.IO.BinaryReader`, which the whole reference contract names exactly once and exactly there;
that single mention is what admits the family to the BCL inventory. The same rule refuses two of
`BinaryReader`'s twenty-six public identities: `ReadDecimal` returns `System.Decimal` and the second
constructor takes `System.Text.Encoding`, and no XNA signature names either, so neither type can be
admitted and neither member is projected. XNA's own `ContentReader..ctor` calls the one-argument
overload, measured at `IL_0002`.

**No `cna_content_reader_*` route is bound, and that is measured rather than assumed.** CNA exports
thirty-one of them and the behaviour matches, but `cna_content_reader_create` takes a
`CNA_StorageStreamHandle`; the whole ABI produces one from exactly two routes, both on a save-game
`StorageContainer`; and an XNA `ContentReader` reads a **title** asset, for which
`cna_title_container_read_ext` answers bytes rather than a stream handle.
`docs/content-reader-native-route-audit.md` carries the derivation.

**Measured end to end** against a compiled asset the test writes byte by byte: the container's four
refusals, the type manifest and its rollback, the one-based type identifier, the shared-resource
fixups, an external reference resolved against the asset's own directory, and all four of
`InvokeReader`'s rules.

### 17 built at Foundation 103 — the `Media` namespace

`MediaLibrary`, `MediaPlayer`, `MediaQueue`, `Song`, `SongCollection`, `Album`, `AlbumCollection`,
`Artist`, `ArtistCollection`, `Genre`, `GenreCollection`, `Playlist`, `PlaylistCollection`,
`Picture`, `PictureAlbum`, `PictureCollection`, `PictureAlbumCollection` — 182 identities, over 167
CNA routes each with a production call site, `ABI_MISMATCHES` 0 against both admitted header roots.
All seventeen are complete, `Song` included — see the correction above.

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
| built at Foundation 103 — `Media` | 17 | 185, all of them |
| built at Foundation 104 — `ContentReader` | 4 | 30, over zero new native routes |
| corrected at Foundation 104 — `Media.Song` | — | 3, on a blocker that was measured false |

**Nothing on this page is locally actionable.** Every remaining type is one of the sixteen missing
ones, and every one of those is either the adapter defect or the `System.ComponentModel` scope;
every remaining member is one of the eight, and every one of those traces to that same adapter
defect. Opening any of them is upstream work.
