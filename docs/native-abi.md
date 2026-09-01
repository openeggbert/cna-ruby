# Native ABI Qualification

## Admission policy

CNA-Ruby admits **the set of encoded CNA C ABI versions whose whole bound surface it has measured
with a compiler**, currently `0.7.0` (`0x00000700`) and `0.21.0` (`0x00001500`). It is deliberately
neither "the same major" nor "a minimum minor" nor a single frozen number; the derivation from CNA's
own `docs/c-api/ABI_VERSIONING.md`, and the compiler-backed measurement that both versions are
byte-identical over this binding's surface, are in `docs/native-abi-migration-evidence.md`.

The set is enforced in two places. `CNA::Native::Library` refuses a library whose
`cna_get_abi_version()` is outside it, naming the admitted set, the version found and the library
path. `tools/native_abi/verify.rb` requires every admitted version's headers to declare an admitted
`CNA_ABI_VERSION` and to agree with every other root on every other measurement, so the policy is
re-derived on each run instead of being asserted.

`CNA_ABI_VERSION` is not in `Manifest::CONSTANTS`. It is not a constant this binding consumes, it is
the identity this binding gates on, and it is the one measurement two admitted versions may
legitimately disagree about.

## The qualification artifact

- CNA source revision: `cnanext` `0a6158e4ff764907065cd7259e3d29e331a52088` (branch `next`)
- library: external `libcna_c_api.so`, pinned at `~/deps/cna-c-abi-0.21.0/libcna_c_api.so`
- SHA-256: `c32bfbd307d695664f906ccf2834ec3f9ebc240fa388d544ac21ee3ebaeb731b`
- headers: 61 files, tree digest `1342fdbb24c654352ebac6b7381ee2a6dafeae6ec413c2c5ec4e653325704850`
- platform: Linux x86-64, `CNA_PLATFORM=SDL3`
- renderer: `HEADLESS` (a build-time selection; the runtime `CNA_GRAPHICS_RENDERER` override can
  only choose a renderer compiled in)
- audio: `SDL3`

The retired artifact was CNA revision `a09196a6477f69a7a57c8364f990658d31531a5b`, SHA-256
`c62949d23d3745964f5e557a06665875621ed4cb6e2930e3f282afd5911f2dcb`, built with the `HEADLESS`
*platform* and the null audio backend. It remains admitted by version and is no longer the qualified
artifact.

Neither artifact is bundled and neither location is a runtime default. Consumers set
`CNA_NATIVE_LIBRARY` to an absolute path. Production resolution then considers a future
package-native directory and platform dynamic-loader names; it never searches developer sibling
repositories.

The reviewed manifest records exact C type names, pointer depth, constness, fixed width, signedness,
CNA_Bool/enum representation, ownership, result lifetime, and callbacks. `tools/native_abi/verify.rb`
compiles an independent C probe against canonical headers, compares structure size/alignment/offsets
and constants with Ruby declarations, type-checks every function/callback prototype, and checks
exports in the actually loaded library. `test/test_native_abi_gate.rb` proves the gate fails, one
planted defect at a time.

## Historical deltas

Foundation 6 binds four already-existing reviewed functions and no adjacent input API: `cna_mouse_get_state`, `cna_mouse_set_position`, `cna_mouse_get_window_handle`, and `cna_mouse_set_window_handle`. It measures the complete `CNA_MouseState` layout and the five consumed button-bit constants. The compiler-backed delta is 30 -> 34 bound functions, 90 -> 103 signature measurements, 158 -> 176 C layout measurements, 158 -> 176 Ruby layout measurements, 2 -> 2 callbacks, and 12 -> 17 constants. Missing header symbols, missing library symbols, and ABI mismatches remain zero.

Foundation 7 binds exactly four already-existing canonical controller routes and no adjacent
extension API: `cna_gamepad_get_state`, `cna_gamepad_get_state_with_dead_zone`,
`cna_gamepad_get_capabilities`, and `cna_gamepad_set_vibration`. The compiler measures
`CNA_Vector2`, `CNA_GamePadAnalogState`, `CNA_GamePadState`, and
`CNA_GamePadCapabilities`, including every field and reserved byte. Forty-two consumed constants
cover four player slots, three dead-zone modes, 25 XNA button bits, and ten CNA device types.

