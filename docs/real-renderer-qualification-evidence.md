# Native frontier 6 — qualifying against a renderer that really renders

Every native measurement this binding had made came from one artifact, built
`CNA_GRAPHICS_RENDERER=HEADLESS`. `docs/graphics-adapter-audit-evidence.md` closed with the
recommendation that follows from that: *"the single largest lever is still a qualification artifact
with a real renderer"*. This is the milestone that built one, ran the whole suite against it, and
measured what it changed.

**Two things it changed, and one it did not.** It made the binding's environment-dependent
expectations measurable instead of pinned; it produced this project's first real rendered pixels.
It did **not** unblock `GraphicsAdapter` — and finding out *why* is the most useful thing in this
document, because the recorded reason turned out to be wrong.

## The artifacts

Both are the same CNA source tree and the same public C ABI. They differ in one CMake variable.

| | HEADLESS | OPENGL33 |
| --- | --- | --- |
| Path | `~/deps/cna-c-abi-0.21.0/libcna_c_api.so` | `~/deps/cna-c-abi-0.21.0-opengl33/libcna_c_api.so` |
| SHA-256 | `c32bfbd307d695664f906ccf2834ec3f9ebc240fa388d544ac21ee3ebaeb731b` | `f7da256097338aacd77cd72eb778e8ab5d80525dd16fddac7cdd9a1885343d5c` |
| `CNA_PLATFORM` | SDL3 | SDL3 |
| `CNA_AUDIO_PLATFORM` | SDL3 | SDL3 |
| `CNA_GRAPHICS_RENDERER` | `HEADLESS` | `OPENGL33` |
| Renderer name from `cna_graphics_device_copy_renderer_name` | `HEADLESS` | `OPENGL33` |
| `CNA_RendererInfo::max_texture_dimension` | 16384 | 16384 |
| Capability bit set | `0xCFF` | `0x7DFFF` |

The `OPENGL33` artifact is byte-identical to `cnanext`'s `cmake-build-opengl33` output; **no CNA
source was changed and no CNA build was run by this milestone**. Both pass the native ABI gate
identically — 260 bound functions, 5 callbacks, 101 constants, 37 layouts, `ABI_MISMATCHES=0` —
against the same pinned headers, which is what makes them interchangeable qualification artifacts
rather than two different bindings.

The only header difference between the pinned 0.21.0 tree and `cnanext`'s current one is a
documentation comment in `devices.h` about the browser target's device type. **The CNA ABI has not
advanced past the admitted set**, so this milestone performs no migration.

Qualified under `Xvfb :77 -screen 0 1280x800x24` with `SDL_VIDEODRIVER=x11`. The X display is real
and so is the driver — Mesa 25.0.7 reports `OpenGL 4.5 (Core Profile)` — but it is a virtual
framebuffer, so *rasterisation* is verified and *visibility on a physical monitor* is not. Those are
two capability rows, `renderer.real-rasterization` and `hardware.visible-renderer`, and they are
deliberately not the same one.

## "Not HEADLESS" is not the same question as "has a window"

The obvious first attempt was the `SOFTWARE` renderer, and it produced **exactly the HEADLESS
answers**: no window, no video subsystem, the same fabricated adapter. CNA says why in
`GraphicsDevice::createOrAttachWindow`:

```cpp
// No real window, ever -- HEADLESS/SOFTWARE/STUB/PORTABLEGL, matching the constructor's own
// needsVideoSubsystem check.
if (!descriptor.needsWindow) { platformWindow_.reset(); ownsWindow_ = false; return; }
```

`needsWindow` is a property of the renderer *descriptor*, not of the platform. `SOFTWARE` rasterises
into memory and never asks the platform for a surface, so selecting it changes the renderer name and
the capability flags and nothing else that matters here. `OPENGL33`, `SDL_RENDERER` and `VULKAN` set
`needsWindow = true`; the first two were measured and both produce a real X11 window.

## What the renderer qualification proves

`tools/run_renderer_qualification.rb`, recorded in `docs/generated/renderer-native-report.json`,
one entry per renderer so the two answers sit side by side.

| Question | HEADLESS | OPENGL33 |
| --- | --- | --- |
| `cna_game_window_get_native_window_ext` system | `UNKNOWN` (0) | `X11` (2) |
| native `Display*` | null | non-null |
| X11 window XID | 0 | real |
| `ClientBounds` | `0,0,0,0` | `0,0,800,480` |
| `ScreenDeviceName` | `\\.\DISPLAY1` | `screen` |
| `RenderTarget2D` created | yes | yes |
| `renderer_available` | true | true |
| bind / clear / unbind | success | success |
| `cna_texture2d_get_data` | `CNA_RESULT_NOT_SUPPORTED` | success, 32 elements |
| pixels read back | `0,0,0,0` | **`64,128,191,255`** |
| 60 frames | 60/60, no error | 60/60, no error |
| 600 frames | 600/600, no error | 600/600, no error |

