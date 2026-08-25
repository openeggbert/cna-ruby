# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.Collections.ObjectModel.Collection`1`.
    #
    # This is a **BCL language projection**, not an XNA type. Like its read-only sibling it lives in
    # the CNA runtime rather than a fabricated Ruby `::System` namespace, and no method it declares
    # is an XNA identity. One XNA type takes the CLR generic as its base —
    # `Microsoft.Xna.Framework.GameComponentCollection` — so what has to survive the projection is
    # the CLR base *relationship*: Ruby has class inheritance, so that class inherits from this one
    # rather than flattening the inherited surface into unrelated methods.
    #
    # Every behaviour below is read out of the admitted Microsoft .NET Framework 4.0 mscorlib
    # (`docs/generated/bcl-inventory.json`, Foundation 28), never from memory.
    #
    # ## It is a view that publishes mutation
    #
    # `ReadOnlyCollection<T>` and this class are the same shape with opposite intent, and the IL
    # says so plainly: both store one `IList<T>` field, both forward every read to it, and neither
    # copies anything. The difference is that this one's mutating members are ordinary public
    # members rather than explicit interface implementations that throw, so the projection has real
    # mutation to carry.
    #
    # Two constructors. The parameterless one **creates** a fresh `List<T>`; the `IList<T>` one
    # throws `ArgumentNullException` naming `list` when it is null and otherwise stores the
    # reference. So a collection built the second way is a live view over a list the caller still
    # owns, and mutation applied to that list is observable here — which is why this class must not
    # `dup` or `freeze` what it is given.
    #
    # ## Mutation always runs through a hook
    #
    # Not one of the five public mutating members touches the backing list itself. Each validates
    # and then calls one of four `protected virtual` hooks:
    #
    #     Add(item)            -> InsertItem(Count, item)
    #     Insert(index, item)  -> InsertItem(index, item)
    #     Item[index] = value  -> SetItem(index, value)
    #     Remove(item)         -> RemoveItem(IndexOf(item))   when found
    #     RemoveAt(index)      -> RemoveItem(index)
    #     Clear()              -> ClearItems()
    #
    # That indirection is the whole point of the type: a subclass overrides a hook and every public
    # entry point routes through it. This projection therefore declares no Ruby-idiomatic mutation
    # of its own — no `<<`, no `push`, no `delete` — because any such member would be a second way
    # to mutate that a subclass's hook never sees.
    #
    # ## What each member validates, and in what order
    #
    # Every mutating member opens with the same check — `items.IsReadOnly` — and throws
    # `NotSupportedException` when it holds. `List<T>` is never read-only, so this fires only for a
    # collection constructed over a list that refuses mutation; the Ruby analogue of that list is a
    # frozen `Array`, and `Array#frozen?` is what this class reads. Then, and only then, the three
    # index-taking members bound-check: `Item[]=` and `RemoveAt` against `0...Count`, `Insert`
    # against `0..Count`. The order is observable — an out-of-range index on a frozen backing list
    # raises the refusal, not the range error.
    #
    # The reads validate nothing at all. `Count`, `Item[]`, `Contains`, `CopyTo`, `GetEnumerator`
    # and `IndexOf` each forward exactly one call to the backing list, so their conditions belong to
    # that list and are governed by `collections.indexErrors` — an index outside `0...Count` raises
    # `IndexError`, exactly as `ReadOnlyCollection` and `CurveKeyCollection` do. The three writers
    # construct `ArgumentOutOfRangeException` in their own bodies, naming `index` in all three
    # cases, so they raise `RangeError` instead. That is `whoConstructsItDecides` applied inside a
    # single type: the same out-of-range condition answers differently depending on whose IL builds
    # the exception, and here both halves are visible at once.
    class Collection
      # Ruby's Enumerable is derived in its entirety from `each`, and `each` is the single Ruby
      # identity that carries CLR `GetEnumerator`. Including it therefore adds no independent
      # behaviour: every method it contributes is a restatement of the one measured operation.
      include ::Enumerable

      CLR_IDENTITY = "System.Collections.ObjectModel.Collection`1"

      # The measured CLR surface, in CLR spelling. `Item[Int32]` maps to Ruby `[]`/`[]=` under the
      # indexed-item rule mapping-rules.json already applies; `Items` and the four hooks are CLR
      # `family`. The fifteen explicit interface implementations are deliberately absent: Ruby has
      # no explicit interface implementation, so they project to no member at all, exactly as
      # `ReadOnlyCollection`'s twelve do.
      CLR_SURFACE = %i[Count [] []= Add Clear Contains CopyTo GetEnumerator IndexOf Insert Remove RemoveAt].freeze
      CLR_PROTECTED_SURFACE = %i[Items ClearItems InsertItem RemoveItem SetItem].freeze

      # Ruby language support: the iteration primitive plus everything Enumerable derives from it.
      # None of these is an XNA identity and none may stand in for one.
      LANGUAGE_SUPPORT = CNA::Runtime::LanguageSupport.identities.freeze

      # Distinguishes `Collection.new` from `Collection.new(nil)`. The CLR has two constructors and
      # they answer differently: the parameterless one builds a list, the other refuses null.
      NO_LIST = ::Object.new.freeze
      private_constant :NO_LIST

      class << self
        # A Ruby class is not statically generic, so the CLR type argument a subclass closes the
        # generic base over cannot live in the superclass expression. It is carried as metadata
        # instead, and the API verifier measures it against the reference contract's declared base.
        def projects_elements(*clr_identities)
          @clr_element_types = clr_identities.map { |identity| identity.dup.freeze }.freeze
        end

        def clr_element_types = defined?(@clr_element_types) ? @clr_element_types : nil
      end

      # `.ctor()`: `items = new List<T>()`.
      # `.ctor(IList<T> list)`: ThrowHelper::ThrowArgumentNullException(ExceptionArgument.list) when
      # null, then one `stfld` of the argument itself. No copy is taken either way.
      def initialize(list = NO_LIST)
        if NO_LIST.equal?(list)
          @list = []
        else
          raise ArgumentError, "list" if list.nil?
          raise TypeError, "list must be an Array" unless list.instance_of?(::Array)

          @list = list
        end
        @version = 0
      end

      # `get_Count` -> `ICollection`1::get_Count`. Live: it answers the backing list's length now.
      def Count = @list.length

      # `get_Item(int32)` -> `IList`1::get_Item`. No condition of its own.
      def [](index) = @list.fetch(forwarded_index(index))

      # `set_Item(int32, T)`: read-only refusal, then `index < 0 || index >= Count`, then the hook.
      def []=(index, value)
        refuse_when_read_only
        SetItem(constructed_index(index, @list.length), value)
        value
      end

      # `Add(T)`: read-only refusal, then `InsertItem(Count, item)`. The index is read once, before
      # the hook runs.
      def Add(item)
        refuse_when_read_only
        InsertItem(@list.length, item)
        nil
      end

      # `Clear()`: read-only refusal, then `ClearItems()`.
      def Clear
        refuse_when_read_only
        ClearItems()
        nil
      end

      # `CopyTo(T[], int32)` -> `ICollection`1::CopyTo`. The wrapper adds no condition, so these are
      # the backing list's: the same argument checks every projected collection already ships.
      def CopyTo(array, index)
        raise ArgumentError, "array" if array.nil?
        raise TypeError, "array must be an Array" unless array.instance_of?(::Array)

        offset = CNA::Runtime::Numeric.int32(index, "index")
        raise IndexError, "index must be non-negative" if offset.negative?
        raise ArgumentError, "destination Array is too small" if offset > array.length - @list.length

        @list.each_with_index { |item, position| array[offset + position] = item }
        nil
      end

      # `Contains(T)` -> `ICollection`1::Contains`. The CLR uses EqualityComparer<T>.Default; the
      # Ruby backing list uses `==`, which is the same relation every value type in this binding
      # already projects Equals onto.
      def Contains(item) = @list.include?(item)

      # `GetEnumerator()` -> `IEnumerable`1::GetEnumerator`, projected to a fresh Ruby Enumerator
      # without a fake System namespace.
      #
      # The CLR enumerator is `List<T>.Enumerator`, which fails fast on the backing list's version
      # counter — so replacing an element in place trips it, not only adding or removing one. This
      # class owns every mutation that reaches it through a hook, so it keeps its own counter and
      # reproduces that exactly. What it cannot see is a caller mutating an `Array` it was handed
      # by the `IList<T>` constructor and still owns; a length change there is caught as well, and a
      # same-length element swap is the one residual gap, which is a property of a Ruby Array
      # carrying no version rather than of this projection.
      def GetEnumerator
        list = @list
        expected_length = list.length
        expected_version = @version
        index = 0
        ::Enumerator.new do |yielder|
          while index < list.length
            verify_unchanged(list, expected_length, expected_version)
            yielder << list[index]
            index += 1
          end
          verify_unchanged(list, expected_length, expected_version)
          nil
        end
      end

      # `IndexOf(T)` -> `IList`1::IndexOf`. Answers -1 when absent, as the CLR does.
      def IndexOf(item) = @list.index(item) || -1

      # `Insert(int32, T)`: read-only refusal, then `index < 0 || index > Count`, then the hook.
      # The upper bound is inclusive here and exclusive in the other two, which is the one place the
      # three index-taking writers differ.
      def Insert(index, item)
        refuse_when_read_only
        InsertItem(constructed_index(index, @list.length + 1), item)
        nil
      end

      # `Remove(T)`: read-only refusal, then `IndexOf`; a negative result answers false without
      # touching the hook, otherwise `RemoveItem(index)` and true.
      def Remove(item)
        refuse_when_read_only
        index = self.IndexOf(item)
        return false if index.negative?

        RemoveItem(index)
        true
      end

      # `RemoveAt(int32)`: read-only refusal, then `index < 0 || index >= Count`, then the hook.
      def RemoveAt(index)
        refuse_when_read_only
        RemoveItem(constructed_index(index, @list.length))
        nil
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

      # The four `protected virtual` hooks. Each is one forwarded call in the CLR, and each is the
      # single point where this class's public surface reaches the backing list. The version bump
      # beside each mutation is `List<T>`'s own `_version++`, which is what the enumerator reads.
      def ClearItems
        @list.clear
        @version += 1
        nil
      end

      def InsertItem(index, item)
        @list.insert(index, item)
        @version += 1
        nil
      end

      def RemoveItem(index)
        @list.delete_at(index)
        @version += 1
        nil
      end

      def SetItem(index, item)
        @list[index] = item
        @version += 1
        nil
      end

      private

      # `items.IsReadOnly`, read before anything else by all six mutating members. A `List<T>` is
      # never read-only, so in the CLR this fires only for a backing list that refuses mutation; the
      # Ruby analogue of such a list is a frozen Array.
      def refuse_when_read_only
        return unless @list.frozen?

        raise CNA::Runtime::NotSupportedError, "the backing collection is read-only"
      end

      # An index a read member forwards: the condition belongs to the backing list, so it raises
      # IndexError like every other projected collection's indexer.
      def forwarded_index(index)
        value = CNA::Runtime::Numeric.int32(index, "index")
        raise IndexError, "Collection index is out of range" if value.negative? || value >= @list.length

        value
      end

      # An index a writer bound-checks in its own body: the CLR constructs
      # ArgumentOutOfRangeException there, naming `index`, so it raises RangeError.
      def constructed_index(index, limit)
        value = CNA::Runtime::Numeric.int32(index, "index")
        raise RangeError, "index" if value.negative? || value >= limit

        value
      end

      def verify_unchanged(list, expected_length, expected_version)
        return if list.length == expected_length && @version == expected_version

        raise RuntimeError, "the backing collection was modified during enumeration"
      end
    end
  end
end
