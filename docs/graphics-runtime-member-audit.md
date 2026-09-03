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

### `Present`'s two overloads — **done, Foundation 92**

`Present()` is `Present(null, null, null)` on the private native three-pointer form.
`Present(Nullable<Rectangle>, Nullable<Rectangle>, IntPtr)` converts each present rectangle into a
`tagRECT` **in a local copy** — `right = width + x`, `bottom = height + y`, so the caller's
rectangle is not mutated — and passes the override window handle through `IntPtr::ToPointer`.

`cna_graphics_device_present(handle)` takes no rectangles and no window handle. So the no-argument
overload is exact, and the three-argument one is exact **for the all-null call** and must refuse
anything else, naming what CNA does not accept. That is the `VideoPlayer.Play(Video)` precedent:
project the member and make it refuse explicitly, rather than defer the member or invent a
behaviour.

### `Reset`'s three overloads — **done, Foundation 92**

`Reset()` re-applies the cached parameters; `Reset(PresentationParameters)` applies new ones;
`Reset(PresentationParameters, GraphicsAdapter)` also switches adapter.
`cna_graphics_device_reset` and `cna_graphics_device_reset_with_parameters(handle, parameters,
adapter_index)` cover the first two exactly — the adapter index argument is nullable, which is
precisely "keep the current adapter". The third overload's second argument is a `GraphicsAdapter`,
so it inherits `Adapter`'s blocker and refuses for that reason, naming it.

A successful reset raises the device's resetting and reset events in that order, which the header
states and the event family below consumes.

**What `Reset` does *not* do here was measured, not assumed.** XNA's third overload is two null
guards, the `DeviceResetting` event, a `SavedDeviceState`, the device re-creation, two `Clone()`s
into the internal and public caches, `InitializeDeviceState`, `SavedDeviceState.Restore()` and the
`DeviceReset` event. Across both reset routes and both artifacts, CNA already preserves the blend
state, the blend factor, the multi-sample mask, the reference stencil and a bound texture slot, and
it preserves the viewport and scissor across a same-size reset while resetting them to the new full
target on a resizing one — which is *exactly* the rule `SavedDeviceState` implements by taking those
two as `Nullable`. Re-applying any of it here would perform a step CNA already performs.

What stays managed is the part CNA cannot know: the two guards, the render-target unbind that
`SavedDeviceState` deliberately does not restore, and the two cached parameter objects, which become
two distinct clones of the argument.

### `DrawUserPrimitives` and `DrawUserIndexedPrimitives` — **done, Foundation 94**

`cna_graphics_device_draw_user_primitives(handle, CNA_UserPrimitives*)` and
`cna_graphics_device_draw_user_indexed_primitives(handle, CNA_UserPrimitives*, CNA_UserIndices*)`
take versioned descriptions by pointer, so no by-value aggregate is involved and the arrays stay
caller-owned — "no vertex array is retained after the call returns".

All six overloads use `CNA_USER_VERTEX_SOURCE_RAW_STREAM` with an explicit vertex declaration. The
typed sources would cover only CNA's four built-in layouts; the raw one covers those **and** an
explicitly declared layout, which is what the five- and eight-argument overloads exist for.

Two language mappings, recorded rather than smoothed over. `T` is read off the array's own
elements, because Ruby has no type argument at a call site and `pack_elements` already requires
every element to be one type. And a Ruby `Array` of integers is neither an `Int32[]` nor an
`Int16[]`, so `DrawUserIndexedPrimitives` takes the index element size as a **leading type
argument** — the same stand-in `IndexBuffer`'s constructor and `SetData` already use, resolved by
the same rule where `IndexElementSize` is itself and `::Integer` means `ThirtyTwoBits`.

Two side effects that are easy to miss and are reproduced. `BeginUserPrimitives` unbinds every
vertex stream **before** the draw, so the streams go whether the draw succeeds or not; and the
indexed draw clears `_currentIB` in its `finally`, so the index buffer goes too — but only for the
indexed one. Both are observable through `GetVertexBuffers` and `Indices`.

`DeclarationManager` is reproduced as well: one native declaration cached per managed one, released
in full by `Reset` (`ReleaseAllDeclarations`) and by the device's invalidation, so a per-frame draw
does not build and destroy a declaration every frame.

The managed validation is the IL's, in the IL's order, including `ldlen; brfalse` — a zero-length
array raises the same `ArgumentNullException` a null one does — and `GetVertexCount`'s unknown
topology answering `-1` compared **unsigned**, so it never fits any window.

### `GetBackBufferData`'s three overloads — **done, Foundation 95**

One route carries all three: `cna_graphics_device_get_backbuffer_data_window`, because
`has_source_rectangle` false is the whole buffer. `cna_graphics_device_get_backbuffer_data_rgba8`
therefore has no call site and is not bound.

