# Architecture

## Layers

`Microsoft::Xna::Framework` is the strict public facade. It contains only projected XNA types. `CNA::Runtime` owns float32 helpers, enum representation, ownership, generation/thread state, and callback trampolines. `CNA::Native` owns resolution, exact ABI admission, layouts, the single signature manifest, symbol binding, and result translation.

No facade class constructs a Fiddle function. No installed-gem path searches a sibling checkout. The native library remains an external CNA runtime responsibility.

## Lifetime graph

Game is an OWNED native root. GraphicsDeviceManager is an OWNED Game child. GraphicsDevice is PARENT_OWNED and its CNA handle is borrowed only during a lifecycle callback. Texture2D and SpriteBatch are OWNED Game-generation children that retain the Game and device facade. Callback tables and every Fiddle closure remain strongly referenced by GameHost until native destruction.

Game disposal runs children in reverse registration order, then the manager, then Game, and finally invalidates the generation. Double Dispose is idempotent. A wrong-thread destruction attempt fails before the handle is cleared, permitting owner-thread retry. A stale generation raises before native work.

## Callbacks

Every native callback verifies the Ruby owner thread, enters a thread-local current-Game scope, exposes the callback-borrowed graphics device, calls the overridable XNA member, and then removes callback scope. Any Ruby exception is retained and the callback returns `CNA_RESULT_CALLBACK`. GameHost re-raises the retained exception only after `cna_game_run` or `cna_game_run_one_frame` returns. No Ruby exception unwinds through C.

## Honest absence

An unavailable type or overload has no runtime method. The static contract and verifier report the gap. There are no catch-all stubs, simulated resources, hard-coded device dimensions, fabricated input snapshots, or no-op native methods.
