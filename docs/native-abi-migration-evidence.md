# Native ABI migration — CNA C ABI 0.7.0 to 0.21.0

This records the evidence for moving CNA-Ruby's only native boundary from the historical CNA C ABI
`0.7.0` artifact to the current live one, and the four behavioural facts the move measured on the
way. It is not a version-number edit: the whole bound surface was re-measured with a compiler
against both header generations, and the admission policy was rebuilt from CNA's own versioning
contract rather than from a preference.

## The live dependencies

| | value |
| --- | --- |
| `cnanext` HEAD | `0a6158e4ff764907065cd7259e3d29e331a52088` (branch `next`, `fix(SAMPLE-060): resolve nested XNB media siblings`, 2026-08-31) |
| `sharp-runtimenext` HEAD | `4a49afb0cfe6a41e6e0af0bb62dc5175976731bb` (branch `next`, 2026-08-30) |
| `CNA_ABI_VERSION` | `0.21.0`, encoded `0x00001500` |
| canonical C declarations | 4054 `CNA_C_API` functions across 61 headers |
| exported `cna_*` symbols | 4054 — declaration count and export count are equal |
| relation to `0.7.0` | strict superset: 2861 → 4054 exports, **zero removed** |

Neither dependency repository was modified. Both were read, and one already-built artifact was
copied out of `cnanext` rather than rebuilt.

## The qualification artifact

The binding needs an artifact whose *behaviour* it can qualify, not merely one whose symbols it can
resolve. Of the nine current `cnanext` build directories carrying a `0.21.0` `libcna_c_api.so`, the
one selected is `cmake-build-headless`:

| option | value | why it matters here |
| --- | --- | --- |
| `CNA_PLATFORM` | `SDL3` | a real platform rather than the `HEADLESS` platform the 0.7.0 artifact was built with |
| `CNA_AUDIO_PLATFORM` | `SDL3` | the audio backend Native frontier 4 could not reach |
| `CNA_GRAPHICS_RENDERER` | `HEADLESS` | the renderer this suite already qualifies, and the only one that runs with no display |

`CNA_GRAPHICS_RENDERER` is a **build-time** selection with a runtime override that can only choose a
renderer compiled in: the same probe run against `cmake-build-opengles3` with
`CNA_GRAPHICS_RENDERER=HEADLESS` refuses with *"the HEADLESS renderer is not compiled into this
build. Available: OPENGLES3"*. That is why an artifact and not just a variable had to be chosen.

The artifact is pinned out of tree so a rebuild in `cnanext` cannot change what this repository
qualified:

- library: `~/deps/cna-c-abi-0.21.0/libcna_c_api.so`
- SHA-256: `c32bfbd307d695664f906ccf2834ec3f9ebc240fa388d544ac21ee3ebaeb731b`
- headers: `~/deps/cna-c-abi-0.21.0/include`, 61 files, tree digest
  `1342fdbb24c654352ebac6b7381ee2a6dafeae6ec413c2c5ec4e653325704850`
- platform Linux x86-64; SDL3 runtime libraries copied beside it under `lib/`

It is not bundled, and its location is not a runtime default. Consumers still set
`CNA_NATIVE_LIBRARY` to an absolute path.

## What the migration measured

`tools/native_abi/probe.c` is compiled with `-Werror` against a header root and emits one record per
prototype, structure, field and constant. Compiling the **unchanged** probe against the 0.21.0
headers succeeded, which is already a strong statement: every one of its 68 `CHECK_FN`
`_Static_assert`s and both callback assertions still hold, so no bound prototype changed.

Running it against both header roots and diffing the output gives the exact delta over the bound
surface:

```
219 signature records, 300 layout records, 66 constant records
diff 0.7.0 0.21.0 ->  CONSTANT|CNA_ABI_VERSION|1792  ->  CONSTANT|CNA_ABI_VERSION|5376
```

**One line.** Every prototype, every structure size and alignment, every field offset and size, and
every other constant is byte-identical between CNA C ABI 0.7.0 and 0.21.0 over the surface this
binding binds. Nothing was inferred from a surviving function name.

That equality is not a footnote — it is the evidence for the admission policy below, so
`tools/native_abi/verify.rb` now *re-derives* it on every run instead of quoting this paragraph.

## The admission policy

`docs/c-api/ABI_VERSIONING.md` in `cnanext` says two things that together rule out both of the easy
policies:

> A consumer must reject a different major and may require a minimum minor.

