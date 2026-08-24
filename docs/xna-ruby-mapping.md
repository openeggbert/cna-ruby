# XNA 4.0 to Ruby Mapping

The selected authority is the Microsoft XNA Framework 4.0 Windows runtime metadata snapshot pinned under `tools/api_compat/reference`. Ruby projection expectations are derived from that snapshot and `tools/api_compat/mapping-rules.json`, never from implementation source.

| CLR concept | Strict Ruby projection |
| --- | --- |
| `Microsoft.Xna.Framework.Vector2` | `Microsoft::Xna::Framework::Vector2` |
| class/struct | Ruby class; reference/value distinction remains in the static contract |
| enum | frozen instances of a dedicated Ruby class, with named constants and exact integer identity |
| constructor overload | one retained `.ctor` contract identity; runtime dispatch through `Class.new`/`initialize` |
| method/property | exact XNA spelling; getter `X`, setter `X=` only when writable |
| static method/property | class method such as `Vector2.Zero`, returning a fresh value where XNA returns a struct |
| field | exact reader and, for mutable struct fields, writer; field identity remains distinct in the static contract |
| operator | mapped Ruby operator where syntax exists; original `op_*` identity remains measured |
| `ref` input | ordinary typed Ruby value input, copied at value boundaries; caller mutation is never simulated |
| one `out` value | ordinary Ruby method return; the CLR overload identity remains separately retained |
| several `out` values | ordered Ruby Array return, following any non-void CLR return (`Matrix#Decompose` returns `[success, scale, rotation, translation]`) |
| array transform overload | caller-provided source/destination Arrays with exact whole-array or indexed-range call shape |
| event | measured contract identity; eventual projection uses explicit add/remove subscription methods |
| generic type/member | CLR arity and full signature remain in the contract; Ruby call dispatch must reject collisions deterministically |

Ruby enum APIs reject arbitrary integers unless the formal parameter bridge explicitly calls the enum's coercion function. Flags enum combinations may contain only declared bits. The synthetic CLR enum storage field `value__` has no Ruby projection, so the formal expected member count excludes exactly those 49 metadata fields.

Ruby objects cannot reproduce CLR struct assignment copying: `b = a` aliases. Value objects therefore contain no native handle, implement `dup`/`clone`, and copy at constructors, returned/set struct properties, collection boundaries, and marshal boundaries. This limitation is classified as `LANGUAGE_MAPPING_LIMITATION`, not hidden.

Geometry array transforms retain caller-owned destination storage. Whole-array calls map to `(source, transform, destination)` and range calls to `(source, source_index, transform, destination, destination_index, length)`. XNA's forward write order is preserved, including observable overlap behavior. A negative length performs no iteration; invalid indices are observed only when at least one element is processed. Every collapsed Ruby call shape still has one entry per CLR overload in `tools/api_compat/signatures.json` and the generated geometry RBS.

Uppercase methods are legal in Ruby but bare uppercase tokens are parsed as constants in several contexts. Ported code uses an explicit receiver (`self.Exit`, `Color.White`). Idiomatic snake_case aliases are excluded from the strict surface.
