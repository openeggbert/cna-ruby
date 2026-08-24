# Foundation 9 DisplayOrientation evidence

Foundation 9 closes exactly `Microsoft.Xna.Framework.DisplayOrientation`. The pinned XNA 4.0
Windows runtime metadata contains one enum and five CLR identities. The established Ruby exclusion
of the synthetic `value__` storage field leaves exactly four Ruby XNA identities. No method,
property, constructor, event, or operator is declared by this XNA type.

## Exact contract

| Type | CLR identities | Expected Ruby | Target | Local diagnostics | Kind |
| --- | ---: | ---: | ---: | ---: | --- |
| `DisplayOrientation` | 5 | 4 | 4 | 0 | flags enum, underlying `System.Int32` |

The four values are explicit metadata facts:

| Name | Raw value |
| --- | ---: |
| `Default` | 0 |
| `LandscapeLeft` | 1 |
| `LandscapeRight` | 2 |
| `Portrait` | 4 |

The metadata marks the type `[Flags]`; its declared-bit union is therefore `0x7`. Runtime values
are typed, frozen `CNA::Runtime::EnumValue` instances created through the unchanged
`CNA::Runtime::EnumType` policy. `DisplayOrientation.coerce(0)` returns the canonical declared
`Default` instance rather than an anonymous zero value. `coerce(1)`, `coerce(2)`, and `coerce(4)`
likewise return their declared canonical values.

## Ruby flags mapping qualification

The existing Ruby language projection creates typed, frozen combined values without collapsing
their bits. OR combinations `3`, `5`, `6`, and `7` retain those exact raw values. AND returns
canonical declared values where possible: `(LandscapeLeft | Portrait) & LandscapeLeft` is
`LandscapeLeft`, intersection with `LandscapeRight` is `Default`, and the all-bits value intersected
with `Portrait` is `Portrait`.

The formal controlled-flags policy rejects any bit outside `0x7`; raw values `8`, `9`, and `0x100`
raise `RangeError`. It also rejects non-Integer coercion and composition with `SpriteEffects`,
`Buttons`, or ordinary enums using `TypeError`. This is qualification of the already-established
Ruby mapping, not a claim that CLR forbids unnamed or unknown underlying enum values. No new
language-mapping rule or mismatch was introduced.

Inherited Ruby `to_s`, `inspect`, `to_i`, `|`, and `&` support the language projection. They do not
become declared XNA identities. No `ToString`, `HasFlag`, orientation helper, or platform behavior
was added. The RBS declaration statically retains all four constants plus the existing flags
operators, with no `untyped` or catch-all signature.

## Evidence provenance and boundary

The `DISPLAY_ORIENTATION` behavior group explicitly distinguishes its sources. Raw values and the
`[Flags]` identity are `PURE_XNA_DERIVED` pinned-metadata facts. Canonical coercion, OR/AND,
undefined-bit rejection, cross-type safety, and frozen typed combinations are
`RUBY_MAPPING_QUALIFICATION`. Neither class of evidence is derived from CNA output.

This milestone is completely managed. It adds no native constant, ABI function, layout, Fiddle
binding, or CNA source. `GraphicsDeviceManager.SupportedOrientations`, all other
`GraphicsDeviceManager` members, `GameWindow`, `CurrentOrientation`, `OrientationChanged`, screen
rotation, window rotation, and mobile/platform orientation remain explicitly deferred. The enum
represents bits only.

## Release qualification

Focused managed tests run without `CNA_NATIVE_LIBRARY`: DisplayOrientation passes 5 runs / 83
assertions, the verifier self/mutation suite passes 52 / 176, and runtime/RBS consistency passes
9 / 1,634. RBS 3.4.0 validation, bundle consistency, syntax validation, and the 255-observation
behavior corpus all pass. The complete native-backed suite passes 190 runs / 4,273 assertions with
no failures, errors, or skips.

Native ABI verification remains exactly unchanged at 38 bound functions, 122 signature
measurements, 290 C and 290 Ruby layout measurements, 2 callbacks, and 59 constants, with zero
missing header/library symbols and zero ABI mismatches. Stress retains 20 game, texture,
SpriteBatch, and game-recreation cycles; 50 Mouse and GamePad-state cycles; and 20 GamePad
capability cycles, with zero crashes, observed use-after-free, or observed double-free. Sanitizers
were not run and remain reported as `NOT_RUN`.

The final `cna-ruby-0.1.0.dev0.gem` retains 37 entries and has SHA-256
`61b1b52996b5905815caca02c1334b8ab0d37d928eb124ecd49e86d5801a40ff`. Its audit finds zero
forbidden entries, bundled native libraries, or developer-path leaks. A fresh gem home installs
only that exact gem, validates all 28 installed Ruby source files, requires `cna`, qualifies the
enum, and passes the unchanged template at 60 and 600 frames. Maintained-source template runs pass
the same frame counts; the template source remains clean at commit
`42ae209b8b4fd175b7b1e5de43d895083b81877b`.
