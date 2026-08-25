# Foundation 29 — `ReadOnlyCollection<T>` projects to `CNA::Runtime::ReadOnlyCollection`

`System.Collections.ObjectModel.ReadOnlyCollection`1` was the last purely-decisional entry in the
BCL register and the highest-leverage one: four XNA types take it as their CLR base and six XNA
members declare it as their type. Foundation 28 admitted a Microsoft mscorlib so the type could be
measured rather than recalled. This milestone reads that measurement and takes the decision.

## The decision

`System.Collections.ObjectModel.ReadOnlyCollection`1` → `CNA::Runtime::ReadOnlyCollection`, a
dedicated Ruby language-support class in the CNA runtime.

Not `Array`, not a frozen `Array`, not `Enumerable` alone, not `Set`, not an opaque `Object`. It is
a **BCL language projection**, not an XNA type: no method it declares is an XNA identity, and it
lives in the CNA runtime rather than a fabricated Ruby `::System` namespace, as `EventArgs` and
`Attribute` already do.

Ruby has class inheritance, so an XNA class whose actual CLR base is this generic **inherits from
the support class**. That preserves the CLR base relationship instead of flattening the inherited
surface into unrelated methods on each collection type.

## What the measurement settled, and what it ruled out

Every fact below is in `docs/generated/bcl-inventory.json`, derived from the admitted mscorlib.
`test/test_read_only_collection.rb` reads them back out of that file rather than restating them, so
a projection that drifts from the IL fails without the test being touched.

### It is a view, not a snapshot — which rules out the frozen copy

The CLR constructor takes an `IList<T>`, throws `ArgumentNullException` naming `list` when it is
null, and stores **the reference**. `storesConstructorArgumentToField` is true and no copy
instruction appears. Every one of the six public read members then loads that field and forwards a
single call to it:

| Ruby | CLR | Forwards to |
| --- | --- | --- |
| `Count` | `get_Count` | `ICollection`1::get_Count` |
| `[]` | `get_Item(Int32)` | `IList`1::get_Item` |
| `Contains` | `Contains(T)` | `ICollection`1::Contains` |
| `CopyTo` | `CopyTo(T[], Int32)` | `ICollection`1::CopyTo` |
| `GetEnumerator` | `GetEnumerator()` | `IEnumerable`1::GetEnumerator` |
| `IndexOf` | `IndexOf(T)` | `IList`1::IndexOf` |

So a mutation applied to the backing list **is observable through the wrapper**: `Count` grows when
the backing list grows, and `[]` answers the current element. The Ruby class therefore neither
`dup`s nor `freeze`s what it is given, and `test_backing_mutation_is_observable_through_the_wrapper`
holds it to that. A frozen copy would have been a different type with different behaviour, and it
was one of the two designs the frontier register listed as plausible.

### It validates nothing of its own — which is why the index rules come from elsewhere

Not one of those six members carries a throw. Bounds behaviour, element equality, ordering and the
whole of `CopyTo`'s argument checking belong to the backing list; the wrapper contributes exactly
zero conditions.

This binding's backing list is a Ruby `Array` read through the `IList<T>` contract, and this
binding already has a realized `IList<T>`: `CurveKeyCollection`, whose own `CopyTo` is a forward to
`List`1::CopyTo` exactly as this one is. The index rules are therefore the ones it already ships,
now written down in `mapping-rules.json` under `collections.indexErrors`:

- an index outside `0...Count` raises `IndexError` rather than answering `nil`;
- a negative index is out of range rather than counting from the end;
- a `CopyTo` whose destination cannot hold the source raises `ArgumentError`.

One CLR operation keeps one Ruby behaviour across the binding. Ruby's own `Array#[]` answers `nil`
out of range and wraps a negative index, and the test asserts the projection deliberately does
neither.

### Read-only is a property of the interface — which is why nothing throws

Twelve members refuse to mutate: `ICollection<T>.Add/Clear/Remove`,
`IList<T>.Insert/RemoveAt/set_Item` and the six non-generic `IList` counterparts. Every one is an
explicit interface implementation whose entire body is an unconditional throw of
`NotSupportedException` carrying the resource literal `NotSupported_ReadOnlyCollection`.

