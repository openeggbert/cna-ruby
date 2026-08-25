# BCL reference authority

`xna40-windows-runtime-contract.json` pins the **public metadata** of the XNA profile and
`XNA_IL_PROVENANCE.md` pins the XNA **implementation authority**. Neither covers the BCL. Several
XNA public members name a `System.*` type — `GraphicsAdapter.Adapters` is a
`ReadOnlyCollection<GraphicsAdapter>`, `LaunchParameters` *derives from*
`Dictionary<string,string>` — and this binding refuses to project a type it has not measured. This
file pins the third authority: the Microsoft .NET Framework mscorlib the XNA 4.0 Windows runtime
binds to.

## It is a separate authority, not another XNA assembly

mscorlib is not part of the XNA profile and none of its types is an XNA identity.

- `REFERENCE_TYPES` stays **257** and `REFERENCE_MEMBERS` stays **2964**. Both are XNA-only.
- `docs/generated/xna-il-inventory.json` stays XNA-only: `TYPES_WITH_IL` **257**,
  `TYPES_WITHOUT_IL` **0**.
- The BCL inventory reports its own metrics — `BCL_FAMILIES`, `BCL_TYPES`, `BCL_MEMBERS`,
  `BCL_EXCEPTION_TYPES` — in `docs/generated/bcl-inventory.json`, and nothing else consumes them as
  XNA surface.

## Pinned assembly

| Field | Value |
| --- | --- |
| Assembly name | `mscorlib` |
| Assembly version | `4.0.0.0` |
| File version | `4.0.30319.1 (RTMRel.030319-0100)` |
| Public key token | `b77a5c561934e089` |
| Bytes | 5196112 |
| SHA-256 | `5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63` |
| CompanyName | `Microsoft Corporation` |
| FileDescription | `Microsoft Common Language Runtime Class Library` |
| Product | `Microsoft® .NET Framework` |

This is the 32-bit desktop .NET Framework 4.0 RTM class library — the CLR generation XNA 4.0
Windows targets, not the .NET Compact Framework mscorlib that XNA Game Studio ships for Xbox 360,
and not a Mono, .NET Core or NuGet reference implementation. On the machine this work was done on
it is the mscorlib of the retained Wine XNA 4.0 environment; any copy whose SHA-256 matches is
equally authoritative and any copy whose SHA-256 does not is not, so no path is recorded here.

## The identity is derived, not asserted

`tools/api_compat/build_bcl_inventory.rb` refuses to run unless all of the following hold, and every
one of them is read out of the admitted bytes:

1. SHA-256 and byte length match the pins above.
2. The `.assembly mscorlib` manifest declares `.ver 4:0:0:0`.
3. The public key token **derived** from the manifest's own `.publickey` blob — SHA-1, low eight
   bytes, reversed, which is the CLR's own rule — equals `b77a5c561934e089`. The token is a
   conclusion drawn from the assembly, never a constant the tool trusts. mscorlib carries the ECMA
   standard key `00000000000000000400000000000000`, and that blob is what hashes to this token.
4. The PE version resource says `Microsoft Corporation` and
   `Microsoft Common Language Runtime Class Library`, and the file version starts `4.0.30319.1`.
5. **Pairing.** All ten pinned XNA assemblies declare an `AssemblyRef` to `mscorlib`, and every one
   of those references must name exactly the version and public key token the admitted binary
   derives. This is what makes the admitted file *the mscorlib the pinned XNA assemblies bind to*
   rather than merely *an* mscorlib.

## Running it

```sh
BCL_REFERENCE_ASSEMBLIES=<directory holding mscorlib.dll> \
XNA_REFERENCE_ASSEMBLIES=<directory holding the pinned XNA assemblies> \
  ruby tools/api_compat/build_bcl_inventory.rb
```

It disassembles with `ikdasm` (Debian package `ikdasm`) and writes
`docs/generated/bcl-inventory.json`.

## The inventory is demand-driven

Ingesting mscorlib wholesale would be a reimplementation of the .NET Framework, which this project
does not attempt. A family is admitted only when the XNA reference contract really names it, and the
tool aborts on a family with zero XNA consumers. The recorded surface is the public and protected
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
