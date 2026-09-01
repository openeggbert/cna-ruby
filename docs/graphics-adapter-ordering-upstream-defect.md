# Upstream CNA defect — the adapter list is cached before the display exists

**Measured 2026-09-01 against `libcna_c_api.so` built from `cnanext` at `e5ae0820e`,
`CNA_PLATFORM=SDL3`, `CNA_GRAPHICS_RENDERER=OPENGL33`, SHA-256
`f7da256097338aacd77cd72eb778e8ab5d80525dd16fddac7cdd9a1885343d5c`.** Recorded here because it is
the reason `Microsoft.Xna.Framework.Graphics.GraphicsAdapter` still cannot be projected truthfully,
and because it replaces a reason this repository had recorded and believed for several milestones.

## What was believed

`docs/graphics-adapter-audit-evidence.md` recorded, correctly for the artifact it measured, that the
adapter values are fabricated because the qualified `libcna_c_api.so` was linked with the
**HEADLESS platform**, whose `GetDisplays()` returns `nullptr`. It concluded: *"The fabrication is a
property of the qualified artifact's build configuration, not of CNA's architecture. A CNA build
carrying the SDL3 platform would answer truthfully."*

The first half is right. The second half is **false**, and Native frontier 6 measured it.

## What a real display actually produces

An artifact with `CNA_PLATFORM=SDL3` **and** a renderer whose descriptor sets `needsWindow = true`,
run against a live 1280×800 X display, creates a real X11 window — `cna_game_window_get_native_window_ext`
reports `CNA_NATIVE_WINDOW_SYSTEM_X11` with a non-null `Display*` and a real XID — and still answers:

```
adapter count             1
description               "Default Display"
device name               "\\.\DISPLAY1"
current display mode      800x480, aspect 1.6666666, format Color
supported display modes   [800x480 / Color]
adapters refresh          CNA_RESULT_NOT_SUPPORTED
```

which is byte-for-byte the HEADLESS answer.

## The contradiction needs no second process and no SDL

In **one frame, with one device**, two canonical routes disagree about whether this host has a
display:

| Route | Answer |
| --- | --- |
| `cna_game_window_copy_screen_device_name` | `"screen"` — the X display's real name |
| `cna_graphics_adapter_copy_description` | `"Default Display"` — CNA's no-display fallback |

`tools/run_renderer_qualification.rb` records exactly this as
`runs.OPENGL33.displayEvidenceConflict.adapterContradictsTheWindow = true`, and the same field is
`false` on the HEADLESS artifact, where the two routes agree that there is no display.

## The cause, from CNA's own source

```cpp
// modules/graphics/src/Xna/GraphicsAdapter.cpp
const std::vector<std::unique_ptr<GraphicsAdapter>>& GraphicsAdapter::getAdaptersProperty()
{
    if (adapters_.empty()) { AdaptersChanged(); }   // static cache, filled once
    return adapters_;
}

void GraphicsAdapter::AdaptersChanged()
{
    ...GetCurrentPlatform().GetDisplays()...
    if (displays.empty()) { /* one adapter, "Default Display", 800x480 */ return; }
    ...
}
```

```cpp
// modules/graphics/src/Xna/GraphicsDevice.cpp
GraphicsDevice::GraphicsDevice()
    : GraphicsDevice(GraphicsAdapter::getDefaultAdapterProperty(), GraphicsProfile::Reach,
                     PresentationParameters())
{ }
```

`getDefaultAdapterProperty()` is a **delegated-constructor argument**, so it is evaluated before the
delegated constructor's body runs — and that body is where `createOrAttachWindow()` calls
`setVideoSubsystemAcquired(true)`. `Sdl3Displays::GetDisplays()` is `SDL_GetDisplays`, which answers
nothing until `SDL_INIT_VIDEO` has been done. So the very first `GraphicsDevice` in a process fills
the static cache from a platform that has not yet been allowed to see a display, and the fallback is
cached for the life of the process.

## The control

Initialising SDL's video subsystem **before** the device is constructed — done from the test harness
by opening the same `libSDL3.so.0` the artifact links and calling `SDL_Init(SDL_INIT_VIDEO)` — makes
the identical build answer:

```
description               "screen"
current display mode      1280x800, aspect 1.6
supported display modes   [1280x800 / Color]
```

which are this host's real values. **CNA's SDL3 display enumeration is correct.** Only the moment it
is first asked is wrong.

## Why a consumer cannot work around it

- `cna_graphics_adapters_refresh` **refuses by design**: *"The active C GraphicsDevice retains its
  adapter; refreshing the global native adapter cache would invalidate that reference."* It returns
  `CNA_RESULT_NOT_SUPPORTED`.
- The cache is a static, so a second `Game` in the same process — created after the first one had a
  window — still reads the fallback. Measured: two sequential games, both `"Default Display"` /
  `800x480`.
- Nothing in the C ABI acquires the video subsystem without constructing a device.
- Reaching around the ABI into SDL is what the ABI exists to prevent, and this binding will not do
  it outside a diagnostic.

## Suggested upstream fix, stated without taking it

Three shapes, in increasing order of intrusiveness. None was taken: this repository does not modify
`cnanext`.

1. **Acquire the video subsystem before resolving the default adapter.** The narrowest change:
   `GraphicsDevice`'s default constructor takes a video-subsystem reference before evaluating
   `getDefaultAdapterProperty()`.
2. **Do not cache an empty result.** `AdaptersChanged()` could record *why* the list is the fallback
   and re-enumerate on the next request while no display service was available. The cache is there
   to keep `GraphicsAdapter&` references stable, so this has to preserve identity for the
   already-handed-out default adapter.
3. **Let the C ABI refresh.** `cna_graphics_adapters_refresh` refuses in order to protect a retained
   reference; a route that refreshes only when the C layer holds no adapter reference, or that
   updates the existing adapter objects in place rather than replacing them, would give a consumer
   the correction that today does not exist.

## Consequence for this binding

`Graphics.GraphicsAdapter` stays deferred, reclassified from `BACKEND_BLOCKED` to
**`UPSTREAM_CNA_BLOCKED`**. Fifteen of its eighteen identities are display values or derived from
them; publishing the cached fallback would publish invented hardware, which this project refuses.
The capability row is `display.adapter-enumeration`.

Two contract facts recorded by the earlier audit are unchanged and would still need answering even
if the cache were fixed:

- every `cna_graphics_adapter_*` route is scoped to a callback-borrowed `GraphicsDevice`, while
  XNA's `Adapters` and `DefaultAdapter` are statics whose purpose is to be readable *before* a
  device exists;
- `MonitorHandle` has no truthful producer — `cna_graphics_adapter_get_native_monitor_handle`
  returns `CNA_RESULT_NOT_SUPPORTED` by design.
