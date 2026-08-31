# Foundation 47 — `Game`'s protected remainder

Derived from the pinned `Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, disassembled with `ikdasm`.

Three `family` members: `Dispose(Boolean)`, `Finalize` and
`ShowMissingRequirementMessage(Exception)`. None of them is CLR machinery a projection may skip —
`Dispose(Boolean)` carries the whole managed teardown, `Finalize` is the finalizer path that
deliberately does nothing, and `ShowMissingRequirementMessage` is the reason `RunGame` has two catch
clauses at all.

## The disposal triangle

```
public void Dispose()            => Dispose(true); GC.SuppressFinalize(this);
protected virtual void Finalize()=> try { Dispose(false); } finally { base.Finalize(); }
protected virtual void Dispose(bool disposing) {
    if (!disposing) return;                       // ldarg.1; brfalse IL_0094 -> ret
    lock (this) {
        var copy = new IGameComponent[gameComponents.Count];
        gameComponents.CopyTo(copy, 0);
        foreach (var c in copy) (c as IDisposable)?.Dispose();
        (graphicsDeviceManager as IDisposable)?.Dispose();
        UnhookDeviceEvents();
        Disposed?.Invoke(this, EventArgs.Empty);
    }
}
```

So `Dispose(false)` does **nothing at all**, and `Finalize` is exactly that call — the CLR finalizer
for this type is observably a no-op. That is the same shape `GameComponent` already ships, and it is
projected as the member the contract declares doing the same nothing. `GC.SuppressFinalize` needs no
analogue because no `ObjectSpace.define_finalizer` is registered anywhere in this binding; a test
scans every non-comment line of `lib/` to keep that true.

The two overloads project to **one Ruby method dispatching on arity**, which is the rule Foundation
38 established for `GameComponent`. It widens the protected overload to public — Ruby cannot give one
name two visibilities — and that stays a recorded mapping limitation rather than a silent one.

### The lock is now taken

Foundation 41 recorded not taking `Monitor.Enter(this)` as a deviation, and named the exact reason:
it belongs to `Dispose(Boolean)`, which was missing. It is taken now. `::Monitor` is the analogue
rather than `Mutex` because the CLR lock is **reentrant** — a `Disposed` handler that disposes the
Game again must not deadlock, and a test asserts both that the lock is held inside the handler and
that re-entering it returns.

`UnhookDeviceEvents()` sits between the manager's disposal and the `Disposed` event. Its whole body
is `if (graphicsDeviceService != null) { remove four handlers }`, and that field is written only by
`HookDeviceEvents`, which the graphics-device-service producer audit deliberately omits. So it is a
**genuine** no-op here rather than one made into one, and nothing is fabricated in its place.

### What remains a deviation

XNA has **no disposed flag anywhere in the type**, so `Dispose()` twice runs the whole body twice and
raises `Disposed` twice. This binding still returns early when already disposed, because native
destruction is not repeatable — unchanged and still recorded.

## `ShowMissingRequirementMessage`

Twenty-three bytes: `host?.ShowMissingRequirementMessage(exception)`, else `false`.

`GameHost.ShowMissingRequirementMessage` is `ldc.i4.0; ret` — an unconditional **false**. Only
`WindowsGameHost` overrides it: it concatenates a localized resource with the exception message for
`NoSuitableGraphicsDeviceException`, uses a second resource for `NoAudioHardwareException`, shows a
`System.Windows.Forms.MessageBox` and returns **true**, and delegates anything else back to that
base.

CNA is the host here and it is not `WindowsGameHost`: the canonical C ABI exposes no
missing-requirement message route at all. So this answers the `GameHost` base's `false` — which is
not a stub standing in for a capability. `false` is the truthful answer to "did you show the
message?", it is the answer the abstract base really gives, and `RunGame` rethrows on false, so the
exception still reaches the caller.

### The catch clauses are live, not decorative

`RunGame`'s body is wrapped in two clauses that a projection of `Run` alone would lose:

```csharp
catch (NoSuitableGraphicsDeviceException e) { if (!ShowMissingRequirementMessage(e)) throw; }
catch (NoAudioHardwareException e)          { if (!ShowMissingRequirementMessage(e)) throw; }
```

Both exception types are projected here (Foundation 22), and a subclass's `Initialize`,
`LoadContent`, `Update` or `Draw` can raise either — the callback retains it and `GameHost#finish`
re-raises it on this side of C, inside `Run`. So the clauses are reachable and observable, and the
member is testable rather than ornamental: with the default `false`, `Run` rethrows both; with an
override answering `true`, `Run` really swallows them; and an unrelated `ArgumentError` is not caught
by either clause.

`RunGame`'s `finally` also clears `inRun` unless `endRunRequired`, which only `StartGameLoop` sets
and which this binding never takes. Keeping it in `Run` rather than only in the `EndRun` hook is what
makes the flag survive a run that ends by raising, where `EndRun` is never delivered — a small
divergence the previous shape had, now closed and tested.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_MEMBERS` | 1790 | 1793 |
| `TOTAL_DIAGNOSTICS` | 274 | 268 |
| `MISSING_MEMBER` | 114 | 111 |
| `OVERLOAD_MAPPING_MISMATCH` | 45 | 42 |
| `Game` remainder | 5 | **2** |
| behaviour observations | 506 | 510 |

`TARGET_TYPES` 143, `COMPLETE_TYPES` 137, `PARTIAL_TYPES` 6, `MISSING_TYPES` 114, allowlist 0 and
every other structural category are unchanged; no native binding was added, so the ABI is untouched
at 55 / 169 / 290 / 290 / 3 / 63.

**`Game`'s remainder is now `Content` and `Window` — and neither is a decision.** Each is blocked on
a missing type, `ContentManager` and `GameWindow`, rather than on an unresolved projection question.

## What this does not claim

Projecting `Finalize` adds no Ruby finalizer, no `ObjectSpace` registration and no
`GC.SuppressFinalize` analogue; nothing in this binding is destroyed by the garbage collector, and
native destruction stays explicit. Projecting `ShowMissingRequirementMessage` adds no message box, no
dialog, no `System.Windows.Forms` surface and no CNA route: it reports that no message was shown,
because none was.
