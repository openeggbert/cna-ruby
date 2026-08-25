# Foundation 27 — the ContentSerializer attributes and the System.Attribute projection

Completes the five `Microsoft.Xna.Framework.Content.ContentSerializer*` attributes — 16 Ruby
identities, local diagnostics zero on all five — and adds the one BCL projection they need. This is
the largest coherent BCL cluster the frontier had left, and it was taken because **five otherwise
unblocked XNA types depended on it**, which is the only justification this project accepts for
designing a BCL mapping.

## System.Attribute

Ruby has no annotation mechanism. A CLR attribute is an ordinary class whose instances the runtime
attaches to metadata, so in Ruby it projects as an ordinary data-carrying class; what needs
preserving is the CLR **base identity**, which the verifier measures under `BASE_MAPPING_MISMATCH`.

`System.Attribute` therefore projects to `CNA::Runtime::Attribute`, an empty marker base. It
declares nothing, because none of the five XNA types declares a member inherited from
`System.Attribute` — no `Match`, no `TypeId`, no `IsDefaultAttribute`, and none of the static
`GetCustomAttribute` surface. Adding any of those would be inventing a contract.

Nothing in this binding reads an attribute: there is no `ContentManager`, `ContentReader`,
`ContentTypeReader`, XNB format support or content pipeline of any kind. The `Content` namespace
holds exactly these five types.

## Thrown-exception mapping

Three of the five constructors and one setter throw `System.ArgumentNullException`.
`mapping-rules.json` gains an explicit table so one CLR exception always maps to exactly one Ruby
exception:

| CLR | Ruby | Why |
| --- | --- | --- |
| `System.ArgumentNullException` | `ArgumentError` | the CLR throws it for a null **or empty** string, so `TypeError` would be wrong for half its cases |
| `System.ArgumentOutOfRangeException` | `RangeError` | the class this binding already raises for a value outside its allowed range (`AudioEmitter.DopplerScale`) |
| `System.ArgumentException` | `ArgumentError` | |
| `System.IndexOutOfRangeException` | `IndexError` | matching the collection-index rule already documented |

The Ruby message is the CLR's parameter name, so `CollectionItemName = ""` raises
`ArgumentError: value` and `ContentSerializerRuntimeTypeAttribute.new("")` raises
`ArgumentError: runtimeType`, exactly as the IL's `ldstr` operands say.

## What the IL established

**`ContentSerializerAttribute`** — six private fields, nine declared identities.

- The constructor stores `allowNull = true` **before** calling the base constructor, and makes no
  other store. Every other field keeps its CLR default: `ElementName` null, `FlattenContent`,
  `Optional` and `SharedResource` false, `collectionItemName` null.
- `ElementName` is a plain field store the CLR never inspects, so an empty string and null are both
  accepted and read back unchanged.
- `CollectionItemName` **get** answers the literal `"Item"` whenever the raw field is null or empty,
  and the raw field otherwise.
- `CollectionItemName` **set** throws `ArgumentNullException("value")` for null or empty.
- `HasCollectionItemName` is the negation of that same emptiness test — so a default instance
  answers `"Item"` from the getter while `HasCollectionItemName` is `false`.
- `Clone` builds a new instance and copies the **six raw fields**, not the getters, so a clone of a
  default instance still answers `"Item"` and still reports no collection item name.

**`ContentSerializerCollectionItemNameAttribute`** and **`ContentSerializerRuntimeTypeAttribute`** —
`base()`, then `IsNullOrEmpty` on the argument throws `ArgumentNullException` naming the parameter,
then one store. Both properties are get-only, and neither has the `"Item"` fallback.

**`ContentSerializerIgnoreAttribute`** — `base()` and nothing else. Zero fields, zero properties.

**`ContentSerializerTypeVersionAttribute`** — `base()` then one store. **The only one of the five
that validates nothing**, so negative and zero versions are accepted; only this binding's `Int32`
boundary applies.

## Structural movement

TARGET_TYPES 129 → 134, TARGET_MEMBERS 1697 → 1713, TOTAL_DIAGNOSTICS 312 → 307, MISSING_TYPE
128 → 123, COMPLETE_TYPES 123 → 128. `MISSING_MEMBER` 132, `PARTIAL_TYPES` 6, every structural
mismatch category unchanged, allowlist 0, unmeasured 0. `BCL_PROJECTED_IDENTITIES` 4 → 5.

Frontier: 22 dependency-complete candidates, 0 consumable. `System.Attribute` and `System.TimeSpan`
leave the `notYetDesigned` list; `System.Type`, `System.IServiceProvider`, `System.IO.Stream`,
`StringBuilder`, `SerializationInfo`, `ReadOnlyCollection` and `Dictionary` remain there.

CNA ABI unchanged: 38 / 122 / 290 / 290 / 2 / 59.

## Verification

- Full Ruby suite: 635 runs / 20701 assertions / 0 failures / 0 errors / 0 skips.
- Behaviour corpus: 420 observations / 420 assertions / 0 failures; 10 additive rows in the new
  `CONTENT_ATTRIBUTE` group.
- API verifier strict: 307 diagnostics, all deferred; leak-only clean.
- RBS: `rbs validate` clean.
- Native ABI: unchanged.
