# frozen_string_literal: true

module CNA
  module Runtime
    class EnumValue
      include Comparable

      attr_reader :name, :value

      def initialize(owner, name, value, flags: false)
        @owner = owner
        @name = String(name).freeze
        @value = Integer(value)
        @flags = flags
        freeze
      end

      def <=>(other)
        return nil unless other.instance_of?(@owner)

        value <=> other.value
      end

      def ==(other) = other.instance_of?(@owner) && value == other.value
      alias eql? ==
      def hash = [@owner, value].hash
      def to_i = value
      def to_s = name
      def inspect = "#{@owner.name}::#{name}"

      def |(other)
        validate_flags!(other)
        @owner.__send__(:from_flags_value, value | other.value)
      end

      def &(other)
        validate_flags!(other)
        @owner.__send__(:from_flags_value, value & other.value)
      end

      private

      def validate_flags!(other)
        raise TypeError, "#{@owner.name} is not a flags enum" unless @flags
        raise TypeError, "expected #{@owner.name}" unless other.instance_of?(@owner)
      end
    end

    module EnumType
      def define_values(values, flags: false)
        @enum_flags = flags
        @enum_values = {}
        @enum_mask = 0
        values.each do |name, value|
          item = new(self, name, value, flags: flags)
          const_set(name, item)
          @enum_values[value] ||= item
          @enum_mask |= value if flags
        end
        private_class_method :new
      end

      def coerce(value)
        return value if value.instance_of?(self)
        raise TypeError, "expected #{name}, not arbitrary Integer" unless value.instance_of?(Integer)

        item = @enum_values[value]
        return item if item
        return from_flags_value(value) if @enum_flags

        raise RangeError, "#{value} is not a defined #{name} value"
      end

      private

      def from_flags_value(value)
        raise RangeError, "#{value} contains undefined #{name} bits" unless (value & ~@enum_mask).zero?

        @enum_values[value] ||= allocate.tap do |item|
          item.__send__(:initialize, self, value.zero? ? "0" : value.to_s, value, flags: true)
        end
      end
    end
  end
end
