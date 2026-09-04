# BCL reference authority

`xna40-windows-runtime-contract.json` pins the **public metadata** of the XNA profile and
`XNA_IL_PROVENANCE.md` pins the XNA **implementation authority**. Neither covers the BCL. Several
XNA public members name a `System.*` type — `GraphicsAdapter.Adapters` is a
`ReadOnlyCollection<GraphicsAdapter>`, `LaunchParameters` *derives from*
`Dictionary<string,string>` — and this binding refuses to project a type it has not measured. This
file pins the third authority: the Microsoft .NET Framework assemblies the XNA 4.0 Windows runtime
binds to.

There are **two** of them, admitted independently and to the same standard, and neither is a
weakening of the other:

| Authority | Admitted at | Because |
| --- | --- | --- |
| `mscorlib` | Foundation 28 | the BCL every pinned XNA assembly binds, and the declaring assembly of every collection, stream, reflection, globalization and exception identity the selected XNA surface names |
| `System` | Foundation 105 | the declaring assembly of `System.ComponentModel`, which the thirteen XNA `Design` converters extend, return, take as a parameter and special-case; mscorlib declares none of those identities |

## They are separate authorities, not more XNA assemblies

Neither is part of the XNA profile and none of their types is an XNA identity.

- `REFERENCE_TYPES` stays **257** and `REFERENCE_MEMBERS` stays **2964**. Both are XNA-only.
- `docs/generated/xna-il-inventory.json` stays XNA-only: `TYPES_WITH_IL` **257**,
  `TYPES_WITHOUT_IL` **0**.
- The BCL inventory reports its own metrics — `BCL_FAMILIES`, `BCL_TYPES`, `BCL_MEMBERS`,
  `BCL_EXCEPTION_TYPES` — in `docs/generated/bcl-inventory.json`, and nothing else consumes them as
  XNA surface.

## Pinned assemblies

| Field | `mscorlib` | `System` |
| --- | --- | --- |
| Assembly name | `mscorlib` | `System` |
| Assembly version | `4.0.0.0` | `4.0.0.0` |
| File version | `4.0.30319.1 (RTMRel.030319-0100)` | `4.0.30319.1 built by: RTMRel` |
| Public key token | `b77a5c561934e089` | `b77a5c561934e089` |
| Bytes | 5196112 | 3481928 |
| SHA-256 | `5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63` | `c3182e40f09a8d3a0167a833dc1ce7c3cb2bfddbd32031d8d3f41481d0467462` |
| CompanyName | `Microsoft Corporation` | `Microsoft Corporation` |
| FileDescription | `Microsoft Common Language Runtime Class Library` | `.NET Framework` |

Both are the 32-bit desktop .NET Framework 4.0 RTM assemblies — the CLR generation XNA 4.0
Windows targets, not the .NET Compact Framework mscorlib that XNA Game Studio ships for Xbox 360,
and not a Mono, .NET Core or NuGet reference implementation. They carry the same ECMA public key
and the same 4.0.30319.1 RTM build. On the machine this work was done on both are from the retained
Wine XNA 4.0 environment; any copy whose SHA-256 matches is equally authoritative and any copy whose
SHA-256 does not is not, so no path is recorded here.

### The near miss, named

A genuine Microsoft assembly called `System` that this gate **refuses** is on the same machine, and
it is worth naming because it is the exact analogue of the Xbox 360 mscorlib recorded above: XNA
Game Studio 4.0 ships a .NET **Compact** Framework `System.dll` under
`.../XNA Game Studio/v4.0/References/Xbox360/`.

| Field | Admitted `System` | The Xbox 360 near miss |
| --- | --- | --- |
| SHA-256 | `c3182e40f09a8d3a0167a833dc1ce7c3cb2bfddbd32031d8d3f41481d0467462` | `0a46c52a7ccdaf16dc4fe29865ed36f0431fbcd1d0bdee3395331bf8ffd3f270` |
| Bytes | 3481928 | 42496 |
| Assembly name | `System` | `System` |
| Assembly version | `4.0.0.0` | **`2.0.5.0`** |
| Public key | the ECMA key `00000000000000000400000000000000` | **a full 128-byte Microsoft key** |

The name is identical and everything the gate actually checks differs, so the refusal is a
measurement rather than a filename rule. It is refused four times over: by SHA-256, by byte length,
by the manifest's `.ver`, and by the token derived from its own key blob — and, had it passed all of
those, by the pairing, because the pinned XNA Windows assemblies bind `System 4.0.0.0`. This is
recorded rather than wired into a test because the path is machine-local; the committed control is
the metadata mutation in the negative-control set, which fails the same four gates.

### A second disassembler, on the facts the gate turns on

`ikdasm` produces every identity value above, so a defect in *it* would be invisible to any check
that reads only its output. The builder therefore reads the assembly table a second time with
**`monodis`** — a different disassembler over the same bytes — and requires it to agree on the
assembly name, the assembly version and the public key blob. Both admitted authorities pass, and
the inventory records which tool ran under each authority's `crossCheck`, so "cross-checked" can
never quietly mean "not run": when `monodis` is absent the record says so instead of being omitted.

