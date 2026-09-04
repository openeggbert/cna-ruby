# Foundation 28 — the BCL reference authority

> **This is a historical milestone record and its numbers are Foundation 28's.** The machinery it
> describes was generalised at Foundation 105, which admitted a **second** authority —
> `System.dll` — for the thirteen XNA `Design` converters. Every gate below still holds and is now
> a property of a registry rather than of mscorlib: read
> `tools/api_compat/reference/BCL_PROVENANCE.md` for both pinned identities and
> `docs/design-converter-evidence.md` for what the second one was admitted to do. The one gate that
> **changed** is the pairing: it is no longer "all ten XNA assemblies", because only six reference
> `System`, so the referrer set is asserted per authority.

Foundation 21 opened `CNA::Runtime::BclProjection` with a rule that has held ever since: only a CLR
identity the selected XNA surface actually names, and whose Ruby projection can be decided *without
guessing*, may be admitted. Three identities passed it — `System.EventArgs`, `System.TimeSpan`,
`System.Attribute` — and one thing they share is easy to miss. Each has an empty or scalar surface.
`System.EventArgs` declares nothing this binding consumes; `System.TimeSpan` is a tick count;
`System.Attribute` is a marker whose members none of the five XNA attribute types inherits. For all
three, "measured" and "obvious" happened to coincide, so no measurement was needed and none was
done.

`ReadOnlyCollection<T>` is the first BCL identity with a real member surface and real behaviour, and
it is the highest-leverage one left: `GraphicsAdapter`, `SpriteFont`, `Microphone` and
`Media.VisualizationData` all name it, and four more XNA types take it as their CLR base. The
frontier register named the obstacle precisely — *"the pinned inventory admits the ten XNA
assemblies and no mscorlib, so unlike every BCL identity projected so far this one has no measured
member surface at all"*. This milestone removes that obstacle, and only that. It projects nothing.

## What was admitted

| Field | Value |
| --- | --- |
| Assembly name | `mscorlib` |
| Assembly version | `4.0.0.0` |
| File version | `4.0.30319.1 (RTMRel.030319-0100)` |
| Public key token | `b77a5c561934e089` (**derived**) |
| Bytes | 5196112 |
| SHA-256 | `5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63` |
| CompanyName | `Microsoft Corporation` |
| FileDescription | `Microsoft Common Language Runtime Class Library` |

This is the 32-bit desktop .NET Framework 4.0 RTM class library. It is deliberately not the .NET
Compact Framework `mscorlib.dll` that XNA Game Studio 4.0 ships under
`References/Xbox360/` — that assembly is Microsoft's and is 396288 bytes, but it is the Xbox 360
CLR, not the Windows CLR the pinned Windows assemblies run on. It is also not Mono's
`4.0-api/mscorlib.dll`, not `System.Private.CoreLib`, and not a NuGet reference assembly. The
project's authority order rules all three out as behavioural authority.

### The identity is derived, not asserted

The public key token is the interesting case. The obvious move is to write `b77a5c561934e089` into
the tool as the expected value and call a match a proof, which proves only that the constant equals
itself. Instead `tools/api_compat/build_bcl_inventory.rb` reads the `.publickey` blob out of the
assembly's own `.assembly mscorlib` manifest and applies the CLR's own rule — SHA-1 of the key, low
eight bytes, reversed. mscorlib carries the ECMA standard key
`00000000000000000400000000000000`, and it is that blob which hashes to this token. The tool aborts
if the derivation disagrees with the pin, and `test/test_bcl_inventory.rb` recomputes it
independently from the ECMA key rather than reading it back out of the report.

Four further admissions gates, all read out of the bytes: SHA-256 and byte length; the manifest's
`.ver 4:0:0:0`; the PE version resource's `CompanyName`, `FileDescription` and `FileVersion`.

### The pairing is proved, not assumed

An mscorlib with the right identity is still only *an* mscorlib. What makes this one the right
authority is that the pinned XNA assemblies bind to it. All ten declare an `AssemblyRef` to
`mscorlib`, and the tool requires every one of those references to name exactly the version and
public key token the admitted binary derives:

```
.assembly extern mscorlib
{
  .publickeytoken = (B7 7A 5C 56 19 34 E0 89 )
  .ver 4:0:0:0
}
```

