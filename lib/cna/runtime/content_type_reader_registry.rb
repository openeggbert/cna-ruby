# frozen_string_literal: true

module CNA
  module Runtime
    # The three process-wide caches `ContentTypeReaderManager` keeps as static fields, and the one
    # thing this binding cannot reproduce from the pinned IL.
    #
    # XNA's `ContentTypeReaderManager` holds `nameToReader`, `targetTypeToReader` and
    # `readerTypeToReader`, and fills them from the reader-type names a compiled asset carries:
    # `InstantiateTypeReader` takes the assembly-qualified CLR name out of the `.xnb`, resolves it
    # with `Type.GetType` and constructs it with `Activator.CreateInstance`. **Ruby has no CLR type
    # resolver**, so that one step -- and only that one step -- is replaced here by an explicit
    # registration, which is the same substitution CNA's own C ABI makes with
    # `cna_content_type_reader_manager_register`: a name, a factory, and a process-wide table.
    #
    # DEVIATION, recorded rather than hidden: in XNA a reader is discovered, here it is declared.
    # Everything after the discovery is the IL's -- the caches, their keys, the duplicate rule, the
    # instance sharing and the rollback -- because all of that *is* in the IL.
    #
    # This lives in `CNA::Runtime` and not in the XNA namespace for the reason every support type
    # here does: it is not an XNA identity, and `ContentTypeReaderManager`'s whole public surface is
    # one method. An `INTERNAL_TYPE_LEAK` diagnostic is what enforces that.
    module ContentTypeReaderRegistry
      module_function

      def factories = (@factories ||= {})
      def name_to_reader = (@name_to_reader ||= {})
      def target_type_to_reader = (@target_type_to_reader ||= {})
      def reader_type_to_reader = (@reader_type_to_reader ||= {})

      # Declares which Ruby `ContentTypeReader` answers for one compiled reader-type name. The name
      # is the string the `.xnb` really carries, assembly-qualified spelling and all, because that
      # is what the type manifest is matched against.
      def register(readerTypeName, factory = nil, &block)
        name = String(readerTypeName)
        raise ::ArgumentError, "readerTypeName" if name.empty?

        producer = factory || block
        raise ::ArgumentError, "a factory or a block is required" if producer.nil?
        raise ::TypeError, "the factory must be callable" unless producer.respond_to?(:call)

        factories[name] = producer
        name
      end

      def registered?(readerTypeName) = factories.key?(String(readerTypeName))

      def unregister(readerTypeName)
        name = String(readerTypeName)
        factories.delete(name)
        reader = name_to_reader.delete(name)
        forget(reader)
        nil
      end

      # Empties every cache **and** every registration. Nothing in XNA does this -- its statics live
      # for the process -- so it exists for the same reason CNA's own
      # `cna_content_type_reader_manager_clear_type_creators` does: a process-wide table that
      # nothing can reset is a table that leaks between one caller and the next.
      def clear
        factories.clear
        name_to_reader.clear
        target_type_to_reader.clear
        reader_type_to_reader.clear
        nil
      end

      # `GetTypeReader(string readerTypeName, ContentReader)`: a cache hit answers the **same
      # instance** every time, which is why a reader may hold no per-asset state; a miss constructs
      # one, adds it to all three caches and reports that it is new, because a new reader is one the
      # manifest still has to `Initialize`.
      def reader_for_name(readerTypeName, contentReader)
        name = String(readerTypeName)
        cached = name_to_reader[name]
        return [cached, false] if cached

        factory = factories[name]
        if factory.nil?
          raise Microsoft::Xna::Framework::Content::ContentLoadException,
                "no ContentTypeReader is registered for #{name.inspect}; " \
                "register one with CNA::Runtime::ContentTypeReaderRegistry.register"
        end

        reader = factory.call
        unless reader.is_a?(Microsoft::Xna::Framework::Content::ContentTypeReader)
          raise ::TypeError, "the factory for #{name.inspect} did not answer a ContentTypeReader"
        end

        add(name, reader, contentReader)
        [reader, true]
      end

      # `GetTypeReader(Type targetType, ContentReader)`: a lookup with no fallback. XNA's message is
      # `FrameworkResources.TypeReaderNotRegistered` formatted with the type.
      def reader_for_target(targetType, _contentReader)
        raise ::ArgumentError, "targetType" if targetType.nil?

        target_type_to_reader.fetch(targetType) do
          raise Microsoft::Xna::Framework::Content::ContentLoadException,
                "no ContentTypeReader is registered for the target type #{targetType}"
        end
      end

      # `RollbackAddReaders`: a manifest that failed part-way leaves nothing behind, so the readers
      # it added come back out of all three caches.
      def rollback(readers)
        readers.each do |reader|
          name_to_reader.delete_if { |_, value| value.equal?(reader) }
          forget(reader)
        end
        nil
      end

      # `AddTypeReader`. The duplicate rule is the IL's and is the one place this throws: two reader
      # type names claiming one target type is `FrameworkResources.TypeReaderDuplicate`, because the
      # asset would otherwise deserialize through whichever of them was seen first.
      def add(name, reader, _contentReader)
        target = reader.TargetType
        unless target.nil?
          if target_type_to_reader.key?(target)
            raise Microsoft::Xna::Framework::Content::ContentLoadException,
                  "#{name} claims the target type #{target}, which " \
                  "#{target_type_to_reader.fetch(target).class} already reads"
          end

          target_type_to_reader[target] = reader
        end
        reader_type_to_reader[reader.class] = reader
        name_to_reader[name] = reader
        nil
      end

      def forget(reader)
        return if reader.nil?

        target_type_to_reader.delete_if { |_, value| value.equal?(reader) }
        reader_type_to_reader.delete_if { |_, value| value.equal?(reader) }
        nil
      end
    end
  end
end
