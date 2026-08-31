# Foundation 45 — `Game.IsActive`

Derived from the pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, and
`Microsoft.Xna.Framework.GamerServices.dll`, SHA-256
`7c6effed97aa25a95c5e095d9c261f5581e402180cc073271a367b9eef79c8af`, both disassembled with `ikdasm`.

Three previous handoffs deferred this property with the same sentence: `cna_game_get_is_active`
answers the *field*, XNA's property is `isActive && !Guide.IsVisible`, and projecting the field alone
would "claim a property whose defining subtlety it cannot observe". The audit this milestone was
asked to do found that it can observe it. **Outcome A, exact**: every term of the pinned expression
has exactly one canonical CNA route, and the expression is implemented as written.

## The pinned expression

`Game.get_IsActive` is thirty bytes and is not a field read:

```
IL_0000: ldc.i4.0 ; stloc.0                       // bool guideVisible = false
IL_0002: call GamerServicesDispatcher::get_IsInitialized()
IL_0007: brfalse.s IL_000f
IL_0009: call Guide::get_IsVisible() ; stloc.0    // only when initialised
IL_000f: ldarg.0 ; ldfld bool Game::isActive
IL_0015: brfalse.s IL_001c
IL_0017: ldloc.0 ; ldc.i4.0 ; ceq ; ret           // return !guideVisible
IL_001c: ldc.i4.0 ; ret                           // return false
```

So `IsActive == isActive && !(GamerServicesDispatcher.IsInitialized && Guide.IsVisible)`.

From the GamerServices assembly:

- `GamerServicesDispatcher.get_IsInitialized` is `packetBuffer != null`. The field is set by
  `GamerServicesDispatcher.Initialize(IServiceProvider)`, which itself throws
  `InvalidOperationException(GamerServicesAlreadyInitialized)` if called twice.
- `Guide.get_IsVisible` **throws** `InvalidOperationException(GamerServicesNotInitialized)` when the
  dispatcher is not initialised, and otherwise answers `isVisible || forceGuideVisible`. The
  `IsInitialized` guard in `get_IsActive` is the only reason the property never throws, which is why
  the projection reproduces the guard rather than the short-circuit a reader might assume.

The backing field `isActive` is written in exactly two places in the whole assembly:
`Game.HostActivated` and `Game.HostDeactivated`. Each returns early when the field already holds the
value it would write, then writes the field, and **only then** raises `OnActivated`/`OnDeactivated`.
Nothing else writes it, so a `Game` that has never run reports the CLR default `false`.

## The three canonical routes

| XNA term | canonical CNA route | shape |
| --- | --- | --- |
| `isActive` | `cna_game_get_is_active` | `(CNA_Handle, CNA_Bool*)` |
| `GamerServicesDispatcher.IsInitialized` | `cna_gamer_services_dispatcher_get_is_initialized` | `(CNA_Bool*)` |
| `Guide.IsVisible` | `cna_guide_get_is_visible` | `(CNA_Bool*)` |

All three were already exported by the reviewed library and none was bound. The two GamerServices
routes take **no handle**, which is the right shape for the CLR statics they project: they are
measured to answer with no Game in the process at all, and they answer off the owner thread. That is
what makes the IL's evaluation order — both GamerServices terms first, `isActive` second —
projectable literally rather than reordered into a short-circuit.

`cna_game_get_is_active` is measured to track XNA's field exactly. Over a real run it is false before
the loop starts and **already true inside the `Activated` handler**, which is precisely where
`HostActivated` leaves it: written before the event is raised.

```
[:Activated, true]  [:update, true]  [:draw, true]  [:update, true]   after run: true
```

## Why `isActive` is not mirrored in managed state

