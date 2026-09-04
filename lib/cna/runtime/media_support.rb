# frozen_string_literal: true

module CNA
  module Runtime
    # The shapes the seventeen `Media` types repeat, written once.
    #
    # It lives here rather than in `Microsoft::Xna::Framework::Media` for the structural reason
    # `StockEffectSupport` records: the strict verifier reports every module in an XNA namespace
    # that is not a selected XNA type as an `INTERNAL_TYPE_LEAK`, and a helper is not an XNA
    # identity.
    #
    # ## The two shapes, read out of the pinned IL rather than inferred
    #
    # **A media item** — `Song`, `Album`, `Artist`, `Genre`, `Playlist`, `Picture`, `PictureAlbum` —
    # is a `uint32` handle plus an `isDisposed` flag, and carries the same six members in the same
    # IL each time:
    #
    #     get_IsDisposed()   => ldfld isDisposed
    #     Dispose()          => Dispose(true); GC.SuppressFinalize(this)
    #     Dispose(bool)      => if (!IsDisposed) { isDisposed = true;
    #                             if (IsValidHandle) { Release(Handle); handle = -1; } }
    #     Finalize()         => try { Dispose(false); } finally { base.Finalize(); }
    #     VerifyNotDisposed()=> if (IsDisposed) throw new ObjectDisposedException(GetType().Name)
    #     ToString()         => get_Name()
    #
    # **A media collection** — the six `*Collection`s — is that plus `Count`, `Item[int]` and
    # `GetEnumerator`, and its `Dispose(bool)` releases the native **list** rather than the item.
    #
    # ## What is not shared
    #
    # `Equals`, `op_Equality` and `GetHashCode` are per type because the handle they compare is, and
    # each reaches its own `cna_<type>_equals` and `cna_<type>_get_hash_code`. They are written in
    # each type rather than generated here, so a reader sees which route a comparison used.
    module MediaSupport
      module_function

      # `get_Name` on every media item: one counted-string pair over the item's own routes.
      def name_of(prefix, handle)
        CNA::Native.library.counted_string("cna_#{prefix}_get_name_size",
                                           "cna_#{prefix}_copy_name", handle)
      end

      def boolean(symbol, handle)
        output = CNA::Native.library.pointer_for("C", 0)
        CNA::Native.library.call(symbol, handle, output)
        !output[0, 1].unpack1("C").zero?
      end

      def int32(symbol, handle)
        output = CNA::Native.library.pointer_for("l", 0)
        CNA::Native.library.call(symbol, handle, output)
        output[0, 4].unpack1("l")
      end

      def int64(symbol, handle)
        output = CNA::Native.library.pointer_for("q", 0)
        CNA::Native.library.call(symbol, handle, output)
        output[0, 8].unpack1("q")
      end

      def handle_of(symbol, handle)
        output = CNA::Native.library.pointer_for("Q", 0)
        CNA::Native.library.call(symbol, handle, output)
        output[0, 8].unpack1("Q")
      end

      # One element of a native list, by index. Every `*_get_at` in this family has the same shape.
      def element_at(symbol, handle, index)
        output = CNA::Native.library.pointer_for("Q", 0)
        CNA::Native.library.call(symbol, handle, index, output)
        output[0, 8].unpack1("Q")
      end

      # An optional handle: the `CNA_Bool*` availability flag every optional getter in this family
      # answers beside the handle.
      def optional_handle(symbol, handle)
        value = CNA::Native.library.pointer_for("Q", 0)
        available = CNA::Native.library.pointer_for("C", 0)
        CNA::Native.library.call(symbol, handle, value, available)
        available[0, 1].unpack1("C").zero? ? nil : value[0, 8].unpack1("Q")
      end

      # A counted byte blob — album art, a picture's image, either thumbnail. The sizing call and
      # the copy call are the same pair `counted_string` uses, over `uint8_t` rather than `char`.
      def bytes(size_symbol, copy_symbol, handle)
        size = CNA::Native.library.pointer_for("Q", 0)
        CNA::Native.library.call(size_symbol, handle, size)
        count = size[0, 8].unpack1("Q")
        return +"" if count.zero?

        buffer = Fiddle::Pointer.malloc(count, Fiddle::RUBY_FREE)
        CNA::Native.library.call(copy_symbol, handle, buffer, count, size)
        buffer[0, count].b
      end

      # `100ns` CLR ticks to the Float seconds this binding projects `System.TimeSpan` as. The
      # register's decision, applied here rather than restated.
      TICKS_PER_SECOND = 10_000_000.0

      def seconds(ticks) = ticks / TICKS_PER_SECOND

      # The disposal half every media item and collection carries.
      module Disposable
        # `ldfld isDisposed`. It is the managed flag, not a native query: XNA's is a field and a
        # disposed object must answer without touching a handle it has already released.
        def IsDisposed = @is_disposed

        # `Dispose()` is `Dispose(true); GC.SuppressFinalize(this)`, and `Dispose(bool)` is the
        # `family virtual` extension point. Ruby cannot give one name two visibilities, so the two
        # CLR overloads project to one public arity-dispatching method — the rule `GameComponent`
        # established — and the widening is recorded.
        def Dispose(disposing = true)
          return nil if @is_disposed

          @is_disposed = true
          release_media_handle if disposing || media_releases_on_finalize?
          nil
        end

        # `try { Dispose(false); } finally { base.Finalize(); }`. `Dispose(false)` still releases
        # the native handle in this family — unlike `GameComponent`, whose `Dispose(false)` returns
        # at its first instruction — because the flag check is what guards it and the handle is
        # unmanaged. Ruby's garbage collector never calls this: no finalizer is registered.
        def Finalize
          self.Dispose(false)
          nil
        end

        private

        def media_releases_on_finalize? = true

        # `if (IsDisposed) throw new ObjectDisposedException(GetType().Name)`, which every member of
        # every one of these types opens with.
        def verify_not_disposed!
          raise CNA::DisposedObjectError, self.class.name.split("::").last if @is_disposed
        end

        def release_media_handle
          return if @handle.nil? || @handle.zero?

          begin
            CNA::Native.library.call(media_dispose_route, @handle)
          rescue CNA::NativeError
            nil
          end
          begin
            CNA::Native.library.call(media_destroy_route, @handle)
          rescue CNA::NativeError
            nil
          end
          @handle = 0
          nil
        end
      end

      # `Count`, `Item[int]` and `GetEnumerator` over a native list, plus the disposal above.
      #
      # `get_Item` is `VerifyNotDisposed()` then the native fetch, and the IL carries **no bounds
      # check of its own**: an out-of-range index is whatever the native list answers, which is what
      # this forwards. `GetEnumerator` answers a fresh walk over the same live list.
      module Collection
        include Disposable
        include ::Enumerable

        def Count
          verify_not_disposed!
          MediaSupport.int32(media_count_route, @handle)
        end

        def [](index)
          verify_not_disposed!
          raise ::TypeError, "index must be an Integer" unless index.is_a?(::Integer)

          media_element(index)
        end

        def GetEnumerator = each

        def each
          return to_enum(:each) unless block_given?

          self.Count.times { |index| yield self[index] }
          self
        end
      end
    end
  end
end
