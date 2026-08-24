# frozen_string_literal: true

module CNA
  class Error < StandardError; end
  class NativeLoadError < Error; end
  class AbiMismatchError < NativeLoadError; end
  class MissingSymbolError < NativeLoadError; end
  class NativeError < Error
    attr_reader :operation, :result, :category

    def initialize(operation, result, category: nil, detail: nil)
      @operation = operation
      @result = result
      @category = category
      suffix = detail.nil? || detail.empty? ? "" : ": #{detail}"
      super("#{operation} failed with CNA result #{result}#{suffix}")
    end
  end
  class CapabilityError < NativeError; end
  class InvalidBindingStateError < Error; end
  class DisposedObjectError < InvalidBindingStateError; end
  class OwnerThreadError < InvalidBindingStateError; end
  class StaleGenerationError < InvalidBindingStateError; end
end
