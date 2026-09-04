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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi serializable beforefieldinit`, extending `System.Exception` and
        # declaring nothing but four constructors, every one of which is a pure forward to its base:
        # `()`, `(string message)`, `(string message, Exception innerException)` and the `family`
        # `(SerializationInfo info, StreamingContext context)`.
        #
        # It was deferred through eight milestones as "a BCL cluster no otherwise-unblocked type
        # needs". What that cluster really costs is two nominal identities, and what makes them
        # nominal rather than markers is a Ruby fact: the last two constructors both take **two**
        # arguments, and Ruby has no overload by parameter type, so `initialize` needs a real
        # `SerializationInfo` to dispatch on. See `CNA::Runtime::XnaSerializableExceptionConstruction`.
        #
        # Nothing in this binding raises it: there is still no ContentManager, ContentReader, XNB
        # support or content pipeline, so no asset load can fail.
        class ContentLoadException < StandardError
          include CNA::Runtime::XnaSerializableExceptionConstruction
        end

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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # Ten members, every one of them derivable, and the two that were called BCL blockers turned
        # out to be a language rule and a callable:
        #
        # * `Load<T>` and `ReadAsset<T>` are generic **methods**. Ruby has no static generics and
        #   cannot infer a type argument from a call site, so each takes its type argument as a
        #   leading positional parameter — a Ruby `Module`, which is what `System.Type` already
        #   projects to. The rule is `mapping-rules.json` `generics.methodProjection`; it is the only
        #   reason a projected Ruby method may take more arguments than its CLR signature declares.
        # * `System.Action`1` structurally collapses to Ruby's `#call`. See the register: every use
        #   across the whole measured XNA reach is null-check, store and one invocation, and
        #   `ContentReader.InvokeReader<T>` settles what the parameter *means* —
        #   `if (recordDisposableObject != null) recordDisposableObject.Invoke(d); else
        #   contentManager.RecordDisposableObject(d);` — so it is an override for **where** a loaded
        #   disposable is registered, and a supplied callable *replaces* this manager's own
        #   bookkeeping rather than adding to it.
        #
        # ## Caching is XNA's, not CNA's
        #
        # `Load<T>` opens `if (loadedAssets == null) throw new ObjectDisposedException(ToString())`,
        # refuses a null-or-empty name, and then keys its cache on
        # **`TitleContainer.GetCleanPath(assetName)`** under the `StringComparer.OrdinalIgnoreCase`
        # the constructor gives the dictionary. A hit whose value is not a `T` throws
        # `ContentLoadException` rather than reloading, and a hit that is one is returned **as the
        # same object** — so two `Load`s of one name are one asset.
        #
        # That cache has to live here, and measurement is why rather than preference: CNA's typed
        # loaders hand back a *new independently owned handle per call*, documented to survive
        # `unload` and destroyed by the caller. CNA's own normalized key was also measured and is
        # **not** XNA's: it case-folds but does not collapse `./` or `../`, so `./white-1` and
        # `white-1` are two native keys and one XNA key. The projection therefore computes XNA's key
        # and never consults CNA's.
        #
        # ## What is native, and what a supported `T` means
        #
        # `Game.Content` is bound to the content manager **CNA's game already owns**, borrowed
        # through `cna_game_get_content_manager_ext`: one XNA ContentManager to one CNA content
        # manager, which is the ownership rule `docs/graphics-device-service-producer-audit.md`
        # established. It answers the same handle every time, cannot be destroyed and dies with the
        # game — measured working before the first frame and outside every callback.
        #
        # `Load` materializes through a **registry**, not a claim of generic completeness. Exactly
        # one `T` is supported today, `Graphics::Texture2D`, because it is the only XNA asset type
        # this binding projects at all; every other `T` raises `ContentLoadException` naming it,
        # which is what XNA does for a type no reader produces.
        #
        # DEVIATION, recorded: a standalone `ContentManager.new(services)` is fully constructible
        # and every managed member works, but loading through it needs a native manager, and
        # `cna_content_manager_create` requires a **graphics device** where XNA's constructor
        # requires nothing. XNA finds that device through
        # `ServiceProvider.GetService(typeof(IGraphicsDeviceService))`, and this binding registers
        # no such service *on purpose* — the producer audit above measured that registering one
        # duplicates a lifecycle step CNA has already performed. So a standalone manager's `Load`
        # refuses, naming the missing service, and `Game.Content` is the manager that loads.
        #
        # DEVIATION, recorded: `ReadAsset` does **not** route through `OpenStream`. XNA reads the
        # stream `OpenStream` returns, so an override redirects where content comes from; CNA's
        # reader takes an asset *name* and no route in the whole ABI accepts `.xnb` bytes from a
        # caller-supplied buffer. `OpenStream` is projected, works, and answers a real `Stream` over
        # the asset's bytes — but overriding it does not redirect `Load`. Calling it and discarding
        # the result to preserve the hook's *ordering* would double every asset's I/O to simulate a
        # redirection that still would not happen, so it is stated instead.
        class ContentManager
          CONTENT_EXTENSION = ".xnb"

          # The supported `T` registry. It is a registry rather than a case statement so that the
          # supported set is a value a test can read, and so adding an asset type is one entry.
          SUPPORTED = {}

          def self.register_materializer(type, &block)
            SUPPORTED[type] = block
          end
          private_class_method :register_materializer

          def self.supported_types = SUPPORTED.keys

          attr_reader :ServiceProvider

          def initialize(serviceProvider, rootDirectory = "")
            raise ArgumentError, "serviceProvider" if serviceProvider.nil?
            raise ArgumentError, "rootDirectory" if rootDirectory.nil?

            @loaded_assets = {}
            @disposable_assets = []
            @ServiceProvider = serviceProvider
            @native = nil
            @owns_native = false
            @game = nil
            self.RootDirectory = rootDirectory
          end

          def RootDirectory = @root_directory

          # `if (value == null) throw new ArgumentNullException("value")`, then
          # `if (loadedAssets.Count > 0) throw new InvalidOperationException(...)`. The order matters:
          # a null root is refused even on a manager that has already loaded something.
          #
          # This is the **only** member of the type with no disposed check — `Load`, `ReadAsset`,
          # `Unload` and `OpenStream` all open with `if (loadedAssets == null) throw new
          # ObjectDisposedException(ToString())` and this one goes straight to `loadedAssets.Count`.
          # So on a disposed manager XNA throws `NullReferenceException` from the dereference rather
          # than `ObjectDisposedException`. Reproduced rather than corrected: the `empty?` below
          # raises `NoMethodError` on nil, which is the same shape of failure and which a bare
          # `rescue` catches exactly as `catch (Exception)` catches a `NullReferenceException`.
          def RootDirectory=(value)
            raise ArgumentError, "value" if value.nil?
            raise ::RuntimeError, "the root directory cannot change once assets are loaded" unless @loaded_assets.empty?

            @root_directory = String(value).dup.freeze
            @is_root_directory_absolute = TitleContainer.__send__(:clean_path_absolute?,
                                                                 TitleContainer.__send__(:clean_path, @root_directory))
            push_root_directory!
            @root_directory
          end

          def Load(type, assetName)
            ensure_not_disposed!
            require_type!(type)
            raise ArgumentError, "assetName" if assetName.nil? || String(assetName).empty?

            key = cache_key(assetName)
            if @loaded_assets.key?(key)
              cached = @loaded_assets.fetch(key)
              unless cached.is_a?(type)
                raise ContentLoadException,
                      "#{assetName} was already loaded as #{cached.class} and cannot be loaded as #{type}"
              end
              return cached
            end

            asset = self.ReadAsset(type, assetName, nil)
            @loaded_assets[key] = asset
            asset
          end

          # XNA disposes every recorded disposable, then clears both stores in a `finally`, so a
          # raising `Dispose` still leaves the manager empty.
          # XNA disposes every recorded disposable and nothing else. This adds one step, and it is
          # this binding's own bookkeeping rather than XNA surface: an asset that holds **native
          # views** but is not `IDisposable` -- `Graphics::Model` is the only one -- releases them
          # here. XNA's `Model` needs no such step because its `ModelReader` registers the buffers
          # and effects it made as disposable assets; CNA's model owns those itself and hands out
          # views instead, so the views are what there is to release.
          def Unload
            ensure_not_disposed!
            begin
              @loaded_assets.each_value do |asset|
                asset.__send__(:release_content_views) if asset.respond_to?(:release_content_views, true)
              end
              @disposable_assets.each { |asset| asset.Dispose if asset.respond_to?(:Dispose) }
            ensure
              @loaded_assets.clear
              @disposable_assets.clear
              CNA::Native.library.call("cna_content_manager_unload", @native) if @native
            end
            nil
          end

          # `public void Dispose() => Dispose(true); GC.SuppressFinalize(this);` and
          # `protected virtual void Dispose(bool disposing)`. Ruby cannot give one name two
          # visibilities and cannot overload by arity, so the two CLR overloads project to one public
          # method with a default argument — the rule `Game` and `GameComponent` already follow — and
          # the widening is recorded: the protected overload is publicly reachable here, which it is
          # not in the CLR. `GC.SuppressFinalize` needs no analogue because nothing registers a Ruby
          # finalizer for this type, so `Dispose` and `Dispose(true)` really do coincide.
          #
          # `Dispose(bool)` unloads when disposing and not already disposed, then nulls both stores
          # in a `finally`. Nulling them is what makes every later member throw
          # `ObjectDisposedException`, which is why disposal is idempotent with no separate flag.
          def Dispose(disposing = true)
            begin
              self.Unload if disposing && !@loaded_assets.nil?
            ensure
              if disposing
                @loaded_assets = nil
                @disposable_assets = nil
                if @native && @owns_native
                  CNA::Native.library.call("cna_content_manager_destroy", @native)
                  @owns_native = false
                end
                @native = nil
              end
            end
            nil
          end

          protected

          def OpenStream(assetName)
            ensure_not_disposed!
            raise ArgumentError, "assetName" if assetName.nil? || String(assetName).empty?

            path = TitleContainer.__send__(:clean_path, join_root("#{assetName}#{CONTENT_EXTENSION}"))
            begin
              # XNA's two branches exactly: an absolute root bypasses `TitleContainer` and opens a
              # `FileStream` directly, because `TitleContainer.OpenStream` refuses an absolute name
              # by contract. CNA's title reader documents that it accepts "a file name relative to
              # the title path, **or an absolute path**", so both branches reach the same route and
              # only the validation differs -- which is the whole of the difference in XNA too.
              if @is_root_directory_absolute
                TitleContainer.__send__(:open_unvalidated, path)
              else
                TitleContainer.OpenStream(path)
              end
            rescue Errno::ENOENT => error
              raise ContentLoadException, "#{assetName} was not found: #{error.message}"
            rescue ArgumentError, CNA::Error => error
              raise ContentLoadException, "#{assetName} could not be opened: #{error.message}"
            end
          end

          def ReadAsset(type, assetName, recordDisposableObject)
            ensure_not_disposed!
            require_type!(type)
            raise ArgumentError, "assetName" if assetName.nil? || String(assetName).empty?

            materializer = SUPPORTED[type]
            return read_compiled_asset(type, String(assetName), recordDisposableObject) if materializer.nil?

            asset = materializer.call(self, String(assetName))
            record_disposable(asset, recordDisposableObject)
            asset
          end

          private

          # The XNB path, and the second half of `ReadAsset`'s dispatch. A `T` no native loader
          # answers for is not a failure any more: it is an asset whose own type manifest names the
          # readers that produce it, which is what XNA does for **every** type and what this binding
          # now does for every type CNA has no C++ loader for.
          #
          # `ContentReader.Create` takes the stream `OpenStream` answers, so overriding `OpenStream`
          # really does redirect this path -- which is the hook the native loaders cannot honour and
          # the reason the deviation recorded above is now narrower than it was.
          def read_compiled_asset(type, assetName, recordDisposableObject)
            stream = self.OpenStream(assetName)
            reader = ContentReader.__send__(:create, self, stream, assetName, recordDisposableObject)
            begin
              reader.__send__(:read_asset, type)
            ensure
              reader.Close
            end
          end

          # `ContentReader.InvokeReader<T>`: a value type is never recorded; a reference type that is
          # disposable goes to the supplied callable when there is one and to this manager's own list
          # otherwise. The callable *replaces* the default rather than adding to it.
          def record_disposable(asset, recordDisposableObject)
            return unless asset.respond_to?(:Dispose)

            if recordDisposableObject.nil?
              @disposable_assets << asset
            else
              raise TypeError, "recordDisposableObject must be callable" unless recordDisposableObject.respond_to?(:call)

              recordDisposableObject.call(asset)
            end
          end

          def cache_key(assetName) = TitleContainer.__send__(:clean_path, String(assetName)).downcase

          def join_root(name)
            return name if @root_directory.empty?

            "#{@root_directory.sub(%r{[\\/]+\z}, "")}/#{name}"
          end

          def ensure_not_disposed!
            raise CNA::DisposedObjectError, "#{self.class.name} is disposed" if @loaded_assets.nil?
          end

          def require_type!(type)
            raise ArgumentError, "type" if type.nil?
            raise TypeError, "type must be a Module" unless type.is_a?(::Module)

            type
          end

          def push_root_directory!
            return if @native.nil?

            view = CNA::Native::Layouts::StringView.new(@root_directory.b)
            CNA::Native.library.call("cna_content_manager_set_root_directory", @native,
                                     view.read_u64(0), view.read_u64(8))
          end

          # Binds this manager to the content manager CNA's game already owns. BORROWED: the handle
          # is the game's value member, it is the same every time, and it must never be destroyed.
          def bind_borrowed!(game, handle)
            @game = game
            @native = handle
            @owns_native = false
            push_root_directory!
            self
          end

          def native_handle
            ensure_not_disposed!
            return @native if @native

            raise ContentLoadException,
                  "this ContentManager has no native content manager: creating one needs a graphics device, " \
                  "which XNA finds through ServiceProvider.GetService(IGraphicsDeviceService) and which this " \
                  "binding deliberately registers no producer for -- see docs/graphics-device-service-producer-audit.md. " \
                  "Game.Content is bound to the content manager CNA's game already owns and loads normally."
          end

          def graphics_device
            device = @game&.GraphicsDevice
            raise ContentLoadException, "no graphics device is available to materialize this asset" if device.nil?

            device
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public abstract auto ansi beforefieldinit` over `System.Object`, six identities of
        # which three are public. A reader is **stateless per asset**: XNA caches one instance per
        # reader type name for the life of the process, so anything an asset-specific reader needs
        # comes in through the `ContentReader` argument rather than through a field.
        #
        # `TargetIsValueType` is an `assembly` field, so it is not projected; what it *decides* is,
        # and it is decided here the same way: the constructor computes it once from the target
        # type, and `ContentReader` consults it in two places.
        class ContentTypeReader
          # `family` in the CLR. A null `targetType` is allowed and is not an argument failure —
          # `op_Inequality` guards only the `IsValueType` probe — so `TargetType` may answer nil.
          def initialize(targetType)
            @targetType = targetType
            @target_is_value_type = false
            return if targetType.nil?

            unless targetType.is_a?(::Module)
              raise ::TypeError, "targetType must be a Module, which is what System.Type projects to"
            end

            # `Type.IsValueType`, decided the way this binding decides it everywhere else: a CLR
            # struct projects to a class including `CNA::Runtime::ValueSemantics`, an enum to a
            # `CNA::Runtime::EnumValue`, and the CLR primitives project to Ruby's own value classes.
            @target_is_value_type =
              targetType.include?(CNA::Runtime::ValueSemantics) ||
              (targetType.is_a?(::Class) && targetType < CNA::Runtime::EnumValue) ||
              PRIMITIVE_VALUE_TYPES.any? { |primitive| targetType == primitive }
          end

          # `ldfld`, and nothing else.
          def TargetType = @targetType

          # Both are `virtual` with a constant body — `ldc.i4.0; ret` — so a subclass that declares
          # a version or deserializes in place overrides them and every other reader inherits zero
          # and false.
          def TypeVersion = 0
          def CanDeserializeIntoExistingObject = false

          # `famorassem`, virtual, and its whole body is `ret`. The manifest calls it on every
          # reader it newly added, which is where a reader that needs *another* reader gets one.
          def Initialize(manager)
            raise ::TypeError, "manager must be a ContentTypeReaderManager" unless
              manager.nil? || manager.is_a?(ContentTypeReaderManager)

            nil
          end

          # `famorassem`, abstract. A Ruby subclass that does not supply it fails where the CLR
          # would have refused to load the type at all.
          def Read(input, existingInstance)
            raise ::NotImplementedError,
                  "#{self.class} must implement Read(ContentReader, existingInstance)"
          end

          # Not XNA surface: `TargetIsValueType` is `assembly`. It is what the two `ContentReader`
          # branches that consult it actually read, so it is here and it is private.
          private def target_is_value_type? = @target_is_value_type

          # `System.Boolean`, the integer family, `System.Single`/`Double` and `System.Char` are all
          # CLR value types, and each projects to a Ruby class that is not a `ValueSemantics`.
          PRIMITIVE_VALUE_TYPES = [::Integer, ::Float, ::TrueClass, ::FalseClass, ::Symbol].freeze
          private_constant :PRIMITIVE_VALUE_TYPES
        end

        # `ContentTypeReader`1<T>`, whose Ruby name is `ContentTypeReaderOfT` — a Ruby class is not
        # statically generic, so the CLR type argument is carried as class metadata the same way
        # every other closed generic in this binding carries one.
        #
        # Its constructor is `ldtoken !T; GetTypeFromHandle; base..ctor(type)`: the target type *is*
        # the type argument. So a Ruby subclass declares it with `reads`, and the constructor takes
        # nothing, which is the CLR signature.
        class ContentTypeReaderOfT < ContentTypeReader
          class << self
            # The class-level stand-in for `!T`. `System.Type` projects to `Module`, so this takes
            # one and answers it, and `clr_element_types` reports it the way the API verifier reads
            # every other closed generic's argument.
            def reads(type = nil)
              # A closed generic base is inherited in the CLR -- a subclass of a
              # `ContentTypeReader<Point>` is still one -- so an undeclared subclass answers what
              # its superclass declared rather than nothing.
              if type.nil?
                return @reads if defined?(@reads) && @reads
                return superclass.respond_to?(:reads) ? superclass.reads : nil
              end

              raise ::TypeError, "reads takes a Module" unless type.is_a?(::Module)

              @reads = type
            end

            def clr_element_types = [reads&.name].compact
          end

          # `family`, no arguments: `T` is the target type and comes from the class.
          def initialize
            target = self.class.reads
            if target.nil?
              raise ::ArgumentError,
                    "#{self.class} must declare its target type with `reads SomeType`, " \
                    "which is the `!T` its CLR constructor loads with ldtoken"
            end

            super(target)
          end

          # `ContentTypeReader`1` declares `Read` **twice** — the `famorassem virtual` untyped
          # override and the `famorassem abstract` typed one — and both take two arguments. Ruby
          # cannot overload on parameter type, so the two collapse into this one method, which is
          # the rule every overload set in this binding follows; a subclass overrides it exactly as
          # a C# subclass overrides the typed half.
          #
          # The untyped override's own body does one thing the typed half does not: it refuses an
          # `existingInstance` that is not a `T`, with `BadXnbWrongType`. Collapsing the pair would
          # have lost that check, so it is not lost -- it moved to `ContentReader#invoke_reader`,
          # the one caller the CLR would have routed through the untyped half, and it is asserted
          # there rather than described here.
          def Read(_input, _existingInstance)
            raise ::NotImplementedError,
                  "#{self.class} must implement Read(ContentReader, existingInstance)"
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi sealed` with a **private** constructor and exactly one public
        # member, `GetTypeReader(Type)`. A consumer never makes one: the type manifest constructs
        # it and hands it to every reader it just added, through `Initialize`, so the only object
        # that can call `GetTypeReader` is a reader being initialised — which is exactly when a
        # reader needs the reader for its element type.
        class ContentTypeReaderManager
          private_class_method :new

          # `GetTypeReader(Type targetType)` is `GetTypeReader(targetType, this.contentReader)`,
          # and that static's first statement is `if (targetType == null) throw new
          # ArgumentNullException("targetType")`.
          def GetTypeReader(targetType)
            raise ::ArgumentError, "targetType" if targetType.nil?

            CNA::Runtime::ContentTypeReaderRegistry.reader_for_target(targetType, @content_reader)
          end

          private

          def initialize_for(contentReader)
            @content_reader = contentReader
            self
          end

          class << self
            private

            def for_reader(contentReader) = allocate.__send__(:initialize_for, contentReader)

            # `ReadTypeManifest(int32 typeCount, ContentReader contentReader)`, under the lock the
            # IL takes on `nameToReader`. Each entry is a reader-type name and the version the asset
            # was compiled against; a version the reader does not claim is `BadXnbTypeVersion`. The
            # readers this manifest **newly** added are the ones `Initialize` runs on, and a failure
            # anywhere rolls exactly those back out again.
            def read_type_manifest(typeCount, contentReader)
              registry = CNA::Runtime::ContentTypeReaderRegistry
              added = []
              readers = []
              MONITOR.synchronize do
                typeCount.times do
                  name = contentReader.__send__(:read_manifest_string)
                  reader, is_new = registry.reader_for_name(name, contentReader)
                  added << reader if is_new
                  version = contentReader.__send__(:read_manifest_int32)
                  unless version == reader.TypeVersion
                    raise ContentLoadException,
                          "#{name} was compiled as version #{version} and this reader is version " \
                          "#{reader.TypeVersion}"
                  end

                  readers << reader
                end
                manager = for_reader(contentReader)
                added.each { |reader| reader.Initialize(manager) }
              rescue StandardError
                registry.rollback(added)
                raise
              end
              readers
            end
          end

          # `lock (nameToReader)` in the IL. `::Monitor` rather than `Mutex` is the recorded rule:
          # a CLR lock is reentrant and a Ruby Mutex is not.
          MONITOR = ::Monitor.new
          private_constant :MONITOR
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi sealed beforefieldinit`, **extending
        # `[mscorlib]System.IO.BinaryReader`** — the one place the whole XNA 4.0 Windows surface
        # names that type, and therefore the reason `CNA::Runtime::BinaryReader` exists and the
        # reason the BCL inventory admits the family at all. Its own eighteen methods are the XNB
        # deserialisation protocol; everything below them is the base's.
        #
        # The constructor is `private`, so the contract selects none and a consumer never makes one.
        # `ContentManager.ReadAsset` does, which is what `ContentReader.Create` is for in XNA and
        # what `ContentManager#ReadAsset`'s XNB path is here.
        #
        # ## What is derived and what is measured
        #
        # Every read below is the IL's own sequence of `BinaryReader` calls, not an approximation:
        # `ReadVector2` is two `ReadSingle`s, `ReadVector3` three, `ReadVector4` and
        # `ReadQuaternion` four in X, Y, Z, W order, `ReadMatrix` sixteen in row order, and
        # `ReadColor` is one `ReadUInt32` straight into `Color.PackedValue`. `ReadSingle` and
        # `ReadDouble` **override** the base to read an integer and reinterpret its bits, which is
        # the same four or eight bytes in the same order and is asserted rather than assumed.
        #
        # ## Why no `cna_content_reader_*` route is bound
        #
        # CNA exports a whole content-reader surface — `cna_content_reader_create`,
        # `read_matrix`, `read_vector2/3/4`, `read_quaternion`, `read_color`,
        # `read_bounding_sphere`, `read_bytes_exact` and the type-reader registry beside them — and
        # none of it is bound here, for one measured reason: `cna_content_reader_create` takes a
        # `CNA_StorageStreamHandle`, and the only route in the whole ABI that produces one is
        # `cna_storage_container_open_file`. An XNA `ContentReader` reads a **title** asset, which
        # is not in a storage container, and `cna_title_container_read_ext` answers bytes rather
        # than a stream handle. So a native reader cannot be pointed at the asset this type reads,
        # and binding routes that no production call site could reach is exactly what the manifest
        # rule forbids. `docs/content-reader-native-route-audit.md` records the measurement.
        class ContentReader < CNA::Runtime::BinaryReader
          private_class_method :new

          # `get_ContentManager` and `get_AssetName`, both `ldfld`.
          attr_reader :ContentManager, :AssetName

          # ------------------------------------------------------------------ the object protocol

          # `ReadObject<T>()`, `ReadObject<T>(T)`, `ReadObject<T>(ContentTypeReader)` and
          # `ReadObject<T>(ContentTypeReader, T)`. Ruby has no static generics, so `T` is the
          # leading `type` argument — `mapping-rules.json` `generics.methodProjection`, the same
          # rule `ContentManager.Load` follows — and the two remaining overloads are told apart by
          # whether the second argument is a `ContentTypeReader`, which is the rule every overload
          # set in this binding uses.
          def ReadObject(type, typeReaderOrExisting = nil, existingInstance = nil)
            require_type!(type)
            if typeReaderOrExisting.is_a?(ContentTypeReader)
              read_object_internal_with_reader(type, typeReaderOrExisting, existingInstance)
            else
              unless existingInstance.nil?
                raise ::ArgumentError, "the three-argument form takes a ContentTypeReader"
              end

              read_object_internal(type, typeReaderOrExisting)
            end
          end

          # `ReadRawObject<T>()` and its three siblings. "Raw" is the whole difference: no type
          # identifier is read, so the reader is decided by `T` or supplied outright.
          def ReadRawObject(type, typeReaderOrExisting = nil, existingInstance = nil)
            require_type!(type)
            if typeReaderOrExisting.is_a?(ContentTypeReader)
              invoke_reader(type, typeReaderOrExisting, existingInstance)
            else
              unless existingInstance.nil?
                raise ::ArgumentError, "the three-argument form takes a ContentTypeReader"
              end

              reader = CNA::Runtime::ContentTypeReaderRegistry.reader_for_target(type, self)
              invoke_reader(type, reader, typeReaderOrExisting)
            end
          end

          # `ReadSharedResource<T>(Action<T> fixup)`. A shared resource is read **once**, after the
          # primary object, and every place that named it is patched afterwards — so this records a
          # callback against an index and answers nothing. Index 0 is the null resource and is the
          # one case that records nothing at all.
          # `System.Action`1` structurally collapses to Ruby's `#call`, and a Ruby block is the
          # plainest thing that answers to it, so the fixup may be either.
          def ReadSharedResource(type, fixup = nil, &block)
            require_type!(type)
            fixup ||= block
            raise ::ArgumentError, "fixup" if fixup.nil?
            raise ::TypeError, "fixup must be callable" unless fixup.respond_to?(:call)

            index = read_7_bit_encoded_int
            return nil if index.zero?

            index -= 1
            if index >= @shared_resource_fixups.length
              raise ContentLoadException, "the compiled asset names shared resource #{index + 1}, " \
                                          "and it declares #{@shared_resource_fixups.length}"
            end

            # The closure the IL builds is not the caller's: it type-checks first and raises
            # `BadXnb` when the resource is not a `T`, and only then invokes the caller's.
            @shared_resource_fixups[index] << lambda do |value|
              unless value.nil? || value.is_a?(type)
                raise ContentLoadException,
                      "shared resource #{index + 1} is a #{value.class} where a #{type} was expected"
              end

              fixup.call(value)
            end
            nil
          end

          # `ReadExternalReference<T>()`: a string, and an empty one means null. A non-empty one is
          # resolved against the asset's own directory and loaded through the same content manager,
          # so an external reference is an ordinary `Load` with a computed name.
          def ReadExternalReference(type)
            require_type!(type)
            name = self.ReadString
            return nil if name.nil? || name.empty?

            path = TitleContainer.__send__(:clean_path, path_to_reference(name))
            @ContentManager.Load(type, path)
          end

          # ---------------------------------------------------------------- the value-type reads

          # Two `ReadSingle`s. Every one of these is the IL's own call sequence.
          def ReadVector2 = Vector2.new(self.ReadSingle, self.ReadSingle)
          def ReadVector3 = Vector3.new(self.ReadSingle, self.ReadSingle, self.ReadSingle)

          def ReadVector4
            Vector4.new(self.ReadSingle, self.ReadSingle, self.ReadSingle, self.ReadSingle)
          end

          # X, Y, Z, W — the order the IL calls the four setters in, which is also the order the
          # constructor takes them.
          def ReadQuaternion
            Quaternion.new(self.ReadSingle, self.ReadSingle, self.ReadSingle, self.ReadSingle)
          end

          # Sixteen singles in row order: M11..M14, M21..M24, M31..M34, M41..M44.
          def ReadMatrix
            Matrix.new(*::Array.new(16) { self.ReadSingle })
          end

          # `ReadUInt32` straight into `set_PackedValue`, so the byte order is the packed one and
          # not R, G, B, A.
          def ReadColor
            color = Color.new
            color.PackedValue = self.ReadUInt32
            color
          end

          # `ReadSingle` and `ReadDouble` are `virtual` overrides that read an unsigned integer and
          # reinterpret its bits rather than calling the base's float read. On a little-endian host
          # that is the same bytes in the same order, which `test_content_reader.rb` asserts by
          # comparing the two paths on the same buffer rather than by reasoning about it.
          def ReadSingle
            bits = self.ReadUInt32
            CNA::Runtime::Numeric.f32([bits].pack("V").unpack1("e"))
          end

          def ReadDouble = [self.ReadUInt64].pack("Q<").unpack1("E")

          private

          # `ContentReader.Create(contentManager, input, assetName, recordDisposableObject,
          # graphicsProfile)` is an `assembly` static that validates the container header and then
          # calls the private constructor. Both halves are here, and the header check is the one
          # that decides whether a file is an XNB at all.
          def initialize_reader(contentManager, input, assetName, recordDisposableObject)
            # `base..ctor(input)` -- the one-argument `BinaryReader` constructor, measured at
            # `IL_0002` of `ContentReader..ctor`. It is reached by name rather than by `super`
            # because this is not the constructor: `new` is private and `Create` allocates.
            CNA::Runtime::BinaryReader.instance_method(:initialize).bind_call(self, input)
            @ContentManager = contentManager
            @AssetName = assetName
            @record_disposable_object = recordDisposableObject
            @type_readers = []
            @shared_resource_fixups = []
            self
          end

          # `ReadHeader`: the type manifest, then the shared-resource count, then one empty fixup
          # list per shared resource. It answers the count, which `ReadAsset` needs afterwards.
          def read_header
            count = read_7_bit_encoded_int
            @type_readers = ContentTypeReaderManager.__send__(:read_type_manifest, count, self)
            shared = read_7_bit_encoded_int
            @shared_resource_fixups = ::Array.new([shared, 0].max) { [] }
            shared
          end

          # `ReadAsset<T>`: the header, the primary object, then the shared resources — and an
          # `IOException` anywhere inside becomes `ContentLoadException`, which is the only place
          # this type converts one exception into another.
          def read_asset(type)
            read_header
            asset = self.ReadObject(type)
            read_shared_resources
            asset
          rescue ::IOError => error
            raise ContentLoadException, "#{@AssetName} is not a valid compiled asset: #{error.message}"
          end

          # `ReadSharedResources(int)`: read every shared object with `ReadObject<object>()`, then
          # run each index's queued fixups against it. Order matters — a fixup may not run before
          # every shared object exists.
          def read_shared_resources
            count = @shared_resource_fixups.length
            return nil if count.zero?

            values = ::Array.new(count) { self.ReadObject(::Object) }
            @shared_resource_fixups.each_with_index do |fixups, index|
              fixups.each { |fixup| fixup.call(values[index]) }
            end
            nil
          end

          # `ReadObjectInternal<T>(object existingInstance)`: the type identifier is 7-bit encoded
          # and **one-based**, so zero is null and everything else indexes the manifest.
          def read_object_internal(type, existingInstance)
            id = read_7_bit_encoded_int
            return nil if id.zero?

            index = id - 1
            if index >= @type_readers.length
              raise ContentLoadException,
                    "the compiled asset names type reader #{id}, and its manifest declares " \
                    "#{@type_readers.length}"
            end

            invoke_reader(type, @type_readers[index], existingInstance)
          end

          # `ReadObjectInternal<T>(ContentTypeReader, object)`: a **value type** is written without
          # a type identifier, so its reader runs directly; a reference type still carries one, so
          # the supplied reader is ignored in favour of the manifest's. That asymmetry is the IL's.
          def read_object_internal_with_reader(type, typeReader, existingInstance)
            raise ::ArgumentError, "typeReader" if typeReader.nil?

            if typeReader.__send__(:target_is_value_type?)
              invoke_reader(type, typeReader, existingInstance)
            else
              read_object_internal(type, existingInstance)
            end
          end

          # `InvokeReader<T>(ContentTypeReader reader, object existingInstance)`, all four of its
          # rules:
          #
          # 1. a `ContentTypeReader<T>` gets the typed `Read`; anything else gets the untyped one
          #    and its result is type-checked, which is `BadXnbWrongType`;
          # 2. a reader handed an existing instance that answers a **different object** is
          #    `InvalidOperationException(ReaderConstructedNewInstance)` — deserializing in place
          #    means in place;
          # 3. a reference-type result that is disposable is recorded, with the supplied callable
          #    *replacing* the manager's own bookkeeping rather than adding to it;
          # 4. a value type is never recorded, however disposable it looks.
          def invoke_reader(type, reader, existingInstance)
            result =
              if reader.is_a?(ContentTypeReaderOfT)
                # `isinst ContentTypeReader`1<T>` succeeded, so the CLR calls the **typed** `Read`
                # and never checks its result -- the type system already has. What it does check
                # first is the existing instance, in the untyped override this Ruby collapse folded
                # into one method, so that check is performed here instead of being lost.
                target = reader.class.reads
                unless existingInstance.nil? || existingInstance.is_a?(target)
                  raise ContentLoadException,
                        "the compiled asset holds a #{existingInstance.class} where a " \
                        "#{target} was expected"
                end

                reader.Read(self, existingInstance)
              else
                value = reader.Read(self, existingInstance)
                if !value.nil? && !value.is_a?(type)
                  raise ContentLoadException,
                        "the compiled asset holds a #{value.class} where a #{type} was expected"
                end

                value
              end

            unless existingInstance.nil?
              unless result.equal?(existingInstance)
                raise ::RuntimeError,
                      "#{reader.class} constructed a new instance where it was given one to fill"
              end

              return result
            end

            record_disposable(reader, result)
            result
          end

          def record_disposable(reader, result)
            return if reader.__send__(:target_is_value_type?)
            return if result.nil? || !result.respond_to?(:Dispose)

            if !@record_disposable_object.nil?
              @record_disposable_object.call(result)
            elsif !@ContentManager.nil?
              @ContentManager.__send__(:record_disposable, result, nil)
            end
            nil
          end

          # `GetPathToReference(string)`: an external reference is relative to the **asset**, not to
          # the content root, so the asset's own directory is prefixed unless the reference is
          # already rooted.
          def path_to_reference(reference)
            return reference if reference.start_with?("/", "\\")

            directory = ::File.dirname(String(@AssetName).tr("\\", "/"))
            directory == "." ? reference : "#{directory}/#{reference}"
          end

          def read_manifest_string = self.ReadString
          def read_manifest_int32 = self.ReadInt32

          # The four literals `PrepareStream` compares against, each a `private static literal` of
          # the same name in the pinned IL: `PlatformLabel = 'w'`, `XnbVersion = 5`,
          # `XnbCompressedVersion = 0x8005`, `XnbPrologueSize = 10`.
          PLATFORM_WINDOWS = 0x77
          XNB_VERSION = 5
          XNB_COMPRESSED_VERSION = 0x8005
          XNB_PROLOGUE_SIZE = 10
          private_constant :PLATFORM_WINDOWS, :XNB_VERSION, :XNB_COMPRESSED_VERSION, :XNB_PROLOGUE_SIZE

          def require_type!(type)
            raise ::ArgumentError, "type" if type.nil?
            raise ::TypeError, "type must be a Module" unless type.is_a?(::Module)
          end

          class << self
            private

            # `ContentReader.Create`, minus the decompression branch this binding does not reach:
            # the header is `XNB`, a platform byte, version 5, a flag byte and a 32-bit file size,
            # and a compressed asset sets `0x80` in the flags. CNA's own loaders handle compressed
            # assets natively; this path refuses one rather than pretending to decompress it.
            def create(contentManager, input, assetName, recordDisposableObject)
              prepare_stream(input, assetName)
              allocate.__send__(:initialize_reader, contentManager, input, assetName,
                                recordDisposableObject)
            end

            # `PrepareStream(Stream, string, out int)`, statement for statement. It answers the
            # graphics profile in XNA; nothing in the selected surface exposes one, so what is kept
            # here is every one of its four refusals.
            def prepare_stream(input, assetName)
              header = CNA::Runtime::BinaryReader.new(input)
              magic = ::Array.new(3) { header.ReadByte }
              unless magic == [0x58, 0x4E, 0x42]
                raise ContentLoadException, "#{assetName} is not a compiled asset: it does not begin with XNB"
              end
              unless header.ReadByte == PLATFORM_WINDOWS
                raise ContentLoadException, "#{assetName} was compiled for another platform"
              end

              version = header.ReadUInt16 & 0xFFFF80FF
              if version == XNB_COMPRESSED_VERSION
                raise ContentLoadException,
                      "#{assetName} is LZX-compressed, which this binding does not decompress; "                       "CNA's own loaders read a compressed asset natively"
              end
              unless version == XNB_VERSION
                raise ContentLoadException, "#{assetName} declares container version #{version}"
              end

              size = header.ReadInt32
              return unless input.CanSeek
              return unless size - XNB_PROLOGUE_SIZE > input.Length - input.Position

              raise ContentLoadException,
                    "#{assetName} declares #{size} bytes and the file holds "                     "#{input.Length - input.Position + XNB_PROLOGUE_SIZE}"
            end
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # Two identities, and the first candidate this session's dependency frontier ever *selected*
        # rather than merely listed: once `System.Resources.ResourceManager` was collapsed, it had no
        # blocker left at all.
        #
        #     public ResourceContentManager(IServiceProvider serviceProvider, ResourceManager resourceManager)
        #         : base(serviceProvider) {
        #         if (resourceManager == null) throw new ArgumentNullException("resourceManager");
        #         this.resourceManager = resourceManager;
        #     }
        #
        #     protected override Stream OpenStream(string assetName) {
        #         object value = resourceManager.GetObject(assetName);
        #         if (value == null) throw new ContentLoadException(OpenResourceNotFound, assetName);
        #         byte[] bytes = value as byte[];
        #         if (bytes == null) throw new ContentLoadException(OpenResourceNotBinary, assetName);
        #         return new MemoryStream(bytes);
        #     }
        #
        # That is the whole type. It reaches nothing native — no CNA route is bound for it — and the
        # `MemoryStream` is `CNA::Runtime::Stream.over_bytes`, which is what that projection is for.
        #
        # The base constructor takes no root directory, so a `ResourceContentManager` keeps
        # `ContentManager`'s default `""` and never consults it: `OpenStream` is overridden and the
        # root is only used by the base's own path building.
        class ResourceContentManager < ContentManager
          CLR_IDENTITY = "Microsoft.Xna.Framework.Content.ResourceContentManager"

          # `System.Resources.ResourceManager` is **structurally collapsed**, not projected: the only
          # member this type reaches is `GetObject(string)`. So the parameter is any object that
          # answers it — the same rule `System.Action`1` follows for a callable — and a .NET
          # resource set is neither required nor invented.
          def initialize(serviceProvider, resourceManager)
            super(serviceProvider)
            raise ArgumentError, "resourceManager" if resourceManager.nil?
            unless resourceManager.respond_to?(:GetObject)
              raise TypeError, "resourceManager must answer GetObject(assetName)"
            end

            @resource_manager = resourceManager
          end

          protected

          # The two `ContentLoadException` branches are the whole of the behaviour, and they are
          # different failures: a name the resource set does not know, and a name whose value is not
          # binary. `System.Byte[]` projects to a Ruby String, so "not binary" is "not a String".
          def OpenStream(assetName)
            ensure_not_disposed!
            raise ArgumentError, "assetName" if assetName.nil? || String(assetName).empty?

            value = @resource_manager.GetObject(String(assetName))
            if value.nil?
              raise ContentLoadException, "resource not found: #{assetName}"
            end
            unless value.is_a?(::String)
              raise ContentLoadException, "resource is not binary: #{assetName}"
            end

            CNA::Runtime::Stream.over_bytes(value.b, writable: false, name: String(assetName))
          end
        end
      end
    end
  end
end
