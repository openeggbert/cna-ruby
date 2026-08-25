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

    # The Ruby projection of `System.NotSupportedException`.
    #
    # This is a **BCL language projection**, not an XNA type, and it is a real dedicated class
    # rather than an alias. The obvious candidate, Ruby's `NotImplementedError`, is wrong and would
    # materially distort CLR semantics: it descends from `ScriptError`, not `StandardError`, so a
    # bare `rescue` — which is what a CLR `catch (Exception)` corresponds to — would not catch it.
    # This binding already documents that trap for the abstract-contract members, and repeating it
    # here would make a routine, recoverable CLR failure escape ordinary Ruby error handling.
    # `RuntimeError` and `ArgumentError` are each catchable but each say something the CLR
    # exception does not, and neither carries a distinct identity a caller can rescue by name.
    #
    # The admitted mscorlib settles the rest. `System.NotSupportedException` extends
    # `System.SystemException`, which extends `System.Exception` — the identity this register
    # already roots at `StandardError` — and declares three public constructors, `()`,
    # `(string message)` and `(string message, Exception innerException)`, plus the protected
    # serialization constructor this binding projects nowhere. The two message-bearing forms
    # forward the message to the base and synthesise nothing.
    #
    # The parameterless form is the one XNA actually uses, and in the CLR it fills the message from
    # the localized framework resource `Arg_NotSupportedException`. That string is Microsoft's, it
    # is culture-dependent, and no XNA member exposes it observably, so it is deliberately **not**
    # reproduced: a `NotSupportedError` raised with no message carries Ruby's own default, the class
    # name. Recorded as a language-mapping limitation rather than fabricated.
    class NotSupportedError < StandardError
      def initialize(message = nil, inner = nil)
        super(message)
        return if inner.nil?

        ExceptionSupport.bind_cause(self, inner)
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
