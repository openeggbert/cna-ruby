# Foundation 46 — `Dictionary<K,V>` and `LaunchParameters`

Derived from the admitted Microsoft .NET Framework 4.0 `mscorlib`, SHA-256
`5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63`, and the pinned
`Microsoft.Xna.Framework.Game.dll`, SHA-256
`b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0`, both disassembled with `ikdasm`.

`Dictionary`2` was the last purely-decisional BCL blocker — recorded as undecided rather than
deferred, on the grounds that two materially different Ruby designs were plausible and no repository
rule chose between them. Two rules do choose, and both were already shipped:
`ReadOnlyCollection<T>` in Foundation 29 and `Collection<T>` in Foundation 34. This is the third
member of that family, measured the same way.

## How much of the CLR type a projection actually owes

The pinned `Dictionary`2` declares fifty-odd methods. The accessibility census is what settles the
scope, and it removes most of them:

| declaration | count | projects to |
| --- | --- | --- |
| `public … rtspecialname` | 6 | the public constructors |
| `family … rtspecialname` | 1 | nothing — `.ctor(SerializationInfo, StreamingContext)` is protected |
| `private … newslot virtual final` | 22 | **nothing** — explicit interface implementations |
| ordinary public | 15 | the projected surface |

An explicit interface implementation projects to no Ruby member at all; that is the rule
`ReadOnlyCollection`'s twelve and `Collection`'s fourteen already follow, and here it accounts for
twenty-two members — including every member of `IDictionary`, `ICollection` and `IEnumerable` in both
their generic and non-generic forms. What is left is one ordinary public surface:

```
Comparer  Count  Keys  Values  Item[]  Item[]=
Add  Clear  ContainsKey  ContainsValue  GetEnumerator  Remove  TryGetValue
GetObjectData  OnDeserialization
```

plus the nested `KeyCollection` and `ValueCollection`, whose whole public surface is four members
each — `.ctor(Dictionary<K,V>)`, `get_Count`, `CopyTo(T[], int32)` and `GetEnumerator()` — every
other member each declares being an explicit interface implementation, including all the mutating
ones.

**This is why the serialization question the handoff flagged is smaller than it looks.** The
protected `SerializationInfo` constructor is not a public identity at all. `GetObjectData` and
`OnDeserialization` are, and they are carried — but neither needs a formatter runtime to be faithful
at this boundary. The contract they implement is "hand your state to this carrier" and "take it
back", and the carrier is a plain named-value bag: `AddValue(name, value)` / `GetValue(name)`. So the
projection is the smallest exact one and no formatter, surrogate selector, binder or stream format is
invented. `System.Runtime.Serialization.SerializationInfo` deliberately stays **out** of the BCL
register, because the pinned reference never names it in a public signature — a test asserts that.

## A Ruby Hash is the private store and nothing else

A `Hash` is a hash map with insertion-ordered traversal and `KeyError` on a missing key; the CLR type
is a hash map with bucket-ordered traversal and `KeyNotFoundException`. Close enough that using one
as the *store* is right and using one as the *projection* would be wrong on three counts a consumer
would hit immediately:

- `Hash#[]` answers `nil` for a missing key; `get_Item` calls `FindEntry` and
  `ThrowHelper::ThrowKeyNotFoundException()` when it answers a negative index.
- `Hash#store` overwrites; `Add` is `Insert(key, value, add: true)`, and finding the key present
  throws `ArgumentException`. `set_Item` is the same `Insert` with `add: false`, which replaces.
- `Hash#each` never fails fast; the CLR enumerator compares `version` on every `MoveNext`.

So every public member is written from the IL and the Hash is reached only through them.

Behaviours measured rather than assumed:

- `Insert` opens with `ThrowHelper::ThrowArgumentNullException(ExceptionArgument.key)` before
  anything else, so **every keyed member refuses a null key** — even for a reference-typed `TKey`.
- `ContainsValue` has a **separate null branch** that answers true for the first null value without
  consulting any comparer; otherwise it compares with `EqualityComparer<TValue>.Default`, never with
  the key comparer.
