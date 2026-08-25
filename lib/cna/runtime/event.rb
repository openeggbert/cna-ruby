# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of System.EventArgs.
    #
    # Every XNA event this binding projects is a System.EventHandler`1[TArgs], whose handler takes
    # (sender, args). The args value must be a real object: passing nil would be a fake EventArgs
    # representation. Only the two public CLR identities of System.EventArgs are projected — the
    # parameterless constructor and the shared static Empty instance — and they live in the CNA
    # runtime rather than a fabricated Ruby ::System namespace, exactly as mapping-rules.json
    # already requires for the enumerable projection.
    class EventArgs
      Empty = new.freeze
    end

    # The generic event subscription primitive.
    #
    # One CLR public event identity projects to one public Ruby event reader that returns this
    # object. Its whole public surface is add/remove: raising is internal to the declaring
    # implementation, which reaches dispatch through __send__, so no consumer-facing emit, fire,
    # trigger or call helper exists.
    class Event
      def initialize
        @handlers = []
      end

      # Appends one handler, given either as a callable or as a block, and returns the token that
      # remove takes back. Registration order is the invocation order and duplicate subscriptions
      # are permitted, matching a CLR multicast delegate invocation list.
      def add(callable = nil, &block)
        handler = validate(callable, block)
        @handlers.push(handler)
        handler
      end

      # Removes one registration, the last matching occurrence, which is what Delegate.Remove does
      # to a multicast invocation list. Removing an absent handler is harmless and answers nil.
      def remove(handler)
        index = @handlers.rindex { |candidate| candidate == handler }
        index.nil? ? nil : @handlers.delete_at(index)
      end

      private

      # Snapshot semantics: a handler that subscribes or unsubscribes during dispatch does not
      # disturb the invocation already in flight. Exceptions are never swallowed, so the first
      # raised exception propagates and the handlers behind it are not invoked.
      def dispatch(sender, args)
        @handlers.dup.each { |handler| handler.call(sender, args) }
        nil
      end

      def validate(callable, block)
        raise ArgumentError, "pass one event handler, either a callable or a block" if callable && block

        handler = callable || block
        raise ArgumentError, "an event handler is required" if handler.nil?
        raise TypeError, "an event handler must respond to call" unless handler.respond_to?(:call)
        raise ArgumentError, "an event handler must accept (sender, args)" unless accepts_pair?(handler)

        handler
      end

      # A lambda or Method is arity-checked because Ruby enforces its arity at call time; an
      # ordinary Proc and any other callable object are left to Ruby's own lenient rules.
      def accepts_pair?(handler)
        strict = handler.is_a?(Method) || handler.is_a?(UnboundMethod) ||
                 (handler.is_a?(Proc) && handler.lambda?)
        return true unless strict

        arity = handler.arity
        arity.negative? ? -arity - 1 <= 2 : arity == 2
      end
    end

    # Declares CLR event identities on a Ruby projection.
    #
    # Extending this is the only sanctioned way to project an event, which is what lets the API
    # verifier measure selected event identities instead of trusting that a reader happens to
    # exist. Concrete owners get a lazily created Event; an abstract XNA interface contract gets a
    # reader that raises NotImplementedError naming its own contract, exactly like every other
    # member of an interface module.
    module EventOwner
      def xna_event(identity)
        record_event_identity(identity)
        storage = :"@xna_event_#{identity}"
        define_method(identity) do
          if instance_variable_defined?(storage)
            instance_variable_get(storage)
          else
            instance_variable_set(storage, Event.new)
          end
        end
      end

      def xna_abstract_event(identity, contract)
        record_event_identity(identity)
        define_method(identity) { raise(NotImplementedError, contract) }
      end

      # Every event identity this projection declares, including the ones it inherits.
      def xna_event_identities
        ancestors.reverse.flat_map do |ancestor|
          ancestor.instance_variable_get(:@xna_event_identities) || []
        end.uniq
      end

      private

      def record_event_identity(identity)
        name = identity.to_sym
        declared = (@xna_event_identities ||= [])
        raise ArgumentError, "duplicate event identity #{name}" if declared.include?(name)

        declared.push(name)
      end
    end
  end
end
