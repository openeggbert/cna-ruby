# The graphics runtime, member by member

Every member `GraphicsDevice` and `GraphicsDeviceManager` still owe, audited **one family at a
time** against the pinned XNA IL and against CNA 0.21.0's real exports.

## Why this document exists

`plan.md` and `NEXT.md` both carried, for eleven milestones, a single sentence that stood in for all
of it: *"the graphics runtime is the large remaining area … which is why a qualification artifact
with a real renderer is the single largest lever this project has left."* Two real-renderer
artifacts were qualified at Native frontier 6 and Foundation 80, and the remainder did not move,
because the sentence was never a measurement. It was a **blanket blocker** — one word covering
thirty-five members with thirteen different situations behind them — and this project already has a
register full of those: eleven `NATIVE_RUNTIME` deferrals and six `RUNTIME_DATA` ones that each
turned out to name something other than the type they were attached to.

So the rule that retired those applies here too, and it is applied here member by member: **audit
before deferring, and say what the blocker names.**

What the audit found, stated up front so nothing depends on reading to the end:

> **Of the thirty-five members the two types owe, thirty have a CNA 0.21.0 route that supports the
> exact XNA behaviour, and five are blocked by one thing — the invented display data behind
> `Graphics.GraphicsAdapter`, whose own blocker is the measured upstream ordering defect in
> `docs/graphics-adapter-ordering-upstream-defect.md`.** No member is blocked by "the renderer",
> and none is blocked by the graphics runtime as such.

**One of those five was in the buildable column when this document was first written, and measuring
it is what moved it.** `GraphicsDevice.DisplayMode` has a route, the route succeeds, and the answer
is invented — see the family below. That is the audit's own rule turned on the audit: a route
existing is not a measurement, and the difference cost one member.

Method, for each family: read the pinned `Microsoft.Xna.Framework.Graphics.dll` IL (SHA-256
`560080fc…`) or `Microsoft.Xna.Framework.dll` IL (`38e7093f…`) for what the member *is*; then
`grep` the canonical headers under `~/deps/cna-c-abi-0.21.0/include` and `nm -D --defined-only` the
artifact for what CNA has; then decide. Where the two disagree, the disagreement is recorded as a
deviation with the measurement behind it, never smoothed over.

---

## `GraphicsDevice`

### `Viewport`'s setter — **done, Foundation 89**

Not a member of the missing list at all: it was the project's single standing
`PROPERTY_MAPPING_MISMATCH`, declared in `selection.json` as `"override": { "set": false }`.

`set_Viewport` is eleven guards — `X < 0`, `Y < 0`, `Width <= 0`, `Height <= 0`, the two bounds
sums against the current render target or the back buffer, the four depth-range comparisons and
`!(MaxDepth >= MinDepth)` — each raising `ArgumentException(ViewportInvalid, "value")`, then one
native `SetViewport` and a cache write. `cna_graphics_device_set_viewport` is the route, and it is
exported by **both** admitted artifacts.

What actually stood in front of it was neither the renderer nor Ruby: `CNA_Viewport` is a 24-byte
aggregate passed **by value**, and the System V x86-64 classification puts an aggregate larger than
two eightbytes in MEMORY — on the stack — where the `by_value` expansion `CNA_StringView` uses
cannot reach. `Manifest.by_value_memory` expands it as the ABI really passes it, the ABI gate
re-derives the shape from the struct's measured `sizeof`, and
`test/test_graphics_device_viewport.rb` measures the call in both directions. See
`docs/graphics-device-viewport-evidence.md`.

**`PROPERTY_MAPPING_MISMATCH` is now zero.**

### The five simple properties — **three of five, done in Foundation 90**

| member | XNA IL | CNA route | verdict |
| --- | --- | --- | --- |
| `GraphicsProfile` | `ldfld _graphicsProfile` | `cna_graphics_device_get_graphics_profile` | **done** |
| `GraphicsDeviceStatus` | native `TestCooperativeLevel`, mapping `D3DERR_DEVICELOST` → `Lost` and `D3DERR_DEVICENOTRESET` → `NotReset` | `cna_graphics_device_get_status` | **done** |
| `PresentationParameters` | `ldfld pPublicCachedParams` | `cna_graphics_device_get_presentation_parameters` | **done**; `PresentationParameters` is projected |
| `DisplayMode` | native `GetDisplayMode`, then **mutates the cached `DisplayMode`** rather than replacing it | `cna_graphics_device_get_display_mode` — exists, succeeds, and answers invented data | **`BLOCKED_UPSTREAM_CNA`** |
| `Adapter` | `ldfld pCurrentAdapter` | — | **`BLOCKED_UPSTREAM_CNA`** |

