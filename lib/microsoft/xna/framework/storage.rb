# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # `StorageDevice`, `StorageContainer` and the exception a disconnected device raises.
      #
      # ## The async that is not
      #
      # `BeginShowSelector`/`EndShowSelector` and `BeginOpenContainer`/`EndOpenContainer` look
      # asynchronous and are not. `BeginShowSelector`'s whole IL validates, constructs a
      # `StorageDeviceAsyncResult` whose `ManualResetEvent` is created **already signalled** and
      # whose `CompletedSynchronously` is `ldc.i4.1`, invokes the callback **inline** and returns
      # it. CNA's C ABI says the same of its side — "no operation handle is invented for work that
      # never pends" — and invokes `CNA_StorageCompletionCallback` before the route returns. So one
      # C route carries each pair, the work happens inside `Begin`, and `End` hands back what
      # `Begin` already produced. `CNA::Runtime::AsyncResult` carries the whole derivation.
      #
      # ## What the device is
      #
      # XNA's `StorageDevice` is a value over `deviceIndex` and `playerIndex` whose three properties
      # ask the **file system** about the save folder — `DriveInfo.AvailableFreeSpace`, falling back
      # to `GetDiskFreeSpaceEx`. CNA answers the same three from its own storage root, so each is
      # one route and nothing is computed here.
      module Storage
        # Derived from the pinned Microsoft.Xna.Framework.Storage.dll IL.
        #
        # Extends `System.Runtime.InteropServices.ExternalException`, which the BCL register maps to
        # `StandardError` — a deliberate, documented loss of one CLR inheritance level, because the
        # selected XNA surface never names `ExternalException` itself. Four constructors, every one a
        # pure forward to its base, the fourth being the `family`
        # `(SerializationInfo info, StreamingContext context)`.
        class StorageDeviceNotConnectedException < StandardError
          include CNA::Runtime::XnaSerializableExceptionConstruction
        end

        # `sealed`, three properties, an event, and two Begin/End pairs plus `DeleteContainer`.
        class StorageDevice
          extend CNA::Runtime::EventOwner
          private_class_method :new

          # `DeviceChanged` is a **static** event in XNA — one `EventHandler` field on the type, not
          # on an instance — and it is projected as one, because that is the identity the contract
          # declares. CNA's subscription is process-global too, which is the same shape.
          class << self
            def DeviceChanged
              @DeviceChanged ||= CNA::Runtime::Event.new
            end
          end

          # `BeginShowSelector` has four overloads and Ruby cannot dispatch on parameter type, so
          # they collapse into one method dispatching on **arity** — the rule this binding applies
          # everywhere:
          #
          #     (callback, state)
          #     (player, callback, state)
          #     (sizeInBytes, directoryCount, callback, state)
          #     (player, sizeInBytes, directoryCount, callback, state)
          #
          # The IL's guards, in its order: a `player` outside `0..3` that is not `PlayerIndex.All`
          # (`0xff`, which the public enum does not carry) is `ArgumentOutOfRangeException("player")`,
          # and a negative `sizeInBytes` is `ArgumentOutOfRangeException("sizeInBytes")`.
          def self.BeginShowSelector(*arguments)
            player, size, directories, callback, state = self.__send__(:selector_arguments, arguments)
            unless player.nil?
              index = PlayerIndex.coerce(player)
              raise ::RangeError, "player" unless (0..3).cover?(index.to_i)
            end
            raise ::RangeError, "sizeInBytes" if !size.nil? && size.negative?

            device = self.__send__(:show_selector, player, size, directories)
            result = CNA::Runtime::AsyncResult.__send__(
              :completed, state, { operation: :show_selector, device: device }
            )
            callback.call(result) if callback
            result
          end

          # `EndShowSelector(IAsyncResult)`: the two shared guards, then the device.
          def self.EndShowSelector(result)
            raise ::ArgumentError, "result" unless result.is_a?(CNA::Runtime::AsyncResult)

            result.__send__(:claim_end, :show_selector).fetch(:device)
          end

          # `BeginOpenContainer(displayName, callback, state)`: no guard of its own in the IL — the
          # container's own constructor is where a bad name is refused.
          def BeginOpenContainer(displayName, callback = nil, state = nil)
            container = open_container(displayName)
            result = CNA::Runtime::AsyncResult.__send__(
              :completed, state, { operation: :open_container, device: self, container: container }
            )
            callback.call(result) if callback
            result
          end

          # The two shared guards, then `ReferenceEquals(this, result.storageDevice)` — a result
          # from another device is `ArgumentException(IAsyncNotFromBegin, "result")`.
          def EndOpenContainer(result)
            raise ::ArgumentError, "result" unless result.is_a?(CNA::Runtime::AsyncResult)

            payload = result.__send__(:claim_end, :open_container)
            unless payload.fetch(:device).equal?(self)
              raise ::ArgumentError, "result"
            end

            payload.fetch(:container)
          end

          # `if (titleName == null) throw new ArgumentNullException(..., TitleNameNotNull)`, then the
          # directory is removed when it exists. A name that names nothing is not an error.
          def DeleteContainer(titleName)
            raise ::ArgumentError, "titleName" if titleName.nil?

            view = CNA::Native::Layouts::StringView.new(String(titleName).b)
            CNA::Native.library.call("cna_storage_device_delete_container", @handle,
                                     view.read_u64(0), view.read_u64(8))
            nil
          end

          def FreeSpace = native_i64("cna_storage_device_get_free_space")
          def TotalSpace = native_i64("cna_storage_device_get_total_space")

          def IsConnected
            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_storage_device_get_is_connected", @handle, output)
            !output[0, 1].unpack1("C").zero?
          end

          private

          def initialize_native(handle)
            @handle = handle
            self
          end

          def native_handle = @handle

          def native_i64(symbol)
            output = CNA::Native.library.pointer_for("q", 0)
            CNA::Native.library.call(symbol, @handle, output)
            output[0, 8].unpack1("q")
          end

          def open_container(displayName)
            view = CNA::Native::Layouts::StringView.new(String(displayName).b)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_storage_container_open", @handle,
                                     view.read_u64(0), view.read_u64(8), 0, 0, output)
            StorageContainer.__send__(:from_native, self, output[0, 8].unpack1("Q"))
          end

          class << self
            private

            # Which of the four overloads the arity names.
            def selector_arguments(arguments)
              case arguments.length
              when 2 then [nil, nil, nil, arguments[0], arguments[1]]
              when 3 then [arguments[0], nil, nil, arguments[1], arguments[2]]
              when 4 then [nil, integer(arguments[0], "sizeInBytes"), integer(arguments[1], "directoryCount"),
                           arguments[2], arguments[3]]
              when 5 then [arguments[0], integer(arguments[1], "sizeInBytes"),
                           integer(arguments[2], "directoryCount"), arguments[3], arguments[4]]
              else
                raise ::ArgumentError,
                      "BeginShowSelector takes (callback, state), (player, callback, state), " \
                      "(sizeInBytes, directoryCount, callback, state) or " \
                      "(player, sizeInBytes, directoryCount, callback, state)"
              end
            end

            def integer(value, name) = CNA::Runtime::Numeric.int32(value, name)

            def show_selector(player, size, directories)
              output = CNA::Native.library.pointer_for("Q", 0)
              if player.nil? && size.nil?
                CNA::Native.library.call("cna_storage_device_show_selector", 0, 0, output)
              elsif player.nil?
                CNA::Native.library.call("cna_storage_device_show_selector_with_space",
                                         size, directories, 0, 0, output)
              elsif size.nil?
                CNA::Native.library.call("cna_storage_device_show_selector_for_player",
                                         PlayerIndex.coerce(player).to_i, 0, 0, output)
              else
                CNA::Native.library.call("cna_storage_device_show_selector_for_player_with_space",
                                         PlayerIndex.coerce(player).to_i, size, directories, 0, 0, output)
              end
              allocate.__send__(:initialize_native, output[0, 8].unpack1("Q"))
            end

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `StorageContainer`: thirteen methods, three properties, one event and a finalizer.
        #
        # Every path-taking member opens with `ValidateArguments(path, "<parameterName>")`, which is
        #
        #     VerifyNotDisposed();
        #     if (String.IsNullOrEmpty(path)) throw new ArgumentNullException(argumentName);
        #     var full = GetFullPath(path);
        #     if (!full.StartsWith(_rootPath))
        #         throw new ArgumentException(InvalidStoragePath, argumentName);
        #
        # so an **empty** path is an `ArgumentNullException` too, and a path that escapes the
        # container's root is refused by name. The resource reads `The specified storage path is
        # invalid.`, read out of the pinned `Microsoft.Xna.Framework.dll`.
        class StorageContainer
          extend CNA::Runtime::EventOwner
          private_class_method :new

          xna_event :Disposing

          attr_reader :DisplayName, :StorageDevice

          def IsDisposed
            return true if @disposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_storage_container_get_is_disposed", @handle, output)
            !output[0, 1].unpack1("C").zero?
          end

          def DirectoryExists(directory) = exists?("cna_storage_container_directory_exists", directory, "directory")
          def FileExists(file) = exists?("cna_storage_container_file_exists", file, "file")

          def CreateDirectory(directory)
            act("cna_storage_container_create_directory", directory, "directory")
          end

          def DeleteDirectory(directory)
            act("cna_storage_container_delete_directory", directory, "directory")
          end

          def DeleteFile(file) = act("cna_storage_container_delete_file", file, "file")

          def CreateFile(file)
            view = validated(file, "file")
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_storage_container_create_file", @handle,
                                     view.read_u64(0), view.read_u64(8), output)
            CNA::Runtime::StorageStream.__send__(:from_native, output[0, 8].unpack1("Q"), String(file))
          end

          #     OpenFile(file, fileMode)
          #     OpenFile(file, fileMode, fileAccess)
          #     OpenFile(file, fileMode, fileAccess, fileShare)
          def OpenFile(file, fileMode, fileAccess = nil, fileShare = nil)
            view = validated(file, "file")
            mode = CNA::Runtime::Stream::FileMode.coerce(fileMode).to_i
            output = CNA::Native.library.pointer_for("Q", 0)
            if fileAccess.nil?
              CNA::Native.library.call("cna_storage_container_open_file", @handle,
                                       view.read_u64(0), view.read_u64(8), mode, output)
            elsif fileShare.nil?
              CNA::Native.library.call("cna_storage_container_open_file_access", @handle,
                                       view.read_u64(0), view.read_u64(8), mode,
                                       CNA::Runtime::Stream::FileAccess.coerce(fileAccess).to_i, output)
            else
              CNA::Native.library.call("cna_storage_container_open_file_share", @handle,
                                       view.read_u64(0), view.read_u64(8), mode,
                                       CNA::Runtime::Stream::FileAccess.coerce(fileAccess).to_i,
                                       CNA::Runtime::Stream::FileShare.coerce(fileShare).to_i, output)
            end
            CNA::Runtime::StorageStream.__send__(:from_native, output[0, 8].unpack1("Q"), String(file))
          end

          # `GetDirectoryNames()` is `GetDirectoryNames("*")` and both answer a **fresh array**.
          def GetDirectoryNames(searchPattern = "*")
            names("cna_storage_container_get_directory_name_count",
                  "cna_storage_container_copy_directory_name", searchPattern)
          end

          def GetFileNames(searchPattern = "*")
            names("cna_storage_container_get_file_name_count",
                  "cna_storage_container_copy_file_name", searchPattern)
          end

          # `Dispose()` is `Dispose(true); GC.SuppressFinalize(this);` and `Dispose(bool)` raises
          # `Disposing` before it releases anything. Ruby cannot give one name two visibilities, so
          # the two CLR overloads project to one public arity-dispatching method — the rule
          # `GameComponent` and `ContentManager` already follow — and the widening is recorded.
          def Dispose(disposing = true)
            return nil if @disposed
            return nil unless disposing

            @disposed = true
            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
            begin
              CNA::Native.library.call("cna_storage_container_dispose", @handle)
            rescue CNA::NativeError
              nil
            end
            begin
              CNA::Native.library.call("cna_storage_container_destroy", @handle)
            rescue CNA::NativeError
              nil
            end
            nil
          end

          # `Finalize()` is `try { Dispose(false); } finally { base.Finalize(); }`, and
          # `Dispose(false)` returns at its first instruction — so the CLR finalizer does nothing
          # observable. Projected as the member the contract declares, doing the same nothing.
          # Ruby's garbage collector never calls it: no `ObjectSpace.define_finalizer` is registered.
          def Finalize = nil

          private

          def initialize_native(device, handle)
            @StorageDevice = device
            @handle = handle
            @disposed = false
            @DisplayName = CNA::Native.library.counted_string(
              "cna_storage_container_get_display_name_size",
              "cna_storage_container_copy_display_name", handle
            )
            self
          end

          def native_handle = @handle

          def verify_not_disposed!
            raise CNA::DisposedObjectError, "StorageContainer" if self.IsDisposed
          end

          # `ValidateArguments`, whose first step is the disposed check and whose second refuses an
          # empty string as null. The root-escape check is CNA's: it resolves the path against the
          # container root and refuses one that leaves it.
          def validated(path, name)
            verify_not_disposed!
            raise ::ArgumentError, name if path.nil? || String(path).empty?

            CNA::Native::Layouts::StringView.new(String(path).b)
          end

          def exists?(symbol, path, name)
            view = validated(path, name)
            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call(symbol, @handle, view.read_u64(0), view.read_u64(8), output)
            !output[0, 1].unpack1("C").zero?
          end

          def act(symbol, path, name)
            view = validated(path, name)
            CNA::Native.library.call(symbol, @handle, view.read_u64(0), view.read_u64(8))
            nil
          end

          # `searchPattern` is not a path and is not validated as one — the IL passes it straight to
          # `DirectoryInfo.GetDirectories` — so only the disposed check applies.
          def names(count_symbol, copy_symbol, searchPattern)
            verify_not_disposed!
            pattern = searchPattern.nil? ? "*" : String(searchPattern)
            view = CNA::Native::Layouts::StringView.new(pattern.b)
            count = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call(count_symbol, @handle, view.read_u64(0), view.read_u64(8), count)
            ::Array.new(count[0, 8].unpack1("Q")) do |index|
              CNA::Native.library.counted_string_at(copy_symbol, @handle, view, index)
            end
          end

          class << self
            private

            def from_native(device, handle) = allocate.__send__(:initialize_native, device, handle)
          end
        end
      end
    end
  end
end
