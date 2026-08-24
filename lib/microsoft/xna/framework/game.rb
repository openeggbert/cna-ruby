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
    end
  end
end
