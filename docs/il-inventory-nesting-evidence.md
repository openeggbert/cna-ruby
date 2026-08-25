# Nested and generic type declarations in the IL inventory

`docs/generated/xna-il-inventory.json` is the measured evidence base that the dependency frontier,
the native-reachability rule and every "derived from the pinned IL" claim in this binding rest on.
Since Foundation 22 it had a blind spot, and the blind spot had been recorded as a fact about the
disassembler rather than as a defect in the extractor.

## What the frontier said, and what was true

`tools/api_compat/analyze_dependencies.rb` carried exactly one `IL_UNAVAILABLE` entry:

> `TouchCollection+Enumerator`, which `ikdasm` does not emit under an addressable name

`ikdasm` emits it. Running it over the pinned `Microsoft.Xna.Framework.Input.Touch.dll`
(SHA-256 `b0585224…`) produces, inside `TouchCollection`'s braces:

```
  .class sequential ansi sealed nested public beforefieldinit Enumerator
         extends [mscorlib]System.ValueType
         implements [mscorlib]System.Collections.Generic.IEnumerator`1<...>,
```

closed 100 lines later by `  } // end of class Enumerator`. The extractor never saw it, because it
opened a type only on a `.class` in **column zero** and closed it by comparing against the **full**
declared name. A nested declaration is indented and closes with the *short* name, so it matched
neither test.

The consequence was not merely that five types went unrecorded. Because a parent's frame stayed
open across its children, every nested type's lines, fields, methods and call-graph edges were
attributed to the declaring type.

## Three separate defects

1. **Indented declarations were invisible.** Five reference types — the four
   `Model*Collection+Enumerator`s and `TouchCollection+Enumerator` — were reported as carrying no
   IL, and five declaring types over-counted themselves.
2. **Quoted and generic names never matched their closing comment.** `ikdasm` quotes a name that is
   not a plain identifier (`'<>c__DisplayClass3'`) and appends a generic parameter list it omits
   from the closing comment (`ContentTypeReader`1<T>` opens, `ContentTypeReader`1` closes). The
   old leading-identifier regex truncated the first and never reconciled the second, which is why
   `ContentTypeReader`1` and `IPackedVector`1` were also reported as having no IL.
3. **Call-graph edges into nested types dangled.** IL spells a nested type `Parent/Child` in a
   reference while the reference contract, the inventory keys and the method nodes all spell it
   `Parent+Child`, so any edge into a nested type landed on a node that did not exist.

A fourth, smaller one fell out of the first: `constructor_facts` and the declared-method count both
matched `"  } // end of method"` at a fixed two-space indent, so no method inside a nested type was
ever finalised even once its body was correctly attributed.

## The fix

`tools/api_compat/build_il_inventory.rb` now keeps a stack of open `.class` frames keyed by indent.
A declaration at a given indent closes any frame at the same or deeper indent that never saw its
comment — which preserves exactly the recovery the single-`current` scanner got for free by
overwriting itself, and which matters because the C++/CLI assemblies contain malformed types such
as `EmbeddedNativeType<_D3DCAPS9>` and the `_extraBytes_*` padding types. The declared name is read
as the last token of the `.class` line, unquoted and stripped of a trailing generic parameter list,
and the closing comment is normalised the same way before comparison. Only the innermost open frame
receives a line. Call targets have `/` normalised to `+`.

## Measured before and after

| Measurement | Before | After |
| --- | --- | --- |
| `TYPES_WITH_IL` | 250 | **257** |
| `TYPES_WITHOUT_IL` | 7 | **0** |
| `TYPES_NATIVE_REACHABLE` | 55 | **61** |
| `NATIVE_ENTRY_POINT_METHODS` | 205 | **214** |
| inventory keys | — | 7 added, 0 removed |
| entries changed | — | 20 |
| dependency-complete candidates | 21 | 20 |
| `IL_UNAVAILABLE` entries | 1 | **0** |

**Every reference type now has IL, and no type lost native reachability.** Six gained it —
`Audio.AudioCategory`, `AudioEngine`, `Cue`, `SoundBank`, `WaveBank` and
`Graphics.VertexDeclaration` — because the `/` to `+` normalisation reconnected edges that had been
dangling into nested types. The entry-point count rose by nine because a nested method that shares
a name with one of its parent's no longer collapses onto the same node.

The twenty changed entries are all corrections downward of `ilLines`, `declaredFields` and
`declaredMethods` where a parent had been counting its children. `TouchCollection` reported 16
declared fields for its own 11; `FrameworkDispatcher` reported 5 for its own 3, having counted the
two `ManagedCallAndArg` fields as its own.

## Corpus correction

Two observations recorded this project’s own measurement of the pinned IL rather than a fact about
XNA, and both carried the pre-fix numbers. `il_provenance.assemblies` moves `typesWithIl` 250 to
257 and `typesNativeReachable` 55 to 61.
`managed_descriptor.presentation_parameters.il_contract` moves `declaredFields` 11 to **1** — and
that one is worth stating plainly, because the corrected value is the one the binding’s own source
already described. `PresentationParameters` declares exactly one field, the nested internal
`Settings` struct that holds its ten values, which is what `graphics.rb` has said since
Foundation 24. The old 11 was the extractor charging the nested struct’s fields to its parent.

A re-serialisation replay could not prove this correction: the committed corpus renders small
floats in decimal notation that this Ruby’s JSON generator does not reproduce, so
`JSON.pretty_generate` is not byte-preserving over it and never was. The proof used instead is
stronger — the edit is made on the bytes and the before and after streams are compared in full, so
the only permitted difference is the four corrected numbers. Every other observation, element and
byte is unchanged, and each file records the correction as `nativeFrontier2CorpusCorrection`.

## The second blind spot this exposed

With the IL present, the frontier immediately selected `TouchCollection+Enumerator` as consumable —
which it is not. Its `Current` calls `TouchCollection::get_Item` and its `MoveNext` calls
`TouchCollection::get_Count`; its constructor takes a `TouchCollection`; and the type cannot even be
named without its declaring type. But no member *signature* mentions `TouchCollection`, and
signatures were all the analyzer looked at.

`analyze_dependencies.rb` now treats a nested type's declaring type as a public-signature
dependency. That is the same class of defect Foundation 26 closed one level up, where a constructed
generic hid its BCL definition behind an XNA type argument. With it, the pair classifies honestly:
neither is dependency-complete while the other is missing, and closing them means closing them
together.

## What now blocks the pair

`TouchCollection` is a read-only `IList<TouchLocation>`: its IL throws `NotSupportedException` from
`Insert`, `RemoveAt`, `Add`, `Clear`, `Remove` and the `Item` setter, and `IsReadOnly` answers true.
Six of its fifteen identities therefore depend on a Ruby mapping for
`System.NotSupportedException`, which `mapping-rules.json` does not have. Its thrown-exception
policy is settled — "the nearest Ruby exception with the same meaning, and one CLR exception always
maps to exactly one Ruby exception" — but the nearest Ruby exception is genuinely contested:
`NotImplementedError` is closest in meaning and is a `ScriptError`, which this project already
documents as a trap because a bare `rescue` does not catch it; `RuntimeError` and `FrozenError` are
each defensible and each say something the CLR exception does not.

That is a public mapping decision with more than one plausible incompatible answer and no rule
choosing between them, so it is recorded rather than taken. Affected identities:
`TouchCollection::Insert`, `RemoveAt`, `Add`, `Clear`, `Remove` and `Item=`. Deciding it closes 18
identities across the two types and moves `TouchPanel` to a single remaining blocker — a device.
