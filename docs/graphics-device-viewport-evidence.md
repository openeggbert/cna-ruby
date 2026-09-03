# `GraphicsDevice::Viewport`'s setter, and the last `PROPERTY_MAPPING_MISMATCH`

Derived from the pinned `Microsoft.Xna.Framework.Graphics.dll` IL (SHA-256 `560080fc…`), measured
against `~/deps/cna-c-abi-0.21.0/libcna_c_api.so`.

## What the diagnostic was

`PROPERTY_MAPPING_MISMATCH = 1` for this project's whole history, and it was always the same
identity: `Microsoft.Xna.Framework.Graphics.GraphicsDevice::Viewport`. Its cause was one line in
`tools/api_compat/selection.json`:

```json
{ "kind": "property", "name": "Viewport", "static": false, "parameters": [],
  "override": { "set": false } }
```

An `override` is how this project *declares* a deviation from the reference rather than smuggling
one in, and the verifier reports every one as a mismatch — so the diagnostic was working exactly as
designed. What had stopped being examined is the reason behind the declaration.

## What the IL says the setter is

`set_Viewport(Viewport value)` is `CheckDisposed`, then eleven guards, then one native call, then
one cache write. Every guard raises the same `ArgumentException(FrameworkResources.ViewportInvalid,
"value")`, and they are checked in this order:

1. `value.X < 0`
2. `value.Y < 0`
3. `value.Width <= 0`
4. `value.Height <= 0`
5. bounds: `currentRenderTargetCount > 0 ? currentRenderTargets[0].width/height
   : pInternalCachedParams.BackBufferWidth/Height`
6. `value.X + value.Width > width`
7. `value.Y + value.Height > height`
8. `value.MinDepth < 0f`
9. `value.MinDepth > 1f`
10. `value.MaxDepth < 0f`
11. `value.MaxDepth > 1f`
12. `!(value.MaxDepth >= value.MinDepth)`

Then `calli` to `IDirect3DDevice9::SetViewport` at vtable offset `0xbc`, and
`this.currentViewport = value`.

**Guard 12 is `bge.un.s`, and the `.un` is load-bearing.** "Branch if greater-or-equal *or
unordered*" means a NaN takes the branch and does **not** throw. Guards 8–11 are ordered
comparisons, which a NaN also fails. So a viewport with a NaN depth passes every managed check in
XNA and reaches the driver. This projection reproduces that exactly, and the refusal that follows
is CNA's — see the deviation at the end.

`get_Viewport` is `CheckDisposed` then `ldfld currentViewport`: a managed cache, whose only three
writers are this setter, the internal `SetRenderTargets(RenderTargetBinding*, int)` — which resets
it to the new target's bounds with `MaxDepth = 1` — and `InitializeDeviceState`, which sets it to
`{0, 0, BackBufferWidth, BackBufferHeight, 0, 1}`.

## Why the setter was not projected, and why that reason was wrong

The recorded reason had drifted into "the graphics runtime". It is neither that nor a Ruby language
limitation. `cna_graphics_device_set_viewport` is exported by **both** admitted artifacts:

```
$ nm -D --defined-only ~/deps/cna-c-abi-0.21.0/libcna_c_api.so | grep viewport
0000000000aa72ab T cna_graphics_device_get_viewport@@CNA_C_API_0.1
0000000000aa73ec T cna_graphics_device_set_viewport@@CNA_C_API_0.1
```

What actually stood in front of it is the calling convention:

```c
CNA_C_API CNA_Result cna_graphics_device_set_viewport(CNA_Handle graphics_device,
                                                      CNA_Viewport viewport);
```

`CNA_Viewport` is **24 bytes** — four `int32_t` and two `float`, measured by the ABI probe as
`size 24, alignment 4`. The System V x86-64 classification puts any aggregate larger than two
eightbytes in class MEMORY: it is pushed onto the stack rather than carried in registers. Fiddle
cannot pass an aggregate at all, and the `by_value` expansion this manifest already uses for
`CNA_StringView` only works because that aggregate is exactly two INTEGER eightbytes and therefore
byte-for-byte equivalent to two scalar arguments. Nothing equivalent exists for a stack-class
aggregate — so the honest reading was "Fiddle cannot make this call", and that reading was accepted
without being tested.