The exact Foundation 6 -> 7 delta is 34 -> 38 bound functions, 103 -> 122 signature
measurements, 176 -> 290 C layout measurements, 176 -> 290 Ruby layout measurements, 2 -> 2
callbacks, and 17 -> 59 constants. `MISSING_HEADER_SYMBOLS`, `MISSING_LIBRARY_SYMBOLS`, and
`ABI_MISMATCHES` are all zero. CNA extension buttons, sensors, GUID/name, battery, LED, touchpad,
and trigger-rumble APIs are deliberately not bound.

`cna_viewport_get_title_safe_area` is intentionally not bound: its canonical prototype passes `CNA_Viewport` by value, a contract this Fiddle-only foundation does not claim to marshal portably.

## Native frontier 1: the framework dispatcher

This milestone binds exactly one already-existing canonical route and no adjacent API:
`cna_framework_dispatcher_update`. It measures no new structure and consumes no new constant, so
the delta touches only the function and signature counts.

The exact Foundation 7 -> Native frontier 1 delta is 38 -> 39 bound functions, 122 -> 124
signature measurements, 290 -> 290 C layout measurements, 290 -> 290 Ruby layout measurements,
2 -> 2 callbacks, and 59 -> 59 constants. `MISSING_HEADER_SYMBOLS`, `MISSING_LIBRARY_SYMBOLS`, and
`ABI_MISMATCHES` are all zero. Every measurement carried over from Foundation 7 is byte- and
signature-identical: the manifest entry was inserted, nothing existing was edited, and the probe
type-checks all 39 prototypes against the same canonical headers.

The qualification artifact of that milestone was unchanged. **No CNA source change was made and no new
native binary was built**, because the audit that opened this milestone found the canonical C ABI
already exposes everything the milestone needed — see
`docs/graphics-adapter-audit-evidence.md`, which also records why the same is true of the
GraphicsAdapter surface this session set out to reach.

`cna_framework_dispatcher_update(CNA_Handle game)` takes the game handle for thread affinity only;
the canonical dispatcher behind it is static. It answers `CNA_RESULT_SUCCESS` inside and outside a
lifecycle callback, `CNA_RESULT_INVALID_HANDLE` for a zero or unknown handle, and
`CNA_RESULT_THREAD` off the owner thread — each observed against the retained artifact before the
route was bound.

## The title surface

The `System.IO.Stream` projection binds four already-existing canonical routes and no adjacent
storage API: `cna_title_location_get_path_size`, `cna_title_location_copy_path`,
`cna_title_location_set_path_ext` and `cna_title_container_read_ext`. The delta is 68 -> 72 bound
functions and 219 -> 238 signature measurements; no structure, callback or constant is added, and
every other measurement is byte-identical. `MISSING_HEADER_SYMBOLS`, `MISSING_LIBRARY_SYMBOLS`,
`CROSS_VERSION_MISMATCHES` and `ABI_MISMATCHES` stay zero, and all four routes are exported by
**both** admitted versions, so the admitted set does not shrink.

`cna_title_container_read_ext` is a count/copy pair rather than a stream handle, by CNA's own
documented design: this ABI has no stream handle for title content. The sizing call answers
`CNA_RESULT_BUFFER_TOO_SMALL` rather than success for any non-empty file — a zero capacity is
smaller than any file — and still writes `out_bytes`, so the projection accepts that result as the
documented answer and treats only `CNA_RESULT_IO` as the missing-file refusal.

`cna_title_location_set_path_ext` is bound for a reason worth stating: the canonical accessor
resolves the **executable's** directory, which under a Ruby interpreter is the interpreter's, so
without the override no title read could be qualified against a fixture at all. CNA documents the
override as process-wide rather than scoped to the game handle it validates.

The three `storage.h` stream handles — `cna_storage_container_open_file` and its two siblings, plus
`cna_storage_container_create_file` — are deliberately **not** bound. They are the producer for
XNA's `StorageContainer`, which is a different type and a different lifetime; the audit is in
`docs/stream-projection-design.md`.

## The content surface

