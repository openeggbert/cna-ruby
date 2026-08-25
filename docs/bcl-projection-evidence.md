# Foundation 21 — the BCL projection register and the XNA exception base mapping

Makes the two BCL decisions that Foundation 19 recorded as unmade, measures both, and adds **no XNA
type and no new public Ruby class**. What it changes is what the binding *knows*, not what it
exposes.

## The register

`CNA::Runtime::BclProjection` records every non-XNA CLR identity this binding projects.

| CLR identity | Ruby projection | Kind |
| --- | --- | --- |
| `System.EventArgs` | `CNA::Runtime::EventArgs` | type |
| `System.Exception` | `StandardError` | exception base |
| `System.Runtime.InteropServices.ExternalException` | `StandardError` | exception base |

It is measured, not aspirational. `tools/api_compat/verifier.rb` resolves every entry and
shape-checks every exception base, reporting `LANGUAGE_MAPPING_MISMATCH` for an entry that does not
exist or is not a Ruby `StandardError` class. `tools/api_compat/analyze_dependencies.rb` consumes
the same register, so the frontier can never report a BCL type as mapped that the runtime does not
actually project. A test asserts every register identity is one the pinned reference genuinely
names.

Before this, the mapped-BCL set was derived only from complete types' signatures. That missed
Foundation 20's `System.EventArgs` projection — no complete type names bare `System.EventArgs`,
only `System.EventHandler`1[System.EventArgs]` — so three types were reported as blocked on a
decision that had already been made.

## The exception base mapping

> A CLR type whose declared base is a projected exception base takes a **Ruby exception superclass**
> rather than `Object`. `StandardError` is the root.

`StandardError` and not `::Exception`, because a CLR `catch (Exception)` is the analogue of a bare
Ruby `rescue` — which catches `StandardError` and deliberately not `::Exception`. Rooting XNA
failures at `::Exception` would place them alongside Ruby's non-recoverable system-level conditions
and make an ordinary `rescue` miss them.

Only the two bases the pinned reference actually names are projected: `System.Exception` (five XNA
types) and `System.Runtime.InteropServices.ExternalException` (three). The selected XNA surface
never names `ExternalException` itself, so no Ruby constant is invented for it: an intermediate BCL
exception class collapses to the nearest projected ancestor. That is a deliberate, documented loss
of one CLR inheritance level.

`verify_runtime_base` previously expected a Ruby superclass of `Object` for any non-XNA base. It now
consults the register first, which is what makes an XNA exception projectable at all. Mutation tests
require it to reject an exception projected as an ordinary `Object` subclass, one rooted at
`::Exception`, one rooted at an unrelated class, one placed too deep in the Ruby hierarchy, a
non-exception CLR base given an exception superclass, a register entry that does not resolve, and an
exception base that is not a Ruby exception class.

## No XNA exception type is claimed

The rule exists; none of the eight XNA exception types can use it yet.

| Type | Declared members | Still blocked by |
| --- | --- | --- |
| `Audio.InstancePlayLimitException` | 3 constructors | `.ctor` IL |
| `Audio.NoAudioHardwareException` | 3 constructors | `.ctor` IL |
| `Audio.NoMicrophoneConnectedException` | 3 constructors | `.ctor` IL |
| `Graphics.DeviceLostException` | 3 constructors | `.ctor` IL |
| `Graphics.DeviceNotResetException` | 3 constructors | `.ctor` IL |
| `Graphics.NoSuitableGraphicsDeviceException` | 3 constructors | `.ctor` IL |
| `Content.ContentLoadException` | 4 constructors | `.ctor` IL + `SerializationInfo`/`StreamingContext` |
| `Storage.StorageDeviceNotConnectedException` | 4 constructors | `.ctor` IL + `SerializationInfo`/`StreamingContext` |

**Every declared member of every one of them is a constructor.** The pinned reference is public
metadata only — `kind`, `name`, `access`, parameter types — so what a constructor does is not on this
host. Specifically unknown:

1. what `Message` the parameterless constructor produces — .NET's framework-supplied
   "Exception of type 'X' was thrown." only if XNA's constructor is a pure `base()` forward, and
   whether it is is exactly the IL that is missing;
2. whether the one- and two-argument constructors forward `message` and `innerException` unchanged
   or transform them;
3. whether any of them validates or rejects its arguments.

Assuming "it is the canonical .NET exception boilerplate" is inference from a conventional pattern,
which is what this project refuses. These constructors sit in the same category as
`Audio.AudioListener.ctor`, `Graphics.PresentationParameters.ctor` and
`Input.Touch.TouchLocation.ctor`, all already deferred for the same reason. The required input is
retained XNA 4.0 Windows IL — proprietary reference data, not a tool and not a package.

Two of the eight additionally need `System.Runtime.Serialization.SerializationInfo` and
`StreamingContext`, a BCL cluster this milestone deliberately does not design.

## Deliberately not designed

`System.Type`, `System.IServiceProvider`, `System.IO.Stream`, `System.TimeSpan` as a first-class
type, `System.Attribute`, `System.Text.StringBuilder`,
`System.Runtime.Serialization.SerializationInfo`, `ReadOnlyCollection`1` and `Dictionary`2` are
recorded in `mapping-rules.json` under `bclProjection.notYetDesigned`. None is the immediate
highest-value blocker, and none can be designed confidently before a type that needs it is otherwise
unblocked.

## Frontier movement

Dependency-complete but blocked stays 38; what changed is the attribution.

| Blocker set | Before | After |
| --- | --- | --- |
| `BCL_PROJECTION` + `BEHAVIOR_EVIDENCE` | 24 | 15 |
| `BEHAVIOR_EVIDENCE` | 14 | 23 |

Nine types moved: the six single-base exception types, plus
`GameComponentCollectionEventArgs`, `Graphics.ResourceCreatedEventArgs` and
`Graphics.ResourceDestroyedEventArgs`, whose only unmapped BCL type was `System.EventArgs`.

That is the whole point of the milestone: **every remaining candidate is now blocked on XNA IL or on
a BCL cluster no unblocked type needs — never on a decision this project has failed to make.**

## Why no exemption was granted to constructor-free classes

`Graphics.ResourceCreatedEventArgs`, `Graphics.ResourceDestroyedEventArgs`,
`Graphics.TextureCollection` and `Media.Video` now show `BEHAVIOR_EVIDENCE` with no IL-bearing
member listed: each is a class declaring no constructor and no method, only properties. The struct
exemption was not extended to them.

A struct with no declared constructor is fully described by its CLR default value, which is why
`TouchPanelCapabilities` could be completed. A class has no CLR default value: an instance can only
come from the framework, and nothing in this binding produces one. Projecting such a class would
mean a Ruby class nothing can instantiate whose readers nothing can legitimately call — a hollow
identity that would raise `COMPLETE_TYPES` without adding any behaviour. Missing XNA types stay
absent rather than simulated.

## Structural movement

None. TARGET_TYPES 113, TARGET_MEMBERS 1623, TOTAL_DIAGNOSTICS 328, COMPLETE_TYPES 107,
MISSING_TYPE 144, `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6, `PROPERTY_MAPPING_MISMATCH` 1,
`OVERLOAD_MAPPING_MISMATCH` 51, every other category 0, allowlist 0, unmeasured 0. The strict report
gained `BCL_PROJECTED_IDENTITIES=3`, `BCL_EXCEPTION_BASES=2` and a `bclProjection` block.

CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59, zero missing symbols, zero mismatches.

## Behaviour corpus

355 → 366 observations, 0 failures. Eleven additive rows in a new `BCL_PROJECTION` group: eight
`PURE_XNA_DERIVED` per-exception contract rows recording that each type's whole declared surface is
constructors, one `PURE_XNA_DERIVED` deferral row, and two `RUBY_MAPPING_QUALIFICATION` rows for the
register and the exception base rule.

Merged by the documented deterministic replay method against pre-merge SHA-256
`fab5788ffbaa551b5f3ca6d4381c2c7a64a620810513ff796cad44ce805abb8f` (355 observations); purely
additive, no existing observation altered. The upstream source `398d0201…` remains absent and
`tools/import_behavior_corpus.rb` was extended but not executed.

## Verification

- Full Ruby suite: 564 runs / 19543 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 366 observations / 366 assertions / 0 failures.
- API verifier strict: 328 diagnostics, all deferred; leak-only clean; `LANGUAGE_MAPPING_MISMATCH`
  and `BASE_MAPPING_MISMATCH` both 0.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
