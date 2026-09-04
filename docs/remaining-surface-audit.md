# The remaining surface, classified member by member

**Measured 2026-09-04 at Foundation 105**, against the strict report
(`docs/generated/api-compat-report.json`), the pinned XNA IL, the two pinned BCL authorities and the
qualified CNA C ABI 0.21.0 artifacts. 254 target types, **252 complete**, 2 partial, 3 missing.

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

**Re-checked at Foundation 105 without re-running the artifacts, because nothing moved.** `cnanext`
advanced 55 commits during that milestone, so the standing rule — re-measure a blocker rather than
trust the note — was applied to the question of *whether* a re-measurement was owed:
`modules/graphics/src/Xna/GraphicsAdapter.cpp`, which
`docs/graphics-adapter-ordering-upstream-defect.md` names as the defect's site, has **zero** commits
since, `modules/graphics` as a whole has zero, the only `Video`-named change is a content test for
`VideoReader`, and the qualified artifact is byte-identical at
`c32bfbd307d695664f906ccf2834ec3f9ebc240fa388d544ac21ee3ebaeb731b`. All 55 commits are
content-pipeline and shader-design work. Re-running three renderer qualifications against unchanged
code would have produced the same three fictions at three artifacts' cost.

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

## The 3 missing types

They were sixteen at Foundation 104. Thirteen of those were the `Design` converters, built at
Foundation 105 and recorded below; what is left is three, and all three are one defect.

### 3 blocked on the adapter defect

`Graphics.GraphicsAdapter`, `GraphicsDeviceInformation`, `PreparingDeviceSettingsEventArgs` —
`BLOCKED_UPSTREAM_CNA`. The second's `Adapter` property is a `GraphicsAdapter` and the third's whole
surface is a `GraphicsDeviceInformation`, so neither can be honest while the first is not.

### 13 built at Foundation 105 — the `Design` converters

`MathTypeConverter` and the twelve converters that derive from it. **This section used to classify
them `BCL_PROJECTION_SCOPE`, and that was a scope decision rather than a blocker.** Its own evidence
said so: the authority was on this machine, the reach was measurable, and what was deferred was the
work of projecting a descriptor system. Foundation 105 does that work.

**A second BCL authority, admitted to the same standard as the first.** `System.dll` declares every
`System.ComponentModel` identity the family reaches and mscorlib declares none of them, so the
inventory had to stop being pinned to one assembly. It is now a registry: exact SHA-256, an identity
derived from each assembly's own `.publickey` blob, a Microsoft origin claim read out of the PE, and
a pairing proof — every gate a property of the registry rather than of mscorlib.

One gate had to get **stronger** to admit the second binary rather than weaker. Only six of the ten
pinned XNA assemblies reference `System`; requiring all ten would have failed and requiring merely
one would have proved nothing, so the referrer set is itself asserted and an assembly that gained or
lost the reference now fails the gate. `tools/api_compat/reference/BCL_PROVENANCE.md` carries both
identities and the partition.

**The demand closure is generated, not asserted.**
`docs/generated/design-converter-inventory.json` derives the whole audit table from the pinned IL —
base, fields, descriptor names, authored order, sort order, field-versus-property reflection, scalar
element type, string-convert support, the constructor each `InstanceDescriptor` names, the dictionary
keys each `CreateInstance` reads — and `test/test_design_converters.rb` asserts the Ruby against it,
so neither side can drift. Thirty-two BCL families are admitted across the two authorities, on three
measured demands: **direct** (an XNA signature names it), **transitive** (an admitted family's
measured surface does), and **behavioural** (the measured XNA behaviour calls it and a consumer
observes the result). `System.ComponentModel.TypeDescriptor` is the case that needed the third: no
signature anywhere names it, and both of `MathTypeConverter`'s generic helpers call `GetConverter`.

**Four facts the IL settled that no page had recorded.**

1. **`MatrixConverter` and `RectangleConverter` never sort.** The other ten call
   `PropertyDescriptorCollection.Sort(names)` in their constructors; those two do not, so their
   property order is the authored one — `M11..M44` and `X, Y, Width, Height`, neither of them
   alphabetical, which is what a bare `Sort()` would have given.

