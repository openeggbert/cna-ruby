# frozen_string_literal: true

module CNA
  module Runtime
    # The non-XNA CLR identities this binding projects, and what each one projects to.
    #
    # This register is measured, not aspirational: the API verifier resolves every entry and
    # reports a mapping mismatch for any that does not exist or does not have the declared shape,
    # and the dependency frontier consumes the same register. A BCL type can therefore never be
    # reported as mapped unless the runtime really projects it.
    #
    # It stays deliberately narrow. Only a CLR identity the selected XNA surface actually names, and
    # whose Ruby projection can be decided without guessing, belongs here.
    # The Ruby projection of System.Attribute: a marker base with no members of its own.
    class Attribute
    end

    module BclProjection
      # CLR type identity => Ruby constant path.
      #
      # System.EventArgs is the argument half of System.EventHandler`1, projected by Foundation 20
      # as CNA::Runtime::EventArgs. It lives in the CNA runtime rather than a fabricated Ruby
      # ::System namespace, which is the rule mapping-rules.json already applies elsewhere.
      # System.TimeSpan projects to an ordinary Ruby Float carrying seconds. GameTime has projected
      # it that way since Foundation 1; Foundation 23 makes the rule measured rather than implicit,
      # because GestureSample.Timestamp is the second consumer. A TimeSpan is a tick count and a
      # binary64 Float is not, so the projection is exact only within Float's 53-bit significand —
      # documented as a LANGUAGE_MAPPING_LIMITATION, not hidden.
      # System.Attribute projects to CNA::Runtime::Attribute, an empty marker base. Ruby has no
      # annotation mechanism, so a CLR attribute projects as an ordinary data-carrying class; what
      # the base preserves is the CLR base identity, which the API verifier measures. None of the
      # XNA attribute types declares a member inherited from System.Attribute, so the base declares
      # none either.
      # System.Collections.ObjectModel.ReadOnlyCollection`1 projects to
      # CNA::Runtime::ReadOnlyCollection, a dedicated runtime support class rather than an Array, a
      # frozen Array, Enumerable alone, a Set or an opaque Object. Foundation 28 admitted a
      # Microsoft mscorlib as a separate BCL authority precisely so this one could be measured
      # instead of guessed: the CLR type is a live *view* over the IList<T> it is constructed with,
      # it validates nothing of its own, and it refuses mutation by implementing every mutating
      # interface member as an unconditional throw. A frozen Ruby Array would get the view semantics
      # wrong; a plain Array would get the refusal wrong. Ruby has class inheritance, so an XNA
      # class whose actual BCL base is this generic inherits from the support class and the CLR base
      # relationship survives.
      TYPES = {
        "System.EventArgs" => "CNA::Runtime::EventArgs",
        "System.TimeSpan" => "Float",
        "System.Attribute" => "CNA::Runtime::Attribute",
        "System.Collections.ObjectModel.ReadOnlyCollection`1" => "CNA::Runtime::ReadOnlyCollection"
      }.freeze

      # CLR exception base identity => the Ruby exception class an XNA type deriving from it takes
      # as its Ruby superclass.
      #
      # An XNA exception must behave as a Ruby exception rather than an ordinary Object subclass.
      # StandardError is the root because a CLR `catch (Exception)` is the analogue of a bare Ruby
      # `rescue`, which catches StandardError and deliberately not ::Exception; mapping to
      # ::Exception would put XNA failures alongside Ruby's non-recoverable system-level conditions
      # and make a bare rescue miss them.
      #
      # Only the two bases the pinned reference actually names appear here: System.Exception (five
      # XNA types) and System.Runtime.InteropServices.ExternalException (three). The selected XNA
      # surface never names ExternalException itself, so no Ruby constant is invented for it; an
      # intermediate BCL exception class collapses to the nearest projected ancestor. That is a
      # deliberate, documented loss of one CLR inheritance level, not an oversight.
      EXCEPTION_BASES = {
        "System.Exception" => "StandardError",
        "System.Runtime.InteropServices.ExternalException" => "StandardError"
      }.freeze

      # A CLR exception a projected member *throws*, and the Ruby exception it raises instead.
      #
      # This is a different register from EXCEPTION_BASES, and the difference is load-bearing. An
      # entry there is a CLR base an XNA exception type *derives from*, so it is named by the
      # reference contract's public signatures. An entry here is never named by a signature at all:
      # it appears only inside a member's IL, as an `ldstr` naming a parameter followed by a
      # `newobj`, or as a call into a throw helper. Mixing the two would let a thrown exception be
      # counted as a mapped BCL identity the XNA surface names, which it is not.
      #
      # One CLR exception maps to exactly one Ruby exception. Every entry must be a real class, must
      # descend from StandardError so a bare `rescue` catches it as a CLR `catch (Exception)` would,
      # and must not descend from ScriptError; the API verifier enforces all three.
      THROWN_EXCEPTIONS = {
        "System.ArgumentNullException" => "ArgumentError",
        "System.ArgumentOutOfRangeException" => "RangeError",
        "System.ArgumentException" => "ArgumentError",
        "System.IndexOutOfRangeException" => "IndexError",
        "System.NotSupportedException" => "CNA::Runtime::NotSupportedError"
      }.freeze

      module_function

      def ruby_type(clr_identity)
        TYPES[clr_identity] || EXCEPTION_BASES[clr_identity] ||
          TYPES[definition(clr_identity)] || EXCEPTION_BASES[definition(clr_identity)]
      end

      # A constructed generic hides its definition behind its type arguments: the reference contract
      # spells the base of ModelBoneCollection as `ReadOnlyCollection`1[...ModelBone]`, and what the
      # register maps is the definition. Reducing to it here is what lets one register entry answer
      # for every closed form, and it is the same reduction the dependency frontier applies.
      def definition(clr_identity) = clr_identity.to_s.sub(/\[.*\]\z/, "")

      # The CLR type arguments of a constructed generic, split at the top level so a nested
      # constructed argument stays whole.
      def element_types(clr_identity)
        arguments = clr_identity.to_s[/\A[^\[]*\[(.*)\]\z/m, 1]
        return [] if arguments.nil?

        parts = []
        depth = 0
        buffer = +""
        arguments.each_char do |char|
          depth += 1 if char == "["
          depth -= 1 if char == "]"
          if char == "," && depth.zero?
            parts << buffer
            buffer = +""
          else
            buffer << char
          end
        end
        parts << buffer
        parts.map(&:strip).reject(&:empty?)
      end

      # A projected identity whose Ruby class carries its CLR type arguments as metadata, because a
      # Ruby class is not statically generic.
      def generic_projection?(clr_identity) = TYPES.key?(definition(clr_identity)) && definition(clr_identity).include?("`")

      def exception_base?(clr_identity) = EXCEPTION_BASES.key?(clr_identity)

      def identities = (TYPES.keys + EXCEPTION_BASES.keys).uniq.sort

      # Deliberately not part of `identities`: a thrown exception is not an identity the XNA public
      # surface names, so it must never count as a mapped BCL type on the dependency frontier.
      def thrown_identities = THROWN_EXCEPTIONS.keys.sort

      def thrown_exception(clr_identity) = THROWN_EXCEPTIONS[clr_identity]

      # The one validation the TimeSpan projection performs: seconds must be numeric.
      def time_span(value)
        raise TypeError, "TimeSpan maps to numeric seconds" unless value.is_a?(::Numeric)

        Float(value)
      end
    end
  end
end
