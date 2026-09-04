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
            raise ContentLoadException, "no content reader is registered for #{type}" if materializer.nil?

            asset = materializer.call(self, String(assetName))
            record_disposable(asset, recordDisposableObject)
            asset
          end

          private

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