**The pixel row is the milestone.** An 8×4 `RenderTarget2D` is created, bound, cleared to
`(0.25, 0.5, 0.75, 1.0)` and read back through the same route `Texture2D.GetData` uses, and every one
of its 32 pixels is exactly `(64, 128, 191, 255)`. That is a real GPU clear observed by a real
readback. The HEADLESS artifact runs the identical sequence, reports success from create, bind, clear
and unbind, and then refuses the readback — which is honest, and is precisely why no earlier
milestone could make this claim.

**A second thing was measured on the way there.** The same probe run from `LoadContent` instead of
`Draw` reads back transparent black while *every call still reports success*. A clear issued outside
the renderer's frame — outside what `BeginDraw`/`EndDraw` open and close — has no target to land on.
Nothing reports an error; the pixels simply are not there. Any future graphics evidence in this
project must be produced inside `Draw`.

## What it did *not* unblock, and the defect that explains it

`GraphicsAdapter` still cannot be projected truthfully, and the reason recorded in
`docs/graphics-adapter-audit-evidence.md` — *"the fabrication is a property of the qualified
artifact's build configuration"* — **is now measurably wrong**. See
`docs/graphics-adapter-ordering-upstream-defect.md`. The short form: with a real window, a real SDL3
platform and a live 1280×800 display, `cna_graphics_adapter_copy_description` still answers
`"Default Display"` with a fabricated 800×480 mode, because the adapter list is a static cache filled
*before* the video subsystem is acquired, and the ABI's only refresh route refuses by design.

## What it changed in the suite

Six tests failed under `OPENGL33` on the first run. Not one was a defect in the binding; each had
written a HEADLESS answer down as a literal.

| Test | Literal it pinned | Why the literal was the artifact's, not XNA's |
| --- | --- | --- |
| `GameIsActiveTest#test_a_host_that_never_ran_is_inactive` | `IsActive == false` | a host with a real focused window is active |
| `GameEventsTest#test_raising_activated_by_hand_does_not_make_the_game_active` | `IsActive == false` | same |
| `NativeIntegrationTest#test_run_one_frame_raises_no_exiting_and_no_activation` | no `Activated` in the callback order | a real window raises one |
| `GameWindowTest#test_allow_user_resizing_round_trips_through_the_real_route` | initial `false` | CNA's windowed default is `true` |
| `GameWindowTest#test_the_headless_host_answers_are_reported_rather_than_replaced` | `ClientBounds == 0,0,0,0` | a real window has a real rectangle |
| `Texture2DConstructionTest#test_the_two_managed_refusals_and_the_ones_that_are_cnas` | `Bgr565` raises `CapabilityError` | `OPENGL33` supports RGB565 texture storage |

Each now asserts the claim it always meant, against a fact measured from the same host:
`test/renderer_environment.rb` takes one snapshot per process — renderer name, native window system,
and per-format usage masks from `cna_graphics_device_get_surface_format_support_ext` — and the tests
branch on it. The last one is the clearest case: what it asserts is *"whether a non-`Color` format is
accepted is the renderer's answer and not this projection's"*, and it now reads that answer from the
renderer instead of predicting it. A format the renderer has not classified leaves the outcome
unasserted rather than guessed, because `graphics.h` states that an absent *known* bit means unknown
and forbids inferring support from the renderer name.

The snapshot is taken at **load time**, before any test runs, because CNA owns at most one C game per
process and measuring lazily from inside a test that already has one fails.

The suite is now **1448 runs / 0 failures / 0 errors / 0 skips against both artifacts**.

## The one environment limit worth recording

Creating and destroying tens of games in one process against a *windowed* renderer intermittently
fails inside SDL with `AcquireSubsystem(Video) failed: x11 not available`, because each game acquires
and releases the video subsystem and each acquisition opens a fresh X connection. It is not a binding
defect and not deterministic: the same suite run again passes. One long-lived game — which is what
the frame-stability runs and any real consumer use — is unaffected, 600 frames in a row.

## A third artifact, and the fresh-X-server rule