Foundation 42 kept `IsFixedTimeStep`, `TargetElapsedTime`, `InactiveSleepTime` and `IsMouseVisible`
as managed state, and each of their getters is also one `ldfld`. `isActive` is the mirror image of
those four: they are written by the **consumer** and read by the loop, so managed state is
authoritative; `isActive` is written by the **host** and only read by the consumer, so the host is
authoritative. That is the `SuppressDraw` case, not the `TargetElapsedTime` case, and it takes the
same answer — forward to the canonical route rather than keep a shadow copy of a flag this side does
not own.

The seam this creates is tested rather than assumed. The protected raisers this binding exposes are
the *second half* of `HostActivated`; they do not write any state. So raising `Activated` by hand —
which a subclass may do, because the raiser is protected and overridable — must not make the game
report itself active, and `test/test_game_events.rb` now asserts exactly that.

## Nothing is fabricated, and nothing is claimed

`cna_guide_get_is_visible` is **asked**, and what it answers is CNA's. In the reviewed artifact it
answers false, and `cna_guide_set_is_visible` is accepted — result `CNA_RESULT_SUCCESS` — without
ever being reflected back by the getter, even after `cna_gamer_services_dispatcher_update`. So no
guide can be raised behind this expression in this artifact. That is a measured property of the
runtime, recorded here and in the behaviour corpus, **not** an assumption compiled into the
projection: if a later artifact can raise a guide, this expression already answers correctly.

Because the guide branch cannot be reached through CNA, the expression is proved *wired* instead of
merely exercised. Two tests drive the private route readers directly and assert the full six-row
truth table, including the one case the guide term decides and the case that proves the guide route
is not read at all while the dispatcher is uninitialised. Both are classified
`RUBY_MAPPING_QUALIFICATION`: they qualify the mapping, not the runtime.

No GamerServices type is invented. The whole `Microsoft.Xna.Framework.GamerServices` namespace
contributes exactly **one** type to the selected profile — `GamerServicesComponent` — and it is
still missing. Neither `Guide` nor `GamerServicesDispatcher` is a selected identity, so reading their
routes adds no type, no constant and no `::System` namespace.

## Recorded deviations

- **Owner thread.** `cna_game_get_is_active` is owner-thread bound and XNA's getter is not, so the
  property raises `CNA::OwnerThreadError` off the owner thread **once a host exists** and answers
  normally before one does. Same asymmetry already recorded for the timing setters,
  `FrameworkDispatcher` and `Tick`.
- **Disposal.** XNA's `Dispose(Boolean)` does not touch `isActive`, so a disposed XNA `Game` still
  answers its last value. Here the native game it would have to ask no longer exists, so the
  property raises `CNA::DisposedObjectError`, consistent with every other native-forwarding member.
  Answering a fabricated `false` would be worse than raising.
- **No host.** A `Game` that has never run answers `false` and **no native host is created**. That is
  exact — XNA's field is at its CLR default and its getter allocates nothing — and it is worth
  stating because a getter that conjured a native game would be a side effect the pinned single
  `ldfld` does not have.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1787 | 1788 |
| `TOTAL_DIAGNOSTICS` | 277 | 276 |
| `MISSING_MEMBER` | 116 | 115 |
| `Game` remainder | 7 | 6 |
| bound CNA functions | 52 | 55 |
| behaviour observations | 491 | 498 |

`OVERLOAD_MAPPING_MISMATCH` stays 45 — `IsActive` is a property, not a method.
`COMPLETE_TYPES` 136, `PARTIAL_TYPES` 6, `MISSING_TYPES` 115, allowlist 0 and every other structural
category are unchanged. `Game` stays partial: `Content`, `Dispose(Boolean)`, `Finalize`,
`LaunchParameters`, `ShowMissingRequirementMessage` and `Window` remain.

## What this does not claim

Reading two GamerServices routes is not a GamerServices runtime. There is no `Guide`, no
`GamerServicesDispatcher`, no `GamerServicesComponent`, no gamer, profile, presence, achievement,
message box, keyboard-input screen or trial-mode surface in this binding; nothing here initialises
the dispatcher, and nothing here can show or hide a guide.
