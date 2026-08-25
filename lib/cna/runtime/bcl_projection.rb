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
      TYPES = {
        "System.EventArgs" => "CNA::Runtime::EventArgs",
        "System.TimeSpan" => "Float"
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

      module_function

      def ruby_type(clr_identity) = TYPES[clr_identity] || EXCEPTION_BASES[clr_identity]

      def exception_base?(clr_identity) = EXCEPTION_BASES.key?(clr_identity)

      def identities = (TYPES.keys + EXCEPTION_BASES.keys).uniq.sort

      # The one validation the TimeSpan projection performs: seconds must be numeric.
      def time_span(value)
        raise TypeError, "TimeSpan maps to numeric seconds" unless value.is_a?(::Numeric)

        Float(value)
      end
    end
  end
end
