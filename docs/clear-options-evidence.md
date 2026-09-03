# Foundation 13 ClearOptions evidence

Foundation 13 closes exactly one managed type:
`Microsoft.Xna.Framework.Graphics.ClearOptions`. It does not add either deferred four-argument
`GraphicsDevice.Clear` overload and changes no native route.

## Exact contract

The authority is the pinned Microsoft XNA Framework 4.0 Windows runtime metadata from
`Microsoft.Xna.Framework.Graphics.dll` 4.0.0.0, SHA-256
`560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55`.

| Type | Reference identities | Expected Ruby identities | Target Ruby identities | Local diagnostics |
| --- | ---: | ---: | ---: | ---: |
| `Microsoft.Xna.Framework.Graphics.ClearOptions` | 4 | 3 | 3 | 0 |

Metadata records `kind=enum`, `underlyingType=System.Int32`, `baseType=System.Enum`, `sealed=true`,
`flags=true`, and no direct interface. The four declared CLR fields are:

| Field | Raw value | Ruby XNA identity |
| --- | ---: | --- |
| `value__` | synthetic Int32 storage | excluded by the established enum-storage mapping |
| `Target` | 1 | `ClearOptions::Target` |
| `DepthBuffer` | 2 | `ClearOptions::DepthBuffer` |
| `Stencil` | 4 | `ClearOptions::Stencil` |

There is no declared constructor, method, property, event, or operator. The exact runtime namespace
is `Microsoft::Xna::Framework::Graphics`; there is no root-framework or `GraphicsDevice` alias.
`require "microsoft/xna/framework/graphics"` exposes the enum without initializing a CNA native
library.

## No named zero

`XNA_NAMED_ZERO_PRESENT=false`. The pinned type declares no `None`, `Default`, `Empty`, or other
zero-valued name, and it declares no `All` identity. Consequently:

- `ClearOptions::None` is absent;
- `ClearOptions::Default` is absent;
- `ClearOptions::All` is absent;
- `constants(false)` contains exactly `Target`, `DepthBuffer`, and `Stencil`.

The verifier rejects invented `None=0`, `Default=0`, and `All=7` as unexpected XNA members. No
convenience identity inflates the public contract.

## Ruby flags projection

The implementation uses the unchanged `CNA::Runtime::EnumValue` / `CNA::Runtime::EnumType` policy
with `define_values(..., flags: true)`. The declared-bit mask is `1 | 2 | 4 = 0x7`.

Named values are typed, frozen, and canonical. `coerce(1)`, `coerce(2)`, and `coerce(4)` return the
same objects as `Target`, `DepthBuffer`, and `Stencil`; coercing an existing ClearOptions value
returns that object unchanged.

All raw values `0..7` are valid under the controlled Ruby flags mapping. Raw zero is not an XNA
declared identity, but it is a valid Ruby language-projected flags value containing no unknown bit:

```text
ClearOptions.coerce(0).instance_of?(ClearOptions) = true
ClearOptions.coerce(0).frozen? = true
ClearOptions.coerce(0).to_i = 0
ClearOptions.coerce(0).to_s = "0"
ClearOptions.coerce(0).inspect = "Microsoft::Xna::Framework::Graphics::ClearOptions::0"
```

Repeated `coerce(0)` returns the same cached unnamed object. The unnamed combinations `3`, `5`,
`6`, and `7` are likewise typed, frozen, exact-valued, and cached by raw value. Raw `7` remains
unnamed; it does not create `ClearOptions::All`.

OR composition produces exact masks `3`, `5`, `6`, and `7`. AND composition returns canonical
named values when the result is `1`, `2`, or `4`. In particular,
`Target & DepthBuffer` returns the cached typed/frozen unnamed zero value, never `nil`, `false`, or
an Integer.

