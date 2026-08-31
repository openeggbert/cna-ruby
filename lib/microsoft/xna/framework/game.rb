# frozen_string_literal: true

require "monitor"

module Microsoft
  module Xna
    module Framework
      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # `.class public auto ansi beforefieldinit`, extending `System.Object` and implementing
      # `IGameComponent`, `IUpdateable` and `System.IDisposable`. Fourteen identities over three
      # private fields and three delegate fields, reaching no native entry point and holding no
      # unmanaged resource: it is pure managed behaviour throughout.
      #
      # The two XNA contracts it implements are projected as Ruby modules and really included, which
      # is what `Game`'s engine tests with `is_a?`. That is the faithful analogue of the CLR's
      # `isinst`: a nominal interface test needs a nominal Ruby relation, and duck-typing on member
      # names would answer true for a type that never declared the contract. Every member either
      # module declares is overridden here, so no abstract `NotImplementedError` survives.
      #
      # `System.IDisposable` is the third, and it contributes no inclusion because Foundation 36
      # measured it as a structural collapse: the interface declares one member, `Dispose()`, which
      # this type declares publicly, so the contract survives as that member and no module exists to
      # include.
      class GameComponent
        extend CNA::Runtime::EventOwner
        include IGameComponent
        include IUpdateable

        xna_event :EnabledChanged
        xna_event :UpdateOrderChanged
        xna_event :Disposed

        # `.ctor(Game game)` is twenty-one bytes: `enabled = true` as a field initialiser, then
        # `Object..ctor()`, then `game = game`. There is **no null check**, so a component with no
        # Game is legal and `Dispose` below is written for it. `updateOrder` gets the CLR's default
        # 0 because nothing assigns it.
        def initialize(game)
          unless game.nil? || game.is_a?(Game)
            raise TypeError, "game must be a Game"
          end

          @Enabled = true
          @UpdateOrder = 0
          @game = game
          # `lock (this)` in `Dispose(bool)` is `Monitor.Enter(this)`, which is **reentrant**: a
          # Disposed handler that disposes the same component again re-enters rather than
          # deadlocking. Ruby's Mutex is not reentrant and ::Monitor is, so ::Monitor is the exact
          # analogue. It is per-instance because the CLR locks the instance.
          @monitor = ::Monitor.new
        end

        # `get_Enabled` and `get_UpdateOrder` are one `ldfld` each; `get_Game` likewise, and it has
        # no setter in the contract.
        attr_reader :Enabled, :UpdateOrder

        def Game = @game

        # `set_Enabled(bool)` and `set_UpdateOrder(int32)` are the same five instructions:
        #
        #     if (field == value) return;          // same-value suppression, before anything else
        #     field = value;                       // the field is written *before* the notification
        #     OnEnabledChanged(this, EventArgs.Empty);
        #
        # So a handler always observes the new value, and setting a property to what it already
        # holds raises nothing at all.
        def Enabled=(value)
          value = value ? true : false unless value == true || value == false
          return if @Enabled == value

          @Enabled = value
          self.OnEnabledChanged(self, CNA::Runtime::EventArgs::Empty)
          value
        end

        def UpdateOrder=(value)
          value = CNA::Runtime::Numeric.int32(value, "value")
          return if @UpdateOrder == value

          @UpdateOrder = value
          self.OnUpdateOrderChanged(self, CNA::Runtime::EventArgs::Empty)
          value
        end

        # `Initialize()` and `Update(GameTime)` are each a bare `ret` — public virtual hooks with
        # genuinely no base behaviour, not placeholders. A subclass overrides them and `super` runs
        # the nothing the base really does.
        def Initialize = nil

        def Update(gameTime)
          require_game_time(gameTime)
          nil
        end

        # `Dispose()` is `Dispose(true)` followed by `GC.SuppressFinalize(this)`;
        # `Dispose(bool disposing)` is the `family virtual` extension point. Ruby cannot give one
        # name two visibilities, so the two CLR overloads project to one public method dispatching
        # on arity — the rule mapping-rules.json already applies to every other overload set — and
        # the static contract retains both signature identities. The widening is recorded: the
        # protected overload is publicly reachable here, which it is not in the CLR.
        #
        # The two bodies differ only by `GC.SuppressFinalize`, which needs no Ruby analogue because
        # nothing registers a Ruby finalizer for this type in the first place (see `Finalize`), so
        # `Dispose` and `Dispose(true)` really do coincide.
        #
        #     if (!disposing) return;
        #     lock (this) {
        #       if (Game != null) Game.Components.Remove(this);   // result popped
        #       if (Disposed != null) Disposed(this, EventArgs.Empty);
        #     }
        #
        # Two measured consequences. The removal happens **before** the notification, so a Disposed
        # handler sees the component already out of `Game.Components`. And there is **no disposed
        # flag anywhere in the type**, so disposing twice removes twice — the second `Remove`
        # answers false and is discarded — and raises `Disposed` twice. Reproduced, not corrected.
        def Dispose(disposing = true)
          return nil unless disposing

          @monitor.synchronize do
            self.Game&.Components&.Remove(self)
            self.Disposed.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          end
          nil
        end

        protected

        # `Finalize()` is `try { Dispose(false); } finally { base.Finalize(); }`, and `Dispose(false)`
        # returns at its first instruction, so the CLR finalizer for this type does **nothing
        # observable**. It is projected as the member the contract declares and it does the same
        # nothing.
        #
        # Ruby's garbage collector never calls it: no `ObjectSpace.define_finalizer` is registered
        # here and none is invented, which is also why `GC.SuppressFinalize` in `Dispose()` needs no
        # analogue — there is nothing to suppress.
        def Finalize
          self.Dispose(false)
          nil
        end

        # `OnEnabledChanged(object sender, EventArgs args)` and `OnUpdateOrderChanged(...)` are
        # `family virtual`, and both carry the same Microsoft quirk: the declared `sender` parameter
        # is **ignored**. The IL loads `ldarg.0` — `this` — as the delegate's sender and `ldarg.2`
        # as the args, so `ldarg.1` is never read. A subclass that calls the base with some other
        # sender still raises the event with the component itself. Recorded and reproduced.
        def OnEnabledChanged(sender, args)
          self.EnabledChanged.__send__(:dispatch, self, args)
          nil
        end

        def OnUpdateOrderChanged(sender, args)
          self.UpdateOrderChanged.__send__(:dispatch, self, args)
          nil
        end

        private

        def require_game_time(value)
          raise TypeError, "gameTime must be GameTime" unless value.instance_of?(GameTime)
        end
      end

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # A sealed `Collection<IGameComponent>` with two events and four overridden hooks, and the
      # first shipped type in this binding whose CLR base is a projected BCL generic. Ruby has class
      # inheritance, so it really inherits from `CNA::Runtime::Collection` and the whole
      # `Collection<T>` public surface — `Count`, the indexer, `Add`, `Clear`, `Contains`, `CopyTo`,
      # `GetEnumerator`, `IndexOf`, `Insert`, `Remove`, `RemoveAt` — arrives by inheritance rather
      # than being flattened into unrelated methods here. The CLR type argument cannot live in the
      # superclass expression because a Ruby class is not statically generic, so it is declared as
      # metadata and the API verifier measures it.
      #
      # The type declares no public member of its own at all. Its whole contribution is four
      # `protected virtual` overrides and two events, which is exactly what `Collection<T>` was
      # designed for: every public mutation the base publishes routes through a hook, and these four
      # hooks are where the component rules live.
      class GameComponentCollection < CNA::Runtime::Collection
        extend CNA::Runtime::EventOwner

        projects_elements "Microsoft.Xna.Framework.IGameComponent"

        # `.ctor()` is one call to the base parameterless constructor, so the collection owns a
        # fresh backing list and never a caller's.
        def initialize
          super()
        end

        # The two CLR events. Both are `EventHandler<GameComponentCollectionEventArgs>`, and both
        # are raised only from the hooks below — the CLR's `OnComponentAdded`/`OnComponentRemoved`
        # are `private`, not `protected`, so neither is an identity a consumer or a subclass reaches.
        xna_event :ComponentAdded
        xna_event :ComponentRemoved

        protected

        # `InsertItem(int32, IGameComponent)`.
        #
        # Three steps, in this order:
        #
        #   1. `if (base.IndexOf(item) != -1) throw new ArgumentException(...)`. The duplicate check
        #      runs **before** the insertion and before any index validation the base performed, and
        #      it uses `IndexOf`, so it is element equality rather than identity. Its CLR message is
        #      the localized resource `CannotAddSameComponentMultipleTimes`, which is not reproduced.
        #   2. `base.InsertItem(index, item)` — the mutation.
        #   3. `if (item != null) OnComponentAdded(new GameComponentCollectionEventArgs(item))`.
        #
        # So the event fires **after** the collection already contains the component, and a null
        # component is inserted silently: the IL's null check guards the event, not the insertion.
        # A *second* null is still rejected by step 1, because `IndexOf(null)` finds the first one.
        def InsertItem(index, item)
          require_game_component!(item)
          raise ArgumentError if self.IndexOf(item) != -1

          super(index, item)
          raise_component_event(:ComponentAdded, item) unless item.nil?
          nil
        end

        # `RemoveItem(int32)`.
        #
        #   1. `item = base[index]` — read **before** the removal, through the base indexer, so an
        #      out-of-range index raises there rather than here.
        #   2. `base.RemoveItem(index)` — the mutation.
        #   3. `if (item != null) OnComponentRemoved(new GameComponentCollectionEventArgs(item))`.
        #
        # Same shape as InsertItem: mutation first, event second, null component silent.
        def RemoveItem(index)
          item = self[index]
          super(index)
          raise_component_event(:ComponentRemoved, item) unless item.nil?
          nil
        end

        # `SetItem(int32, IGameComponent)` is `newobj NotSupportedException; throw` and nothing else
        # — eleven bytes of IL with no branch. Its CLR message is the localized resource
        # `CannotSetItemsIntoGameComponentCollection`, which is not reproduced.
        #
        # The refusal is reached *through* `Collection<T>::set_Item`, which validates first, so the
        # order is observable: an out-of-range index raises `RangeError` and never gets here, and a
        # read-only backing list raises `NotSupportedError` from the base for a different reason.
        def SetItem(index, item)
          raise CNA::Runtime::NotSupportedError
        end

        # `ClearItems()`, and the one hook whose ordering is the opposite of the others:
        #
        #     for (i = 0; i < base.Count; i++) OnComponentRemoved(new ...(base[i]));
        #     base.ClearItems();
        #
        # Every event fires **before** any mutation, in index order, and `Count` is re-read on each
        # iteration — so a handler that adds a component during `Clear` extends the loop and that
        # component is announced as removed too, before being cleared with the rest.
        #
        # There is also no null check here, unlike the other two hooks: a null element produces a
        # `GameComponentCollectionEventArgs` carrying null and the event fires for it.
        def ClearItems
          index = 0
          while index < self.Count
            raise_component_event(:ComponentRemoved, self[index])
            index += 1
          end
          super()
          nil
        end

        private

        # `OnComponentAdded`/`OnComponentRemoved` are `private` in the CLR and each is the same four
        # instructions: a null check on the delegate, then `Invoke(this, eventArgs)`. The sender is
        # the collection and the args are freshly constructed per notification, so no two handlers
        # of two different notifications ever see the same args object.
        def raise_component_event(identity, component)
          public_send(identity)
            .__send__(:dispatch, self, GameComponentCollectionEventArgs.new(component))
          nil
        end

        # The CLR base is `Collection<IGameComponent>`, and that type argument is a static
        # constraint the CLR enforces at every entry point. A Ruby class is not statically generic,
        # so the constraint is carried as `projects_elements` metadata for the verifier and enforced
        # here at the one point every insertion passes through. This is the boundary check
        # `GameComponentCollectionEventArgs` already ships, on the same type and for the same
        # reason; null is admitted because `Collection<IGameComponent>` admits it.
        def require_game_component!(item)
          return if item.nil? || item.is_a?(IGameComponent)

          raise TypeError, "item must be an IGameComponent"
        end
      end

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # `.class public abstract auto ansi beforefieldinit`, extending `System.Object`. Twenty
      # selected identities: eleven methods, six properties and three events.
      #
      # ## It is a façade over CNA's window, not a second object
      #
      # Six of its members are `abstract` -- `Handle`, `AllowUserResizing` both ways, `ClientBounds`,
      # `ScreenDeviceName`, `CurrentOrientation` -- plus `BeginScreenDeviceChange`, the three-argument
      # `EndScreenDeviceChange`, `SetTitle` and `SetSupportedOrientations`. XNA leaves every one of
      # them for a concrete host to supply, and the canonical C ABI supplies exactly that set.
      #
      # Every one of those routes is addressed through the **game** handle: CNA's window has no
      # handle of its own. So there is no second object to invent and no second lifetime to
      # reconcile -- this class holds one reference to the Game and forwards, which is what the
      # graphics-device-service producer audit's rule asks for. A route reached after the Game is
      # disposed raises, because the window it names no longer exists.
      #
      # ## What is managed and what is the host's
      #
      # `Title`'s getter is one `ldfld` of a private field and its setter is validation plus a push
      # through the abstract `SetTitle`, which reads like the `IsMouseVisible` shape. It is *not*
      # projected as managed state, and the reason is measured: the abstract constructor sets
      # `title = String.Empty`, but `WindowsGameWindow`'s constructor immediately calls
      # `set_Title(GetDefaultTitleName())`, so the value a consumer actually observes before writing
      # one is the **host's** default, not the empty string. CNA's host has its own default, carried
      # by `CNA_GameCreateInfo::window_title`, and `cna_game_window_copy_title` reads it back. So the
      # read forwards and the write pushes, with the abstract class's own two validations applied
      # here: `ArgumentNullException` on a null title, and a same-value write suppressed before the
      # push, which the IL performs with `String::op_Inequality`.
      #
      # ## What HEADLESS answers, and why none of it is fabricated
      #
      # Measured on the reviewed artifact: `ClientBounds` is `0,0,0,0`, `Handle` is `0`,
      # `ScreenDeviceName` is empty and `CurrentOrientation` is `Default`. Those are CNA's honest
      # answers for a platform with no native window -- the same shape `Mouse.WindowHandle` already
      # reports -- and not one of them is replaced by an invented default. `AllowUserResizing`
      # round-trips through the real route, and `Title` round-trips through the create info.
      class GameWindow
        extend CNA::Runtime::EventOwner

        # The three **public** events. XNA declares six event fields, but `Activated`, `Deactivated`
        # and `Paint` are `assembly` -- internal plumbing between the host and `Game` -- so they are
        # not identities and no reader exists for them. The canonical C ABI agrees exactly: it
        # defines three `CNA_GAME_WINDOW_EVENT_*` identities and they are these three.
        xna_event :ScreenDeviceNameChanged
        xna_event :ClientSizeChanged
        xna_event :OrientationChanged

        # `.ctor()` is `assembly`, so `new` is private under the rule Foundation 25 established:
        # a CLR class whose only constructor is internal projects with construction made private.
        # `Game` reaches it through `__send__`.
        def initialize(game)
          @game = game
        end
        private_class_method :new

        # `get_Title` reads the field the host seeded; here that is CNA's own window title.
        def Title = read_string("cna_game_window_get_title_size", "cna_game_window_copy_title")

        # `set_Title(string)`, exactly:
        #
        #     if (value == null) throw new ArgumentNullException("value", Resources.TitleCannotBeNull);
        #     if (title != value) { title = value; SetTitle(title); }
        #
        # The same-value suppression is observable -- it is why setting the current title pushes
        # nothing -- so it is reproduced rather than simplified away.
        def Title=(value)
          raise ArgumentError, "title must not be nil" if value.nil?

          title = String(value)
          return title if title == self.Title

          push_title(title)
          title
        end

        # `get_Handle` is abstract; the canonical route is documented as the platform's own window
        # token. On a platform with no native window it is zero, which is what HEADLESS answers and
        # what this reports rather than hiding. `System.IntPtr` projects to a Ruby Integer under the
        # established primitive mapping.
        def Handle = read_u64("cna_game_window_get_native_handle_ext")

        def AllowUserResizing = read_bool("cna_game_window_get_allow_user_resizing")

        def AllowUserResizing=(value)
          flag = value ? true : false
          call("cna_game_window_set_allow_user_resizing", flag ? 1 : 0)
          flag
        end

        # `get_ClientBounds` is abstract and answers a `Rectangle` by value, so the projection
        # copies the native POD into a fresh managed value rather than handing out a view.
        def ClientBounds
          value = CNA::Native::Layouts::Rectangle.new
          call("cna_game_window_get_client_bounds", value.pointer)
          Rectangle.new(value.read_i32(0), value.read_i32(4), value.read_i32(8), value.read_i32(12))
        end

        def ScreenDeviceName
          read_string("cna_game_window_get_screen_device_name_size",
                      "cna_game_window_copy_screen_device_name")
        end

        def CurrentOrientation = DisplayOrientation.coerce(read_u32("cna_game_window_get_current_orientation"))

        # `BeginScreenDeviceChange(bool)` is abstract, and the C ABI documents the pair the same way
        # XNA does: this records the intent and the other applies it.
        def BeginScreenDeviceChange(willBeFullScreen)
          flag = willBeFullScreen ? true : false
          call("cna_game_window_begin_screen_device_change", flag ? 1 : 0)
          nil
        end

        # Two overloads. The three-argument one is abstract; the one-argument one is concrete and is
        # thirty bytes: `EndScreenDeviceChange(name, ClientBounds.Width, ClientBounds.Height)`. The C
        # ABI collapses them into one route that reads a non-positive size as "keep it", so the
        # one-argument form is projected as XNA writes it -- through the current client bounds --
        # rather than by passing the sentinel, which keeps the two overloads observably identical to
        # the CLR pair.
        def EndScreenDeviceChange(screenDeviceName, clientWidth = nil, clientHeight = nil)
          raise ArgumentError, "screenDeviceName must not be nil" if screenDeviceName.nil?

          if clientWidth.nil? && clientHeight.nil?
            bounds = self.ClientBounds
            clientWidth = bounds.Width
            clientHeight = bounds.Height
          end
          bytes = String(screenDeviceName).encode(Encoding::UTF_8).b
          call("cna_game_window_end_screen_device_change", Fiddle::Pointer[bytes], bytes.bytesize,
               CNA::Runtime::Numeric.int32(clientWidth, "clientWidth"),
               CNA::Runtime::Numeric.int32(clientHeight, "clientHeight"))
          nil
        end

        protected

        # The six `family` raisers, each twenty-six bytes: `if (X != null) X(this, EventArgs.Empty)`.
        # Three raise a public event; the other three raise an `assembly` one that projects to no
        # reader at all, so they are declared -- the contract names them -- and raise nothing, which
        # is exactly what an absent invocation list does.
        def OnScreenDeviceNameChanged
          self.ScreenDeviceNameChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          nil
        end

        def OnClientSizeChanged
          self.ClientSizeChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          nil
        end

        def OnOrientationChanged
          self.OrientationChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
          nil
        end

        def OnActivated = nil
        def OnDeactivated = nil
        def OnPaint = nil

        # `SetTitle(string)` is `family abstract`, the push half of `Title=`. `WindowsGameWindow`
        # implements it as `mainForm?.Text = title`; the canonical route is its analogue.
        def SetTitle(title)
          raise ArgumentError, "title must not be nil" if title.nil?

          push_title(String(title))
          nil
        end

        # `SetSupportedOrientations(DisplayOrientation)` is `famorassem abstract`. The canonical C
        # ABI exposes **no** route for it -- orientation is readable and not settable there -- so it
        # is declared, as the contract names it, and refuses rather than pretending to apply an
        # orientation the runtime never receives.
        def SetSupportedOrientations(orientations)
          DisplayOrientation.coerce(orientations)
          raise CNA::Runtime::NotSupportedError,
                "the canonical runtime exposes no supported-orientation route"
        end

        private

        # The bytes a `CNA_StringView` carries, handed to the decomposed route as its two eightbytes.
        # The buffer is held for the duration of the call and the ABI copies it, which is what the
        # route documents.
        def push_title(title)
          bytes = title.encode(Encoding::UTF_8).b
          call("cna_game_set_window_title", Fiddle::Pointer[bytes], bytes.bytesize)
          nil
        end

        def call(symbol, *arguments)
          CNA::Native.library.call(symbol, host_handle, *arguments)
          nil
        end

        def host_handle
          handle = @game.__send__(:window_host_handle)
          raise CNA::DisposedObjectError, "the Game that owns this window is disposed" if handle.nil?

          handle
        end

        def read_bool(symbol)
          output = CNA::Native.library.pointer_for("C", 0)
          call(symbol, output)
          output[0, 1].unpack1("C") != 0
        end

        def read_u32(symbol)
          output = CNA::Native.library.pointer_for("L", 0)
          call(symbol, output)
          output[0, 4].unpack1("L")
        end

        def read_u64(symbol)
          output = CNA::Native.library.pointer_for("Q", 0)
          call(symbol, output)
          output[0, 8].unpack1("Q")
        end

        # The canonical size-then-copy pair every string route in this ABI uses. An empty value has
        # size zero and needs no copy, which is what HEADLESS answers for the screen device name.
        def read_string(size_symbol, copy_symbol)
          size_output = CNA::Native.library.pointer_for("Q", 0)
          call(size_symbol, size_output)
          bytes = size_output[0, 8].unpack1("Q")
          return "" if bytes.zero?

          buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
          required = CNA::Native.library.pointer_for("Q", 0)
          call(copy_symbol, buffer, bytes, required)
          buffer[0, bytes].force_encoding(Encoding::UTF_8)
        end
      end

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # `.class public auto ansi beforefieldinit`, extending
      # `System.Collections.Generic.Dictionary`2<string,string>` and declaring **one** member of its
      # own in the selected contract: the public parameterless constructor. Its whole public surface
      # is therefore inherited, which Ruby class inheritance carries directly, and the ten interfaces
      # the contract lists are all inherited too -- `directInterfaces` is empty.
      #
      # The other two methods it declares are not identities. `ParseCommandLineArguments(string[])`
      # is `assembly` and `ParseKeyValuePair(string, out string, out string)` is `private`, so only
      # their *effect* is observable, through the inherited dictionary surface:
      #
      #     char[] trim = { '/', '-' };
      #     if (args.Length <= 1) return;              // element 0 is the executable path
      #     for (int i = 1; i < args.Length; i++) {
      #         string argument = args[i].TrimStart(trim);
      #         key = argument; value = String.Empty;
      #         int colon = argument.IndexOf(':');     // the FIRST colon only
      #         if (colon != -1) { key = argument.Substring(0, colon);
      #                            value = argument.Substring(colon + 1); }
      #         if (!ContainsKey(key) && key != String.Empty) Add(key, value);
      #     }
      #
      # Three details a summary would get wrong. An argument with **no colon** is kept, with the
      # empty string as its value -- it is not skipped. The **first** occurrence of a name wins,
      # because the guard is `ContainsKey` and the write is `Add`, which would otherwise throw. And
      # the split is on a colon, never an equals sign.
      #
      # ## Why this is managed and reads nothing native
      #
      # `Game.get_LaunchParameters` is one `ldfld`, the field is written in exactly one place --
      # `Game..ctor`, `newobj LaunchParameters::.ctor()` -- and **nothing in XNA ever reads it
      # again**. It is consumer-facing data the loop never consults, which is a stronger case than
      # the four timing properties, which the loop does read. So the projection is managed state and
      # creates no host, and `Environment.GetCommandLineArgs()` projects to Ruby's `ARGV`: XNA skips
      # element 0, the executable path, and `ARGV` already excludes it.
      #
      # The canonical CNA launch-parameter routes exist and are deliberately **not** used. Audited
      # against this IL they implement different semantics on three counts the inherited dictionary
      # surface makes observable: `cna_game_launch_parameters_parse_ext` documents that "an argument
      # shorter than three characters or without a colon is skipped silently", where XNA keeps a
      # colonless argument with an empty value; `cna_game_launch_parameters_add` "overwrites an
      # existing entry rather than refusing", which is `set_Item` and not `Add`; and its indexed
      # enumeration is sorted by name, "deliberately not the canonical container's own order". A
      # binding that read them would report a different map than XNA does.
      class LaunchParameters < CNA::Runtime::Dictionary
        clr_element_types! "System.String", "System.String"

        # The trim set is `{ '/', '-' }` -- 0x2F then 0x2D -- and the separator is `':'`, 0x3A.
        ARGUMENT_PREFIXES = "/-"
        private_constant :ARGUMENT_PREFIXES
        SEPARATOR = ":"
        private_constant :SEPARATOR

        def initialize(arguments = ::ARGV)
          super()
          parse_command_line_arguments(arguments)
        end

        private

        # `ParseCommandLineArguments` is `assembly`, so this is its effect and not an identity. XNA
        # is handed `GetCommandLineArgs()` and skips element 0; `ARGV` has no element 0 to skip, so
        # the loop starts at the beginning of what it is given and the `args.Length <= 1` guard
        # becomes the empty case.
        def parse_command_line_arguments(arguments)
          arguments.each do |argument|
            key, value = parse_key_value_pair(argument.to_s.sub(/\A[#{ARGUMENT_PREFIXES}]+/, ""))
            self.Add(key, value) unless self.ContainsKey(key) || key.empty?
          end
          nil
        end

        # `ParseKeyValuePair` is `private`. `String.IndexOf(char)` answers the **first** occurrence,
        # so a value containing a colon keeps it; a missing colon leaves the whole argument as the
        # key and `String.Empty` as the value.
        def parse_key_value_pair(argument)
          colon = argument.index(SEPARATOR)
          return [argument, ""] if colon.nil?

          [argument[0, colon], argument[(colon + 1)..] || ""]
        end
      end

      class Game
        extend CNA::Runtime::EventOwner

        attr_reader :GraphicsDevice

        # The four canonical Game events, in the pinned metadata's declaration order. Every one is
        # `EventHandler`1<EventArgs>`, and each projects to exactly one public Ruby reader over the
        # generic subscription primitive -- no writer, no add_/remove_ pair, and raising stays
        # internal, reached through the protected raisers below or, for `Disposed`, through
        # `Dispose` itself.
        #
        # Handlers may be added before the Game has ever run: the readers are ordinary managed
        # objects that exist from construction, and the native subscriptions that feed three of them
        # are created when the host is, which is later.
        xna_event :Activated
        xna_event :Deactivated
        xna_event :Exiting
        xna_event :Disposed

        # A CLR TimeSpan is 100-nanosecond ticks; this binding projects TimeSpan as Float seconds,
        # so the two pinned defaults are converted once, here, rather than spelled as magic seconds.
        TICKS_PER_SECOND = 10_000_000.0
        private_constant :TICKS_PER_SECOND
        # `TimeSpan.FromTicks(0x28b0b)` -- one sixtieth of a second.
        TARGET_ELAPSED_TIME_DEFAULT_TICKS = 166_667.0
        private_constant :TARGET_ELAPSED_TIME_DEFAULT_TICKS
        # `TimeSpan.FromMilliseconds(20)`.
        INACTIVE_SLEEP_TIME_DEFAULT_TICKS = 200_000.0
        private_constant :INACTIVE_SLEEP_TIME_DEFAULT_TICKS

        # Each getter is one `ldfld`: it reads the managed field and never consults the host, so it
        # answers before the Game has run, after it has run, and on a Game that never will.
        attr_reader :IsFixedTimeStep, :TargetElapsedTime, :InactiveSleepTime, :IsMouseVisible

        # `set_IsFixedTimeStep(bool)` is a bare field write with no validation at all.
        def IsFixedTimeStep=(value)
          value = value ? true : false unless value == true || value == false
          @IsFixedTimeStep = value
          push_native_game_setting("cna_game_set_is_fixed_time_step", value ? 1 : 0)
          value
        end

        # `set_TargetElapsedTime(TimeSpan)`:
        #
        #     if (value <= TimeSpan.Zero)
        #         throw new ArgumentOutOfRangeException("value", Resources.TargetElaspedCannotBeZero);
        #     targetElapsedTime = value;
        #
        # The comparison is `op_LessThanOrEqual`, so zero is rejected as well as negative -- which
        # is also what CNA's route documents, refusing a step that is not positive.
        def TargetElapsedTime=(value)
          seconds = CNA::Runtime::BclProjection.time_span(value)
          raise RangeError, "TargetElapsedTime must be greater than zero" unless seconds.positive?

          @TargetElapsedTime = seconds
          push_native_game_setting("cna_game_set_target_elapsed_time_ticks", ticks_for(seconds))
          seconds
        end

        # `set_InactiveSleepTime(TimeSpan)` is the same shape with `op_LessThan`, so **zero is
        # accepted** and only a negative duration is refused, despite the resource being named
        # `InactiveSleepTimeCannotBeZero`. CNA's route agrees: it refuses a negative duration.
        def InactiveSleepTime=(value)
          seconds = CNA::Runtime::BclProjection.time_span(value)
          raise RangeError, "InactiveSleepTime must not be negative" if seconds.negative?

          @InactiveSleepTime = seconds
          push_native_game_setting("cna_game_set_inactive_sleep_time_ticks", ticks_for(seconds))
          seconds
        end

        # `set_IsMouseVisible(bool)` writes the field first and then, **only when `Window` is not
        # null**, forwards to `Window.IsMouseVisible`. `GameWindow` is still a deferred type here, so
        # the window this forwards to is CNA's own -- `cna_game_set_is_mouse_visible` is documented
        # as showing or hiding the cursor over the game window -- and the null check becomes the
        # same question this binding can actually ask: whether a native host exists yet.
        def IsMouseVisible=(value)
          value = value ? true : false unless value == true || value == false
          @IsMouseVisible = value
          push_native_game_setting("cna_game_set_is_mouse_visible", value ? 1 : 0)
          value
        end

        # The construction order below is the one the pinned Game.dll `.ctor` performs, in its own
        # sequence. Two of its steps are field initialisers, which the CLR runs *before* the base
        # constructor, and the rest run after; what matters to a consumer is the relative order, and
        # it is preserved exactly:
        #
        #   1. the five private component lists                        (field initialiser)
        #   2. `gameServices = new GameServiceContainer()`             (field initialiser)
        #   3. `Object..ctor()`
        #   4. `FrameworkDispatcher.Update()`                          -- see below
        #   5. `EnsureHost()`                                          -- deferred here
        #   6. `launchParameters = new LaunchParameters()`             -- LaunchParameters missing
        #   7. `gameComponents = new GameComponentCollection()`
        #   8. `gameComponents.ComponentAdded += GameComponentAdded`
        #   9. `gameComponents.ComponentRemoved += GameComponentRemoved`
        #  10. `content = new ContentManager(gameServices)`            -- ContentManager missing
        #  11. `host.Window.Paint += Paint`                            -- GameWindow missing
        #  12. the clock and the four TimeSpan fields                  -- native timing here
        #
        # So **Services exists before Components**, and both exist by the time the constructor
        # returns. The steps this binding does not perform are each blocked on a type that is
        # missing or on lifecycle CNA owns, and none of them touches component state.
        #
        # Step 4 is the one worth naming. XNA pumps `FrameworkDispatcher.Update()` here and again
        # from `Game.Update`. The canonical CNA C ABI documents `cna_framework_dispatcher_update` as
        # pumping "the framework-wide per-frame work **the game loop normally drives**", so the CNA
        # host this Game delegates its loop to already performs it; and this binding's projection of
        # the dispatcher carries a recorded deviation -- it needs a live CNA Game on its owner
        # thread, which XNA's pure static does not. Calling it from here would therefore both pump
        # the same queue twice and fail on a Game that has not been run, which XNA's constructor
        # does not. Recorded rather than faked, in both places it appears.
        def initialize
          @updateable_components = []
          @currently_updating_components = []
          @drawable_components = []
          @currently_drawing_components = []
          @not_yet_initialized = []
          @gameServices = GameServiceContainer.new
          @owner_thread = Thread.current
          @monitor = ::Monitor.new
          @generation = CNA::Runtime::Generation.new(@owner_thread)
          @host = nil
          @graphics_manager = nil
          @GraphicsDevice = nil
          @native_children = []
          @disposed = false
          @has_run = false
          @in_run = false
          @exit_requested = false
          @suppress_draw_pending = false
          @inside_native_callback = false
          # The four timing/presentation defaults, exactly as the pinned `.ctor` sets them:
          # `isFixedTimeStep = true` as a field initialiser before the base constructor,
          # `targetElapsedTime = TimeSpan.FromTicks(0x28b0b)` -- 166667 ticks, one sixtieth of a
          # second -- and `inactiveSleepTime = TimeSpan.FromMilliseconds(20)`. `isMouseVisible` is
          # never assigned, so it keeps the CLR default `false`.
          #
          # All four are **managed** state here because they are managed state in XNA: every getter
          # is one `ldfld` and nothing else, and it is the host loop that reads the fields. So they
          # answer correctly on a Game that has never run, which is what XNA does, and each setter
          # pushes the new value down to CNA only once a native host exists.
          @IsFixedTimeStep = true
          @TargetElapsedTime = CNA::Runtime::BclProjection.time_span(TARGET_ELAPSED_TIME_DEFAULT_TICKS / TICKS_PER_SECOND)
          @InactiveSleepTime = CNA::Runtime::BclProjection.time_span(INACTIVE_SLEEP_TIME_DEFAULT_TICKS / TICKS_PER_SECOND)
          @IsMouseVisible = false
          @launchParameters = LaunchParameters.new
          @gameWindow = GameWindow.__send__(:new, self)
          @gameComponents = GameComponentCollection.new
          @gameComponents.ComponentAdded.add(method(:game_component_added))
          @gameComponents.ComponentRemoved.add(method(:game_component_removed))
          @updateable_order_changed = method(:updateable_update_order_changed)
          @drawable_order_changed = method(:drawable_draw_order_changed)
        end

        # `get_Components` and `get_Services` are each one `ldfld` and nothing else, so both answer
        # the same object for the life of the Game. Neither is fallible: the collection and the
        # container are ordinary managed objects that exist from the moment the constructor returns,
        # and neither goes through the native host or needs one.
        def Components = @gameComponents

        def Services = @gameServices

        # `get_LaunchParameters` is one `ldfld` and nothing else, so it answers the same object for
        # the life of the Game -- the one the constructor created -- and needs no native host.
        def LaunchParameters = @launchParameters

        # `get_Window` is `host?.Window`. XNA's null branch is defensive rather than reachable:
        # `Game..ctor` calls `EnsureHost()`, so a constructed XNA Game always has a host and this
        # property is never null. This binding defers that constructor step, so the faithful answer
        # is to complete it here -- the same `ensure_host` `Run`, `RunOneFrame` and `Tick` already
        # perform -- rather than to expose a nil XNA never shows. The façade itself is one managed
        # object created once and answered for the life of the Game, which is what `host.Window` is.
        #
        # Recorded deviation: completing the deferred step makes this getter owner-thread bound and
        # able to fail, where XNA's single `ldfld` chain cannot. That is the same asymmetry every
        # other native route in this binding carries.
        def Window
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          assert_owner_thread!
          ensure_host
          @gameWindow
        end

        # `get_IsActive` is thirty bytes and is **not** a field read. In full:
        #
        #     bool guideVisible = false;
        #     if (GamerServicesDispatcher.IsInitialized) guideVisible = Guide.IsVisible;
        #     if (!isActive) return false;
        #     return guideVisible == false;
        #
        # `Guide.get_IsVisible` throws `InvalidOperationException(GamerServicesNotInitialized)` when
        # the dispatcher is not initialised and otherwise answers `isVisible || forceGuideVisible`;
        # `GamerServicesDispatcher.get_IsInitialized` is `packetBuffer != null`, so that guard is the
        # only reason this getter never throws. Both are CLR statics, which is why the projection
        # reads them without a Game.
        #
        # All three terms have exactly one canonical CNA route, so the exact expression is
        # implemented rather than approximated. Nothing here fabricates a Guide state:
        # `cna_guide_get_is_visible` is *asked*, and what it answers is CNA's, not this binding's.
        # In the reviewed artifact it answers false and `cna_guide_set_is_visible` is accepted
        # without being reflected, so no guide can be raised behind it -- a property of that
        # runtime, recorded in the evidence, not an assumption baked into this expression.
        #
        # The IL's evaluation order is kept: the two GamerServices terms are read first, even when
        # `isActive` will decide the answer, because that is the order the pinned getter uses and
        # both routes are process-global, need no host, and work off the owner thread.
        #
        # `isActive` is the one term this binding does **not** mirror in managed state. XNA's field
        # is written by the host's own `HostActivated`/`HostDeactivated` handlers and only read by
        # consumers, so it is host-owned -- the `SuppressDraw` case, not the `TargetElapsedTime`
        # case -- and the projection forwards instead of keeping a shadow copy. Measured over a
        # real run, `cna_game_get_is_active` is false before the loop starts and already true
        # inside the `Activated` handler, which is exactly where XNA's `HostActivated` leaves the
        # field: written before the event is raised.
        #
        # Before a host exists there is nothing to ask and XNA's field is still at its CLR default,
        # so the answer is false and **no host is created** -- a getter that allocated a native
        # game would be a side effect XNA's single `ldfld` does not have.
        #
        # Recorded deviations: `cna_game_get_is_active` is owner-thread bound where XNA's getter is
        # not, so this raises off the owner thread once a host exists and does not before; and a
        # disposed Game raises rather than answering the last value XNA's field would still hold,
        # because the native game it would have to ask no longer exists.
        def IsActive
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?

          guide_visible = false
          guide_visible = read_native_flag("cna_guide_get_is_visible") if gamer_services_initialized?
          return false if @host.nil? || @host.handle.zero?

          assert_owner_thread!
          return false unless read_native_flag("cna_game_get_is_active", @host.handle)

          !guide_visible
        end

        # `Run()` is `RunGame(useBlockingRun: true)`, and `RunGame`'s body is wrapped in two things a
        # projection of `Run` alone would lose.
        #
        # The two `catch` clauses are the reason `ShowMissingRequirementMessage` exists at all:
        #
        #     catch (NoSuitableGraphicsDeviceException e) { if (!ShowMissingRequirementMessage(e)) rethrow; }
        #     catch (NoAudioHardwareException e)          { if (!ShowMissingRequirementMessage(e)) rethrow; }
        #
        # Both exception types are projected here, and a subclass's `Initialize`, `LoadContent` or
        # `Update` can raise either one -- the callback retains it and `GameHost#finish` re-raises it
        # on this side of C, inside this method -- so the clause is live and observable rather than
        # decorative. `rethrow` preserves the original exception, which is what a bare Ruby `raise`
        # inside a `rescue` does.
        #
        # The `finally` clears `inRun` unless `endRunRequired`, which only `StartGameLoop` sets and
        # which this binding never takes. Keeping it here rather than only in the `EndRun` hook is
        # what makes the flag survive a run that ends by raising, where `EndRun` is never delivered.
        def Run
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          raise CNA::InvalidBindingStateError, "Game.Run may only be called once" if @has_run
          assert_owner_thread!
          begin
            ensure_host
            @has_run = true
            @host.run
          rescue Graphics::NoSuitableGraphicsDeviceException, Audio::NoAudioHardwareException => error
            raise unless self.ShowMissingRequirementMessage(error)
          ensure
            @in_run = false
          end
          nil
        end

        def RunOneFrame
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          assert_owner_thread!
          ensure_host.run_one_frame
          nil
        end

        # `Tick()` and `RunOneFrame()` are two different XNA operations, and the pinned IL says so
        # in one line each. `Game.RunOneFrame` is `host?.RunOneFrame()`; `WindowsGameHost` implements
        # that as three steps -- `gameWindow.Tick()`, which rethrows the exception the WinForms pump
        # captured, then `GameHost.OnIdle()`, whose *only* subscriber is `Game.HostIdle` and whose
        # whole body is `this.Tick()`, then the `Guide.IsVisible` relay when GamerServices is
        # initialised. So `RunOneFrame` is literally host-event processing wrapped around `Tick`.
        #
        # The canonical C ABI keeps the identical split -- `cna_game_tick` is documented as "the
        # canonical frame step `cna_game_run_one_frame` wraps; it does not process host events" --
        # so the two bind separately and are deliberately **not** aliased. `test_game_tick.rb`
        # asserts they resolve to different native symbols so nobody later "simplifies" one away.
        #
        # `Tick`'s own first instruction is the one part of it that is not CNA's:
        #
        #     if (ShouldExit) return;
        #
        # `get_ShouldExit` is a single `ldfld exitRequested`, and `exitRequested` is written exactly
        # once in the whole assembly -- `ldc.i4.1` in `Game.Exit()` -- and **never cleared**. It is
        # a latch, so after `Exit()` XNA's `Tick` returns before it touches the clock, for the rest
        # of the Game's life. That field is managed state this binding already keeps and already
        # writes in exactly the same place, so the guard is projected here rather than delegated:
        # CNA's step, measured after `cna_game_request_exit`, still delivers one Update and skips
        # only the Draw, which is one callback more than XNA delivers.
        #
        # Everything after the latch is the timing loop, which CNA owns, and it is measured faithful
        # on the points the loop makes observable: the fixed step advances TotalGameTime by exactly
        # TargetElapsedTime per tick, a pending SuppressDraw skips exactly one Draw and clears
        # itself, and no lifecycle callback other than Update/BeginDraw/Draw/EndDraw is delivered --
        # Tick initialises nothing, which is why XNA's own `Initialize`/`BeginRun` live in `RunGame`
        # and not here.
        #
        # Recorded deviation: `cna_game_tick` is refused from inside a lifecycle callback, "because
        # a frame step called from within a frame would re-enter the loop it is part of". XNA has no
        # such guard, but it has no useful behaviour there either -- a `Tick` from inside `Update`
        # re-enters with `accumulatedElapsedGameTime` not yet decremented by the loop's `finally`,
        # so the recursive frame's `num` is again at least one and the recursion is unbounded,
        # ending in a `StackOverflowException` the CLR does not let anyone catch. The refusal is
        # surfaced as CNA's own translated error rather than pre-empted here, so the message a
        # consumer sees is the native contract's.
        def Tick
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          return nil if @exit_requested

          assert_owner_thread!
          ensure_host.tick
          nil
        end

        # `SuppressDraw()` is eight bytes: `suppressDraw = true`, and nothing else. The field's only
        # reader is `DrawFrame`, part of the timing loop CNA owns here, so the projection forwards
        # to the canonical route rather than keeping a shadow copy of a flag nothing else reads.
        #
        # Before a host exists there is no loop and no frame to skip, so the request is remembered
        # and delivered when the host is created -- which is the frame XNA would have suppressed,
        # the first one. It is a *pending* request rather than durable state: the loop consumes it
        # by skipping one draw, exactly as the CLR field is cleared after one frame.
        def SuppressDraw
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?

          if @host.nil? || @host.handle.zero?
            @suppress_draw_pending = true
          else
            assert_owner_thread!
            CNA::Native.library.call("cna_game_suppress_draw", @host.handle)
          end
          nil
        end

        # `ResetElapsedTime()` is four field writes:
        #
        #     forceElapsedTimeToZero = true;
        #     drawRunningSlowly = false;
        #     updatesSinceRunningSlowly1 = int.MaxValue;
        #     updatesSinceRunningSlowly2 = int.MaxValue;
        #
        # All four belong to the accumulator the timing loop drives, so all four are CNA's here and
        # the projection forwards. On a Game with no host there is no accumulated time to forget, so
        # the operation really is a no-op rather than being made into one.
        def ResetElapsedTime
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          return nil if @host.nil? || @host.handle.zero?

          assert_owner_thread!
          CNA::Native.library.call("cna_game_reset_elapsed_time", @host.handle)
          nil
        end

        def Exit
          raise CNA::DisposedObjectError, "Game is disposed" if disposed?
          @exit_requested = true
          @host&.request_exit
          nil
        end

        # The overridable lifecycle hooks, each carrying the base behaviour its pinned IL really
        # has. Ruby has class inheritance, so `super` *is* the analogue of `base.Initialize()` --
        # a subclass chooses whether, when and how many times to run the base, exactly as a CLR
        # override does, and this binding introduces no parallel base-call API. The native host
        # invokes the virtual Ruby method once and never runs the base itself.

        # `Game.Initialize()`:
        #
        #   1. `HookDeviceEvents()` -- reads `Services.GetService(typeof(IGraphicsDeviceService))`
        #      and subscribes four device events when it answers non-null. Foundation 40 completed
        #      that interface, so the key now exists; what still does not is a producer. Nothing in
        #      this binding registers one, and the producer audit settled why: CNA's own native Game
        #      is already the producer, into its own service container, and has already run this
        #      exact step. So the guard is false here and the method stays unreachably conditional.
        #      It touches no component state.
        #   2. the drain loop below.
        #   3. `if (graphicsDeviceService != null && graphicsDeviceService.GraphicsDevice != null)
        #      LoadContent();` -- guarded by the same service, so false here for the same reason.
        #      The CNA host delivers `load_content` as its own callback immediately after
        #      `initialize`, which is the canonical order its header documents and the order the
        #      audit measured, so nothing is called twice and nothing is skipped. Registering a
        #      managed producer to make this guard true was measured to produce **two**
        #      `LoadContent` calls, which is why it was not done.
        #
        # The drain loop is exact: `Initialize` is called on the element at index 0 and the element
        # is removed **after** it returns, and `Count` is re-read every iteration. So a component
        # added by another component's `Initialize` is picked up by the same loop, and a component
        # whose `Initialize` raises stays at the head of the queue.
        def Initialize
          until @not_yet_initialized.empty?
            @not_yet_initialized[0].Initialize
            @not_yet_initialized.delete_at(0)
          end
          nil
        end

        def LoadContent = nil
        def UnloadContent = nil

        # Both are `{ ret }` in the pinned IL -- genuinely no user work, not a placeholder.
        def BeginRun = nil
        def EndRun = nil

        # `Game.Update(GameTime)`:
        #
        #   1. copy `updateableComponents` into the reusable `currentlyUpdatingComponents`
        #   2. for each of those, `if (u.Enabled) u.Update(gameTime)`
        #   3. `currentlyUpdatingComponents.Clear()`
        #   4. `FrameworkDispatcher.Update()`
        #   5. `doneFirstUpdate = true`
        #
        # Step 1 is what makes mutation during the pass safe: the iteration walks a snapshot, so a
        # component added or removed by another component's `Update` takes effect from the next
        # frame. `Enabled` is *not* snapshotted -- it is read immediately before each call, so a
        # component disabled earlier in the same pass is skipped in that pass.
        #
        # Step 3 has no try/finally in the IL, so a component whose `Update` raises leaves the
        # snapshot list populated and the next pass appends to it. That is XNA's behaviour and it is
        # reproduced rather than corrected.
        #
        # Step 4 is not performed. The canonical CNA C ABI documents
        # `cna_framework_dispatcher_update` as pumping "the framework-wide per-frame work the game
        # loop normally drives", and the CNA host this Game delegates its loop to already drives it
        # every frame, so a managed call here would pump the same queue a second time. It would also
        # impose this binding's recorded `FrameworkDispatcher` deviation -- a live CNA Game on its
        # owner thread -- on `Game.Update`, which XNA's does not have, so `super` would fail on a
        # Game that has never run. Recorded, not faked.
        #
        # Step 5 sets a private field whose only readers, `Tick` and `DrawFrame`, are the native
        # timing loop CNA owns here, so it would be state nothing reads.
        def Update(game_time)
          require_game_time(game_time)
          index = 0
          while index < @updateable_components.length
            @currently_updating_components.push(@updateable_components[index])
            index += 1
          end
          index = 0
          while index < @currently_updating_components.length
            updateable = @currently_updating_components[index]
            updateable.Update(game_time) if updateable.Enabled
            index += 1
          end
          @currently_updating_components.clear
          nil
        end

        # `Game.BeginDraw()`: `if (graphicsDeviceManager != null && !graphicsDeviceManager.BeginDraw())
        # return false;` then a log event, then `true`. `GraphicsDeviceManager` is a deferred partial
        # whose `IGraphicsDeviceManager.BeginDraw` is an explicit interface implementation and so
        # projects to no member, and the logger is XNA-internal, so the base answers the `true` the
        # IL's only other exit answers.
        def BeginDraw = true

        # `Game.Draw(GameTime)` is `Game.Update`'s shape over the drawable list, and shorter: no
        # dispatcher pump and no first-frame flag.
        #
        #   1. copy `drawableComponents` into `currentlyDrawingComponents`
        #   2. for each, `if (d.Visible) d.Draw(gameTime)`
        #   3. `currentlyDrawingComponents.Clear()`
        #
        # Nothing here requires a device: the base decides which components to visit and each
        # component's own `Draw` decides what, if anything, it renders. No GraphicsDevice behaviour
        # is fabricated and none is required to observe the ordering.
        def Draw(game_time)
          require_game_time(game_time)
          index = 0
          while index < @drawable_components.length
            @currently_drawing_components.push(@drawable_components[index])
            index += 1
          end
          index = 0
          while index < @currently_drawing_components.length
            drawable = @currently_drawing_components[index]
            drawable.Draw(game_time) if drawable.Visible
            index += 1
          end
          @currently_drawing_components.clear
          nil
        end

        # `Game.EndDraw()`: `if (graphicsDeviceManager != null) graphicsDeviceManager.EndDraw();`
        # then a log event. Same two absences as BeginDraw, so the base does nothing.
        def EndDraw = nil

        # `Game.Dispose()` is `Dispose(true)` plus `GC.SuppressFinalize`, and `Dispose(bool)` opens
        # under `lock (this)` with the component pass:
        #
        #     array = new IGameComponent[gameComponents.Count];
        #     gameComponents.CopyTo(array, 0);
        #     foreach (x in array) if (x is IDisposable) x.Dispose();
        #     if (graphicsDeviceManager is IDisposable d) d.Dispose();
        #     UnhookDeviceEvents();
        #     if (Disposed != null) Disposed(this, EventArgs.Empty);
        #
        # Only the first three lines belong to this slice and only they are implemented here; the
        # rest of this method is the native ownership chain this binding already had, and
        # `Dispose(Boolean)`, `Finalize` and the `Disposed` event stay in Game's missing list.
        #
        # The pass is over a **snapshot array**, which is what makes it safe: each component's own
        # `Dispose` removes it from `Game.Components`, so iterating the live collection would skip
        # every other one. `x is IDisposable` has no nominal Ruby analogue, because Foundation 36
        # measured `System.IDisposable` as a structural collapse with no constant; under that rule
        # the contract survives as the member, so testing for the member is the projection of
        # testing for the interface. This is the first place the collapse has an observable
        # consequence.
        # The two CLR overloads project to one Ruby method dispatching on arity, which is the rule
        # Foundation 38 established for `GameComponent` and which widens the protected overload to
        # public -- a recorded mapping limitation Ruby cannot avoid, since one name cannot carry two
        # visibilities.
        #
        #     public void Dispose()                 => Dispose(true); GC.SuppressFinalize(this);
        #     protected virtual void Dispose(bool disposing) {
        #         if (!disposing) return;
        #         lock (this) { … }
        #     }
        #
        # `Dispose(false)` returns at its first instruction, so the finalizer path does nothing --
        # see `Finalize` below. `GC.SuppressFinalize` needs no analogue because no
        # `ObjectSpace.define_finalizer` is registered anywhere in this binding.
        #
        # The `lock (this)` is now taken. Foundation 41 recorded it as a deviation precisely because
        # it belongs to `Dispose(Boolean)`, which was missing; `::Monitor` is its analogue rather
        # than `Mutex`, because the CLR lock is reentrant and a `Mutex` would deadlock a `Disposed`
        # handler that disposed the Game again.
        #
        # `UnhookDeviceEvents()` sits between the manager's disposal and the `Disposed` event. Its
        # whole body is `if (graphicsDeviceService != null) { remove four handlers }`, and that field
        # is written only by `HookDeviceEvents`, which the graphics-device-service producer audit
        # deliberately omits. So it is a *genuine* no-op here rather than one made into one, and
        # nothing is fabricated in its place.
        def Dispose(disposing = true)
          return nil unless disposing
          return if disposed?
          assert_owner_thread!
          first_error = nil
          @monitor.synchronize do
            snapshot = Array.new(@gameComponents.Count)
            @gameComponents.CopyTo(snapshot, 0)
            snapshot.each do |component|
              next unless component.respond_to?(:Dispose)

              begin
                component.Dispose
              rescue Exception => error
                first_error ||= error
              end
            end
            @native_children.reverse_each do |child|
              begin
                child.Dispose
              rescue Exception => error
                first_error ||= error
              end
            end
            @native_children.clear
            begin
              @graphics_manager&.__send__(:dispose_native)
            rescue Exception => error
              first_error ||= error
            end
            begin
              @host&.destroy
            rescue Exception => error
              first_error ||= error
            end
            @generation.invalidate!
            @disposed = true
            # `Disposed` is the one Game event with no `On…` raiser: the IL raises it inline at the
            # end of `Dispose(Boolean)`'s `if (disposing)` body, with `this` as the sender and
            # `EventArgs.Empty` as the args, after the components and the graphics device manager have
            # been disposed and after `UnhookDeviceEvents()`. That is exactly this position.
            #
            # It is raised from here rather than relayed from CNA's own `CNA_GAME_EVENT_DISPOSED`,
            # and the reason is measured: that signal only exists once a native host exists, so a Game
            # that was constructed and disposed without ever running would raise nothing, while XNA
            # raises it for every disposal. Raising it here is right in both cases.
            #
            # Two recorded deviations, both inherited from this method rather than introduced by the
            # event. XNA's `Dispose(Boolean)` has **no disposed guard at all**, so calling `Dispose()`
            # twice runs the whole body twice and raises `Disposed` twice -- the same absence
            # Foundation 38 recorded for `GameComponent`. This binding's `Dispose` returns early when
            # already disposed, because native destruction is not repeatable, so the event is raised
            # **once**. And XNA's body runs under `Monitor.Enter(this)`, which belongs to
            # `Dispose(Boolean)` -- still one of Game's missing members -- and is not taken here.
            begin
              self.Disposed.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
            rescue Exception => error
              first_error ||= error
            end
          end
          raise first_error if first_error
          nil
        end

        # The three protected raisers, each reproducing its pinned IL exactly.
        #
        # All three declare a `sender` parameter and **none of them reads it**: the IL loads
        # `ldarg.0` -- `this` -- as the delegate's sender for `OnActivated` and `OnDeactivated`, so a
        # subclass calling the base with some other sender still raises with the Game itself. That
        # is the same shape `GameComponent.OnEnabledChanged` already has.
        #
        # `OnExiting` is the exception that a summary would get wrong. Its IL loads **`ldnull`**, so
        # XNA raises `Exiting` with a **null sender** while the other two raise with the Game. It is
        # not a quirk this binding is free to tidy up: a handler written against XNA may test the
        # sender, so the projection dispatches `nil`.
        #
        # In all three the `args` argument is `ldarg.2`, passed through unchanged rather than forced
        # to `EventArgs.Empty` -- the callers are the ones that supply `EventArgs.Empty`.
        def OnActivated(sender, args)
          self.Activated.__send__(:dispatch, self, args)
          nil
        end

        def OnDeactivated(sender, args)
          self.Deactivated.__send__(:dispatch, self, args)
          nil
        end

        # `Finalize()` is `try { Dispose(false); } finally { base.Finalize(); }`, and `Dispose(false)`
        # returns at its first instruction, so the CLR finalizer for this type does **nothing
        # observable**. It is projected as the member the contract declares and it does the same
        # nothing -- the same shape `GameComponent` already ships. Ruby's garbage collector never
        # calls it: no `ObjectSpace.define_finalizer` is registered here and none is invented.
        def Finalize
          self.Dispose(false)
          nil
        end

        # `ShowMissingRequirementMessage(Exception)` is `family newslot virtual` and is twenty-three
        # bytes: `host?.ShowMissingRequirementMessage(exception) ?? false`. `GameHost`'s own body is
        # `ldc.i4.0; ret` -- an unconditional **false** -- and only `WindowsGameHost` overrides it,
        # putting up a WinForms `MessageBox` for `NoSuitableGraphicsDeviceException` and
        # `NoAudioHardwareException`, returning true, and delegating anything else back to that base.
        #
        # CNA is the host here and it is not `WindowsGameHost`: the canonical C ABI exposes no
        # missing-requirement message route at all, so this answers the `GameHost` base's `false`.
        # That is not a stub standing in for a capability -- `false` is the truthful answer to
        # "did you show the message?", and it is the answer the abstract base really gives. `RunGame`
        # rethrows on false, so the exception still reaches the caller, which is the safe half of the
        # contract. A subclass that overrides this and answers true really does suppress both, which
        # is what makes the member observable rather than decorative.
        def ShowMissingRequirementMessage(_exception)
          false
        end

        def OnExiting(sender, args)
          self.Exiting.__send__(:dispatch, nil, args)
          nil
        end

        protected :Initialize, :LoadContent, :UnloadContent, :BeginRun, :EndRun,
                  :Update, :Draw, :BeginDraw, :EndDraw,
                  :OnActivated, :OnDeactivated, :OnExiting

        private

        attr_reader :owner_thread, :generation

        def disposed? = @disposed

        # The one thing `GameWindow` needs from its Game: the handle every canonical window route is
        # addressed through. Nil once the native game is gone, which is what makes a window member
        # reached after disposal raise instead of calling into a destroyed handle.
        def window_host_handle
          return nil if disposed? || @host.nil? || @host.handle.zero?

          assert_owner_thread!
          @host.handle
        end
        def __cna_exiting = nil

        def attach_graphics_manager(manager)
          raise ArgumentError, "a Game accepts exactly one GraphicsDeviceManager" if @graphics_manager
          @graphics_manager = manager
          @GraphicsDevice = manager.GraphicsDevice
        end

        def ensure_host
          return @host if @host
          @host = CNA::Runtime::GameHost.new(self)
          @host.create
          @graphics_manager&.__send__(:create_native, @host.handle)
          if @suppress_draw_pending
            @suppress_draw_pending = false
            CNA::Native.library.call("cna_game_suppress_draw", @host.handle)
          end
          @host.request_exit if @exit_requested
          @host
        rescue Exception => error
          begin
            @graphics_manager&.__send__(:dispose_native)
          rescue Exception
            # Preserve the creation error; all reachable handles retain their
            # normal explicit-disposal retry semantics.
          end
          begin
            @host&.destroy
          rescue Exception
            # Preserve the creation error at this boundary.
          end
          @host = nil
          raise error
        end

        def begin_native_callback
          @inside_native_callback = true
          @graphics_manager&.__send__(:begin_native_callback)
        end

        def end_native_callback
          @graphics_manager&.__send__(:end_native_callback)
          @inside_native_callback = false
        end

        def register_native_child(child)
          @native_children << child unless @native_children.any? { |value| value.equal?(child) }
        end

        def unregister_native_child(child)
          @native_children.reject! { |value| value.equal?(child) }
        end


        # ------------------------------------------------------------------ the component engine
        #
        # Four private handlers and two ordered lists, all derived from the pinned Game.dll IL.
        # None of them is an XNA identity: `GameComponentAdded`, `GameComponentRemoved`,
        # `UpdateableUpdateOrderChanged` and `DrawableDrawOrderChanged` are `private` in the CLR
        # too, and the four lists they maintain are private fields. What a consumer observes is the
        # order `Game.Update` and `Game.Draw` visit components in, and nothing else.

        # `GameComponentAdded(sender, e)`, in its exact order:
        #
        #   1. `inRun ? e.GameComponent.Initialize() : notYetInitialized.Add(e.GameComponent)`
        #   2. if it is an IUpdateable: BinarySearch, and **skip everything** when the search
        #      succeeds; otherwise insert at the upper bound of its UpdateOrder run and subscribe
        #      to UpdateOrderChanged.
        #   3. the same for IDrawable, DrawOrder and DrawOrderChanged.
        #
        # Step 1 runs for every component, including one that is neither updateable nor drawable.
        def game_component_added(_sender, args)
          component = args.GameComponent
          if @in_run
            component.Initialize
          else
            @not_yet_initialized.push(component)
          end
          if component.is_a?(IUpdateable)
            insert_ordered(@updateable_components, component, :UpdateOrder) do
              component.UpdateOrderChanged.add(@updateable_order_changed)
            end
          end
          return unless component.is_a?(IDrawable)

          insert_ordered(@drawable_components, component, :DrawOrder) do
            component.DrawOrderChanged.add(@drawable_order_changed)
          end
        end

        # `GameComponentRemoved(sender, e)`:
        #
        #   1. `if (!inRun) notYetInitialized.Remove(e.GameComponent)` -- the result is popped, so a
        #      component that was never queued is removed harmlessly.
        #   2. remove from updateableComponents and unsubscribe UpdateOrderChanged.
        #   3. the same for drawableComponents and DrawOrderChanged.
        #
        # Both removals pop their result too, so removing a component that is not in the list is
        # harmless, and the unsubscribe happens whether or not the removal found anything.
        def game_component_removed(_sender, args)
          component = args.GameComponent
          remove_first(@not_yet_initialized, component) unless @in_run
          if component.is_a?(IUpdateable)
            remove_first(@updateable_components, component)
            component.UpdateOrderChanged.remove(@updateable_order_changed)
          end
          return unless component.is_a?(IDrawable)

          remove_first(@drawable_components, component)
          component.DrawOrderChanged.remove(@drawable_order_changed)
        end

        # `UpdateableUpdateOrderChanged(sender, e)` and `DrawableDrawOrderChanged(sender, e)`: the
        # component is taken from **`sender`**, not from the args, then removed and reinserted at
        # its new position. The reinsertion is the same BinarySearch and upper-bound walk the add
        # path uses, so a component whose order changes lands after every component that already
        # has the new order.
        #
        # The `i >= 0` early return is reachable here in principle -- it means the search found a
        # component the removal did not, which requires an equality that is not identity -- and it
        # would drop the component from the list. That is XNA's behaviour and it is reproduced
        # rather than corrected.
        def updateable_update_order_changed(sender, _args)
          remove_first(@updateable_components, sender)
          insert_ordered(@updateable_components, sender, :UpdateOrder)
        end

        def drawable_draw_order_changed(sender, _args)
          remove_first(@drawable_components, sender)
          insert_ordered(@drawable_components, sender, :DrawOrder)
        end

        # `List<T>.Remove` pops its result and removes the **first** match by
        # EqualityComparer<T>.Default, which for a reference type is Object.Equals -- Ruby `==`.
        def remove_first(list, value)
          index = list.index { |candidate| candidate == value }
          list.delete_at(index) unless index.nil?
          nil
        end

        # The shared shape of all four insertion sites:
        #
        #     i = list.BinarySearch(item, Comparer.Default);
        #     if (i >= 0) return;                                   // already there: do nothing
        #     i = ~i;
        #     while (i < list.Count && list[i].Order == item.Order) i++;
        #     list.Insert(i, item);
        #
        # The `~i` is the CLR's own complement of the insertion point, and the walk that follows
        # moves it past every element sharing the new element's order -- so insertion is stable and
        # a component added later with an equal order runs later. The optional block runs only when
        # the insertion really happened, which is where the order-changed subscription lives.
        def insert_ordered(list, item, order)
          index = component_binary_search(list, item, order)
          return nil unless index.negative?

          index = ~index
          value = item.public_send(order)
          index += 1 while index < list.length && list[index].public_send(order) == value
          list.insert(index, item)
          yield if block_given?
          nil
        end

        # `UpdateOrderComparer.Compare` and `DrawOrderComparer.Compare` are the same five branches
        # over different properties:
        #
        #     x == null && y == null -> 0;  x == null -> 1;  y == null -> -1
        #     x.Equals(y)            -> 0
        #     x.Order < y.Order      -> -1
        #     otherwise              -> 1
        #
        # It answers 0 **only** for equal objects, never for two different components that share an
        # order, so it is not a consistent total order -- and that is load-bearing. It makes
        # BinarySearch behave as a lower bound over the order, which is exactly what the walk above
        # then turns into an upper bound.
        def compare_component_order(left, right, order)
          return 0 if left.nil? && right.nil?
          return 1 if left.nil?
          return -1 if right.nil?
          return 0 if left == right

          left.public_send(order) < right.public_send(order) ? -1 : 1
        end

        # `List<T>.BinarySearch` -> `ArraySortHelper<T>.BinarySearch`, whose body is the loop below
        # wrapped in a `try`/`catch (Exception)` that rethrows as
        # `InvalidOperationException("InvalidOperation_IComparerFailed", inner)`. The message is a
        # localized framework resource and is not reproduced; the CLR exception maps to RuntimeError
        # and the original is kept as the Ruby cause.
        def component_binary_search(list, item, order)
          low = 0
          high = list.length - 1
          while low <= high
            middle = low + ((high - low) >> 1)
            result = compare_component_order(list[middle], item, order)
            return middle if result.zero?

            if result.negative?
              low = middle + 1
            else
              high = middle - 1
            end
          end
          ~low
        rescue StandardError
          raise RuntimeError, "a component comparer failed"
        end

        def assert_owner_thread! = @generation.assert_owner_thread!

        # A CLR TimeSpan carries whole ticks, so the projected Float seconds are rounded to the
        # nearest tick on the way down rather than truncated.
        def ticks_for(seconds) = (seconds * TICKS_PER_SECOND).round

        # The push half of each setter. Before a host exists there is nothing to push to and the
        # managed field is the whole story -- which is also the state the host is *created* from,
        # so nothing is lost. Once one exists the value is forwarded immediately, as XNA forwards
        # `IsMouseVisible` to a non-null Window.
        #
        # Recorded deviation: the native routes are owner-thread bound and XNA's setters are not, so
        # a setter called off the owner thread raises once a host exists and does not before. The
        # asymmetry is the native contract's, not this projection's, and it is asserted rather than
        # hidden.
        # `GamerServicesDispatcher.IsInitialized` and `Guide.IsVisible` are CLR statics, and their
        # canonical routes are process-global to match: no handle, no owner-thread contract, and
        # measured to answer with no Game in the process at all.
        def gamer_services_initialized?
          read_native_flag("cna_gamer_services_dispatcher_get_is_initialized")
        end

        # One `CNA_Bool*` output, read back as a Ruby boolean. Every failure travels the single
        # translation boundary, so a refused route raises rather than answering a default.
        def read_native_flag(symbol, *arguments)
          library = CNA::Native.library
          output = library.pointer_for("C", 0)
          library.call(symbol, *arguments, output)
          output[0, 1].unpack1("C") != 0
        end

        def push_native_game_setting(symbol, value)
          return if @host.nil? || @host.handle.zero?

          assert_owner_thread!
          CNA::Native.library.call(symbol, @host.handle, value)
          nil
        end
        def require_game_time(value)
          raise TypeError, "game_time must be GameTime" unless value.instance_of?(GameTime)
        end
      end

      # Derived from the pinned Microsoft.Xna.Framework.Game.dll IL (SHA-256 b5dffdd8…).
      #
      # A four-identity managed container over one private `Dictionary<Type, object>`. It reaches no
      # native entry point, holds no unmanaged resource and needs no `Game`: its constructor is
      # public, so unlike most of the Game family a caller can make one and use it directly. What it
      # is *for* is `Game.Services`, which is one of the six deferred partial runtime types, so
      # nothing in this binding populates one.
      #
      # `System.Type` is a service key here, and in every one of the twenty-four places the XNA
      # surface names it, so it projects to a Ruby `Module` — a `Class` is one. The single operation
      # the IL performs on it, `type.IsAssignableFrom(provider.GetType())`, is exactly Ruby's
      # `provider.is_a?(type)`, and the dictionary's default comparer is reference equality, which
      # is what a Ruby Hash gives a Module key.
      #
      # `System.IServiceProvider` declares one member, `GetService(Type)`, which this type already
      # declares publicly. Ruby has no interfaces, so no constant is invented for it and the contract
      # survives as that member — the same collapse `ExternalException` takes, for the same reason:
      # inventing a Ruby identity the CLR surface never names would be unmeasurable.
      #
      # All four exception messages in the IL are localized `Resources` strings, so none is
      # reproduced; the Ruby message is the CLR's parameter name, as everywhere else in this
      # binding. `AddService`'s assignability failure names no parameter at all, and its CLR message
      # carries a Microsoft bug worth recording rather than copying: the second format argument is
      # `type.GetType().FullName`, the type *of the Type object*, where every reading of the message
      # expects `type.FullName`.
      class GameServiceContainer
        def initialize
          @services = {}
        end

        # `type == null` -> ArgumentNullException("type"); `provider == null` ->
        # ArgumentNullException("provider"); an already-registered key -> ArgumentException naming
        # "type"; a provider the key is not assignable from -> ArgumentException naming nothing.
        # Then one `Dictionary.Add`.
        def AddService(type, provider)
          require_service_type!(type)
          raise ArgumentError, "provider" if provider.nil?
          raise ArgumentError, "type" if @services.key?(type)
          raise ArgumentError unless provider.is_a?(type)

          @services[type] = provider
          nil
        end

        # `Dictionary.Remove` and the result is popped, so removing a key that was never added is
        # harmless and answers nothing.
        def RemoveService(type)
          require_service_type!(type)
          @services.delete(type)
          nil
        end

        # `ContainsKey` then the indexer, else `ldnull`: an absent service answers nil rather than
        # raising, which is the one place this type differs from the dictionary it wraps.
        def GetService(type)
          require_service_type!(type)
          @services[type]
        end

        private

        # Every one of the three members opens with the same null check on the same parameter.
        def require_service_type!(type)
          raise ArgumentError, "type" if type.nil?
          raise TypeError, "type must be a Module" unless type.is_a?(::Module)

          type
        end
      end
    end
  end
end
