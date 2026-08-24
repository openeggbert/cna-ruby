# Native ABI Qualification

The Foundation 1 admission policy retained unchanged through Foundation 4 admits exactly CNA C ABI 0.7.0 (`0x00000700`). Newer 0.x and same-major versions are rejected until separately reviewed.

The retained qualification artifact used for this milestone is:

- CNA source revision: `a09196a6477f69a7a57c8364f990658d31531a5b`
- library: external `libcna_c_api.so`
- SHA-256: `c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`
- platform: Linux x86-64
- renderer: HEADLESS
- audio: NULL

It is not bundled and its temporary qualification location is not a runtime default. Consumers set `CNA_NATIVE_LIBRARY` to an absolute path. Production resolution then considers a future package-native directory and platform dynamic-loader names; it never searches developer sibling repositories.

The reviewed manifest records exact C type names, pointer depth, constness, fixed width, signedness, CNA_Bool/enum representation, ownership, result lifetime, and callbacks. `tools/native_abi/verify.rb` compiles an independent C probe against canonical headers, compares structure size/alignment/offsets and constants with Ruby declarations, type-checks every function/callback prototype, and checks exports in the actually loaded library.

`cna_viewport_get_title_safe_area` is intentionally not bound: its canonical prototype passes `CNA_Viewport` by value, a contract this Fiddle-only foundation does not claim to marshal portably.
