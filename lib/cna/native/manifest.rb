# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    Signature = Data.define(
      :symbol, :c_return, :c_arguments, :fiddle_return, :fiddle_arguments,
      :pointer_depths, :const_arguments, :integer_widths, :signedness,
      :ownership, :result_lifetime, :callback_abi, :value_aggregates
    )

    module Manifest
      U8 = Fiddle::TYPE_UINT8_T
      U32 = Fiddle::TYPE_UINT32_T
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
        arguments.each_with_index do |value, index|
          next unless value[:value_aggregate]

          next unless value.fetch(:aggregate_start, false)

          value_aggregates[index] = { c: value.fetch(:value_aggregate), members: value.fetch(:aggregate_members) }
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
          value_aggregates: value_aggregates.freeze
        )
      end

      T = {
        result: { c: "CNA_Result", fiddle: U32, width: 32, signed: false },
        u32: { c: "uint32_t", fiddle: U32, width: 32, signed: false },
        i32: { c: "int32_t", fiddle: I32, width: 32, signed: true },
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
        signature("cna_graphics_device_manager_dispose", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "borrows manager; canonical dispose"),
        signature("cna_graphics_device_manager_destroy", T[:result], [handle("CNA_GraphicsDeviceManagerHandle")], ownership: "consumes OWNED manager"),
        signature("cna_graphics_device_get_viewport", T[:result], [T[:handle], pointer("CNA_Viewport")], ownership: "caller output"),
        signature("cna_graphics_device_clear_rgba", T[:result], [T[:handle], T[:float], T[:float], T[:float], T[:float]], ownership: "borrows device"),
        signature("cna_texture2d_create_from_encoded_memory", T[:result], [T[:handle], pointer("uint8_t", const: true), T[:u64], pointer("CNA_Texture2DDecodeInfo", const: true), pointer("CNA_Handle")], ownership: "returns OWNED Texture2D"),
        signature("cna_texture2d_get_info", T[:result], [T[:handle], pointer("CNA_Texture2DInfo")], ownership: "caller output"),
        signature("cna_texture2d_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED Texture2D"),
        signature("cna_sprite_batch_create", T[:result], [T[:handle], pointer("CNA_Handle")], ownership: "returns OWNED SpriteBatch"),
        signature("cna_sprite_batch_begin", T[:result], [T[:handle], pointer("CNA_SpriteBatchBeginInfo", const: true)], ownership: "borrows SpriteBatch"),
        signature("cna_sprite_batch_submit_scaled_many", T[:result], [T[:handle], pointer("CNA_SpriteScaledCommand", const: true), T[:u64]], ownership: "copies commands; retains Texture until End"),
        signature("cna_sprite_batch_end", T[:result], [T[:handle]], ownership: "borrows SpriteBatch"),
        signature("cna_sprite_batch_destroy", T[:result], [T[:handle]], ownership: "consumes OWNED SpriteBatch"),
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
        { name: "CNA_GameEventCallback", c_return: "void", c_arguments: ["void*"], calling_convention: "platform C", fiddle_return: VOID, fiddle_arguments: [PTR] }
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
