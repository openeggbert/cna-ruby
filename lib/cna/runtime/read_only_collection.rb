# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.Collections.ObjectModel.ReadOnlyCollection`1`.
    #
    # This is a **BCL language projection**, not an XNA type. It lives in the CNA runtime rather
    # than a fabricated Ruby `::System` namespace, exactly as `EventArgs` and `Attribute` do, and no
    # method it declares is an XNA identity. Four XNA collection types take the CLR generic as their
    # base and six XNA members declare it as their type, so what has to survive the projection is
    # the CLR base *relationship* — Ruby has class inheritance, so an XNA class whose actual BCL
    # base is `ReadOnlyCollection<T>` inherits from this class rather than flattening the inherited
    # surface into unrelated methods.
    #
    # Every behaviour below is read out of the admitted Microsoft .NET Framework 4.0 mscorlib
    # (`docs/generated/bcl-inventory.json`, Foundation 28), never from memory.
    #
    # ## It is a view, not a snapshot
    #
    # The CLR constructor takes an `IList<T>`, throws `ArgumentNullException` naming `list` when it
    # is null, and stores **the reference**. It copies nothing, then or later, and each of the six
    # public read members loads that field and forwards a single call to it. So a mutation applied
    # to the backing list is observable through the wrapper, and this class must not `dup` or
    # `freeze` what it is given: a frozen copy would be a different type with different behaviour.
    #
    # "Read-only" is a statement about this interface, not about the data. The CLR expresses it by
    # implementing every mutating member of `IList<T>`, `ICollection<T>` and `IList` as an explicit
    # interface implementation whose entire body throws `NotSupportedException` — twelve of them,
    # each unconditional, each carrying the resource literal `NotSupported_ReadOnlyCollection`.
    # Ruby has no explicit interface implementation and this binding fabricates no `IList` module,
    # so the projection of "the caller cannot mutate through this interface" is simply that no
    # mutating member exists here at all. There is nothing to call and nothing to throw from.
    #
    # ## It validates nothing of its own
    #
    # Not one of the six public read members carries a throw. Bounds behaviour, element equality,
    # ordering and enumeration all belong to the backing list. This binding's backing list is a Ruby
    # `Array` read through the `IList<T>` contract, so the index rules are the ones
    # `CurveKeyCollection` — this binding's realized `IList<T>` — already ships: an index outside
    # `0...Count` raises `IndexError` rather than answering `nil`, and a negative index is out of
    # range rather than counting from the end. One CLR operation keeps one Ruby behaviour across the
    # binding.
    class ReadOnlyCollection
      # Ruby's Enumerable is derived in its entirety from `each`, and `each` is the single Ruby
      # identity that carries CLR `GetEnumerator`. Including it therefore adds no independent
      # behaviour: every method it contributes is a restatement of the one measured operation.
      include ::Enumerable

      CLR_IDENTITY = "System.Collections.ObjectModel.ReadOnlyCollection`1"

      # The measured CLR surface, in CLR spelling. `Item[Int32]` maps to Ruby `[]` under the
      # indexed-item rule mapping-rules.json already applies; `Items` is CLR `family`.
      CLR_SURFACE = %i[Count [] Contains CopyTo GetEnumerator IndexOf].freeze
      CLR_PROTECTED_SURFACE = %i[Items].freeze

      # Ruby language support: the iteration primitive plus everything Enumerable derives from it.
      # None of these is an XNA identity and none may stand in for one. The register is shared with
      # every projected type, so one rule governs both this support class and an XNA collection.
      LANGUAGE_SUPPORT = CNA::Runtime::LanguageSupport.identities.freeze

      class << self
        # A Ruby class is not statically generic, so the CLR type argument a subclass closes the
        # generic base over cannot live in the superclass expression. It is carried as metadata
        # instead, and the API verifier measures it against the reference contract's declared base.
        def projects_elements(*clr_identities)
          @clr_element_types = clr_identities.map { |identity| identity.dup.freeze }.freeze
        end

        def clr_element_types = defined?(@clr_element_types) ? @clr_element_types : nil
      end

      # `.ctor(IList<T> list)`: ThrowHelper::ThrowArgumentNullException(ExceptionArgument.list) when
      # null, then one `stfld` of the argument itself. No copy is taken.
      def initialize(list)
        raise ArgumentError, "list" if list.nil?
        raise TypeError, "list must be an Array" unless list.instance_of?(::Array)

        @list = list
      end

      # `get_Count` -> `ICollection`1::get_Count`. Live: it answers the backing list's length now,
      # not the length it had at construction.
      def Count = @list.length

      # `get_Item(int32)` -> `IList`1::get_Item(int32)`.
      def [](index) = @list.fetch(bounded_index(index))

      # `Contains(T)` -> `ICollection`1::Contains`. The CLR uses EqualityComparer<T>.Default; the
      # Ruby backing list uses `==`, which is the same relation every value type in this binding
      # already projects Equals onto.
      def Contains(value) = @list.include?(value)

      # `IndexOf(T)` -> `IList`1::IndexOf`. Answers -1 when absent, as the CLR does.
      def IndexOf(value) = @list.index(value) || -1

      # `CopyTo(T[], int32)` -> `ICollection`1::CopyTo`. The wrapper adds no condition, so these are
      # the backing list's: the same argument checks `CurveKeyCollection::CopyTo` already ships,
      # because both are the one CLR operation `List`1::CopyTo`.
      def CopyTo(array, array_index)
        raise ArgumentError, "array" if array.nil?
        raise TypeError, "array must be an Array" unless array.instance_of?(::Array)

        index = CNA::Runtime::Numeric.int32(array_index, "arrayIndex")
        raise IndexError, "arrayIndex must be non-negative" if index.negative?
        raise ArgumentError, "destination Array is too small" if index > array.length - @list.length

        @list.each_with_index { |item, offset| array[index + offset] = item }
        nil
      end

      # `GetEnumerator()` -> `IEnumerable`1::GetEnumerator`, projected to a fresh Ruby Enumerator
      # without a fake System namespace, which is the rule mapping-rules.json already applies.
      #
      # It walks the backing list by index, so it sees the live contents rather than a snapshot,
      # and it fails fast when the backing list changes length during enumeration. That is narrower
      # than `List`1`'s version counter, which also trips on replacing an element in place: a Ruby
      # Array carries no version, and this wrapper does not own the list well enough to add one.
      def GetEnumerator
        list = @list
        expected = list.length
        index = 0
        ::Enumerator.new do |yielder|
          while index < list.length
            verify_length(list, expected)
            yielder << list[index]
            index += 1
          end
          verify_length(list, expected)
          nil
        end
      end

      # The Ruby iteration primitive, and the only language-support identity this class declares of
      # its own. Without a block it answers the same Enumerator GetEnumerator does.
      def each(&block)
        enumerator = self.GetEnumerator
        return enumerator unless block

        enumerator.each(&block)
        self
      end

      protected

      # CLR `family` accessor for the backing list, so a subclass reaches what the CLR gives it.
      def Items = @list

      private

      def bounded_index(index)
        value = CNA::Runtime::Numeric.int32(index, "index")
        raise IndexError, "ReadOnlyCollection index is out of range" if value.negative? || value >= @list.length

        value
      end

      def verify_length(list, expected)
        return if list.length == expected

        raise RuntimeError, "the backing collection was modified during enumeration"
      end
    end
  end
end