Ten of ten agree. That is the whole of the pairing claim, and it is checked on every run.

## It is a separate authority

mscorlib is not an XNA assembly and none of its types is an XNA identity. Admitting it moves no XNA
metric, and the test asserts each of these rather than trusting the intent:

| Metric | Before | After |
| --- | --- | --- |
| `REFERENCE_TYPES` | 257 | **257** |
| `REFERENCE_MEMBERS` | 2964 | **2964** |
| `TYPES_WITH_IL` | 257 | **257** |
| `TYPES_WITHOUT_IL` | 0 | **0** |
| XNA IL inventory assemblies | 10 | **10** |
| Strict `TOTAL_DIAGNOSTICS` | 306 | **306** |
| Projected BCL identities | 5 | **5** |

The BCL inventory reports its own, separate metrics:

| Metric | Value |
| --- | --- |
| `BCL_FAMILIES` | 3 |
| `BCL_TYPES` | 17 |
| `BCL_MEMBERS` | 246 |
| `BCL_EXCEPTION_TYPES` | 9 |
| XNA pairing assemblies | 10 |

## The inventory is demand-driven

Ingesting mscorlib wholesale would be a reimplementation of the .NET Framework. The tool admits a
family only when the XNA reference contract really names it, derives the consumer list from that
contract rather than from a hand-written note, and aborts on a family with zero consumers.