The `ContentManager` projection binds eight already-existing canonical routes and no adjacent
content API, chosen against the whole 32-route `content.h` because each is what one member of the
selected contract needs: `cna_game_get_content_manager_ext`, `cna_content_manager_create`,
`..._destroy`, the root-directory count/copy pair, `..._set_root_directory`, `..._unload` and
`..._load_texture2d`. The delta is 72 -> 80 bound functions, 238 -> 266 signature measurements and
18 -> 19 layouts; `CNA_ContentManagerCreateInfo` is the new one, measured 32 bytes at alignment 8
with its embedded `CNA_StringView` at offset 8. No callback and no constant is added, every other
measurement is byte-identical, and every route is exported by both admitted versions, so the
admitted set does not shrink.

Two ownerships, deliberately different. `cna_game_get_content_manager_ext` is **BORROWED**: a CNA
game owns exactly one content manager as a value member, so the route answers the same handle every
time, must never be destroyed, and dies with the game. `cna_content_manager_create` is **OWNED** and
must be destroyed before its game — and it takes a **graphics device**, which is why a standalone
`ContentManager` cannot create one lazily without a service this binding registers no producer for.

Deliberately not bound, each for a stated reason recorded beside the manifest entries:
`create_resource` (its own header records that every load through it fails today, the canonical
embedded-resource stream being a declared placeholder); `load_sound_effect`, `load_texture_cube`,
`load_sprite_font` and `load_foreign_ext` (no `SoundEffect`, `TextureCube`, `SpriteFont` or custom
reader is projected, and a materializer for a type this binding does not have would be unreachable);
`set_content_manager_ext` (the canonical setter copies where XNA's `Game.Content` setter replaces a
reference); the asset-path and normalized-key pairs (CNA's key case-folds but does not collapse `./`
or `../`, while XNA's cache key is `TitleContainer.GetCleanPath` under an ordinal-ignore-case
comparer, so the projection must compute XNA's and cannot consult CNA's); the manifest and
reader-usage families (diagnostics with no XNA identity); and `register_builtin_loaders` (creation
already performs it).

## The audio surface

The `SoundEffect` cluster binds 35 canonical routes -- the whole `audio.h` surface those two types
reach and nothing beyond it. The delta is 80 -> 115 bound functions, 266 -> 391 signature
measurements and 19 -> 23 layouts: `CNA_SoundEffectCreateInfo` (24/8), `CNA_SoundEffectInstanceInfo`
(32/4), `CNA_AudioListener` (56/4) and `CNA_AudioEmitter` (60/4), the last two differing by the
emitter's own `doppler_scale` ahead of the four shared `CNA_Vector3` fields. No callback and no
constant is added, and every route is exported by both admitted versions.

Two routes take **no handle at all**: `cna_sound_effect_get_sample_duration_ticks` and
`cna_sound_effect_get_sample_size_in_bytes` are pure computations, which is why the two static
members that use them are the only ones in the type that work with no Game. Four take the **game**
handle where XNA's counterparts are CLR statics -- the master volume, distance scale, doppler scale
and speed of sound -- and that asymmetry is recorded on the type rather than hidden.

Deliberately not bound: `cna_sound_effect_create_from_asset_ext` (that is `Load<SoundEffect>`, and no
content reader for it is registered), the whole `cna_dynamic_sound_effect_instance_*` family and
`cna_audio_unsubscribe_ext` (no `DynamicSoundEffectInstance` is projected), every
`cna_microphone_*` route, and the type-name count/copy pairs, which answer a .NET type name that
Ruby's own `class` already carries. The first two of those exclusions were retired by later
milestones; the type-name pairs are still not bound.

## The device texture collections

`cna_graphics_device_get_texture` and `cna_graphics_device_set_texture` bring the count to 117 and
the layouts to 24, adding `CNA_TextureSlotInfo` (24/8) and three constants —
`CNA_SHADER_STAGE_PIXEL`, `CNA_SHADER_STAGE_VERTEX` and
`CNA_TEXTURE_COLLECTION_MAX_TEXTURES` = 16.

