# XNA 4.0 to Ruby Mapping

The selected authority is the Microsoft XNA Framework 4.0 Windows runtime metadata snapshot pinned under `tools/api_compat/reference`. Ruby projection expectations are derived from that snapshot and `tools/api_compat/mapping-rules.json`, never from implementation source.

| CLR concept | Strict Ruby projection |
| --- | --- |
| `Microsoft.Xna.Framework.Vector2` | `Microsoft::Xna::Framework::Vector2` |
| class/struct | Ruby class; reference/value distinction remains in the static contract |
| enum | frozen instances of a dedicated Ruby class, with named constants and exact integer identity |
| constructor overload | one retained `.ctor` contract identity; runtime dispatch through `Class.new`/`initialize` |
| method/property | exact XNA spelling; getter `X`, setter `X=` only when writable |
| indexed `Item[index]` property | `collection[index]` and `collection[index] = value`; getter/setter identity and mutability remain measured |
| static method/property | class method such as `Vector2.Zero`, returning a fresh value where XNA returns a struct |
| `System.IntPtr` | signed native-pointer-width Ruby `Integer`; width is `Fiddle::SIZEOF_VOIDP * 8`, with exact range validation and two's-complement conversion only at the private fixed-width C carrier boundary |
| field | exact reader and, for mutable struct fields, writer; field identity remains distinct in the static contract |
| operator | mapped Ruby operator where syntax exists; original `op_*` identity remains measured |
| `ref` input | ordinary typed Ruby value input, copied at value boundaries; caller mutation is never simulated |
| one `out` value | ordinary Ruby method return; the CLR overload identity remains separately retained |
| several `out` values | ordered Ruby Array return, following any non-void CLR return (`Matrix#Decompose` returns `[success, scale, rotation, translation]`) |
| array transform overload | caller-provided source/destination Arrays with exact whole-array or indexed-range call shape |
| event | measured contract identity; eventual projection uses explicit add/remove subscription methods |
| generic type/member | CLR arity and full signature remain in the contract; a generic definition with base name `Name` maps to `NameOfT` for arity 1 and `NameOfT1T2...TN` for higher arity |
| `ICollection<CurveKey>` | the CLR interfaces remain in structural metadata; the exact typed collection members live directly on `CurveKeyCollection` |
| `IEnumerator<CurveKey>` | `GetEnumerator` returns a fresh Ruby `Enumerator`; no public fake `System::Collections` hierarchy |

Ruby enum APIs reject arbitrary integers unless the formal parameter bridge explicitly calls the enum's coercion function. Flags enum combinations may contain only declared bits. The synthetic CLR enum storage field `value__` has no Ruby projection, so the formal expected member count excludes exactly those 49 metadata fields.

The generic-name rule is project-wide and collision-safe. The non-generic `Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector` therefore remains `Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVector`, while the CLR arity-one identity maps to `Microsoft::Xna::Framework::Graphics::PackedVector::IPackedVectorOfT`. The latter remains `IPackedVectorOfT[TPacked]` in RBS and retains the CLR `TPacked` parameter and every constructed generic identity in verifier metadata. There is no alias between the two modules and no synthetic `System` namespace.

CLR interfaces project to Ruby modules. PackedVector explicit interface members are private Ruby protocol methods: a format-specific public `ToAlpha`, `ToSingle`, `ToVector2`, or `ToVector3` remains the only declared conversion where the XNA metadata says so, while private `ToVector4` and `PackFromVector4` retain callable interface behavior without becoming unexpected public XNA members. The verifier checks module ancestry and rejects a concrete type that merely inherits an abstract interface stub without supplying the protocol operation.

Ruby objects cannot reproduce CLR struct assignment copying: `b = a` aliases. Value objects therefore contain no native handle, implement `dup`/`clone`, and copy at constructors, returned/set struct properties, collection boundaries, and marshal boundaries. This limitation is classified as `LANGUAGE_MAPPING_LIMITATION`, not hidden.

Geometry array transforms retain caller-owned destination storage. Whole-array calls map to `(source, transform, destination)` and range calls to `(source, source_index, transform, destination, destination_index, length)`. XNA's forward write order is preserved, including observable overlap behavior. A negative length performs no iteration; invalid indices are observed only when at least one element is processed. Every collapsed Ruby call shape still has one entry per CLR overload in `tools/api_compat/signatures.json` and the generated geometry RBS.

Uppercase methods are legal in Ruby but bare uppercase tokens are parsed as constants in several contexts. Ported code uses an explicit receiver (`self.Exit`, `Color.White`). Idiomatic snake_case aliases are excluded from the strict surface.

`System.IntPtr` never maps to `Fiddle::Pointer`, `CNA_Handle`, or `void*` in the public API. On the
qualified x86-64 host it accepts `-9223372036854775808..9223372036854775807`. A negative value is
carried through a canonical unsigned C integer as the same-width two's-complement bit pattern and
is sign-extended back to Ruby on return. The scalar is externally owned: Ruby never dereferences,
frees, closes, or otherwise assumes ownership of it.

`CurveKeyCollection` deliberately does not mix in Ruby `Enumerable`, because that would add a broad helper surface unrelated to XNA. Its mapped `Enumerator` preserves XNA order, independent cursors, and `List<CurveKey>`-style fail-fast mutation detection. Invalid strict collection indices, including negative indices, map to `IndexError`; null/wrong typed values map to `TypeError`, destination-capacity failures map to `ArgumentError`, and enumerator invalidation maps to `RuntimeError`.
