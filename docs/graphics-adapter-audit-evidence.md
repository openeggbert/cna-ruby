# GraphicsAdapter architecture and CNA capability audit

> **Superseded in part, 2026-09-01 (Native frontier 6).** Everything below about the XNA contract,
> the IL and the canonical C ABI still stands and was re-measured. **Blocker 2 is wrong.** It
> concluded that the fabricated adapter data "is a property of the qualified artifact's build
> configuration, not of CNA's architecture" and that "a CNA build carrying the SDL3 platform would
> answer truthfully". A second qualified artifact — same source, `CNA_PLATFORM=SDL3`,
> `CNA_GRAPHICS_RENDERER=OPENGL33`, a real X11 window, a real GL 4.5 context and a live 1280x800
> display — answers **exactly the same invented values**. The cause is that the adapter list is a
> static cache filled before the video subsystem is acquired, and the ABI's only refresh route
> refuses by design. See `docs/graphics-adapter-ordering-upstream-defect.md`.
>
> Blocker 1 has also moved: mscorlib **is** admitted now (`tools/api_compat/reference/BCL_PROVENANCE.md`),
> so `ReadOnlyCollection`1` is measurable rather than unmeasurable — it is a mapping decision that
> has not been taken, not a missing authority. Blockers 3 and 4 are unchanged and were re-measured.

This is the audit that opened the native/CNA expansion sequence. It was commissioned to decide
whether `Microsoft.Xna.Framework.Graphics.GraphicsAdapter` could be projected truthfully, and, if
that required new canonical CNA capability, to design the smallest additive C ABI for it.

**It found that no C ABI expansion is needed, and that the type still cannot be completed
truthfully.** Both halves of that sentence contradict what this repository previously recorded, so
both are evidenced below.

## The exact XNA contract

Derived from the pinned `Microsoft.Xna.Framework.Graphics.dll`, SHA-256
`560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`, disassembled with `ikdasm`.

`.class public auto ansi sealed beforefieldinit` — a sealed class deriving from `System.Object`,
implementing nothing. Its only constructor is `private .ctor(uint32 adapterOrdinal)`, so the type
is publicly non-constructible and the Foundation 25 constructor-free rule would apply to it.

Eighteen public identities, and nothing else:

| # | Identity | Shape | Type |
| --- | --- | --- | --- |
| 1 | `Adapters` | static property, get | `ReadOnlyCollection<GraphicsAdapter>` |
| 2 | `DefaultAdapter` | static property, get | `GraphicsAdapter` |
| 3 | `UseNullDevice` | static property, get/set | `Boolean` |
| 4 | `UseReferenceDevice` | static property, get/set | `Boolean` |
| 5 | `Description` | instance property, get | `String` |
| 6 | `DeviceName` | instance property, get | `String` |
| 7 | `VendorId` | instance property, get | `Int32` |
| 8 | `DeviceId` | instance property, get | `Int32` |
| 9 | `SubSystemId` | instance property, get | `Int32` |
| 10 | `Revision` | instance property, get | `Int32` |
| 11 | `IsDefaultAdapter` | instance property, get | `Boolean` |
| 12 | `IsWideScreen` | instance property, get | `Boolean` |
| 13 | `CurrentDisplayMode` | instance property, get | `DisplayMode` |
| 14 | `SupportedDisplayModes` | instance property, get | `DisplayModeCollection` |
| 15 | `MonitorHandle` | instance property, get | `IntPtr` |
| 16 | `QueryBackBufferFormat` | instance method | `(GraphicsProfile, SurfaceFormat, DepthFormat, Int32, out SurfaceFormat, out DepthFormat, out Int32) -> Boolean` |
| 17 | `QueryRenderTargetFormat` | instance method | same shape as 16 |
| 18 | `IsProfileSupported` | instance method | `(GraphicsProfile) -> Boolean` |

### What each member actually does, from the IL

The type is Direct3D 9 through and through. `.cctor` runs `InitalizeGraphics` — which
`LoadLibraryW("d3dx9_41.dll")`, throws `FileNotFoundException` if it is missing, then
`Direct3DCreate9(32)` — followed by `InitializeAdapterList`, which calls
`IDirect3D9::GetAdapterCount` and constructs one `GraphicsAdapter` per ordinal into a
`List<GraphicsAdapter>` wrapped in a `ReadOnlyCollection`.

- **`Adapters`** is a single `ldsfld` of that collection. It is built once at static
  initialisation and never refreshed. **`DefaultAdapter`** is `pAdapterList[0]`, and
  **`IsDefaultAdapter`** is `adapterOrdinal == 0` — both pure derivations.
- **`UseNullDevice`/`UseReferenceDevice`** are a bare `ldsfld`/`stsfld` pair over two private
  static booleans. **No native call is involved in either accessor.** They are read later by the
  internal `CurrentDeviceType`, which maps them to `D3DDEVTYPE` 4 (NULLREF), 2 (REF) or 1 (HAL)
  for the three query members.
- **`Description`, `DeviceName`, `VendorId`, `DeviceId`, `SubSystemId`, `Revision`** are eagerly
  read in the constructor from a `_D3DADAPTER_IDENTIFIER9` filled by
  `IDirect3D9::GetAdapterIdentifier`, at fixed offsets `0x200`, `0x400`, `0x428`, `0x42c`, `0x430`
  and `0x434`. The two strings are `Marshal.PtrToStringAnsi`.
- **`CurrentDisplayMode`** is lazy and cached. It calls `GetAdapterDisplayMode`, and builds
  `DisplayMode(width, height, ConvertWindowsFormatToXna(format))`. The mode's **refresh rate is
  read and discarded**. If the conversion answers a negative value the format is forced to
  `SurfaceFormat.Color` — so XNA's Color fallback is narrow and conditional, not a blanket
  assumption.
- **`IsWideScreen`** is `CurrentDisplayMode.AspectRatio > 1.6f`, evaluated in `float64` after a
  `conv.r8`. The comparison is strict, so exactly 16:10 is **not** widescreen.
- **`SupportedDisplayModes`** is lazy and cached. It iterates
  `ProfileCapabilities.HiDef.ValidTextureFormats` — measured from the same IL as
  `SurfaceFormat` 0 through 19 inclusive, i.e. every declared value; the Reach list is 0 through 8.
  For each, it maps to a D3D adapter format via `ConvertXnaFormatToWindowsAdapterFormat`
  (`Color -> D3DFMT_X8R8G8B8`, `Bgra5551 -> D3DFMT_X1R5G5B5`, otherwise the ordinary surface-format
  conversion), calls `GetAdapterModeCount`, and enumerates with `EnumAdapterModes`. Within one
  format it de-duplicates by `Point(width, height)` using a fresh `Dictionary`, and constructs
  `DisplayMode(width, height, thatProbedXnaFormat)` — **the probed format, not the format the
  enumerated mode reports.** Order is the outer format list, then the enumeration index.
- **`MonitorHandle`** is `IDirect3D9::GetAdapterMonitor` widened to `IntPtr` — a Win32 `HMONITOR`.
- **`QueryBackBufferFormat`/`QueryRenderTargetFormat`** both delegate to the internal `QueryFormat`
  with the `D3DDEVTYPE` derived from the two static device flags, and **`IsProfileSupported`**
  delegates to `ProfileChecker.IsProfileSupported`, a full `D3DCAPS9` inspection.

## What CNA already has

The canonical CNA repository at `develop` `1bb2145d99ed572dd4eb15009c34e2e5f410fcf0`.

### The capability exists in CNA core

`modules/graphics/include/Microsoft/Xna/Framework/Graphics/GraphicsAdapter.hpp` and
`modules/graphics/src/Xna/GraphicsAdapter.cpp` implement the type in full. It sits on a genuine
platform abstraction, not on SDL: `CNA::Platform::IPlatformDisplays` in
`modules/platform/include/CNA/Platform/IPlatformSystemServices.hpp` exposes `GetDisplays`,
`GetDisplayModes` and `TryGetCurrentDisplayMode` over neutral `DisplayInfo`/`DisplayMode` structs,
with SDL3, SDL2, Terminal and Headless implementations behind it. The architecture rule this
session was given — CNA-Ruby to canonical C ABI to CNA core to platform backend — is already the
shape CNA has.

### The capability is already exposed by the canonical C ABI

`modules/c-api/include/CNA/C/display.h` carries the whole surface. This is the finding that
overturns the recorded frontier:

| XNA identity | Canonical C ABI route |
| --- | --- |
| `Adapters` (count) | `cna_graphics_adapter_get_count` |
| `Description` | `cna_graphics_adapter_copy_description` |
| `DeviceName` | `cna_graphics_adapter_copy_device_name` |
| `VendorId`, `DeviceId`, `SubSystemId`, `Revision`, `IsDefaultAdapter`, `IsWideScreen`, both device flags | `cna_graphics_adapter_get_info` |
| `CurrentDisplayMode` | `cna_graphics_adapter_get_current_display_mode` |
| `SupportedDisplayModes` | `cna_graphics_adapter_get_display_mode_count` + `cna_graphics_adapter_copy_display_modes` |
| `UseNullDevice=`, `UseReferenceDevice=` | `cna_graphics_adapter_set_device_preferences` |
| `IsProfileSupported` | `cna_graphics_adapter_is_profile_supported` |
| `QueryBackBufferFormat` | `cna_graphics_adapter_query_backbuffer_format` |
| `QueryRenderTargetFormat` | `cna_graphics_adapter_query_render_target_format` |
| `MonitorHandle` | `cna_graphics_adapter_get_native_monitor_handle` — refuses by design |

Every one of these is present as an exported symbol in the retained qualification artifact and
every one was executed against it during this audit.

**`NEXT.md` recorded that the six `NATIVE_RUNTIME` types are blocked because "crossing that
boundary means new CNA ABI". That is false.** The retained `libcna_c_api.so` 0.7.0 exports **2861**
`cna_*` functions; this binding's measured manifest binds **39** of them. The native frontier is
not gated on canonical ABI that does not exist — it is gated on Ruby binding work, on undesigned
BCL projections, and on the six deferred partial runtime types.

## Why GraphicsAdapter still cannot be completed truthfully

Four independent blockers. Any one of them alone would be sufficient.

### 1. `ReadOnlyCollection<T>` has no decided projection and no reference authority

`Adapters` is a `System.Collections.ObjectModel.ReadOnlyCollection<GraphicsAdapter>`.
`tools/api_compat/mapping-rules.json` already lists that identity under
`bclProjection.notYetDesigned`, and the register's own admission rule is "only a CLR identity the
selected XNA surface actually names, **and whose Ruby projection can be decided without
guessing**".

Two materially different public Ruby designs are plausible — a frozen Ruby `Array`, or a dedicated
CLR-shaped runtime collection preserving `Count`/`Item`/`Contains`/`IndexOf`/`CopyTo`/
`GetEnumerator` — and no repository rule chooses between them.

The deeper obstacle is authority. Every BCL identity projected so far has an empty or scalar
surface with nothing to measure: `System.EventArgs` and `System.Attribute` declare no members, and
`System.TimeSpan` collapses to `Float`. `ReadOnlyCollection<T>` would be the first with a real
member surface — and `docs/generated/xna-il-inventory.json` admits the ten XNA assemblies and **no
mscorlib**, so this project has no measured reference for it. Admitting mscorlib would change the
measurement basis of the whole binding and is not a decision to take incidentally.

This is the single highest-leverage BCL blocker in the register: `GraphicsAdapter`, `SpriteFont`,
`Microphone` and `Media.VisualizationData` all name it. It is recorded as
`mapping.readonly-collection` in `docs/runtime-capabilities.json`.

### 2. The qualified native artifact cannot supply truthful adapter data

`libcna_c_api.so` 0.7.0, SHA-256
`c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`, was linked with
`CNA_PLATFORM=HEADLESS`. `nm` finds `HeadlessPlatform` and `TerminalPlatform` in it and **no
`Sdl3Platform` or `Sdl2Platform`**, and `ldd` shows it does not link SDL at all. Platform selection
in CNA is a build-time choice (`cmake/PlatformSelection.cmake`), not a runtime one, so no
environment variable can change this.

`HeadlessPlatform::GetDisplays()` returns `nullptr`. `GraphicsAdapter::AdaptersChanged()` therefore
always takes its no-display branch, which fabricates a single adapter. Executed against the
retained artifact inside a live `Draw` callback, the canonical routes answer:

```
adapter count             1
description               "Default Display"
device name               "\\.\DISPLAY1"
current display mode      800x480, aspect 1.6666666, SurfaceFormat.Color
supported display modes   [800x480 / Color]
vendor id / device id     0x1002 / 0x15bf      (real, read from this host's sysfs)
revision / subsystem id   0 / 0                (hardcoded in CNA)
is_profile_supported      true for Reach and true for HiDef
native monitor handle     CNA_RESULT_NOT_SUPPORTED
adapters refresh          CNA_RESULT_NOT_SUPPORTED
```

"One fake adapter named Default", a fabricated 800x480 mode, a blanket `SurfaceFormat.Color`,
zeroed hardware properties presented as answers, and this development machine's own PCI IDs are
each explicitly on the list of things this project refuses to publish as XNA behaviour. Binding a
Ruby `GraphicsAdapter` to them would publish invented hardware. Recorded as
`display.adapter-enumeration`.

Note what this blocker is **not**: it is not a claim that CNA cannot enumerate displays. CNA's
SDL3 backend implements the neutral interface properly, and this host has both an X and a Wayland
display. A CNA build carrying the SDL3 platform would answer truthfully. The fabrication is a
property of the qualified artifact's build configuration, not of CNA's architecture.

### 3. The C ABI is device-scoped; XNA's contract is not

Every adapter route takes `CNA_Handle graphics_device` and validates it through
`GetBorrowedGraphicsDevice`, so it answers only inside a live graphics-device callback. XNA's
`Adapters` and `DefaultAdapter` are statics usable before any `GraphicsDevice` exists — which is
their purpose, since an adapter is what you choose a device *from*. A Ruby projection could only
offer them during a frame, which is a different contract, not a narrower one.

### 4. `MonitorHandle` has no truthful producer

`cna_graphics_adapter_get_native_monitor_handle` returns `CNA_RESULT_NOT_SUPPORTED` and zero by
design; the header describes `CNA_NativeHandleValue` as "a native IntPtr that is never disclosed by
this ABI". Underneath, CNA's own value is the display id cast to `uintptr_t`, not an `HMONITOR`.
The Ruby mapping is not the problem — `mapping-rules.json` already maps `System.IntPtr` to
`Integer` — the problem is that no truthful value exists to map.

## Divergences found in CNA, recorded but not changed

The audit was authorised to modify CNA. It did not, because each of these is a decision with
consequences beyond this binding and none of them unblocks the Ruby type. They are recorded here
so a future CNA milestone can take them deliberately.

1. **`IsWideScreen` uses the wrong threshold.** `GraphicsAdapter.cpp` compares the aspect ratio
   against `4.0f / 3.0f`; XNA's IL compares against `1.6f`. Every mode between 1.334 and 1.6 —
   4:3 is excluded but 3:2 and 5:3 are not — is reported widescreen by CNA and not by XNA, and
   16:10 is reported widescreen by CNA while XNA's strict `>` excludes it. A Ruby projection
   should derive this member from `CurrentDisplayMode.AspectRatio` rather than consuming
   `CNA_GraphicsAdapterInfo::is_wide_screen`, which is both XNA-exact and avoids the divergence.
2. **`UseNullDevice`/`UseReferenceDevice` are instance state in CNA and static in XNA.** The C ABI
   follows CNA and scopes them per adapter index. XNA's IL shows a bare static field pair, so the
   correct Ruby projection is pure managed static state with no native round trip at all.
3. **Display modes are hardcoded to `SurfaceFormat::Color`.** `queryDisplayModes` and
   `queryCurrentDisplayMode` both discard whatever pixel format the platform reports.
   `CNA::Platform::DisplayMode` carries `width`, `height` and `refreshRate` and **no format**, even
   though SDL3's `SDL_DisplayMode` has one. The principled fix is a neutral pixel format on the
   platform struct, mapped in the SDL backends and reported honestly as unknown by Headless; the
   C ABI needs no change, because `CNA_DisplayMode::format` already exists and would simply start
   carrying truthful values.
4. **`Revision` and `SubSystemId` return a hardcoded zero**, which `display.h` documents as
   "current CNA returns zero". That is honest in the header and would stop being honest the moment
   a binding surfaced it as `GraphicsAdapter.Revision`.
5. **`IsProfileSupported` answers an unconditional `true`** on every renderer that supplies no
   descriptor hook, which is all of them but the D3D9 renderer. CNA documents this as deliberate —
   the alternative was "a hardcoded table pretending to be a capability query" — but it means a
   Ruby `IsProfileSupported` would report HiDef supported under the headless renderer.

## Decision boundaries this audit hands upward

1. **The `ReadOnlyCollection<T>` public mapping.** Two plausible incompatible designs, no
   repository rule choosing between them, and no measured reference surface. Unblocks four types.
2. **Whether to admit mscorlib to the pinned reference inventory.** This is what would make (1)
   measurable rather than a guess, and it changes the measurement basis of the whole binding.
3. **Whether the qualification artifact should be rebuilt with the SDL3 platform.** That would
   turn the fabricated adapter into a real one, at the cost of making the qualified suite depend on
   the host's displays — which is exactly the split between architecture qualification and
   environment-dependent integration observation that this project keeps separate.
4. **Whether CNA should stop fabricating an adapter when no display service exists.** Reporting
   zero adapters is the honest answer, and `getDefaultAdapterProperty` already throws in that case
   — but headless CNA games depend on the current fallback, so this is a CNA architecture decision
   with more than one viable design.

None of the four was taken autonomously.

## What was done instead

The audit's negative result is not the whole milestone. The same C ABI survey that found the
adapter surface already exposed also found `cna_framework_dispatcher_update`, which retires the
one `RUNTIME_DATA` frontier entry whose recorded reason turned out to be wrong. See
`docs/framework-dispatcher-evidence.md`.
