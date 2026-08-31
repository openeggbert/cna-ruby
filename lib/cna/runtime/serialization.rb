# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of the three `System.Runtime.Serialization` identities the selected XNA
    # surface names.
    #
    # These are **BCL language projections**, not XNA types. Like `EventArgs`, `Attribute`,
    # `ReadOnlyCollection`, `Collection` and `Dictionary` they live in the CNA runtime rather than a
    # fabricated Ruby `::System` namespace, and no method any of them declares is an XNA identity.
    #
    # ## Why they exist at all, and why a marker would not do
    #
    # Two XNA exception types — `Content.ContentLoadException` and
    # `Storage.StorageDeviceNotConnectedException` — declare the standard four-constructor
    # exception shape, and the fourth is `family .ctor(SerializationInfo, StreamingContext)`. Both
    # were deferred for exactly that, as "a BCL cluster no otherwise-unblocked type needs".
    #
    # What settles the projection is a Ruby fact rather than a preference: those types have **two
    # two-argument constructors**, `(string message, Exception innerException)` and
    # `(SerializationInfo info, StreamingContext context)`. Ruby has no overload by parameter type,
    # so one `initialize` must tell them apart, and the only sound way to do that is a **nominal**
    # first argument. A marker class or a duck type would make the dispatch guess; a real identity
    # makes it decide. That is why these are projected as classes and not collapsed.
    #
    # ## How much surface each owes
    #
    # The register's own narrowness rule: only a CLR identity the selected XNA surface actually
    # names, projected to what that surface can reach. `System.Type` projects to `Module` because a
    # service key is all the XNA surface uses it as; `System.Attribute` projects to an empty marker
    # because no XNA attribute inherits a member from it. Here the XNA surface names both types in
    # one parameter list and **calls no member of either** — every one of those constructors is a
    # pure forward to `System.Exception`'s.
    #
    # So `SerializationInfo` carries the surface something in this binding really reaches: the
    # general `AddValue`/`GetValue` pair and `MemberCount`. mscorlib declares forty-three public
    # members, but forty of them are the typed `AddValue`/`Get*` overloads over the CLR primitive
    # set, and those are conveniences over the general form that a dynamically typed language has
    # nothing to distinguish — the same collapse this binding already applies to ref/out pairs and
    # to indexers. `FullTypeName`, `AssemblyName`, `SetType`, `ObjectType` and the enumerator belong
    # to a formatter's type-resolution protocol, and no formatter exists here to run it.
    #
    # `CNA::Runtime::Dictionary`'s `GetObjectData` and `OnDeserialization` are the one place this
    # binding really uses a carrier, and they use exactly that pair.
    class SerializationInfo
      # `AddValue(name, value, type)` throws `ArgumentNullException("name")` on a null name,
      # `ArgumentNullException("type")` on a null type, and
      # `SerializationException(Serialization_SameNameTwice)` when the name is already present. The
      # two-argument form forwards with `value?.GetType() ?? typeof(object)`, so the type argument
      # is never null through it and only the first and third checks are reachable here.
      #
      # The CLR type argument is not carried: a Ruby object's class is reachable from the value
      # itself, so storing it would duplicate what `value.class` already answers.
      def initialize
        @values = {}
      end

      def AddValue(name, value)
        key = require_name!(name)
        if @values.key?(key)
          raise CNA::Runtime::SerializationError,
                "Cannot add the same member twice to a SerializationInfo object."
        end

        @values[key] = value
        nil
      end

      # `GetValue(name, type)` reaches `GetElement`, which throws
      # `SerializationException(Serialization_NotFound)` when `FindElement` answers -1. A missing
      # member is not nil, which is the same distinction `Dictionary`'s indexer draws.
      def GetValue(name)
        key = require_name!(name)
        unless @values.key?(key)
          raise CNA::Runtime::SerializationError,
                "Member '#{key}' was not found."
        end

        @values[key]
      end

      # `get_MemberCount` is the live count of added members.
      def MemberCount = @values.length

      private

      def require_name!(name)
        raise ArgumentError, "name must not be nil" if name.nil?

        String(name)
      end
    end

    # `System.Runtime.Serialization.StreamingContextStates`, an ordinary CLR flags enum read from
    # the pinned mscorlib. `All` is `0xFF`, the composition of the eight named bits, and there is no
    # named zero.
    class StreamingContextStates < EnumValue
      extend EnumType
      define_values({
        "CrossProcess" => 0x01,
        "CrossMachine" => 0x02,
        "File" => 0x04,
        "Persistence" => 0x08,
        "Remoting" => 0x10,
        "Other" => 0x20,
        "Clone" => 0x40,
        "CrossAppDomain" => 0x80,
        "All" => 0xFF
      }, flags: true)
    end

    # `System.Runtime.Serialization.StreamingContext` is a `sequential sealed` value type over two
    # fields, `m_state` and `m_additionalContext`, with two public constructors, two get-only
    # properties and value equality. It is a value type, so this projection copies rather than
    # aliases at every boundary, which is the rule every XNA value type here already follows.
    class StreamingContext
      attr_reader :State, :Context

      def initialize(state = StreamingContextStates::All, context = nil)
        @State = StreamingContextStates.coerce(state)
        @Context = context
        freeze
      end

      # `Equals(object)` compares both fields; `GetHashCode` is `(int)m_state`.
      def ==(other)
        other.instance_of?(self.class) && other.State == @State && other.Context.equal?(@Context)
      end
      alias eql? ==

      def hash = @State.value.hash
    end
  end
end
