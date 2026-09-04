# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.IAsyncResult`, and of the one `WaitHandle` member reachable
    # through it.
    #
    # ## Why this is small, and measured rather than assumed
    #
    # Four XNA signatures name `IAsyncResult`, all of them in `Storage`, and every one of them is a
    # `BeginXxx` return or an `EndXxx` argument. XNA's own implementations of it —
    # `StorageDeviceAsyncResult` and `StorageContainerOpenAsyncResult`, both `private` — are read
    # from the pinned `Microsoft.Xna.Framework.Storage.dll` and they are **not asynchronous at all**:
    #
    #     .ctor(object state, int playerIndex)
    #         mre = new ManualResetEvent(true);   // created ALREADY SIGNALLED
    #     get_AsyncState()             => ldfld syncObject
    #     get_AsyncWaitHandle()        => ldfld mre
    #     get_CompletedSynchronously() => ldc.i4.1; ret
    #     get_IsCompleted()            => mre.WaitOne(0, false)   // true, always
    #
    # and `BeginShowSelector`'s whole body is validate, construct one of these, invoke the callback
    # **inline**, return it. So the async façade completes before `Begin` returns, in XNA itself.
    # CNA's C ABI says the same of its side — "no operation handle is invented for work that never
    # pends" — and invokes its completion callback before the route returns. The two agree, and this
    # projection is the shape both of them actually have rather than a threading model neither uses.
    #
    # ## What it does not project
    #
    # `System.Threading.WaitHandle` is a large BCL type and only one member of it is reachable here:
    # `WaitOne`, on a handle that is permanently signalled. So `WaitHandle` below carries that one
    # member and its two overloads, answers `true` immediately, and is documented as what it is. No
    # `ManualResetEvent`, `EventWaitHandle`, `SafeHandle` or `Set`/`Reset` is invented — nothing in
    # the reachable surface can call them.
    class AsyncResult
      # The permanently-signalled wait handle `AsyncWaitHandle` answers.
      #
      # `WaitOne()`, `WaitOne(millisecondsTimeout)` and `WaitOne(timeout, exitContext)` are the
      # three CLR overloads; all three answer `true` here because the underlying event is created
      # signalled and nothing ever resets it. A timeout is accepted and ignored, which is what
      # waiting on an already-signalled handle does.
      class WaitHandle
        CLR_IDENTITY = "System.Threading.WaitHandle"

        private_class_method :new

        def WaitOne(_millisecondsTimeout = nil, _exitContext = false) = true

        class << self
          private

          def signalled = allocate
        end
      end

      private_class_method :new

      # `get_AsyncState` is one `ldfld` of the `state` object the caller passed to `Begin`.
      attr_reader :AsyncState

      def AsyncWaitHandle = @wait_handle

      # `ldc.i4.1; ret` — the operation always completed on the calling thread.
      def CompletedSynchronously = true

      # `mre.WaitOne(0, false)` on a handle created signalled: always true.
      def IsCompleted = true

      private

      def initialize_completed(state, payload)
        @AsyncState = state
        @payload = payload
        @wait_handle = WaitHandle.__send__(:signalled)
        @end_has_been_called = false
        self
      end

      # `EndXxx`'s first two guards, which both implementations share:
      #
      #     if (!(result is TheExpectedAsyncResult)) throw new ArgumentNullException("result");
      #     if (endHasBeenCalled) throw new InvalidOperationException(CannotEndTwice);
      #     endHasBeenCalled = true;
      #
      # The first is an `ArgumentNullException` even when the argument is merely the wrong type,
      # which is the IL rather than a tidy-up: `isinst` answers null for both cases and the null is
      # what is tested.
      def claim_end(expected_operation)
        if @payload.nil? || @payload.fetch(:operation) != expected_operation
          raise ::ArgumentError, "result"
        end
        raise ::RuntimeError, "Cannot call End twice." if @end_has_been_called

        @end_has_been_called = true
        @payload
      end

      class << self
        private

        # A completed result carrying the payload its `End` will hand back.
        def completed(state, payload) = allocate.__send__(:initialize_completed, state, payload)
      end
    end
  end
end
