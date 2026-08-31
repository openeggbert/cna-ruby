# Foundation 44 — `Game.Tick`

Derived from the pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, disassembled with `ikdasm`.

`Tick` was the last member of `Game` that a previous handoff called "a public architecture decision,
not a binding", on the grounds that projecting it would add a second frame-step entry point whose
semantics differ from `RunOneFrame`. The IL says the difference is XNA's own, not this binding's, so
there was no architecture to decide: the two are separate operations in XNA and they are separate
operations here.

## `RunOneFrame` is host-event processing wrapped around `Tick`

`Game.RunOneFrame` is twenty bytes and does one thing:

```
IL_0000: ldarg.0
IL_0001: ldfld    class GameHost Game::host
IL_0006: brfalse.s IL_0013          // a null host is a silent no-op
IL_000e: callvirt instance void GameHost::RunOneFrame()
```

`GameHost.RunOneFrame` is `abstract`; `WindowsGameHost` implements it in three steps:

1. `gameWindow.Tick()` — `WindowsGameWindow.Tick` rethrows and clears the `pendingException` the
   WinForms message pump captured. This is the host-event half.
2. `GameHost.OnIdle()` — raises the internal `Idle` event. Its **only** subscriber is
   `Game.HostIdle`, added in `Game.EnsureHost`, and `HostIdle`'s entire body is
   `IL_0001: call instance void Game::Tick()`.
3. When `GamerServicesDispatcher.IsInitialized`, `gameWindow.IsGuideVisible = Guide.IsVisible`.

So `RunOneFrame` really is `Tick` with host-event processing around it. The canonical CNA C ABI
already documents exactly that split — `cna_game_tick` is "the canonical frame step
`cna_game_run_one_frame` wraps; it **does not process host events**" — so the binding is direct.
The two are never aliased, and `test/test_game_tick.rb` asserts they resolve to different Ruby
`UnboundMethod`s over different native symbols so a later "simplification" cannot merge them.

The Microsoft-free IL inventory records the same relationship independently. `Game`'s
`externalMemberReferences` contain `GameHost::RunOneFrame` and the three `GameClock` calls that are
`Tick`'s own body — `UpdateElapsedTime`, `get_ElapsedAdjustedTime`, `AdvanceFrameTime` — and its
`nativeReachableMethods` contain `Tick` and `HostIdle` but **not** `RunOneFrame`. `HostIdle` is on
that list only because its body is `this.Tick()`, and `RunOneFrame` is off it because its native work
happens inside the internal host rather than in `Game`.

## What `Tick` does

682 bytes, in order:

```
if (ShouldExit) return;
if (!isActive) Thread.Sleep((int)inactiveSleepTime.TotalMilliseconds);
clock.UpdateElapsedTime();
bool skipDraw = true;
TimeSpan elapsed = clock.ElapsedAdjustedTime;
if (elapsed < TimeSpan.Zero) elapsed = TimeSpan.Zero;
if (forceElapsedTimeToZero) { elapsed = TimeSpan.Zero; forceElapsedTimeToZero = false; }
if (elapsed > maximumElapsedTime) elapsed = maximumElapsedTime;
if (isFixedTimeStep) { … } else { … }
if (!skipDraw) DrawFrame();
```

The fixed-step branch snaps `elapsed` to `targetElapsedTime` when the two differ by less than
`targetElapsedTime.Ticks >> 6`, divides the accumulator by the target to get a catch-up count,
**returns outright when that count is zero**, and otherwise runs `Update` that many times inside a
`try`/`finally` that subtracts the step from `accumulatedElapsedGameTime` and adds it to
`lastFrameElapsedGameTime` and `totalGameTime`. `updatesSinceRunningSlowly1`/`2` are saturating
counters and `drawRunningSlowly` is `updatesSinceRunningSlowly2 < 20`. The variable-step branch
advances the clock once, forces `drawRunningSlowly` false and both counters to `int.MaxValue`, and
runs `Update` once.

`skipDraw` starts **true** and is `and`ed with `suppressDraw` after every `Update`, which clears the
field in the same breath, and the method ends `if (!skipDraw) DrawFrame()`. So one pending
`SuppressDraw` skips exactly one frame's draw. `DrawFrame` is private, and its own four gates are
`ShouldExit`, `doneFirstUpdate`, `Window.IsMinimized` and `BeginDraw()`.

Everything after the first line is the timing loop, which CNA owns here. It is measured faithful on
every point the loop makes observable: the fixed step advances `TotalGameTime` by exactly one
`TargetElapsedTime` per tick and reports that same span as `ElapsedGameTime`; a pending
`SuppressDraw` skips exactly one draw and then normal drawing resumes; and no lifecycle callback
other than `Update`/`BeginDraw`/`Draw`/`EndDraw` is delivered. That last one matters:
**`Tick` initialises nothing.** XNA's `Initialize`, `BeginRun` and the priming `Update` live in
`RunGame`, not here, which is why a Game driven only by `Tick` never sees them and a later `Run`
still delivers all of them.

## The one line that is not CNA's

`Tick`'s first instruction is `if (ShouldExit) return`. `get_ShouldExit` is a single
`ldfld exitRequested`, and `exitRequested` is written **exactly once in the whole assembly** —
`ldc.i4.1` in `Game.Exit()` — and is **never cleared**. It is a latch: after `Exit()`, XNA's `Tick`
returns before it touches the clock, for the rest of the Game's life.

That field is managed state this binding already keeps and already writes in the same place, so the
guard is projected rather than delegated. The reason is measured, not stylistic:

```
game.Tick                       -> update, begin_draw, draw, end_draw
host.request_exit; host.tick    -> update
```

CNA's step, after `cna_game_request_exit`, still delivers one `Update` and skips only the `Draw` —
one callback more than XNA delivers. The latch is also why an `Exit()` before the first `Tick`
leaves the Game with **no native host at all**: nothing needs creating for an operation that returns
at its first line.

## Recorded deviations

- **Re-entrancy.** `cna_game_tick` is refused from inside a lifecycle callback, "because a frame step
  called from within a frame would re-enter the loop it is part of". XNA has no such guard — but it
  has no usable behaviour there either. A `Tick` from inside `Update` re-enters with
  `accumulatedElapsedGameTime` not yet decremented by the loop's `finally`, so the recursive frame's
  catch-up count is again at least one, it calls `Update` again, and the recursion is unbounded,
  ending in a `StackOverflowException` the CLR does not let anyone catch. No valid XNA program can
  depend on that. The refusal is surfaced as CNA's own translated error — `CNA::NativeError` for
  `cna_game_tick` carrying the native message — rather than pre-empted by a binding-level guard, so
  the contract a consumer sees is the native one and no shadow state can drift from it.
- **Owner thread.** `cna_game_tick` is owner-thread bound and XNA's `Tick` is not, so a `Tick` off
  the owner thread raises `CNA::OwnerThreadError`. This is the same asymmetry already recorded for
  the timing setters and for `FrameworkDispatcher`, and it is asserted rather than hidden.

## Measured deviations of CNA's loop that `Tick` did **not** introduce

The audit found two places where CNA's loop differs from XNA's, both of which belong to `Run` and
`RunOneFrame` as much as to `Tick`, and both of which are the native host's to own. Neither is
re-implemented on this side, because the managed `Game` here is a callback façade over CNA's native
`Game` and any managed step CNA already performs would be performed twice — the rule the
`GraphicsDeviceManager` producer audit established.

- **`doneFirstUpdate`.** XNA sets it at the end of the *base* `Game.Update`, and `DrawFrame` returns
  early while it is false. A subclass that overrides `Update` without calling `base.Update` therefore
  never draws in XNA; here it does. In practice the gap is narrower than it looks, because
  `RunGame` also sets the flag unconditionally after its priming `Update`, so a `Run`-driven Game is
  unaffected either way; it is only reachable on a Game driven by `Tick`/`RunOneFrame` alone.
- **The priming `Update`.** XNA's `RunGame` calls `Update(gameTime)` once with
  `ElapsedGameTime = TimeSpan.Zero` between `BeginRun()` and the host loop. CNA's `Run` does not, so
  the measured order here is `initialize load_content begin_run update draw update …` where XNA's is
  `initialize … begin_run update(0) update draw …`. Synthesising the missing call would fabricate a
  lifecycle callback CNA never delivered, which this project does not do.

## Corrected by the CNA C ABI 0.21.0 migration

Two of the statements above were true of the CNA `0.7.0` artifact and are no longer true of the
current one. Both corrections are recorded here rather than by editing the sentences they replace,
because what the audit measured at the time is itself evidence.

- **The priming `Update` exists now.** The second "measured deviation of CNA's loop" above says
  CNA's `Run` does not deliver `RunGame`'s zero-elapsed priming `Update`. On CNA `0.21.0` it does,
  and the measured order is `initialize load_content begin_run update(0,0) draw update(0,step) …`.
  The deviation is retired on `Run` and replaced by a narrower one on `Tick`: CNA delivers the
  priming update from the **first frame step**, so a Game driven only by `Tick` sees it, where
  XNA's `Tick` has none. CNA also draws after the priming update, where XNA's first draw follows the
  first loop update.
- **"The fixed step advances `TotalGameTime` by exactly one `TargetElapsedTime` per tick" was a
  misreading of the IL.** `IL_0180` writes `gameTime.TotalGameTime = this.totalGameTime` **before**
  the `finally` at `IL_01e8` adds the step, so an Update is handed the total accumulated before its
  own step and the first advancing Update reports zero. CNA `0.7.0` reported the post-increment
  value and this document and its test both took that for XNA's behaviour; CNA `0.21.0` reports the
  pre-increment value the IL specifies, which is what exposed the error. The test now asserts the
  IL's rule directly — every Update's `TotalGameTime` is the sum of every earlier Update's
  `ElapsedGameTime` — and is named for it. Full record in
  `docs/native-abi-migration-evidence.md`.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1786 | 1787 |
| `TOTAL_DIAGNOSTICS` | 279 | 277 |
| `MISSING_MEMBER` | 117 | 116 |
| `OVERLOAD_MAPPING_MISMATCH` | 46 | 45 |
| `Game` remainder | 8 | 7 |
| bound CNA functions | 51 | 52 |
| behaviour observations | 484 | 491 |

`COMPLETE_TYPES` 136, `PARTIAL_TYPES` 6, `MISSING_TYPES` 115, allowlist 0 and every other structural
category are unchanged. `Game` stays partial: `Content`, `Dispose(Boolean)`, `Finalize`, `IsActive`,
`LaunchParameters`, `ShowMissingRequirementMessage` and `Window` remain.

## What this does not claim

`Tick` adds no host-event processing, no window message pump, no `GameWindow`, no `Guide` or
GamerServices surface, and no `IsActive`. Those are precisely the three steps `RunOneFrame` has and
`Tick` does not, and none of them is fabricated here.