`Adapter` is one `ldfld`, so nothing about the member is hard. Its *type* is
`Graphics.GraphicsAdapter`, which this binding does not project because every
`cna_graphics_adapter_*` route answers `SUCCESS` with invented values — one adapter,
`"Default Display"`, `\\.\DISPLAY1`, a single 800x480 mode — and Native frontier 6 measured that a
real X11 window and a real GL 4.5 context answer *exactly the same invented values*, because the
adapter list is cached before the video subsystem exists and `cna_graphics_adapters_refresh` refuses
by design. That is an upstream ordering defect, recorded in
`docs/graphics-adapter-ordering-upstream-defect.md`.

**`DisplayMode` is the same defect reached through a different door, and this document said the
opposite until it was measured.** `cna_graphics_device_get_display_mode` is a separate symbol in a
separate header with no mention of adapters, so "the route exists" read as "the member is
buildable". What it actually answers, measured on a game whose back buffer is **320x200**, running
under a real X server whose display is **1280x800**:

| artifact | back buffer | X display | `cna_graphics_device_get_display_mode` | `cna_graphics_adapter_get_current_display_mode` |
| --- | --- | --- | --- | --- |
| `HEADLESS` | 320x200 | — | 800x480, `Color`, aspect 1.6666666 | 800x480, `Color`, aspect 1.6666666 |
| `OPENGL33` under `Xvfb` | 320x200 | 1280x800 | 800x480, `Color`, aspect 1.6666666 | 800x480, `Color`, aspect 1.6666666 |

It is neither the back buffer nor the display, it is byte-identical to the adapter route on both
artifacts, and it does not move when the display does. It is the same no-display fallback, so
projecting the getter would report invented hardware — the exact reason `GraphicsAdapter` is not
projected. The route is not bound and the member is not projected.

`PresentationParameters`, measured the same way in the same run, is the counter-case that makes the
comparison worth anything: it answers **320x200** — the real applied configuration — so this family
is not "CNA cannot answer display questions". One of its two answers is real and one is invented,
and only measuring tells them apart.

### `Clear`'s two remaining overloads — **done, Foundation 91**

`Clear(Color)` is `Clear(DefaultClearOptions, color, 1f, 0)` and the `Vector4` overload converts
through `new Color(color)`, so all three reach one route:
`cna_graphics_device_clear_options(handle, options, color, depth, stencil)`, which is that shape
exactly. `cna_graphics_device_clear_rgba` — four normalised floats, bound when the projection had
only the `Color` overload and no `ClearOptions` — left the manifest with them, because a bound route
without a production call site does not stay.

`DefaultClearOptions` is reproduced from the IL, and XNA's **two** presentation-parameter objects
with it: `pPublicCachedParams`, which the getter hands out and a consumer may mutate, and
`pInternalCachedParams`, which the device reads its own rules from. Collapsing them would let a
consumer change what `DefaultClearOptions` decides.

MEASURED, and one measurement is a limit: **CNA's clear never fails** — not for `Stencil` on a
`Depth24` device, not for `DepthBuffer` on a render target whose depth format is `None` — so XNA's
`CannotClearNullDepth` rule cannot be exercised on these artifacts. It is projected anyway and
proved by a truth table over every declared depth format plus one stub, the way `Game.IsActive`'s
guide term is. See `docs/clear-options-evidence.md`.

### `Present`'s two overloads — **buildable, with one recorded refusal**

`Present()` is `Present(null, null, null)` on the private native three-pointer form.
`Present(Nullable<Rectangle>, Nullable<Rectangle>, IntPtr)` converts each present rectangle into a
`tagRECT` **in a local copy** — `right = width + x`, `bottom = height + y`, so the caller's
rectangle is not mutated — and passes the override window handle through `IntPtr::ToPointer`.

`cna_graphics_device_present(handle)` takes no rectangles and no window handle. So the no-argument
overload is exact, and the three-argument one is exact **for the all-null call** and must refuse
anything else, naming what CNA does not accept. That is the `VideoPlayer.Play(Video)` precedent:
project the member and make it refuse explicitly, rather than defer the member or invent a
behaviour.

