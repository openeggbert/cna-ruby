# Foundation 49 — the serialization carrier, and the two exception types it unblocks

Derived from the pinned `Microsoft.Xna.Framework.dll` (SHA-256 `38e7093f…`),
`Microsoft.Xna.Framework.Storage.dll` (SHA-256 `798f678e…`) and the admitted Microsoft .NET
Framework 4.0 `mscorlib` (SHA-256 `5634668d…`), all disassembled with `ikdasm`.

`Content.ContentLoadException` and `Storage.StorageDeviceNotConnectedException` were deferred
through eight milestones with the same sentence: their selected surface "includes a protected
serialization constructor over System.Runtime.Serialization, a BCL cluster no otherwise-unblocked
type needs". What that cluster really costs is **two nominal identities**.

## Why nominal, and not a marker

Both types declare the standard four-constructor exception shape:

```
public   .ctor()
public   .ctor(string message)
public   .ctor(string message, Exception innerException)
family   .ctor(SerializationInfo info, StreamingContext context)
```

Every one is a pure forward to its base — `System.Exception` for the first, ExternalException for
the second, which the register collapses to the nearest projected ancestor.

**Two of the four take two arguments.** Ruby has no overload by parameter type, so one `initialize`
has to tell `(message, innerException)` from `(info, context)`, and the only sound way to do that is
a nominal first argument. A marker class or a duck type would make that dispatch a guess; a real
identity makes it a decision. That is the whole argument for projecting these two as classes, and it
is a Ruby fact rather than a preference.

## How much surface each owes

The register's own narrowness rule: only a CLR identity the selected XNA surface actually names,
projected to what that surface can reach. `System.Type` projects to `Module` because a service key is
all the XNA surface uses it as; `System.Attribute` projects to an empty marker because no XNA
attribute inherits a member from it.

Here the XNA surface names both types in one parameter list and **calls no member of either** —
every one of those constructors is a pure forward. So:

- `SerializationInfo` carries the general `AddValue`/`GetValue` pair and `MemberCount`. mscorlib
  declares **forty-three** public members, but forty of them are the typed `AddValue`/`Get*`
  overloads over the CLR primitive set — conveniences over the general form that a dynamically typed
  language has nothing to distinguish, the same collapse this binding already applies to ref/out
  pairs and to indexers. `FullTypeName`, `AssemblyName`, `SetType`, `ObjectType` and the enumerator
  belong to a formatter's type-resolution protocol, and no formatter exists here to run it.
- `StreamingContext` is the `sequential sealed` value type it is in the IL: two fields, two
  constructors, `State`, `Context`, value equality and a hash of the state.
- `StreamingContextStates` is projected as the ordinary flags enum it is — eight named bits,
  `All = 0xFF`, no named zero — but is deliberately **not registered**, because the selected
  reference never names it. The register admits only identities that surface really names.

The validations are exact. `AddValue(name, value, type)` throws `ArgumentNullException("name")` on a
null name and `SerializationException(Serialization_SameNameTwice)` on a duplicate; the two-argument
form forwards with `value?.GetType() ?? typeof(object)`, so the type argument is never null through
it. `GetValue` reaches `GetElement`, which throws `SerializationException(Serialization_NotFound)`
when `FindElement` answers −1. A stored `nil` is a value, not an absence — the same distinction
`Dictionary`'s indexer draws.

`SerializationException` joins the thrown-exception register as `CNA::Runtime::SerializationError`,
a dedicated `StandardError` subclass for the same reason `NotSupportedError` is one: it is a distinct
CLR identity a caller can rescue by name, and no existing Ruby class says what it says.

## What crosses the serialization constructor, and what does not

`System.Exception`'s own serialization constructor reads **eleven** named values: `ClassName`,
`Message`, `Data`, `InnerException`, `HelpURL`, `StackTraceString`, `RemoteStackTraceString`,
`RemoteStackIndex`, `ExceptionMethod`, `HResult` and `Source`.

Ruby's exception base holds exactly one of them — the message — so that is the one this carries
across. The other ten name CLR-internal state that `System.Exception`'s projection to `StandardError`
does not have, and **none of them is fabricated**: a test fills a carrier with all ten and asserts
that only `Message` reaches the exception. A carrier with no `Message` yields an exception with no
message, which is what an absence means rather than an error.

## It unifies what Foundation 46 left duck-typed

`CNA::Runtime::Dictionary`'s `GetObjectData` and `OnDeserialization` were built over an unnamed
carrier because no identity existed yet. They now take the projected `SerializationInfo` and refuse
anything else, so one carrier serves the BCL collection and the two XNA exception types alike.

## `Storage`, a namespace holding one type

`Microsoft::Xna::Framework::Storage` opens with exactly one projected type, which is the shape
`Audio` and `Media` took when Foundation 16 opened them for their enums. There is no `StorageDevice`,
`StorageContainer`, save-game enumeration or file system: the profile's other Storage types are still
missing, and nothing here opens, reads or writes a container.

## Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_TYPES` | 144 | 146 |
| `TARGET_MEMBERS` | 1814 | 1822 |
| `COMPLETE_TYPES` | 138 | **140** |
| `MISSING_TYPES` | 113 | 111 |
| `TOTAL_DIAGNOSTICS` | 266 | 264 |
| `BCL_PROJECTED_IDENTITIES` | 11 | 13 |
| `BCL_THROWN_EXCEPTIONS` | 7 | 8 |
| dependency-complete candidates | 17 | 15 |
| `blockerSummary` `BCL_PROJECTION` | 4 | 2 |
| behaviour observations | 515 | 520 |

`MISSING_MEMBER` 110, `PARTIAL_TYPES` 6, allowlist 0 and every other structural category unchanged.
No native binding was added, so the ABI is untouched at 68 / 219 / 300 / 300 / 3 / 66.

## What this does not claim

Nothing in this binding serialises anything. There is no formatter, no surrogate selector, no
binder, no stream format and no `ISerializable` module: `GetObjectData` and `OnDeserialization` hand
state to a named-value bag and take it back, which is the whole of the contract they implement.
Neither exception type is raised by anything — there is still no `ContentManager`, `ContentReader`,
XNB support or content pipeline, so no asset load can fail, and no storage device is queried, so none
can be disconnected.