- `Remove` answers `false` for an absent key **without touching `version`**, and increments it when
  an entry really goes.
- `Clear` returns at its first branch — `ldfld count; ldc.i4.0; ble.s` straight to `ret` — so
  **clearing an empty dictionary does not increment `version`** and does not invalidate an
  enumeration in flight.
- `KeyCollection`/`ValueCollection` store one reference and forward: they are **views**, so an `Add`
  after the view was taken is visible through it, and both fail fast on the dictionary's own counter
  because the nested enumerators read the same field.

The one thing not reproduced is bucket traversal order. The CLR order is an artefact of bucket layout
and of the free list `Remove` feeds, so a re-inserted key can reappear in a slot it did not occupy
before. That layout is not public behaviour — it is documented as unspecified, and the canonical C
ABI's own launch-parameter enumeration sorts by name rather than trusting it. Ruby's insertion order
is kept and no hash layout is fabricated. What *is* public is preserved exactly: key equality,
duplicate recognition, lookup, removal, `Count`, and version invalidation.

## `IEqualityComparer<T>`, at its narrowest

`get_Comparer` is one `ldfld`, and `Insert`/`FindEntry` reach the stored comparer for both
`GetHashCode` and `Equals`. A dictionary built by the parameterless constructor stores
`EqualityComparer<TKey>.Default`, whose `Equals` is the key's own — and Ruby's Hash keys already
compare with `eql?` and hash with `hash`, which is the same pairing. So **the default comparer
projects to `nil`**, the absence of a custom comparer, rather than to an invented object claiming a
CLR identity nothing here needs.

A supplied comparer is a duck-typed object answering `Equals(a, b)` and `GetHashCode(x)`. That is
`IEqualityComparer<T>`'s entire contract, so it is the narrowest reusable projection the interface
admits, and no implementation-private CLR comparer class is exposed. A comparer really decides
equality, hashing, duplicate recognition, lookup and removal — tested with a case-insensitive one.

`KeyNotFoundException` joins the measured thrown-exception register as Ruby's own `KeyError`: it is
precisely "the key was not found in this keyed collection", it descends from `IndexError` and so from
`StandardError`, and it is what `Hash#fetch` already raises. `IndexError` itself would lose the
distinction the CLR draws between a missing index and a missing key, which `IndexOutOfRangeException`
already occupies in that register.

## `LaunchParameters`

