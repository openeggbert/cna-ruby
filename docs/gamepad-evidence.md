# Foundation 7 GamePad evidence

This milestone is limited to the dependency-contained XNA GamePad family. The pinned XNA 4.0
Windows runtime metadata independently regenerates exactly 10 source types, 129 CLR member
identities, and 126 Ruby identities after excluding the synthetic `value__` field from each of
`Buttons`, `GamePadDeadZone`, and `GamePadType`.

The closure is `Buttons`, `GamePad`, `GamePadButtons`, `GamePadCapabilities`, `GamePadDPad`,
`GamePadDeadZone`, `GamePadState`, `GamePadThumbSticks`, `GamePadTriggers`, and `GamePadType`.
Its only external XNA signature dependencies are the already-complete `ButtonState`,
`PlayerIndex`, and `Vector2`. Touch is not a dependency.

## Pre-binding canonical CNA capability inventory

Canonical headers were inspected at CNA revision `1bb2145d99ed572dd4eb15009c34e2e5f410fcf0`
(`CNA_ABI_VERSION == 0x00000700`). The exact qualified library is
`/tmp/cna-python-m8-build2/modules/c-api/libcna_c_api.so`, SHA-256
`c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`, built from CNA revision
`a09196a6477f69a7a57c8364f990658d31531a5b`. A revision diff proves that the selected GamePad
headers and C implementation are unchanged between those revisions. All four selected symbols are
exported by that exact library.

