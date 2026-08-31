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
    # serialization constructor. That fourth form is not projected *here*, because
    # `NotSupportedException` is not an XNA type and no selected signature names it; the two
    # XNA exception types that do declare it get it in Foundation 49. The two message-bearing forms
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

    # The Ruby projection of `System.Runtime.Serialization.SerializationException`, which
    # `SerializationInfo` really throws: `Serialization_SameNameTwice` from `AddValue` and
    # `Serialization_NotFound` from `GetElement`. A dedicated `StandardError` subclass for the same
    # reason `NotSupportedError` is one -- it is a distinct CLR identity a caller can rescue by
    # name, and no existing Ruby class says what it says. It is a *thrown* exception, never an
    # identity the XNA surface names, so it belongs in that register and not in the projected one.
    class SerializationError < StandardError
    end

    # The four-constructor exception shape, for the two XNA exception types that add the protected
    # `.ctor(SerializationInfo, StreamingContext)` to the standard trio.
    #
    # Both of those types have **two two-argument constructors**, and Ruby has no overload by
    # parameter type, so one `initialize` has to tell `(message, innerException)` from
    # `(info, context)`. The nominal carrier is what makes that a decision rather than a guess: the
    # first argument either is a `SerializationInfo` or it is not.
    #
    # Every one of the four is a pure forward to `System.Exception`'s in the pinned IL, and the
    # serialization form's base reads eleven named values -- ClassName, Message, Data,
    # InnerException, HelpURL, StackTraceString, RemoteStackTraceString, RemoteStackIndex,
    # ExceptionMethod, HResult and Source. Ruby's exception base holds exactly one of them, the
    # message, so that is the one this carries across; the other ten name CLR-internal state
    # `System.Exception` projects to `StandardError` without, and none of them is fabricated. A
    # carrier with no `Message` member yields an exception with no message, which is what an absent
    # value means rather than an error.
    module XnaSerializableExceptionConstruction
      def initialize(first = nil, second = nil)
        if first.is_a?(CNA::Runtime::SerializationInfo)
          raise ArgumentError, "info must not be nil" if first.nil?

          message = first.MemberCount.zero? ? nil : serialized_message(first)
          super(message)
          return
        end

        super(first)
        return if second.nil?

        ExceptionSupport.bind_cause(self, second)
      end

      private

      # `System.Exception`'s serialization constructor reads the message with
      # `info.GetString("Message")`. `GetValue` raises when the member is absent, and an absent
      # message is not an error here, so the absence is answered rather than propagated.
      def serialized_message(info)
        info.GetValue("Message")
      rescue CNA::Runtime::SerializationError
        nil
      end
    end
  end
end
