# frozen_string_literal: true

module CNAApiCompat
  module NameMapper
    module_function

    GENERIC_SEGMENT = /\A(?<name>[^`]+)`(?<arity>[1-9][0-9]*)\z/

    def runtime_constant_path(clr_type_identity)
      raise ArgumentError, "CLR type identity must be a String" unless clr_type_identity.instance_of?(String)
      raise ArgumentError, "constructed CLR types do not have one Ruby constant identity" if clr_type_identity.include?("[")

      clr_type_identity.split(/[.+]/).map { |segment| runtime_segment(segment) }.join("::")
    end

    def runtime_segment(segment)
      match = GENERIC_SEGMENT.match(segment)
      return segment unless match

      arity = Integer(match[:arity], 10)
      suffix = arity == 1 ? "T" : (1..arity).map { |position| "T#{position}" }.join
      "#{match[:name]}Of#{suffix}"
    end
    private_class_method :runtime_segment
  end
end
