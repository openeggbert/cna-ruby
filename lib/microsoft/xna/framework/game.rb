# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
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
