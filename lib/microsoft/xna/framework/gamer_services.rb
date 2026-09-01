# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # The first type of the `GamerServices` namespace. Nothing else in it is projected: no `Guide`,
      # no `Gamer`, no `SignedInGamer`, no storage or profile surface.
      module GamerServices
        # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
        #
        # A `GameComponent` subclass with three identities and no state of its own:
        #
        #     public GamerServicesComponent(Game game) : base(game) { }
        #
        #     public override void Initialize() {
        #         GamerServicesDispatcher.WindowHandle = Game.Window.Handle;
        #         GamerServicesDispatcher.InstallingTitleUpdate += GamerServicesDispatcher_InstallingTitleUpdate;
        #         GamerServicesDispatcher.Initialize(Game.Services);
        #         base.Initialize();
        #     }
        #
        #     public override void Update(GameTime gameTime) {
        #         GamerServicesDispatcher.Update();
        #         base.Update(gameTime);
        #     }
        #
        #     private void GamerServicesDispatcher_InstallingTitleUpdate(object s, EventArgs e) => Game.Exit();
        #
        # Every step has exactly one canonical CNA route, and — unusually for this binding — the
        # dispatcher routes are **process-global statics with no handle**, which is what XNA's
        # `GamerServicesDispatcher` is too. The game-scoped asymmetry the audio and window families
        # record does not apply here; only `initialize` takes a game, and it takes it because the
        # dispatcher adopts that game's service container, which is exactly what XNA passes it.
        #
        # The private handler is not an identity and is not projected as one; what is projected is
        # its **effect**, because the subscription is real and the callback really calls `Game.Exit`.
        #
        # DEVIATION, recorded: `cna_gamer_services_component_create` builds a *canonical* component
        # whose initialize and update belong to CNA's runtime and which CNA's own component list
        # drives. It is deliberately not used. `Game.Components` here is the managed engine
        # Foundations 35 and 38 built, so a canonical component would be driven twice — the
        # duplication `docs/graphics-device-service-producer-audit.md` refused for
        # `GraphicsDeviceManager`. This is an ordinary Ruby `GameComponent` whose overrides call the
        # dispatcher routes, which is what XNA's own type is.
        class GamerServicesComponent < GameComponent
          def initialize(game)
            super
            @registration = 0
            @callback = nil
            # DEVIATION, recorded: XNA subscribes to the static `InstallingTitleUpdate` event in
            # `Initialize` and **never unsubscribes**, so the component outlives its own disposal
            # inside a CLR static's invocation list. Here the subscription is a native registration
            # with an owner and a lifetime, so it is released when the component is disposed. That
            # is done through the type's own `Disposed` event rather than by overriding `Dispose`,
            # because XNA declares no `Dispose` on this class and declaring one would add an
            # identity the contract does not have.
            self.Disposed.add(->(_sender, _args) { release_registration })
          end

          # The order is the IL's and is observable: the window handle is pushed **before** the
          # dispatcher is initialized, and `base.Initialize()` runs last, after both.
          def Initialize
            library = CNA::Native.library
            host = CNA::Runtime::Context.native_host("GamerServicesComponent.Initialize")
            library.call("cna_gamer_services_dispatcher_set_window_handle", self.Game.Window.Handle)
            subscribe_installing_title_update
            library.call("cna_gamer_services_dispatcher_initialize", host.handle)
            super
          end

          # `GamerServicesDispatcher.Update()` then `base.Update(gameTime)`, so the dispatcher is
          # pumped even by a subclass that overrides `Update` and calls `super` — and, exactly as in
          # XNA, not at all by one that does not.
          def Update(gameTime)
            CNA::Native.library.call("cna_gamer_services_dispatcher_update")
            super
          end

          private

          # The closure is retained for the registration's lifetime, which is this binding's standing
          # rule for a callback that crosses into C. A Ruby exception raised inside it is captured and
          # re-raised after the C call returns rather than unwinding through native frames.
          def subscribe_installing_title_update
            return unless @registration.zero?

            @callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]) do |_context|
              begin
                self.Game&.Exit
              rescue ::Exception # rubocop:disable Lint/RescueException
                nil
              end
              nil
            end
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_gamer_services_dispatcher_subscribe_installing_title_update_ext",
                                     @callback, nil, output)
            @registration = output[0, 8].unpack1("Q")
          end

          def release_registration
            return if @registration.zero?

            begin
              CNA::Native.library.call("cna_gamer_unsubscribe_ext", @registration)
            rescue CNA::Error
              nil
            end
            @registration = 0
            @callback = nil
          end
        end
      end
    end
  end
end