Ruby has no explicit interface implementation and this binding fabricates no `IList` module, so the
faithful projection of "the caller cannot mutate through this interface" is that **no mutating
member exists at all**. There is nothing to call and nothing to throw from. A caller holding the
backing Array can still mutate it, which is exactly the CLR's position.

This is why Foundation 29 does not need a `NotSupportedException` mapping. `TouchCollection` does,
because it declares those refusals on its own public surface; that is Foundation 31.

`Collection`1` was measured beside it and the contrast is the evidence: it is *also* a view over its
backing `IList<T>`, and it publishes `Add/Clear/Insert/Remove/RemoveAt/set_Item` — which throw
`NotSupportedException` only **conditionally**, when the backing list is itself read-only. The two
types differ in what they publish, not in how they hold their data.

## The public Ruby surface

CLR identities, in CLR spelling, under the rules `mapping-rules.json` already applies —
`Item[Int32]` maps to `[]` by the indexed-item rule, `IEnumerable<T>` to a Ruby `Enumerator` without
a fake `System` namespace:

```ruby
Count            # -> Integer
[](index)        # -> element, IndexError outside 0...Count
Contains(value)  # -> true/false
IndexOf(value)   # -> Integer, -1 when absent
CopyTo(array, array_index)  # -> nil
GetEnumerator    # -> a fresh Enumerator over the live backing list
Items            # protected, the CLR `family` accessor
```

Plus exactly one Ruby language-support identity of its own, `each`, and `Enumerable`.

### Why including `Enumerable` is not surface inflation

The prompt for this work asked that, if `Enumerable` is included, its identities be related to CLR
`GetEnumerator` rather than counted as dozens of new members. They relate exactly: **Ruby derives
every `Enumerable` method from `each` alone**, and `each` is the single Ruby identity that carries
CLR `GetEnumerator` — it answers that same `Enumerator` when called without a block. Including the
module therefore adds no independent behaviour to measure.

The two sets are separable by construction, and the test asserts the partition is exact:

- a CLR identity is PascalCase or an operator (`Count`, `Contains`, `[]`);
- language support is not (`each`, `map`, `select`).

They can never collide, and `CLR_SURFACE` / `CLR_PROTECTED_SURFACE` / `LANGUAGE_SUPPORT` are
declared on the class so the distinction is machine-readable rather than a convention.

### Enumeration

`GetEnumerator` walks the backing list by index, so it sees live contents rather than a snapshot,
and a fresh call answers a fresh Enumerator. It fails fast with `RuntimeError` when the backing list
changes length during enumeration, which is the analogue `CurveKeyCollection` already uses for
`InvalidOperationException`.

That is deliberately **narrower** than `List<T>`'s version counter, which also trips on replacing an
element in place. A Ruby `Array` carries no version, and this wrapper does not own the list — the
whole point of the type is that someone else does. Recorded as a limitation, not hidden.

## The generic element projection

A Ruby class is not statically generic, so the CLR type argument cannot live in the superclass
expression. It is carried as class metadata instead:

```ruby
class ModelBoneCollection < CNA::Runtime::ReadOnlyCollection
  projects_elements "Microsoft.Xna.Framework.Graphics.ModelBone"
