# Foundation 25 — constructor-free classes

Establishes how a CLR class whose only constructor is internal projects to Ruby, and applies that
rule to `Graphics.DisplayMode`, `Graphics.ResourceCreatedEventArgs` and
`Graphics.ResourceDestroyedEventArgs`. Nine Ruby identities, local diagnostics zero on all three.

## The rule

> A CLR class whose only constructor is internal projects to a Ruby class with `new` made private.
> Its **public non-constructibility is part of the contract**, and the internal construction path
> stays reachable to a future producer through `__send__`. No producer is fabricated, and no public
> Ruby constructor is created that XNA does not expose.

This is not a new mechanism: `GraphicsResource`, `Texture` and `Texture2D` have used
`private_class_method :new` plus `__send__` construction since the native milestones. Foundation 25
only names the rule and writes it into `mapping-rules.json`.

Foundation 21 had deferred such classes with a blanket "a class has no CLR default value, so
projecting one nothing can instantiate would be a hollow identity". That was too broad. The pinned
IL shows each of these three declares exactly one constructor, `assembly`-scoped, and public
properties that are single field reads: the type's whole public contract is expressible, and
withholding it does not make the binding more honest — it only leaves the contract unpinned for
whenever a producer arrives.

What still keeps a type out is that its **values**, or the arguments its internal constructor needs,
do not exist here. The `RUNTIME_DATA` register now says exactly that, and `Media.Video` remains in
it for a sharper reason than before: its internal constructor takes a `GraphicsDevice` — one of the
six deferred partial runtime types — and builds a `Duration` from tick components only the content
pipeline supplies.

## DisplayMode

`assembly .ctor(int32 width, int32 height, SurfaceFormat format)`: three stores, no validation.
Three private fields, five get-only properties and `ToString`.

| Member | What the IL does |
| --- | --- |
| `Width`, `Height`, `Format` | single field reads |
| `AspectRatio` | `brfalse` on height then `brtrue` on width — a zero in **either** answers `0`; otherwise both convert to `Single` and divide in `Single` |
| `TitleSafeArea` | `Viewport.GetTitleSafeArea(0, 0, width, height)`, which is itself just `new Rectangle(x, y, w, h)` — a fresh rectangle at the origin |
| `ToString` | `{Width:… Height:… Format:… AspectRatio:…}`, with the aspect ratio formatted as a Single |

Nothing validates the extents, so negative values divide as given. A complete managed `DisplayMode`
implies **no** `GraphicsAdapter` and **no** `DisplayModeCollection`; nothing enumerates a display.

## ResourceCreatedEventArgs and ResourceDestroyedEventArgs

Pure storage over `System.EventArgs`, which the Foundation 21 register maps to
`CNA::Runtime::EventArgs`. `ResourceCreatedEventArgs.ctor(object resource)` is `base()` plus one
store. `ResourceDestroyedEventArgs.ctor(string name, object tag)` is `base()`, then `tag`, then
`name` — the IL's order, preserved.

Neither is raised: `GraphicsDevice.ResourceCreated` and `GraphicsDevice.ResourceDestroyed` remain
deferred, and `GraphicsDevice` still exposes exactly `IsDisposed`, `Viewport` and `Clear`.

## Structural movement

TARGET_TYPES 125 → 128, TARGET_MEMBERS 1686 → 1695, TOTAL_DIAGNOSTICS 316 → 313, MISSING_TYPE
132 → 129, COMPLETE_TYPES 119 → 122. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6, every structural
mismatch category unchanged, allowlist 0, unmeasured 0.

Frontier: 27 dependency-complete candidates, 1 consumable. `RUNTIME_DATA` shrank from eight entries
to six. CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59.

## Verification

- Full Ruby suite: 619 runs / 20549 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 408 observations / 408 assertions / 0 failures; 6 additive rows in the new
  `CONSTRUCTOR_FREE` group.
- API verifier strict: 313 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