## What the call really looks like

```
0000000000aa73ec <cna_graphics_device_set_viewport>:
  aa73ec:  push   %rbp
  aa73ed:  mov    %rsp,%rbp
  aa73f0:  sub    $0x20,%rsp
  aa73f4:  mov    %rdi,-0x18(%rbp)      # the handle, from rdi
  aa73f8:  lea    0x10(%rbp),%rax       # the viewport, from the FIRST STACK SLOT
  aa73fc:  mov    %rax,-0x10(%rbp)
  ...
```

`0x10(%rbp)` is the first stack argument slot — saved `rbp` at `0x0`, return address at `0x8`. The
callee reads its handle from `rdi` and its aggregate from three consecutive stack eightbytes, and it
reads nothing else.

Fiddle *can* put values there. A function declared with nine integer arguments puts the first six in
`rdi rsi rdx rcx r8 r9` and the seventh onward on the stack at `[rsp+0]`, `[rsp+8]`, `[rsp+16]` —
exactly where the MEMORY-class aggregate belongs. So the expansion is: the handle, **five register
fillers** the callee never reads, then the aggregate's three eightbytes.

`CNA::Native::Manifest.by_value_memory` records that expansion the way `by_value` records the
register one, and the number of fillers is derived rather than written down: six integer argument
registers, minus the one the handle consumes.

## How it is checked rather than trusted

**By the compiler.** `tools/native_abi/probe.c` gains
`CHECK_FN(cna_graphics_device_set_viewport, CNA_Result, (CNA_Handle, CNA_Viewport))` and the
matching `SIGNATURE` record, so the C prototype is asserted with
`_Static_assert(__builtin_types_compatible_p(...))` against the canonical headers of **both**
admitted versions. `NativeAbiGate.ruby_signature` reconstructs `CNA_Result|CNA_Handle,CNA_Viewport`
from the manifest — the fillers contribute nothing, because they are not arguments of the C
function — and compares it with what the header declares.

**By re-derivation.** `NativeAbiGate.aggregate_mismatches` recomputes both numbers from the
aggregate's measured `sizeof` and from the arguments that precede it, for *every* by-value aggregate
in the manifest, not just this one:

* at most 16 bytes → register class, `ceil(size / 8)` eightbytes, zero fillers;
* larger → MEMORY class, `ceil(size / 8)` eightbytes and `6 − preceding integer arguments` fillers.

A manifest declaring four fillers instead of five, or two eightbytes instead of three, is reported
as a mismatch. Both mutations were planted and both were caught.

**By round trip.** Three distinct viewports, written through the expansion and read back with
`cna_graphics_device_get_viewport`, come back identical in all six fields — including
`MinDepth = 0.25, MaxDepth = 0.75`, which no zero-filled buffer could produce.

**By the negative control.** The same symbol, called with the three eightbytes in registers — which
is what treating the aggregate as register-class would produce — never delivers the values the
caller sent. The callee reads whatever the stack happens to hold, so **the shape of the failure is
artifact-specific and only the failure itself is a fact.** Measured three consecutive calls in one
frame on each artifact, with the intended argument `(9, 9, 8, 8, 0.25, 0.75)`:

| Artifact | Result | Viewport afterwards |
| --- | --- | --- |
| `HEADLESS` | `CNA_RESULT_INTERNAL` (12), all three times | unchanged at `(3, 4, 16, 16, 0.125, 0.875)` |
| `OPENGL33` | `CNA_RESULT_SUCCESS` (0), all three times | `(3, 0, 163173224, 32766, 4.47e-33, 4.59e-41)` |

On the headless artifact the stack did not hold a finite viewport and CNA's exception barrier caught
it; on the real renderer it held something CNA accepted and installed. Neither is the argument, and
that is the whole of the claim: a register-class expansion of this aggregate cannot deliver it.

