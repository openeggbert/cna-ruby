# Foundation 105 — the `Design` converters, and the second BCL authority

The thirteen `Microsoft.Xna.Framework.Design` converters were classified `BCL_PROJECTION_SCOPE` for
four milestones. **That was a scope decision, not a blocker**, and its own evidence said so: the
authority was on this machine, the reach was measurable, and what was actually deferred was the
work of projecting a descriptor system. This milestone does that work, and installs a gate so a
family the project has selected cannot carry the classification again.

| Metric | Before | After |
| --- | ---: | ---: |
| `TARGET_TYPES` | 241 | **254** |
| `COMPLETE_TYPES` | 239 | **252** |
| `PARTIAL_TYPES` | 2 | 2 |
| `MISSING_TYPES` | 16 | **3** |
| `TOTAL_DIAGNOSTICS` | 29 | **16** |
| `BCL_PROJECTED_IDENTITIES` | 29 | **50** |
| `BCL_AUTHORITIES` | 1 | **2** |
| `BCL_FAMILIES` | 11 | **32** |
| bound native functions | 760 | **760** |
| dependency-frontier candidates | 2 | **1** |

Every other structural category stays zero, the allowlist stays empty, `ABI_MISMATCHES` stays zero
and no native route was added: the whole family is managed.

## 1. Two authorities, and a gate that got stronger

mscorlib declares no `System.ComponentModel` identity, so `tools/api_compat/build_bcl_inventory.rb`
had to stop being pinned to one assembly. It is now a **registry**, and every gate is a property of
the registry rather than of either binary: exact SHA-256 and byte length, an identity derived from
the assembly's own `.publickey` blob by the CLR's own rule, a Microsoft origin claim read out of the
PE version resource, and a pairing proof. Adding a third authority would be a table entry plus its
demand.

`System.dll` is admitted at
`c3182e40f09a8d3a0167a833dc1ce7c3cb2bfddbd32031d8d3f41481d0467462`, 3481928 bytes, assembly
`System` 4.0.0.0, token `b77a5c561934e089` derived from the ECMA key
`00000000000000000400000000000000`, `CompanyName` *Microsoft Corporation*, `FileDescription`
*.NET Framework*, file version `4.0.30319.1 built by: RTMRel`.

**The pairing gate had to get stronger rather than weaker to admit it.** Only six of the ten pinned
XNA assemblies declare an `AssemblyRef` to `System`:

| Authority | Referrers | Non-referrers |
| --- | ---: | --- |
| `mscorlib` | 10 | none |
| `System` | 6 | `Avatar`, `Input.Touch`, `Storage`, `Video` |

Requiring all ten would have failed; requiring "at least one" would have proved nothing. So the
**referrer set is itself asserted**, and an XNA assembly that gained or lost the reference now fails
the gate. That is the opposite of relaxing a standard to fit a second file.

### The scanner defect this project keeps finding, once more

Reading the PE version resource found the same shape of defect the field-name and blocker audits
have each found before: **a token anchored on one side only.** A resource key occurs three times in
a managed PE — in the `VS_VERSION_INFO` string table beside its value, in the resource-name
directory with nothing after it, and in the string heap. The reader that answered mscorlib
correctly answered, for `System.dll`, the whole name directory rather than `Microsoft Corporation`,
because the first occurrence happened to be the wrong one. Every occurrence is read now and the
expected value must be among the plausible candidates.

### Twelve identities are declared by both assemblies

`System.ThrowHelper`, `System.ExceptionResource` and `System.ExceptionArgument` among them — and
they are *different types with different members*. Body tables, support literals and throw-helper
resolution are therefore built **per authority**. A merged table would have derived a System.dll
member's throw from mscorlib's helper, which is a wrong answer that nothing would have reported.

## 2. Demand gained a third channel, and it is generated

A family is admitted on one of three measured demands, and the builder aborts on a family with
none:

- **direct** — an XNA public or protected signature names it. `CultureInfo` (21 signatures),
  `ITypeDescriptorContext` (38), `PropertyDescriptorCollection` (2), `IDictionary` (12).
