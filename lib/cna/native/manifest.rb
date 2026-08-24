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
        signature("cna_keyboard_state_copy_pressed_keys", T[:result], [pointer("CNA_KeyboardState", const: true), pointer("CNA_Key"), T[:u64], pointer("uint32_t")], ownership: "caller output")
      ].freeze

      CALLBACKS = [
        { name: "CNA_GameLifecycleCallback", c_return: "CNA_Result", c_arguments: ["CNA_Handle", "const CNA_GameTime*", "void*", "CNA_CallbackError*"], calling_convention: "platform C", fiddle_return: U32, fiddle_arguments: [U64, PTR, PTR, PTR] },
        { name: "CNA_GameBeginDrawCallback", c_return: "CNA_Result", c_arguments: ["CNA_Handle", "const CNA_GameTime*", "void*", "CNA_Bool*", "CNA_CallbackError*"], calling_convention: "platform C", fiddle_return: U32, fiddle_arguments: [U64, PTR, PTR, PTR, PTR] }
      ].freeze

      CONSTANTS = {
        "CNA_ABI_VERSION" => 0x0000_0700,
        "CNA_FALSE" => 0, "CNA_TRUE" => 1,
        "CNA_RESULT_SUCCESS" => 0, "CNA_RESULT_NOT_SUPPORTED" => 6,
        "CNA_RESULT_THREAD" => 8, "CNA_RESULT_CALLBACK" => 9,
        "CNA_SPRITE_SORT_MODE_DEFERRED" => 0,
        "CNA_SPRITE_EFFECT_NONE" => 0,
        "CNA_SPRITE_EFFECT_FLIP_HORIZONTALLY" => 1,
        "CNA_SPRITE_EFFECT_FLIP_VERTICALLY" => 2,
        "CNA_SURFACE_FORMAT_COLOR" => 0
      }.freeze
    end
  end
end
