# frozen_string_literal: true

module CNA
  module Runtime
    # The body of an XNA collection's nested `Enumerator` struct.
    #
    # Five XNA collections declare one — `TouchCollection` and the four `Model*Collection`s — and
    # all five are the same two fields and three members over a **backing array**:
    #
    #     .ctor(T[] wrappedArray) { this.wrappedArray = wrappedArray; this.position = -1; }
    #     T    get_Current()      { return wrappedArray[position]; }              // no guard
    #     bool MoveNext()         { if (++position < wrappedArray.Length) return true;
    #                               position = wrappedArray.Length; return false; }
    #     void Dispose()          { }                                             // a bare ret
    #
    # This is Ruby language support, not an XNA identity: it carries no name of its own into any
    # projected surface, and each collection's `Enumerator` is its own class so that
    # `ModelBoneCollection+Enumerator` and `ModelMeshCollection+Enumerator` stay two identities the
    # way the reference contract spells them. `TouchCollection+Enumerator` predates this module and
    # keeps its own copy, because its collection is a **struct** whose enumerator walks a snapshot
    # of the collection rather than a reference to an array.
    #
    # `IEnumerator.Reset` exists in every one of them as a private explicit interface implementation
    # and is not part of any selected surface, so it is deliberately not projected.
    module ArrayEnumerator
      def initialize(wrappedArray)
        @wrapped_array = wrappedArray
        @position = -1
      end

      # `wrappedArray[position]` with no guard of its own, so reading it before the first
      # `MoveNext` or after exhaustion raises exactly what indexing the array raises.
      def Current = @wrapped_array.fetch(@position)

      # Increment, answer true while below the length, otherwise clamp and answer false. Clamping
      # is what stops a second `MoveNext` past the end from walking further.
      def MoveNext
        @position += 1
        return true if @position < @wrapped_array.length

        @position = @wrapped_array.length
        false
      end

      # The IL body is a bare `ret`: the enumerator holds nothing to release.
      def Dispose = nil
    end
  end
end
