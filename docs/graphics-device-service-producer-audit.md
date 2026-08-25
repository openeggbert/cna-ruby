# The `IGraphicsDeviceService` producer audit

Foundation 40 completed the contract. This is the separate question it deliberately did not answer:
**does `GraphicsDeviceManager` provide the service?**

The answer is **deferred**, and the reason is not the one that was expected. Every native signal the
producer needs already exists in the pinned CNA C ABI. What blocks it is that CNA's own runtime is
already the producer, into a container this binding cannot reach and does not own.

## The exact XNA producer, from IL

`Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`.

```
.class public auto ansi beforefieldinit Microsoft.Xna.Framework.GraphicsDeviceManager
       extends [mscorlib]System.Object
       implements Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService,
                  [mscorlib]System.IDisposable,
                  Microsoft.Xna.Framework.IGraphicsDeviceManager
```

### Constructor registration, in order

`.ctor(Game game)`, 228 bytes:

1. field initialisers **before** `Object::.ctor()` — `synchronizeWithVerticalRetrace = true`,
   `depthStencilFormat = 2`, `backBufferWidth/Height` from the two static defaults (800 × 480);
2. `base()`;
3. `if (game == null) throw new ArgumentNullException("game", Resources.GameCannotBeNull)`;
4. `this.game = game`;
5. **duplicate check** — `if (game.Services.GetService(typeof(IGraphicsDeviceManager)) != null)
   throw new ArgumentException(Resources.GraphicsDeviceManagerAlreadyPresent)`. Note it tests
   **only** `IGraphicsDeviceManager`, never `IGraphicsDeviceService`;
6. `game.Services.AddService(typeof(IGraphicsDeviceManager), this)` — **first**;
7. `game.Services.AddService(typeof(IGraphicsDeviceService), this)` — **second**;
8. three `Game.Window` subscriptions — `ClientSizeChanged`, `ScreenDeviceNameChanged`,
   `OrientationChanged`;
9. `this.graphicsProfile = ReadDefaultGraphicsProfile()`.

Both keys, both `this`, both inside the constructor, after the checks and before the window
subscriptions.

### Which members are explicit, and which are not

This is the question the *explicit interface implementation precedent* was raised for, and the
answer is that the precedent is **not needed for the service**:

| Interface | Members | Declaration |
| --- | --- | --- |
| `IGraphicsDeviceService` | `GraphicsDevice`, and the four device events | `public hidebysig newslot specialname virtual final` — **implicit** |
| `IGraphicsDeviceManager` | `CreateDevice`, `BeginDraw`, `EndDraw` | `private … .override` — **explicit** |
| `System.IDisposable` | `Dispose()` | `private … .override` — **explicit** |

So all five service members are ordinary public members of `GraphicsDeviceManager` and would project
as ordinary public Ruby members. The three `IGraphicsDeviceManager` members and `Dispose()` are
explicit, and an explicit implementation projects to no member — the rule `ReadOnlyCollection`'s
twelve and `Collection`'s fourteen already follow, and the one Foundation 36 already recorded for
this exact type. Should a future milestone need them callable, the established **private Ruby
protocol** precedent that `PackedVector` set applies unchanged; nothing new had to be invented, and
nothing was.

### `GraphicsDevice` availability, exactly

`get_GraphicsDevice` is `ldfld device` and nothing else — a bare field read. The field is written in
exactly three places:

| Site | Writes |
| --- | --- |
| private `CreateDevice(GraphicsDeviceInformation)` | `null` first if a device exists, after `Dispose()`ing it; then the new device |
| `Dispose(bool)` | `null`, after disposing |

So the CLR property answers **null** from construction until the first device creation, non-null
after it, null again across a re-creation, and null after disposal. It is never a permanently
allocated object.

### Where the four events are actually raised