### `Reset`'s three overloads — **buildable, with one recorded refusal**

`Reset()` re-applies the cached parameters; `Reset(PresentationParameters)` applies new ones;
`Reset(PresentationParameters, GraphicsAdapter)` also switches adapter.
`cna_graphics_device_reset` and `cna_graphics_device_reset_with_parameters(handle, parameters,
adapter_index)` cover the first two exactly — the adapter index argument is nullable, which is
precisely "keep the current adapter". The third overload's second argument is a `GraphicsAdapter`,
so it inherits `Adapter`'s blocker and refuses for that reason, naming it.

A successful reset raises the device's resetting and reset events in that order, which the header
states and the event family below consumes.

### `DrawUserPrimitives` and `DrawUserIndexedPrimitives` — **buildable, six overloads**

`cna_graphics_device_draw_user_primitives(handle, CNA_UserPrimitives*)` and
`cna_graphics_device_draw_user_indexed_primitives(handle, CNA_UserPrimitives*, CNA_UserIndices*)`
take versioned descriptions by pointer, so no by-value aggregate is involved. The header states
that "the vertex source and the optional declaration together select the canonical overload", which
is exactly the `IVertexType`-versus-explicit-`VertexDeclaration` split XNA's six overloads are.
Sixteen-bit and thirty-two-bit index arrays are `CNA_UserIndices`' own element size.

The managed validation is the same shape as the three device-buffer draw calls that landed in
Foundation 88, plus the array-bounds guards a user array needs.

### `GetBackBufferData`'s three overloads — **buildable, renderer-dependent**

`cna_graphics_device_get_backbuffer_data_rgba8(handle, destination, capacity, out_pixels)` reads the
whole logical back buffer; `cna_graphics_device_get_backbuffer_data_window(handle, readback,
destination, capacity)` reads a window, which is the `Nullable<Rectangle>` overload. Both document
`CNA_RESULT_BUFFER_TOO_SMALL` with **no partial write**, which is what XNA's own capacity guard
means.

Both answer `CNA_RESULT_NOT_SUPPORTED` "when the active renderer has no honest back-buffer
readback" — the `HEADLESS` artifact. That is a **capability** of one artifact rather than a blocker
on the member: the member is projected, the managed guards are exercised on every artifact, and the
pixel assertions run on the artifacts that can produce pixels, exactly as the render-target
readback tests already do through `test/renderer_environment.rb`.

### `Dispose`, `Dispose(Boolean)` and `Finalize` — **buildable, with a documented upstream refusal**

`cna_graphics_device_dispose` exists and **deliberately answers `CNA_RESULT_NOT_SUPPORTED` for a
valid device handle**. The header says why, and it is not a gap:

> The canonical `GraphicsDevice` belongs to the running game, so disposing it through a borrowed
> handle would leave that game drawing into a destroyed device. `cna_game_destroy` performs the
> canonical disposal and `cna_graphics_device_get_is_disposed` observes the resulting state.

That is the same two-owners fact `docs/graphics-device-service-producer-audit.md` recorded for the
service container, and it settles the family rather than blocking it. This binding's device is
already invalidated by the Game's disposal — `IsDisposed` is `@invalidated || game.disposed?` — so
what `Dispose` must project is the *managed* contract: the `Disposing` event, idempotence, and
`GC.SuppressFinalize`. `Finalize` is `protected` and, under this project's standing rule that **no
GC finalizer destroys native state**, projects as a protected member that performs the managed half
only. Both are recorded deviations with the header quotation behind them.

### The six events — **buildable**

| XNA event | CNA route |
| --- | --- |
| `Disposing` | `cna_graphics_device_subscribe_event`, `CNA_GRAPHICS_DEVICE_EVENT_DISPOSING` |
| `DeviceLost` | … `CNA_GRAPHICS_DEVICE_EVENT_DEVICE_LOST` |
| `DeviceReset` | … `CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESET` |
| `DeviceResetting` | … `CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESETTING` |
| `ResourceCreated` | `cna_graphics_device_subscribe_resource_created` |
| `ResourceDestroyed` | `cna_graphics_device_subscribe_resource_destroyed` |

Every one is released by `cna_graphics_device_unsubscribe`, which answers `CNA_RESULT_INVALID_HANDLE`
on a second release. `ResourceCreatedEventArgs` and `ResourceDestroyedEventArgs` are both already
projected complete types.

