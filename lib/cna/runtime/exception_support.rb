# frozen_string_literal: true

module CNA
  module Runtime
    # Shared construction for the projected XNA exception types.
    #
    # Every XNA exception constructor is, in the pinned XNA 4.0 Windows IL, a pure forward to its
    # System.Exception or System.Runtime.InteropServices.ExternalException base — literally
    # `ldarg.0 [ldarg.1 [ldarg.2]]; call base::.ctor(...); ret` — with no message synthesis, no
    # validation and no state of its own. None of the eight types declares a field, a property or a
    # method. The Ruby projection therefore forwards to Ruby's own exception base in the same three
    # public shapes, and adds nothing.
    module ExceptionSupport
      module_function

      # System.Exception(string, Exception) stores the inner exception, which the CLR exposes
      # through the inherited InnerException property. Ruby's analogue of that slot is
      # Exception#cause, and only `raise` can fill it — but `raise` fills it on this very object,
      # so the exception is raised and immediately re-caught here and its backtrace is then
      # cleared. A constructed-but-unraised XNA exception therefore has `cause` set and `backtrace`
      # nil, exactly as the CLR has InnerException set and StackTrace null before a throw.
      def bind_cause(exception, inner)
        begin
          raise exception, cause: inner
        rescue ::Exception => raised
          raise unless raised.equal?(exception)
        end
        exception.set_backtrace(nil)
        exception
      end
    end

    # The three public CLR constructor identities of every projected XNA exception:
    # `()`, `(string message)` and `(string message, Exception inner)`.
    module XnaExceptionConstruction
      def initialize(message = nil, inner = nil)
        super(message)
        return if inner.nil?

        ExceptionSupport.bind_cause(self, inner)
      end
    end
  end
end