| Service event | Raised by | Source |
| --- | --- | --- |
| `DeviceCreated` | `OnDeviceCreated(this, EventArgs.Empty)` | the tail of private `CreateDevice`, after `ConfigureTouchInput` |
| `DeviceDisposing` | `OnDeviceDisposing(this, EventArgs.Empty)` | `HandleDisposing`, subscribed to **`GraphicsDevice.Disposing`** |
| `DeviceResetting` | `OnDeviceResetting(this, EventArgs.Empty)` | `HandleDeviceResetting`, subscribed to **`GraphicsDevice.DeviceResetting`** |
| `DeviceReset` | `OnDeviceReset(this, EventArgs.Empty)` | `HandleDeviceReset`, subscribed to **`GraphicsDevice.DeviceReset`** |

Three of the four are pure relays of the device's own events. In every case the sender is **the
manager**, not the device, and the args are always `EventArgs.Empty` — each `Handle*` discards the
`sender` and `e` it was given. (`HandleDeviceLost`, subscribed to `GraphicsDevice.DeviceLost`, is a
bare `ret`: XNA raises no service event for device loss.)

### What `Game` does with them

`Game.Initialize` is 78 bytes:

```
HookDeviceEvents();
while (notYetInitialized.Count > 0) { notYetInitialized[0].Initialize(); notYetInitialized.RemoveAt(0); }
if (graphicsDeviceService != null && graphicsDeviceService.GraphicsDevice != null) LoadContent();
```

`HookDeviceEvents` sets the private field from `Services.GetService(typeof(IGraphicsDeviceService))`
and, when it is non-null, subscribes four private handlers in the order `DeviceCreated`,
`DeviceResetting`, `DeviceReset`, `DeviceDisposing`. Of those, `DeviceResetting` and `DeviceReset`
are bare `ret`; `DeviceCreated` calls `LoadContent()`; `DeviceDisposing` calls `content.Unload()`
then `UnloadContent()`.

**XNA calls `LoadContent` exactly once at startup, and the event is not what does it.** `RunGame` is

```
graphicsDeviceManager = Services.GetService(typeof(IGraphicsDeviceManager)) as IGraphicsDeviceManager;
if (graphicsDeviceManager != null) graphicsDeviceManager.CreateDevice();   // DeviceCreated raised here
Initialize();                                                             // HookDeviceEvents subscribes here
inRun = true; BeginRun(); …
```

The device is created *before* `HookDeviceEvents` subscribes, so `Game.DeviceCreated` does not run
for the first device. The single call comes from the `Initialize` tail. The event path only fires on
a later re-creation.

## What the pinned CNA C ABI actually provides

Read from the 59 headers byte-verified against CNA revision `a09196a6…`, and confirmed against the
2861 exported symbols of the reviewed `libcna_c_api.so` (SHA-256 `c62949d2…`).

**Every signal the producer needs exists.** This audit expected to record
`PRODUCER_RUNTIME_MISSING` and cannot:

```c
/* CNA/C/runtime_graphics_manager.h */
#define CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DEVICE_CREATED   UINT32_C(1)
#define CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DEVICE_DISPOSING UINT32_C(2)
#define CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DEVICE_RESET     UINT32_C(3)
#define CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DEVICE_RESETTING UINT32_C(4)

CNA_C_API CNA_Result cna_graphics_device_manager_subscribe(…);   /* exported */
```

whose own documentation says: *"The four device events are also the canonical graphics-device-service
events, so subscribing here is what a consumer of that service would observe."*

And the service registration is not missing either — it has already happened:

```c
/* CNA/C/runtime_components.h */
#define CNA_GAME_SERVICE_TYPE_GRAPHICS_DEVICE_MANAGER UINT32_C(0)
#define CNA_GAME_SERVICE_TYPE_GRAPHICS_DEVICE_SERVICE UINT32_C(1)
CNA_C_API CNA_Result cna_game_services_contains_ext(…);          /* exported */
```

`cna_graphics_device_manager_create` — which this binding already calls — *"registers it as the
game's graphics device manager **and graphics device service**"*.

### Measured, not read

Probing `cna_game_services_contains_ext` from inside each lifecycle callback of a real run:

| Callback | `GRAPHICS_DEVICE_MANAGER` | `GRAPHICS_DEVICE_SERVICE` |
| --- | --- | --- |
| `initialize` | **true** | **true** |
| `load_content` | true | true |
| `begin_run` | true | true |
| `update` | true | true |
| `unload_content` | false | false |

Both services are registered **before the first callback**, and disposal unregisters both. With no
manager attached, both are false throughout. `LoadContent` is delivered **exactly once** in both
configurations.

## The architecture conflict

CNA's native `Game` **is** the XNA `Game`. Its hook table documents the contract explicitly:

> *"The order is a contract, not an accident: this [`initialize`] runs, then the runtime initializes
> its components and creates the device, and only then does `CNA_GameCallbacks::load_content` run."*

So Ruby's `Game.Initialize` is not XNA's `Game.Initialize` — it is the *body of the override* that
CNA's `Game.Initialize` invokes. CNA has already registered both services, already run its own
`HookDeviceEvents`, already created the device, and already performed the conditional `LoadContent`,
surfacing the result as the `load_content` callback.

There are therefore **two service containers**: CNA's native one, which is the one the code that
reads it actually consults, and this binding's managed `GameServiceContainer`, which nothing native
can see. And the C ABI closes the gap deliberately rather than accidentally:

> *"A removal cannot be undone from here, and there is deliberately no registration route. … a C
> caller cannot name a C++ type to key the entry by, and cannot author an object implementing the
> C++ interface a native consumer would then call through."*

### The double call, measured rather than predicted

Restoring XNA's exact `Initialize` tail — the service is present, so the only open question was
whether the device is non-null at that moment — gives:

```
device at initialize [nil?, IsDisposed, has borrowed handle]: false, false, true
LoadContent calls = 2
```

XNA calls it **once**. CNA delivers **once**. Ruby currently delivers **once**. Registering the
manager in the managed container and restoring the guard makes it **two**, because the managed
`Initialize` tail does again what CNA's `Initialize` tail already did.

This cannot be hidden behind a guard: XNA's own lifecycle contains no such guard, and inventing one
would be fabricating a behaviour to conceal a duplicate. Registering into the managed container does
not *enable* the XNA lifecycle here — it *duplicates* it.

## Outcome: deferred producer

Per the two permitted outcomes, this is **B**, taken in full:

- `GraphicsDeviceManager` stays **unregistered** — nothing is added to `Game.Services`.
- Its interface conformance stays **unclaimed** — it includes neither `Graphics::IGraphicsDeviceService`
  nor `IGraphicsDeviceManager`, so `is_a?` stays false and the `GameServiceContainer` projection of
  CLR assignability keeps refusing it, by the general rule and with no special case.
- `Game.Initialize` keeps omitting `HookDeviceEvents` and the conditional `LoadContent`.
- The contract itself stays **complete**.

No intermediate producer was built. In particular the four device events were **not** projected onto
`GraphicsDeviceManager`, even though `cna_graphics_device_manager_subscribe` would supply them
faithfully: doing so would let the type claim conformance to a service that nothing registers, which
is the intermediate state this audit was told to refuse.

**The blocker is not a missing CNA capability, and no CNA change is requested.** It is that the
managed `Game`/`GameServiceContainer` in this binding and the native `Game`/service container in CNA
are two different objects playing the same role, and only one of them is the one XNA's lifecycle
logic actually runs against. Making the managed container authoritative would be a material
Game/graphics lifecycle redesign — the managed `Game` would have to stop being a callback façade
over CNA's `Game` and start being the `Game`, which is the opposite of how every milestone so far
has been built.

## What `DrawableGameComponent` still needs

Unchanged by this milestone, and now measured rather than argued: its nine
`IGraphicsDeviceService` member edges are satisfied by a *type* that exists and blocked by an
*object* that does not, which the frontier reports as `INTERFACE_PRODUCER_MISSING`. Completing it
today would ship a type whose `Initialize` throws
`InvalidOperationException(MissingGraphicsDeviceService)` the moment `Game.Initialize` reaches it.
