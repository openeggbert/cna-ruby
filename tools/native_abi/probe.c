// SPDX-License-Identifier: MIT
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "CNA/C/cna.h"

#define CHECK_FN(name, result, parameters) \
    typedef result (*expected_##name) parameters; \
    _Static_assert(__builtin_types_compatible_p(__typeof__(&name), expected_##name), "prototype mismatch: " #name)

CHECK_FN(cna_get_abi_version, uint32_t, (void));
CHECK_FN(cna_error_get_last_info, CNA_Result, (CNA_ErrorInfo*));
CHECK_FN(cna_error_get_last_message_size, CNA_Result, (uint64_t*));
CHECK_FN(cna_error_copy_last_message, CNA_Result, (char*, uint64_t, uint64_t*));
CHECK_FN(cna_game_create, CNA_Result, (const CNA_GameCreateInfo*, CNA_Handle*));
CHECK_FN(cna_game_set_frame_hooks_ext, CNA_Result, (CNA_Handle, const CNA_GameFrameHooks*));
CHECK_FN(cna_game_run, CNA_Result, (CNA_Handle));
CHECK_FN(cna_game_run_one_frame, CNA_Result, (CNA_Handle));
CHECK_FN(cna_game_request_exit, CNA_Result, (CNA_Handle));
CHECK_FN(cna_game_destroy, CNA_Result, (CNA_Handle));
CHECK_FN(cna_graphics_device_manager_create, CNA_Result, (CNA_Handle, CNA_GraphicsDeviceManagerHandle*));
CHECK_FN(cna_graphics_device_manager_get_graphics_device, CNA_Result, (CNA_GraphicsDeviceManagerHandle, CNA_Handle*));
CHECK_FN(cna_graphics_device_manager_dispose, CNA_Result, (CNA_GraphicsDeviceManagerHandle));
CHECK_FN(cna_graphics_device_manager_destroy, CNA_Result, (CNA_GraphicsDeviceManagerHandle));
CHECK_FN(cna_graphics_device_get_viewport, CNA_Result, (CNA_Handle, CNA_Viewport*));
CHECK_FN(cna_graphics_device_clear_rgba, CNA_Result, (CNA_Handle, float, float, float, float));
CHECK_FN(cna_texture2d_create_from_encoded_memory, CNA_Result, (CNA_Handle, const uint8_t*, uint64_t, const CNA_Texture2DDecodeInfo*, CNA_Handle*));
CHECK_FN(cna_texture2d_get_info, CNA_Result, (CNA_Handle, CNA_Texture2DInfo*));
CHECK_FN(cna_texture2d_destroy, CNA_Result, (CNA_Handle));
CHECK_FN(cna_sprite_batch_create, CNA_Result, (CNA_Handle, CNA_Handle*));
CHECK_FN(cna_sprite_batch_begin, CNA_Result, (CNA_Handle, const CNA_SpriteBatchBeginInfo*));
CHECK_FN(cna_sprite_batch_submit_scaled_many, CNA_Result, (CNA_Handle, const CNA_SpriteScaledCommand*, uint64_t));
CHECK_FN(cna_sprite_batch_end, CNA_Result, (CNA_Handle));
CHECK_FN(cna_sprite_batch_destroy, CNA_Result, (CNA_Handle));
CHECK_FN(cna_keyboard_get_state, CNA_Result, (CNA_Handle, CNA_KeyboardState*));
CHECK_FN(cna_keyboard_get_state_for_player, CNA_Result, (CNA_Handle, CNA_PlayerIndex, CNA_KeyboardState*));
CHECK_FN(cna_keyboard_state_is_key_down, CNA_Result, (const CNA_KeyboardState*, CNA_Key, CNA_Bool*));
CHECK_FN(cna_keyboard_state_is_key_up, CNA_Result, (const CNA_KeyboardState*, CNA_Key, CNA_Bool*));
CHECK_FN(cna_keyboard_state_get_pressed_key_count, CNA_Result, (const CNA_KeyboardState*, uint32_t*));
CHECK_FN(cna_keyboard_state_copy_pressed_keys, CNA_Result, (const CNA_KeyboardState*, CNA_Key*, uint64_t, uint32_t*));

typedef CNA_Result (*expected_lifecycle)(CNA_Handle, const CNA_GameTime*, void*, CNA_CallbackError*);
typedef CNA_Result (*expected_begin_draw)(CNA_Handle, const CNA_GameTime*, void*, CNA_Bool*, CNA_CallbackError*);
_Static_assert(__builtin_types_compatible_p(CNA_GameLifecycleCallback, expected_lifecycle), "lifecycle callback mismatch");
_Static_assert(__builtin_types_compatible_p(CNA_GameBeginDrawCallback, expected_begin_draw), "begin-draw callback mismatch");

#define STRUCT(type) printf("STRUCT|" #type "|%zu|%zu\n", sizeof(type), _Alignof(type))
#define FIELD(type, field) printf("FIELD|" #type "|" #field "|%zu|%zu\n", offsetof(type, field), sizeof(((type*)0)->field))
#define CONSTANT(name) printf("CONSTANT|" #name "|%llu\n", (unsigned long long)(name))
#define SIGNATURE(name, value) printf("SIGNATURE|" #name "|" value "\n")

int main(void) {
    SIGNATURE(cna_get_abi_version, "uint32_t|");
    SIGNATURE(cna_error_get_last_info, "CNA_Result|CNA_ErrorInfo*");
    SIGNATURE(cna_error_get_last_message_size, "CNA_Result|uint64_t*");
    SIGNATURE(cna_error_copy_last_message, "CNA_Result|char*,uint64_t,uint64_t*");
    SIGNATURE(cna_game_create, "CNA_Result|const CNA_GameCreateInfo*,CNA_Handle*");
    SIGNATURE(cna_game_set_frame_hooks_ext, "CNA_Result|CNA_Handle,const CNA_GameFrameHooks*");
    SIGNATURE(cna_game_run, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_game_run_one_frame, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_game_request_exit, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_game_destroy, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_graphics_device_manager_create, "CNA_Result|CNA_Handle,CNA_GraphicsDeviceManagerHandle*");
    SIGNATURE(cna_graphics_device_manager_get_graphics_device, "CNA_Result|CNA_GraphicsDeviceManagerHandle,CNA_Handle*");
    SIGNATURE(cna_graphics_device_manager_dispose, "CNA_Result|CNA_GraphicsDeviceManagerHandle");
    SIGNATURE(cna_graphics_device_manager_destroy, "CNA_Result|CNA_GraphicsDeviceManagerHandle");
    SIGNATURE(cna_graphics_device_get_viewport, "CNA_Result|CNA_Handle,CNA_Viewport*");
    SIGNATURE(cna_graphics_device_clear_rgba, "CNA_Result|CNA_Handle,float,float,float,float");
    SIGNATURE(cna_texture2d_create_from_encoded_memory, "CNA_Result|CNA_Handle,const uint8_t*,uint64_t,const CNA_Texture2DDecodeInfo*,CNA_Handle*");
    SIGNATURE(cna_texture2d_get_info, "CNA_Result|CNA_Handle,CNA_Texture2DInfo*");
    SIGNATURE(cna_texture2d_destroy, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_sprite_batch_create, "CNA_Result|CNA_Handle,CNA_Handle*");
    SIGNATURE(cna_sprite_batch_begin, "CNA_Result|CNA_Handle,const CNA_SpriteBatchBeginInfo*");
    SIGNATURE(cna_sprite_batch_submit_scaled_many, "CNA_Result|CNA_Handle,const CNA_SpriteScaledCommand*,uint64_t");
    SIGNATURE(cna_sprite_batch_end, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_sprite_batch_destroy, "CNA_Result|CNA_Handle");
    SIGNATURE(cna_keyboard_get_state, "CNA_Result|CNA_Handle,CNA_KeyboardState*");
    SIGNATURE(cna_keyboard_get_state_for_player, "CNA_Result|CNA_Handle,CNA_PlayerIndex,CNA_KeyboardState*");
    SIGNATURE(cna_keyboard_state_is_key_down, "CNA_Result|const CNA_KeyboardState*,CNA_Key,CNA_Bool*");
    SIGNATURE(cna_keyboard_state_is_key_up, "CNA_Result|const CNA_KeyboardState*,CNA_Key,CNA_Bool*");
    SIGNATURE(cna_keyboard_state_get_pressed_key_count, "CNA_Result|const CNA_KeyboardState*,uint32_t*");
    SIGNATURE(cna_keyboard_state_copy_pressed_keys, "CNA_Result|const CNA_KeyboardState*,CNA_Key*,uint64_t,uint32_t*");

    STRUCT(CNA_StringView); FIELD(CNA_StringView, data); FIELD(CNA_StringView, byte_length);
    STRUCT(CNA_ErrorInfo); FIELD(CNA_ErrorInfo, struct_size); FIELD(CNA_ErrorInfo, struct_version); FIELD(CNA_ErrorInfo, result); FIELD(CNA_ErrorInfo, category); FIELD(CNA_ErrorInfo, message_byte_length);
    STRUCT(CNA_GameTime); FIELD(CNA_GameTime, total_game_time_ticks); FIELD(CNA_GameTime, elapsed_game_time_ticks); FIELD(CNA_GameTime, is_running_slowly); FIELD(CNA_GameTime, reserved);
    STRUCT(CNA_CallbackError); FIELD(CNA_CallbackError, struct_size); FIELD(CNA_CallbackError, struct_version); FIELD(CNA_CallbackError, message);
    STRUCT(CNA_GameCallbacks); FIELD(CNA_GameCallbacks, struct_size); FIELD(CNA_GameCallbacks, struct_version); FIELD(CNA_GameCallbacks, load_content); FIELD(CNA_GameCallbacks, update); FIELD(CNA_GameCallbacks, draw); FIELD(CNA_GameCallbacks, unload_content); FIELD(CNA_GameCallbacks, exiting); FIELD(CNA_GameCallbacks, context);
    STRUCT(CNA_GameFrameHooks); FIELD(CNA_GameFrameHooks, struct_size); FIELD(CNA_GameFrameHooks, struct_version); FIELD(CNA_GameFrameHooks, initialize); FIELD(CNA_GameFrameHooks, begin_run); FIELD(CNA_GameFrameHooks, end_run); FIELD(CNA_GameFrameHooks, begin_draw); FIELD(CNA_GameFrameHooks, end_draw); FIELD(CNA_GameFrameHooks, context);
    STRUCT(CNA_GameCreateInfo); FIELD(CNA_GameCreateInfo, struct_size); FIELD(CNA_GameCreateInfo, struct_version); FIELD(CNA_GameCreateInfo, is_fixed_time_step); FIELD(CNA_GameCreateInfo, reserved); FIELD(CNA_GameCreateInfo, target_elapsed_time_ticks); FIELD(CNA_GameCreateInfo, window_title); FIELD(CNA_GameCreateInfo, callbacks);
    STRUCT(CNA_Viewport); FIELD(CNA_Viewport, x); FIELD(CNA_Viewport, y); FIELD(CNA_Viewport, width); FIELD(CNA_Viewport, height); FIELD(CNA_Viewport, min_depth); FIELD(CNA_Viewport, max_depth);
    STRUCT(CNA_Texture2DInfo); FIELD(CNA_Texture2DInfo, struct_size); FIELD(CNA_Texture2DInfo, struct_version); FIELD(CNA_Texture2DInfo, width); FIELD(CNA_Texture2DInfo, height); FIELD(CNA_Texture2DInfo, level_count); FIELD(CNA_Texture2DInfo, format);
    STRUCT(CNA_SpriteBatchBeginInfo); FIELD(CNA_SpriteBatchBeginInfo, struct_size); FIELD(CNA_SpriteBatchBeginInfo, struct_version); FIELD(CNA_SpriteBatchBeginInfo, sort_mode); FIELD(CNA_SpriteBatchBeginInfo, reserved);
    STRUCT(CNA_SpriteScaledCommand); FIELD(CNA_SpriteScaledCommand, struct_size); FIELD(CNA_SpriteScaledCommand, struct_version); FIELD(CNA_SpriteScaledCommand, texture); FIELD(CNA_SpriteScaledCommand, position); FIELD(CNA_SpriteScaledCommand, source); FIELD(CNA_SpriteScaledCommand, color); FIELD(CNA_SpriteScaledCommand, rotation); FIELD(CNA_SpriteScaledCommand, origin); FIELD(CNA_SpriteScaledCommand, scale); FIELD(CNA_SpriteScaledCommand, effects); FIELD(CNA_SpriteScaledCommand, layer_depth);
    STRUCT(CNA_KeyboardState); FIELD(CNA_KeyboardState, struct_size); FIELD(CNA_KeyboardState, struct_version); FIELD(CNA_KeyboardState, pressed_key_words);

    CONSTANT(CNA_ABI_VERSION); CONSTANT(CNA_FALSE); CONSTANT(CNA_TRUE);
    CONSTANT(CNA_RESULT_SUCCESS); CONSTANT(CNA_RESULT_NOT_SUPPORTED); CONSTANT(CNA_RESULT_THREAD); CONSTANT(CNA_RESULT_CALLBACK);
    CONSTANT(CNA_SPRITE_SORT_MODE_DEFERRED); CONSTANT(CNA_SPRITE_EFFECT_NONE); CONSTANT(CNA_SPRITE_EFFECT_FLIP_HORIZONTALLY); CONSTANT(CNA_SPRITE_EFFECT_FLIP_VERTICALLY);
    CONSTANT(CNA_SURFACE_FORMAT_COLOR);
    return 0;
}