> ABI `0.x` is experimental: an incompatible change requires a minor-version increment, release
> notes and a regenerated ABI baseline.

- **"Same major accepts everything" is unsound.** In `0.x` a *later* minor may be incompatible, and
  `0.20.0` really was: it removed eleven public renderer identities and moved
  `CNA_GRAPHICS_RENDERER_MAXIMUM` from 50 to 49.
- **"Require a minimum minor" is unsound for the same reason.** The incompatibility travels forward,
  not backward, so a floor admits precisely the versions it cannot vouch for.
- **A single frozen version would be sound but says nothing about why**, and is the policy the old
  `expected 0x00000700 (0.7.0)` message hard-coded into a string.

So admission is neither a range nor a single number. `CNA::Native::Manifest::ADMITTED_ABI_VERSIONS`
is **the set of encoded versions whose whole bound surface this repository has measured with a
compiler**, and the verifier proves the membership rather than asserting it:

- `CNA_HEADERS` names the loaded library's header root; `CNA_ADMITTED_HEADERS` names every other
  admitted version's, colon-separated.
- Every root must itself declare a `CNA_ABI_VERSION` in the admitted set — reported as
  `admission …` rather than as a constant mismatch, because the version is the one measurement that
  legitimately differs.
- Every root must agree with every other on **every other** measurement — `CROSS_VERSION_MISMATCHES`.
- The loaded library's `cna_get_abi_version()` must be in the set, and the refusal names the set, the
  version found and the library path.

The set is currently `{0.7.0, 0.21.0}` because both are measured, not because 0.7.0 is preferred. It
will lose 0.7.0 the moment this binding imports a route 0.7.0 does not export, and that will be a
measurement — `MISSING_LIBRARY_SYMBOLS` — rather than a decision.

`CNA_ABI_VERSION` left `Manifest::CONSTANTS` for the same reason: it is not a constant this binding
consumes, it is the identity this binding gates on. The constant census is therefore 66 → 65 with no
constant lost.

## The gate is falsifiable

`test/test_native_abi_gate.rb` plants one defect at a time and requires the gate to name it. The
canonical headers are never touched; every mutation is on the Ruby side, which is the side that can
drift. Sixteen controls, all passing, each with the unmutated surface asserted clean against the
same measurement:

| mutation | what it models | caught as |
| --- | --- | --- |
| `int64_t` → `int32_t` on a tick parameter | a width that still marshals and truncates quietly | `signature …` |
| dropped `const` on `cna_game_create` | an API-contract change that no Fiddle type records | `signature …` |
| `CNA_Handle*` → `CNA_Handle**` | pointer depth, which `TYPE_VOIDP` cannot distinguish | `signature …` |
| `CNA_GAMEPAD_BUTTON_A`/`_B` swapped | a controller that reports the wrong button forever | two `constant …` |
| a constant no header declares | an invented identity | `constant … C=nil` |
| `CNA_MouseState.scroll_wheel` offset +4 | reading the adjacent field | `field …` |
| `CNA_GamePadState` size +8 | a structure that stopped matching | `layout …` |
| a manifest symbol no header declares | `MISSING_HEADER_SYMBOLS`, now measured rather than asserted zero | `signature … no canonical declaration measured` |
| by-value expansion record removed | comparing two eightbytes against one struct | `signature …` |
| by-value member count 2 → 3 | a decomposition that stopped matching the platform ABI | `signature …` |
| lifecycle callback's 4th argument retyped | a callback the compiler must reject | probe **fails to compile** |
| `cna_game_run(CNA_Handle)` → `(uint32_t)` | a prototype the compiler must reject | probe **fails to compile** |
| ABI `0.3.0` presented to the gate | an inadmissible version | refusal naming set, version, path |
| headers declaring an unadmitted version | an unreviewed header root | `admission …` |
| two roots disagreeing on a constant and a prototype | the cross-version equality above | two `cross-version …` |

The two compile controls matter most: `CHECK_FN` and the callback typedefs are `_Static_assert`s, so
the claim being tested is that a drifted declaration is a **build** failure and not a runtime
surprise. Both mutations are applied to a copy of `probe.c` in a temporary directory.

## Four behavioural facts the migration measured

The ABI is identical; the runtime behind it is not. Each of these was measured against both
artifacts with the same driver.

### 1. The audio-playback blocker is fixed upstream

Native frontier 4 recorded `SoundEffect`/`SoundEffectInstance` as `UPSTREAM_CNA_BLOCKED`: against the
0.7.0 artifact every route reported success while `SoundState` never left `Stopped`, one second of
PCM16 answered a zero duration, and `set_is_looped` was refused with `CNA_RESULT_INVALID_STATE` in
every state. Driven identically against the 0.21.0 artifact:

```
duration_ticks              -> SUCCESS  10000000   (exactly one second)
sample_duration_ticks       -> SUCCESS  10000000
set_is_looped(TRUE)         -> SUCCESS  is_looped round-trips
play                        -> state Stopped -> Playing
pause                       -> Paused
resume                      -> Playing
stop                        -> Stopped
volume / pitch / pan        -> 0.50 / 0.25 / -0.75 round-trip
```

`cna_sound_effect_get_sample_duration_ticks` is also a different route than the audit assumed: it is
a **static computation** `(size_in_bytes, sample_rate, channels, out_ticks)` and takes no handle,
which is why calling it with a sound-effect handle failed. The audio cluster is reopened.

### 2. XNA's priming `Update` now exists

`docs/game-tick-evidence.md` recorded two CNA loop deviations that were deliberately not
re-implemented. One of them is gone. XNA's `RunGame` (`Microsoft.Xna.Framework.Game.dll` IL
`IL_004c`–`IL_007f`) sets `ElapsedGameTime = TimeSpan.Zero`, `TotalGameTime = totalGameTime` and
`IsRunningSlowly = false`, calls `Update`, then sets `doneFirstUpdate`. Measured on 0.21.0:

```
initialize load begin_run  update(total=0, elapsed=0)  draw  update(total=0, elapsed=step) …
```

The priming `Update` is delivered. It is delivered from the **first frame step**, so a Game driven
only by `Tick` sees it too, where XNA's `Tick` has no priming update — that half is a new recorded
deviation. The draw placement also differs: CNA draws after the priming update, where XNA's first
draw follows the first *loop* update.

### 3. `TotalGameTime` was wrong here, and 0.21.0 is what the IL says

This is a defect the migration found in **this repository**, not upstream. `Game.Tick`'s fixed-step
branch writes `gameTime.TotalGameTime = this.totalGameTime` at `IL_0180`, and only the `finally` at
`IL_01e8` adds the step. An Update is therefore handed the total accumulated *before* its own step,
so the first advancing Update reports **zero**.

`test_the_fixed_step_advances_total_game_time_by_exactly_one_target_step` asserted
`step * (index + 1)`. That was CNA 0.7.0's post-increment value, and the test had encoded it as
though it were XNA's. CNA 0.21.0 reports the pre-increment value, the assertion failed, and reading
the IL showed the test — not the runtime — was wrong. It is now
`test_the_fixed_step_hands_each_update_the_total_accumulated_before_its_own_step` and states the
rule the way the IL states it: every Update's `TotalGameTime` is the sum of every earlier Update's
`ElapsedGameTime`, which holds however many Updates one tick delivers.

### 4. `GraphicsAdapter` is still fabricated, and now for a narrower reason

The 0.7.0 artifact was a `HEADLESS`-*platform* build, which is why every adapter query answered
invented values. The 0.21.0 artifact is an `SDL3`-platform build, so that specific explanation is
gone — and the values are unchanged: one adapter, description `Default Display`, device name
`\\.\DISPLAY1`, one supported mode, current mode `800x480`, format 0. The same measurement against
`cmake-build-opengles3`, which brings up a real OpenGL ES 3.2 context on this host's Mesa driver,
answers **identically**. So the fabrication is not the platform build and not the renderer; it is
above both. `GraphicsAdapter` stays blocked and the audit needs redoing against the current source
rather than against the retired artifact's explanation.

## Qualification after the migration

| gate | result |
| --- | --- |
| `rake test` | 1143 runs / 44635 assertions / 0 failures / 0 skips |
| `tools/native_abi/verify.rb` | 68 functions, 219 signature, 300 C layout, 300 Ruby layout, 3 callbacks, 65 constants, 2 admitted versions, 2 header roots, 0 cross-version mismatches, 0 missing header symbols, 0 missing library symbols, 0 mismatches |
| `tools/api_compat/verify.rb` | unchanged structural report; every mismatch category as before |
| `tools/api_compat/analyze_dependencies.rb` | unchanged at the moment of migration; re-run separately in the frontier pass |
| `tools/run_behavior_corpus.rb` | 526 observations, 0 failures |
| `tools/capability_consistency.rb` | clean |

No behaviour-corpus row was added or corrected by the migration: the corpus is XNA-derived and the
migration changed a native artifact, not an XNA fact.