- **transitive** — an already-admitted family's *measured* surface names it, the way
  `System.IO.Stream::Seek` names `SeekOrigin`. `TextInfo`, `ICollection`, `MemberInfo`,
  `PropertyDescriptor`, `TypeConverter`.
- **behavioural** — the measured XNA *behaviour* calls it and a Ruby consumer observes the result.

`System.ComponentModel.TypeDescriptor` is the case that needed the third and could not have been
admitted without it: no signature anywhere names it, and `MathTypeConverter.ConvertToValues` calls
`GetConverter` at `IL_0054` while `ConvertFromValues` calls it at `IL_002a`. So the string form of
every value the thirteen converters produce or accept is that class's answer. The evidence is
`docs/generated/design-converter-inventory.json`, derived from the same IL the converters are —
never a claim in prose.

The three scalar element converters are admitted through the same chain, one step further out:
`ConvertToValues<T>` names `T`, and `ReflectTypeDescriptionProvider`'s intrinsic table — extracted
from its own property getter into `docs/generated/bcl-inventory.json` — says which converter each
resolves to. `System.Int32` → `Int32Converter`, `System.Single` → `SingleConverter`, `System.Byte`
→ `ByteConverter`.

## 3. The audit table is generated, not transcribed

`tools/api_compat/build_design_inventory.rb` derives, per converter: base type, declared members
and their access, the value type, the descriptor member names **in authored order**, whether each
descriptor reflects a field or a property, the sort order or its absence, `supportStringConvert`,
the scalar element type, the expected parameter names, the constructor the `InstanceDescriptor`
branch names, whether that constructor **resolves** against the reference contract, and the
dictionary keys `CreateInstance` reads.

`test/test_design_converters.rb` asserts the Ruby implementation against that file. Neither side can
drift without the other failing, which is the property every hand-maintained table in this project
has eventually lost.

## 4. Five facts the IL settled that no page had recorded

### `MatrixConverter` and `RectangleConverter` never sort

The other ten call `PropertyDescriptorCollection.Sort(names)` in their constructors; those two do
not. So their property order is the **authored** order — `M11..M44` and `X, Y, Width, Height` —
and neither is alphabetical, which is what a bare `Sort()` would have produced. A projection that
sorted uniformly would have reordered `Rectangle` to `Height, Width, X, Y`.

### ...and none of the ten sorts reorders anything

Each of the ten passes `Sort` **exactly the order it just authored its descriptors in**, so the
sorted collection equals the unsorted one. All twelve converters therefore answer their authored
order, by two different paths, and the sort is belt and braces rather than the thing that decides.

That is worth stating because it changes what a test can catch. "Ignore `Sort`" is a **no-op mutant
against every converter's answer**, and can only be scored on the collection's own contract — that
`Sort` answers a new collection carrying the requested order — which is where the negative control
for it lives. It also says where the real risk is: an implementation that authored in one order and
sorted into another would diverge from XNA while every individual fact still matched, so the test
asserts that the authored order and the sort order are the same list for all ten.

### `ColorConverter` cannot produce an `InstanceDescriptor`

Its `ConvertTo` asks `typeof(Color).GetConstructor(new[]{ typeof(byte) ×4 })`. `Color` declares
seven public constructors — `(uint)`, `(int,int,int)`, `(int,int,int,int)`, `(float,float,float)`,
`(float,float,float,float)`, `(Vector3)`, `(Vector4)` — and **none takes four bytes**. So
`GetConstructor` answers null, the IL's own `ConstructorInfo.op_Inequality(ctor, null)` at
`IL_00bb` fails, the branch is skipped, and what a consumer gets is the base `TypeConverter.ConvertTo`,
which throws for a non-`String` destination.

This is reproduced rather than corrected. The generator resolves every named constructor against the
reference contract: eleven of twelve resolve and the twelfth is reported as not resolving, so the
finding is a measurement rather than a note. `ColorConverter`'s *string* conversion is unaffected.

### Six converters answer `CanConvertTo(String)` true and cannot format one