| XNA_REQUIREMENT | CNA_SYMBOL | HEADER_EXISTS | LIBRARY_EXPORT_EXISTS | C_PROTOTYPE | SEMANTIC_FIT | STATE_LAYOUT | OWNERSHIP | THREAD_REQUIREMENT | BACKEND_LIMIT | STATUS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GetState(PlayerIndex)` | `cna_gamepad_get_state` | yes, `input.h` | yes | `CNA_Result (CNA_Handle, CNA_PlayerIndex, CNA_GamePadState*)` | Fresh canonical IndependentAxes snapshot with real connection, packet, physical/virtual button mask, sticks, and triggers | versioned `CNA_GamePadState`, caller output | borrows active Game; caller copies POD | Game owner thread before platform/cache access | HEADLESS can prove disconnected state only without controller hardware | `VERIFIED_NATIVE_ROUTE` |
| `GetState(PlayerIndex, GamePadDeadZone)` | `cna_gamepad_get_state_with_dead_zone` | yes, `input.h` | yes | `CNA_Result (CNA_Handle, CNA_PlayerIndex, CNA_GamePadDeadZone, CNA_GamePadState*)` | Explicit None, IndependentAxes, and Circular processing through the canonical route | same state POD | borrows active Game; caller copies POD | Game owner thread | positive analog/dead-zone cases require controller hardware | `VERIFIED_NATIVE_ROUTE` / `HARDWARE_PENDING` |
| `GetCapabilities(PlayerIndex)` | `cna_gamepad_get_capabilities` | yes, `input_gamepad.h` | yes | `CNA_Result (CNA_Handle, CNA_PlayerIndex, CNA_GamePadCapabilities*)` | Returns the selected device type, connection flag, every selected XNA button/axis/trigger/motor capability, and voice support individually | versioned `CNA_GamePadCapabilities`, caller output | borrows active Game; caller copies POD | Game owner thread | connected-device positive flags are hardware-pending | `VERIFIED_NATIVE_ROUTE` / `HARDWARE_PENDING` |
| `SetVibration(PlayerIndex, Single, Single)` | `cna_gamepad_set_vibration` | yes, `input_gamepad.h` | yes | `CNA_Result (CNA_Handle, CNA_PlayerIndex, float, float, CNA_Bool*)` | Real selected-device rumble request; Boolean reports whether the device accepted it | no retained layout | borrows active Game; no Ruby/native state retained | Game owner thread before actuator access | no controller/no rumble returns false; positive actuation is hardware-pending | `VERIFIED_NATIVE_ROUTE` / `HARDWARE_PENDING` |

`CNA_PlayerIndex` explicitly maps One, Two, Three, and Four to 0, 1, 2, and 3. The selected
`CNA_GamePadDeadZone` identities explicitly map None, IndependentAxes, and Circular to 0, 1, and
2. The CNA button bits used by XNA are intentionally identical to the pinned XNA bit identities;
CNA extension-only controller bits are not projected. CNA controller type 9 (`BIG_BUTTON_PAD`)
is deliberately not cast to XNA: it maps explicitly to XNA `GamePadType.BigButtonPad` 768.

The canonical SDL3 platform adapter is below the CNA boundary and is never called by Ruby. Its
reviewed mapping inverts both native thumbstick Y axes into XNA's Y-up convention before publishing
the CNA snapshot. Its published trigger domain is float `[0,1]`; CNA-Ruby does not assume an XInput
byte carrier. Packet numbers come from the CNA platform snapshot and are never synthesized in Ruby.

The native PODs are call-duration temporaries. `GamePadState` and `GamePadCapabilities` returned to
Ruby are independent `MANAGED_VALUE` snapshots. `GamePad` itself is `PROCESS_GLOBAL` and retains no
Game or controller handle.

## Exact type and identity matrix

| Type | Reference | Expected Ruby | Target Ruby | Local diagnostics | Kind | Behavior | Native |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| `Buttons` | 26 | 25 | 25 | 0 | flags enum / Int32 | `VERIFIED_MANAGED` | n/a |
| `GamePad` | 4 | 4 | 4 | 0 | static sealed class | `VERIFIED_MANAGED` + native-negative | `VERIFIED_NATIVE_ROUTE`; positive hardware pending |
| `GamePadButtons` | 17 | 17 | 17 | 0 | struct | `VERIFIED_MANAGED` | n/a |
| `GamePadCapabilities` | 26 | 26 | 26 | 0 | struct | `VERIFIED_MANAGED` snapshots | `VERIFIED_NATIVE_ROUTE`; positive flags pending |
| `GamePadDPad` | 10 | 10 | 10 | 0 | struct | `VERIFIED_MANAGED` | n/a |
| `GamePadDeadZone` | 4 | 3 | 3 | 0 | enum / Int32 | `VERIFIED_MANAGED` | n/a |
| `GamePadState` | 15 | 15 | 15 | 0 | struct | `VERIFIED_MANAGED` | `VERIFIED_NATIVE_ROUTE` |
| `GamePadThumbSticks` | 8 | 8 | 8 | 0 | struct | `VERIFIED_MANAGED` | n/a |
| `GamePadTriggers` | 8 | 8 | 8 | 0 | struct | `VERIFIED_MANAGED` | n/a |
| `GamePadType` | 11 | 10 | 10 | 0 | enum / Int32 | `VERIFIED_MANAGED` | explicit native mapping |

The three identity differences are only the CLR enum-storage fields. No selected type is partial,
and no existing partial type changed.

## Enums and flags

`Buttons` is a typed frozen `[Flags]` projection with these exact raw values:

| Name | Raw | Name | Raw |
| --- | ---: | --- | ---: |
| `DPadUp` | 1 | `DPadDown` | 2 |
| `DPadLeft` | 4 | `DPadRight` | 8 |
| `Start` | 16 | `Back` | 32 |
| `LeftStick` | 64 | `RightStick` | 128 |
| `LeftShoulder` | 256 | `RightShoulder` | 512 |
| `BigButton` | 2048 | `A` | 4096 |
| `B` | 8192 | `X` | 16384 |
| `Y` | 32768 | `LeftThumbstickLeft` | 2097152 |
| `RightTrigger` | 4194304 | `LeftTrigger` | 8388608 |
| `RightThumbstickUp` | 16777216 | `RightThumbstickDown` | 33554432 |
| `RightThumbstickRight` | 67108864 | `RightThumbstickLeft` | 134217728 |
| `LeftThumbstickUp` | 268435456 | `LeftThumbstickDown` | 536870912 |
| `LeftThumbstickRight` | 1073741824 |  |  |

The existing flags mapping supports typed `|` and `&`, named values, zero, and any combination of
declared bits through mask `0x7fe0fbff`. It rejects unknown bit `0x400`, bit 31, and arbitrary
non-integers. This is the existing formal Ruby flags policy; no special GamePad-only flags API was
added. The verifier now measures flags metadata, Int32 underlying type, and runtime combination
mask independently.

`GamePadDeadZone` is non-flags: `None=0`, `IndependentAxes=1`, `Circular=2`.
`GamePadType` is non-flags: `Unknown=0`, `GamePad=1`, `Wheel=2`, `ArcadeStick=3`,
`FlightStick=4`, `DancePad=5`, `Guitar=6`, `AlternateGuitar=7`, `DrumKit=8`, and
`BigButtonPad=768`. Undefined raw values are rejected by the existing non-flags enum policy.

## Managed value behavior

`GamePadButtons(Buttons)` retains only A, B, X, Y, Back, Start, Left/Right Shoulder,
Left/Right Stick, and BigButton. DPad and all ten analog-derived flags do not create properties or
participate in this value. Combined inputs use bit tests. Its string order is A, B, X, Y,
LeftShoulder, RightShoulder, LeftStick, RightStick, Start, Back, BigButton. `None` is rendered when
empty.

`GamePadDPad(upValue, downValue, leftValue, rightValue)` preserves that constructor order while
presenting properties Up, Down, Right, Left. Its string order is Up, Down, Left, Right; asymmetric
fixtures prevent an accidental left/right swap.

`GamePadTriggers(leftTrigger, rightTrigger)` narrows to binary32, applies XNA's ordered
`Math.Min(value, 1)` then `Math.Max(value, 0)`, and therefore clamps finite values and infinities to
`[0,1]`, preserves NaN, and converts negative zero to positive zero. It does not use CNA/FNA's
epsilon equality.

`GamePadThumbSticks(left, right)` applies component-wise `Vector2.Min(value, One)` followed by
`Vector2.Max(value, -One)`. This is a square clamp, not normalization to the unit circle. NaN
components become positive one through XNA `Vector2.Min/Max` comparison order; infinities clamp to
the endpoint and negative zero is retained. `Left` and `Right` return independent `Vector2` copies.

For `GamePadButtons`, `GamePadDPad`, `GamePadTriggers`, and `GamePadThumbSticks`, equality compares
their exact XNA fields. Hashes reproduce `Helpers.SmartGetHashCode`: XOR every raw Int32-sized word
of the XNA struct and return `Int32.MaxValue` when the XOR is zero. Strings are respectively
`{Buttons:...}`, `{DPad:...}`, `{Left:... Right:...}`, and
`{Left:{X:... Y:...} Right:{X:... Y:...}}` under the existing invariant qualification culture.

## GamePadState

Both public constructors are retained as distinct formal identities. The component constructor
copies `GamePadThumbSticks`, `GamePadTriggers`, `GamePadButtons`, and `GamePadDPad`. The vector/float
constructor accepts a Ruby `Array[Buttons]`; `nil` reproduces CLR null and acts like an empty array,
repeated and combined entries are ORed, and scalar or wrongly typed entries are rejected. Analog
flags supplied in the array are ignored because XNA derives them from the analog fields.

Both public XNA constructors set `IsConnected=true` and `PacketNumber=0`. A private native snapshot
path alone may set the real CNA connection and packet values; it is not an RBS or public XNA
constructor. `Buttons`, `DPad`, `ThumbSticks`, and `Triggers` return independent nested copies on
every access. Constructor sources and returned copies cannot mutate the state.

`IsButtonDown` requires **all** requested bits. `A|B` is down only when both are down; zero is down
and therefore `IsButtonUp(0)` is false. `IsButtonUp` is the exact negation. Ordinary and DPad bits
come from the corresponding managed fields. Analog virtual flags use XNA's independent-axis tests
regardless of the state capture mode:

- left stick: raw signed short strictly below `-7849` or above `7849`;
- right stick: raw signed short strictly below `-8689` or above `8689`;
- triggers: raw byte strictly above `30`.

Public-constructor values are first quantized exactly as XNA does: `(short)(value*32767)` and
`(byte)(value*255)`. For native states, CNA extension bits and CNA's derived flag result are not
trusted as XNA query truth. Ruby retains only the lower physical `0x0000fbff` bits and reconstructs
the XNA virtual result from the mode-specific analog snapshot. IndependentAxes uses the sign of
the rescaled result, None applies the raw threshold, and Circular reverses the radial rescale before
the independent-axis threshold test. This specifically avoids importing CNA/FNA's different
virtual-button implementation.

State equality includes connection, packet, thumbsticks, triggers, buttons, and DPad. Its hash is
the Int32 XOR of those five nested hashes, Boolean hash, and packet hash. Its exact string is only
`{IsConnected:True}` or `{IsConnected:False}`.

## Dead-zone routes

The one-argument overload is proven by XNA source to select `IndependentAxes`; it is not a guessed
default. XNA's reference integer algorithm is:

1. if `value < -deadZone`, add the zone; if `value > deadZone`, subtract it; otherwise return zero;
2. divide by `maxValue-deadZone`;
3. clamp to the destination range in binary32 order.

Stick `maxValue` is 32767, left/right dead zones are 7849 and 8689, and trigger `maxValue` and dead
zone are 255 and 30. None uses dead zone zero but still clamps components. IndependentAxes applies
the formula separately to X and Y. Circular computes the raw magnitude, applies the same linear
formula to that magnitude, multiplies each original component by `newMagnitude/rawMagnitude`, and
clamps each component. Trigger dead zone is disabled only for None; IndependentAxes and Circular
both use 30. The canonical CNA header publishes equivalent normalized thresholds
`7849/32768`, `8689/32768`, and `30/255` and exposes all three real modes. Exact positive boundary
and rescaling behavior is reference/managed-qualified; the current no-controller host cannot add
physical analog evidence.

The reviewed SDL adapter below CNA maps signed stick axes to `[-1,1]`, inverts both Y axes to XNA
Y-up, and maps triggers to `[0,1]`. Ruby never calls SDL and does not expose its carriers.

## Capabilities

`GamePadCapabilities` has no public Ruby constructor and no invented declared equality, hash, or
string member. Every native call creates a fresh private managed snapshot. The complete mapping is:

| XNA property | Canonical field | XNA property | Canonical field |
| --- | --- | --- | --- |
| `GamePadType` | `gamepad_type` via explicit table | `IsConnected` | `is_connected` |
| `HasAButton` | `has_a_button` | `HasBButton` | `has_b_button` |
| `HasXButton` | `has_x_button` | `HasYButton` | `has_y_button` |
| `HasBackButton` | `has_back_button` | `HasStartButton` | `has_start_button` |
| `HasBigButton` | `has_big_button` | `HasDPadUpButton` | `has_dpad_up_button` |
| `HasDPadDownButton` | `has_dpad_down_button` | `HasDPadLeftButton` | `has_dpad_left_button` |
| `HasDPadRightButton` | `has_dpad_right_button` | `HasLeftShoulderButton` | `has_left_shoulder_button` |
| `HasRightShoulderButton` | `has_right_shoulder_button` | `HasLeftStickButton` | `has_left_stick_button` |
| `HasRightStickButton` | `has_right_stick_button` | `HasLeftXThumbStick` | `has_left_x_thumb_stick` |
| `HasLeftYThumbStick` | `has_left_y_thumb_stick` | `HasRightXThumbStick` | `has_right_x_thumb_stick` |
| `HasRightYThumbStick` | `has_right_y_thumb_stick` | `HasLeftTrigger` | `has_left_trigger` |
| `HasRightTrigger` | `has_right_trigger` | `HasLeftVibrationMotor` | `has_left_vibration_motor` |
| `HasRightVibrationMotor` | `has_right_vibration_motor` | `HasVoiceSupport` | `has_voice_support` |

Native types 0 through 8 map to their same semantic XNA names, native type 9 maps explicitly to
XNA raw 768, and an unknown native identity maps to `Unknown`. Motor capability flags come from the
selected device fields, never the existence of a global function. Voice is a real canonical field;
the qualified Linux/no-controller snapshot reports false. Positive voice support remains platform
and hardware pending rather than being inferred.

## Static facade, context, and vibration

`GamePad` is nonconstructible, process-global, has no handle and no disposal. Every call selects the
unique current live Game, rejects an absent, ambiguous, uninitialized, shut down, or wrong-thread
context before native entry, and borrows only the current call's Game handle. Game-1 disposal and
Game-2 creation reselect Game-2; no handle is cached. All four players use an explicit reviewed
One→0, Two→1, Three→2, Four→3 conversion.

XNA `SetVibration` converts each binary32 motor input with `(short)(value*65535)` before its native
call. CNA's public route accepts floats, so Ruby converts to the corresponding 16-bit word and then
passes the normalized word through the real canonical actuator route. This preserves XNA's
observable wrap behavior for negative and greater-than-one finite values and maps NaN/infinities to
the conversion word established by CLR IL evidence. The returned Boolean is solely CNA/backend
`out_applied`; Ruby never substitutes success. On the qualified host the safe all-off request
returned false because no controller was connected. Nonzero physical motor evidence is
`HARDWARE_PENDING`, and no vibration stress loop ran.

## Compiler-backed native layout and ABI delta

The independent C11 probe verifies:

- `CNA_Vector2`: size 8, alignment 4, X/Y offsets 0/4;
- `CNA_GamePadAnalogState`: size 24, alignment 4, stick offsets 0/8 and trigger offsets 16/20;
- `CNA_GamePadState`: size 48, alignment 4, connection 8, packet 12, buttons 16, analog 24;
- `CNA_GamePadCapabilities`: size 48, alignment 4, type 8, connection 12, the selected Boolean
  fields 13 through 36, extensions 37 through 46, and reserved byte 47.

Foundation 6 → 7: bound functions 34→38, signature measurements 103→122, C layouts 176→290,
Ruby layouts 176→290, callbacks 2→2, and constants 17→59. The exact new functions are the four in
the inventory; the exact new layouts are the four above; the 42 constants are four players, three
dead zones, 25 selected XNA button bits, and ten CNA types. Missing header symbols, missing library
symbols, and ABI mismatches are zero.

## Qualification and strict-zero result

The pure corpus grows from 208 to 239 observations/assertions with zero failures. New separate
groups are `BUTTONS=4`, `GAMEPAD_BUTTONS=4`, `GAMEPAD_DPAD=4`, `GAMEPAD_TRIGGERS=5`,
`GAMEPAD_THUMBSTICKS=5`, `GAMEPAD_STATE=7`, and `GAMEPAD_ENUMS=2`. Native results are kept outside
those totals in `docs/generated/gamepad-native-report.json`.

All four players returned real `CNA_RESULT_SUCCESS` disconnected snapshots under HEADLESS. State,
all three explicit modes, capabilities, and a safe all-off vibration request executed. No
controller was connected; state/capability positive cases and physical vibration remain
`HARDWARE_PENDING`. Stress completed 20 Game/Texture/SpriteBatch/recreation cycles, 50 GamePad
state calls, and 20 capability calls with zero observed crash, UAF, or double-free. Wrong-thread,
shutdown, ambiguity, and generation-reselection checks pass.

The complete source suite passes 161 runs / 3677 assertions with no failure, error, or skip; this
includes Mouse, Keyboard, runtime/RBS consistency, and verifier regressions. RBS validation and
bundle consistency pass independently. The unchanged template passes maintained-source and fresh
isolated exact-gem runs at both 60 and 600 frames. The final 35-entry gem is
`cna-ruby-0.1.0.dev0.gem`, SHA-256
`2971d2fb1c179639849be041acc7a76ba5da58ea135b8c589db5181f43969694`, with no forbidden entry,
bundled native library, or developer path.

For every selected type, every local category is zero: missing/unexpected members; kind, base,
interface, field, property, method, parameter, return, overload, generic, enum, flags, event,
operator, and language mismatches; internal/raw/public-native leaks; allowlist entries; and
unmeasured structural categories.

Because every required static member has a real canonical CNA route, absence of attached hardware
does not replace any result with a Ruby default, and all required structural and qualification
gates above pass, `FOUNDATION_MILESTONE_7_COMPLETE=true`. Positive controller observations remain
explicitly hardware-pending and are not part of that claim.
