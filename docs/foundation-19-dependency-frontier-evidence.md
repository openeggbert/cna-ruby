# Foundation 19 — dependency frontier and blocker register

Foundation 19 adds no XNA type. It converts an opaque tooling failure into a measured, tested,
machine-readable statement of exactly what is left and why each item cannot be consumed.

## The problem it fixes

`tools/api_compat/analyze_dependencies.rb` selected the next milestone from *enums only*. Foundation
16 exhausted the enums that a deferred partial member still referenced, and the tool was widened
once to rank all pure managed enums globally. Foundations 16–18 then consumed every remaining pure
managed enum, and the tool aborted outright:

    no dependency-complete pure managed enum candidate remains

An abort is the wrong answer. "Nothing is safely consumable" is a real, useful result and the
workflow needs it as data, not as a crash. The report is now schema version 3 and exits 0 with
`SELECTED_NEXT=none` when the frontier is blocked.

## Classification rule

For every missing type whose XNA public-signature dependencies are already complete, the tool
records why it cannot be consumed:

- `EVENT_PROJECTION` — the type declares a CLR event. No selected type has ever projected one, so
  subscription and unsubscription have no Ruby mapping. Selecting such a type would let it count as
  complete while some of its public identities projected to nothing.
- `BCL_PROJECTION` — the public signature names a BCL type that no complete type projects. The
  mapped BCL set is *derived from measured work*: a BCL type counts as mapped when a type that is
  already complete projects it. It is not a hand-maintained wish list.
- `BEHAVIOR_EVIDENCE` — the type declares a constructor or method whose behaviour lives in XNA IL.
  A struct with no declared constructor and only read-only properties is exempt, because the CLR
  default value is then its entire contract; that is the rule under which
  `TouchPanelCapabilities` was consumed in Foundation 17.

A candidate is consumable only when none of the three applies.

## The rule is validated against shipped work

`test/test_dependency_frontier.rb` restates the rule independently and asserts it twice:

1. it agrees with the generated report for all 40 dependency-complete candidates, and
2. it retroactively classifies **all 31 types completed in Foundations 16, 17 and 18 as
   consumable**.

So the classifier is not a post-hoc rationalisation: if it ever drifts such that already-shipped
work would have been called blocked, or blocked work would have been called consumable, the suite
fails.

## Current frontier: 40 dependency-complete, 0 consumable

| Blocker | Count | Representative types |
| --- | --- | --- |
| `BCL_PROJECTION` + `BEHAVIOR_EVIDENCE` | 23 | the eight XNA exception types, the five `ContentSerializer*` attributes, `ContentManager`, `GameServiceContainer`, `TitleContainer`, `SpriteFont`, `LaunchParameters`, `MathTypeConverter`, the three `*EventArgs` types |
| `BEHAVIOR_EVIDENCE` | 13 | `Input.Touch.TouchLocation`, `Graphics.PresentationParameters`, `Graphics.DisplayMode`, `Graphics.EffectAnnotation`, `Audio.AudioListener`, `Audio.AudioEmitter`, `Audio.AudioCategory`, `Audio.RendererDetail`, `Media.MediaSource`, `Media.Video`, `Input.Touch.GestureSample`, `Graphics.TextureCollection`, `FrameworkDispatcher` |
| `EVENT_PROJECTION` + `BCL_PROJECTION` | 2 | `IUpdateable`, `IDrawable` |
| `EVENT_PROJECTION` + `BCL_PROJECTION` + `BEHAVIOR_EVIDENCE` | 2 | `GameWindow`, `Audio.Microphone` |

`docs/generated/dependency-frontier.md` carries the full table and is regenerated with the report.

## What each blocker actually needs

**`BEHAVIOR_EVIDENCE` needs the retained original XNA assemblies.** `tools/api_compat/reference/PROVENANCE.md`
is explicit that the pinned snapshot is "public contract metadata, not Microsoft binaries or
implementation code". Earlier milestones derived `VertexElement.GetHashCode`, `Viewport.Project` and
the packed-vector algorithms from "the retained original XNA assemblies and direct IL inspection"
plus reference probes run against the real runtime. Those assemblies are not on this reconstructed
Linux host, and the behaviour-corpus upstream source (SHA-256 `398d0201…`) is absent as well.

This is an unavailable proprietary input, not a gap that can be closed by reasoning. Guessing
`TouchLocation.GetHashCode` or `PresentationParameters` constructor defaults would be exactly the
fabricated behaviour this project forbids.

`tools/touch_location_reference_probe.cs` is added in the established probe style so the highest
value item in this category is actionable the moment a Windows XNA host is available: it prints the
Id/State/Position/hash/string/previous-location tuple and the full equality matrix, including
signed-zero and NaN positions and whether the three-argument constructor records a previous
location at all.

**`EVENT_PROJECTION` and `BCL_PROJECTION` need explicit design decisions**, not evidence. Both
would materially extend the public API and the compatibility policy, so both are left for review
rather than invented. See "Decisions required" in `NEXT.md`.

## Verification

Suite 515 runs. Frontier test 5 runs / 490 assertions. No XNA type, CNA ABI value, native binding
or partial-type member changed.