It answers `CNA_RESULT_NOT_SUPPORTED` "when the active renderer has no honest back-buffer readback"
— the `HEADLESS` artifact. That is a **capability** of one artifact rather than a blocker: the
managed guards are exercised on every artifact, and the pixel assertions run where pixels exist.
Measured on `OPENGL33`: an 8x4 back buffer cleared to one colour reads back as thirty-two pixels of
exactly that colour through all three overloads, `startIndex` writes into the middle of the
destination and leaves what precedes it untouched, and a destination too small is
`CNA_RESULT_BUFFER_TOO_SMALL` with **nothing partial written**.

DEVIATION, recorded, and it is the interesting one. XNA refuses this member on a **Reach** device:
it is a HiDef feature and `ProfileCapabilities.GetBackBufferDataSupported` is what says so. This
binding's device reports `Reach`, so XNA would refuse where this succeeds on a real renderer.
`ProfileCapabilities` is not projected — the same decision the draw calls' `ProfileMaxPrimitiveCount`
and the occlusion query's profile check record — so the refusal is CNA's, and CNA refuses for a
**renderer** reason instead. Same shape, different reason, both recorded rather than blurred.

DEVIATION, recorded: `T` is `Color`, because the route takes `CNA_Color*`. XNA's is any struct whose
size divides the format's — the same limit `Texture3D.GetData` records for the same reason.

### `Dispose`, `Dispose(Boolean)` and `Finalize` — **done, Foundation 95**

`cna_graphics_device_dispose` exists and **deliberately answers `CNA_RESULT_NOT_SUPPORTED` for a
valid device handle**. The header says why, and it is not a gap:

> The canonical `GraphicsDevice` belongs to the running game, so disposing it through a borrowed
> handle would leave that game drawing into a destroyed device. `cna_game_destroy` performs the
> canonical disposal and `cna_graphics_device_get_is_disposed` observes the resulting state.

That is the same two-owners fact `docs/graphics-device-service-producer-audit.md` recorded for the
service container, and it settles the family rather than blocking it: the route is not bound,
because it has no call site that could succeed.

The C++/CLI shape is the one `GraphicsResource` already records, on the device itself:

    void !GraphicsDevice() { if (isDisposed) return; isDisposed = true;
                             resourceManager.ReleaseAllDeviceResources();
                             declarationManager.ReleaseAllDeclarations();
                             release the native objects; }
    void ~GraphicsDevice() { if (isDisposed) return; !GraphicsDevice();
                             Disposing?.Invoke(this, EventArgs.Empty); }
    protected virtual void Dispose(bool disposing) { if (disposing) ~GraphicsDevice(); !GraphicsDevice(); }
    public void Dispose() { Dispose(true); GC.SuppressFinalize(this); }
    protected void Finalize() { Dispose(false); }

So `Dispose(false)` releases without raising `Disposing` and `Dispose(true)` raises it exactly
once, because both destructors return early once the flag is set. All of that is projected. What
the managed half really does here is the flag, the declaration cache and the native event
registrations — `ReleaseAllDeclarations` and its analogue — and the device itself is released with
the game. `GC.SuppressFinalize` has no analogue either: **no GC finalizer releases native state**
in this binding, so there is nothing to suppress.

### The six events — **done, Foundation 93**, and three of them are not CNA's to raise

The route table this section first carried mapped all six onto CNA subscriptions. Measuring each
moved three of them:

| XNA event | how it is raised | why |
| --- | --- | --- |
| `DeviceLost` | `cna_graphics_device_subscribe_event`, `…_DEVICE_LOST` | only CNA knows |
| `DeviceReset` | … `…_DEVICE_RESET` | only CNA knows; a reset raises it |
| `DeviceResetting` | … `…_DEVICE_RESETTING` | the same, and first |
| `Disposing` | **managed**, from the device's own invalidation | the native signal cannot arrive in time |
| `ResourceCreated` | **managed**, from `GraphicsResource`'s registration | CNA's payload is presence only |
| `ResourceDestroyed` | **managed**, from `GraphicsResource`'s release | the same |

**`Disposing`.** CNA raises `CNA_GRAPHICS_DEVICE_EVENT_DISPOSING` inside `cna_game_destroy`, and by
then the graphics-device-manager handle — which every registration made through the device belongs
to — has already been released, because `cna_graphics_device_manager_create` documents "release it
before the game". Measured both ways: a deliberately *leaked* subscription does receive it during
`Game#Dispose`, and a correctly released one never can. So it is raised where XNA raises it, from
`~GraphicsDevice()`, and the constant is not even in the manifest.

**The two resource events.** CNA's routes fire — measured, for a `Texture2D` this binding creates —
and what they carry is presence only. The header says why: *"the canonical event is raised from the
graphics-resource base constructor, so the reported object is still under construction … no native
object pointer crosses the ABI."* But `ResourceCreatedEventArgs.Resource` **is** that object, and
`ResourceDestroyedEventArgs` carries `Name` and `Tag`, which are managed properties CNA never sees.
This projection has all three, because the resource is a Ruby object it constructed. So both are
raised from `GraphicsResource` — which is exactly where `DeviceResourceManager.AddTrackedObject`
and `ReleaseAllReferences` raise them in XNA — and the two subscribe routes stay unbound.