2. **`ColorConverter` cannot produce an `InstanceDescriptor`.** Its `ConvertTo` asks
   `typeof(Color).GetConstructor(new[]{ typeof(byte) ×4 })`. `Color` declares seven public
   constructors and none takes four bytes, so `GetConstructor` answers **null**, the IL's own
   `ConstructorInfo.op_Inequality(ctor, null)` at `IL_00bb` fails, and the branch is skipped
   entirely. The generator resolves every named constructor against the reference contract: eleven
   of twelve resolve and the twelfth is reported rather than implemented as though it did.

3. **Six converters answer `CanConvertTo(String)` true and cannot format one.**
   `supportStringConvert` is false for `BoundingBox`, `BoundingSphere`, `Matrix`, `Plane`, `Ray` and
   `Rectangle`, so `CanConvertFrom(String)` is false — but `CanConvertTo` falls through to
   `TypeConverter.CanConvertTo`, whose whole body is `destinationType == typeof(string)`. So it is
   true, and `ConvertTo` really does produce a string: the base's, which is `value.ToString()`.

4. **`TypeConverter.CanConvertFrom` answers for `InstanceDescriptor`, not for `String`.** Half of
   each converter's answer is the base class's, which is why the base is projected rather than
   flattened: writing those members by hand would have been inventing behaviour rather than
   deriving it.

**One language mapping limitation, recorded rather than hidden.** Ruby's `Integer` is the
projection of both `System.Int32` and `System.Byte`, and two measured behaviours turn on telling
them apart — `Color`'s missing four-byte constructor, and which element converter parses a channel
(`ByteConverter` accepts hexadecimal and ranges 0..255; `Int32Converter` does not range-check to a
byte). So the reflection registry is keyed by **CLR identity** and answers the Ruby type beside it:
the lookup is exact and the value a consumer reads is what `System.Type` projects to.

A second one: the CLR reads culture data from the operating system and Ruby has nothing equivalent.
This binding ships no locale database — `CultureInfo` carries the separators the reach consumes,
the invariant culture's values are read out of the pinned mscorlib's own `CultureData` initialiser,
and a consumer constructs any other culture with the values it needs. `CurrentCulture` defaults to
the invariant one so a converter's output does not depend on the host's locale environment.

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
| built at Foundation 103 — `Media` | 17 | 185, all of them |
| built at Foundation 104 — `ContentReader` | 4 | 30, over zero new native routes |
| corrected at Foundation 104 — `Media.Song` | — | 3, on a blocker that was measured false |
| built at Foundation 105 — `Design` | 13 | 55, over zero new native routes |

**Every remaining row is the same upstream defect.** All three missing types and all eight partial
members trace to CNA's adapter initialisation order, and there is nothing else on this page.
`BCL_PROJECTION_SCOPE` no longer classifies a **type**: the thirteen converters were the whole of
that, and `test/test_design_converters.rb` asserts on three independent artifacts that no selected
type carries it, so reintroducing it for a selected family fails a test rather than passing review.

It still classifies two **members**, and that is a different thing rather than a leftover.
`BinaryReader.ReadDecimal` returns `System.Decimal` and its second constructor takes
`System.Text.Encoding`; no XNA signature names either type, so the inventory's demand rule refuses
both families and the members that return them cannot be projected. That is the classification doing
its job — refusing an identity nothing demands — rather than deferring one the project selected.
`lib/cna/runtime/binary_reader.rb` records both.

## Every strict diagnostic, accounted for

`TOTAL_DIAGNOSTICS` is **16**, down from 29, and this is all of them:

| count | category | classification |
| ---: | --- | --- |
| 3 | `MISSING_TYPE` — `GraphicsAdapter`, `GraphicsDeviceInformation`, `PreparingDeviceSettingsEventArgs` | `BLOCKED_UPSTREAM_CNA` |
| 8 | `MISSING_MEMBER` — `GraphicsDevice`'s 3 and `GraphicsDeviceManager`'s 5 | `BLOCKED_UPSTREAM_CNA` |
| 5 | `OVERLOAD_MAPPING_MISMATCH` | **not a fourth thing**: the verifier reports an overload count beside a missing member whenever the member is a method or constructor, so these five are the five method-shaped entries of the eight above, counted a second time |

Every other structural category is **zero**, the allowlist is empty and
`UNMEASURED_STRUCTURAL_CATEGORY` is zero. There is no diagnostic on this project that is not in the
table above, all sixteen trace to one upstream defect, and none of them is local.
