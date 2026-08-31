# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # The `Storage` namespace contains exactly one projected type and nothing else, which is the
      # same shape `Audio` and `Media` took when Foundation 16 opened them for their enums. There is
      # no StorageDevice, StorageContainer, save-game enumeration, title storage or file system of
      # any kind here: the selected profile's other Storage types are still missing, and nothing in
      # this binding opens, reads or writes a storage container.
      module Storage
        # Derived from the pinned Microsoft.Xna.Framework.Storage.dll IL.
        #
        # Extends `System.Runtime.InteropServices.ExternalException`, which the BCL register maps to
        # `StandardError` — a deliberate, documented loss of one CLR inheritance level, because the
        # selected XNA surface never names `ExternalException` itself. Four constructors, every one a
        # pure forward to its base, the fourth being the `family`
        # `(SerializationInfo info, StreamingContext context)`.
        #
        # Nothing in this binding raises it: no storage device is queried, so none can be
        # disconnected.
        class StorageDeviceNotConnectedException < StandardError
          include CNA::Runtime::XnaSerializableExceptionConstruction
        end
      end
    end
  end
end