### `.ctor(GraphicsAdapter, GraphicsProfile, PresentationParameters)` — **`BLOCKED_UPSTREAM_CNA`**

`cna_graphics_device_create(adapter_index, graphics_profile, parameters, out_device)` exists and
creates a caller-owned device outside any Game — the header is explicit that "the returned handle is
accepted everywhere a borrowed device handle is". So the *route* is not the blocker.

The blocker is the first parameter. XNA's constructor takes a `GraphicsAdapter`; CNA's takes the
index that adapter would carry, and this binding does not project `GraphicsAdapter` because the
values behind it are invented. A constructor whose first argument cannot be produced is not
constructible, so this is `Adapter`'s blocker a third time rather than a new one.

---

## `GraphicsDeviceManager`

`docs/graphics-device-service-producer-audit.md` deferred every one of these fifteen, and its
finding is **correct about what it measured and wrong about what it concluded for this family**.
What it measured is that a *managed* `IGraphicsDeviceService` producer cannot be registered: CNA's
native `Game` is the XNA `Game`, `cna_graphics_device_manager_create` already registers the manager
as both services, there are two service containers, and the C ABI closes the registration route on
purpose. All of that still holds, and none of it is about these members.

### The five events and their four raisers — **buildable**

`cna_graphics_device_manager_subscribe` carries five identities, and they are exactly XNA's five
events:

| XNA event | CNA identity |
| --- | --- |
| `Disposed` | `CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DISPOSED` |
| `DeviceCreated` | `…_DEVICE_CREATED` |
| `DeviceDisposing` | `…_DEVICE_DISPOSING` |
| `DeviceReset` | `…_DEVICE_RESET` |
| `DeviceResetting` | `…_DEVICE_RESETTING` |

The header adds the sentence that settles the producer question for this family: *"The four device
events are also the canonical graphics-device-service events, so subscribing here is what a consumer
of that service would observe."* The four `On*` raisers — `OnDeviceCreated`, `OnDeviceDisposing`,
`OnDeviceReset`, `OnDeviceResetting` — are `protected` methods whose IL is one null-check and one
`Invoke` each, which this project has projected fourteen times already for `Game` and
`GameComponent`.

### `PreparingDeviceSettings` and `OnPreparingDeviceSettings` — **buildable**

`cna_graphics_device_manager_subscribe_preparing_device_settings_ext` is the canonical mutable form:
*"what the handler writes into the configuration is what the device is created from"*, covering
adapter selection, back-buffer format and size, depth-stencil format, multisample count and
presentation interval. The read-only sibling exists only because it was published first.

The event's argument type is `PreparingDeviceSettingsEventArgs`, which is one constructor and one
property over a `GraphicsDeviceInformation` — see below.

### `Dispose(Boolean)` — **buildable**

`cna_graphics_device_manager_dispose` "unregisters both services and raises the disposed event once;
a second disposal is a no-op, which is this canonical type's own idempotence" — XNA's own contract,
already implemented natively.

### `FindBestDevice`, `CanResetDevice`, `RankDevices` — **`BLOCKED_UPSTREAM_CNA`**

All three name `GraphicsDeviceInformation` in their signatures, and
`GraphicsDeviceInformation.Adapter` is a `GraphicsAdapter`. `cna_graphics_device_information_init`
and `cna_graphics_device_information_clone` exist, so the carrier is not missing; what is missing is
an honest adapter to put in it. This is `Adapter`'s blocker a fourth time.

`PreparingDeviceSettingsEventArgs` is buildable *around* that: its own surface is a constructor and
one property, and the `GraphicsDeviceInformation` it carries can be projected with `Adapter`
refusing for the recorded reason rather than answering invented hardware — the same shape
`VideoPlayer.Play(Video)` already uses. That decision is deliberately left to the milestone that
implements the family, so that it is made against a measurement rather than in advance.

---

## Summary

| classification | members |
| --- | --- |
| **buildable against CNA 0.21.0** | 30 |
| `BLOCKED_UPSTREAM_CNA` (all five are the invented display data) | 5 |
| blocked by "the renderer" | 0 |
| blocked by "the graphics runtime" | 0 |

The single blocker behind all five is one measured upstream defect with its own evidence file. Two
of the three artifacts this project qualifies have a real renderer, a real window and a real GL
context, and none of them changes that number — which is exactly what Native frontier 6 measured and
what this audit confirms family by family.
