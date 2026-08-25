# Foundation 34 — `Collection<T>` as a BCL base projection

`System.Collections.ObjectModel.Collection`1` → `CNA::Runtime::Collection`.

The ninth entry in the measured BCL projection register, and the first one with **mutation** on its
public surface. Foundation 29 projected the read-only sibling and measured this class beside it
without projecting it, because nothing consumed it: the four XNA types that take
`ReadOnlyCollection<T>` as a base are all missing, and the one type that takes *this* class as a
base — `Microsoft.Xna.Framework.GameComponentCollection` — was not on the frontier either.

That is what changed. Nothing about the measurement changed; only the demand did.

## Authority

The admitted Microsoft .NET Framework 4.0 mscorlib, SHA-256
`5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63`, pinned by
`tools/api_compat/reference/BCL_PROVENANCE.md` and located by hash. The measured surface is already
in `docs/generated/bcl-inventory.json` — Foundation 28's inventory admitted the family on the
strength of `GameComponentCollection` naming it, so **this milestone re-derives nothing and adds no
new authority**. Every behavioural claim below is a statement about IL in that inventory, and the
tests read the inventory rather than restating it.

## The measured surface

Thirty-six entries: two public constructors, twelve public methods, five `family` methods, fourteen
explicit interface implementations, and three property records for `Count`, `Items` and `Item`.

| CLR member | Access | What its IL does |
| --- | --- | --- |
| `.ctor()` | public | `items = new List<T>()` |
| `.ctor(IList<T> list)` | public | `ThrowArgumentNullException(list)` when null, then one `stfld` of the argument |
| `get_Count` | public | `items.Count` |
| `get_Items` | family | `ldfld items` |
| `get_Item(int32)` | public | `items[index]` |
| `set_Item(int32, T)` | public | read-only refusal, `index < 0 \|\| index >= Count`, `SetItem` |
| `Add(T)` | public | read-only refusal, `InsertItem(Count, item)` |
| `Clear()` | public | read-only refusal, `ClearItems()` |
| `CopyTo(T[], int32)` | public | `items.CopyTo` |
| `Contains(T)` | public | `items.Contains` |
| `GetEnumerator()` | public | `items.GetEnumerator` |
| `IndexOf(T)` | public | `items.IndexOf` |
| `Insert(int32, T)` | public | read-only refusal, `index < 0 \|\| index > Count`, `InsertItem` |
| `Remove(T)` | public | read-only refusal, `IndexOf`; `false` when negative, else `RemoveItem` and `true` |
| `RemoveAt(int32)` | public | read-only refusal, `index < 0 \|\| index >= Count`, `RemoveItem` |
| `ClearItems()` | family | `items.Clear()` |
| `InsertItem(int32, T)` | family | `items.Insert(index, item)` |
| `RemoveItem(int32)` | family | `items.RemoveAt(index)` |
| `SetItem(int32, T)` | family | `items[index] = item` |

## Three facts the measurement settles

**1. It is a view that publishes mutation.** The two classes are one shape with opposite intent.
Both store a single `IList<T>` field, both forward every read to it, neither copies anything. A
collection built through the `IList<T>` constructor is a live view over a list the caller still
owns, so this projection must not `dup` or `freeze` what it is given — the same reason
`ReadOnlyCollection` must not, reached from the other direction.

**2. Every mutation runs through a hook.** Not one of the six mutating members touches the backing
list. Each validates and then calls one of four `protected virtual` hooks. That indirection *is* the
type — it is the entire reason `Collection<T>` exists rather than `List<T>` — so the projection
declares no Ruby-idiomatic mutation beside the CLR surface. No `<<`, no `push`, no `delete`, no
`concat`. Any of those would be a second way to mutate that a subclass's hook never sees, which is
exactly the failure the class was designed to prevent.

**3. Read-only is a property of the backing list, not of this class.** All six mutating members open
with `items.IsReadOnly` and throw `NotSupportedException` (resource
`NotSupported_ReadOnlyCollection`) when it holds. `List<T>` is never read-only, so in the CLR this
fires only for a collection constructed over a list that refuses mutation. The Ruby analogue of such
a list is a frozen `Array`, and `Array#frozen?` is what the projection reads. This is the mirror of
`ReadOnlyCollection`'s twelve unconditional throws: there the refusal is unconditional and belongs to
the interface, here it is conditional and belongs to the data.