This paragraph originally recorded only the refusal, and the test beside it asserted only that.
It passed for two milestones because `HEADLESS` is the default artifact, and it failed the first
time the suite was run against `OPENGL33` — a control asserting undefined stack contents rather than
the deterministic half beneath them.
`GraphicsDeviceViewportTest#test_the_register_class_expansion_never_delivers_the_values` now asserts
the deterministic half, and it is green on both.

## Recorded deviations

* **`get_Viewport` asks the device; XNA's reads a managed cache.** They are observationally equal
  for everything the managed contract can distinguish — the round trip above is exact in all six
  fields — and asking is strictly better in the one case they differ: canonical CNA code that moves
  the viewport itself, which a managed cache would answer stalely.
* **A NaN depth is refused by CNA rather than by a managed guard.** XNA's twelfth guard is
  unordered-true and its four range guards are ordered, so a NaN reaches the driver in XNA too.
  `cna_graphics_device_set_viewport` documents that both depth values must be finite and answers
  `CNA_RESULT_INVALID_ARGUMENT`, so the member still refuses; the exception is the translated native
  one rather than `ArgumentException`. Measured: the viewport is unchanged afterwards.
* **The bounds source is the cached render-target bindings**, not a device query — the same cache
  the draw calls' instance-frequency guard reads, and the same thing XNA's
  `currentRenderTargets[0]` is. Measured: binding a 32×32 target makes `(0, 0, 32, 32)` legal and
  `(0, 0, 33, 32)` an `ArgumentException`, and unbinding restores the back buffer's bounds.

## The corpus correction this required

Two `RUBY_MAPPING_QUALIFICATION` observations recorded, as one element of a longer tuple, that this
binding does **not** project `GraphicsDevice::Viewport=`. Both are now false statements about the
binding, so both were corrected — `false` to `true`, one element each — as **surgical byte edits**,
which is a stronger guarantee than a replay proof because every other byte of each file is provably
untouched. Four lines moved in total, and `git diff --stat` says exactly that.

| file | observation | element | pre-correction SHA-256 | post-correction SHA-256 |
| --- | --- | ---: | --- | --- |
| `behavior/xna40-foundation-values.json` | `viewport_title_safe_area.ruby_mapping` | 6 | `2d08025e413f3e4db3f27818c17423716185d9566b4857d593a531e97cf673d1` | `a515d3c34f831ed7d594fa7e61df10883b381a0995f884adc16ed3bf2458dcaf` |
| `behavior/xna40-viewport-values.json` | `viewport_title_safe_area.ruby_mapping` | 6 | `21823530554be44496a0cc9e50588c99e9155b03ad51cbd83c38f0fdc7b8d129` | `45f89636f09dc4386120e0b6d5b1ea8516dfde142f81031d54c58afd5355a15f` |
| `behavior/xna40-foundation-values.json` | `clear_options.ruby_flags_mapping` | 29 | `a515d3c34f831ed7d594fa7e61df10883b381a0995f884adc16ed3bf2458dcaf` | `8a6b6cf7554c8358a589fbd178a0eb228cb51340e145a2eb8328556d0b1c1857` |
| `behavior/xna40-clear-options-values.json` | `clear_options.ruby_flags_mapping` | 29 | `900a655d067f1b392880e0783ae13a751e85ffbb11014c79c55dc0272c412dac` | `632398ee093aa199f01f44aa623377784821644692573b459484f17e62df6513` |

The aggregate is what `tools/run_behavior_corpus.rb` replays and the per-milestone files are the
authoring records, so **both** were corrected rather than only the one that gates: correcting the
aggregate alone would have created an eighth entry in `test_behavior_corpus_integrity.rb`'s closed
supersession register, and this is a value correction rather than a shape supersession. The corpus
replays 526 observations with zero failures afterwards, and the register still holds seven.

Neither observation is a statement about XNA, and neither took its value from CNA: each records what
*this projection* exposes, which is what `RUBY_MAPPING_QUALIFICATION` means. The corpus remains
`never CNA output` by construction.