`supportStringConvert` is false for `BoundingBox`, `BoundingSphere`, `Matrix`, `Plane`, `Ray` and
`Rectangle`, so `CanConvertFrom(String)` is false for all six. But `CanConvertTo` falls through to
`TypeConverter.CanConvertTo`, whose whole body is `destinationType == typeof(string)` — so the
answer is **true**, and `ConvertTo` really does produce a string: the base implementation's, which
is `value.ToString()`. A `MatrixConverter` therefore answers `Matrix.ToString()` where a
`Vector3Converter` answers a separator-joined list.

### `TypeConverter.CanConvertFrom` answers for `InstanceDescriptor`, not for `String`

Half of each converter's answer is the base class's. That is why the base is *projected* rather than
flattened into `MathTypeConverter` by hand: writing those two members from what they appear to do
would have inverted both. It is also why three converters declare a `ConvertFrom` whose whole body
is a call to the base — accepting an `InstanceDescriptor` is the behaviour they want — and why the
three that declare none behave identically.

## 5. What was projected, and by which half of the rule

The admission rule pulls in two directions: do not under-project the **inherited public surface**,
and do not over-project a **private implementation dependency**. Each family is placed by which it
is.

| Family | Rule | What that means here |
| --- | --- | --- |
| `TypeConverter`, `ExpandableObjectConverter` | inherited | the base chain of all thirteen converters, so every public member is callable on each — the whole public surface is projected |
| `PropertyDescriptor` | inherited | the base of the descriptors a consumer receives from `GetProperties` |
| `PropertyDescriptorCollection`, `InstanceDescriptor` | reachable | objects the converters *answer*; everything public is reachable on the instance |
| `TypeDescriptor` | reached | a static utility nothing inherits, so only `GetConverter` and `GetProperties` are projected and its other seventy statics are not |
| `CultureInfo`, `TextInfo`, the four `System.Reflection` types | reached | exactly the members the measured reach touches |

Two identities are **refused** with their reason recorded rather than left silent.
`TypeConverter+StandardValuesCollection` is not projected because `GetStandardValues` answers
`ldnull` in the base and no XNA converter overrides it, so no consumer of this binding can obtain
one — a Ruby class nothing can produce would be an invented identity.
`System.ComponentModel.IContainer` is not projected because nothing in the admitted reach calls a
member of it: it is the declared type of a context property this binding only passes through.

`ITypeDescriptorContext` is the register's **first projected interface**. The structural collapse
the register applies to `IDisposable` and `IServiceProvider` needs an implementing type whose
members the contract can survive as, and XNA implements this one nowhere — the *consumer* supplies
the context. So it projects to a Ruby module carrying the six measured identities, plus a check that
refuses an object missing any of them, because accepting anything and failing later at the call site
is the failure mode the projection exists to prevent.

## 6. Two language mapping limitations, recorded rather than hidden

### Ruby's `Integer` is both `System.Int32` and `System.Byte`

Two measured behaviours turn on telling them apart: `Color`'s missing four-byte constructor, and
which element converter parses a channel — `ByteConverter` ranges 0..255 and accepts hexadecimal,
`Int32Converter` does not range-check to a byte. Resolving the constructor lookup on Ruby types
would make `(Byte,Byte,Byte,Byte)` and `(Int32,Int32,Int32,Int32)` equal, the lookup succeed, and
this binding produce an `InstanceDescriptor` where XNA produces none.

So `CNA::Runtime::Reflection` is keyed by **CLR identity** and answers the Ruby type beside it: the
lookup stays exact, and `FieldInfo.FieldType`, `PropertyInfo.PropertyType` and
`ConstructorInfo.ParameterTypes` answer what `System.Type` projects to.
`TypeDescriptor.GetConverter` answers the reachable half for a Ruby type — `Integer` →
`Int32Converter`, `Float` → `SingleConverter` — and `System.Byte`'s converter is the one an ordinary
consumer cannot name.

### There is no locale database, and there will not be one

The CLR reads culture data from the operating system's locale tables. Shipping a table of hundreds
of cultures would be asserting facts nothing here measured, so `CultureInfo` carries the separators
the admitted reach consumes and a consumer constructs any culture other than the invariant one with
the values it needs.

