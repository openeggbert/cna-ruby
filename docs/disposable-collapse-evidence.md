# Foundation 36 — `System.IDisposable` as a measured structural collapse

`System.IDisposable` → **no Ruby constant at all**.

The second entry in `CNA::Runtime::BclProjection::STRUCTURAL_COLLAPSE`, after
`System.IServiceProvider`, and the first one with real reach: twenty-nine XNA reference types
declare the interface, against one for the first entry.

## The measurement that settles it

`System.IDisposable` in the admitted Microsoft .NET Framework 4.0 mscorlib (SHA-256
`5634668d…`) is four lines of IL:

```
.class interface public abstract auto ansi System.IDisposable
{
  .custom instance void System.Runtime.InteropServices.ComVisibleAttribute::.ctor(bool) = ( 01 00 01 00 00 )
  .method public hidebysig newslot abstract virtual
          instance void  Dispose() cil managed
  {
  } // end of method IDisposable::Dispose
} // end of class System.IDisposable
```

**One member. `void Dispose()`. Nothing else.**

There is no `Close`, no `IsDisposed`, no finalizer contract, no double-dispose rule, no ownership
protocol and no `using` semantics in the interface. Every one of those is a convention the framework
and its callers build *on top of* the interface, or a language construct, or a member a particular
type declares for itself. None of them is `IDisposable`, so none of them may be invented here.

## Why the collapse is the faithful projection

The rule `System.IServiceProvider` established in Foundation 33: **a BCL interface whose whole
declared surface the implementing XNA type already exposes survives as those members, and inventing
a Ruby module for it would add an identity the CLR contract does not have and that nothing could
measure.** Ruby has no interfaces.

Applied here and counted:

| | Types |
| --- | --- |
| Declare `System.IDisposable` | **29** |
| …and declare a public parameterless `Dispose()` of their own | **28** |
| …and implement it explicitly instead | **1** |

The one is `Microsoft.Xna.Framework.GraphicsDeviceManager`, whose Game.dll IL carries

```
.method private hidebysig newslot virtual final
        instance void  System.IDisposable.Dispose() cil managed
{
  .override [mscorlib]System.IDisposable::Dispose
  IL_0002:  callvirt   instance void Microsoft.Xna.Framework.GraphicsDeviceManager::Dispose(bool)
}
```

An explicit interface implementation, which projects to **no member at all** — the same rule
`ReadOnlyCollection`'s twelve and `Collection`'s fourteen already follow. So in Ruby a
`GraphicsDeviceManager` will have no `Dispose()` where C# offers one through the interface cast.
That is a deliberate, recorded loss of one identity, not an oversight; `GraphicsDeviceManager` is one
of the six deferred partial runtime types and `Dispose(Boolean)` is in its missing list, so nothing
is being claimed for it either way.

## What is *not* being claimed

This is the half the decision exists to protect, and every part of it is measured.

**No type's disposal is implemented by this.** Mapping the identity is a statement about the
interface and about nothing else. Each type's own `Dispose` remains its own measured work, derived
from its own IL, in its own milestone.

**No native runtime becomes available.** Native frontier 3 proved that `Audio.SoundEffectInstance`
and `Audio.Cue` reach XACT through mixed-mode C++/CLI thunks. Both lose their `BCL_PROJECTION`
blocker here and both keep `NATIVE_RUNTIME`, so **neither becomes consumable** and both stay
deferred. `consumableCandidates` is 0 before and after.

**Nothing was invented.** No `IDisposable` or `Disposable` module at top level, in `CNA::Runtime`, or
in any XNA namespace; no `Close` alias; no `IsDisposed` this projection contributes; no finalizer API
and no ownership wrapper. Three separate verifier categories catch an attempt:

| Attempt | Caught as |
| --- | --- |
| a constant in `Object` or `CNA::Runtime` | `LANGUAGE_MAPPING_MISMATCH` |
| a fabricated `::System` namespace | `LANGUAGE_MAPPING_MISMATCH` |
| a module inside `Microsoft::Xna::Framework` | `INTERNAL_TYPE_LEAK` |
| a `Close` alias on a projected type | `UNEXPECTED_MEMBER` |

Each is a mutation test that passes only because the mutation is detected. `IsDisposed` on
`GraphicsResource` and `GraphicsDevice` stays exactly where the reference contract declares it: it is
a real XNA identity on those two types, not a contribution of this collapse.

## The frontier effect, exactly

| Type | Before | **After** |
| --- | --- | --- |
| `Audio.SoundEffectInstance` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | **`NATIVE_RUNTIME`** |
| `Audio.Cue` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | **`NATIVE_RUNTIME`** |
| `Content.ContentManager` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | unchanged — it named four other identities |

```
blockerSummary before: BCL_PROJECTION 5, BCL_PROJECTION+NATIVE_RUNTIME 5, NATIVE_RUNTIME 3,
                       NATIVE_RUNTIME+RUNTIME_DATA 1, RUNTIME_DATA 5
blockerSummary after:  BCL_PROJECTION 5, BCL_PROJECTION+NATIVE_RUNTIME 3, NATIVE_RUNTIME 5,
                       NATIVE_RUNTIME+RUNTIME_DATA 1, RUNTIME_DATA 5
```

`ContentManager` is the useful control: it keeps `BCL_PROJECTION` because
`System.IDisposable` was never the only BCL identity it named — `System.IO.Stream`,
`System.Action`1` and `!!0` remain.

## One tool correction

`test/test_dependency_frontier.rb` restates the tool's mapped-BCL rule independently, and its
restatement read only the `TYPES` and `EXCEPTION_BASES` halves of the register. A structural
collapse settles an identity too — precisely by deciding no constant is needed — and the tool has
always used `BclProjection.identities`, which includes it. The two agreed anyway while the single
collapsed identity was also reachable from a complete type's signatures, as
`System.IServiceProvider` is through `GameServiceContainer`. `System.IDisposable` is declared only by
types that are missing or partial, so the omission stopped being invisible and the restatement now
reads all three parts.

## Scoreboard

| Metric | Foundation 35 | **Foundation 36** |
| --- | --- | --- |
| `BCL_PROJECTED_IDENTITIES` | 9 | **10** |
| Structural collapses | 1 | **2** |
| Frontier: `BCL_PROJECTION`-bearing | 10 | **8** |
| Frontier: consumable | 0 | 0 |
| Behaviour observations | 445 | **449** |
| Capability rows / contradictions | 89 / 0 | **90** / 0 |
| `COMPLETE_TYPES` | 134 | 134 |
| `PARTIAL_TYPES` / `MISSING_MEMBER` | 6 / 132 | 6 / 132 |
| `TOTAL_DIAGNOSTICS` | 301 | 301 |
| CNA ABI | 39 / 124 / 290 / 290 / 2 / 59 | unchanged |

No type was completed, no member was closed, no CNA source was changed and no native symbol was
added.