### Reading the PE version resource

A resource key occurs in a PE more than once: in the `VS_VERSION_INFO` string table beside its
value, again in the resource-name directory with nothing after it, and in a managed assembly a
third time in the string heap. Reading only the first occurrence is a token anchored on one side
only — the scanner defect this project keeps finding — and for `System.dll` the first `CompanyName`
hit answers the whole name directory rather than `Microsoft Corporation`. The tool therefore reads
**every** occurrence, keeps the ones whose value is a plausible resource string, and asserts the
expected value is among them. A binary whose real `CompanyName` differs still fails the gate.

## The identity is derived, not asserted

`tools/api_compat/build_bcl_inventory.rb` refuses to run unless all of the following hold, and every
one of them is read out of the admitted bytes:

1. SHA-256 and byte length match the pins above.
2. The `.assembly <name>` manifest declares `.ver 4:0:0:0`.
3. The public key token **derived** from the manifest's own `.publickey` blob — SHA-1, low eight
   bytes, reversed, which is the CLR's own rule — equals `b77a5c561934e089`. The token is a
   conclusion drawn from the assembly, never a constant the tool trusts. Both carry the ECMA
   standard key `00000000000000000400000000000000`, and that blob is what hashes to this token.
4. The PE version resource says `Microsoft Corporation` and the assembly's own `FileDescription`,
   and the file version starts `4.0.30319.1`.
5. **Pairing.** Every pinned XNA assembly that declares an `AssemblyRef` to the authority must name
   exactly the version and public key token the admitted binary derives, and **the set of
   assemblies that declare one is itself asserted**. This is what makes each admitted file *the
   assembly the pinned XNA assemblies bind to* rather than merely *an* assembly of that name.

   The two sets are not the same, and pretending they were would make the second proof vacuous:

   | Authority | Referrers | Non-referrers |
   | --- | ---: | --- |
   | `mscorlib` | all 10 | none |
   | `System` | 6 | `Avatar`, `Input.Touch`, `Storage`, `Video` |

6. **Every authority is demanded.** An assembly admitted with no family declared by it aborts the
   build. A larger registry is not a stronger one.

## Running it

```sh
BCL_REFERENCE_ASSEMBLIES=<directory holding mscorlib.dll> \
XNA_REFERENCE_ASSEMBLIES=<directory holding the pinned XNA assemblies> \
  ruby tools/api_compat/build_bcl_inventory.rb
```

It disassembles with `ikdasm` (Debian package `ikdasm`) and writes
`docs/generated/bcl-inventory.json`.

## The inventory is demand-driven

Ingesting either assembly wholesale would be a reimplementation of the .NET Framework, which this
project does not attempt. A family is admitted only on one of three measured demands, and the tool
aborts on a family that has none of them:

- **direct** — an XNA public or protected signature names it;
- **transitive** — an already-admitted family's *measured* surface names it, as `System.IO.Stream::Seek`
  names `SeekOrigin` and `CultureInfo.TextInfo` names `TextInfo`;
- **behavioural** — the measured XNA *behaviour* calls it and a Ruby consumer observes the result,
  with the evidence taken from `docs/generated/design-converter-inventory.json` rather than from a
  claim. `System.ComponentModel.TypeDescriptor` is the case that needs it: no signature anywhere
  names it, and `MathTypeConverter.ConvertToValues` and `ConvertFromValues` both call `GetConverter`,
  so the string form of every value the thirteen converters produce or accept is its answer.

The recorded surface is the public and protected
surface plus the explicit interface implementations — for a read-only collection the refusal to
mutate lives in exactly those — and then the closure of exception types that surface actually
throws, walked up its base chain to `System.Exception`, which is where this binding's projection
register already roots.

## What is recorded

Identities, shapes and **derived behavioural facts**. Never IL text, never Microsoft-owned bytes,
never a machine-local path, and nothing Microsoft-owned is packaged into the gem.

A derived fact is one of:

- `delegatesTo` / `viaField` — the member's whole body loads `this`, reads one instance field,
  pushes its arguments in order and makes one call. This is the shape that decides whether a wrapper
  is a live view over a backing collection or an immutable snapshot of one.
- `throws` — the exception identity, resolved through `System.ThrowHelper` by reading which
  exception that helper actually constructs, together with the `System.ExceptionResource` and
  `System.ExceptionArgument` literal names the call site passes.
- `throwsUnconditionally` — the body reaches a throw with no branch instruction anywhere in it.
- `storesConstructorArgumentToField` — the constructor keeps its argument.

## Authority order

1. **Exact original binary + `ikdasm` IL** — the only implementation authority, for the BCL exactly
   as for XNA.
2. Hash-proven decompilation — readability and cross-checking only, never authority.
3. Mono, .NET Core, `System.Private.CoreLib`, FNA, MonoGame and every reimplementation — comparators
   only, never authority.