Foundation 80 added a third qualified artifact: `cmake-build-debug`'s `OPENGLES3` build with
`-DCNA_EASYGL_COMPILED_EFFECTS=ON`, staged as
`~/deps/cna-c-abi-0.21.0-opengles3-fx/libcna_c_api.so`, SHA-256
`ab055b5e9c10b57d9755445951b118406bc065ca9eaa3fe4c0851a2352bb3e6e`. It passes the same ABI gate, it
has a real X11 window and volume and cube storage like `OPENGL33`, and it is the only one of the
three whose `CNA_GRAPHICS_CAPABILITY_COMPILED_EFFECTS` is true — which is what makes `Effect`
constructible at all.

**The environment limit above has an exact remedy, and it is now the documented procedure.** One X
connection per game is a finite resource on this host, and it is not reclaimed within a run: a churn
test created 155 games before the 156th failed, and the *next* process failed at its 9th. Running
the whole suite under a windowed renderer in a **fresh** X server fixes it completely:

```sh
CNA_NATIVE_LIBRARY=~/deps/cna-c-abi-0.21.0-opengles3-fx/libcna_c_api.so \
CNA_TEST_FX=.../CnaConformanceEffect.fxb SDL_VIDEODRIVER=x11 \
xvfb-run -a -s "-screen 0 1280x800x24 -nolisten tcp" rake test
```

**`SDL_VIDEODRIVER=x11` in that command is load-bearing, and Foundation 81 measured what it is
worth.** This host runs a Wayland session, and `xvfb-run` sets `DISPLAY` without taking
`WAYLAND_DISPLAY` — or the default `wayland-0` socket under `XDG_RUNTIME_DIR` — away, so SDL picks
Wayland unless it is told not to. Under Wayland the `OPENGL33` artifact **segfaults inside
`cna_game_create`** after about thirty create/destroy cycles in one process: measured at the 30th,
30th and 35th game in three runs, and the crash is a null dereference in the artifact, not a Ruby
error. The same churn survives 200 games on `HEADLESS`, on `SOFTWARE`, on `OPENGLES3` and on
`OPENGL33` **with** `SDL_VIDEODRIVER=x11`. Two other things follow from the same cause and were also
measured: with SDL on Wayland the `OPENGLES3` artifact reports `CNA_NATIVE_WINDOW_SYSTEM_WAYLAND`
where the recorded run says `X11`, which is the staleness guard doing its job, and its window is
never activated, so `Game.Activated` does not fire. Forcing the X11 driver — rather than unsetting
`XDG_RUNTIME_DIR`, which also takes the audio device away — makes all three artifacts green again.

**A second environment flake, measured at Foundation 86 and recorded rather than hidden.** The
compiled-effects artifact intermittently fails to acquire SDL's video subsystem at
`cna_game_create`: *"AcquireSubsystem(Video) failed: x11 not available; this SDL build contains
these video drivers: wayland, x11, kmsdrm, offscreen, dummy, evdev"* — a driver the same message
lists as present. It appeared once in each of two consecutive whole-suite runs, on a different test
each time, and once at the sixth game of a 200-game churn; four further churns of forty games each
saw it not at all, and a rerun of the suite is green. It is rare, non-deterministic and specific to
the GLES/EGL artifact — `OPENGL33` under the same command has never shown it — so it is classified
as an environment flake rather than a defect in anything this repository builds. What it costs is
that a single green run of that artifact is not proof; two are.

1558 runs / 0 failures / 0 errors under each of the three artifacts at Foundation 86 — 50525
assertions and 21 skips on `HEADLESS`, 50540 and 17 on `OPENGL33`, 50626 and **none** on the
compiled-effects build — the difference being exactly the tests whose
behaviour needs a capability the artifact does not have, each of which says so. The environment
measurement itself is failure-tolerant: an unmeasurable environment is reported as unmeasured rather
than taking the suite down with it.

## Reproducing

```sh
Xvfb :77 -screen 0 1280x800x24 -nolisten tcp &
export CNA_HEADERS=~/deps/cna-c-abi-0.21.0/include
export CNA_ADMITTED_HEADERS=~/deps/cna-c-abi-0.7.0/include
export CNA_NATIVE_LIBRARY=~/deps/cna-c-abi-0.21.0-opengl33/libcna_c_api.so
export DISPLAY=:77 SDL_VIDEODRIVER=x11    # the driver is not optional -- see above

ruby -Ilib tools/native_abi/verify.rb            # ABI_MISMATCHES=0 on this artifact too
ruby -Ilib tools/run_renderer_qualification.rb   # writes docs/generated/renderer-native-report.json
rake test                                        # 1558 runs, 0 failures, 17 skips on this artifact
```

Running it against the HEADLESS artifact writes the second entry of the same report, and the
difference between the two entries is the evidence.
