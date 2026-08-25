# Native frontier 3 — the `modopt` blind spot in the native-boundary measurement

No type was projected in this milestone. What changed is a measurement that several earlier
milestones relied on, and one recorded conclusion that was drawn from it and was wrong.

## How it surfaced

The frontier's `BCL_PROJECTION`-only list is where safe managed work comes from, and after
Foundation 33 it had one entry left that was neither out of scope nor already declined:
`Audio.SoundEffectInstance`, 16 identities, blocked only on `System.IDisposable`. The IL inventory
reported it `nativeReachable: false`, which would have made it pure managed work.

It is not. Its own IL calls:

```
call int32 modopt([mscorlib]System.Runtime.CompilerServices.IsLong)
     Microsoft.Xna.Framework.Audio.SoundEffectUnsafeNativeMethods::Play(uint32)
```

and `SoundEffectUnsafeNativeMethods::Play`'s body is `calli unmanaged thiscall` into XACT. The
inventory was wrong.

## The defect

The extractor built a call-graph node per method as `FullTypeName::MethodName`, reading the name
from the `.method` header as *the first identifier followed by a parenthesis* — after removing
`pinvokeimpl(...)` and `marshal(...)`, the two header forms known to carry a parenthesis before the
name.

A mixed-mode C++/CLI thunk carries a third:

```
.method public hidebysig static int32 modopt([mscorlib]System.Runtime.CompilerServices.IsLong)
        Play(uint32 voiceHandle) cil managed
```

The first identifier before a parenthesis is `modopt`. So the *declaration* was recorded as
`SoundEffectUnsafeNativeMethods::modopt`, while every *call site* resolved correctly to
`SoundEffectUnsafeNativeMethods::Play` — a node that did not exist. Every edge into XNA's
native-methods classes dangled, and the reachability fixpoint never crossed them.

This is the same class of defect as Native frontier 2's: a declaration form the scanner could not
read, costing measurement silently rather than loudly. `modopt` and `modreq` join `pinvokeimpl` and
`marshal` in one named `HEADER_NOISE` pattern, so a fourth form is added in one place.

## What the correction moves

| Metric | Foundation 22 | Native frontier 2 | **Native frontier 3** |
| --- | --- | --- | --- |
| Native entry-point methods | 205 | 214 | **254** |
| Native-reachable reference types | 55 of 250 | 61 of 257 | **77 of 257** |

Sixteen reference types gained native reachability and **none lost it**. Every other measured number
is unchanged: `REFERENCE_TYPES` 257, `TYPES_WITH_IL` 257, `TYPES_WITHOUT_IL` 0, and not one type's
`declaredMethods` or `declaredFields` moved.

The sixteen:

- `Audio.SoundEffectInstance`
- `FrameworkDispatcher`
- `Media.Album`, `Media.AlbumCollection`, `Media.Artist`, `Media.ArtistCollection`, `Media.Genre`,
  `Media.GenreCollection`, `Media.MediaQueue`, `Media.Picture`, `Media.PictureAlbum`,
  `Media.PictureAlbumCollection`, `Media.PictureCollection`, `Media.Playlist`,
  `Media.PlaylistCollection`, `Media.SongCollection`

`NATIVE_ENTRY_POINT_METHODS` is now written into `docs/generated/xna-il-inventory.json` rather than
only printed. It was the number the whole fixpoint starts from and nothing could pin it.

## The conclusion it corrects

`FrameworkDispatcher` is a **shipped, complete type**, and Native frontier 1's evidence recorded, as
a measured fact:

> In this Windows assembly `PollForEvents` does nothing, so `Update` reaches no native entry point
> at all. That is measured independently by `docs/generated/xna-il-inventory.json`, which records
> this type as `nativeReachable: false`.

The premise is right — `PollForEvents` really is `{ ret }` — and the conclusion was wrong.
`Update`'s last instruction before returning is

```
call void Microsoft.Xna.Framework.Audio.SoundEffect::RecycleStoppedFireAndForgetInstances()
```

which reaches XACT through exactly the thunks this defect hid. The inventory now records
`nativeReachable: true` with `nativeReachableMethods: ["Update"]`, and still
`declaresNativeEntryPoint: false`, because the reachability is transitive rather than declared.

**This strengthens Native frontier 1's decision rather than undermining it.** That milestone argued
that forwarding to `cna_framework_dispatcher_update` is a real pump rather than a Ruby no-op wearing
a pump's name, and it turns out XNA's own `Update` also ends in native work. The projection is the
closer analogue, not the looser one. The evidence file carries the correction inline where the wrong
sentence was.

## What it corrects on the frontier

`Audio.SoundEffectInstance` moves from `BCL_PROJECTION` to **`BCL_PROJECTION` + `NATIVE_RUNTIME`**,
which is the honest classification and the reason this milestone exists: without the fix, the next
milestone would have projected sixteen identities of live-XACT behaviour as pure managed work.

Frontier totals are unchanged at 19 dependency-complete and 0 consumable; the `BCL_PROJECTION`-only
group is 6 → 5.

The shipped-boundary rule the classifier is validated against still holds and is now stated with
four entries rather than three: every partial runtime type but `GraphicsResource` is native, and of
the complete types exactly `Input.Mouse`, `Input.GamePad`, `Graphics.Texture` and
`FrameworkDispatcher` are — each one a type whose native route this binding really implements.

## Regression

`test_the_extractor_reads_a_method_name_past_a_return_type_modifier` pins both halves: the name rule
itself, against `modopt`, `modreq`, `pinvokeimpl` and an ordinary declaration; and the reachability
it restores, including that the pure-managed families — `Vector2`, `Matrix`,
`Input.Touch.TouchPanel`, `GameServiceContainer` — gained none.

## A corpus correction

`il_provenance.assemblies` pinned this project's own measurement of `typesNativeReachable`, which
this milestone corrected from 61 to 77. That one element was updated.

Unlike the Native frontier 2 correction — which could not use a replay, because the committed corpus
then rendered small floats in a decimal notation the JSON generator did not reproduce — a
byte-preserving re-serialisation replay **is** available again and was used: the pre-correction
corpus re-serialises byte-identically first, and exactly one observation differs afterwards.
Recorded as `nativeFrontier3CorpusCorrection`.

## What this milestone does not do

No type was added, no member changed, no Ruby behaviour moved, and the CNA ABI is unchanged at
39 / 124 / 290 / 290 / 2 / 59. Strict stays at 139 types / 1745 members, 133 complete, 302
diagnostics.
