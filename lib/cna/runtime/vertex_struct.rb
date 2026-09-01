# frozen_string_literal: true

require_relative "numeric"

module CNA
  module Runtime
    # The four XNA 4.0 vertex structs, derived from the pinned
    # Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
    #
    # They are the first types in this binding that **conform** to a projected interface rather
    # than merely declaring one, which is exactly what `INTERFACE_PRODUCER_MISSING` has measured
    # since Foundation 40: a completed interface is not a provider, and these are what turn
    # `IVertexType` into one.
    #
    # XNA implements `IVertexType.VertexDeclaration` **explicitly** -- the metadata says
    # `private hidebysig newslot specialname virtual final`, so a C# consumer must cast to the
    # interface to reach it, and `v.VertexDeclaration` on the concrete type does not compile.
    # The Ruby analogue is a **private** instance method, reachable the way this binding reaches
    # every other private identity. The public name of the same spelling is the type's `static
    # initonly` field, which is a constant here, so the two never collide.
    module VertexStruct
      # `Helpers.SmartGetHashCode` over the sequential layout: XOR every complete 32-bit word of
      # the boxed struct, then substitute `Int32.MaxValue` when the result is zero. A `Vector`
      # component contributes its binary32 bits and a `Color` its packed value -- the same rule
      # `VertexElement` and the GamePad family already record, applied to a longer layout.
      def GetHashCode
        value = CNA::Runtime::Numeric.wrap_int32(vertex_words.reduce(0) { |left, right| left ^ right })
        value.zero? ? 2_147_483_647 : value
      end

      # `op_Inequality` is its own IL method rather than a negation of `op_Equality`, so it is
      # its own identity here too.
      def !=(other) = !(self == other)

      private

      # XNA's explicit `IVertexType.VertexDeclaration`, private for the reason it is private
      # there: the concrete type does not expose it, the interface does.
      def VertexDeclaration = self.class::VertexDeclaration

      # The 32-bit words of the sequential layout, in declaration order.
      def vertex_words = raise(NotImplementedError, "VertexStruct#vertex_words")

      def position_words
        numeric = CNA::Runtime::Numeric
        [numeric.f32_bits(@Position.X), numeric.f32_bits(@Position.Y), numeric.f32_bits(@Position.Z)]
      end
    end
  end
end
