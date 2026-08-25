# frozen_string_literal: true

require "fiddle"

module CNA
  module Runtime
    class GameHost
      CALLBACK_FAILURE = 9
      TICKS_PER_SECOND = 10_000_000

      attr_reader :handle, :pending_exception

      # The three canonical Game events CNA raises, and the protected raiser each one drives.
      #
      # `CNA_GAME_EVENT_DISPOSED` is deliberately absent: `Game#Dispose` raises `Disposed` itself,
      # because that signal only exists once a host does and XNA raises the event for every
      # disposal, including one on a Game that never ran.
      #
      # `CNA_GameCallbacks::exiting` is deliberately *not* used for `Exiting` either, and that is a
      # measured decision rather than a stylistic one: the callback fires on every teardown --
      # including `RunOneFrame` that never exited, and a Game destroyed without ever running --
      # while XNA raises `Game.Exiting` only when the host actually exits its loop. The C ABI says
      # as much, noting the callback "can stop the game by failing, while these handlers only
      # observe". The observer is the faithful source; the veto-capable callback is not.
      GAME_EVENTS = {
        "CNA_GAME_EVENT_ACTIVATED" => :OnActivated,
        "CNA_GAME_EVENT_DEACTIVATED" => :OnDeactivated,
        "CNA_GAME_EVENT_EXITING" => :OnExiting
      }.freeze

      def initialize(game)
        @game = game
        @library = CNA::Native.library
        @handle = 0
        @pending_exception = nil
        @callbacks_keepalive = []
        @callback_buffers = []
        @event_registrations = []
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
        subscribe_game_events
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

        unsubscribe_game_events
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

      # Each callback invokes the **virtual** Ruby method once. A subclass override runs; the base
      # runs only if that override calls `super`, exactly as a CLR override chooses whether and when
      # to call `base.Update(gameTime)`. The host never runs the base implementation itself, so a
      # subclass that omits `super` really does suppress the base component pass.
      #
      # `after:` carries the one piece of driver bookkeeping XNA's `RunGame` performs around a
      # lifecycle call rather than inside it -- see `in_run` below.
      def lifecycle(name, takes_time: false, after: nil)
        callback = Fiddle::Closure::BlockCaller.new(
          Fiddle::TYPE_UINT32_T,
          [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]
        ) do |_game_handle, time_pointer, _context, _error|
          result = safely(name) do
            argument = takes_time ? game_time(time_pointer) : nil
            takes_time ? @game.__send__(name, argument) : @game.__send__(name)
          end
          after&.call if result.zero?
          result
        end
        @callbacks_keepalive << callback
        callback
      end

      # XNA's `RunGame` owns the in-run flag, not `Game.Initialize`: it sets `inRun = true` after
      # `Initialize()` returns and clears it in a `finally` once the run is over. Keeping it here
      # rather than in the base method is what makes it survive a subclass that overrides
      # `Initialize` without calling `super`, which is exactly what XNA does.
      #
      # The position is measured rather than transcribed. In XNA `Initialize()`'s own body ends by
      # calling `LoadContent()`, so both managed steps happen while `inRun` is still false; the CNA
      # host delivers `load_content` as a separate callback right after `initialize`, so the
      # faithful place to raise the flag is after **LoadContent** returns. A component added during
      # either step is therefore queued rather than initialised on the spot, as in XNA, and a
      # component added after them is initialised immediately.
      def set_in_run(value) = -> { @game.instance_variable_set(:@in_run, value) }

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

      # One native subscription per event identity, created with the host and released before the
      # game is destroyed. Each registration is an owned handle; `cna_game_unsubscribe` consumes it.
      def subscribe_game_events
        GAME_EVENTS.each do |constant, raiser|
          callback = game_event_callback(raiser)
          @callbacks_keepalive << callback
          output = @library.pointer_for("Q", 0)
          @library.call("cna_game_subscribe", handle,
                        CNA::Native::Manifest::CONSTANTS.fetch(constant),
                        callback, 0, output)
          @event_registrations << output[0, 8].unpack1("Q")
        end
      end

      def unsubscribe_game_events
        registrations = @event_registrations
        @event_registrations = []
        registrations.each { |registration| @library.function("cna_game_unsubscribe").call(registration) }
      end

      # A game event carries nothing but its sender, so the handler receives only its context, and
      # it returns `void` -- there is no result channel a failure could travel back through. So an
      # exception is captured the way a lifecycle callback's is and re-raised by the next `finish`,
      # and **nothing is allowed to escape into C**.
      #
      # These arrive between lifecycle callbacks rather than inside one, so the device-borrow
      # prologue `safely` performs is deliberately not run: no borrowed GraphicsDevice is promised
      # outside a lifecycle callback, and pretending otherwise would hand out a handle CNA has not
      # lent. The owner-thread check is kept, because it is the same contract every callback has.
      def game_event_callback(raiser)
        Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]) do |_context|
          begin
            unless pending_exception
              if Thread.current.equal?(@game.__send__(:owner_thread))
                CNA::Runtime::Context.enter(@game) do
                  @game.__send__(raiser, @game, CNA::Runtime::EventArgs::Empty)
                end
              else
                @pending_exception =
                  CNA::OwnerThreadError.new("CNA raised #{raiser} off the Game owner thread")
              end
            end
          rescue Exception => exception
            @pending_exception ||= exception
          end
          nil
        end
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
        load_content = lifecycle("LoadContent", after: set_in_run(true))
        update = lifecycle("Update", takes_time: true)
        draw = lifecycle("Draw", takes_time: true)
        unload_content = lifecycle("UnloadContent")
        exiting = lifecycle("__cna_exiting")
        @callbacks = CNA::Native::Layouts::GameCallbacks.new(
          [load_content, update, draw, unload_content, exiting]
        )
        @hooks = CNA::Native::Layouts::GameFrameHooks.new(
          [lifecycle("Initialize"), lifecycle("BeginRun"),
           lifecycle("EndRun", after: set_in_run(false)), begin_draw, lifecycle("EndDraw")]
        )
      end
    end
  end
end
