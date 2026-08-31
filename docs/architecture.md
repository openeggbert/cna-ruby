# Architecture

## Layers

`Microsoft::Xna::Framework` is the strict public facade. It contains only projected XNA types. `CNA::Runtime` owns float32 helpers, enum representation, the event subscription primitive and its `EventArgs`, the BCL projection register, ownership, generation/thread state, and callback trampolines. `CNA::Native` owns resolution, exact ABI admission, layouts, the single signature manifest, symbol binding, and result translation.

A projected BCL identity lives in `CNA::Runtime`, never in a fabricated Ruby `::System` namespace, and `CNA::Runtime::BclProjection` is the single measured register of which BCL identities are projected at all. The API verifier resolves every register entry and the dependency frontier consumes the same register, so the two cannot disagree about what is mapped.

No facade class constructs a Fiddle function. No installed-gem path searches a sibling checkout. The native library remains an external CNA runtime responsibility.

## Lifetime graph

Game is an OWNED native root. GraphicsDeviceManager is an OWNED Game child. GraphicsDevice is PARENT_OWNED and its CNA handle is borrowed only during a lifecycle callback. Texture2D and SpriteBatch are OWNED Game-generation children that retain the Game and device facade. Callback tables and every Fiddle closure remain strongly referenced by GameHost until native destruction.

Game disposal runs children in reverse registration order, then the manager, then Game, and finally invalidates the generation. Double Dispose is idempotent. A wrong-thread destruction attempt fails before the handle is cleared, permitting owner-thread retry. A stale generation raises before native work.

## Callbacks

Every native callback verifies the Ruby owner thread, enters a thread-local current-Game scope, exposes the callback-borrowed graphics device, calls the overridable XNA member, and then removes callback scope. Any Ruby exception is retained and the callback returns `CNA_RESULT_CALLBACK`. GameHost re-raises the retained exception only after `cna_game_run`, `cna_game_run_one_frame` or `cna_game_tick` returns. No Ruby exception unwinds through C.

## Events

One CLR public event projects to one public Ruby event reader keeping the XNA spelling, whose value is a `CNA::Runtime::Event`. That object's whole public surface is `add`/`remove`; `dispatch` is private, so raising an event is available only to the declaring implementation and never to a consumer. `CNA::Runtime::EventOwner` is the only sanctioned way to declare an event identity, which is what lets the verifier measure selected event identities rather than trust that a reader happens to exist. Seventeen identities are declared across six owner types. Two owners are abstract contracts whose readers raise `NotImplementedError` (`IUpdateable`, `IDrawable`), one is a contract nothing here implements (`Graphics::IGraphicsDeviceService`), and three really raise: `GameComponentCollection`, `GameComponent` and `Game`. `Game` raises `Activated`, `Deactivated` and `Exiting` from CNA's own game-event subscriptions through the protected raisers XNA declares, and raises `Disposed` inline from `Dispose`.

## Honest absence

An unavailable type or overload has no runtime method. The static contract and verifier report the gap. There are no catch-all stubs, simulated resources, hard-coded device dimensions, fabricated input snapshots, or no-op native methods.
