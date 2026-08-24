# Foundation 6 Mouse evidence

This milestone is limited to `Microsoft.Xna.Framework.Input.ButtonState`, `MouseState`, and
`Mouse`: 3 public XNA types, 20 CLR member identities, and 19 Ruby identities after the existing
`value__` enum-storage exclusion.

## Pre-implementation native capability inventory

Canonical headers were inspected at CNA revision `1bb2145d99ed572dd4eb15009c34e2e5f410fcf0`
(`CNA_ABI_VERSION == 0x00000700`). The exact retained qualified library is
`/tmp/cna-python-m8-build2/modules/c-api/libcna_c_api.so`, SHA-256
`c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`, built from CNA revision
`a09196a6477f69a7a57c8364f990658d31531a5b`. The four prototypes below are identical in that
source revision and the current canonical headers.

| XNA_MOUSE_REQUIREMENT | CNA_SYMBOL | EXISTS_IN_HEADER | EXISTS_IN_LOADED_LIBRARY | PROTOTYPE | SEMANTIC_FIT | OWNERSHIP | THREAD_REQUIREMENT | STATUS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GetState()` | `cna_mouse_get_state` | yes, `input.h` | yes | `CNA_Result (CNA_Handle, CNA_MouseState*)` | Fresh native snapshot; logical/window-client X/Y, raw cumulative 120-unit vertical wheel, five independent button bits | borrows active Game; caller owns copied POD output | game creation/owner thread | `VERIFIED_NATIVE_ROUTE` |
| `SetPosition(Int32, Int32)` | `cna_mouse_set_position` | yes, `input_mouse.h` | yes | `CNA_Result (CNA_Handle, int32_t, int32_t)` | XNA window-relative logical coordinates; CNA converts to the bound backend window and preserves CNA/XNA no-result behavior when a backend cannot warp | borrows active Game; owns nothing | game creation/owner thread | `VERIFIED_NATIVE_ROUTE` |
| `WindowHandle` get | `cna_mouse_get_window_handle` | yes, `input_mouse.h` | yes | `CNA_Result (CNA_Handle, uint64_t*)` | Reads the process-global opaque native-window compatibility token; zero means unbound; it is explicitly not a `CNA_Handle` | borrows active Game; returns a borrowed external scalar bit pattern | game creation/owner thread | `VERIFIED_NATIVE_ROUTE` |
| `WindowHandle` set | `cna_mouse_set_window_handle` | yes, `input_mouse.h` | yes | `CNA_Result (CNA_Handle, uint64_t)` | Sets the process-global opaque native-window compatibility token; zero unbinds; CNA never dereferences it at the C boundary | borrows active Game and external scalar; owns/frees neither | game creation/owner thread | `VERIFIED_NATIVE_ROUTE` |

No SDL or platform symbol is used directly. No CNA source, header, library, or ABI is modified.

## ButtonState

`ButtonState` is the established typed, frozen, non-flags enum projection. `Released` is exactly
`0` and `Pressed` is exactly `1`; the synthetic `value__` CLR field is the only formally excluded
identity. The public boundary accepts typed values and the already-established enum coercion route
for raw `0`/`1`, always storing and returning `ButtonState`. Booleans and all other integers are
rejected. The type closes 3 CLR identities as 2 Ruby identities and has zero local diagnostics.

## Managed MouseState contract

The behavior authority is the XNA 4.0 Windows runtime assembly
`Microsoft.Xna.Framework.dll`, SHA-256
`38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`, and its inspected IL.
`MouseState` closes all 14 identities without adding a typed `Equals(MouseState)` overload.

The exact constructor order is `x`, `y`, `scrollWheel`, `leftButton`, `middleButton`,
`rightButton`, `xButton1`, `xButton2`. The read-only property order is `X`, `Y`, `LeftButton`,
`RightButton`, `MiddleButton`, `XButton1`, `XButton2`, `ScrollWheelValue`. The asymmetric fixture
`(-17, 203, -120, Pressed, Released, Pressed, Pressed, Released)` proves that middle and right are
not transposed. X, Y, and the raw cumulative wheel value are exact signed Int32 values; no wheel
step normalization occurs.

`Equals(Object)`, `==`, and `!=` compare all eight XNA components. One-field-difference cases cover
every component. `GetHashCode` is the unchecked signed-Int32 XOR of X, Y, all five enum values, and
the wheel value. The retained golden state `(12, -3, 120, Pressed, Released, Pressed, Pressed,
Released)` hashes to `-120` and prints exactly
`{X:12 Y:-3 Buttons:Left Right XButton1 Wheel:120}`. Button labels are emitted in XNA order Left,
Right, Middle, XButton1, XButton2; the empty label is `None`.

MouseState is `MANAGED_VALUE`. Construction, `dup`, `clone`, and every native snapshot have
independent state. Native memory and buffers are never public and are not retained by a snapshot.
Ruby assignment aliasing remains the existing documented struct-language limitation. Int32 minimum
and maximum values are qualified for X, Y, and ScrollWheelValue.

## Measured native snapshot

The compiler-backed `CNA_MouseState` measurement is size 32 and alignment 4. Its complete layout is:

| CNA field | C type | offset | Ruby use |
| --- | --- | ---: | --- |
| `struct_size` | `uint32_t` | 0 | initialized to 32 |
| `struct_version` | `uint32_t` | 4 | initialized to canonical version |
| `x` | `int32_t` | 8 | X |
| `y` | `int32_t` | 12 | Y |
| `scroll_wheel` | `int32_t` | 16 | ScrollWheelValue, unchanged |
| `horizontal_scroll_wheel` | `int32_t` | 20 | not exposed by the pinned XNA contract |
| `pressed_buttons` | `CNA_MouseButtonFlags` (`uint32_t`) | 24 | decoded by named masks |
| `reserved` | `uint32_t` | 28 | not exposed |

The explicit button mapping is LEFT (1) -> LeftButton, MIDDLE (2) -> MiddleButton, RIGHT (4) ->
RightButton, X1 (8) -> XButton1, and X2 (16) -> XButton2. A retained asymmetric native fixture
proves the mapping and proves that successive conversions return distinct managed values.

## Process-global Mouse and native context

`Mouse` is a nonconstructible static facade with ownership `PROCESS_GLOBAL`; it has no handle,
instance state, disposal, or finalizer. The native CNA calls need a Game handle, so the facade
internally resolves the current live Game on its owner thread and borrows its host only for the
duration of the call. This internal dependency is absent from the public XNA signatures.

With no current initialized Game, after shutdown, or with ambiguous live contexts, operations raise
`InvalidBindingStateError` instead of fabricating state. Calls work during callbacks and while one
initialized Game is live. All four operations reject a non-owner Ruby thread with
`OwnerThreadError` before entering CNA; a subsequent owner-thread retry succeeds. After Game 1 is
disposed, Game 2 is selected afresh, so no stale generation/handle is retained. Native result
failures for every route are translated by `CNA::Native.library.call`.

`GetState` calls `cna_mouse_get_state` and copies the measured native result into a new managed
MouseState each time. `SetPosition` validates exact signed Int32 coordinates and calls
`cna_mouse_set_position`; it never mutates cached Ruby state. `WindowHandle` get/set call the two
canonical window-handle functions and never reinterpret a Game/CNA handle as a window handle.
The external window scalar is `BORROWED_EXTERNAL_SCALAR`; Ruby and CNA-Ruby never free, close, or
destroy it.

## IntPtr mapping

`System.IntPtr` maps publicly to a signed native-width Ruby `Integer`. Width is measured with
`Fiddle::SIZEOF_VOIDP`; it is 8 bytes / 64 bits on the qualified Linux x86-64 host. The qualified
accepted interval is `-9223372036854775808..9223372036854775807`. Values outside the exact signed
native-width interval and non-Integer values, including `Fiddle::Pointer`, are rejected.

At the native boundary, the signed value is preserved as its same-width two's-complement bit
pattern in CNA's fixed `uint64_t` compatibility carrier; reads narrow to native width and sign
extend. Thus `-1` remains the native all-bits-one IntPtr value without making the public mapping a
UIntPtr. `Fiddle::Pointer`, `CNA_Handle`, `void*`, and raw native buffers never cross the public API.

## HEADLESS qualification and limitations

The exact artifact's HEADLESS backend returns a real backend snapshot through CNA. A zero/released
state is accepted only as that observed backend result. The real SetPosition route executes, but no
physical cursor movement or immediate state round trip is claimed. WindowHandle zero/null and a
non-destructive same-token set/get are qualified; an arbitrary nonzero desktop window is
`PLATFORM_PENDING`. Physical cursor and visible window integration remain `BACKEND_BLOCKED` on the
qualified artifact. These limitations do not replace or simulate any Mouse member.

## ABI delta and qualification

| Measurement | before | after |
| --- | ---: | ---: |
| bound functions | 30 | 34 |
| signature measurements | 90 | 103 |
| C layout measurements | 158 | 176 |
| Ruby layout measurements | 158 | 176 |
| callbacks | 2 | 2 |
| constants | 12 | 17 |

New bound functions are exactly the four symbols in the inventory. The only new layout is
`CNA_MouseState`. New constants are `CNA_MOUSE_BUTTON_LEFT`, `CNA_MOUSE_BUTTON_MIDDLE`,
`CNA_MOUSE_BUTTON_RIGHT`, `CNA_MOUSE_BUTTON_X1`, and `CNA_MOUSE_BUTTON_X2`. Missing header symbols,
missing library symbols, and ABI mismatches are all zero.

No `cna_mouse_state_*` helper is bound: ButtonState and MouseState are pure managed XNA values, and
the inspected XNA runtime IL remains their behavior authority. Binding adjacent helpers would add
unused ABI and, for hash behavior, would incorrectly substitute CNA behavior for the pinned XNA
Windows runtime contract.

The PURE_XNA_DERIVED corpus is 208 observations / 208 assertions / 0 failures, including
BUTTON_STATE=2 and MOUSE_STATE=13. CNA/backend observations remain separately identified as native
integration evidence rather than being mislabeled PURE_XNA_DERIVED. Native qualification exercises
all four routes, safe HEADLESS behavior, callback use, native-error containment, owner-thread
rejection/retry, shutdown, and Game-generation replacement. Stress includes 50 safe Mouse GetState
cycles in addition to the retained 20 Game/Texture/SpriteBatch/recreation cycles, with no observed
crash, UAF, or double-free. Sanitizers were not run.

## Local strict-zero matrix

Each of `ButtonState`, `MouseState`, and `Mouse` has local diagnostics=0. For each type,
`MISSING_MEMBER`, `TYPE_KIND_MISMATCH`, `BASE_MAPPING_MISMATCH`, `INTERFACE_MAPPING_MISMATCH`,
`FIELD_MAPPING_MISMATCH`, `PROPERTY_MAPPING_MISMATCH`, `METHOD_SIGNATURE_MAPPING_MISMATCH`,
`PARAMETER_MAPPING_MISMATCH`, `RETURN_MAPPING_MISMATCH`, `OVERLOAD_MAPPING_MISMATCH`,
`GENERIC_MAPPING_MISMATCH`, `ENUM_VALUE_MISMATCH`, `FLAGS_MAPPING_MISMATCH`,
`EVENT_MAPPING_MISMATCH`, `OPERATOR_MAPPING_MISMATCH`, and `LANGUAGE_MAPPING_MISMATCH` are zero.
The global allowlist, unmeasured structural category, raw-handle leak, and public-native-FFI leak
counts also remain zero.

## Release evidence

The full suite is 136 runs / 2759 assertions / 0 failures / 0 errors / 0 skips. RBS validation,
runtime/RBS consistency, verifier self-tests, leak-only mode, complete Keyboard regression, native
integration, and compiler-backed ABI verification pass. The exact final artifact is
`cna-ruby-0.1.0.dev0.gem`, SHA-256
`b7d5751c36b15f5b1f4f9d02f4574e390c201b26c4150175cc7d17701157126b`, with 35 entries, no
forbidden entries, bundled native library, or developer-path leak.

The maintained template remains at commit `42ae209b8b4fd175b7b1e5de43d895083b81877b`, with source-tree
SHA-256 `1365fa309f84673c4f932039010cb1c75c31ec4fd4e2433fdc2f93efe64d43f1` before and after
qualification. Its source is unchanged. Maintained-source and isolated exact-gem runs both pass at
60 updates/draws and 600 updates/draws.
