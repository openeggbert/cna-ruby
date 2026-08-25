# Foundation 41 — the four canonical Game events

`Activated`, `Deactivated`, `Exiting` and `Disposed`, plus the three protected raisers XNA declares
for the first three. Seven of `Game`'s twenty-one deferred members, closed together because they are
one mechanism.

This is the milestone the deferred graphics-device producer made room for: the producer is blocked
on an architecture conflict, not on missing CNA signals, so the next honest work was the *other*
already-existing canonical lifecycle surface — and the pinned C ABI really does carry it.

## The exact CLR surface

`Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`.

| Member | Kind | Type / signature |
| --- | --- | --- |
| `Activated` | event | `System.EventHandler`1<System.EventArgs>` |
| `Deactivated` | event | same |
| `Exiting` | event | same |
| `Disposed` | event | same |
| `OnActivated` | method, **protected** | `(object sender, EventArgs args)` |
| `OnDeactivated` | method, **protected** | same |
| `OnExiting` | method, **protected** | same |

There are **three** raisers and four events. `Disposed` has no `OnDisposed`: the IL raises it inline.

## Three facts a summary would get wrong

### 1. `OnExiting` raises with a **null** sender

`OnActivated` and `OnDeactivated` load `ldarg.0` — `this` — as the delegate's sender. `OnExiting`
loads **`ldnull`**:

```
OnActivated    IL_000e:  ldarg.0     // this
OnDeactivated  IL_000e:  ldarg.0     // this
OnExiting      IL_000e:  ldnull      // null
```

So XNA really does raise `Exiting` with a null sender while the other two raise with the `Game`. A
handler written against XNA may test the sender, so the projection dispatches `nil` rather than
tidying the inconsistency away.

### 2. All three declare a `sender` parameter and none of them reads it

The declared `sender` is dead in every one of the three bodies — only `args` (`ldarg.2`) is passed
through. A subclass calling the base with some other sender still raises with the `Game` (or, for
`Exiting`, with null). This is the same shape Foundation 38 already recorded for
`GameComponent.OnEnabledChanged`, and it is reproduced rather than corrected.

### 3. `Activated`/`Deactivated` are edge-triggered, and the flag is written first

```csharp
// HostActivated
if (isActive) return;
isActive = true;
OnActivated(this, EventArgs.Empty);
```

`HostDeactivated` is the mirror image. So activating an already-active game raises nothing, and a
handler always observes the new `isActive`. The guard lives in the host handler, which in this
binding is CNA's — so the projection relays one raise per delivered signal and adds no guard of its
own. `HostExiting` has no guard at all.

## Where each event comes from here

| Event | Source | Sender | Args |
| --- | --- | --- | --- |
| `Activated` | `cna_game_subscribe(CNA_GAME_EVENT_ACTIVATED)` → `OnActivated` | the `Game` | `EventArgs::Empty` |
| `Deactivated` | `cna_game_subscribe(CNA_GAME_EVENT_DEACTIVATED)` → `OnDeactivated` | the `Game` | `EventArgs::Empty` |
| `Exiting` | `cna_game_subscribe(CNA_GAME_EVENT_EXITING)` → `OnExiting` | **`nil`** | `EventArgs::Empty` |
| `Disposed` | `Game#Dispose` itself | the `Game` | `EventArgs::Empty` |

### Why `Exiting` is not the callback that was already bound

`CNA_GameCallbacks::exiting` has been bound since the first native milestone and routed to a
`Game#__cna_exiting` that did nothing. Using it would have cost no ABI change at all, and it is the
wrong signal. Measured side by side:

| Scenario | `CNA_GameCallbacks::exiting` | `CNA_GAME_EVENT_EXITING` |
| --- | --- | --- |
| `Run`, then `Exit()` | fires | **fires** |
| `RunOneFrame`, never exits | fires | does not fire |
| never run at all | fires | does not fire |

The callback is a *teardown* hook; XNA raises `Game.Exiting` only when the host actually exits its
loop. The C ABI says so itself — the callback "can stop the game by failing, while these handlers
only observe" — and XNA's `Exiting` event cannot veto anything. The observer is the faithful source.

### Why `Disposed` is not relayed either

