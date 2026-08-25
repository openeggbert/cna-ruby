# Foundation 30 — `System.NotSupportedException` projects to `CNA::Runtime::NotSupportedError`

The last mapping decision the frontier register carried, and the one where the obvious answer is
wrong in a way that fails silently.

## The decision

`System.NotSupportedException` → `CNA::Runtime::NotSupportedError`, a dedicated class descending
from `StandardError`.

### Why not `NotImplementedError`

It is the closest name in Ruby and it is unusable, because in Ruby it is not an error class in the
ordinary sense:

```ruby
NotImplementedError < ScriptError   # => true
NotImplementedError <= StandardError # => false
```

A bare `rescue`, and `rescue StandardError`, do **not** catch a `ScriptError`. A CLR
`catch (Exception)` is exactly the analogue of a bare `rescue`, so a caller writing the obvious
XNA-shaped code

```ruby
begin
  touches.Add(location)
rescue => error      # catches StandardError
  ...
end
```

would see the exception escape. A routine, recoverable, entirely expected CLR failure — calling a
mutating member of a read-only collection — would blow past the caller's error handling. This
binding already records that trap for `IUpdateable`/`IDrawable`, where `NotImplementedError` is
correct precisely because an abstract contract member is *not* an ordinary failure. Reusing it here
would erase the distinction.

`RuntimeError` and `ArgumentError` are both catchable and both say something the CLR exception does
not; neither gives a caller an identity to `rescue` by name. `StandardError` itself is catchable and
loses the identity entirely. A real class is the only option that keeps both properties.

### What the mscorlib settled

From `docs/generated/bcl-inventory.json`, Foundation 28:

- `System.NotSupportedException` extends `System.SystemException`, which extends `System.Exception`
  — the identity `BclProjection::EXCEPTION_BASES` already roots at `StandardError`. The CLR chain
  and the Ruby chain end in the same place, which is what makes `StandardError` the right root
  rather than a convenience.
- Three public constructors: `()`, `(string message)`, `(string message, Exception innerException)`,
  plus the protected `(SerializationInfo, StreamingContext)` this binding projects nowhere. The two
  message-bearing forms forward the message to the base and synthesise nothing. All three set
  HRESULT `0x80131515`, which has no Ruby analogue and is not projected.
- The parameterless form fills the message from `Environment.GetResourceString`, resource
  `Arg_NotSupportedException`.

That last one is the message-fabrication question the work was warned about. The resource text is
Microsoft's, it is culture-dependent, and no XNA member exposes it observably — `TouchCollection`
throws with the parameterless constructor and never reads the message back. So it is **not**
reproduced. `CNA::Runtime::NotSupportedError.new.message` answers Ruby's own default, the class
name. The test asserts no file in the repository carries the framework string.

The inner-exception form reuses `ExceptionSupport.bind_cause`, which the six XNA exception types
already use: Ruby's slot for `InnerException` is `Exception#cause`, only `raise` can fill it, so the
exception is raised and immediately re-caught and its backtrace cleared. A constructed-but-unraised
instance therefore has `cause` set and `backtrace` nil, exactly as the CLR has `InnerException` set
and `StackTrace` null before a throw.

## A third register, deliberately

The mapping lives in `CNA::Runtime::BclProjection::THROWN_EXCEPTIONS`, beside but **not inside**
`TYPES` and `EXCEPTION_BASES`. The difference is load-bearing:

| Register | What an entry is | Named by an XNA signature? |
| --- | --- | --- |
| `TYPES` | a BCL type the XNA public surface declares | yes |
| `EXCEPTION_BASES` | a CLR base an XNA exception type derives from | yes |
| `THROWN_EXCEPTIONS` | a CLR exception a projected member's IL constructs | **no** |

`System.NotSupportedException` appears nowhere in the 257-type reference contract's signatures. It
exists only inside method bodies. Folding it into `identities` would make the dependency frontier
count it as a mapped BCL type the XNA surface names, which is false; and it would break the
standing rule, tested since Foundation 21, that every register identity is one the pinned reference
actually names. `BCL_PROJECTED_IDENTITIES` stays 6; the new count is reported separately as
`BCL_THROWN_EXCEPTIONS` 5.

The register is measured, not documentation. `verify_thrown_exceptions` resolves every entry and
reports `LANGUAGE_MAPPING_MISMATCH` unless it is a class, descends from `StandardError`, and does
**not** descend from `ScriptError`. Five mutations are covered by test:

| Mutation | Caught because |
| --- | --- |
| `NotImplementedError` substitution | it is a `ScriptError` |
| any other `ScriptError` subclass | same rule, stated generally |
| a plain `Object` subclass with the identity lost | not a `StandardError` |
| an unresolved constant | does not resolve |
| a fabricated `System::NotSupportedException` | does not resolve; no `::System` namespace exists |

A generic `StandardError` cannot be rejected on shape alone — it *is* a `StandardError` — so that
one is stated where it can be checked: no entry may be the bare root, and the test asserts it of
every entry, not just this one.

## Which exception a member raises: who constructs it decides

Adding this entry exposed a tension worth writing down rather than fudging. `mapping-rules.json`
requires that one CLR exception maps to exactly one Ruby exception, and Foundation 29 wrote a
collection rule saying an out-of-range index raises `IndexError`. `TouchCollection`'s indexer throws
`ArgumentOutOfRangeException`, which the table maps to `RangeError`. Both cannot apply.

They do not conflict, and the reason is in the IL:

- `ReadOnlyCollection<T>` and `CurveKeyCollection` **forward** their indexer to the backing
  `IList<T>`. No CLR exception is constructed in the projected member at all, so nothing is being
  mapped; the condition arises in this binding's own Ruby `Array` backing, and
  `collections.indexErrors` governs it — `IndexError`, which is the identity `Array#fetch` raises.
- `TouchCollection`'s `get_Item` **constructs** `ArgumentOutOfRangeException("index")` in its own
  body, with the parameter name as an `ldstr` operand. That is precisely what the thrown-exception
  table is for, so it raises `RangeError` with the CLR's parameter name as the message.

Recorded as `bclProjection.thrownExceptions.whoConstructsItDecides`. The one-to-one policy holds:
`ArgumentOutOfRangeException` still maps to exactly one Ruby exception wherever it is actually
projected.

## What this milestone does not do

- **No XNA type becomes complete.** Strict is unchanged: 135 types / 1714 members, 129 complete,
  306 diagnostics. `TouchCollection` is Foundation 31.
- **Nothing raises it yet.** No member in this binding throws `NotSupportedError` at present; the
  class exists because the mapping is now decided and measured.
- **No CNA source change.** ABI unchanged at 39 / 124 / 290 / 290 / 2 / 59.

## Numbers

| Metric | Before | After |
| --- | --- | --- |
| `BCL_PROJECTED_IDENTITIES` | 6 | 6 |
| `BCL_EXCEPTION_BASES` | 2 | 2 |
| `BCL_THROWN_EXCEPTIONS` | — | **5** |
| `LANGUAGE_MAPPING_MISMATCH` | 0 | 0 |
| `TOTAL_DIAGNOSTICS` | 306 | 306 |
| Capability rows / contradictions | 85 / 0 | 85 / 0 |
| Open `UNRESOLVED_MAPPING_DECISION` rows | 1 | **0** |