The invariant culture's values are **read out of the pinned mscorlib**, from `CultureData`'s
invariant initialiser where each is an `ldstr` followed by the `stfld` that stores it:
`Name` `""`, `ListSeparator` `","`, decimal `"."`, group `","`, negative `"-"`, positive `"+"`,
`"NaN"`, `"Infinity"`, `"-Infinity"`. `CurrentCulture` answers the invariant culture until a
consumer sets one, so a converter's output is the same on every machine rather than depending on
the host's locale environment.

## 7. The registries are explicit and load-order independent

`System.Type` projects to Ruby `Module`, and a `Module` has no fields — so `Type.GetField`,
`GetProperty` and `GetConstructor` have to be answered by something. Both ways of doing it
implicitly are wrong: monkey-patching `Module` would put XNA's names on every class in the
consumer's program, and scanning `instance_methods` would make the answer depend on what happened to
be defined, and therefore on load order.

Members and converters are **registered explicitly**, once, beside the type that declares them, and
a lookup is a hash read. `test/test_design_converters.rb` asserts this by cold-loading the binding
twice in a subprocess with a shuffled registration order and comparing the marshalled answers byte
for byte.

## 8. What was measured end to end

- every converter's descriptor order against a **non-symmetric** sample, with each descriptor's
  value read back, so a swapped pair is a different answer rather than merely a different order;
- both `InstanceDescriptor` directions for the eleven that resolve, including reconstruction
  through `Invoke`, and the refusal for the twelfth;
- `CreateInstance` from a dictionary keyed by descriptor name, for all twelve;
- two cultures whose list, decimal **and** group separators all differ, in both directions, with
  `CurrentCulture` restored afterwards;
- hexadecimal accepted by the integer element converters (`#10`, `0xFF`, `&hFF`) and refused by the
  single ones, which is `BaseNumberConverter.AllowHex` true against `SingleConverter`'s override;
- the failure set — too few values, too many, an invalid element, empty, separator-only, a trailing
  separator — each an `ArgumentError` naming the expected parameters, as
  `FrameworkResources.InvalidStringFormat` does;
- `PropertyDescriptorCollection`'s ordinal `Find`, its non-mutating `Sort`, and the read-only
  refusals on `Empty`;
- `PropertyDescriptor.AddValueChanged` firing on `SetValue`, which is the `OnValueChanged` call at
  `IL_000d`..`IL_0014` of the field descriptor.

**Twenty-five negative controls, all killed, zero survivors** — including a wrong `System.dll`
SHA-256, a wrong referrer set, a dropped base mapping, `PropertyDescriptorCollection` mapped to
`Array`, a missing `ITypeDescriptorContext` member, an always-true base fallback, reordered and
transposed descriptors, a hard-coded comma, a joined separator that loses its space, an invented
`Color` constructor, a `Color` that drops its alpha channel, a `Sort` that mutates the receiver, a
`Sort` that answers the receiver, a descriptor `SetValue` that does not write, a skipped change
notification, a `ConvertFrom` that accepts a wrong value count, a `ConvertTo` that ignores the
culture, a family projected without being admitted, and a selected `Design` type removed from the
selection.

## 9. The gate

`test_a_selected_family_can_never_be_classified_bcl_projection_scope` checks the rule on three
independent artifacts rather than by reading prose for the phrase, because a document can be
reworded and a measurement cannot:

1. the strict report — every selected type is complete or partial, never missing;
2. the dependency frontier — no selected type is a candidate, and `BCL_PROJECTION` names nothing;
3. the BCL register — every `System.ComponentModel` identity the family reaches resolves to a real
   Ruby projection, so "the reach is too large" cannot be reasserted without failing.

## 10. What this milestone does not claim

No runtime consumer. The converters are design-time surface and nothing in the game loop reaches
them; the binding implements the XNA public profile rather than only what a running game touches.
No native route was added and no CNA behaviour was measured. And the packaged gem carries no
Microsoft assembly: the two authorities are build-and-test authority only, and the converters run
cold from an installed gem with no `BCL_REFERENCE_ASSEMBLIES`, no `XNA_REFERENCE_ASSEMBLIES`, no
`ikdasm` and no DLL present.
