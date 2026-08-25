# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
      #
      # `.class public abstract auto ansi sealed beforefieldinit` — a C# `static class` whose whole
      # public surface is `static void Update()`. It has no public constructor; its `.cctor` only
      # allocates the two static `List<ManagedCallAndArg>` buffers.
      #
      # `Update` sets the assembly-internal `UpdateCalledAtLeastOnce` flag, calls `PollForEvents`,
      # then drains the static `pendingCalls` list under a `Monitor` and dispatches each entry to
      # one of five managed sinks: `Media.MediaPlayer.OnActiveSongChanged`,
      # `Media.MediaPlayer.OnMediaStateChanged`, `Audio.Microphone.AllMicrophones`,
      # `Audio.DynamicSoundEffectInstance.RaiseBufferNeededOnInstance` and
      # `FrameworkCallbackLinker.OnStorageDeviceChanged`. It takes no arguments, returns void and
      # validates nothing.
      #
      # Two measured facts about that body matter here. First, in this **Windows** assembly
      # `PollForEvents` is `{ ret }` — an empty method — so `Update` reaches no native entry point
      # at all, which is why the hash-admitted IL inventory records this type as
      # `nativeReachable: false`. Second, the queue it drains is filled by XNA's own audio and
      # media internals through `AddNewPendingCall`; `Update` is the point at which that
      # accumulated work is handed to managed code.
      #
      # This binding's audio and media *are* CNA, so the faithful analogue of draining XNA's queue
      # is draining CNA's. `cna_framework_dispatcher_update` is the canonical operation that does
      # it, and this projection forwards to it. The pump is therefore real — it is the same
      # operation CNA's own game loop drives, not a Ruby no-op standing in for one, which is what
      # a pure-managed projection with nothing to fill its queue would have been. What is absent
      # is the managed fan-out, because none of the five XNA sinks above is projected yet; when
      # one of them is, it subscribes to the pump that already runs here rather than to a second
      # one this binding would otherwise have had to invent.
      #
      # DEVIATION, recorded rather than hidden: XNA's dispatcher is a pure static usable with no
      # `Game` in existence — that is its documented purpose, driving audio and media for an
      # application that does not run the game loop. The canonical CNA C ABI takes a game handle
      # for thread affinity only, so this projection requires a live CNA `Game` on its owner
      # thread and raises `CNA::InvalidBindingStateError` without one and `CNA::OwnerThreadError`
      # off it. Calling it while the loop runs is harmless and, as the canonical header states,
      # simply does the work twice.
      class FrameworkDispatcher
        class << self
          def new(*) = raise(TypeError, "FrameworkDispatcher is static")

          def Update
            host = CNA::Runtime::Context.native_host("FrameworkDispatcher.Update")
            CNA::Native.library.call("cna_framework_dispatcher_update", host.handle)
            nil
          end
        end
        private_class_method :new
      end
    end
  end
end
