# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # Only the five ContentSerializer attributes are projected. There is no ContentManager,
      # ContentReader, ContentTypeReader, XNB format support or content pipeline of any kind:
      # nothing in this binding reads an attribute or loads an asset.
      #
      # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…). Ruby has no
      # annotation mechanism, so each projects as an ordinary data-carrying class over the
      # CNA::Runtime::Attribute marker base that System.Attribute maps to.
      module Content
        N = CNA::Runtime::Numeric
        private_constant :N

        # `String.IsNullOrEmpty` guards three of the seven setters and constructors below; where it
        # fails the CLR throws ArgumentNullException, which this binding maps to ArgumentError.
        def self.require_present(value, name)
          raise TypeError, "#{name} must be a String" unless value.nil? || value.instance_of?(String)
          raise ArgumentError, name if value.nil? || value.empty?

          value
        end
        private_class_method :require_present

        class ContentSerializerAttribute < CNA::Runtime::Attribute
          # The constructor stores allowNull true before calling the base constructor; every other
          # field keeps its CLR default of null or false.
          def initialize
            super
            @ElementName = nil
            @FlattenContent = false
            @Optional = false
            @AllowNull = true
            @SharedResource = false
            @collection_item_name = nil
          end

          attr_reader :ElementName, :FlattenContent, :Optional, :AllowNull, :SharedResource

          # A plain field store: the CLR inspects nothing.
          def ElementName=(value)
            @ElementName = value
          end

          %i[FlattenContent Optional AllowNull SharedResource].each do |name|
            define_method(:"#{name}=") do |value|
              raise TypeError, "#{name} must be true or false" unless value == true || value == false

              instance_variable_set(:"@#{name}", value)
            end
          end

          # `IsNullOrEmpty` on the raw field answers the literal "Item" instead.
          def CollectionItemName
            @collection_item_name.nil? || @collection_item_name.empty? ? "Item" : @collection_item_name
          end

          def CollectionItemName=(value)
            @collection_item_name = Content.__send__(:require_present, value, "value")
          end

          def HasCollectionItemName = !(@collection_item_name.nil? || @collection_item_name.empty?)

          # Copies the six raw fields, so the clone reflects the source rather than the "Item"
          # default the getter substitutes.
          def Clone
            copy = self.class.new
            copy.ElementName = @ElementName
            copy.FlattenContent = @FlattenContent
            copy.Optional = @Optional
            copy.AllowNull = @AllowNull
            copy.SharedResource = @SharedResource
            copy.__send__(:collection_item_name=, @collection_item_name)
            copy
          end

          private

          attr_writer :collection_item_name
        end

        class ContentSerializerCollectionItemNameAttribute < CNA::Runtime::Attribute
          attr_reader :CollectionItemName

          def initialize(collectionItemName)
            super()
            @CollectionItemName = Content.__send__(:require_present, collectionItemName, "collectionItemName")
          end
        end

        class ContentSerializerIgnoreAttribute < CNA::Runtime::Attribute
        end

        class ContentSerializerRuntimeTypeAttribute < CNA::Runtime::Attribute
          attr_reader :RuntimeType

          def initialize(runtimeType)
            super()
            @RuntimeType = Content.__send__(:require_present, runtimeType, "runtimeType")
          end
        end

        # The only one of the five whose constructor validates nothing.
        class ContentSerializerTypeVersionAttribute < CNA::Runtime::Attribute
          attr_reader :TypeVersion

          def initialize(typeVersion)
            super()
            @TypeVersion = N.int32(typeVersion, "typeVersion")
          end
        end
      end
    end
  end
end
