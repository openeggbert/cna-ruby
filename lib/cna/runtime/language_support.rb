# frozen_string_literal: true

module CNA
  module Runtime
    # Ruby identities a projected type may declare **beside** its CLR ones.
    #
    # These are not XNA identities and must never stand in for one. The register exists so the API
    # verifier can tell the two apart by rule rather than by an allowlist of names: a projected type
    # may declare a language-support identity only when it also projects the CLR identity that
    # identity is derived from. `each` is permitted on a type that projects `GetEnumerator`, and
    # nowhere else.
    #
    # The two sets are also separable by spelling, which is a property of the mapping rather than a
    # coincidence: a CLR identity keeps its XNA casing and is PascalCase or an operator, and a Ruby
    # language-support identity is neither.
    module LanguageSupport
      # Ruby identity => the CLR identity it is derived from.
      #
      # `each` is the single Ruby identity that carries CLR `GetEnumerator`: called with a block it
      # walks the same enumeration, and called without one it answers the same Enumerator. It adds
      # no behaviour of its own.
      DERIVED_FROM = {each: "GetEnumerator"}.freeze

      # Ruby derives every method of Enumerable from `each` alone, so a type that includes the
      # module gains no independent behaviour to measure — each of these is a restatement of the one
      # CLR operation `each` already carries.
      ENUMERABLE = ::Enumerable.instance_methods.freeze

      module_function

      def identities = ([:each] + ENUMERABLE).uniq

      def derived_from(identity) = DERIVED_FROM[identity]

      def support?(identity) = DERIVED_FROM.key?(identity) || ENUMERABLE.include?(identity)
    end
  end
end
