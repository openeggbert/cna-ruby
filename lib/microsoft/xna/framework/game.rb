# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # A sealed `Collection<IGameComponent>` with two events and four overridden hooks, and the
      # first shipped type in this binding whose CLR base is a projected BCL generic. Ruby has class
      # inheritance, so it really inherits from `CNA::Runtime::Collection` and the whole
      # `Collection<T>` public surface — `Count`, the indexer, `Add`, `Clear`, `Contains`, `CopyTo`,
      # `GetEnumerator`, `IndexOf`, `Insert`, `Remove`, `RemoveAt` — arrives by inheritance rather
      # than being flattened into unrelated methods here. The CLR type argument cannot live in the
      # superclass expression because a Ruby class is not statically generic, so it is declared as
      # metadata and the API verifier measures it.
      #
      # The type declares no public member of its own at all. Its whole contribution is four
      # `protected virtual` overrides and two events, which is exactly what `Collection<T>` was
      # designed for: every public mutation the base publishes routes through a hook, and these four
      # hooks are where the component rules live.
      class GameComponentCollection < CNA::Runtime::Collection
        extend CNA::Runtime::EventOwner

        projects_elements "Microsoft.Xna.Framework.IGameComponent"

        # `.ctor()` is one call to the base parameterless constructor, so the collection owns a
        # fresh backing list and never a caller's.
        def initialize
          super()
        end

        # The two CLR events. Both are `EventHandler<GameComponentCollectionEventArgs>`, and both
        # are raised only from the hooks below — the CLR's `OnComponentAdded`/`OnComponentRemoved`
        # are `private`, not `protected`, so neither is an identity a consumer or a subclass reaches.
        xna_event :ComponentAdded
        xna_event :ComponentRemoved

        protected

        # `InsertItem(int32, IGameComponent)`.
        #
        # Three steps, in this order:
        #
        #   1. `if (base.IndexOf(item) != -1) throw new ArgumentException(...)`. The duplicate check
        #      runs **before** the insertion and before any index validation the base performed, and
        #      it uses `IndexOf`, so it is element equality rather than identity. Its CLR message is
        #      the localized resource `CannotAddSameComponentMultipleTimes`, which is not reproduced.
        #   2. `base.InsertItem(index, item)` — the mutation.
        #   3. `if (item != null) OnComponentAdded(new GameComponentCollectionEventArgs(item))`.
        #
        # So the event fires **after** the collection already contains the component, and a null
        # component is inserted silently: the IL's null check guards the event, not the insertion.
        # A *second* null is still rejected by step 1, because `IndexOf(null)` finds the first one.
        def InsertItem(index, item)
          require_game_component!(item)
          raise ArgumentError if self.IndexOf(item) != -1

          super(index, item)
          raise_component_event(:ComponentAdded, item) unless item.nil?
          nil
        end

        # `RemoveItem(int32)`.
        #
        #   1. `item = base[index]` — read **before** the removal, through the base indexer, so an
        #      out-of-range index raises there rather than here.
        #   2. `base.RemoveItem(index)` — the mutation.
        #   3. `if (item != null) OnComponentRemoved(new GameComponentCollectionEventArgs(item))`.
        #
        # Same shape as InsertItem: mutation first, event second, null component silent.
        def RemoveItem(index)
          item = self[index]
          super(index)
          raise_component_event(:ComponentRemoved, item) unless item.nil?
          nil
        end

        # `SetItem(int32, IGameComponent)` is `newobj NotSupportedException; throw` and nothing else
        # — eleven bytes of IL with no branch. Its CLR message is the localized resource
        # `CannotSetItemsIntoGameComponentCollection`, which is not reproduced.
        #
        # The refusal is reached *through* `Collection<T>::set_Item`, which validates first, so the
        # order is observable: an out-of-range index raises `RangeError` and never gets here, and a
        # read-only backing list raises `NotSupportedError` from the base for a different reason.
        def SetItem(index, item)
          raise CNA::Runtime::NotSupportedError
        end

        # `ClearItems()`, and the one hook whose ordering is the opposite of the others:
        #
        #     for (i = 0; i < base.Count; i++) OnComponentRemoved(new ...(base[i]));
        #     base.ClearItems();
        #
        # Every event fires **before** any mutation, in index order, and `Count` is re-read on each
        # iteration — so a handler that adds a component during `Clear` extends the loop and that
        # component is announced as removed too, before being cleared with the rest.
        #
        # There is also no null check here, unlike the other two hooks: a null element produces a
        # `GameComponentCollectionEventArgs` carrying null and the event fires for it.
        def ClearItems
          index = 0
          while index < self.Count
            raise_component_event(:ComponentRemoved, self[index])
            index += 1
          end
          super()
          nil
        end

        private

        # `OnComponentAdded`/`OnComponentRemoved` are `private` in the CLR and each is the same four
        # instructions: a null check on the delegate, then `Invoke(this, eventArgs)`. The sender is
        # the collection and the args are freshly constructed per notification, so no two handlers
        # of two different notifications ever see the same args object.
        def raise_component_event(identity, component)
          public_send(identity)
            .__send__(:dispatch, self, GameComponentCollectionEventArgs.new(component))
          nil
        end

        # The CLR base is `Collection<IGameComponent>`, and that type argument is a static
        # constraint the CLR enforces at every entry point. A Ruby class is not statically generic,
        # so the constraint is carried as `projects_elements` metadata for the verifier and enforced
        # here at the one point every insertion passes through. This is the boundary check
        # `GameComponentCollectionEventArgs` already ships, on the same type and for the same
        # reason; null is admitted because `Collection<IGameComponent>` admits it.
        def require_game_component!(item)
          return if item.nil? || item.is_a?(IGameComponent)

          raise TypeError, "item must be an IGameComponent"
        end
      end

      class Game
        attr_reader :GraphicsDevice

        def initialize
          @owner_thread = Thread.current
          @generation = CNA::Runtime::Generation.new(@owner_thread)
          @host = nil
          @graphics_manager = nil
          @GraphicsDevice = nil
          @native_children = []
          @disposed = false
          @has_run = false
          @exit_requested = false
          @inside_native_callback = false
        end

        def Run
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          raise CNA::InvalidBindingStateError, "Game.Run may only be called once" if @has_run
          assert_owner_thread!
          ensure_host
          @has_run = true
          @host.run
          nil
        end

        def RunOneFrame
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          assert_owner_thread!
          ensure_host.run_one_frame
          nil
        end

        def Exit
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          @exit_requested = true
          @host&.request_exit
          nil
        end

        # Canonical overridable lifecycle hooks. Their base XNA behavior is no
        # user work; the real lifecycle and timing are driven by CNA callbacks.
        def Initialize = nil
        def LoadContent = nil
        def UnloadContent = nil
        def BeginRun = nil
        def EndRun = nil
        def Update(game_time) = require_game_time(game_time)
        def Draw(game_time) = require_game_time(game_time)
        def BeginDraw = true
        def EndDraw = nil

        def Dispose
          return if disposed?
          assert_owner_thread!
          first_error = nil
          @native_children.reverse_each do |child|
            begin
              child.Dispose
            rescue Exception => error
              first_error ||= error
            end
          end
          @native_children.clear
          begin
            @graphics_manager&.__send__(:dispose_native)
          rescue Exception => error
            first_error ||= error
          end
          begin
            @host&.destroy
          rescue Exception => error
            first_error ||= error
          end
          @generation.invalidate!
          @disposed = true
          raise first_error if first_error
          nil
        end

        protected :Initialize, :LoadContent, :UnloadContent, :BeginRun, :EndRun,
                  :Update, :Draw, :BeginDraw, :EndDraw

        private

        attr_reader :owner_thread, :generation

        def disposed? = @disposed
        def __cna_exiting = nil

        def attach_graphics_manager(manager)
          raise ArgumentError, "a Game accepts exactly one GraphicsDeviceManager" if @graphics_manager
          @graphics_manager = manager
          @GraphicsDevice = manager.GraphicsDevice
        end

        def ensure_host
          return @host if @host
          @host = CNA::Runtime::GameHost.new(self)
          @host.create
          @graphics_manager&.__send__(:create_native, @host.handle)
          @host.request_exit if @exit_requested
          @host
        rescue Exception => error
          begin
            @graphics_manager&.__send__(:dispose_native)
          rescue Exception
            # Preserve the creation error; all reachable handles retain their
            # normal explicit-disposal retry semantics.
          end
          begin
            @host&.destroy
          rescue Exception
            # Preserve the creation error at this boundary.
          end
          @host = nil
          raise error
        end

        def begin_native_callback
          @inside_native_callback = true
          @graphics_manager&.__send__(:begin_native_callback)
        end

        def end_native_callback
          @graphics_manager&.__send__(:end_native_callback)
          @inside_native_callback = false
        end

        def register_native_child(child)
          @native_children << child unless @native_children.any? { |value| value.equal?(child) }
        end

        def unregister_native_child(child)
          @native_children.reject! { |value| value.equal?(child) }
        end

        def assert_owner_thread! = @generation.assert_owner_thread!
        def require_game_time(value)
          raise TypeError, "game_time must be GameTime" unless value.instance_of?(GameTime)
        end
      end

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # A four-identity managed container over one private `Dictionary<Type, object>`. It reaches no
      # native entry point, holds no unmanaged resource and needs no `Game`: its constructor is
      # public, so unlike most of the Game family a caller can make one and use it directly. What it
      # is *for* is `Game.Services`, which is one of the six deferred partial runtime types, so
      # nothing in this binding populates one.
      #
      # `System.Type` is a service key here, and in every one of the twenty-four places the XNA
      # surface names it, so it projects to a Ruby `Module` — a `Class` is one. The single operation
      # the IL performs on it, `type.IsAssignableFrom(provider.GetType())`, is exactly Ruby's
      # `provider.is_a?(type)`, and the dictionary's default comparer is reference equality, which
      # is what a Ruby Hash gives a Module key.
      #
      # `System.IServiceProvider` declares one member, `GetService(Type)`, which this type already
      # declares publicly. Ruby has no interfaces, so no constant is invented for it and the contract
      # survives as that member — the same collapse `ExternalException` takes, for the same reason:
      # inventing a Ruby identity the CLR surface never names would be unmeasurable.
      #
      # All four exception messages in the IL are localized `Resources` strings, so none is
      # reproduced; the Ruby message is the CLR's parameter name, as everywhere else in this
      # binding. `AddService`'s assignability failure names no parameter at all, and its CLR message
      # carries a Microsoft bug worth recording rather than copying: the second format argument is
      # `type.GetType().FullName`, the type *of the Type object*, where every reading of the message
      # expects `type.FullName`.
      class GameServiceContainer
        def initialize
          @services = {}
        end

        # `type == null` -> ArgumentNullException("type"); `provider == null` ->
        # ArgumentNullException("provider"); an already-registered key -> ArgumentException naming
        # "type"; a provider the key is not assignable from -> ArgumentException naming nothing.
        # Then one `Dictionary.Add`.
        def AddService(type, provider)
          require_service_type!(type)
          raise ArgumentError, "provider" if provider.nil?
          raise ArgumentError, "type" if @services.key?(type)
          raise ArgumentError unless provider.is_a?(type)

          @services[type] = provider
          nil
        end

        # `Dictionary.Remove` and the result is popped, so removing a key that was never added is
        # harmless and answers nothing.
        def RemoveService(type)
          require_service_type!(type)
          @services.delete(type)
          nil
        end

        # `ContainsKey` then the indexer, else `ldnull`: an absent service answers nil rather than
        # raising, which is the one place this type differs from the dictionary it wraps.
        def GetService(type)
          require_service_type!(type)
          @services[type]
        end

        private

        # Every one of the three members opens with the same null check on the same parameter.
        def require_service_type!(type)
          raise ArgumentError, "type" if type.nil?
          raise TypeError, "type must be a Module" unless type.is_a?(::Module)

          type
        end
      end
    end
  end
end
