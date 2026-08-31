# Foundation 48 — `GameWindow`

Derived from the pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, disassembled with `ikdasm`.

`GameWindow` sat on the dependency frontier under `RUNTIME_DATA`, with the justification "an
abstract window whose concrete implementation is the platform window behind Game; projecting it
would require the deferred Game/window runtime". That reasoning was wrong in exactly the way
`FrameworkDispatcher`'s was in Native frontier 1, and for the same reason: **the concrete
implementation this binding needs is CNA's**, and the canonical C ABI already supplies every member
XNA leaves abstract. The register entry is retired.

## The type

`.class public abstract auto ansi beforefieldinit`, extending `System.Object`, with twenty selected
identities — eleven methods, six properties, three events.

Ten members are `abstract`, left for a concrete host: `Handle`, `AllowUserResizing` both ways,
`ClientBounds`, `ScreenDeviceName`, `CurrentOrientation`, `BeginScreenDeviceChange(bool)`, the
three-argument `EndScreenDeviceChange`, the `family` `SetTitle(string)` and the `famorassem`
`SetSupportedOrientations(DisplayOrientation)`.

It declares **six** private `EventHandler`1` fields, but the accessors of `Activated`, `Deactivated`
and `Paint` are `assembly` — internal plumbing between the host and `Game` — so only three are
identities. The canonical C ABI agrees exactly: it defines three `CNA_GAME_WINDOW_EVENT_*` values,
and they are `ClientSizeChanged`, `OrientationChanged` and `ScreenDeviceNameChanged`.

`.ctor()` is `assembly`, so construction is private under the Foundation 25 rule.

## It is a façade, and the ABI is what makes that the faithful shape

Every canonical window route — thirteen of them — is addressed through the **game** handle. CNA's
window has no handle of its own. So there is no second object to invent, no second lifetime to
reconcile, and no producer question of the kind the `GraphicsDeviceService` audit had to defer: the
projection holds one reference to its `Game` and forwards. A member reached after the Game is
disposed raises, because the window it names no longer exists.

`Game.get_Window` is `host?.Window`. XNA's null branch is **unreachable** — `Game..ctor` calls
`EnsureHost()`, so a constructed XNA Game always has a host and the property is never null. This
binding defers that constructor step, so `Game#Window` completes it, exactly as `Run`, `RunOneFrame`
and `Tick` already do, rather than exposing a nil XNA never shows. The façade itself is one managed
object created in the constructor and answered for the life of the Game.

## `Title` is the host's, not a managed shadow

`get_Title` is one `ldfld` and `set_Title` is validation plus a push through the abstract `SetTitle`,
which reads exactly like the `IsMouseVisible` shape Foundation 42 kept as managed state. It is
deliberately **not** kept as managed state here, and the reason is measured: the abstract constructor
sets `title = String.Empty`, but `WindowsGameWindow`'s constructor calls `base..ctor()` and then
`set_Title(GetDefaultTitleName())`. So the value a consumer observes before writing one is the
**host's** default, not the empty string. CNA's host has its own default, carried by
`CNA_GameCreateInfo::window_title`, and `cna_game_window_copy_title` reads it back — measured as
`"CNA-Ruby"`, round-tripping through UTF-8 including a non-ASCII title.

The setter keeps both of the abstract class's own validations: `ArgumentNullException` on a null
title, and a same-value write suppressed with `String::op_Inequality` before the push, which is why
setting the current title pushes nothing.

## What HEADLESS answers, and why none of it is invented

```
ClientBounds        0, 0, 0, 0
Handle              0
ScreenDeviceName    ""
CurrentOrientation  Default
AllowUserResizing   false -> set true -> true
Title               "CNA-Ruby" -> set -> reads back
```

The zeros and the empty string are CNA's honest report of a platform with no native window — the same
shape `Mouse.WindowHandle` already reports — and not one of them is replaced by an invented default.
`AllowUserResizing` and `Title` round-trip through the real routes, which is what proves the rest are
answers rather than placeholders.

`SetSupportedOrientations` is the one member with no canonical route: orientation is readable in the
ABI and not settable. It is declared, because the contract names it, and it **refuses** — a
`NotSupportedError` — rather than pretending to apply an orientation the runtime never receives.

## A by-value aggregate, recorded rather than smuggled

`cna_game_set_window_title` and `cna_game_window_end_screen_device_change` take a `CNA_StringView`
**by value**, and Fiddle cannot pass an aggregate. The manifest therefore expands such a parameter
into the eightbytes the platform ABI really puts in registers, and the expansion is recorded on the
signature rather than performed silently: `tools/native_abi/verify.rb` reconstructs the aggregate's C
spelling from that record and compares it with what the header declares, so a decomposition that
stopped matching would fail the probe.

The premise is measured, not assumed. `CNA_StringView` is a `const char*` at offset 0 and a
`uint64_t` at offset 8, size 16, alignment 8 — which the ABI probe already emits. Under the System V
x86-64 classification both eightbytes are INTEGER, so the aggregate travels in the next two integer
registers, byte for byte what two separate scalar arguments occupy. It is qualified only for the one
platform this binding qualifies at all.

## The frontier movement it uncovered

Retiring the deferral did more than remove one row. `GameWindow` was
`GamerServices.GamerServicesComponent`'s **only** il-only unmet dependency, so that candidate moved
out of the il-only blocked list — twelve to eleven — and into `partialDependencySatisfied`, joining
`DrawableGameComponent`. That is precisely the transition the member-level dependency measurement
exists to observe, and the behaviour-corpus row that pins it records all three moves.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_TYPES` | 143 | **144** |
| `TARGET_MEMBERS` | 1793 | 1814 |
| `COMPLETE_TYPES` | 137 | **138** |
| `MISSING_TYPES` | 114 | 113 |
| `TOTAL_DIAGNOSTICS` | 268 | 266 |
| `MISSING_MEMBER` | 111 | 110 |
| `EVENT_IDENTITIES` | 17 | 20 |
| `EVENT_OWNER_TYPES` | 6 | 7 |
| bound CNA functions | 55 | **68** |
| CNA constants | 63 | 66 |
| dependency-complete candidates | 18 | 17 |
| `Game` remainder | 2 | **1** |
| behaviour observations | 510 | 515 |

ABI 68 / 219 / 300 / 300 / 3 / 66 with zero mismatches. `PARTIAL_TYPES` 6, allowlist 0,
`EVENT_MAPPING_MISMATCH` 0 and every other structural category unchanged. **`Game`'s remainder is now
`Content` alone.**

## What this does not claim

A window that answers a zero rectangle and a zero handle is not a visible window. Nothing here
creates, shows, moves, resizes or paints one; HEADLESS qualifies the routes and the returned state,
not a rendered surface. No `System.Windows.Forms` surface, icon, cursor or message pump is added,
`SetSupportedOrientations` applies nothing, and the three window events are subscribable but nothing
in the reviewed artifact raises them.