Values `8`, `9`, `0x100`, and `-1` contain bits outside `0x7` and raise `RangeError`. Nil, true,
false, Float, String, and arbitrary Object inputs raise `TypeError`; no `to_i`, name, symbol, or
duck conversion is accepted. Coercion, OR, and AND reject values from `DisplayOrientation`,
`SpriteEffects`, `Buttons`, `GraphicsDeviceStatus`, `GraphicsProfile`, and `SurfaceFormat`.
Cross-type equality remains false and comparison returns nil.

Inherited `to_s`, `inspect`, `to_i`, `|`, `&`, and `coerce` are Ruby mapping infrastructure, not
XNA declared identities. No `ToString`, `HasFlag`, `Contains`, `Includes`, predicate, mask, or
valid-bits helper is added.

## Structural strict-zero matrix

The selected type has zero local diagnostics in every measured category:

| Category | Count | Category | Count |
| --- | ---: | --- | ---: |
| `MISSING_MEMBER` | 0 | `UNEXPECTED_MEMBER` | 0 |
| `TYPE_KIND_MISMATCH` | 0 | `BASE_MAPPING_MISMATCH` | 0 |
| `INTERFACE_MAPPING_MISMATCH` | 0 | `FIELD_MAPPING_MISMATCH` | 0 |
| `PROPERTY_MAPPING_MISMATCH` | 0 | `METHOD_SIGNATURE_MAPPING_MISMATCH` | 0 |
| `PARAMETER_MAPPING_MISMATCH` | 0 | `RETURN_MAPPING_MISMATCH` | 0 |
| `OVERLOAD_MAPPING_MISMATCH` | 0 | `GENERIC_MAPPING_MISMATCH` | 0 |
| `ENUM_VALUE_MISMATCH` | 0 | `FLAGS_MAPPING_MISMATCH` | 0 |
| `EVENT_MAPPING_MISMATCH` | 0 | `OPERATOR_MAPPING_MISMATCH` | 0 |
| `LANGUAGE_MAPPING_MISMATCH` | 0 | `INTERNAL_TYPE_LEAK` | 0 |
| `RAW_HANDLE_LEAK` | 0 | `PUBLIC_NATIVE_FFI_LEAK` | 0 |
| `ALLOWLIST_ENTRIES` | 0 | `UNMEASURED_STRUCTURAL_CATEGORY` | 0 |

Focused generic and ClearOptions mutations detect a missing type, wrong namespace, wrong type
kind, wrong underlying type, flags=false/ordinary-enum classification, all three raw-value
mutations, missing Stencil, exposed `value__`, invented None/Default/All, unexpected XNA members,
public helper leakage, a wrong runtime flags mask, and accidental addition of each deferred
GraphicsDevice.Clear overload. A generic `1/2/4` flags fixture proves that structural validity does
not require a declared zero member. No manual allowlist or special ClearOptions verifier rule is
used.

## Behavior provenance

The compact `CLEAR_OPTIONS` corpus group has two observations. One `PURE_XNA_DERIVED` observation
records enum kind, Int32 underlying type, flags metadata, values 1/2/4, no declared zero, and no
declared All. One `RUBY_MAPPING_QUALIFICATION` observation covers typed/frozen/cached values,
unnamed zero, all combinations, AND-to-zero, controlled-mask rejection, non-Integer and cross-type
safety, strings, exact constants, and the unchanged deferred/native boundary.

The cumulative corpus is 273 observations / 273 assertions with zero failures: 268
`PURE_XNA_DERIVED` and five `RUBY_MAPPING_QUALIFICATION`. Ruby mask enforcement is deliberately
classified as mapping qualification, not XNA runtime behavior or CNA evidence.

## Explicitly deferred scope — **closed by Foundation 91**

This milestone selected exactly one `Clear(Color)` overload, over the native
`cna_graphics_device_clear_rgba` route, and deferred the two four-argument ones:

```text
Clear(ClearOptions, Color, Single, Int32)
Clear(ClearOptions, Vector4, Single, Int32)
```

