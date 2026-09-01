# Audio.AudioEngine and Audio.AudioCategory — evidence

Behaviour authority: the pinned `Microsoft.Xna.Framework.Xact.dll` (SHA-256 `a14d5364…`), whose
`AudioEngine` and `AudioCategory` carry the whole contract, and `System.TimeSpan` from the pinned
Microsoft .NET Framework 4.0 `mscorlib` (SHA-256 `5634668d…`). Nothing measured from CNA is in the
behaviour corpus.

## 1. The deferral, and why it stopped being true

`Audio.AudioCategory` sat in `analyze_dependencies.rb`'s `RUNTIME_DATA` register with the reasoning

> an XACT AudioEngine category handle; SetVolume/Pause/Resume/Stop act on a live engine this binding
> does not have

Both halves are about the **producer**, the pattern five earlier register entries were retired for.
This one is different in one way worth recording: it did not need re-reading, it needed measuring.
The binding really did not have a live engine when that was written, and it does now.

The XNA Spacewar sample's XACT project is on this machine, and CNA 0.21.0 loads all of it:

    [AudioEngine] Loaded XGS: …/SpaceWar.xgs (6 categories, 8 variables)
    renderer_count -> SUCCESS 1      friendly 'SDL3_mixer'   id 'SDL3_mixer'
    cat Global/Default/Music/Weapons/Ships -> SUCCESS, each reporting its own name back
    get SpeedOfSound -> SUCCESS 343.5      set 400 -> SUCCESS      get -> 400

The fixtures are referenced by path through `CNA_TEST_XACT_DIR` and are never copied into this
repository — they are Microsoft XNA sample content — exactly as `CNA_TEST_XNB_DIR` references the
MonoGame XNB fixtures.

## 2. The constructor refuses a wrong file before XACT sees it

`AudioEngine(settingsFile)` is `AudioEngine(settingsFile, TimeSpan.FromMilliseconds(250), null)`.
The three-argument form, in the IL's order:

1. `if (string.IsNullOrEmpty(settingsFile)) throw new ArgumentNullException("settingsFile", NullNotAllowed)`
2. `File.OpenRead(Path.GetFullPath(settingsFile))` and a four-byte read; if the file is **four bytes
   or shorter**, or those bytes are not `X G S F` — `ldc.i4.s 88, 71, 83, 70` compared at indices
   0..3 — `ArgumentException(InvalidContentVersion)`
3. `Engine::CreateHandle(fullPath, (int)lookAheadTime.TotalMilliseconds, rendererId)`, and a `-1`
   handle becomes `InvalidOperationException(CouldNotCreateResource)`

So the magic-number check is **managed**, and it is reproduced: handing the projection the sound
bank (`spacewar.xsb`) instead of the settings file raises `ArgumentError` without the engine being
asked for anything. The fixture really carries `XGSF`, which the test asserts rather than assumes.

`ContentVersion` is `.field public static literal int32 ContentVersion = int32(0x00000027)` — 39.

## 3. The category handle, and why `GetCategory` caches

XNA's `AudioCategory` is a **struct** over three fields: the owning engine, a `uint16` category
index, and the name. `Equals` is `_category == other._category && _parent == other._parent`;
`op_Equality` compares the parent first and then the index; `GetHashCode` is
`_category.GetHashCode()`, XOR'd with the parent's hash when the parent is non-null.

CNA hands out a **handle** instead, and two calls for one name answer two different handles —
measured, `4294967299` and `4294967300` for `Music`. Its own `cna_audio_category_equals` says they
are equal and `cna_audio_category_get_hash_code` gives both the same value, so CNA's notion of
category identity is XNA's. The projection still caches the handle by name in the engine, for three
reasons: it makes handle equality exactly XNA's `_category ==`; it bounds the set of handles the
engine has to release; and it is the only way a value type with no `Dispose` can have a lifetime at
all. The cache is not trusted — `test_audio_engine.rb` asserts that it agrees with
`cna_audio_category_equals` in **both** directions, so a cache that started handing out wrong
handles would show.

Ownership: a category handle is `PARENT_OWNED`. `AudioEngine.Dispose` releases every handle it
handed out **before** releasing the engine, because a category outliving its engine is a handle into
a destroyed XACT engine and XNA declares nothing that would release one.

## 4. Two IL asymmetries, opposite to each other

`AudioCategory.SetVolume`:

    IL_0000: ldarg.1
    IL_0001: ldc.r4 0.0
    IL_0006: bge.un.s IL_0013        // >= 0, **or unordered**, jumps past the throw

`bge.un` is unordered, so `NaN` takes the **accepting** branch. That is the exact opposite of
`SoundEffectInstance.Volume`, whose `blt.un`/`bgt.un` make `NaN` **throw**. Both are the IL's and
both are reproduced. There is also no upper bound here at all: 2.5 is accepted.

**DEVIATION, recorded**: `cna_audio_category_set_volume` accepts a negative volume without
complaint, so the refusal is managed-side exactly as XNA's is and CNA never sees one. In the other
direction CNA refuses `NaN`, which XNA's managed check admits and hands to XACT — whose behaviour
the IL cannot tell us. So the managed contract is reproduced exactly and CNA's own refusal is what a
consumer sees, as `CNA::NativeError`.

`Pause()` and `Resume()` are one XACT entry point with a flag — `Engine::Pause(engine, category, 1)`
and `(…, 0)` — which CNA splits into two routes.

## 5. `RendererDetails` can be null

    IL_0000: ldnull
    IL_0001: stloc.3
    …
    IL_0010: ble.s IL_005e           // renderer count <= 0 skips the whole build
    IL_005e: ldloc.3
    IL_005f: ret

The local holding the answer starts as `ldnull` and is only replaced when the count is positive, so
**zero renderers answers null rather than an empty collection**. This host reports one renderer, so
the test asserts the branch that was actually taken and does not fabricate the null case.

Each call builds a fresh `List` and a fresh `ReadOnlyCollection`, which the projection reproduces —
unlike `Microphone.All`, whose wrapper is the same object every time.

## 6. Global variables, and whose refusal it is

`GetGlobalVariable`/`SetGlobalVariable` both begin
`if (string.IsNullOrEmpty(name)) throw new ArgumentNullException("name")` and then call XACT.

The settings file declares eight variables. Exactly one, `SpeedOfSound`, is global; the other seven
— `NumCueInstances`, `AttackTime`, `ReleaseTime`, `OrientationAngle`, `DopplerPitchScalar`,
`Distance`, `Unused` — are **cue-scoped**, and XACT answers `CNA_RESULT_INVALID_STATE` for each.
That refusal is XACT's own and is recorded as such rather than turned into a managed rule this
binding invented.

## 7. What is not projected

No `WaveBank`, no `SoundBank`, no `Cue`. `WaveBank` reached the frontier the moment `AudioEngine`
completed — its constructor names one — which is what completing a type does, and `Cue` left the
il-only blocked list for the same reason: `AudioEngine` was its one il-only unmet dependency.

`cna_audio_engine_create` is deliberately unbound: XNA's one-argument constructor delegates to the
three-argument one with an explicit 250 ms look-ahead, so the projection always has one to pass and
`cna_audio_engine_create_with_renderer` is the route it needs.
