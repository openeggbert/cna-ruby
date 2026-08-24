# frozen_string_literal: true

module CNA
  module Runtime
    module GeometrySupport
      module_function

      def require_type(value, type, name = "value")
        raise TypeError, "#{name} must be #{type.name.split("::").last}" unless value.instance_of?(type)

        value
      end

      def require_array(value, name, mutable: false)
        raise TypeError, "#{name} must be an Array" unless value.instance_of?(Array)
        raise FrozenError, "#{name} must be mutable" if mutable && value.frozen?

        value
      end

      # Mirrors XNA's forward transform loop. A negative length performs no
      # work; negative indices fail only when an element would be accessed.
      def transform_range(source, source_index, destination, destination_index, length, element_type)
        require_array(source, "sourceArray")
        require_array(destination, "destinationArray", mutable: true)
        source_index = Numeric.int32(source_index, "sourceIndex")
        destination_index = Numeric.int32(destination_index, "destinationIndex")
        length = Numeric.int32(length, "length")
        raise ArgumentError, "source array is too small" if source.length < source_index + length
        raise ArgumentError, "destination array is too small" if destination.length < destination_index + length
        if length.positive? && (source_index.negative? || destination_index.negative?)
          raise IndexError, "transform array index is outside the array"
        end

        if length.positive?
          source.slice(source_index, length).each do |value|
            require_type(value, element_type, "sourceArray element")
          end
        end
        [source_index, destination_index, length]
      end

      def copy_components(value, type, *names)
        require_type(value, type)
        type.new(*names.map { |name| value.public_send(name) })
      end
    end
  end
end