end
```

`verify_bcl_generic_base` measures that metadata against the reference contract's declared base and
reports `GENERIC_MAPPING_MISMATCH` when it is absent or wrong. There is no allowlist. Five mutations
are covered by test:

| Mutation | Caught as |
| --- | --- |
| Ruby base is an `Array` subclass | `BASE_MAPPING_MISMATCH` |
| Ruby base is a bare `Object` subclass | `BASE_MAPPING_MISMATCH` |
| correct Ruby base, no element metadata | `GENERIC_MAPPING_MISMATCH` |
| correct Ruby base, wrong element identity | `GENERIC_MAPPING_MISMATCH` |
| a fabricated `::System::…` constant | does not resolve at all |

One register entry answers for every constructed form: `BclProjection.definition` reduces
`ReadOnlyCollection`1[X]` to `ReadOnlyCollection`1`, and `element_types` splits the arguments at the
top level so a nested constructed argument stays whole.

## What moved on the frontier — and what did not

The previous session recorded that this projection "may unblock four types". **It unblocks none**,
and separating that out is part of the milestone. Each of the four carries another blocker:

| Type | Before | After |
| --- | --- | --- |
| `Graphics.GraphicsAdapter` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | **`NATIVE_RUNTIME`** |
| `Media.VisualizationData` | `BCL_PROJECTION` + `RUNTIME_DATA` | **`RUNTIME_DATA`** |
| `Audio.Microphone` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | unchanged; `System.Byte[]` remains |
| `Graphics.SpriteFont` | `BCL_PROJECTION` + `NATIVE_RUNTIME` | unchanged; `System.Char`, `Nullable`1[System.Char]`, `StringBuilder` remain |

The four XNA types that take it as their CLR base — `ModelBoneCollection`, `ModelEffectCollection`,
`ModelMeshCollection`, `ModelMeshPartCollection` — are not on the frontier at all, because
`ModelBone`, `Effect`, `ModelMesh` and `ModelMeshPart` are themselves missing. So no Ruby class
inherits from the support class yet, and the inheritance rule is proved by verifier fixtures rather
than by a shipped type.

`GraphicsAdapter` reaching a **single** blocker is the concrete gain. Its remaining obstacles are
the ones the audit recorded and this managed sequence does not touch.

### One analyzer correction rode along

`Media.VisualizationData` and `SpriteFont` declare `ReadOnlyCollection`1[System.Single]` and
`ReadOnlyCollection`1[System.Char]`. The frontier reduced a signature to the identities it really
names — the outer definition, plus the whole signature when it names no XNA type — so both of those
were also reported whole, as opaque unmapped identities, even after the definition was projected.

That is the Foundation 26 blind spot seen from the other side: there a constructed generic hid its
*definition* behind an XNA type argument; here it hid its *already-projected* definition behind a
BCL one. Once the register projects a generic definition, a constructed form of it requires the
definition's projection plus its type arguments', and the analyzer now reduces it that way. A
generic the register does **not** project stays opaque, because then the whole constructed form
really is what is missing.

The effect is exact rather than blanket: `System.Single` is mapped, so
`ReadOnlyCollection`1[System.Single]` is fully mapped and `VisualizationData` loses its BCL blocker;
`System.Char` is not, so `SpriteFont` now reports the *argument* rather than the constructed string,
which is a truer statement of what it needs.

## What this milestone does not do

- **No XNA type becomes complete.** Strict stays 135 types / 1714 members, 129 complete, 306
  diagnostics, and consumable candidates stay 0.
- **No CNA source change and no new native symbol.** The ABI stays 39 / 124 / 290 / 290 / 2 / 59.
- **`Collection`1` and `Dictionary`2` stay unprojected.** Both are measured in the BCL inventory;
  neither has a decided Ruby design, and both remain under `bclProjection.notYetDesigned`.
- **`GraphicsAdapter` is not implemented.** Its remaining blocker is native and unchanged.

## Numbers

| Metric | Before | After |
| --- | --- | --- |
| `BCL_PROJECTED_IDENTITIES` | 5 | **6** |
| `TARGET_TYPES` / `TARGET_MEMBERS` | 135 / 1714 | 135 / 1714 |
| `COMPLETE_TYPES` | 129 | 129 |
| `TOTAL_DIAGNOSTICS` | 306 | 306 |
| `GENERIC_MAPPING_MISMATCH` | 0 | 0 |
| Frontier: dependency-complete | 20 | 20 |
| Frontier: consumable | 0 | 0 |
| Frontier: `BCL_PROJECTION` blockers | 14 | **12** |
| Capability registry | 85 rows, 0 contradictions | 85 rows, 0 contradictions |
