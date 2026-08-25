# Native ABI Qualification

The Foundation 1 admission policy retained unchanged through Foundation 7 admits exactly CNA C ABI 0.7.0 (`0x00000700`). Newer 0.x and same-major versions are rejected until separately reviewed.

The retained qualification artifact used for this milestone is:

- CNA source revision: `a09196a6477f69a7a57c8364f990658d31531a5b`
- library: external `libcna_c_api.so`
- SHA-256: `c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`
- platform: Linux x86-64
- renderer: HEADLESS
- audio: NULL

It is not bundled and its temporary qualification location is not a runtime default. Consumers set `CNA_NATIVE_LIBRARY` to an absolute path. Production resolution then considers a future package-native directory and platform dynamic-loader names; it never searches developer sibling repositories.

The reviewed manifest records exact C type names, pointer depth, constness, fixed width, signedness, CNA_Bool/enum representation, ownership, result lifetime, and callbacks. `tools/native_abi/verify.rb` compiles an independent C probe against canonical headers, compares structure size/alignment/offsets and constants with Ruby declarations, type-checks every function/callback prototype, and checks exports in the actually loaded library.

Foundation 6 binds four already-existing reviewed functions and no adjacent input API: `cna_mouse_get_state`, `cna_mouse_set_position`, `cna_mouse_get_window_handle`, and `cna_mouse_set_window_handle`. It measures the complete `CNA_MouseState` layout and the five consumed button-bit constants. The compiler-backed delta is 30 -> 34 bound functions, 90 -> 103 signature measurements, 158 -> 176 C layout measurements, 158 -> 176 Ruby layout measurements, 2 -> 2 callbacks, and 12 -> 17 constants. Missing header symbols, missing library symbols, and ABI mismatches remain zero.

Foundation 7 binds exactly four already-existing canonical controller routes and no adjacent
extension API: `cna_gamepad_get_state`, `cna_gamepad_get_state_with_dead_zone`,
`cna_gamepad_get_capabilities`, and `cna_gamepad_set_vibration`. The compiler measures
`CNA_Vector2`, `CNA_GamePadAnalogState`, `CNA_GamePadState`, and
`CNA_GamePadCapabilities`, including every field and reserved byte. Forty-two consumed constants
cover four player slots, three dead-zone modes, 25 XNA button bits, and ten CNA device types.

The exact Foundation 6 -> 7 delta is 34 -> 38 bound functions, 103 -> 122 signature
measurements, 176 -> 290 C layout measurements, 176 -> 290 Ruby layout measurements, 2 -> 2
callbacks, and 17 -> 59 constants. `MISSING_HEADER_SYMBOLS`, `MISSING_LIBRARY_SYMBOLS`, and
`ABI_MISMATCHES` are all zero. CNA extension buttons, sensors, GUID/name, battery, LED, touchpad,
and trigger-rumble APIs are deliberately not bound.

`cna_viewport_get_title_safe_area` is intentionally not bound: its canonical prototype passes `CNA_Viewport` by value, a contract this Fiddle-only foundation does not claim to marshal portably.

## Native frontier 1: the framework dispatcher

This milestone binds exactly one already-existing canonical route and no adjacent API:
`cna_framework_dispatcher_update`. It measures no new structure and consumes no new constant, so
the delta touches only the function and signature counts.

The exact Foundation 7 -> Native frontier 1 delta is 38 -> 39 bound functions, 122 -> 124
signature measurements, 290 -> 290 C layout measurements, 290 -> 290 Ruby layout measurements,
2 -> 2 callbacks, and 59 -> 59 constants. `MISSING_HEADER_SYMBOLS`, `MISSING_LIBRARY_SYMBOLS`, and
`ABI_MISMATCHES` are all zero. Every measurement carried over from Foundation 7 is byte- and
signature-identical: the manifest entry was inserted, nothing existing was edited, and the probe
type-checks all 39 prototypes against the same canonical headers.

The retained qualification artifact is unchanged. **No CNA source change was made and no new
native binary was built**, because the audit that opened this milestone found the canonical C ABI
already exposes everything the milestone needed — see
`docs/graphics-adapter-audit-evidence.md`, which also records why the same is true of the
GraphicsAdapter surface this session set out to reach.

`cna_framework_dispatcher_update(CNA_Handle game)` takes the game handle for thread affinity only;
the canonical dispatcher behind it is static. It answers `CNA_RESULT_SUCCESS` inside and outside a
lifecycle callback, `CNA_RESULT_INVALID_HANDLE` for a zero or unknown handle, and
`CNA_RESULT_THREAD` off the owner thread — each observed against the retained artifact before the
route was bound.
