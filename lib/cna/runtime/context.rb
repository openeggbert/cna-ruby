# frozen_string_literal: true

require "thread"

module CNA
  module Runtime
    class Generation
      @lock = Mutex.new
      @next_identity = 0

      class << self
        def next_identity
          @lock.synchronize { @next_identity += 1 }
        end
      end

      attr_reader :identity, :owner_thread

      def initialize(owner_thread = Thread.current)
        @identity = self.class.next_identity
        @owner_thread = owner_thread
        @valid = true
        @owned_handles = {}
        @lock = Mutex.new
      end

      def valid? = @lock.synchronize { @valid }

      def assert_valid!
        raise CNA::StaleGenerationError, "native Game generation #{identity} is invalid" unless valid?
      end

      def assert_owner_thread!
        return if Thread.current.equal?(owner_thread)

        raise CNA::OwnerThreadError, "operation belongs to Game generation #{identity} owner thread"
      end

      def claim_owned(handle, wrapper)
        @lock.synchronize do
          raise CNA::StaleGenerationError, "native Game generation #{identity} is invalid" unless @valid
          raise CNA::InvalidBindingStateError, "native handle #{handle} already has an OWNED Ruby wrapper" if @owned_handles.key?(handle)

          @owned_handles[handle] = wrapper
        end
      end

      def release_owned(handle, wrapper)
        @lock.synchronize { @owned_handles.delete(handle) if @owned_handles[handle].equal?(wrapper) }
      end

      def invalidate!
        @lock.synchronize do
          @valid = false
          @owned_handles.clear
        end
      end
    end

    module Context
      THREAD_KEY = :__cna_ruby_game_generation
      @lock = Mutex.new
      @live_games = []

      module_function

      def enter(game)
        previous = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = game
        yield
      ensure
        Thread.current[THREAD_KEY] = previous
      end

      def current_game(operation)
        game = Thread.current[THREAD_KEY]
        return game if game

        live_games = @lock.synchronize do
          @live_games.select { |value| !value.__send__(:disposed?) }
        end
        candidates = live_games.select { |value| value.__send__(:owner_thread).equal?(Thread.current) }
        if candidates.empty? && live_games.length == 1
          raise CNA::OwnerThreadError, "#{operation} belongs to the live CNA Game owner thread"
        end
        raise CNA::InvalidBindingStateError, "#{operation} requires a live CNA Game on its owner thread" if candidates.empty?
        raise CNA::InvalidBindingStateError, "#{operation} cannot select between Game generations" if candidates.length > 1

        candidates.first
      end

      def register(game)
        @lock.synchronize do
          @live_games.reject! { |value| value.equal?(game) || value.__send__(:disposed?) }
          @live_games << game
        end
      end

      def unregister(game)
        @lock.synchronize { @live_games.reject! { |value| value.equal?(game) || value.__send__(:disposed?) } }
      end
    end
  end
end