| Family | XNA consumers | Why |
| --- | --- | --- |
| `System.Collections.ObjectModel.ReadOnlyCollection`1` | 10 | four CLR bases and six declared member types |
| `System.Collections.ObjectModel.Collection`1` | 1 | the CLR base of `GameComponentCollection`; also the mutable sibling the read-only one is measured against |
| `System.Collections.Generic.Dictionary`2` | 1 | the CLR base of `LaunchParameters`, the one dependency-complete XNA type blocked on it alone |

The ten `ReadOnlyCollection<T>` consumers, derived:

- bases — `Graphics.ModelBoneCollection`, `Graphics.ModelEffectCollection`,
  `Graphics.ModelMeshCollection`, `Graphics.ModelMeshPartCollection`
- members — `Audio.AudioEngine.RendererDetails`, `Audio.Microphone.All`,
  `Graphics.GraphicsAdapter.Adapters`, `Graphics.SpriteFont.Characters`,
  `Media.VisualizationData.Frequencies`, `Media.VisualizationData.Samples`

From those three families the tool then walks the **exception closure**: every exception identity
their recorded surface actually throws, and each one's base chain up to `System.Exception`, which is
where `BclProjection::EXCEPTION_BASES` already roots. Nine exception types, none of them chosen by
hand:

`System.Exception`, `System.SystemException`, `System.ArgumentException`,
`System.ArgumentNullException`, `System.ArgumentOutOfRangeException`,
`System.InvalidOperationException`, `System.NotSupportedException`,
`System.Collections.Generic.KeyNotFoundException`,
`System.Runtime.Serialization.SerializationException`.

## What the IL settles about `ReadOnlyCollection<T>`

This is the evidence Foundation 29 consumes, recorded here so the projection is a reading rather
than a recollection.

**It is a view, not a snapshot.** The constructor takes an `IList<T>`, throws
`ArgumentNullException` (argument `list`) when it is null, and stores the reference. Every one of
the six public read members then loads that field and forwards a single call to it:

| Member | Forwards to |
| --- | --- |
| `get_Count` | `ICollection`1::get_Count` |
| `get_Item` | `IList`1::get_Item` |
| `Contains` | `ICollection`1::Contains` |
| `CopyTo` | `ICollection`1::CopyTo` |
| `GetEnumerator` | `IEnumerable`1::GetEnumerator` |
| `IndexOf` | `IList`1::IndexOf` |

No copy is taken anywhere, at construction or afterwards. A mutation applied to the backing list is
observable through the wrapper. **Implementing the Ruby projection as a frozen copy would be a
different type.**

**It validates nothing of its own.** Not one of those six members carries a throw. Bounds behaviour,
element equality, ordering, enumeration and the whole of `CopyTo`'s argument checking belong to the
backing list; the wrapper contributes exactly zero conditions.

**"Read-only" is a property of the interface, not of the data.** Twelve members refuse to mutate,
and every one of them is an explicit interface implementation whose entire body is a throw:
`ICollection<T>.Add/Clear/Remove`, `IList<T>.Insert/RemoveAt/set_Item`, and the six non-generic
`IList` counterparts. Each throws `NotSupportedException` unconditionally — no branch instruction
anywhere in the body — through `ThrowHelper::ThrowNotSupportedException` with the
`System.ExceptionResource` literal `NotSupported_ReadOnlyCollection`. A caller holding the wrapper
cannot mutate; a caller holding the backing list can.

**The public surface is small.** Public: `.ctor(IList<T>)`, `Count`, `Item[Int32]`, `Contains`,
`CopyTo`, `GetEnumerator`, `IndexOf`. Protected: `Items`. Everything else is explicit interface
implementation.

`Collection<T>` was measured alongside it because the contrast is itself evidence. It is *also* a
view over a backing `IList<T>` — field `items`, same forwarding shape — and it publishes
`Add/Clear/Insert/Remove/RemoveAt/set_Item` as ordinary public members. Those throw
`NotSupportedException` too, but **conditionally**: only when the backing list is itself read-only.
The two types differ in what they publish, not in how they hold their data. Its four protected
hooks — `ClearItems`, `InsertItem`, `RemoveItem`, `SetItem` — forward to the backing list as well.

## What is recorded, and what is not

Identities, shapes and derived behavioural facts. Never IL text, never Microsoft-owned bytes, never
a machine-local path, and the gem packages nothing Microsoft-owned — `git ls-files` carries no
`.dll`, `.exe`, `.pdb` or `.winmd`, which the test asserts.

A derived fact is one of `delegatesTo`/`viaField`, `throws` (with the resolved exception identity
and the `ExceptionResource`/`ExceptionArgument` literal names), `throwsUnconditionally`, or
`storesConstructorArgumentToField`.

Resolving `throws` needed two things worth naming:

1. **`ThrowHelper` resolution is derived.** The map from helper method to exception identity is
   built by reading which exception each helper actually constructs, transitively through guard
   helpers such as `IfNullAndNullsAreIllegalThenThrow<T>` that construct nothing themselves. No
   exception is ever inferred from a helper's name.
2. **Wrapped operands are folded back.** `ikdasm` wraps a two-argument helper signature onto a
   second line. Reading only the first line loses the `ExceptionResource` half and mislabels the
   `ExceptionArgument`: `ReadOnlyCollection<T>`'s `ICollection.CopyTo` came out as argument `info`
   with no resource, where the IL says argument `arrayIndex`, resource
   `ArgumentOutOfRange_NeedNonNegNum`. Both readings are pinned by test.

The extractor is nested- and generic-aware for the same reason the XNA one had to become so in
Native frontier 2, and `Dictionary`2` proves both halves at once: a generic definition `ikdasm`
declares as ``Dictionary`2<TKey,TValue>`` and closes as ``Dictionary`2``, carrying nested types two
levels deep (`Dictionary`2+KeyCollection+Enumerator`). All five are addressed the way the reference
contract spells a nested type, `Parent+Child`, never `Parent/Child`.

## What this milestone does not do

- **No BCL type is projected.** `BclProjection::TYPES` is unchanged at three entries and
  `EXCEPTION_BASES` at two; `BCL_PROJECTED_IDENTITIES` stays 5.
  `ReadOnlyCollection`1`, `Collection`1` and `Dictionary`2` remain under
  `mapping-rules.json`'s `bclProjection.notYetDesigned`.
- **No XNA type becomes complete**, and the frontier is unchanged.
- **`Dictionary`2` is inventoried, not decided.** Whether `LaunchParameters` derives from a Ruby
  `Hash` or from a runtime support class is a public API decision this milestone does not take.
- **Nothing about CNA, the native ABI or GraphicsAdapter changes.** The ABI stays
  39 / 124 / 290 / 290 / 2 / 59.

## Reproducing

```sh
BCL_REFERENCE_ASSEMBLIES=<directory holding mscorlib.dll> \
XNA_REFERENCE_ASSEMBLIES=<directory holding the pinned XNA assemblies> \
  ruby tools/api_compat/build_bcl_inventory.rb
```

The output is deterministic: two consecutive runs produce byte-identical
`docs/generated/bcl-inventory.json`.