Both landed in Foundation 91, together with a route swap. `clear_rgba` takes four normalised
floats, which was honest while `ClearOptions` was not projected and the device had no render
targets; XNA's `Clear(color)` is `Clear(DefaultClearOptions, color, 1f, 0)` — a packed D3DCOLOR, a
depth and a stencil — and `cna_graphics_device_clear_options` is that shape exactly. All three
overloads reach it, `clear_rgba` left the manifest for want of a production call site, and
`GraphicsDevice.Clear expected 3, got 1` left the overload register.

`GraphicsDevice.Viewport=`, the other deferral this section recorded, was projected in
Foundation 89, and `PROPERTY_MAPPING_MISMATCH` has been zero since.

No CNA enum, constant, function, Fiddle argument, manifest entry, native conversion, depth/stencil
operation, or renderer clear-mask capability is added **by this milestone**; Foundation 91's swap
is recorded above and is still one route rather than two. ABI verification remains exactly 38 bound
functions, 122 signature measurements, 290 C and 290 Ruby layout measurements, two callbacks,
and 59 constants, with zero missing symbol or mismatch.

## Qualification

The focused native-unset ClearOptions suite passes 8 runs / 159 assertions. Verifier mutation and
self-tests pass 80 / 162; runtime/RBS consistency passes 13 / 1779; RBS 3.4.0 validation passes.
The cumulative source suite passes 249 / 4796 with zero failure, error, or skip. Viewport remains
complete at 14/14, and DisplayOrientation, SpriteEffects, Buttons, ordinary enums, Matrix, Vector3,
Rectangle, Keyboard, Mouse, GamePad, the native `Clear(Color)` route, the Viewport getter, resource
ownership, and wrong-thread behavior all retain their qualified tests.

Native integration passes 14 / 528. Stress retains 20 Game, Texture2D, SpriteBatch, and Game
recreation cycles; 50 Mouse and GamePad state cycles; and 20 GamePad capability cycles. Crashes,
observed UAF, and observed double-free are zero. Sanitizers were not run and remain `NOT_RUN`.

The final `cna-ruby-0.1.0.dev0.gem` has 37 entries and SHA-256
`eee6fde53cadb145d2b9326be5e7c892fe275cb46106fd133a05ad05ae5963eb`, with zero forbidden
entry, bundled native library, or developer path. A fresh exact-GEM_HOME install validates all 28
installed Ruby sources, qualifies ClearOptions with the native library unset, and passes the
unchanged template at 60 and 600 frames. The maintained source-path template passes both frame
counts and remains clean at `42ae209b8b4fd175b7b1e5de43d895083b81877b`.

## The corpus correction Foundation 91 required

`clear_options.ruby_flags_mapping` recorded, as one element of its tuple,
`GraphicsDevice.instance_method(:Clear).arity == 1`. Ruby cannot overload by parameter type, so
three XNA identities are one method with a variable arity, and that element is now `-1`. Corrected
as a **surgical byte edit** in the aggregate and in this milestone's authoring record alike, so the
closed supersession register in `test_behavior_corpus_integrity.rb` still holds seven.

| file | element | pre-correction SHA-256 | post-correction SHA-256 |
| --- | ---: | --- | --- |
| `behavior/xna40-foundation-values.json` | 28 | `8a6b6cf7554c8358a589fbd178a0eb228cb51340e145a2eb8328556d0b1c1857` | `680a009dbaa6cf1fba6e1722a0caa5ba1b08fbe7d34913b2d3959e7b149f08d1` |
| `behavior/xna40-clear-options-values.json` | 28 | `632398ee093aa199f01f44aa623377784821644692573b459484f17e62df6513` | `1a84934b75f2007037dfbc149de7d3ac10fbcc13aafe4143636f101296f60356` |

Two lines moved. The observation is `RUBY_MAPPING_QUALIFICATION` — it records what this projection
exposes, not an XNA fact and not a CNA measurement — and the corpus replays 526 observations with
zero failures afterwards.