Two details of `FireCreatedEvent`/`FireDestroyedEvent` that a paraphrase loses are reproduced: each
device keeps **one** args object and overwrites its fields on every raise, and the created one
**nulls `_resource` once the handlers return** while the destroyed one does not.

The three native registrations are released by `cna_graphics_device_unsubscribe`, which answers
`CNA_RESULT_INVALID_HANDLE` on a second release — which is what the test uses to prove the first
release happened.

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

### The five events and their four raisers — **done, Foundation 96, and with no new route**

`cna_graphics_device_manager_subscribe` carries five identities, and they are exactly XNA's five
events:

| XNA event | CNA identity |
| --- | --- |
| `Disposed` | `CNA_GRAPHICS_DEVICE_MANAGER_EVENT_DISPOSED` |
| `DeviceCreated` | `…_DEVICE_CREATED` |
| `DeviceDisposing` | `…_DEVICE_DISPOSING` |
| `DeviceReset` | `…_DEVICE_RESET` |
| `DeviceResetting` | `…_DEVICE_RESETTING` |

That table was the plan and **the IL made it unnecessary**, which is this audit's own rule turned on
itself for the second time. `CreateDevice` hooks four private handlers onto the `GraphicsDevice` it
has just made:

    device.DeviceResetting += HandleDeviceResetting;   // -> OnDeviceResetting(this, EventArgs.Empty)
    device.DeviceReset     += HandleDeviceReset;       // -> OnDeviceReset(this, EventArgs.Empty)
    device.DeviceLost      += HandleDeviceLost;        // body is a single `ret`
    device.Disposing       += HandleDisposing;         // -> OnDeviceDisposing(this, EventArgs.Empty)

So four of the five events are **relays of the device's own**, `HandleDeviceLost` doing nothing is
why the manager declares no `DeviceLost`, and Foundation 93 had already given the device every
signal. `DeviceCreated` is raised by the manager at the end of `CreateDevice` and `Disposed` by
`Dispose(Boolean)`. **`cna_graphics_device_manager_subscribe` is still unbound**: ten members and
not one new native route.

The four `On*` raisers are `family` and one null-check plus one `Invoke` each, which this project
has projected fourteen times for `Game` and `GameComponent`.

### `PreparingDeviceSettings` and `OnPreparingDeviceSettings` — **`BLOCKED_UPSTREAM_CNA`**

Not by the route, which exists and is the canonical mutable form. By the **argument**: the event's
args carry a `GraphicsDeviceInformation`, whose `Adapter` is a `Graphics.GraphicsAdapter`. That is
the fifth member of this audit the invented display data takes.

The original note follows, because the route half of it is still true and is what a later milestone
would use if the adapter defect were ever fixed upstream.

`cna_graphics_device_manager_subscribe_preparing_device_settings_ext` is the canonical mutable form:
*"what the handler writes into the configuration is what the device is created from"*, covering
adapter selection, back-buffer format and size, depth-stencil format, multisample count and
presentation interval. The read-only sibling exists only because it was published first.

The event's argument type is `PreparingDeviceSettingsEventArgs`, which is one constructor and one
property over a `GraphicsDeviceInformation` — see below.

### `Dispose(Boolean)` — **done, Foundation 96**

Two of its five steps are already no-ops here, and for measured reasons rather than omissions: the
`RemoveService` branch has nothing to remove, because this manager was never in the managed
container (the producer audit's own finding), and the three `GameWindow` handlers are CNA's, so
there are none to unhook. What is left is XNA's: dispose the device, null it, raise `Disposed`.

DEVIATION, recorded: XNA's `Dispose(Boolean)` has **no disposed guard**, so a second call raises
`Disposed` again — the opposite of `Game.Dispose`, which guards and raises once. This reproduces
XNA's, because the native release is idempotent on its own and nothing needed a guard.

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
| **built** | 30 of `GraphicsDevice`'s, and its remainder is now only the five below |
| `BLOCKED_UPSTREAM_CNA` (all five are the invented display data) | 5 |
| blocked by "the renderer" | 0 |
| blocked by "the graphics runtime" | 0 |

`GraphicsDevice` owes three members — `.ctor`, `Adapter` and `DisplayMode` — and
`GraphicsDeviceManager` owes the two of its fifteen that name `GraphicsDeviceInformation`'s adapter.
Every one of the five is the same upstream defect.

The single blocker behind all five is one measured upstream defect with its own evidence file. Two
of the three artifacts this project qualifies have a real renderer, a real window and a real GL
context, and none of them changes that number — which is exactly what Native frontier 6 measured and
what this audit confirms family by family.
