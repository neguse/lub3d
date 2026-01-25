/*
 * miniaudio Lua bindings for mane3d
 * Provides audio playback functionality using miniaudio library
 */

#include <string.h>
#include <stdlib.h>

/* Enable stb_vorbis for OGG support */
#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

/* stb_vorbis implementation */
#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

/* stb_vorbis defines L, R, C macros that conflict with Lua */
#undef L
#undef R
#undef C

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* Global engine instance */
static ma_engine g_engine;
static int g_engine_initialized = 0;

/* Sound userdata */
typedef struct {
    ma_sound sound;
    int initialized;
    char* filepath; /* Keep track of loaded file */
} ma_sound_ud;

#define SOUND_MT "miniaudio.sound"

/* ============================================================
 * Engine functions
 * ============================================================ */

/* ma.engine_init() -> bool, error_string */
static int l_engine_init(lua_State *L) {
    if (g_engine_initialized) {
        lua_pushboolean(L, 1);
        return 1;
    }

    ma_engine_config config = ma_engine_config_init();
    ma_result result = ma_engine_init(&config, &g_engine);

    if (result != MA_SUCCESS) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "Failed to initialize audio engine: %d", result);
        return 2;
    }

    g_engine_initialized = 1;
    lua_pushboolean(L, 1);
    return 1;
}

/* ma.engine_uninit() */
static int l_engine_uninit(lua_State *L) {
    if (g_engine_initialized) {
        ma_engine_uninit(&g_engine);
        g_engine_initialized = 0;
    }
    return 0;
}

/* ma.engine_is_initialized() -> bool */
static int l_engine_is_initialized(lua_State *L) {
    lua_pushboolean(L, g_engine_initialized);
    return 1;
}

/* ma.engine_get_time() -> number (milliseconds) */
static int l_engine_get_time(lua_State *L) {
    if (!g_engine_initialized) {
        lua_pushnumber(L, 0);
        return 1;
    }
    ma_uint64 time_in_pcm_frames = ma_engine_get_time_in_pcm_frames(&g_engine);
    ma_uint32 sample_rate = ma_engine_get_sample_rate(&g_engine);
    double time_ms = (double)time_in_pcm_frames / sample_rate * 1000.0;
    lua_pushnumber(L, time_ms);
    return 1;
}

/* ma.engine_set_volume(volume) */
static int l_engine_set_volume(lua_State *L) {
    float volume = (float)luaL_checknumber(L, 1);
    if (g_engine_initialized) {
        ma_engine_set_volume(&g_engine, volume);
    }
    return 0;
}

/* ============================================================
 * Sound functions
 * ============================================================ */

/* ma.sound_new(filepath) -> sound userdata */
static int l_sound_new(lua_State *L) {
    const char *filepath = luaL_checkstring(L, 1);

    if (!g_engine_initialized) {
        return luaL_error(L, "Audio engine not initialized");
    }

    ma_sound_ud *ud = (ma_sound_ud *)lua_newuserdata(L, sizeof(ma_sound_ud));
    memset(ud, 0, sizeof(ma_sound_ud));

    /* Set metatable */
    luaL_getmetatable(L, SOUND_MT);
    lua_setmetatable(L, -2);

    /* Initialize sound from file */
    ma_result result = ma_sound_init_from_file(&g_engine, filepath, 0, NULL, NULL, &ud->sound);
    if (result != MA_SUCCESS) {
        return luaL_error(L, "Failed to load sound: %s (error %d)", filepath, result);
    }

    ud->initialized = 1;
    ud->filepath = strdup(filepath);

    return 1;
}

/* sound:start() */
static int l_sound_start(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        ma_sound_start(&ud->sound);
    }
    return 0;
}

/* sound:stop() */
static int l_sound_stop(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        ma_sound_stop(&ud->sound);
    }
    return 0;
}

