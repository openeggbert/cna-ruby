# frozen_string_literal: true

module CNA
  module Runtime
    module ValueSemantics
      def dup = self.class.new(*value_components)
      def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }
      def ==(other)
        return false unless other.instance_of?(self.class)

        value_components.zip(other.__send__(:value_components)).all? { |left, right| left == right }
      end
      alias eql? ==
      def hash = self.GetHashCode
      def Equals(other) = self == other

      private

      def value_components = raise(NotImplementedError)
    end
  end
end