## `whoConstructsItDecides`, visible on both sides of one type

Foundation 31 established the rule and Foundation 29 applied it across two types. `Collection<T>` is
the first type where both halves are observable at once, on the same out-of-range condition:

| Member | Who builds the exception | Ruby |
| --- | --- | --- |
| `Item[index]` (get) | `List<T>`, because `Collection<T>` merely forwards | `IndexError` |
| `Item[index] = value` | `Collection<T>`'s own body, `ThrowArgumentOutOfRangeException()` | `RangeError`, `"index"` |
| `Insert(index, item)` | `Collection<T>`'s own body, `ThrowArgumentOutOfRangeException(index, ArgumentOutOfRange_ListInsert)` | `RangeError`, `"index"` |
| `RemoveAt(index)` | `Collection<T>`'s own body, `ThrowArgumentOutOfRangeException()` | `RangeError`, `"index"` |

The no-argument `ThrowHelper::ThrowArgumentOutOfRangeException()` overload was read rather than
assumed: its body is `GetArgumentName(ExceptionArgument.index)` — enum value 13 — so all three
writers name the same parameter and the Ruby message is `"index"` in all three cases, as everywhere
else in this binding.

## Two orderings that are observable

**The refusal comes before the range check.** `set_Item`, `Insert` and `RemoveAt` each read
`items.IsReadOnly` at IL offset 0 and bound-check only after the branch. So an out-of-range index on
a frozen backing list raises `NotSupportedError`, not `RangeError`. Getting this backwards would be
invisible in every other case and wrong in this one.

**`Add` reads `Count` once, before the hook.** `Add`'s IL stores `items.Count` into a local and
passes the local to `InsertItem`. A subclass hook that changes the length before calling its base
therefore inserts at the index `Add` computed, not at the length the list has by then.

## The enumerator

`GetEnumerator` forwards to `List<T>.Enumerator`, which fails fast on the backing list's `_version`
counter — so replacing an element in place trips it, not only adding or removing one. That is
*stricter* than `ReadOnlyCollection`'s projection, which checks length alone because it does not own
its list well enough to add a counter.

This class does own every mutation that reaches it through a hook, so it keeps its own counter,
bumped beside each of the four mutations exactly where `List<T>` writes `_version++`. The residual
gap is a caller mutating an `Array` it handed to the `IList<T>` constructor and still owns; a length
change there is caught too, and a same-length element swap through the caller's own reference is the
one case that escapes. That is a property of a Ruby `Array` carrying no version, not of this
projection, and it is the same documented limitation `ReadOnlyCollection` records.

## Explicit interface implementations project to nothing

Fourteen of the thirty-six measured entries are explicit implementations of `ICollection<T>`,
`IList`, `ICollection` and `IEnumerable` — `IsReadOnly` twice, `IsSynchronized`, `SyncRoot`,
`IsFixedSize`, the non-generic `GetEnumerator` and `CopyTo`, the `object`-typed
`Add`/`Contains`/`IndexOf`/`Insert`/`Remove` and both halves of the `object`-typed indexer. Ruby has
no explicit interface implementation and this binding fabricates no `IList` module, so they project
to no member at all — exactly the rule Foundation 29 established for `ReadOnlyCollection`'s twelve,
applied to a larger set. Each one either restates an operation the public CLR surface already
carries, under an interface-qualified name, or is an interface-only flag that exists nowhere on the
projection.

`_syncRoot` is a `notserialized` private field with no public reader, and nothing in this binding
reads it.

## What this milestone does not do

It completes **no XNA type**. `GameComponentCollection` is the next milestone; nothing in the
selection changes here. The frontier gains a mapped BCL identity and loses no blocker on its own,
which is the same shape Foundation 29 reported and the reason that milestone separated the two
claims.

No `::System` namespace is created, no CNA symbol is added and no CNA source is changed.
