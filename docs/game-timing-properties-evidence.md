# Foundation 42 — Game's timing and presentation properties

`IsFixedTimeStep`, `TargetElapsedTime`, `InactiveSleepTime` and `IsMouseVisible`. Four more of
`Game`'s deferred members, closed together because they are one mechanism and because CNA carries an
exact route for every one of them.

## They are managed state, and that is the whole design

Every one of the four getters is a single instruction in the pinned
`Microsoft.Xna.Framework.Game.dll` (SHA-256 `b5dffdd8…`):

```
get_IsFixedTimeStep     ldfld  bool     Game::isFixedTimeStep
get_TargetElapsedTime   ldfld  TimeSpan Game::targetElapsedTime
get_InactiveSleepTime   ldfld  TimeSpan Game::inactiveSleepTime
get_IsMouseVisible      ldfld  bool     Game::isMouseVisible
```

They are **fields the host loop reads**, not queries into a running host. So the projection keeps
the managed state authoritative: every getter answers on a `Game` that has never run — which is what
XNA does — and no getter creates a host. Each setter writes the field and then pushes the value down
to CNA *if and when* a native host exists.

That is also what makes the setters meaningful before the first `Run`. `CNA_GameCreateInfo` carries
`is_fixed_time_step` and `target_elapsed_time_ticks`, and the host is now created from the Game's own
state instead of the hardcoded pair it used to carry. The other two have no slot there, so they are
pushed the moment the host exists. The defaults are unchanged, because the hardcoded pair was already
XNA's.

## The defaults, from the constructor

| Field | IL | Value |
| --- | --- | --- |
| `isFixedTimeStep` | `ldc.i4.1` field initialiser, before the base constructor | `true` |
| `targetElapsedTime` | `TimeSpan.FromTicks(0x28b0b)` | 166 667 ticks |
| `inactiveSleepTime` | `TimeSpan.FromMilliseconds(20)` | 200 000 ticks |
| `isMouseVisible` | never assigned | CLR default `false` |

`0x28b0b` is 166 667, which is *not* one sixtieth of a second: `1.0 / 60` is a different Float. The
projection stores the tick-derived value and a test asserts the two differ, so nobody later
"simplifies" it into `1.0/60`.

## The validation, which differs between the two TimeSpans

```csharp
// set_TargetElapsedTime            op_LessThanOrEqual
if (value <= TimeSpan.Zero) throw new ArgumentOutOfRangeException("value", …TargetElaspedCannotBeZero);

// set_InactiveSleepTime            op_LessThan
if (value <  TimeSpan.Zero) throw new ArgumentOutOfRangeException("value", …InactiveSleepTimeCannotBeZero);
```

So **`TargetElapsedTime` refuses zero and `InactiveSleepTime` accepts it** — despite the latter's CLR
resource being named `InactiveSleepTimeCannotBeZero`. The resource name is wrong about its own
comparison and the IL is not. CNA's two routes agree exactly: one refuses a step that is not
positive, the other refuses a negative duration.

`set_IsFixedTimeStep` is a bare `stfld` with no validation whatsoever. `set_IsMouseVisible` writes
the field and then, **only when `Window` is not null**, forwards to `Window.IsMouseVisible`;
`GameWindow` is still deferred here, so the window it forwards to is CNA's own — the route is
documented as showing or hiding the cursor over the game window — and the null check becomes the
only form of the same question this binding can ask: whether a native host exists yet.

`ArgumentOutOfRangeException` maps to `RangeError`, which is the register's existing pairing.

## Two recorded deviations

- **Rounding.** A CLR `TimeSpan` carries whole ticks and this binding projects `TimeSpan` as `Float`
  seconds, so seconds are rounded to the nearest tick on the way down rather than truncated.
- **Owner thread.** The native push routes are owner-thread bound and XNA's setters are not, so a
  setter called off the owner thread raises once a host exists and does not before. The asymmetry is
  the native contract's; it is asserted rather than hidden.

## Native boundary

Eight symbols bound, all already exported:

```
cna_game_{get,set}_is_fixed_time_step
cna_game_{get,set}_target_elapsed_time_ticks
cna_game_{get,set}_inactive_sleep_time_ticks
cna_game_{get,set}_is_mouse_visible
```

The four getters are bound for **verification**, not for the projection: the Ruby getters read
managed state, and the native getters are what the tests use to prove the managed state really
reached the runtime. Values set before the host exists arrive through the create info and the initial
push; values set afterwards arrive immediately.

CNA ABI **41 / 132 / 290 / 290 / 3 / 63** → **49 / 156 / 290 / 290 / 3 / 63**. No CNA source changed
and no native binary built.

## The scoreboard

| | Before | After |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1780 | **1784** |
| `MISSING_MEMBER` | 123 | **119** |
| `TOTAL_DIAGNOSTICS` | 287 | **283** |

Types, complete, partial, event counts and every other structural counter unchanged; the one
`PROPERTY_MAPPING_MISMATCH` is still `GraphicsDevice::Viewport`, which is unrelated and pre-existing.

## Game's remaining ten

`Tick`, `SuppressDraw`, `ResetElapsedTime`, `Dispose(Boolean)`, `Finalize`,
`ShowMissingRequirementMessage`, `LaunchParameters`, `Window`, `IsActive`, `Content`.

`IsActive` is the one that looks closest and is not. XNA's property is

```csharp
bool guideVisible = false;
if (GamerServicesDispatcher.IsInitialized) guideVisible = Guide.IsVisible;
return isActive ? !guideVisible : false;
```

`cna_game_get_is_active` answers the *field*, not that expression. On a host with no GamerServices
the two agree, but the projection would be claiming a property whose defining subtlety it cannot
observe, so it stays deferred.

`LaunchParameters` has canonical CNA routes for every operation and is blocked on the type: it
derives from `Dictionary<string, string>`, the last purely-decisional BCL cluster.
