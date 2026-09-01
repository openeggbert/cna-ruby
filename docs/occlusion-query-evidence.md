# Foundation 84 — `OcclusionQuery`, whose getter is what unblocks the next call

One type, six identities, and the last entry the `partialDependencySatisfied` list had been carrying
since `GraphicsResource` completed. The strict scoreboard goes **197 complete / 58 missing to
198 / 57**, `TARGET_MEMBERS` 2347 to 2353 and `TOTAL_DIAGNOSTICS` 151 to **150**.

## Five fields and the state machine they make

```
.ctor(device)   null device -> ArgumentNullException("graphicsDevice", DeviceCannotBeNullOnResourceCreate)
                a profile without ProfileCapabilities.OcclusionQuery -> NotSupportedException
                then _hasIsCompleteBeenQueried = **true**
Begin()         _isInBeginEndPair          -> InvalidOperationException(EndMustBeCalledBeforeBegin)
                !_hasIsCompleteBeenQueried -> InvalidOperationException(IsCompleteMustBeCalled)
                then native begin, and _isAvailable false, _isInBeginEndPair true,
                _hasCalledBegin true, _hasIsCompleteBeenQueried **false**
End()           !_isInBeginEndPair         -> InvalidOperationException(BeginMustBeCalledBeforeEnd)
                then native end, and _isInBeginEndPair false
IsComplete      sets _hasIsCompleteBeenQueried true **first**, then answers _isAvailable with no
                native object or before any Begin, and otherwise asks the device and records the
                pixel count when the answer is yes
PixelCount      !IsComplete                -> InvalidOperationException(DataNotAvailable)
```

The rule a reader would not guess is the pair of stores at each end: the **constructor** sets
`_hasIsCompleteBeenQueried` true, which is what lets the first `Begin` through, and `Begin` clears
it — so every later `Begin` needs an `IsComplete` read in between. `IsComplete` is not a pure query,
and it records that it ran even on the paths that answer without asking the device.

## What CNA supplies, and the one route that is not a diagnostic

Seven routes, all declared by **both** admitted header versions: create, begin, end,
`get_is_complete`, `get_pixel_count`, `has_renderer` and destroy.

`has_renderer` is production surface rather than a probe: XNA's `get_IsComplete` begins by checking
whether the query still holds a native object (`pComPtr`) and answers `_isAvailable` without asking
the device when it does not. That is the same question, and CNA exports it.

`cna_occlusion_query_get_is_pixel_count_precise_ext` stays **unbound**. It answers a real question —
OpenGL ES 3.0 and WebGL 2 count "any or none" rather than fragments, so a coverage ratio computed
from a boolean count is `1/area` rather than a fraction, and CNA's own header says so — but XNA has
no identity for it, and a route bound for no caller is dead native surface.

## DEVIATION, recorded: the profile check is CNA's

XNA refuses construction on a `GraphicsProfile` whose `ProfileCapabilities.OcclusionQuery` is false —
which is `Reach` — with `NotSupportedException`. That is a device capability rather than a managed
rule, and inventing a profile table here would be guessing at hardware. CNA answers the same
question from the backend: `cna_occlusion_query_create` reports `CNA_RESULT_NOT_SUPPORTED` where the
renderer has no query object, which surfaces as `CNA::CapabilityError`. Every qualified artifact
creates one.

## Measured, and the renderers disagree about *when*

Both artifacts answer the same shape and differ in timing, which is the honest result for a GPU
query:

- `HEADLESS` completes immediately — one `Begin`/`End` pair and `IsComplete` is true on the first
  read, with a pixel count of 1.
- `OPENGL33` is asynchronous: the first read after `End` is usually false and the query settles
  within a few reads, counting **0** for an interval that drew nothing.

The test reads up to thirty-two times and asserts the count is 0 or 1 — zero where the backend
tallies fragments and nothing was drawn, one where the backend can only answer "any".

## Mutation

Seven planted defects, six caught: the constructor's flag cleared, `Begin` not clearing it, either
sequencing guard dropped, `IsComplete` not recording that it ran, and `PixelCount` answering without
checking. The survivor removes the `_hasCalledBegin` short-circuit — and it is an **equivalent
mutant on every qualified artifact**: the raw route answers "not complete" for a query that has
never run, which is exactly what the guard produces. The test now asserts that agreement rather than
leaving the survivor unexplained.

## The frontier

`partialDependencySatisfiedCandidates` falls from seven entries to six. `OcclusionQuery` had been on
that list rather than the candidate list because its one unmet dependency is the partial
`GraphicsDevice` — and the only member of it the query's IL reaches is the constructor's
profile-capability check, which is the device fact CNA answers itself. Nothing arrived behind it; the
six that remain are all stock effects and `DrawableGameComponent`.
