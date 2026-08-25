# Foundation 32 — `TouchPanel`, and the closing of `Input.Touch`

One type, 14 Ruby identities, and the last missing member of its namespace. `Input.Touch` is now
complete: `TouchLocationState`, `GestureType`, `TouchPanelCapabilities`, `TouchLocation`,
`GestureSample`, `TouchCollection`, `TouchCollection+Enumerator` and `TouchPanel`.

## The measurement the whole milestone rests on

**The pinned XNA 4.0 Windows `Input.Touch` assembly is a stub.** XNA's touch support was for Windows
Phone; the Windows assembly keeps the shape and answers constants.

That is a measurement, not a reading of history:

- the hash-admitted IL inventory records `nativeReachable: false` and an empty
  `nativeReachableMethods` for **all eight** types the assembly declares;
- `Touch::WindowHandle`, the only thing in it that looks like a platform hook, is a plain static
  field read;
- `TouchPanelCapabilities::GetCaps` is `initobj; ret`.

So every member is settled by IL rather than by a device, which is why the dependency frontier
reported the type consumable the moment `TouchCollection` existed, and why completing it claims no
touch hardware at all.

## Member by member

| Member | Measured behaviour |
| --- | --- |
| `GetCapabilities` | forwards to `TouchPanelCapabilities::GetCaps`, whose whole body is `initobj; ret` — `IsConnected` false, `MaximumTouchCount` 0 |
| `GetState` | always an empty, connected `TouchCollection` (derivation below) |
| `IsGestureAvailable` | `InvalidOperationException` until `EnabledGestures` has been assigned; afterwards the literal `false` |
| `ReadGesture` | throws on both branches and cannot return — `InvalidOperationException` for gestures never enabled, then again because none is available |
| `EnabledGestures` | a static `GestureType`; the setter rejects any bit outside `0x3FF` and records that gestures have been enabled |
| `WindowHandle` | `Touch`'s static `native int`, read and written and consumed by nothing on this profile |
| `DisplayOrientation` | a static; the setter accepts exactly one declared value and marks the display settings changed |
| `DisplayWidth` / `DisplayHeight` | plain statics; the setters validate nothing beyond the Int32 domain |

It is a CLR `abstract sealed` class, projected under the static-class rule `MathHelper` established
and `FrameworkDispatcher` follows: `new` raises `TypeError` and is private, and every CLR static
member is a Ruby class method.

## Why `GetState` is a projection and not a shortcut

This is the one member that needed deriving rather than transcribing, so the derivation is written
out.

`GetState`'s IL:

1. zeroes a local `XNAINPUT_TOUCH_LOCATION_STATE` with `initobj`;
2. if `displaySettingsChanged`, calls the private `OnDisplaySettingsChanged`, which resets
   `prevState` and `touchState` to their default values and clears the flag;
3. calls the internal `TouchCollection.Update(prevState, newState, connected)` with the static
   `prevState`, that zeroed local, and the literal `true`;
4. assigns the zeroed local back over `prevState`;
5. returns the static `touchState`.

Step 4 is what makes the whole thing constant. The local is **never filled**, so `prevState` is
zeroed after the first call and stays zeroed for ever, and the local passed as `newState` is zeroed
on every call by construction. `Update` therefore iterates `prevState.Count` (0) and `newState.Count`
(0), adds nothing, resets `locationCount` to 0, and stores the `connected` argument.

The observable result is always an empty collection with `isConnected` true — and
`TouchCollection.new([])` produces exactly that state: same `isConnected`, same `locationCount`. So
the projection is of the composite behaviour, not a substitute for it. The internal `Update` is
`assembly`, is not in the selected surface, and takes a private native-layout struct; nothing here
fabricates one.

### `GetState().IsConnected` is `true` while `GetCapabilities().IsConnected` is `false`

Read together without alarm. They are different facts:

- `GetState().IsConnected` is a **field of the returned value**, set from the `connected` argument
  the non-throwing branch passes as the literal `true`;
- `GetCapabilities().IsConnected` is the member that actually reports **device presence**, and it is
  the CLR default `false`.

Both are faithful and together they are precisely XNA's Windows answer. The test asserts the pair
side by side so the reason is on record rather than looking like a defect.

## One new BCL mapping: `InvalidOperationException`

`IsGestureAvailable` and `ReadGesture` throw `System.InvalidOperationException`, which had no
projection. It maps to Ruby `RuntimeError`.

