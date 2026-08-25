# XNA 4.0 Windows IL provenance

`xna40-windows-runtime-contract.json` pins the **public metadata** of the profile. This file pins
the **implementation authority** used to derive behaviour: the original Microsoft XNA Framework 4.0
Windows assemblies, identified by exact SHA-256.

No Microsoft binary is stored in this repository, and none is packaged into the gem. Only hashes,
assembly identities, derivation notes and derived behavioural facts are committed.

## Locating the assemblies

The assemblies are located **by hash, never by filename**. On a machine that carries them, the
durable copy used for this work is the sibling repository `openeggbert/xna4-decomp` at
`reference/xna4/original/windows/`. Any other copy with a matching SHA-256 is equally authoritative;
any copy whose SHA-256 does not match is not.

Point `XNA_REFERENCE_ASSEMBLIES` at a directory holding them and run:

```sh
ruby tools/api_compat/build_il_inventory.rb
```

The tool refuses to run unless every listed assembly is present with its exact pinned SHA-256. It
disassembles each with `ikdasm` (Debian package `ikdasm`) and writes the derived, Microsoft-free
inventory to `docs/generated/xna-il-inventory.json`.

## Pinned assemblies

Every assembly below is `Microsoft.Xna.Framework*`, version `4.0.0.0`, public key token
`842cf8be1de50553`, dated 2011-09-01.

| Assembly | Bytes | SHA-256 |
| --- | --- | --- |
| `Microsoft.Xna.Framework.dll` | 679424 | `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130` |
| `Microsoft.Xna.Framework.Graphics.dll` | 427520 | `560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55` |
| `Microsoft.Xna.Framework.Game.dll` | 74752 | `b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0` |
| `Microsoft.Xna.Framework.Input.Touch.dll` | 23040 | `b0585224c18022c3661057ae79544644c10f33f1dc529678364f3d6b25151c25` |
| `Microsoft.Xna.Framework.Xact.dll` | 75776 | `a14d5364dca7cf49fb90639e87ba04d52b59a700dc9198efa5707ce8eae28f0a` |
| `Microsoft.Xna.Framework.Storage.dll` | 20992 | `798f678e9ae3d9afc3bed66c30123bc9634fb923b6d200188344b618e608cbb8` |
| `Microsoft.Xna.Framework.Video.dll` | 17920 | `17538b1ca9d48a993e2cd88c96b436df08e7abb4aec5d4758eb21feb580d6e06` |
| `Microsoft.Xna.Framework.Net.dll` | 54272 | `39739dbf5f6ba02e1d0b02ed404f6fe0692497848bc1a6a25be132d47ed9c151` |
| `Microsoft.Xna.Framework.GamerServices.dll` | 73728 | `7c6effed97aa25a95c5e095d9c261f5581e402180cc073271a367b9eef79c8af` |
| `Microsoft.Xna.Framework.Avatar.dll` | 26624 | `b3c70bbe469000b9e11507cc63b88d54a4e0bc5c27afc826d66e0aee51640871` |

The two hashes the behaviour corpus already cited as `sourceAssemblySha256` — `38e7093f…` for
`Microsoft.Xna.Framework.dll` and `560080fc…` for `Microsoft.Xna.Framework.Graphics.dll` — are the
first two rows, so every earlier milestone's provenance claim is now verifiable rather than
asserted.

## Authority order

1. **Exact original binary + `ikdasm` IL** — the only implementation authority.
2. Hash-proven ILSpy C# reconstructions — readability and cross-checking only, never authority.
3. FNA, MonoGame, CNA, CNA-Go, CNA-Swift and every other reimplementation — comparators only, never
   authority.

Derived behavioural facts enter the repository as behaviour-corpus observations classified
`PURE_XNA_DERIVED`, with the deriving assembly's SHA-256 recorded on the milestone file.