/* sound:is_playing() -> bool */
static int l_sound_is_playing(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        lua_pushboolean(L, ma_sound_is_playing(&ud->sound));
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* sound:set_volume(volume) */
static int l_sound_set_volume(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    float volume = (float)luaL_checknumber(L, 2);
    if (ud->initialized) {
        ma_sound_set_volume(&ud->sound, volume);
    }
    return 0;
}

/* sound:seek_to_pcm_frame(frame) */
static int l_sound_seek_to_pcm_frame(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    ma_uint64 frame = (ma_uint64)luaL_checkinteger(L, 2);
    if (ud->initialized) {
        ma_sound_seek_to_pcm_frame(&ud->sound, frame);
    }
    return 0;
}

/* sound:get_cursor_in_pcm_frames() -> integer */
static int l_sound_get_cursor_in_pcm_frames(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        ma_uint64 cursor;
        ma_sound_get_cursor_in_pcm_frames(&ud->sound, &cursor);
        lua_pushinteger(L, (lua_Integer)cursor);
    } else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/* sound:get_length_in_pcm_frames() -> integer */
static int l_sound_get_length_in_pcm_frames(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        ma_uint64 length;
        ma_sound_get_length_in_pcm_frames(&ud->sound, &length);
        lua_pushinteger(L, (lua_Integer)length);
    } else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/* sound:set_looping(looping) */
static int l_sound_set_looping(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    int looping = lua_toboolean(L, 2);
    if (ud->initialized) {
        ma_sound_set_looping(&ud->sound, looping);
    }
    return 0;
}

/* sound:is_looping() -> bool */
static int l_sound_is_looping(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        lua_pushboolean(L, ma_sound_is_looping(&ud->sound));
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* sound:at_end() -> bool */
static int l_sound_at_end(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        lua_pushboolean(L, ma_sound_at_end(&ud->sound));
    } else {
        lua_pushboolean(L, 1);
    }
    return 1;
}

/* sound:set_start_time_in_milliseconds(ms)
 * Schedule when this sound will start playing (relative to engine time) */
static int l_sound_set_start_time_in_milliseconds(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    double ms = luaL_checknumber(L, 2);
    if (ud->initialized && g_engine_initialized) {
        ma_uint32 sample_rate = ma_engine_get_sample_rate(&g_engine);
        ma_uint64 time_in_pcm_frames = (ma_uint64)(ms / 1000.0 * sample_rate);
        ma_sound_set_start_time_in_pcm_frames(&ud->sound, time_in_pcm_frames);
    }
    return 0;
}

/* sound:__gc() */
static int l_sound_gc(lua_State *L) {
    ma_sound_ud *ud = (ma_sound_ud *)luaL_checkudata(L, 1, SOUND_MT);
    if (ud->initialized) {
        ma_sound_uninit(&ud->sound);
        ud->initialized = 0;
    }
    if (ud->filepath) {
        free(ud->filepath);
        ud->filepath = NULL;
    }
    return 0;
}

/* ============================================================
 * Module registration
 * ============================================================ */

static const luaL_Reg ma_funcs[] = {
    {"engine_init", l_engine_init},
    {"engine_uninit", l_engine_uninit},
    {"engine_is_initialized", l_engine_is_initialized},
    {"engine_get_time", l_engine_get_time},
    {"engine_set_volume", l_engine_set_volume},
    {"sound_new", l_sound_new},
    {NULL, NULL}
};

static const luaL_Reg sound_methods[] = {
    {"start", l_sound_start},
    {"stop", l_sound_stop},
    {"is_playing", l_sound_is_playing},
    {"set_volume", l_sound_set_volume},
    {"seek_to_pcm_frame", l_sound_seek_to_pcm_frame},
    {"get_cursor_in_pcm_frames", l_sound_get_cursor_in_pcm_frames},
    {"get_length_in_pcm_frames", l_sound_get_length_in_pcm_frames},
    {"set_looping", l_sound_set_looping},
    {"is_looping", l_sound_is_looping},
    {"at_end", l_sound_at_end},
    {"set_start_time_in_milliseconds", l_sound_set_start_time_in_milliseconds},
    {"__gc", l_sound_gc},
    {NULL, NULL}
};

int luaopen_miniaudio(lua_State *L) {
    /* Create sound metatable */
    luaL_newmetatable(L, SOUND_MT);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_setfuncs(L, sound_methods, 0);
    lua_pop(L, 1);

    /* Create module table */
    luaL_newlib(L, ma_funcs);
    return 1;
}

/* Cleanup function to be called on shutdown */
void miniaudio_shutdown(void) {
    if (g_engine_initialized) {
        ma_engine_uninit(&g_engine);
        g_engine_initialized = 0;
    }
}