`.class public auto ansi beforefieldinit`, extending `Dictionary`2<string,string>`, declaring in the
selected contract **exactly one member**: the public parameterless constructor. `directInterfaces` is
empty and all ten interfaces are inherited, so the whole public surface arrives by inheritance —
which Ruby class inheritance carries directly, and which the verifier measures as
`BASE_MAPPING_MISMATCH` 0, `INTERFACE_MAPPING_MISMATCH` 0 and `GENERIC_MAPPING_MISMATCH` 0 with
`clr_element_types` recording `String, String`.

The other two methods it declares are not identities — `ParseCommandLineArguments(string[])` is
`assembly` and `ParseKeyValuePair(string, out string, out string)` is `private` — so only their
effect is observable:

```csharp
char[] trim = { '/', '-' };
if (args.Length <= 1) return;                     // element 0 is the executable path
for (int i = 1; i < args.Length; i++) {
    string argument = args[i].TrimStart(trim);
    key = argument; value = String.Empty;
    int colon = argument.IndexOf(':');            // the FIRST colon only
    if (colon != -1) { key = argument.Substring(0, colon);
                       value = argument.Substring(colon + 1); }
    if (!ContainsKey(key) && key != String.Empty) Add(key, value);
}
```

Three details a summary would get wrong, all of them tested: an argument with **no colon is kept**,
with the empty string as its value, rather than skipped; the **first** occurrence of a name wins,
because the guard is `ContainsKey` and the write is `Add`, which would otherwise throw; and the split
is on a colon, never an equals sign, and only on the first one, so `x:a:b` is `{"x" => "a:b"}`.

`Environment.GetCommandLineArgs()` projects to Ruby's `ARGV`. XNA skips element 0, the executable
path; `ARGV` already excludes it, so the default source is exact rather than approximate.

## The audit that changed the design

An earlier handoff recorded that "`LaunchParameters` has a canonical CNA route for every operation
and is blocked only on the type". The routes exist —
`cna_game_launch_parameters_{get_count, contains_key, get_value_size, copy_value, get_key_size,
copy_key, add, parse_ext}` — but reading them would have been a category error, and the C ABI's own
documentation says why. Three differences are load-bearing because the inherited dictionary surface
makes all three observable:

1. **Parsing.** `cna_game_launch_parameters_parse_ext` documents that "an argument shorter than three
   characters or without a colon is skipped silently". XNA keeps a colonless argument with an empty
   value and has no minimum-length rule, so `-windowed` is `{"windowed" => ""}` in XNA and **nothing**
   in CNA.
2. **Add.** `cna_game_launch_parameters_add` "overwrites an existing entry rather than refusing".
   `Dictionary.Add` throws on a duplicate. That route is `set_Item`, not `Add` — two different XNA
   members.
3. **Order.** `cna_game_launch_parameters_get_key_size` indexes "by name, ordinal byte order,
   ascending — deliberately not the canonical container's own order".

And the decisive fact: **XNA's `Game.LaunchParameters` reads nothing native.**
`Game.get_LaunchParameters` is one `ldfld`, the field is written in exactly one place —
`Game..ctor`, `newobj LaunchParameters::.ctor()` — and nothing in the assembly ever reads it again.
It is consumer-facing data the loop never consults, which is a stronger case for managed state than
the four timing properties Foundation 42 kept managed, because those the loop *does* read.

This is deliberately **not** the two-container conflict the `GraphicsDeviceManager` producer audit
deferred. That conflict was a doubly-executed lifecycle *step*: registering the service made
`LoadContent` run twice, and no guard could hide it. There is no step here at all — neither runtime
reads the other's map, and nothing in either is executed twice. So the managed projection is
projectable, and the routes stay unbound with the reason recorded; a test asserts no
`launch_parameters` symbol is bound.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_TYPES` | 142 | 143 |
| `TARGET_MEMBERS` | 1788 | 1790 |
| `COMPLETE_TYPES` | 136 | **137** |
| `MISSING_TYPES` | 115 | 114 |
| `TOTAL_DIAGNOSTICS` | 276 | 274 |
| `MISSING_MEMBER` | 115 | 114 |
| `BCL_PROJECTED_IDENTITIES` | 10 | 11 |
| `BCL_THROWN_EXCEPTIONS` | 6 | 7 |
| dependency-complete candidates | 19 | 18 |
| `blockerSummary` `BCL_PROJECTION` | 5 | 4 |
| `Game` remainder | 6 | 5 |
| behaviour observations | 498 | 506 |

`PARTIAL_TYPES` 6, allowlist 0, `OVERLOAD_MAPPING_MISMATCH` 45 and every other structural category
are unchanged; no native binding was added, so the ABI is untouched at 55 / 169 / 290 / 290 / 3 / 63.
`Game` stays partial: `Content`, `Dispose(Boolean)`, `Finalize`, `ShowMissingRequirementMessage` and
`Window` remain.

## What this does not claim

A projected `Dictionary` is a language projection, not a collections framework: no `List<T>`,
`HashSet<T>`, `SortedDictionary<K,V>`, `KeyValuePair<K,V>` type, `IEqualityComparer<T>` module or
`EqualityComparer<T>.Default` object is added. Nothing in this binding serialises anything, and
`GetObjectData`/`OnDeserialization` imply no formatter, no `StreamingContext` projection and no
stream format. `LaunchParameters` reads the process argument list and nothing else: it implies no
`GameWindow`, no `ContentManager`, no storage, and no CNA launch-parameter route.
