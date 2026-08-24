# frozen_string_literal: true

require "fiddle"

module CNA
  module Runtime
    class GameHost
      CALLBACK_FAILURE = 9
      TICKS_PER_SECOND = 10_000_000

      attr_reader :handle, :pending_exception

      def initialize(game)
        @game = game
        @library = CNA::Native.library
        @handle = 0
        @pending_exception = nil
        @callbacks_keepalive = []
        @callback_buffers = []
        build_callback_tables
      end

      def create
        info = CNA::Native::Layouts::GameCreateInfo.new(
          fixed: true,
          target_ticks: 166_667,
          title: "CNA-Ruby",
          callbacks: @callbacks
        )
        output = @library.pointer_for("Q", 0)
        @library.call("cna_game_create", info.pointer, output)
        @handle = output[0, 8].unpack1("Q")
        @library.call("cna_game_set_frame_hooks_ext", handle, @hooks.pointer)
        CNA::Runtime::Context.register(@game)
      rescue Exception
        destroy if @handle != 0
        raise
      end

      def run
        finish(@library.function("cna_game_run").call(handle), "cna_game_run")
      end

      def run_one_frame
        finish(@library.function("cna_game_run_one_frame").call(handle), "cna_game_run_one_frame")
      end

      def request_exit
        @library.call("cna_game_request_exit", handle)
      end

      def destroy
        return if handle.zero?

        result = @library.function("cna_game_destroy").call(handle)
        if result.zero? || result == CALLBACK_FAILURE
          @handle = 0
          CNA::Runtime::Context.unregister(@game)
        end
        finish(result, "cna_game_destroy") unless result == CALLBACK_FAILURE && pending_exception.nil?
      end

      private

      def finish(result, operation)
        if pending_exception
          exception = @pending_exception
          @pending_exception = nil
          raise exception
        end
        @library.check(result, operation)
      end

      def lifecycle(name, takes_time: false)
        callback = Fiddle::Closure::BlockCaller.new(
          Fiddle::TYPE_UINT32_T,
          [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]
        ) do |_game_handle, time_pointer, _context, _error|
          safely(name) do
            argument = takes_time ? game_time(time_pointer) : nil
            takes_time ? @game.__send__(name, argument) : @game.__send__(name)
          end
        end
        @callbacks_keepalive << callback
        callback
      end

      def begin_draw
        callback = Fiddle::Closure::BlockCaller.new(
          Fiddle::TYPE_UINT32_T,
          [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]
        ) do |_game_handle, _time_pointer, _context, should_draw_pointer, _error|
          safely("BeginDraw") do
            value = @game.__send__(:BeginDraw)
            raise TypeError, "Game.BeginDraw must return true or false" unless value == true || value == false
            Fiddle::Pointer.new(should_draw_pointer)[0, 1] = [value ? 1 : 0].pack("C")
          end
        end
        @callbacks_keepalive << callback
        callback
      end

      def safely(name)
        return CALLBACK_FAILURE if pending_exception
        unless Thread.current.equal?(@game.__send__(:owner_thread))
          @pending_exception = CNA::OwnerThreadError.new("CNA invoked #{name} off the Game owner thread")
          return CALLBACK_FAILURE
        end

        @game.__send__(:begin_native_callback)
        CNA::Runtime::Context.enter(@game) { yield }
        0
      rescue Exception => exception
        @pending_exception ||= exception
        CALLBACK_FAILURE
      ensure
        @game.__send__(:end_native_callback)
      end

      def game_time(address)
        numeric_address = address.nil? ? 0 : address.to_i
        return Microsoft::Xna::Framework::GameTime.new if numeric_address.zero?

        value = CNA::Native::Layouts::GameTime.new
        value.pointer[0, value.class.size] = Fiddle::Pointer.new(numeric_address)[0, value.class.size]
        Microsoft::Xna::Framework::GameTime.new(
          value.read_i64(0).fdiv(TICKS_PER_SECOND),
          value.read_i64(8).fdiv(TICKS_PER_SECOND),
          value.read_u8(16) != 0
        )
      end

      def build_callback_tables
        load_content = lifecycle("LoadContent")
        update = lifecycle("Update", takes_time: true)
        draw = lifecycle("Draw", takes_time: true)
        unload_content = lifecycle("UnloadContent")
        exiting = lifecycle("__cna_exiting")
        @callbacks = CNA::Native::Layouts::GameCallbacks.new(
          [load_content, update, draw, unload_content, exiting]
        )
        @hooks = CNA::Native::Layouts::GameFrameHooks.new(
          [lifecycle("Initialize"), lifecycle("BeginRun"), lifecycle("EndRun"), begin_draw, lifecycle("EndDraw")]
        )
      end
    end
  end
end