`CNA_GAME_EVENT_DISPOSED` exists and fires, but only once a native host exists. A `Game` that is
constructed and disposed without ever running has no host, and XNA raises `Disposed` for **every**
disposal. So `Dispose` raises it directly, at the position the IL puts it: after the components and
the graphics device manager are disposed and after `UnhookDeviceEvents()`.

Two deviations, both inherited from `Game#Dispose` rather than introduced here:

- XNA's `Dispose(Boolean)` carries **no disposed guard**, so calling `Dispose()` twice runs the whole
  body twice and raises `Disposed` twice — the same absence Foundation 38 recorded for
  `GameComponent`. This binding's `Dispose` returns early because native destruction is not
  repeatable, so the event is raised **once**.
- XNA's body runs under `Monitor.Enter(this)`. That belongs to `Dispose(Boolean)`, still one of
  Game's missing members, and is not taken here.

## The measured order

One ordered log across a real run, HEADLESS:

```
initialize  load_content  begin_run  Activated  update  draw  update  Exiting  end_run
unload_content  Disposed
```

`Activated` after `BeginRun` and before the first `Update`; `Exiting` after the `Update` that
requested the exit and before `EndRun`; `Disposed` at disposal. Each exactly once.

`Deactivated` never fires in HEADLESS, and nothing fabricates one. The event exists, has a reader,
and is raised by the runtime if and when the runtime deactivates — which on this host it does not.

## Native boundary

Two symbols bound, both already exported by the reviewed library:

```c
CNA_C_API CNA_Result cna_game_subscribe(CNA_Handle, CNA_GameEvent, CNA_GameEventCallback,
                                        void*, CNA_GameEventRegistrationHandle*);
CNA_C_API CNA_Result cna_game_unsubscribe(CNA_GameEventRegistrationHandle);
```

plus one callback type, `CNA_GameEventCallback`, and the four `CNA_GAME_EVENT_*` identities.

Three subscriptions are created with the host and released **before** `cna_game_destroy`; releasing
them is what stops CNA calling into a Ruby closure afterwards. The closures are kept alive by the
host for exactly as long as the registrations are.

`CNA_GameEventCallback` returns `void`, so a failure has nowhere to go. An exception from a handler
is captured the way a lifecycle callback's is and re-raised by the next native call — **nothing
escapes into C**. The owner-thread check is kept, because every callback has it. The device-borrow
prologue is deliberately *not* run: these arrive between lifecycle callbacks, and no borrowed
`GraphicsDevice` is promised outside one.

CNA ABI **39 / 124 / 290 / 290 / 2 / 59** → **41 / 132 / 290 / 290 / 3 / 63**. No CNA source was
changed and no new native binary was built.

## The scoreboard

| | Before | After |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1773 | **1780** |
| `MISSING_MEMBER` | 130 | **123** |
| `OVERLOAD_MAPPING_MISMATCH` | 51 | **48** |
| `TOTAL_DIAGNOSTICS` | 297 | **287** |
| `EVENT_IDENTITIES` | 13 | **17** |
| `EVENT_OWNER_TYPES` | 5 | **6** |
| `TARGET_TYPES` / `COMPLETE_TYPES` / `PARTIAL_TYPES` | 142 / 136 / 6 | unchanged |

The overload count fell by exactly three because three of the seven closed members are methods; the
four events are of `event` kind and only move `MISSING_MEMBER`.

## What this does not claim

`IsActive` stays deferred and is **not** implied by `Activated`/`Deactivated`. XNA's property is

```csharp
bool guideVisible = false;
if (GamerServicesDispatcher.IsInitialized) guideVisible = Guide.IsVisible;
return isActive ? !guideVisible : false;
```

which reaches the GamerServices runtime this binding does not have. The events read and write the
private `isActive` field, not the property, so closing them settles nothing about it.

`Game` remains a partial type with fourteen deferred members: `Tick`, `SuppressDraw`,
`ResetElapsedTime`, `Dispose(Boolean)`, `Finalize`, `ShowMissingRequirementMessage`,
`LaunchParameters`, `InactiveSleepTime`, `IsMouseVisible`, `TargetElapsedTime`, `IsFixedTimeStep`,
`Window`, `IsActive` and `Content`. No component, timing, window or content behaviour was touched.
