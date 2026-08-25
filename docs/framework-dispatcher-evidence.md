# FrameworkDispatcher

`Microsoft.Xna.Framework.FrameworkDispatcher` is complete: one type, one identity, one canonical
CNA route. It is the first type this binding has taken off the dependency frontier's
`RUNTIME_DATA` register, and it came off because the reason recorded there was wrong.

## The exact XNA contract

Derived from the pinned `Microsoft.Xna.Framework.dll`, SHA-256
`38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`, disassembled with `ikdasm`.

```
.class public abstract auto ansi sealed beforefieldinit Microsoft.Xna.Framework.FrameworkDispatcher
       extends [mscorlib]System.Object
```

`abstract sealed` is C#'s `static class`. The reference contract lists exactly one public member,
`static void Update()`, and no constructor — the `.cctor` only allocates the two static
`List<ManagedCallAndArg>` buffers. `MathHelper` is the binding's other static XNA class and this
type follows it: `new` is defined to raise `TypeError` and made private, so public
non-constructibility is part of the contract.

`Update` takes no arguments, returns void and validates nothing. Its body:

1. `stsfld UpdateCalledAtLeastOnce = true`
2. `call PollForEvents()`
3. under a `Monitor`, copy `pendingCalls` into `pendingCallsCopy` and clear the original
4. walk the copy, dispatching each entry by its `ManagedCallType` to one of five managed sinks:
   `Media.MediaPlayer.OnActiveSongChanged`, `Media.MediaPlayer.OnMediaStateChanged`,
   `Audio.Microphone.AllMicrophones`,
   `Audio.DynamicSoundEffectInstance.RaiseBufferNeededOnInstance`, and
   `FrameworkCallbackLinker.OnStorageDeviceChanged`

The queue is filled elsewhere, by XNA's own audio and media internals through
`AddNewPendingCall`. `Update` is the point at which that accumulated work is handed to managed
code.

### PollForEvents is empty on Windows

```
.method private hidebysig static void  PollForEvents() cil managed
{
  // Code size       1 (0x1)
  IL_0000:  ret
}
```

In this Windows assembly `PollForEvents` does nothing, so `Update` reaches no native entry point
at all. That is measured independently by `docs/generated/xna-il-inventory.json`, which records
this type as `nativeReachable: false` and `declaresNativeEntryPoint: false`, and
`test_the_pinned_il_records_the_type_as_not_native_reachable` keeps the inventory saying so.

## Why the recorded deferral was wrong

`tools/api_compat/analyze_dependencies.rb` carried this type in `RUNTIME_DATA` with the
justification:

> Update pumps the live audio and media services; with neither present it would be a no-op
> pretending to be a pump.

That reasoning was about the wrong pump. It assumed the only implementation available was a
pure-managed one — a static queue nothing fills, drained on `Update` — which would indeed have
been a no-op wearing a pump's name. But this binding's audio and media **are** CNA, and the
canonical C ABI exposes `cna_framework_dispatcher_update`, the same drain CNA's own game loop
drives. Forwarding to it is the faithful analogue of draining XNA's queue: XNA's is filled by
XNA's audio and media layer, CNA's by CNA's.

What is genuinely absent is the managed fan-out, because none of the five sinks above has a Ruby
projection. An absent subscriber is not a missing runtime value, and `RUNTIME_DATA` is a register
of missing values. The row is retired, and
`test_the_runtime_data_deferral_is_retired` asserts it stays retired.

## The Ruby projection

```ruby
def Update
  host = CNA::Runtime::Context.native_host("FrameworkDispatcher.Update")
  CNA::Native.library.call("cna_framework_dispatcher_update", host.handle)
  nil
end
```

`Update` is a class method, since the CLR member is static, and answers `nil` for `System.Void`.
The route goes through the measured native manifest like every other, so
`tools/native_abi/verify.rb` type-checks its prototype against the canonical header rather than it
being an ad-hoc Fiddle lookup.

### The one deviation

XNA's dispatcher is a pure static usable with no `Game` in existence — that is its documented
purpose, driving audio and media for an application that does not run the game loop.
`cna_framework_dispatcher_update` takes a `CNA_Handle game`, and the canonical header is explicit
that the dispatcher behind it is static and the handle is "taken here only for thread affinity".

So this projection requires a live CNA `Game` on its owner thread. Without one it raises
`CNA::InvalidBindingStateError`; off the owner thread it raises `CNA::OwnerThreadError`. Both
refusals happen before the native entry is reached. This is recorded rather than hidden: the
alternative — returning `nil` as though the pump had run — is the exact failure mode the frontier
register warned about.

## Observed native behaviour

Measured against the retained artifact (`libcna_c_api.so` 0.7.0, SHA-256 `c62949d2…`, HEADLESS
renderer, NULL audio) before the route was bound:

| Call | Result |
| --- | --- |
| live game handle, owner thread, outside any callback | `CNA_RESULT_SUCCESS` |
| live game handle, inside `Update` and `Draw` callbacks | `CNA_RESULT_SUCCESS` |
| handle `0`, and an unknown handle | `CNA_RESULT_INVALID_HANDLE` |
| live game handle, off the owner thread | `CNA_RESULT_THREAD` |

Repetition is harmless: the canonical header states that calling it while the loop runs simply
does the work twice, and five consecutive calls were qualified.

## Qualification delta

| Measurement | Before | After |
| --- | --- | --- |
| `TARGET_TYPES` | 134 | 135 |
| `TARGET_MEMBERS` | 1713 | 1714 |
| `COMPLETE_TYPES` | 128 | 129 |
| `MISSING_TYPE` | 123 | 122 |
| `TOTAL_DIAGNOSTICS` | 307 | 306 |
| `BOUND_FUNCTIONS` | 38 | 39 |
| `SIGNATURE_MEASUREMENTS` | 122 | 124 |
| dependency-complete candidates | 22 | 21 |
| `BLOCKED_RUNTIME_DATA` | 5 | 4 |

`PARTIAL_TYPES` stays 6, `MISSING_MEMBER` stays 132, `PROPERTY_MAPPING_MISMATCH` stays 1,
`OVERLOAD_MAPPING_MISMATCH` stays 51, and every other structural category stays 0. Layout
measurements stay 290/290, callbacks stay 2 and constants stay 59, because the route measures no
new structure and consumes no new constant. No CNA source was changed and no new native binary was
built.

## Capability registry

`native.framework-dispatcher` is `VERIFIED_NATIVE_ROUTE` rather than `VERIFIED_NATIVE`: the route
executes and its preconditions are qualified, but no managed sink observes the drain, so there is
nothing downstream to verify yet. The `audio-media` row was corrected in the same change — it
claimed "no CNA audio or media route", and there is now exactly one.
