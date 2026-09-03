# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    Signature = Data.define(
      :symbol, :c_return, :c_arguments, :fiddle_return, :fiddle_arguments,
      :pointer_depths, :const_arguments, :integer_widths, :signedness,
      :ownership, :result_lifetime, :callback_abi, :value_aggregates, :abi_fillers
    )

    module Manifest
      U8 = Fiddle::TYPE_UINT8_T
      U32 = Fiddle::TYPE_UINT32_T
      I16 = Fiddle::TYPE_INT16_T
      U16 = Fiddle::TYPE_UINT16_T
      I32 = Fiddle::TYPE_INT32_T
      I64 = Fiddle::TYPE_INT64_T
      U64 = Fiddle::TYPE_UINT64_T
      F32 = Fiddle::TYPE_FLOAT
      PTR = Fiddle::TYPE_VOIDP
      VOID = Fiddle::TYPE_VOID

      module_function

      def signature(symbol, return_type, arguments, ownership:, result_lifetime: "thread-local until next failing call", callback_abi: nil)
        c_arguments = arguments.map { |value| value.fetch(:c) }
        # An argument declared with `by_value` expands into one entry per eightbyte, and this
        # records where each aggregate starts and how many entries it occupies, so the C spelling
        # can be reconstructed exactly and the decomposition can never become silent.
        value_aggregates = {}
        abi_fillers = []
        arguments.each_with_index do |value, index|
          abi_fillers << index if value[:abi_filler]
          next unless value[:value_aggregate]

          next unless value.fetch(:aggregate_start, false)

          value_aggregates[index] = {
            c: value.fetch(:value_aggregate),
            members: value.fetch(:aggregate_members),
            fillers: value.fetch(:aggregate_fillers, 0)
          }
        end
        Signature.new(
          symbol: symbol,
          c_return: return_type.fetch(:c),
          c_arguments: c_arguments,
          fiddle_return: return_type.fetch(:fiddle),
          fiddle_arguments: arguments.map { |value| value.fetch(:fiddle) },
          pointer_depths: arguments.map { |value| value.fetch(:pointer_depth, 0) },
          const_arguments: arguments.map { |value| value.fetch(:const, false) },
          integer_widths: [return_type.fetch(:width, nil), *arguments.map { |value| value.fetch(:width, nil) }],
          signedness: [return_type.fetch(:signed, nil), *arguments.map { |value| value.fetch(:signed, nil) }],
          ownership: ownership,
          result_lifetime: result_lifetime,
          callback_abi: callback_abi,
          value_aggregates: value_aggregates.freeze,
          abi_fillers: abi_fillers.freeze
        )
      end

      T = {
        result: { c: "CNA_Result", fiddle: U32, width: 32, signed: false },
        u32: { c: "uint32_t", fiddle: U32, width: 32, signed: false },
        i32: { c: "int32_t", fiddle: I32, width: 32, signed: true },
        i16: { c: "int16_t", fiddle: I16, width: 16, signed: true },
        char16: { c: "CNA_Char16", fiddle: U16, width: 16, signed: false },
        i64: { c: "int64_t", fiddle: I64, width: 64, signed: true },
        u64: { c: "uint64_t", fiddle: U64, width: 64, signed: false },
        handle: { c: "CNA_Handle", fiddle: U64, width: 64, signed: false },
        bool: { c: "CNA_Bool", fiddle: U8, width: 8, signed: false },
        float: { c: "float", fiddle: F32, width: 32, signed: true },
        void: { c: "void", fiddle: VOID },
        ptr: { c: "void", fiddle: PTR, pointer_depth: 1 }
      }.freeze

      def pointer(c, const: false, depth: 1)
        { c: c, fiddle: PTR, pointer_depth: depth, const: const }
      end

      def enum(c)
        { c: c, fiddle: U32, width: 32, signed: false }
      end

      def handle(c)
        { c: c, fiddle: U64, width: 64, signed: false }
      end

      # A callback typedef is already a function-pointer type, so the parameter carries no star of
      # its own. It is still a pointer at the Fiddle boundary, which is why the depth stays 0 here
      # and only the C spelling differs from `pointer`.
      # A struct passed **by value**. Fiddle cannot pass an aggregate, so this expands into the
      # eightbytes the platform ABI really puts in registers, and the expansion is recorded rather
      # than performed silently.
      #
      # The one aggregate this binding passes by value is `CNA_StringView`: two eightbytes, a
      # `const char*` at offset 0 and a `uint64_t` at offset 8, which the ABI probe already measures
      # as `size 16, alignment 8`. Under the System V x86-64 classification both eightbytes are
      # INTEGER, so the aggregate travels in the next two integer registers -- byte for byte what
      # two separate scalar arguments occupy. That equivalence is the whole of the decomposition,
      # it is a property of the measured layout rather than an assumption, and it is qualified only
      # for the one platform this binding qualifies at all. `tools/native_abi/verify.rb`
      # reconstructs the aggregate's C spelling from `value_aggregates` and compares it with what
      # the header really declares, so a decomposition that stopped matching would fail the probe.
      def by_value(c, *members)
        members.each_with_index.map do |member, index|
          member.merge(value_aggregate: c, aggregate_start: index.zero?, aggregate_members: members.length)
        end
      end

      # The System V x86-64 integer argument registers, in order: `rdi rsi rdx rcx r8 r9`.
      INTEGER_ARGUMENT_REGISTERS = 6

      # A struct passed by value that the classification puts in **MEMORY** rather than in
      # registers, which on System V x86-64 means any aggregate larger than two eightbytes.
      #
      # `by_value` above covers the register case and cannot cover this one: a MEMORY-class
      # argument is pushed onto the stack, and Fiddle only ever fills the argument registers. The
      # expansion that does work is to declare enough integer arguments that the aggregate's
      # eightbytes are the ones that *overflow* onto the stack, which is byte for byte where the
      # callee reads them. The arguments in between are `fillers`: they occupy the integer
      # registers a real argument would have used, the callee never reads them for this prototype,
      # and they are recorded here so the reconstructed C signature can leave them out.
      #
      # **This is measured, not reasoned.** `cna_graphics_device_set_viewport(CNA_Handle,
      # CNA_Viewport)` is the one route in this manifest that needs it, and its disassembly reads
      # the handle from `rdi` and the viewport from `0x10(%rbp)` — the first stack slot — exactly as
      # the classification says. `tools/native_abi/gate.rb` re-derives both numbers below from the
      # aggregate's *measured* `sizeof` and the preceding arguments rather than trusting them, and
      # `test/test_native_abi_gate.rb` plants a wrong filler count and a wrong eightbyte count and
      # requires the gate to catch each. The round trip is qualified end to end as well: a viewport
      # written through this expansion reads back exactly, and the register-class expansion the
      # naive reading would produce is refused by CNA with `CNA_RESULT_INVALID_ARGUMENT` and
      # changes nothing.
      #
      # Like every other ABI fact in this manifest it is qualified for the one platform this
      # binding qualifies at all.
      def by_value_memory(c, eightbytes:, preceding_integer_arguments:)
        fillers = INTEGER_ARGUMENT_REGISTERS - preceding_integer_arguments
        raise ArgumentError, "#{c}: no integer register is left to fill" if fillers.negative?

        filler_entries = Array.new(fillers) { T[:u64].merge(abi_filler: c) }
        aggregate = Array.new(eightbytes) do |index|
          T[:u64].merge(value_aggregate: c, aggregate_start: index.zero?,
                        aggregate_members: eightbytes, aggregate_fillers: fillers)
        end
        filler_entries + aggregate
      end

      def callback_pointer(c)
        { c: c, fiddle: PTR, pointer_depth: 0 }
      end

      # The set of encoded CNA C ABI versions this binding admits.
      #
      # CNA's own contract (`docs/c-api/ABI_VERSIONING.md`) says two things that together rule out
      # both of the easy policies:
      #
      #   * "A consumer must reject a different major and may require a minimum minor."
      #   * "ABI `0.x` is experimental: an incompatible change requires a minor-version increment,
      #     release notes and a regenerated ABI baseline."
      #
      # So "same major accepts everything" is unsound -- in `0.x` a *later* minor may be
      # incompatible, and `0.20.0` really was: it removed eleven renderer identities and moved a
      # public `MAXIMUM` sentinel. And "require a minimum minor" is unsound for exactly the same
      # reason, because the incompatibility travels forward rather than backward. A single frozen
      # version would be sound but would say nothing about why.
      #
      # Admission is therefore neither a range nor a single number but **the set of encoded
      # versions whose whole bound surface this repository has measured with a compiler**.
      # `tools/native_abi/verify.rb` compiles the probe once per admitted version's headers,
      # requires each to report a version in this list, and requires every measurement except
      # `CNA_ABI_VERSION` itself to agree across them. A version leaves this list the moment that
      # measurement stops holding -- which is a fact about headers, not a preference.
      ADMITTED_ABI_VERSIONS = [0x0000_0700, 0x0000_1500].freeze

      def self.decode_abi_version(encoded)
        format("%d.%d.%d", (encoded >> 16) & 0xFFFF, (encoded >> 8) & 0xFF, encoded & 0xFF)
      end

      FUNCTIONS = [
        signature("cna_get_abi_version", T[:u32], [], ownership: "process-global metadata", result_lifetime: "value"),
        signature("cna_error_get_last_info", T[:result], [pointer("CNA_ErrorInfo")], ownership: "caller output"),
        signature("cna_error_get_last_message_size", T[:result], [pointer("uint64_t")], ownership: "caller output"),
        signature("cna_error_copy_last_message", T[:result], [pointer("char"), T[:u64], pointer("uint64_t")], ownership: "caller output"),
        signature("cna_game_create", T[:result], [pointer("CNA_GameCreateInfo", const: true), pointer("CNA_Handle")], ownership: "returns OWNED Game"),
        signature("cna_game_set_frame_hooks_ext", T[:result], [T[:handle], pointer("CNA_GameFrameHooks", const: true)], ownership: "copies callbacks"),
        signature("cna_game_run", T[:result], [T[:handle]], ownership: "borrows Game"),
        signature("cna_game_run_one_frame", T[:result], [T[:handle]], ownership: "borrows Game"),
        # XNA's Game.RunOneFrame and Game.Tick are two different operations, and the C ABI keeps the
        # same split: `cna_game_run_one_frame` is the host frame, and this is "the canonical frame
        # step `cna_game_run_one_frame` wraps; it does not process host events". That is exactly
        # what the pinned IL says -- WindowsGameHost::RunOneFrame is gameWindow.Tick(), then
        # GameHost::OnIdle() whose only subscriber is Game::HostIdle -> Game::Tick(), then the
        # Guide-visibility relay -- so the two are bound separately and never aliased.
        signature("cna_game_tick", T[:result], [T[:handle]], ownership: "borrows Game; refused from inside a lifecycle callback"),
        signature("cna_game_request_exit", T[:result], [T[:handle]], ownership: "borrows Game"),
        signature("cna_game_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED Game"),
        # The canonical game-event subscription. XNA's Activated, Deactivated and Exiting are raised
        # by Game's private Host* handlers, which are exactly the observers this route registers --
        # the `exiting` slot in CNA_GameCallbacks is a *different* thing, documented as able to stop
        # the game by failing, and measured to fire on every teardown including one that never ran.
        signature("cna_game_subscribe", T[:result], [T[:handle], enum("CNA_GameEvent"), callback_pointer("CNA_GameEventCallback"), T[:ptr], pointer("CNA_GameEventRegistrationHandle")], ownership: "borrows Game; returns OWNED registration; retains callback and context until released"),
        signature("cna_game_unsubscribe", T[:result], [handle("CNA_GameEventRegistrationHandle")], ownership: "consumes OWNED registration"),
        # Game's four timing/presentation properties. In XNA every getter is one `ldfld` -- they are
        # managed fields the host loop reads, not native queries -- so the projection keeps the
        # managed state authoritative and pushes it down; these are the push routes.
        # The three routes `Game.IsActive` is made of. XNA's getter is
        #
        #     bool guideVisible = false;
        #     if (GamerServicesDispatcher.IsInitialized) guideVisible = Guide.IsVisible;
        #     if (!isActive) return false;
        #     return !guideVisible;
        #
        # so it needs the game's own focus flag plus both GamerServices terms, and each has exactly
        # one canonical route. The two GamerServices routes are process-global: no handle, no owner
        # thread, and measured to answer with no Game in the process at all -- which is what the
        # CLR statics they project are.
        signature("cna_game_get_is_active", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_guide_get_is_visible", T[:result], [pointer("CNA_Bool")], ownership: "PROCESS_GLOBAL guide; caller output"),
        signature("cna_gamer_services_dispatcher_get_is_initialized", T[:result], [pointer("CNA_Bool")], ownership: "PROCESS_GLOBAL dispatcher; caller output"),
        # The rest of the canonical dispatcher, for `GamerServices.GamerServicesComponent`. All but
        # the initialize are PROCESS_GLOBAL statics with no handle, which is what XNA's
        # `GamerServicesDispatcher` is too -- the one asymmetry the other native families carry
        # (a game handle where XNA has a CLR static) does not apply here.
        #
        # `cna_gamer_services_component_create` is deliberately **not** bound. It builds a
        # *canonical* component whose initialize and update belong to CNA's runtime and which CNA's
        # own component list drives; this binding's `Game.Components` is the managed engine
        # Foundations 35 and 38 built, so adding one would run a second component pass -- the
        # duplication `docs/graphics-device-service-producer-audit.md` refused. The Ruby type is a
        # `GameComponent` subclass whose overrides call these routes instead.
        signature("cna_gamer_services_dispatcher_set_window_handle", T[:result], [T[:u64]], ownership: "PROCESS_GLOBAL dispatcher; BORROWED_EXTERNAL_SCALAR window token"),
        signature("cna_gamer_services_dispatcher_initialize", T[:result], [T[:handle]], ownership: "borrows Game; PROCESS_GLOBAL dispatcher takes the game's service container"),
        signature("cna_gamer_services_dispatcher_update", T[:result], [], ownership: "PROCESS_GLOBAL dispatcher", result_lifetime: "no result value"),
        signature("cna_gamer_services_dispatcher_subscribe_installing_title_update_ext", T[:result], [callback_pointer("CNA_GamerAsyncCallback"), T[:ptr], pointer("CNA_Handle")], ownership: "PROCESS_GLOBAL dispatcher; returns OWNED registration; retains callback and context until released"),
        signature("cna_gamer_unsubscribe_ext", T[:result], [T[:handle]], ownership: "consumes OWNED registration"),
        signature("cna_game_get_is_mouse_visible", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_is_mouse_visible", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; shows or hides the window cursor"),
        signature("cna_game_get_is_fixed_time_step", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_is_fixed_time_step", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; chooses fixed or variable timing"),
        signature("cna_game_get_target_elapsed_time_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_target_elapsed_time_ticks", T[:result], [T[:handle], T[:i64]], ownership: "borrows Game; rejects a non-positive step"),
        signature("cna_game_get_inactive_sleep_time_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_inactive_sleep_time_ticks", T[:result], [T[:handle], T[:i64]], ownership: "borrows Game; rejects a negative duration"),
        # Game's two loop-state operations. XNA's SuppressDraw is eight bytes -- `suppressDraw = true`
        # -- and ResetElapsedTime is four field writes; every field either one touches belongs to the
        # timing loop, which CNA owns here, so both forward rather than keeping a shadow.
        signature("cna_game_suppress_draw", T[:result], [T[:handle]], ownership: "borrows Game; skips the next frame's draw", result_lifetime: "no result value"),
        signature("cna_game_reset_elapsed_time", T[:result], [T[:handle]], ownership: "borrows Game; forgets accumulated time", result_lifetime: "no result value"),
        # The canonical window surface. Every route is addressed through the **game** handle: CNA's
        # window has no handle of its own, which is what lets `Game.Window` project as a façade over
        # the host rather than a second object with its own lifetime. XNA's abstract `GameWindow`
        # declares exactly these as abstract members for a concrete host to supply, and the C ABI
        # supplies them.
        signature("cna_game_set_window_title", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows Game; copies the bytes"),
        signature("cna_game_window_get_title_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_copy_title", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_get_allow_user_resizing", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_set_allow_user_resizing", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; applies to the window"),
        signature("cna_game_window_get_client_bounds", T[:result], [T[:handle], pointer("CNA_Rectangle")], ownership: "borrows Game; caller MANAGED_VALUE snapshot output"),
        signature("cna_game_window_get_current_orientation", T[:result], [T[:handle], pointer("CNA_DisplayOrientation")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_get_native_handle_ext", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; BORROWED_EXTERNAL_SCALAR platform token"),
        signature("cna_game_window_get_screen_device_name_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_copy_screen_device_name", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_window_begin_screen_device_change", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; records the intent"),
        signature("cna_game_window_end_screen_device_change", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), T[:i32], T[:i32]], ownership: "borrows Game; applies the change"),
        # A window registration and a game registration are the same kind of thing, and
        # `cna_game_unsubscribe` releases both, so no second release route is bound.
        signature("cna_game_window_subscribe", T[:result], [T[:handle], enum("CNA_GameWindowEvent"), callback_pointer("CNA_GameEventCallback"), T[:ptr], pointer("CNA_GameEventRegistrationHandle")], ownership: "borrows Game; returns OWNED registration; retains callback and context until released"),
        signature("cna_framework_dispatcher_update", T[:result], [T[:handle]], ownership: "borrows Game; pumps the canonical CNA framework dispatcher", result_lifetime: "no result value"),
        # The title surface. `TitleContainer.OpenStream` is `File.OpenRead(Path.Combine(
        # TitleLocation.Path, name))` in XNA, and CNA answers the same question with a count/copy
        # pair over the whole file: its own header states that this ABI has no stream handle for
        # title content, so incremental reads over a title stream are not available. The narrowing
        # is the producer's, recorded in docs/stream-projection-design.md, and the projection wraps
        # the bytes rather than pretending to have read them lazily.
        #
        # The location routes are bound as a pair with the reader for two reasons: the projection's
        # missing-file message names the base path CNA really resolved rather than one this side
        # guessed, and `set_path_ext` is the only way a test can point the title at a fixture
        # directory. The canonical accessor resolves the *executable's* directory, which under a
        # Ruby interpreter is the interpreter's, so without the setter no title read could be
        # falsifiable at all. CNA documents the override as process-wide rather than scoped to the
        # game handle it validates.
        signature("cna_title_location_get_path_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_title_location_copy_path", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_title_location_set_path_ext", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows Game; PROCESS_GLOBAL title location; copies the bytes"),
        signature("cna_title_container_read_ext", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("uint8_t"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output; no partial write on BUFFER_TOO_SMALL"),
        # The content surface. Seven routes and no adjacent content API, chosen against the whole
        # 32-route `content.h` because each is what one member of the selected `ContentManager`
        # contract actually needs.
        #
        # `cna_game_get_content_manager_ext` is the producer for `Game.Content`, and its ownership
        # is the reason it is here rather than `cna_content_manager_create`: a CNA game owns exactly
        # one content manager **as a value member**, so the route answers the same handle every
        # time, cannot be destroyed, and dies with the game. That is one XNA ContentManager to one
        # CNA content manager, which is the ownership the GraphicsDeviceManager producer audit
        # established -- creating a second manager for a game that already has one would give every
        # game two native caches and use one of them.
        #
        # `cna_content_manager_create` is the OWNED counterpart, for a standalone
        # `new ContentManager(services)`. It takes a **graphics device**, which XNA's constructor
        # does not, which is why the projection creates the native manager lazily rather than in
        # `initialize`.
        #
        # Deliberately not bound: `create_resource` (its own header records that every load through
        # it fails today, because the canonical embedded-resource stream is a declared placeholder);
        # `load_sound_effect`, `load_texture_cube`, `load_sprite_font` and `load_foreign_ext` (no
        # `SoundEffect`, `TextureCube`, `SpriteFont` or custom reader is projected yet, and a
        # materializer for a type this binding does not have would be unreachable);
        # `set_content_manager_ext` (the canonical setter **copies**, where XNA's `Game.Content`
        # setter replaces a reference -- a different operation, so the projection replaces the
        # managed reference and this route stays unbound); `get_asset_path`/`get_normalized_key`
        # (CNA's key case-folds but does not collapse `./` or `../`, while XNA's cache key is
        # `TitleContainer.GetCleanPath` under `StringComparer.OrdinalIgnoreCase`, so the projection
        # must compute XNA's key and cannot consult CNA's); the manifest and reader-usage families
        # (diagnostics with no XNA identity); and `register_builtin_loaders` (creation already does
        # it and the route exists only to undo an alteration nothing here makes).
        signature("cna_game_get_content_manager_ext", T[:result], [T[:handle], pointer("CNA_Handle")], ownership: "borrows Game; returns BORROWED content manager owned by the Game as a value member"),
        signature("cna_content_manager_create", T[:result], [T[:handle], pointer("CNA_ContentManagerCreateInfo", const: true), pointer("CNA_Handle")], ownership: "returns OWNED content manager; must be destroyed before its Game"),
        signature("cna_content_manager_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED content manager"),
        signature("cna_content_manager_get_root_directory_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "caller output"),
        signature("cna_content_manager_copy_root_directory", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "caller output"),
        signature("cna_content_manager_set_root_directory", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows manager; copies the bytes"),
        signature("cna_content_manager_unload", T[:result], [T[:handle]], ownership: "borrows manager; drops the native cache and leaves earlier owned handles valid"),
        signature("cna_content_manager_load_texture2d", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "returns a NEW independently owned Texture2D per call; survives unload and must be destroyed before the Game"),
        signature("cna_graphics_device_manager_create", T[:result], [T[:handle], pointer("CNA_GraphicsDeviceManagerHandle")], ownership: "returns OWNED manager"),
        signature("cna_graphics_device_manager_get_graphics_device", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_Handle")], ownership: "returns callback BORROWED device"),
        # The graphics-device manager's preferred-settings surface. XNA keeps these in **managed
        # fields** and pushes them at `ChangeDevice`; so does this projection, because a consumer
        # sets them before `Run` and the native manager does not exist yet. These routes are what
        # the flush writes into.
        signature("cna_graphics_device_manager_apply_changes", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_toggle_full_screen", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_graphics_profile", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_GraphicsProfile")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_graphics_profile", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), enum("CNA_GraphicsProfile")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_is_full_screen", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_Bool")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_is_full_screen", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), T[:bool]], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_prefer_multi_sampling", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_Bool")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_prefer_multi_sampling", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), T[:bool]], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_preferred_back_buffer_format", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_SurfaceFormat")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_preferred_back_buffer_format", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), enum("CNA_SurfaceFormat")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_preferred_back_buffer_width", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("int32_t")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_preferred_back_buffer_width", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), T[:i32]], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_preferred_back_buffer_height", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("int32_t")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_preferred_back_buffer_height", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), T[:i32]], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_preferred_depth_stencil_format", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_DepthFormat")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_preferred_depth_stencil_format", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), enum("CNA_DepthFormat")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_synchronize_with_vertical_retrace", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_Bool")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_synchronize_with_vertical_retrace", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), T[:bool]], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_get_supported_orientations", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), pointer("CNA_DisplayOrientation")], ownership: "borrows manager; caller output"),
        signature("cna_graphics_device_manager_set_supported_orientations", T[:result], [handle("CNA_GraphicsDeviceManagerHandle"), enum("CNA_DisplayOrientation")], ownership: "borrows manager"),
        signature("cna_graphics_device_manager_dispose", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "borrows manager; canonical dispose"),
        signature("cna_graphics_device_manager_destroy", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "consumes OWNED manager"),
        signature("cna_graphics_device_get_viewport", T[:result], [T[:handle], pointer("CNA_Viewport")], ownership: "caller output"),
        # `CNA_Viewport` is 24 bytes, which the System V x86-64 classification puts in MEMORY: the
        # aggregate is pushed onto the stack rather than carried in registers, so `by_value` cannot
        # express it and `by_value_memory` does. See that helper for the measurement.
        signature("cna_graphics_device_set_viewport", T[:result],
                  [T[:handle], *by_value_memory("CNA_Viewport", eightbytes: 3, preceding_integer_arguments: 1)],
                  ownership: "borrows device"),
        signature("cna_graphics_device_clear_rgba", T[:result], [T[:handle], T[:float], T[:float], T[:float], T[:float]], ownership: "borrows device"),
        # The device texture collections. Native frontier 4 recorded `Graphics.TextureCollection` as
        # "the one case where NATIVE_RUNTIME was the right word -- no CNA route at all". That was
        # wrong, and not because the ABI moved: `cna_graphics_device_get_texture` and
        # `cna_graphics_device_set_texture` are exported by the retired 0.7.0 artifact too. It is the
        # fourth frontier deferral this session to survive being checked and the first to have been
        # simply mistaken rather than reasoned from the wrong premise.
        #
        # `cna_graphics_device_unbind_texture` is deliberately **not** bound: XNA's collection has no
        # member that unbinds one texture from every slot, and binding a route with no identity to
        # carry it would be surface this projection does not have.
        signature("cna_graphics_device_get_texture", T[:result], [T[:handle], enum("CNA_ShaderStage"), T[:u32], pointer("CNA_TextureSlotInfo")], ownership: "borrows device; caller output"),
        signature("cna_graphics_device_set_texture", T[:result], [T[:handle], enum("CNA_ShaderStage"), T[:u32], T[:handle]], ownership: "borrows device; stores no ownership -- a destroyed texture unbinds itself"),
        signature("cna_texture2d_create_from_encoded_memory", T[:result], [T[:handle], pointer("uint8_t", const: true), T[:u64], pointer("CNA_Texture2DDecodeInfo", const: true), pointer("CNA_Handle")], ownership: "returns OWNED Texture2D"),
        signature("cna_texture2d_create", T[:result], [T[:handle], pointer("CNA_Texture2DCreateInfo", const: true), pointer("CNA_Handle")], ownership: "borrows device; returns OWNED texture"),
        signature("cna_texture2d_set_data", T[:result], [T[:handle], enum("CNA_TextureDataType"), pointer("CNA_Texture2DTransfer", const: true), pointer("void", const: true), T[:u64]], ownership: "borrows texture; copies the elements"),
        signature("cna_texture2d_get_data", T[:result], [T[:handle], enum("CNA_TextureDataType"), pointer("CNA_Texture2DTransfer", const: true), T[:ptr], T[:u64], pointer("uint64_t")], ownership: "borrows texture; caller output"),
        signature("cna_texture2d_get_info", T[:result], [T[:handle], pointer("CNA_Texture2DInfo")], ownership: "caller output"),
        signature("cna_texture2d_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED Texture2D"),
        # `Texture3D` and `TextureCube`. Both transfer routes take `const CNA_Color*` rather than the
        # tagged `CNA_TextureDataType` the 2D one takes, so CNA carries **only** `Color` elements for
        # a volume or a cube face; that is the recorded deviation on both types. `cna_texture3d_set_data_bytes`
        # and `cna_texturecube_create_from_dds_memory` stay unbound: neither has an XNA identity here,
        # the first being a raw pointer upload and the second a DDS decoder XNA reaches through the
        # content pipeline.
        signature("cna_texture3d_create", T[:result], [T[:handle], pointer("CNA_Texture3DCreateInfo", const: true), pointer("CNA_Handle")], ownership: "borrows device; returns OWNED texture"),
        signature("cna_texture3d_set_data", T[:result], [T[:handle], pointer("CNA_Texture3DTransfer", const: true), pointer("CNA_Color", const: true), T[:u64]], ownership: "borrows texture; copies the voxels"),
        signature("cna_texture3d_get_data", T[:result], [T[:handle], pointer("CNA_Texture3DTransfer", const: true), pointer("CNA_Color"), T[:u64], pointer("uint64_t")], ownership: "borrows texture; caller output"),
        signature("cna_texture3d_get_info", T[:result], [T[:handle], pointer("CNA_Texture3DInfo")], ownership: "caller output"),
        signature("cna_texture3d_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED Texture3D"),
        signature("cna_texturecube_create", T[:result], [T[:handle], pointer("CNA_TextureCubeCreateInfo", const: true), pointer("CNA_Handle")], ownership: "borrows device; returns OWNED texture"),
        signature("cna_texturecube_set_data", T[:result], [T[:handle], pointer("CNA_TextureCubeTransfer", const: true), pointer("CNA_Color", const: true), T[:u64]], ownership: "borrows texture; copies the texels"),
        signature("cna_texturecube_get_data", T[:result], [T[:handle], pointer("CNA_TextureCubeTransfer", const: true), pointer("CNA_Color"), T[:u64], pointer("uint64_t")], ownership: "borrows texture; caller output"),
        signature("cna_texturecube_get_info", T[:result], [T[:handle], pointer("CNA_TextureCubeInfo")], ownership: "caller output"),
        signature("cna_texturecube_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED TextureCube"),
        # `RenderTarget2D` and `RenderTargetCube`, whose handles are **textures** as far as the rest
        # of the C ABI is concerned: `cna_texture2d_get_data` reads a 2D target back, which is what
        # the renderer qualification has been measuring since Native frontier 6. Creation negotiates
        # -- the format, depth format and sample count a target ends up with are the adapter's answer
        # rather than the caller's request, exactly as XNA's `GraphicsAdapter.QueryFormat` makes them
        # -- so both types read theirs back from `cna_render_target_get_info` rather than storing what
        # was asked for.
        #
        # `cna_render_target_subscribe_content_lost` and its unsubscribe stay unbound for the reason
        # the dynamic buffers' do: `is_content_lost` is false on every renderer family that cannot
        # lose a device, which is all three qualified artifacts, so a bound callback would be native
        # surface with nothing to deliver -- and both routes exist only in 0.21.0, so binding one
        # would end the retired 0.7.0 headers' admission as well. The pool family is 0.21.0-only and
        # has no XNA identity at all, and `cna_render_target_usage_preserves_contents` answers a
        # question no XNA member asks.
        signature("cna_render_target2d_create", T[:result], [T[:handle], pointer("CNA_RenderTarget2DCreateInfo", const: true), pointer("CNA_Handle")], ownership: "borrows device; returns OWNED render target"),
        signature("cna_render_target_cube_create", T[:result], [T[:handle], pointer("CNA_RenderTargetCubeCreateInfo", const: true), pointer("CNA_Handle")], ownership: "borrows device; returns OWNED render target"),
        signature("cna_render_target_get_info", T[:result], [T[:handle], pointer("CNA_RenderTargetInfo")], ownership: "caller output"),
        signature("cna_render_target_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED render target"),
        # `OcclusionQuery`. `has_renderer` is a production route rather than a diagnostic: XNA's
        # `get_IsComplete` begins by checking whether the query still holds a native object, and
        # answers `_isAvailable` without asking the device when it does not.
        # `cna_occlusion_query_get_is_pixel_count_precise_ext` stays unbound -- XNA has no identity
        # for it, and its own header says so by being an `_ext`.
        signature("cna_occlusion_query_create", T[:result], [T[:handle], pointer("CNA_OcclusionQueryHandle")], ownership: "borrows device; returns OWNED query"),
        signature("cna_occlusion_query_begin", T[:result], [handle("CNA_OcclusionQueryHandle")], ownership: "borrows query"),
        signature("cna_occlusion_query_end", T[:result], [handle("CNA_OcclusionQueryHandle")], ownership: "borrows query"),
        signature("cna_occlusion_query_get_is_complete", T[:result], [handle("CNA_OcclusionQueryHandle"), pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_occlusion_query_get_pixel_count", T[:result], [handle("CNA_OcclusionQueryHandle"), pointer("int32_t")], ownership: "caller output"),
        signature("cna_occlusion_query_has_renderer", T[:result], [handle("CNA_OcclusionQueryHandle"), pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_occlusion_query_destroy", T[:result], [handle("CNA_OcclusionQueryHandle")], ownership: "consumes OWNED query"),
        # `GraphicsDevice`'s state slice. The three descriptor routes take the same structures the
        # state objects already write, so one mapping now has three callers: the state object, the
        # sampler collection, and the device property.
        #
        # Two arguments are aggregates passed **by value**, and both classifications were measured
        # rather than assumed, on two artifacts. `CNA_Color` is four `uint8_t`s -- four bytes, one
        # INTEGER eightbyte -- so it travels in the low half of one integer register, which is byte
        # for byte what a `uint32_t` argument occupies; a packed RGBA written through the expansion
        # reads back identical. `CNA_Rectangle` is four `int32_t`s -- sixteen bytes, two INTEGER
        # eightbytes -- so it travels in two integer registers holding `x | y << 32` and
        # `width | height << 32`; a rectangle written through the expansion reads back field for
        # field. `cna_graphics_device_get_backbuffer_info` is what XNA's scissor validation needs:
        # its rule is the current render target's bounds or the back buffer's, and nothing here can
        # bind a render target.
        signature("cna_graphics_device_get_blend_state", T[:result], [T[:handle], pointer("CNA_BlendState")], ownership: "caller output"),
        signature("cna_graphics_device_set_blend_state", T[:result], [T[:handle], pointer("CNA_BlendState", const: true)], ownership: "borrows device; copies the descriptor"),
        signature("cna_graphics_device_get_depth_stencil_state", T[:result], [T[:handle], pointer("CNA_DepthStencilState")], ownership: "caller output"),
        signature("cna_graphics_device_set_depth_stencil_state", T[:result], [T[:handle], pointer("CNA_DepthStencilState", const: true)], ownership: "borrows device; copies the descriptor"),
        signature("cna_graphics_device_get_rasterizer_state", T[:result], [T[:handle], pointer("CNA_RasterizerState")], ownership: "caller output"),
        signature("cna_graphics_device_set_rasterizer_state", T[:result], [T[:handle], pointer("CNA_RasterizerState", const: true)], ownership: "borrows device; copies the descriptor"),
        signature("cna_graphics_device_get_blend_factor", T[:result], [T[:handle], pointer("CNA_Color")], ownership: "caller output"),
        signature("cna_graphics_device_set_blend_factor", T[:result], [T[:handle], *by_value("CNA_Color", T[:u32])], ownership: "borrows device"),
        signature("cna_graphics_device_get_multi_sample_mask", T[:result], [T[:handle], pointer("int32_t")], ownership: "caller output"),
        signature("cna_graphics_device_set_multi_sample_mask", T[:result], [T[:handle], T[:i32]], ownership: "borrows device"),
        signature("cna_graphics_device_get_reference_stencil", T[:result], [T[:handle], pointer("int32_t")], ownership: "caller output"),
        signature("cna_graphics_device_set_reference_stencil", T[:result], [T[:handle], T[:i32]], ownership: "borrows device"),
        signature("cna_graphics_device_get_scissor_rectangle", T[:result], [T[:handle], pointer("CNA_Rectangle")], ownership: "caller output"),
        signature("cna_graphics_device_set_scissor_rectangle", T[:result], [T[:handle], *by_value("CNA_Rectangle", T[:u64], T[:u64])], ownership: "borrows device"),
        signature("cna_graphics_device_get_backbuffer_info", T[:result], [T[:handle], pointer("CNA_BackBufferInfo")], ownership: "caller output"),
        # `GraphicsDevice`'s binding slice. CNA hands back **handles** for what is bound, and this
        # ABI has no route from a native object back to a handle, so the projection answers the Ruby
        # objects it bound -- the rule `TextureCollection` already follows -- and the native count is
        # what tells "something else owns this now" from "nothing is bound".
        #
        # `cna_graphics_device_set_vertex_buffer_offset` is the two-argument `SetVertexBuffer`, and
        # `cna_graphics_device_set_vertex_buffer` the one-argument one; both are XNA identities
        # rather than conveniences, so both are bound.
        #
        # The three **read-back** routes -- `get_vertex_buffer_count`, `copy_vertex_buffers` and
        # `get_index_buffer` -- are deliberately **not** bound. XNA's own getters are field reads, so
        # nothing in `lib/` would call them, and a route bound for a test is dead native surface.
        # `test/test_graphics_device_binding.rb` reaches them through raw Fiddle for the same reason
        # `test/renderer_environment.rb` does: measuring what the device really holds must not put a
        # test-only route in the manifest.
        signature("cna_graphics_device_set_vertex_buffer", T[:result], [T[:handle], handle("CNA_VertexBufferHandle")], ownership: "borrows device and buffer"),
        signature("cna_graphics_device_set_vertex_buffer_offset", T[:result], [T[:handle], handle("CNA_VertexBufferHandle"), T[:i32]], ownership: "borrows device and buffer"),
        signature("cna_graphics_device_set_vertex_buffers", T[:result], [T[:handle], pointer("CNA_VertexBufferBinding", const: true), T[:u64]], ownership: "borrows device; copies the bindings"),
        signature("cna_graphics_device_set_index_buffer", T[:result], [T[:handle], handle("CNA_IndexBufferHandle")], ownership: "borrows device and buffer"),
        # `SetRenderTarget`'s two overloads forward to the array form in the IL, so this projection
        # forwards to `cna_graphics_device_set_render_targets` too and the two single-target routes
        # -- `set_render_target2d` and `set_render_target_cube` -- have no production caller and stay
        # unbound. `get_render_target_count` and `copy_render_targets` stay unbound for the reason
        # the vertex read-backs do: `GetRenderTargets` is an `Array.Copy` over a cached array.
        signature("cna_graphics_device_set_render_targets", T[:result], [T[:handle], pointer("CNA_RenderTargetBinding", const: true), T[:u64]], ownership: "borrows device; copies the bindings"),
        # The three draw calls that read the device's own bound buffers. Every parameter is a
        # scalar, so nothing here is passed by value and nothing is allocated.
        signature("cna_graphics_device_draw_primitives", T[:result], [T[:handle], enum("CNA_PrimitiveType"), T[:i32], T[:i32]], ownership: "borrows device; draws from the bound buffers"),
        signature("cna_graphics_device_draw_indexed_primitives", T[:result], [T[:handle], enum("CNA_PrimitiveType"), T[:i32], T[:i32], T[:i32], T[:i32], T[:i32]], ownership: "borrows device; draws from the bound buffers"),
        signature("cna_graphics_device_draw_instanced_primitives", T[:result], [T[:handle], enum("CNA_PrimitiveType"), T[:i32], T[:i32], T[:i32], T[:i32], T[:i32], T[:i32]], ownership: "borrows device; draws from the bound buffers"),
        # The Effect cluster. Every getter in it returns an **owned view**: `cna_effect_get_parameters`
        # hands back a fresh collection handle on every call, and so does
        # `cna_effect_parameter_collection_get_at` for every element -- measured, two calls answer two
        # different handles naming the same parameter. That is why the projection builds the whole
        # object graph once, holds one Ruby object per logical child, and destroys every view when the
        # Effect is disposed: XNA's collections are built once in the constructor and hand back the
        # same object every time, and a fresh native handle is not a new XNA object.
        #
        # `cna_effect_parameter_collection_find_name` and `find_semantic` are deliberately **not**
        # bound. XNA's `Item[String]` scans its own managed list with `String::op_Equality` and
        # `GetParameterBySemantic` scans with `String::Compare(..., OrdinalIgnoreCase)`; CNA's two
        # routes both match exactly, so binding them would change `GetParameterBySemantic`'s answer.
        # The scan is managed here for the same reason it is managed in XNA.
        signature("cna_effect_create_compiled", T[:result], [T[:handle], pointer("uint8_t", const: true), T[:u64], pointer("CNA_EffectHandle")], ownership: "borrows device; returns OWNED effect"),
        signature("cna_effect_clone", T[:result], [handle("CNA_EffectHandle"), pointer("CNA_EffectHandle")], ownership: "borrows source; returns OWNED clone"),
        signature("cna_effect_dispose", T[:result], [handle("CNA_EffectHandle")], ownership: "borrows effect; releases its graphics resources without releasing the handle"),
        signature("cna_effect_destroy", T[:result], [handle("CNA_EffectHandle")], ownership: "consumes OWNED effect"),
        signature("cna_effect_get_parameters", T[:result], [handle("CNA_EffectHandle"), pointer("CNA_EffectParameterCollectionHandle")], ownership: "borrows effect; returns an OWNED collection view"),
        signature("cna_effect_get_techniques", T[:result], [handle("CNA_EffectHandle"), pointer("CNA_EffectTechniqueCollectionHandle")], ownership: "borrows effect; returns an OWNED collection view"),
        signature("cna_effect_get_current_technique", T[:result], [handle("CNA_EffectHandle"), pointer("CNA_EffectTechniqueHandle")], ownership: "borrows effect; returns an OWNED technique view"),
        signature("cna_effect_set_current_technique", T[:result], [handle("CNA_EffectHandle"), handle("CNA_EffectTechniqueHandle")], ownership: "borrows both"),
        signature("cna_effect_parameter_collection_get_count", T[:result], [handle("CNA_EffectParameterCollectionHandle"), pointer("uint64_t")], ownership: "borrows collection; caller output"),
        signature("cna_effect_parameter_collection_get_at", T[:result], [handle("CNA_EffectParameterCollectionHandle"), T[:u64], pointer("CNA_EffectParameterHandle")], ownership: "borrows collection; returns an OWNED element view"),
        signature("cna_effect_parameter_collection_destroy", T[:result], [handle("CNA_EffectParameterCollectionHandle")], ownership: "consumes OWNED collection view"),
        signature("cna_effect_parameter_destroy", T[:result], [handle("CNA_EffectParameterHandle")], ownership: "consumes OWNED parameter view"),
        signature("cna_effect_parameter_get_info", T[:result], [handle("CNA_EffectParameterHandle"), pointer("CNA_EffectParameterInfo")], ownership: "caller output"),
        signature("cna_effect_parameter_get_name_byte_count", T[:result], [handle("CNA_EffectParameterHandle"), pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_copy_name", T[:result], [handle("CNA_EffectParameterHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_get_semantic_byte_count", T[:result], [handle("CNA_EffectParameterHandle"), pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_copy_semantic", T[:result], [handle("CNA_EffectParameterHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_get_elements", T[:result], [handle("CNA_EffectParameterHandle"), pointer("CNA_EffectParameterCollectionHandle")], ownership: "borrows parameter; returns an OWNED collection view"),
        signature("cna_effect_parameter_get_structure_members", T[:result], [handle("CNA_EffectParameterHandle"), pointer("CNA_EffectParameterCollectionHandle")], ownership: "borrows parameter; returns an OWNED collection view"),
        signature("cna_effect_parameter_get_annotations", T[:result], [handle("CNA_EffectParameterHandle"), pointer("CNA_EffectAnnotationCollectionHandle")], ownership: "borrows parameter; returns an OWNED collection view"),
        signature("cna_effect_parameter_get_value", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectValueType"), T[:ptr]], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_get_values", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectValueType"), T[:u64], T[:ptr], T[:u64], pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_set_value", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectValueType"), pointer("void", const: true)], ownership: "borrows parameter; copies the value"),
        signature("cna_effect_parameter_set_values", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectValueType"), pointer("void", const: true), T[:u64]], ownership: "borrows parameter; copies the values"),
        signature("cna_effect_parameter_get_value_string_byte_count", T[:result], [handle("CNA_EffectParameterHandle"), pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_copy_value_string", T[:result], [handle("CNA_EffectParameterHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows parameter; caller output"),
        signature("cna_effect_parameter_set_value_string", T[:result], [handle("CNA_EffectParameterHandle"), *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows parameter; copies the string"),
        signature("cna_effect_parameter_get_value_texture", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectTextureType"), pointer("CNA_Handle")], ownership: "borrows parameter; returns a RETAINED texture handle"),
        signature("cna_effect_parameter_set_value_texture", T[:result], [handle("CNA_EffectParameterHandle"), enum("CNA_EffectTextureType"), T[:handle]], ownership: "borrows parameter; retains the texture until the slot is replaced"),
        signature("cna_effect_annotation_collection_get_count", T[:result], [handle("CNA_EffectAnnotationCollectionHandle"), pointer("uint64_t")], ownership: "borrows collection; caller output"),
        signature("cna_effect_annotation_collection_get_at", T[:result], [handle("CNA_EffectAnnotationCollectionHandle"), T[:u64], pointer("CNA_EffectAnnotationHandle")], ownership: "borrows collection; returns an OWNED element view"),
        signature("cna_effect_annotation_collection_destroy", T[:result], [handle("CNA_EffectAnnotationCollectionHandle")], ownership: "consumes OWNED collection view"),
        signature("cna_effect_annotation_destroy", T[:result], [handle("CNA_EffectAnnotationHandle")], ownership: "consumes OWNED annotation view"),
        signature("cna_effect_annotation_get_info", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_EffectAnnotationInfo")], ownership: "caller output"),
        signature("cna_effect_annotation_get_name_byte_count", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_copy_name", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_semantic_byte_count", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_copy_semantic", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_boolean", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_Bool")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_int32", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("int32_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_single", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("float")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_vector2", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_Vector2")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_vector3", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_Vector3")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_vector4", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_Vector4")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_matrix", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("CNA_Matrix")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_get_value_string_byte_count", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_annotation_copy_value_string", T[:result], [handle("CNA_EffectAnnotationHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows annotation; caller output"),
        signature("cna_effect_pass_collection_get_count", T[:result], [handle("CNA_EffectPassCollectionHandle"), pointer("uint64_t")], ownership: "borrows collection; caller output"),
        signature("cna_effect_pass_collection_get_at", T[:result], [handle("CNA_EffectPassCollectionHandle"), T[:u64], pointer("CNA_EffectPassHandle")], ownership: "borrows collection; returns an OWNED element view"),
        signature("cna_effect_pass_collection_destroy", T[:result], [handle("CNA_EffectPassCollectionHandle")], ownership: "consumes OWNED collection view"),
        signature("cna_effect_pass_destroy", T[:result], [handle("CNA_EffectPassHandle")], ownership: "consumes OWNED pass view"),
        signature("cna_effect_pass_get_name_byte_count", T[:result], [handle("CNA_EffectPassHandle"), pointer("uint64_t")], ownership: "borrows pass; caller output"),
        signature("cna_effect_pass_copy_name", T[:result], [handle("CNA_EffectPassHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows pass; caller output"),
        signature("cna_effect_pass_get_annotations", T[:result], [handle("CNA_EffectPassHandle"), pointer("CNA_EffectAnnotationCollectionHandle")], ownership: "borrows pass; returns an OWNED collection view"),
        signature("cna_effect_pass_apply", T[:result], [handle("CNA_EffectPassHandle")], ownership: "borrows pass; selects it on the owning device"),
        signature("cna_effect_technique_collection_get_count", T[:result], [handle("CNA_EffectTechniqueCollectionHandle"), pointer("uint64_t")], ownership: "borrows collection; caller output"),
        signature("cna_effect_technique_collection_get_at", T[:result], [handle("CNA_EffectTechniqueCollectionHandle"), T[:u64], pointer("CNA_EffectTechniqueHandle")], ownership: "borrows collection; returns an OWNED element view"),
        signature("cna_effect_technique_collection_destroy", T[:result], [handle("CNA_EffectTechniqueCollectionHandle")], ownership: "consumes OWNED collection view"),
        signature("cna_effect_technique_destroy", T[:result], [handle("CNA_EffectTechniqueHandle")], ownership: "consumes OWNED technique view"),
        signature("cna_effect_technique_get_name_byte_count", T[:result], [handle("CNA_EffectTechniqueHandle"), pointer("uint64_t")], ownership: "borrows technique; caller output"),
        signature("cna_effect_technique_copy_name", T[:result], [handle("CNA_EffectTechniqueHandle"), pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows technique; caller output"),
        signature("cna_effect_technique_get_index_ext", T[:result], [handle("CNA_EffectTechniqueHandle"), pointer("uint32_t")], ownership: "borrows technique; caller output"),
        signature("cna_effect_technique_get_passes", T[:result], [handle("CNA_EffectTechniqueHandle"), pointer("CNA_EffectPassCollectionHandle")], ownership: "borrows technique; returns an OWNED collection view"),
        signature("cna_effect_technique_get_annotations", T[:result], [handle("CNA_EffectTechniqueHandle"), pointer("CNA_EffectAnnotationCollectionHandle")], ownership: "borrows technique; returns an OWNED collection view"),
        # The vertex and index buffers.
        #
        # XNA's `SetData<T>` is generic over any struct and CNA's **typed** vertex transfer carries
        # only its seven built-in `CNA_VertexType` layouts, so the static path uses the `_raw`
        # family -- bytes, a vertex count and a stride -- which the header documents as existing for
        # exactly that asymmetry.
        #
        # The dynamic path needs `SetDataOptions`, and here the **two-version admission policy chose
        # the route**: `cna_vertex_buffer_set_data_raw_at_with_options` carries both the offset and
        # the options, and it exists only in 0.21.0. Binding it would make the retired 0.7.0 headers
        # report a missing symbol and end their admission, which is not a decision a buffer milestone
        # gets to take on its own. The typed `cna_vertex_buffer_set_data` is declared by both, and
        # its transfer carries the options -- at the cost of the seven built-in layouts, which are a
        # superset of the four vertex structs this binding projects. See
        # `docs/vertex-index-buffer-evidence.md`.
        #
        # `cna_index_buffer_set_data_at` needs no such choice: both versions declare it and its
        # transfer carries the element width and the options, so one route covers all five XNA
        # `SetData` overloads across the static and dynamic classes.
        signature("cna_vertex_declaration_create_with_stride", T[:result], [T[:i32], pointer("CNA_VertexElement", const: true), T[:u64], pointer("CNA_VertexDeclarationHandle")], ownership: "copies the elements; returns OWNED VertexDeclaration"),
        signature("cna_vertex_buffer_create", T[:result], [T[:handle], pointer("CNA_VertexBufferCreateInfo", const: true), pointer("CNA_VertexBufferHandle")], ownership: "borrows device; returns OWNED vertex buffer"),
        signature("cna_vertex_buffer_destroy", T[:result], [handle("CNA_VertexBufferHandle")], ownership: "consumes OWNED vertex buffer"),
        signature("cna_vertex_buffer_get_info", T[:result], [handle("CNA_VertexBufferHandle"), pointer("CNA_VertexBufferInfo")], ownership: "caller output"),
        signature("cna_vertex_buffer_copy_declaration_elements", T[:result], [handle("CNA_VertexBufferHandle"), pointer("CNA_VertexElement"), T[:u64], pointer("uint64_t")], ownership: "borrows buffer; caller output"),
        signature("cna_vertex_buffer_set_data_raw_at", T[:result], [handle("CNA_VertexBufferHandle"), T[:u64], pointer("void", const: true), T[:u64], T[:u64], T[:u32]], ownership: "borrows buffer; copies the bytes"),
        signature("cna_vertex_buffer_set_data", T[:result], [handle("CNA_VertexBufferHandle"), pointer("CNA_VertexBufferTransfer", const: true), pointer("void", const: true), T[:u64]], ownership: "borrows buffer; copies the vertices"),
        signature("cna_vertex_buffer_get_data_raw", T[:result], [handle("CNA_VertexBufferHandle"), T[:u64], T[:ptr], T[:u64], T[:u64], T[:u32]], ownership: "borrows buffer; caller output"),
        signature("cna_vertex_buffer_binding_init", T[:result], [handle("CNA_VertexBufferHandle"), T[:i32], T[:i32], pointer("CNA_VertexBufferBinding")], ownership: "borrows buffer; caller output"),
        signature("cna_index_buffer_create", T[:result], [T[:handle], pointer("CNA_IndexBufferCreateInfo", const: true), pointer("CNA_IndexBufferHandle")], ownership: "borrows device; returns OWNED index buffer"),
        signature("cna_index_buffer_destroy", T[:result], [handle("CNA_IndexBufferHandle")], ownership: "consumes OWNED index buffer"),
        signature("cna_index_buffer_get_info", T[:result], [handle("CNA_IndexBufferHandle"), pointer("CNA_IndexBufferInfo")], ownership: "caller output"),
        signature("cna_index_buffer_set_data", T[:result], [handle("CNA_IndexBufferHandle"), pointer("CNA_IndexBufferTransfer", const: true), pointer("void", const: true), T[:u64]], ownership: "borrows buffer; replaces the whole contents"),
        signature("cna_index_buffer_set_data_at", T[:result], [handle("CNA_IndexBufferHandle"), T[:u64], pointer("CNA_IndexBufferTransfer", const: true), pointer("void", const: true), T[:u64]], ownership: "borrows buffer; copies the indices"),
        signature("cna_index_buffer_get_data", T[:result], [handle("CNA_IndexBufferHandle"), pointer("CNA_IndexBufferTransfer", const: true), T[:ptr], T[:u64], pointer("uint64_t")], ownership: "borrows buffer; caller output"),
        # The two encode routes `SaveAsPng` and `SaveAsJpeg` need: ask for the size, then copy. CNA
        # also exports `cna_texture2d_save_file`, which writes a path rather than a stream and has
        # no XNA identity, so it stays unbound.
        signature("cna_texture2d_get_encoded_byte_count", T[:result], [T[:handle], enum("CNA_TextureImageFormat"), T[:u32], T[:u32], pointer("uint64_t")], ownership: "borrows texture; caller output"),
        signature("cna_texture2d_copy_encoded", T[:result], [T[:handle], enum("CNA_TextureImageFormat"), T[:u32], T[:u32], pointer("uint8_t"), T[:u64], pointer("uint64_t")], ownership: "borrows texture; caller output"),
        # The four graphics state objects. These four routes take **no handle** -- they fill a
        # caller-owned POD from a native preset identity -- so they need no game, no device and no
        # renderer. They are the cross-check for the four state types, whose values are derived from
        # the pinned XNA IL: each projected preset is asserted equal to CNA's own, field by field,
        # rather than only to itself. `cna_graphics_device_get/set_*_state` stay unbound because
        # applying a state to a device is `GraphicsDevice`'s surface and XNA's own `Apply` is
        # `assembly`-visible, so neither is a projected identity yet.
        # `Media.VideoPlayer`. Every one of the fifteen contract members has a canonical route here,
        # all of them work headless, and the optional video decoder really is compiled into the
        # qualified artifact -- `docs/video-player-audit-evidence.md` measures a real file being
        # probed, played and yielding a frame texture. DEVIATION: `cna_video_player_create` takes a
        # **game** where XNA's constructor takes nothing, the game-scoped asymmetry every audio and
        # window route in this manifest already records. `set_audio_track_ext`,
        # `set_video_track_ext`, `get_frame_ext`, `get_type_name_size` and `copy_type_name` stay
        # unbound: none has an XNA identity.
        signature("cna_video_player_create", T[:result], [T[:handle], pointer("CNA_Handle")], ownership: "returns OWNED VideoPlayer parented to the game"),
        signature("cna_video_player_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows player; caller output"),
        signature("cna_video_player_get_is_looped", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows player; caller output"),
        signature("cna_video_player_set_is_looped", T[:result], [T[:handle], T[:bool]], ownership: "borrows player"),
        signature("cna_video_player_get_is_muted", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows player; caller output"),
        signature("cna_video_player_set_is_muted", T[:result], [T[:handle], T[:bool]], ownership: "borrows player"),
        signature("cna_video_player_get_play_position_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "borrows player; caller output"),
        signature("cna_video_player_get_state", T[:result], [T[:handle], pointer("CNA_MediaState")], ownership: "borrows player; caller output"),
        signature("cna_video_player_get_video", T[:result], [T[:handle], pointer("CNA_Handle"), pointer("CNA_Bool")], ownership: "borrows player; returns BORROWED video"),
        signature("cna_video_player_get_volume", T[:result], [T[:handle], pointer("float")], ownership: "borrows player; caller output"),
        signature("cna_video_player_set_volume", T[:result], [T[:handle], T[:float]], ownership: "borrows player"),
        signature("cna_video_player_get_texture", T[:result], [T[:handle], pointer("CNA_Handle"), pointer("CNA_Bool")], ownership: "borrows player; returns BORROWED frame texture"),
        signature("cna_video_player_play", T[:result], [T[:handle], T[:handle]], ownership: "borrows player; borrows the video"),
        signature("cna_video_player_stop", T[:result], [T[:handle]], ownership: "borrows player"),
        signature("cna_video_player_pause", T[:result], [T[:handle]], ownership: "borrows player"),
        signature("cna_video_player_resume", T[:result], [T[:handle]], ownership: "borrows player"),
        signature("cna_video_player_dispose", T[:result], [T[:handle]], ownership: "borrows player; releases its decoder"),
        signature("cna_video_player_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED VideoPlayer"),
        # The vertex-declaration routes. They take **no device and no handle in** -- a declaration
        # is a value CNA computes a stride for -- which is what makes them usable as the headless
        # cross-check for `VertexDeclaration`'s own stride arithmetic, derived from the pinned IL.
        # `create_with_stride`, `create_empty`, `copy_type_name` and `get_type_name_byte_count`
        # stay unbound: XNA computes nothing in the explicit-stride case, declares no empty
        # declaration, and has no type-name identity on this type at all.
        signature("cna_vertex_declaration_create", T[:result], [pointer("CNA_VertexElement", const: true), T[:u64], pointer("CNA_Handle")], ownership: "copies the elements; returns OWNED VertexDeclaration"),
        signature("cna_vertex_declaration_get_stride", T[:result], [T[:handle], pointer("int32_t")], ownership: "borrows declaration; caller output"),
        signature("cna_vertex_declaration_copy_elements", T[:result], [T[:handle], pointer("CNA_VertexElement"), T[:u64], pointer("uint64_t")], ownership: "borrows declaration; caller output"),
        signature("cna_vertex_declaration_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED VertexDeclaration"),
        signature("cna_graphics_device_get_sampler_state", T[:result], [T[:handle], enum("CNA_ShaderStage"), T[:u32], pointer("CNA_SamplerState")], ownership: "borrows device; caller output"),
        signature("cna_graphics_device_set_sampler_state", T[:result], [T[:handle], enum("CNA_ShaderStage"), T[:u32], pointer("CNA_SamplerState", const: true)], ownership: "borrows device; copies the descriptor"),
        signature("cna_blend_state_init", T[:result], [enum("CNA_BlendStatePreset"), pointer("CNA_BlendState")], ownership: "caller output"),
        signature("cna_depth_stencil_state_init", T[:result], [enum("CNA_DepthStencilStatePreset"), pointer("CNA_DepthStencilState")], ownership: "caller output"),
        signature("cna_rasterizer_state_init", T[:result], [enum("CNA_RasterizerStatePreset"), pointer("CNA_RasterizerState")], ownership: "caller output"),
        signature("cna_sampler_state_init", T[:result], [enum("CNA_SamplerStatePreset"), pointer("CNA_SamplerState")], ownership: "caller output"),
        signature("cna_sprite_batch_create", T[:result], [T[:handle], pointer("CNA_Handle")], ownership: "returns OWNED SpriteBatch"),
        signature("cna_sprite_batch_begin", T[:result], [T[:handle], pointer("CNA_SpriteBatchBeginInfo", const: true)], ownership: "borrows SpriteBatch"),
        signature("cna_sprite_batch_submit_many", T[:result], [T[:handle], pointer("CNA_SpriteCommand", const: true), T[:u64]], ownership: "copies commands; retains Texture until End"),
        signature("cna_sprite_batch_submit_scaled_many", T[:result], [T[:handle], pointer("CNA_SpriteScaledCommand", const: true), T[:u64]], ownership: "copies commands; retains Texture until End"),
        # The state-bearing `Begin` overloads. This is the route XNA's own seven-argument `Begin`
        # maps to exactly: a **null** state means "use the default", which CNA documents as
        # AlphaBlend, LinearClamp, None and CullCounterClockwise -- the same four `SetRenderState`
        # substitutes in the IL. `CNA_INVALID_HANDLE` is the default sprite effect and a null matrix
        # is the identity, which is what the overloads without an `Effect` pass.
        signature("cna_sprite_batch_begin_with_effect", T[:result], [T[:handle], enum("CNA_SpriteSortMode"), pointer("CNA_BlendState", const: true), pointer("CNA_SamplerState", const: true), pointer("CNA_DepthStencilState", const: true), pointer("CNA_RasterizerState", const: true), T[:handle], pointer("CNA_Matrix", const: true)], ownership: "borrows SpriteBatch; copies every descriptor"),
        signature("cna_sprite_batch_draw_string", T[:result], [T[:handle], pointer("CNA_SpriteTextCommand", const: true)], ownership: "borrows SpriteBatch; copies the command and its text"),
        signature("cna_sprite_batch_end", T[:result], [T[:handle]], ownership: "borrows SpriteBatch"),
        signature("cna_sprite_batch_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED SpriteBatch"),
        # The audio surface. Native frontier 4 recorded this cluster UPSTREAM_CNA_BLOCKED against the
        # retired 0.7.0 artifact; the ABI migration re-measured it and found the artifact had been
        # built `CNA_AUDIO_PLATFORM=NULL`, which is a build-time CMake choice and not the runtime
        # variable that audit thought it was controlling. On the current artifact the whole path is
        # behaviourally real, so the cluster is reopened and these are the routes its two types need.
        #
        # A SoundEffect is OWNED and parented to the Game; an instance is OWNED and parented to its
        # effect, and CNA enforces the order -- destroying an effect that still has a live instance
        # answers `CNA_RESULT_INVALID_STATE`, measured.
        #
        # The four global settings are addressed through the **game** handle where XNA's are CLR
        # statics. That is the same asymmetry `FrameworkDispatcher` already records, and it is why
        # those four Ruby properties need a live Game where XNA's do not.
        signature("cna_sound_effect_create_pcm16", T[:result], [T[:handle], pointer("CNA_SoundEffectCreateInfo", const: true), pointer("uint8_t", const: true), T[:u64], pointer("CNA_Handle")], ownership: "returns OWNED SoundEffect; copies the PCM bytes"),
        signature("cna_sound_effect_create_pcm16_range_ext", T[:result], [T[:handle], pointer("CNA_SoundEffectCreateInfo", const: true), pointer("uint8_t", const: true), T[:u64], T[:i32], T[:i32], T[:i32], T[:i32], pointer("CNA_Handle")], ownership: "returns OWNED SoundEffect; copies the PCM bytes"),
        signature("cna_sound_effect_create_from_encoded_ext", T[:result], [T[:handle], pointer("uint8_t", const: true), T[:u64], pointer("CNA_Handle")], ownership: "returns OWNED SoundEffect; decodes a container"),
        signature("cna_sound_effect_get_duration_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "caller output"),
        signature("cna_sound_effect_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_sound_effect_get_name_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "caller output"),
        signature("cna_sound_effect_copy_name", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "caller output"),
        signature("cna_sound_effect_set_name", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows effect; copies the bytes"),
        signature("cna_sound_effect_create_instance", T[:result], [T[:handle], pointer("CNA_Handle")], ownership: "returns OWNED instance; PARENT_OWNED by its SoundEffect and destroyed before it"),
        signature("cna_sound_effect_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED SoundEffect; refuses while an instance is live"),
        signature("cna_sound_effect_play", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows effect; fire-and-forget; caller Boolean output"),
        signature("cna_sound_effect_play_with_settings", T[:result], [T[:handle], T[:float], T[:float], T[:float], pointer("CNA_Bool")], ownership: "borrows effect; fire-and-forget; caller Boolean output"),
        signature("cna_sound_effect_get_sample_duration_ticks", T[:result], [T[:i32], T[:i32], enum("CNA_AudioChannels"), pointer("int64_t")], ownership: "pure computation; no handle"),
        signature("cna_sound_effect_get_sample_size_in_bytes", T[:result], [T[:i64], T[:i32], enum("CNA_AudioChannels"), pointer("int32_t")], ownership: "pure computation; no handle"),
        signature("cna_sound_effect_get_master_volume", T[:result], [T[:handle], pointer("float")], ownership: "borrows Game; caller output"),
        signature("cna_sound_effect_set_master_volume", T[:result], [T[:handle], T[:float]], ownership: "borrows Game; game-scoped where XNA is a CLR static"),
        signature("cna_sound_effect_get_distance_scale", T[:result], [T[:handle], pointer("float")], ownership: "borrows Game; caller output"),
        signature("cna_sound_effect_set_distance_scale", T[:result], [T[:handle], T[:float]], ownership: "borrows Game; game-scoped where XNA is a CLR static"),
        signature("cna_sound_effect_get_doppler_scale", T[:result], [T[:handle], pointer("float")], ownership: "borrows Game; caller output"),
        signature("cna_sound_effect_set_doppler_scale", T[:result], [T[:handle], T[:float]], ownership: "borrows Game; game-scoped where XNA is a CLR static"),
        signature("cna_sound_effect_get_speed_of_sound", T[:result], [T[:handle], pointer("float")], ownership: "borrows Game; caller output"),
        signature("cna_sound_effect_set_speed_of_sound", T[:result], [T[:handle], T[:float]], ownership: "borrows Game; game-scoped where XNA is a CLR static"),
        signature("cna_sound_effect_instance_play", T[:result], [T[:handle]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_pause", T[:result], [T[:handle]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_resume", T[:result], [T[:handle]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_stop", T[:result], [T[:handle], T[:bool]], ownership: "borrows instance; immediate or as authored"),
        signature("cna_sound_effect_instance_get_info", T[:result], [T[:handle], pointer("CNA_SoundEffectInstanceInfo")], ownership: "caller MANAGED_VALUE snapshot output"),
        signature("cna_sound_effect_instance_set_volume", T[:result], [T[:handle], T[:float]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_set_pitch", T[:result], [T[:handle], T[:float]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_set_pan", T[:result], [T[:handle], T[:float]], ownership: "borrows instance"),
        signature("cna_sound_effect_instance_set_is_looped", T[:result], [T[:handle], T[:bool]], ownership: "borrows instance; refused once playback has begun"),
        signature("cna_sound_effect_instance_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_sound_effect_instance_apply_3d", T[:result], [T[:handle], pointer("CNA_AudioListener", const: true), pointer("CNA_AudioEmitter", const: true)], ownership: "borrows instance; copies both value snapshots"),
        signature("cna_sound_effect_instance_apply_3d_multi_ext", T[:result], [T[:handle], pointer("CNA_AudioListener", const: true), T[:u64], pointer("CNA_AudioEmitter", const: true)], ownership: "borrows instance; copies every value snapshot"),
        signature("cna_sound_effect_instance_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED instance"),
        # `DynamicSoundEffectInstance`. It is game-parented where an ordinary instance is
        # effect-parented, which is the ABI's own shape: it has no `SoundEffect` behind it.
        #
        # `submit_float_buffer_ext` and `clear_buffers_ext` are deliberately unbound -- XNA declares
        # neither, and a route with no identity to carry is surface this projection does not have.
        # `update_ext` is unbound for a stronger reason: it is the per-instance half of the pump that
        # `cna_framework_dispatcher_update` already drives, and `FrameworkDispatcher.Update` is the
        # projected member that drives it. Binding it would give this binding two pumps for one
        # queue, which is the duplication the producer audit refused.
        signature("cna_dynamic_sound_effect_instance_create", T[:result], [T[:handle], T[:i32], enum("CNA_AudioChannels"), pointer("CNA_Handle")], ownership: "returns OWNED instance parented to the Game"),
        signature("cna_dynamic_sound_effect_instance_get_pending_buffer_count", T[:result], [T[:handle], pointer("int32_t")], ownership: "caller output"),
        signature("cna_dynamic_sound_effect_instance_submit_buffer", T[:result], [T[:handle], pointer("uint8_t", const: true), T[:u64], T[:i32], T[:i32]], ownership: "borrows instance; copies the bytes"),
        signature("cna_dynamic_sound_effect_instance_queue_initial_buffers_ext", T[:result], [T[:handle]], ownership: "borrows instance", result_lifetime: "no result value"),
        signature("cna_dynamic_sound_effect_instance_get_sample_duration_ticks", T[:result], [T[:handle], T[:i32], pointer("int64_t")], ownership: "caller output"),
        signature("cna_dynamic_sound_effect_instance_get_sample_size_in_bytes", T[:result], [T[:handle], T[:i64], pointer("int32_t")], ownership: "caller output"),
        signature("cna_dynamic_sound_effect_instance_subscribe_buffer_needed", T[:result], [T[:handle], callback_pointer("CNA_AudioEventCallback"), T[:ptr], pointer("CNA_AudioEventRegistrationHandle")], ownership: "borrows instance; returns OWNED registration; retains the callback until released"),
        signature("cna_audio_unsubscribe_ext", T[:result], [handle("CNA_AudioEventRegistrationHandle")], ownership: "consumes OWNED registration"),
        # The microphone family. Every route is game-scoped and **index-addressed**: CNA has no
        # microphone handle at all, so a device is named by its position in the machine's list and
        # the runtime owns it. That makes every one of these BORROWED_EXTERNAL_SCALAR at the Ruby
        # side -- there is nothing to destroy, and `cna_microphone_stop_at` is a state change rather
        # than a release.
        signature("cna_microphone_get_count", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_default_index_ext", T[:result], [T[:handle], pointer("uint64_t"), pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_name_size_at", T[:result], [T[:handle], T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_copy_name_at", T[:result], [T[:handle], T[:u64], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_buffer_duration_ticks_at", T[:result], [T[:handle], T[:u64], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_set_buffer_duration_ticks_at", T[:result], [T[:handle], T[:u64], T[:i64]], ownership: "borrows Game; borrows BORROWED_EXTERNAL_SCALAR device index"),
        signature("cna_microphone_get_is_headset_at", T[:result], [T[:handle], T[:u64], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_sample_rate_at", T[:result], [T[:handle], T[:u64], pointer("int32_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_state_at", T[:result], [T[:handle], T[:u64], pointer("CNA_MicrophoneState")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_start_at", T[:result], [T[:handle], T[:u64]], ownership: "borrows Game; borrows BORROWED_EXTERNAL_SCALAR device index"),
        signature("cna_microphone_stop_at", T[:result], [T[:handle], T[:u64]], ownership: "borrows Game; borrows BORROWED_EXTERNAL_SCALAR device index"),
        signature("cna_microphone_get_data_at", T[:result], [T[:handle], T[:u64], pointer("uint8_t"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_sample_duration_ticks_at", T[:result], [T[:handle], T[:u64], T[:i32], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_get_sample_size_in_bytes_at", T[:result], [T[:handle], T[:u64], T[:i64], pointer("int32_t")], ownership: "borrows Game; caller output"),
        signature("cna_microphone_subscribe_buffer_ready_at", T[:result], [T[:handle], T[:u64], callback_pointer("CNA_AudioEventCallback"), T[:ptr], pointer("CNA_AudioEventRegistrationHandle")], ownership: "borrows Game; returns OWNED registration; retains the callback until released"),
        signature("cna_microphone_check_all_buffers_ext", T[:result], [T[:handle]], ownership: "borrows Game"),
        # The XACT engine cluster. `cna_audio_engine_create*` is **game-parented** where XNA's
        # constructor needs no Game -- the asymmetry every game-scoped audio route in this binding
        # records -- and a category handle is `PARENT_OWNED`: XNA's `AudioCategory` is a value type
        # with no `Dispose` and no finalizer, so the engine that produced one destroys it.
        signature("cna_audio_engine_create_with_renderer", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), T[:i64], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "borrows Game; returns OWNED engine"),
        signature("cna_audio_engine_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED engine"),
        signature("cna_audio_engine_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_update", T[:result], [T[:handle]], ownership: "borrows engine"),
        signature("cna_audio_engine_get_renderer_count", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_get_renderer_friendly_name_size", T[:result], [T[:handle], T[:u64], pointer("uint64_t")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_copy_renderer_friendly_name", T[:result], [T[:handle], T[:u64], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_get_renderer_id_size", T[:result], [T[:handle], T[:u64], pointer("uint64_t")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_copy_renderer_id", T[:result], [T[:handle], T[:u64], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_get_global_variable", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("float")], ownership: "borrows engine; caller output"),
        signature("cna_audio_engine_set_global_variable", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), T[:float]], ownership: "borrows engine"),
        signature("cna_audio_engine_get_category", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "borrows engine; returns PARENT_OWNED category, released with the engine"),
        signature("cna_audio_engine_subscribe_disposing_ext", T[:result], [T[:handle], callback_pointer("CNA_AudioEventCallback"), T[:ptr], pointer("CNA_Handle")], ownership: "borrows engine; returns OWNED registration; retains the callback until released"),
        signature("cna_audio_category_destroy", T[:result], [T[:handle]], ownership: "consumes PARENT_OWNED category"),
        signature("cna_audio_category_get_name_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows category; caller output"),
        signature("cna_audio_category_copy_name", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows category; caller output"),
        signature("cna_audio_category_pause", T[:result], [T[:handle]], ownership: "borrows category"),
        signature("cna_audio_category_resume", T[:result], [T[:handle]], ownership: "borrows category"),
        signature("cna_audio_category_set_volume", T[:result], [T[:handle], T[:float]], ownership: "borrows category"),
        signature("cna_audio_category_stop", T[:result], [T[:handle], enum("CNA_AudioStopOptions")], ownership: "borrows category"),
        signature("cna_audio_category_equals", T[:result], [T[:handle], T[:handle], pointer("CNA_Bool")], ownership: "borrows both; caller output"),
        signature("cna_audio_category_get_hash_code", T[:result], [T[:handle], pointer("int32_t")], ownership: "borrows category; caller output"),
        # The XACT bank and cue families. A wave bank and a sound bank are each `OWNED` and
        # engine-parented; a cue is `OWNED` by whoever asked the sound bank for it, which is what
        # XNA's `Cue.Dispose` says too.
        signature("cna_wave_bank_create", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "borrows engine; returns OWNED wave bank"),
        signature("cna_wave_bank_create_streaming", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), T[:i32], T[:i16], pointer("CNA_Handle")], ownership: "borrows engine; returns OWNED wave bank"),
        signature("cna_wave_bank_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED wave bank"),
        signature("cna_wave_bank_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows wave bank; caller output"),
        signature("cna_wave_bank_get_is_prepared", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows wave bank; caller output"),
        signature("cna_wave_bank_get_is_in_use", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows wave bank; caller output"),
        signature("cna_sound_bank_create", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "borrows engine; returns OWNED sound bank"),
        signature("cna_sound_bank_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED sound bank"),
        signature("cna_sound_bank_get_is_disposed", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows sound bank; caller output"),
        signature("cna_sound_bank_get_is_in_use", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows sound bank; caller output"),
        signature("cna_sound_bank_get_cue", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle")], ownership: "borrows sound bank; returns OWNED cue"),
        signature("cna_sound_bank_play_cue", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64])], ownership: "borrows sound bank"),
        signature("cna_sound_bank_play_cue_3d", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_AudioListener", const: true), pointer("CNA_AudioEmitter", const: true)], ownership: "borrows sound bank; borrows both descriptors"),
        signature("cna_cue_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED cue"),
        signature("cna_cue_get_info", T[:result], [T[:handle], pointer("CNA_CueInfo")], ownership: "borrows cue; caller MANAGED_VALUE snapshot output"),
        signature("cna_cue_get_name_size", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows cue; caller output"),
        signature("cna_cue_copy_name", T[:result], [T[:handle], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows cue; caller output"),
        signature("cna_cue_apply_3d", T[:result], [T[:handle], pointer("CNA_AudioListener", const: true), pointer("CNA_AudioEmitter", const: true)], ownership: "borrows cue; borrows both descriptors"),
        signature("cna_cue_get_variable", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("float")], ownership: "borrows cue; caller output"),
        signature("cna_cue_set_variable", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), T[:float]], ownership: "borrows cue"),
        signature("cna_cue_play", T[:result], [T[:handle]], ownership: "borrows cue"),
        signature("cna_cue_pause", T[:result], [T[:handle]], ownership: "borrows cue"),
        signature("cna_cue_resume", T[:result], [T[:handle]], ownership: "borrows cue"),
        signature("cna_cue_stop", T[:result], [T[:handle], enum("CNA_AudioStopOptions")], ownership: "borrows cue"),
        # The media-source enumeration. XNA's `MediaSource.GetAvailableMediaSources` queries nothing
        # at all -- it builds one object from a resource string -- so these four are bound to
        # *measure* what CNA answers for the same question, not to answer it.
        signature("cna_media_source_get_available_count", T[:result], [T[:handle], pointer("uint32_t")], ownership: "borrows Game; caller output"),
        signature("cna_media_source_get_type_at", T[:result], [T[:handle], T[:u32], pointer("CNA_MediaSourceType")], ownership: "borrows Game; caller output"),
        signature("cna_media_source_get_name_size_at", T[:result], [T[:handle], T[:u32], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        signature("cna_media_source_copy_name_at", T[:result], [T[:handle], T[:u32], pointer("char"), T[:u64], pointer("uint64_t")], ownership: "borrows Game; caller output"),
        # The sprite-font family. `cna_content_manager_load_sprite_font` is the producer XNA's
        # `ContentManager.Load<SpriteFont>` is, and it answers **two** owned handles: the font and
        # the atlas texture behind it, which the font's own destruction does not release.
        signature("cna_content_manager_load_sprite_font", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Handle"), pointer("CNA_Handle")], ownership: "borrows content manager; returns OWNED font and OWNED atlas texture"),
        signature("cna_sprite_font_get_info", T[:result], [T[:handle], pointer("CNA_SpriteFontInfo")], ownership: "borrows font; caller MANAGED_VALUE snapshot output"),
        signature("cna_sprite_font_copy_glyphs", T[:result], [T[:handle], pointer("CNA_SpriteFontGlyph"), T[:u64], pointer("uint64_t")], ownership: "borrows font; caller output"),
        signature("cna_sprite_font_set_default_character", T[:result], [T[:handle], T[:bool], T[:char16]], ownership: "borrows font"),
        signature("cna_sprite_font_set_line_spacing", T[:result], [T[:handle], T[:i32]], ownership: "borrows font"),
        signature("cna_sprite_font_set_spacing", T[:result], [T[:handle], T[:float]], ownership: "borrows font"),
        signature("cna_sprite_font_measure_utf8", T[:result], [T[:handle], *by_value("CNA_StringView", pointer("char", const: true), T[:u64]), pointer("CNA_Vector2")], ownership: "borrows font; caller MANAGED_VALUE output"),
        signature("cna_sprite_font_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED font"),
        signature("cna_keyboard_get_state", T[:result], [T[:handle], pointer("CNA_KeyboardState")], ownership: "caller MANAGED_VALUE output"),
        signature("cna_keyboard_get_state_for_player", T[:result], [T[:handle], enum("CNA_PlayerIndex"), pointer("CNA_KeyboardState")], ownership: "caller MANAGED_VALUE output"),
        signature("cna_keyboard_state_is_key_down", T[:result], [pointer("CNA_KeyboardState", const: true), enum("CNA_Key"), pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_keyboard_state_is_key_up", T[:result], [pointer("CNA_KeyboardState", const: true), enum("CNA_Key"), pointer("CNA_Bool")], ownership: "caller output"),
        signature("cna_keyboard_state_get_pressed_key_count", T[:result], [pointer("CNA_KeyboardState", const: true), pointer("uint32_t")], ownership: "caller output"),
        signature("cna_keyboard_state_copy_pressed_keys", T[:result], [pointer("CNA_KeyboardState", const: true), pointer("CNA_Key"), T[:u64], pointer("uint32_t")], ownership: "caller output"),
        signature("cna_mouse_get_state", T[:result], [T[:handle], pointer("CNA_MouseState")], ownership: "borrows Game; caller MANAGED_VALUE snapshot output"),
        signature("cna_mouse_set_position", T[:result], [T[:handle], T[:i32], T[:i32]], ownership: "borrows Game; PROCESS_GLOBAL mouse; no retained state"),
        signature("cna_mouse_get_window_handle", T[:result], [T[:handle], pointer("uint64_t")], ownership: "borrows Game; caller output BORROWED_EXTERNAL_SCALAR"),
        signature("cna_mouse_set_window_handle", T[:result], [T[:handle], T[:u64]], ownership: "borrows Game and BORROWED_EXTERNAL_SCALAR; never frees window"),
        signature("cna_gamepad_get_state", T[:result], [T[:handle], enum("CNA_PlayerIndex"), pointer("CNA_GamePadState")], ownership: "borrows Game; caller MANAGED_VALUE snapshot output"),
        signature("cna_gamepad_get_state_with_dead_zone", T[:result], [T[:handle], enum("CNA_PlayerIndex"), enum("CNA_GamePadDeadZone"), pointer("CNA_GamePadState")], ownership: "borrows Game; caller MANAGED_VALUE snapshot output"),
        signature("cna_gamepad_get_capabilities", T[:result], [T[:handle], enum("CNA_PlayerIndex"), pointer("CNA_GamePadCapabilities")], ownership: "borrows Game; caller MANAGED_VALUE snapshot output"),
        signature("cna_gamepad_set_vibration", T[:result], [T[:handle], enum("CNA_PlayerIndex"), T[:float], T[:float], pointer("CNA_Bool")], ownership: "borrows Game; writes selected controller actuator; caller Boolean output")
      ].freeze

      CALLBACKS = [
        { name: "CNA_GameLifecycleCallback", c_return: "CNA_Result", c_arguments: ["CNA_Handle", "const CNA_GameTime*", "void*", "CNA_CallbackError*"], calling_convention: "platform C", fiddle_return: U32, fiddle_arguments: [U64, PTR, PTR, PTR] },
        { name: "CNA_GameBeginDrawCallback", c_return: "CNA_Result", c_arguments: ["CNA_Handle", "const CNA_GameTime*", "void*", "CNA_Bool*", "CNA_CallbackError*"], calling_convention: "platform C", fiddle_return: U32, fiddle_arguments: [U64, PTR, PTR, PTR, PTR] },
        # A game event carries nothing but its sender, so the handler receives only its context --
        # and it returns void, so a failure has nowhere to go and must never escape into C.
        { name: "CNA_GameEventCallback", c_return: "void", c_arguments: ["void*"], calling_convention: "platform C", fiddle_return: VOID, fiddle_arguments: [PTR] },
        # Shape-identical to CNA_GameEventCallback and still a separate identity: it is a different
        # typedef in a different header, and the ABI probe type-checks each against its own
        # declaration rather than against the other.
        { name: "CNA_GamerAsyncCallback", c_return: "void", c_arguments: ["void*"], calling_convention: "platform C", fiddle_return: VOID, fiddle_arguments: [PTR] },
        { name: "CNA_AudioEventCallback", c_return: "void", c_arguments: ["void*"], calling_convention: "platform C", fiddle_return: VOID, fiddle_arguments: [PTR] }
      ].freeze

      # `CNA_ABI_VERSION` is deliberately **not** here. It is not a constant this binding consumes;
      # it is the identity this binding gates on, and it is the one measurement that legitimately
      # differs between two admitted versions. The verifier checks it against
      # `ADMITTED_ABI_VERSIONS` per header root instead, so a version mismatch is reported as an
      # admission failure rather than as a constant mismatch.
      CONSTANTS = {
        "CNA_FALSE" => 0, "CNA_TRUE" => 1,
        "CNA_RESULT_SUCCESS" => 0, "CNA_RESULT_NOT_SUPPORTED" => 6,
        "CNA_RESULT_THREAD" => 8, "CNA_RESULT_CALLBACK" => 9,
        "CNA_GAME_EVENT_ACTIVATED" => 0,
        "CNA_GAME_EVENT_DEACTIVATED" => 1,
        "CNA_GAME_EVENT_DISPOSED" => 2,
        "CNA_GAME_EVENT_EXITING" => 3,
        "CNA_GAME_WINDOW_EVENT_CLIENT_SIZE_CHANGED" => 0,
        "CNA_GAME_WINDOW_EVENT_ORIENTATION_CHANGED" => 1,
        "CNA_GAME_WINDOW_EVENT_SCREEN_DEVICE_NAME_CHANGED" => 2,
        "CNA_SPRITE_SORT_MODE_DEFERRED" => 0,
        "CNA_SPRITE_EFFECT_NONE" => 0,
        "CNA_SPRITE_EFFECT_FLIP_HORIZONTALLY" => 1,
        "CNA_SPRITE_EFFECT_FLIP_VERTICALLY" => 2,
        "CNA_SURFACE_FORMAT_COLOR" => 0,
        "CNA_TEXTURE_DATA_COLOR" => 0,
        "CNA_TEXTURE_DATA_BGR565" => 1,
        "CNA_TEXTURE_DATA_BGRA5551" => 2,
        "CNA_TEXTURE_DATA_BGRA4444" => 3,
        "CNA_TEXTURE_DATA_BYTE" => 4,
        "CNA_TEXTURE_DATA_NORMALIZED_BYTE2" => 5,
        "CNA_TEXTURE_DATA_NORMALIZED_BYTE4" => 6,
        "CNA_TEXTURE_DATA_RGBA1010102" => 7,
        "CNA_TEXTURE_DATA_RG32" => 8,
        "CNA_TEXTURE_DATA_RGBA64" => 9,
        "CNA_TEXTURE_DATA_ALPHA8" => 10,
        "CNA_TEXTURE_IMAGE_FORMAT_PNG" => 0,
        "CNA_TEXTURE_IMAGE_FORMAT_JPEG" => 1,
        # The preset identities the four state-object cross-checks name. Every one is measured
        # against the header by the ABI probe rather than transcribed on trust.
        "CNA_BLEND_STATE_PRESET_ADDITIVE" => 1,
        "CNA_BLEND_STATE_PRESET_ALPHA_BLEND" => 2,
        "CNA_BLEND_STATE_PRESET_NON_PREMULTIPLIED" => 3,
        "CNA_BLEND_STATE_PRESET_OPAQUE" => 4,
        "CNA_DEPTH_STENCIL_STATE_PRESET_DEFAULT" => 0,
        "CNA_DEPTH_STENCIL_STATE_PRESET_DEPTH_READ" => 1,
        "CNA_DEPTH_STENCIL_STATE_PRESET_NONE" => 2,
        "CNA_RASTERIZER_STATE_PRESET_CULL_CLOCKWISE" => 1,
        "CNA_RASTERIZER_STATE_PRESET_CULL_COUNTER_CLOCKWISE" => 2,
        "CNA_RASTERIZER_STATE_PRESET_CULL_NONE" => 3,
        "CNA_SAMPLER_STATE_PRESET_ANISOTROPIC_CLAMP" => 1,
        "CNA_SAMPLER_STATE_PRESET_ANISOTROPIC_WRAP" => 2,
        "CNA_SAMPLER_STATE_PRESET_LINEAR_CLAMP" => 3,
        "CNA_SAMPLER_STATE_PRESET_LINEAR_WRAP" => 4,
        "CNA_SAMPLER_STATE_PRESET_POINT_CLAMP" => 5,
        "CNA_SAMPLER_STATE_PRESET_POINT_WRAP" => 6,
        # The effect-cluster identities. `CNA_EffectValueType` tags which C type a parameter's
        # value routes carry, `CNA_EffectTextureType` which of XNA's four texture overloads a
        # texture slot is, and the class/type pairs are what `EffectParameter.ParameterClass` and
        # `ParameterType` answer. Every one is measured against the header by the ABI probe.
        "CNA_EFFECT_VALUE_BOOLEAN" => 0, "CNA_EFFECT_VALUE_INT32" => 1,
        "CNA_EFFECT_VALUE_SINGLE" => 2, "CNA_EFFECT_VALUE_MATRIX" => 3,
        "CNA_EFFECT_VALUE_MATRIX_TRANSPOSE" => 4, "CNA_EFFECT_VALUE_QUATERNION" => 5,
        "CNA_EFFECT_VALUE_VECTOR2" => 6, "CNA_EFFECT_VALUE_VECTOR3" => 7,
        "CNA_EFFECT_VALUE_VECTOR4" => 8,
        "CNA_EFFECT_TEXTURE_BASE" => 0, "CNA_EFFECT_TEXTURE_2D" => 1,
        "CNA_EFFECT_TEXTURE_3D" => 2, "CNA_EFFECT_TEXTURE_CUBE" => 3,
        "CNA_EFFECT_PARAMETER_CLASS_SCALAR" => 0, "CNA_EFFECT_PARAMETER_CLASS_VECTOR" => 1,
        "CNA_EFFECT_PARAMETER_CLASS_MATRIX" => 2, "CNA_EFFECT_PARAMETER_CLASS_OBJECT" => 3,
        "CNA_EFFECT_PARAMETER_CLASS_STRUCT" => 4,
        "CNA_EFFECT_PARAMETER_TYPE_VOID" => 0, "CNA_EFFECT_PARAMETER_TYPE_BOOL" => 1,
        "CNA_EFFECT_PARAMETER_TYPE_INT32" => 2, "CNA_EFFECT_PARAMETER_TYPE_SINGLE" => 3,
        "CNA_EFFECT_PARAMETER_TYPE_STRING" => 4, "CNA_EFFECT_PARAMETER_TYPE_TEXTURE" => 5,
        "CNA_EFFECT_PARAMETER_TYPE_TEXTURE1D" => 6, "CNA_EFFECT_PARAMETER_TYPE_TEXTURE2D" => 7,
        "CNA_EFFECT_PARAMETER_TYPE_TEXTURE3D" => 8, "CNA_EFFECT_PARAMETER_TYPE_TEXTURE_CUBE" => 9,
        # The four built-in vertex layouts this binding projects a type for. CNA's typed
        # vertex-buffer transfer is what carries `SetDataOptions`, and these are the identities it
        # accepts; the other three built-ins name types no XNA 4.0 profile has.
        "CNA_VERTEX_TYPE_POSITION_COLOR" => 0, "CNA_VERTEX_TYPE_POSITION_COLOR_TEXTURE" => 1,
        "CNA_VERTEX_TYPE_POSITION_NORMAL_TEXTURE" => 4, "CNA_VERTEX_TYPE_POSITION_TEXTURE" => 6,
        "CNA_MICROPHONE_STATE_STARTED" => 0,
        "CNA_MICROPHONE_STATE_STOPPED" => 1,
        "CNA_MICROPHONE_STATE_MAXIMUM" => 1,
        "CNA_MAX_SAMPLERS" => 16,
        "CNA_SHADER_STAGE_PIXEL" => 0,
        "CNA_SHADER_STAGE_VERTEX" => 1,
        "CNA_TEXTURE_COLLECTION_MAX_TEXTURES" => 16,
        "CNA_MOUSE_BUTTON_LEFT" => 1,
        "CNA_MOUSE_BUTTON_MIDDLE" => 2,
        "CNA_MOUSE_BUTTON_RIGHT" => 4,
        "CNA_MOUSE_BUTTON_X1" => 8,
        "CNA_MOUSE_BUTTON_X2" => 16,
        "CNA_PLAYER_INDEX_ONE" => 0,
        "CNA_PLAYER_INDEX_TWO" => 1,
        "CNA_PLAYER_INDEX_THREE" => 2,
        "CNA_PLAYER_INDEX_FOUR" => 3,
        "CNA_GAMEPAD_DEAD_ZONE_NONE" => 0,
        "CNA_GAMEPAD_DEAD_ZONE_INDEPENDENT_AXES" => 1,
        "CNA_GAMEPAD_DEAD_ZONE_CIRCULAR" => 2,
        "CNA_GAMEPAD_BUTTON_DPAD_UP" => 0x0000_0001,
        "CNA_GAMEPAD_BUTTON_DPAD_DOWN" => 0x0000_0002,
        "CNA_GAMEPAD_BUTTON_DPAD_LEFT" => 0x0000_0004,
        "CNA_GAMEPAD_BUTTON_DPAD_RIGHT" => 0x0000_0008,
        "CNA_GAMEPAD_BUTTON_START" => 0x0000_0010,
        "CNA_GAMEPAD_BUTTON_BACK" => 0x0000_0020,
        "CNA_GAMEPAD_BUTTON_LEFT_STICK" => 0x0000_0040,
        "CNA_GAMEPAD_BUTTON_RIGHT_STICK" => 0x0000_0080,
        "CNA_GAMEPAD_BUTTON_LEFT_SHOULDER" => 0x0000_0100,
        "CNA_GAMEPAD_BUTTON_RIGHT_SHOULDER" => 0x0000_0200,
        "CNA_GAMEPAD_BUTTON_BIG_BUTTON" => 0x0000_0800,
        "CNA_GAMEPAD_BUTTON_A" => 0x0000_1000,
        "CNA_GAMEPAD_BUTTON_B" => 0x0000_2000,
        "CNA_GAMEPAD_BUTTON_X" => 0x0000_4000,
        "CNA_GAMEPAD_BUTTON_Y" => 0x0000_8000,
        "CNA_GAMEPAD_BUTTON_LEFT_THUMBSTICK_LEFT" => 0x0020_0000,
        "CNA_GAMEPAD_BUTTON_RIGHT_TRIGGER" => 0x0040_0000,
        "CNA_GAMEPAD_BUTTON_LEFT_TRIGGER" => 0x0080_0000,
        "CNA_GAMEPAD_BUTTON_RIGHT_THUMBSTICK_UP" => 0x0100_0000,
        "CNA_GAMEPAD_BUTTON_RIGHT_THUMBSTICK_DOWN" => 0x0200_0000,
        "CNA_GAMEPAD_BUTTON_RIGHT_THUMBSTICK_RIGHT" => 0x0400_0000,
        "CNA_GAMEPAD_BUTTON_RIGHT_THUMBSTICK_LEFT" => 0x0800_0000,
        "CNA_GAMEPAD_BUTTON_LEFT_THUMBSTICK_UP" => 0x1000_0000,
        "CNA_GAMEPAD_BUTTON_LEFT_THUMBSTICK_DOWN" => 0x2000_0000,
        "CNA_GAMEPAD_BUTTON_LEFT_THUMBSTICK_RIGHT" => 0x4000_0000,
        "CNA_GAMEPAD_TYPE_UNKNOWN" => 0,
        "CNA_GAMEPAD_TYPE_GAMEPAD" => 1,
        "CNA_GAMEPAD_TYPE_WHEEL" => 2,
        "CNA_GAMEPAD_TYPE_ARCADE_STICK" => 3,
        "CNA_GAMEPAD_TYPE_FLIGHT_STICK" => 4,
        "CNA_GAMEPAD_TYPE_DANCE_PAD" => 5,
        "CNA_GAMEPAD_TYPE_GUITAR" => 6,
        "CNA_GAMEPAD_TYPE_ALTERNATE_GUITAR" => 7,
        "CNA_GAMEPAD_TYPE_DRUM_KIT" => 8,
        "CNA_GAMEPAD_TYPE_BIG_BUTTON_PAD" => 9
      }.freeze
    end
  end
end
