# frozen_string_literal: true

module CNA
  module Runtime
    module Ownership
      OWNED = :owned
      BORROWED = :borrowed
      PARENT_OWNED = :parent_owned
      PROCESS_GLOBAL = :process_global
      MANAGED_VALUE = :managed_value
      ALL = [OWNED, BORROWED, PARENT_OWNED, PROCESS_GLOBAL, MANAGED_VALUE].freeze
    end

    class NativeHandle
      attr_reader :ownership, :generation

      def initialize(handle:, ownership:, generation:, release: nil, parent: nil)
        raise ArgumentError, "invalid ownership category" unless Ownership::ALL.include?(ownership)
        raise ArgumentError, "native handle zero is invalid" if handle.zero?

        @handle = handle
        @ownership = ownership
        @generation = generation
        @release = release
        @parent = parent
        @disposed = false
        generation.claim_owned(handle, self) if ownership == Ownership::OWNED
      end

      def disposed? = @disposed

      def value
        raise CNA::DisposedObjectError, "native resource is disposed" if disposed?
        generation.assert_valid!
        raise CNA::DisposedObjectError, "native parent is disposed" if @parent&.__send__(:disposed?)

        @handle
      end

      def dispose
        return false if disposed?
        generation.assert_owner_thread!
        if ownership == Ownership::OWNED && @release
          # The handle stays intact if CNA refuses the destruction. A later
          # owner-thread retry therefore remains possible.
          @release.call(@handle)
        end
        generation.release_owned(@handle, self) if ownership == Ownership::OWNED
        @handle = 0
        @disposed = true
        true
      end
    end

    module NativeResource
      def initialize_native_resource(game, handle, release)
        @native_game = game
        @native_handle = NativeHandle.new(
          handle: handle,
          ownership: Ownership::OWNED,
          generation: game.__send__(:generation),
          release: release,
          parent: game
        )
        game.__send__(:register_native_child, self)
      end

      def IsDisposed = @native_handle.nil? || @native_handle.disposed?

      def Dispose
        return if self.IsDisposed

        prepare_native_dispose
        @native_handle.dispose
        @native_game.__send__(:unregister_native_child, self)
        nil
      end

      private

      def prepare_native_dispose = nil
      def native_handle = @native_handle.value
      def native_game = @native_game
    end
  end
end