The pairing is not new to this milestone — it is being **made measured**. `CurveKeyCollection` has
raised `RuntimeError` for the fail-fast enumeration the CLR signals with `InvalidOperationException`
since Foundation 4, and `ReadOnlyCollection` followed it in Foundation 29. `RuntimeError` is Ruby's
generic recoverable failure, the class `raise "message"` produces; `InvalidOperationException` is the
CLR's generic wrong-state failure. `FrozenError` would say something about frozen objects the CLR
does not, and `StandardError` itself would lose the identity — which the Foundation 30 rule already
forbids of every entry.

`BCL_THROWN_EXCEPTIONS` 5 → **6**. Both exception messages are localized `FrameworkResources`
strings — `GesturesNotEnabled` and `GesturesNotAvailable` — which are Microsoft's, so no message is
fabricated. The same applies to `Helpers::ValidateOrientation`'s `InvalidDisplayOrientation`.

## Two places where the Ruby enum projection draws the boundary

**`EnabledGestures`.** The CLR setter tests `value & 0xfffffc00` and throws
`ArgumentException("EnabledGestures")` for any bit outside the declared `GestureType` mask. Ruby
never gets that far: `GestureType.coerce` refuses an undefined bit first, and it draws the
**identical** accept/reject boundary because the declared bits sum to exactly `0x3FF` — which the
test asserts by summing them rather than by trusting the constant. So the guard is not written twice
in the setter, and the only divergence is the exception class: `RangeError` from the enum projection
rather than `ArgumentException` from the member. That is a consequence of projecting a CLR enum as a
validating typed value instead of a bare integer, which is a mapping this binding made long ago.

**`DisplayOrientation`.** The opposite case. `Helpers::ValidateOrientation` accepts exactly `0`, `1`,
`2` or `4` — one declared value, never a combination — even though `DisplayOrientation` carries
`[Flags]`, and `coerce` accepts any combination of declared bits as a flags enum should. So this
guard *is* the member's own and is written out, raising `ArgumentError` for
`LandscapeLeft | Portrait`.

## Process-global statics

`TouchPanel`'s state is static in the CLR and is static here: `EnabledGestures`, `WindowHandle`,
`DisplayOrientation`, `DisplayWidth` and `DisplayHeight` are per-process, and `_haveGestureBeenEnabled`
latches on the first `EnabledGestures` assignment and is never cleared, exactly as the IL does. That
is the type's contract, not an implementation shortcut — a program that never assigns
`EnabledGestures` cannot read a gesture at all. The tests save and restore every static so ordering
cannot leak between them.

## What moved

| Metric | Before | After |
| --- | --- | --- |
| `TARGET_TYPES` | 137 | **138** |
| `TARGET_MEMBERS` | 1732 | **1741** |
| `COMPLETE_TYPES` | 131 | **132** |
| `MISSING_TYPES` | 120 | **119** |
| `TOTAL_DIAGNOSTICS` | 304 | **303** |
| `BCL_THROWN_EXCEPTIONS` | 5 | **6** |
| Behaviour observations | 429 | **433** |
| Capability rows / contradictions | 86 / 0 | 87 / 0 |
| Frontier: dependency-complete | 21 | **20** |
| Frontier: consumable | 1 | **0** |

The frontier's one consumable candidate was this type, and it is gone. Every remaining entry is
blocked on a BCL projection, a native runtime or runtime data.

## A corpus correction

`touch_closure.touch_panel_capabilities.default_value` ended with
`Touch.const_defined?(:TouchPanel)`, pinning the absence of a type this milestone added from its own
IL rather than from anything `TouchPanelCapabilities` implies — the same shape as the Foundation 24
correction to `depth_format.ruby_enum_mapping`. That one slot was dropped so the row asserts only
what the Foundation 17 closure still establishes about the capabilities struct itself. The
deterministic replay proved every other element of that row, and every other row, unchanged, and the
corpus records it as `milestone32CorpusCorrection`.

## What this milestone does not claim

No touch hardware has been measured, nothing queries a touch device, no touch route was bound, no
CNA symbol was added and no CNA source was changed — the ABI is unchanged at
39 / 124 / 290 / 290 / 2 / 59. `TouchPanel` reaches no native code because the assembly it is
projected from reaches none either. Nothing in this binding produces a `TouchLocation`, a
`GestureSample` or a non-empty `TouchCollection`.