Worth recording for its own sake: Native frontier 4 concluded that `Graphics.TextureCollection` was
"the one case where `NATIVE_RUNTIME` was the right word — no CNA route at all". Both routes are
exported by the **retired 0.7.0 artifact** as well, so no version difference explains it. That
deferral was simply mistaken.

`cna_graphics_device_unbind_texture` is deliberately not bound: XNA's collection has no member that
unbinds one texture from every slot, so there is no identity for the route to carry.

## The gamer-services dispatcher

Five routes and a fourth callback bring the count to 122. All but
`cna_gamer_services_dispatcher_initialize` are **process-global statics with no handle**, which is
what XNA's `GamerServicesDispatcher` is too — so the game-scoped asymmetry the audio and window
families record does not apply here. `initialize` takes a game because the dispatcher adopts that
game's service container, which is exactly what XNA passes it.

`CNA_GamerAsyncCallback` is shape-identical to `CNA_GameEventCallback` — `void (*)(void*)` — and is
still a separate callback identity, because it is a different typedef in a different header and the
probe type-checks each against its own declaration rather than against the other.

`cna_gamer_services_component_create` is deliberately not bound: it builds a *canonical* component
that CNA's own component list drives, and this binding's `Game.Components` is the managed engine, so
one would be driven twice.

## The streaming audio instance

Eight routes and a fifth callback bring the count to 130.
`cna_dynamic_sound_effect_instance_create` is **game-parented** where an ordinary instance is
effect-parented, which is the ABI's own shape: a streaming instance has no `SoundEffect` behind it.

`CNA_AudioEventCallback` is the third `void (*)(void*)` typedef bound here, after
`CNA_GameEventCallback` and `CNA_GamerAsyncCallback`. Each stays a separate callback identity
because each is a different typedef in a different header, and the probe type-checks every one
against its own declaration rather than against the others.

`cna_dynamic_sound_effect_instance_update_ext` is deliberately not bound, and the reason is stronger
than "no XNA identity": it is the per-instance half of a pump `cna_framework_dispatcher_update`
already drives, and `FrameworkDispatcher.Update` is the projected member that drives it. Binding it
would give this binding two pumps for one queue. `submit_float_buffer_ext` and `clear_buffers_ext`
have no XNA identity at all.

## The microphone family

Sixteen routes bring the count to 146, and three constants — `CNA_MICROPHONE_STATE_STARTED` (0),
`CNA_MICROPHONE_STATE_STOPPED` (1) and `CNA_MICROPHONE_STATE_MAXIMUM` — bring those to 71. No new
callback: `cna_microphone_subscribe_buffer_ready_at` reuses `CNA_AudioEventCallback`, and its
registration is released with the `cna_audio_unsubscribe_ext` the streaming instance already bound.

This family is the first in the binding with **no handle of its own**. Every route is
`(CNA_Handle game, uint64_t index, …)`, addressing a device by its position in the machine's list,
because CNA's runtime owns the device — which `audio.h` says in as many words. So the Ruby side
carries a `BORROWED_EXTERNAL_SCALAR` index, there is nothing to destroy, and the one route that
looks like a release, `cna_microphone_stop_at`, is a state change.

The single route that is neither game- nor index-addressed is
`cna_microphone_check_all_buffers_ext`, which takes the game alone: it is the capture-side pump, and
it is bound for the same reason its playback counterpart is.

Two routes are bound and **deliberately not used by the projection**:
`cna_microphone_get_sample_duration_ticks_at` and `cna_microphone_get_sample_size_in_bytes_at`
measurably disagree with XNA's own managed arithmetic — 8818 against 8820 bytes for 100 ms at
44 100 Hz, and a duration that truncates where `TimeSpan.FromMilliseconds` rounds. Binding them is
what lets a test assert the divergence instead of a document describing it;
`docs/microphone-evidence.md` §3 has the table. `cna_microphone_get_is_headset_at` is bound on the
same footing, because XNA's `IsHeadset` is an unconditional `true` and CNA's answer is the device's.

Native frontier 4 recorded this family `NATIVE_RUNTIME`. Every one of the sixteen routes is exported
and declared identically by the **retired 0.7.0 headers**, which the gate's cross-version check
proves, and the host really has three capture devices. That deferral was about neither the ABI nor
the machine.
