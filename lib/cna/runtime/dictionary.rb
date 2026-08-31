# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.Collections.Generic.Dictionary`2`.
    #
    # This is a **BCL language projection**, not an XNA type. Like `Collection` and
    # `ReadOnlyCollection` it lives in the CNA runtime rather than a fabricated Ruby `::System`
    # namespace, and no method it declares is an XNA identity. One XNA type takes the CLR generic as
    # its base — `Microsoft.Xna.Framework.LaunchParameters`, which is a
    # `Dictionary<string, string>` — so what has to survive the projection is the CLR base
    # *relationship*: Ruby has class inheritance, so that class inherits from this one rather than
    # flattening the inherited surface into unrelated methods.
    #
    # Every behaviour below is read out of the admitted Microsoft .NET Framework 4.0 mscorlib
    # (SHA-256 `5634668d…`), never from memory and never from a modern .NET or Mono reimplementation.
    #
    # ## Most of the CLR type projects to nothing
    #
    # The pinned `Dictionary`2` declares fifty-odd methods, and the accessibility census settles what
    # a projection owes. Twenty-two of them are `private … newslot virtual final` — **explicit**
    # interface implementations of `IDictionary`, `ICollection`, `IEnumerable` and their generic
    # forms — and an explicit implementation projects to no Ruby member at all, which is the rule
    # `ReadOnlyCollection`'s twelve and `Collection`'s fourteen already follow. One constructor is
    # `family`, protected, taking `SerializationInfo` and `StreamingContext`. What is left, and what
    # this class carries, is the ordinary public surface:
    #
    #     Comparer  Count  Keys  Values  Item[]  Item[]=
    #     Add  Clear  ContainsKey  ContainsValue  GetEnumerator  Remove  TryGetValue
    #     GetObjectData  OnDeserialization
    #
    # ## A Ruby Hash is the private store and nothing else
    #
    # A `Hash` is a hash map with insertion-ordered traversal and `KeyError` on a missing key, and
    # the CLR type is a hash map with bucket-ordered traversal and `KeyNotFoundException`. The two
    # are close enough that using one as the *store* is right and using one as the *projection*
    # would be wrong: `Hash#[]` answers nil for a missing key where `get_Item` throws, `Hash#store`
    # overwrites where `Add` throws, and `Hash#each` never fails fast. So every public member below
    # is written from the IL and the Hash is reached only through them.
    #
    # Traversal order is the one place the two genuinely differ and the difference is not
    # reproducible. The CLR order is an artefact of bucket layout and of the free list that `Remove`
    # feeds, so a re-inserted key can reappear in a slot it did not occupy before; Ruby's is
    # insertion order. Bucket layout is not part of the public contract — it is documented as
    # unspecified, and the canonical C ABI's own launch-parameter enumeration sorts by name rather
    # than trusting it — so this projection keeps Ruby's order and does not fabricate a hash layout.
    # What *is* public and is preserved exactly: key equality, duplicate recognition, lookup,
    # removal, `Count`, and the version counter that fails an in-flight enumeration.
    #
    # ## The comparer
    #
    # `get_Comparer` is one `ldfld`, and `Insert`/`FindEntry` reach the stored comparer for both
    # `GetHashCode` and `Equals`. A `Dictionary` built by the parameterless constructor stores
    # `EqualityComparer<TKey>.Default`, whose `Equals` is the key's own `Equals`. Ruby's Hash keys
    # compare with `eql?` and hash with `hash`, which is the same pairing, so the default comparer
    # projects to `nil` — the absence of a custom comparer — rather than to an invented object that
    # would claim a CLR identity nothing here needs. A caller-supplied comparer is a duck-typed
    # object answering `Equals(a, b)` and `GetHashCode(x)`, which is exactly
    # `IEqualityComparer<T>`'s whole contract; that is the narrowest reusable projection the
    # interface admits, and no implementation-private CLR comparer class is exposed.
    class Dictionary
      class << self
        # A Ruby class is not statically generic, so an XNA class whose CLR base is a constructed
        # `Dictionary`2` records its type arguments here. The API verifier measures this against
        # the reference contract, which is what stops the base relationship from silently losing
        # them. The same mechanism `Collection` and `ReadOnlyCollection` use.
        def clr_element_types!(*clr_identities)
          @clr_element_types = clr_identities.map { |identity| identity.dup.freeze }.freeze
        end

        def clr_element_types = defined?(@clr_element_types) ? @clr_element_types : nil
      end

      # The six public constructors reduce to two shapes once capacity is dropped: an empty
      # dictionary, and one seeded from another dictionary. Capacity is a CLR allocation hint with
      # no observable behaviour other than `ArgumentOutOfRangeException` on a negative value, so it
      # is accepted and validated rather than silently ignored, and a Ruby Hash needs none of it.
      #
      # `.ctor(IDictionary<K,V>)` copies through `Add`, so a seed carrying a duplicate under the
      # supplied comparer raises exactly as `Add` would, and a null seed raises
      # `ArgumentNullException`.
      def initialize(source = nil, comparer: nil, capacity: nil)
        unless capacity.nil?
          raise TypeError, "capacity must be an Integer" unless capacity.is_a?(::Integer)
          raise RangeError, "capacity must not be negative" if capacity.negative?
        end
        @comparer = comparer
        @store = {}
        @version = 0
        seed(source) unless source.nil?
      end

      # `get_Comparer` is one `ldfld`. The parameterless constructor stores
      # `EqualityComparer<TKey>.Default`, which is the key's own equality — Ruby's own — so the
      # default projects to nil rather than to an invented object.
      def Comparer = @comparer

      # `get_Count` is `count - freeCount`: the live entries, not the slot high-water mark.
      def Count = @store.length

      # `get_Keys` and `get_Values` answer the nested `KeyCollection`/`ValueCollection`, which are
      # **live views** over the dictionary — each stores one reference to it and forwards — not
      # snapshots. A Ruby Array would be a snapshot, and a `ReadOnlyCollection` would claim a CLR
      # base relationship these types do not have, so each answers the dedicated view below.
      def Keys = KeyCollection.new(self)

      def Values = ValueCollection.new(self)

      # `get_Item(key)`: `FindEntry`, and `ThrowKeyNotFoundException()` when it answers a negative
      # index. A missing key is not nil.
      def [](key)
        index = find_entry(key)
        raise ::KeyError, "the given key was not present in the dictionary" if index.nil?

        @store[index]
      end

      # `set_Item(key, value)` is `Insert(key, value, add: false)`: it replaces an existing entry
      # and bumps the version, or inserts a new one.
      def []=(key, value)
        insert(key, value, add: false)
        value
      end

      # `Add(key, value)` is `Insert(key, value, add: true)`, whose only difference is that finding
      # the key already present throws `ArgumentException` instead of replacing.
      def Add(key, value)
        insert(key, value, add: true)
        nil
      end

      # `Clear()` returns at its first branch when `count <= 0`, so **clearing an empty dictionary
      # does not bump the version** and does not invalidate an enumeration in flight. Measured, not
      # assumed: the guard is `ldfld count; ldc.i4.0; ble.s` straight to `ret`.
      def Clear
        return nil if @store.empty?

        @store.clear
        @version += 1
        nil
      end

      # `ContainsKey(key)` is `FindEntry(key) >= 0`.
      def ContainsKey(key) = !find_entry(key).nil?

      # `ContainsValue(value)` walks every live entry. Its null branch is separate in the IL and
      # answers true for the first entry whose value is null, without consulting a comparer;
      # otherwise it compares with `EqualityComparer<TValue>.Default`, never with the key comparer.
      def ContainsValue(value)
        return @store.each_value.any?(&:nil?) if value.nil?

        @store.each_value.any? { |candidate| !candidate.nil? && candidate == value }
      end

      # `TryGetValue(key, out value)` answers a Boolean and writes the value through a by-reference
      # parameter. Ruby has no `out`, and this binding's established collapse for a ref/out pair is
      # to answer the value; the Boolean is `ContainsKey`. So the projection answers the value or
      # nil, which loses nothing a `TValue` of a reference type could not already carry, and
      # `ContainsKey` remains the exact question when nil is a legitimate stored value.
      def TryGetValue(key)
        index = find_entry(key)
        index.nil? ? nil : @store[index]
      end

      # `Remove(key)` throws `ArgumentNullException` on a null key, answers false when the key is
      # absent **without** touching the version, and bumps it when an entry really goes.
      def Remove(key)
        require_key!(key)
        index = find_entry(key)
        return false if index.nil?

        @store.delete(index)
        @version += 1
        true
      end

      # `GetEnumerator()` yields `KeyValuePair<TKey,TValue>`, which this binding projects as a
      # two-element Array — the shape Ruby's own `Hash#each` yields — and fails fast on the version
      # counter, which is what every mutating member above maintains.
      def GetEnumerator
        expected = @version
        store = @store
        ::Enumerator.new do |yielder|
          store.each do |key, value|
            verify_version(expected)
            yielder << [key, value]
          end
          verify_version(expected)
          nil
        end
      end

      # Ruby's iteration protocol over the same enumerator, so a projected dictionary is usable
      # where Ruby expects one without a second, unversioned traversal path existing beside it.
      include ::Enumerable

      def each(&block)
        return self.GetEnumerator unless block

        self.GetEnumerator.each(&block)
        self
      end

      # `GetObjectData(SerializationInfo, StreamingContext)` and `OnDeserialization(object)` are the
      # two public `ISerializable`/`IDeserializationCallback` members. `GetObjectData` writes three
      # values into the info — the version, the comparer and a `KeyValuePair<K,V>[]` of the live
      # entries — and throws `ArgumentNullException` when the info is null; `OnDeserialization`
      # reads them back. Neither needs a formatter runtime to be faithful at this boundary: the
      # contract they implement is "hand your state to this carrier" and "take it back", and the
      # carrier is a plain named-value bag.
      #
      # So the projection is the smallest exact one — a `SerializationInfo` duck type answering
      # `AddValue(name, value)` and `GetValue(name)` — and no formatter, surrogate selector,
      # binder or stream format is invented. Nothing in this binding serialises anything; these
      # exist because they are public members of the CLR type this class projects.
      SERIALIZATION_VERSION = "Version"
      SERIALIZATION_COMPARER = "Comparer"
      SERIALIZATION_ENTRIES = "KeyValuePairs"

      def GetObjectData(info, _context = nil)
        raise ArgumentError, "info must not be nil" if info.nil?

        info.AddValue(SERIALIZATION_VERSION, @version)
        info.AddValue(SERIALIZATION_COMPARER, @comparer)
        info.AddValue(SERIALIZATION_ENTRIES, @store.map { |key, value| [key, value] })
        nil
      end

      def OnDeserialization(_sender = nil, info: nil)
        return nil if info.nil?

        @comparer = info.GetValue(SERIALIZATION_COMPARER)
        entries = info.GetValue(SERIALIZATION_ENTRIES) || []
        @store = {}
        entries.each { |key, value| insert(key, value, add: true) }
        @version = info.GetValue(SERIALIZATION_VERSION).to_i
        nil
      end

      # The nested `KeyCollection` and `ValueCollection`. Their entire public surface in the pinned
      # IL is four members — `.ctor(Dictionary<K,V>)`, `get_Count`, `CopyTo(T[], int)` and
      # `GetEnumerator()` — because every other member each declares is an explicit interface
      # implementation, including all of the mutating ones, which throw `NotSupportedException`.
      # So the projection carries those four and declares no mutation at all: there is nothing to
      # call and nothing to throw from, exactly as `ReadOnlyCollection` establishes.
      #
      # `.ctor` throws `ArgumentNullException` on a null dictionary and stores the reference. It
      # copies nothing, so a view taken before an `Add` sees the added element.
      class View
        include ::Enumerable

        def initialize(dictionary)
          raise ArgumentError, "dictionary must not be nil" if dictionary.nil?

          @dictionary = dictionary
        end

        # `get_Count` forwards one call to the dictionary's own `Count`.
        def Count = @dictionary.Count

        # `CopyTo(T[], int)` throws `ArgumentNullException` on a null array,
        # `ArgumentOutOfRangeException` on a negative index and `ArgumentException` when the
        # remaining room is smaller than `Count`, then writes in enumeration order.
        def CopyTo(array, index)
          raise ArgumentError, "array must not be nil" if array.nil?
          raise RangeError, "index must not be negative" if index.negative?
          raise ArgumentError, "the destination is too small" if array.length - index < self.Count

          elements.each_with_index { |element, offset| array[index + offset] = element }
          nil
        end

        # `GetEnumerator()` fails fast on the dictionary's version counter, exactly as the
        # dictionary's own enumerator does — the nested enumerators read the same field.
        def GetEnumerator = @dictionary.__send__(:view_enumerator, self)

        def each(&block)
          return self.GetEnumerator unless block

          self.GetEnumerator.each(&block)
          self
        end

        private

        def elements = raise(NotImplementedError, "a view names either the keys or the values")
      end

      class KeyCollection < View
        private

        def elements = @dictionary.__send__(:store).keys
      end

      class ValueCollection < View
        private

        def elements = @dictionary.__send__(:store).values
      end

      private

      attr_reader :store

      # One version-checked traversal, shared by the dictionary's enumerator and both views, so a
      # mutation invalidates an in-flight enumeration of the keys and of the values as well.
      def view_enumerator(view)
        expected = @version
        elements = view.__send__(:elements)
        ::Enumerator.new do |yielder|
          elements.each do |element|
            verify_version(expected)
            yielder << element
          end
          verify_version(expected)
          nil
        end
      end

      # `FindEntry` hashes the key with the comparer and walks the bucket comparing with
      # `comparer.Equals`. With no comparer that is the key's own equality, which is what a Ruby
      # Hash lookup already performs, so the fast path is a Hash lookup and the comparer path is a
      # scan — the same answers, and the same number of `Equals` calls a bucket walk would make on
      # a one-entry bucket.
      #
      # It answers the *stored* key rather than an index, because that is what the Ruby store is
      # keyed by; every caller uses it only to reach the value or to test presence.
      def find_entry(key)
        require_key!(key)
        return @store.key?(key) ? key : nil if @comparer.nil?

        hash = @comparer.GetHashCode(key)
        @store.each_key do |candidate|
          return candidate if @comparer.GetHashCode(candidate) == hash && @comparer.Equals(candidate, key)
        end
        nil
      end

      # `Insert(key, value, add)`: `ArgumentNullException` on a null key first, then the bucket
      # walk. Finding the key with `add` true throws `ArgumentException`; with `add` false it
      # replaces the value and bumps the version. Not finding it appends and bumps the version.
      def insert(key, value, add:)
        require_key!(key)
        existing = find_entry(key)
        if existing.nil?
          @store[key] = value
        else
          raise ArgumentError, "an item with the same key has already been added" if add

          @store[existing] = value
        end
        @version += 1
        value
      end

      # `ThrowArgumentNullException(ExceptionArgument.key)`. A CLR `Dictionary` refuses a null key
      # even when `TKey` is a reference type, which is the one validation every keyed member shares.
      def require_key!(key)
        raise ArgumentError, "key must not be nil" if key.nil?
      end

      # The CLR enumerator compares `version` on every `MoveNext` and on `get_Current`, and throws
      # `InvalidOperationException` when it moved. This binding maps that to `RuntimeError` through
      # the measured thrown-exception register, as `CurveKeyCollection` and `ReadOnlyCollection`
      # already do.
      def verify_version(expected)
        return if @version == expected

        raise ::RuntimeError, "collection was modified; enumeration operation may not execute"
      end

      # `.ctor(IDictionary<K,V>)` copies through `Add`, so a duplicate under the supplied comparer
      # raises exactly as `Add` would rather than being silently collapsed.
      def seed(source)
        raise ArgumentError, "dictionary must not be nil" if source.nil?

        pairs = source.respond_to?(:GetEnumerator) ? source.GetEnumerator.to_a : source.to_a
        pairs.each { |key, value| insert(key, value, add: true) }
      end
    end
  end
end
