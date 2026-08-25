# Foundation 33 — `GameServiceContainer`, and two BCL identities with opposite answers

One type, four Ruby identities, and the two BCL identities that had blocked it since the frontier
register was created. It is the smallest interesting case in the register so far, because
`System.Type` and `System.IServiceProvider` need **opposite** treatments and the difference is what
the milestone is really about.

## The type

`GameServiceContainer` is a managed container over one private `Dictionary<Type, object>`. The
hash-admitted IL inventory records it in `Microsoft.Xna.Framework.Game.dll` with one public
constructor, one declared field, three methods and `nativeReachable: false`. Nothing in it touches
CNA, holds an unmanaged resource, or needs a `Game`.

Its constructor is **public**, which makes it unusual in the Game family: a caller can make one and
use it. What it is *for* is `Game.Services`, and `Game` is one of the six deferred partial runtime
types, so nothing in this binding registers a service in one.

| Member | Measured behaviour |
| --- | --- |
| `.ctor()` | allocates one `Dictionary<Type, object>` |
| `AddService(Type, Object)` | four checks, then `Dictionary.Add` |
| `RemoveService(Type)` | null check, then `Dictionary.Remove` with the result **popped** |
| `GetService(Type)` | null check, then `ContainsKey` ? indexer : `ldnull` |

All three members open with the same null check on the same parameter. `AddService` then rejects a
null provider, a key already present, and a provider the key is not assignable from — and the
assignability failure is the only one of the four that names **no** parameter, so it is the only one
whose Ruby message is not a parameter name.

`RemoveService` popping the `Remove` result is why removing a key that was never added is harmless,
and why the key can be added again afterwards. `GetService` answering `null` for an absent key is
the one place the type differs from the dictionary it wraps, which throws `KeyNotFoundException`.

All four CLR messages are localized `Resources` strings and none is reproduced. One of them carries
a Microsoft bug worth recording rather than copying: `ServiceMustBeAssignable`'s second format
argument is `type.GetType().FullName` — the type *of the `Type` object*, which is always
`System.RuntimeType` — where every reading of the message expects `type.FullName`.

## `System.Type` → Ruby `Module`

`System.Type` is named in **24** places by the XNA reference contract, and in every one of them it is
a *type token*: a service key here, a content reader's `TargetType`, an `IndexBuffer`'s element type,
a converter's destination type. Ruby has a type token — a `Module`, and a `Class` is one.

Two facts make the projection exact rather than approximate for the use the surface actually makes
of it:

- the only operation any of those members performs on a `Type` is
  `type.IsAssignableFrom(value.GetType())`, which is precisely Ruby's `value.is_a?(type)` — and it
  works for a module key as well as a class key, exactly as the CLR's does for an interface type;
- `Dictionary<Type, object>`'s default comparer is reference equality, and a Ruby `Module` used as a
  `Hash` key compares the same way. The test proves it with two distinct anonymous modules.

The register entry claims the *token*, not the CLR reflection surface. Nothing here projects
`FullName`, `GetMethods`, generics or any other member of `System.Type`.

## `System.IServiceProvider` → nothing, deliberately

The opposite answer, and it needed a new kind of register entry.

`System.IServiceProvider` declares exactly one member, `GetService(Type)`, and
`GameServiceContainer` declares that member publicly itself. Ruby has no interfaces. Inventing a
`CNA::Runtime::IServiceProvider` module would add an identity the CLR contract does not have, that
no XNA member returns or accepts by that name in the selected surface, and that nothing could
measure — the same objection Foundation 21 raised to inventing a constant for `ExternalException`.

So the answer is that it projects to **no Ruby constant at all**, and the contract survives as the
member. That is a decision, and a decision left implicit is indistinguishable from an oversight, so
it is recorded:

```ruby
STRUCTURAL_COLLAPSE = {
  "System.IServiceProvider" => "declares one member, GetService(Type), which GameServiceContainer
                                declares publicly; the contract survives as that member and no Ruby
                                constant is invented"
}.freeze
```

Two things follow. The dependency frontier counts the identity as decided, so it stops reporting it
as an unmapped BCL type. And `verify_structural_collapse` asserts the decision holds — that neither
a fabricated `::System` namespace nor a `CNA::Runtime` constant named after the identity exists — so
a later milestone cannot quietly invent one. The mutation test creates
`CNA::Runtime::IServiceProvider` and proves the verifier reports it.

`BCL_PROJECTED_IDENTITIES` 6 → **8**: `System.Type` in `TYPES`, `System.IServiceProvider` in
`STRUCTURAL_COLLAPSE`. Both leave `bclProjection.notYetDesigned`, which is down to four:
`System.IO.Stream`, `System.Text.StringBuilder`,
`System.Runtime.Serialization.SerializationInfo` and `System.Collections.Generic.Dictionary`2`.

## What moved

| Metric | Before | After |
| --- | --- | --- |
| `TARGET_TYPES` | 138 | **139** |
| `TARGET_MEMBERS` | 1741 | **1745** |
| `COMPLETE_TYPES` | 132 | **133** |
| `MISSING_TYPES` | 119 | **118** |
| `TOTAL_DIAGNOSTICS` | 303 | **302** |
| `BCL_PROJECTED_IDENTITIES` | 6 | **8** |
| Behaviour observations | 433 | **435** |
| Capability rows / contradictions | 87 / 0 | 88 / 0 |
| Frontier: dependency-complete | 20 | **19** |
| Frontier: `BCL_PROJECTION`-only | 7 | **6** |

## A corpus correction

The three `BclProjection.Register` rows each carried a slot asserting that `System.Type` stays
unprojected — the same shape of over-reach the Foundation 23 and 24 corrections fixed, where a row
pinned something a later milestone could legitimately end. That slot was dropped from the operation
and from all three rows, so each asserts only the identities it was written to pin plus the standing
rule that no `::System` namespace exists. The deterministic replay proved every other element of
those rows, and every other row, unchanged; the corpus records it as `milestone33CorpusCorrection`.

## What this milestone does not claim

Nothing registers a service: `Game.Services` is the producer and `Game` remains a deferred partial.
No `IServiceProvider`-shaped Ruby module exists, no `System.Type` reflection surface is projected, no
CNA symbol was added and no CNA source was changed — the ABI is unchanged at
39 / 124 / 290 / 290 / 2 / 59.
