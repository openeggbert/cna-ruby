# frozen_string_literal: true

require "fiddle"

module CNA
  module Native
    Signature = Data.define(
      :symbol, :c_return, :c_arguments, :fiddle_return, :fiddle_arguments,
      :pointer_depths, :const_arguments, :integer_widths, :signedness,
      :ownership, :result_lifetime, :callback_abi
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
          callback_abi: callback_abi
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
      def callback_pointer(c)
        { c: c, fiddle: PTR, pointer_depth: 0 }
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
        signature("cna_game_get_is_mouse_visible", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_is_mouse_visible", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; shows or hides the window cursor"),
        signature("cna_game_get_is_fixed_time_step", T[:result], [T[:handle], pointer("CNA_Bool")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_is_fixed_time_step", T[:result], [T[:handle], T[:bool]], ownership: "borrows Game; chooses fixed or variable timing"),
        signature("cna_game_get_target_elapsed_time_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_target_elapsed_time_ticks", T[:result], [T[:handle], T[:i64]], ownership: "borrows Game; rejects a non-positive step"),
        signature("cna_game_get_inactive_sleep_time_ticks", T[:result], [T[:handle], pointer("int64_t")], ownership: "borrows Game; caller output"),
        signature("cna_game_set_inactive_sleep_time_ticks", T[:result], [T[:handle], T[:i64]], ownership: "borrows Game; rejects a negative duration"),
        signature("cna_framework_dispatcher_update", T[:result], [T[:handle]], ownership: "borrows Game; pumps the canonical CNA framework dispatcher", result_lifetime: "no result value"),
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

      CONSTANTS = {
        "CNA_ABI_VERSION" => 0x0000_0700,
        "CNA_FALSE" => 0, "CNA_TRUE" => 1,
        "CNA_RESULT_SUCCESS" => 0, "CNA_RESULT_NOT_SUPPORTED" => 6,
        "CNA_RESULT_THREAD" => 8, "CNA_RESULT_CALLBACK" => 9,
        "CNA_GAME_EVENT_ACTIVATED" => 0,
        "CNA_GAME_EVENT_DEACTIVATED" => 1,
        "CNA_GAME_EVENT_DISPOSED" => 2,
        "CNA_GAME_EVENT_EXITING" => 3,
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
