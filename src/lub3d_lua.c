/*
 * lub3d_lua.c - Shared Lua module registration
 */
#include "lub3d_lua.h"
#include <lauxlib.h>
#include <stdio.h>

/* Declare luaopen functions from generated bindings */
extern int luaopen_sokol_gfx(lua_State *L);
extern int luaopen_sokol_app(lua_State *L);
extern int luaopen_sokol_glue(lua_State *L);
extern int luaopen_sokol_log(lua_State *L);
extern int luaopen_sokol_time(lua_State *L);
extern int luaopen_sokol_gl(lua_State *L);
extern int luaopen_sokol_debugtext(lua_State *L);
extern int luaopen_sokol_audio(lua_State *L);
extern int luaopen_sokol_shape(lua_State *L);
extern int luaopen_lub3d_licenses(lua_State *L);
extern int luaopen_stb_image(lua_State *L);
extern int luaopen_miniaudio(lua_State *L);
extern int luaopen_lub3d_fs(lua_State *L);
extern int luaopen_mane3d_encoding(lua_State *L);
extern int luaopen_lib_glm(lua_State *L);

#ifdef LUB3D_HAS_SHDC
extern int luaopen_shdc(lua_State *L);
#endif

#ifdef LUB3D_HAS_IMGUI
extern int luaopen_sokol_imgui(lua_State *L);
extern int luaopen_imgui(lua_State *L);
#else
/* Dummy imgui module for headless testing */
static int l_imgui_dummy_func(lua_State *L) { (void)L; return 0; }
static int l_imgui_dummy_index(lua_State *L) {
    (void)L;
    lua_pushcfunction(L, l_imgui_dummy_func);
    return 1;
}
static int luaopen_imgui_dummy(lua_State *L)
{
    lua_newtable(L);
    /* Return a table with __index that returns a no-op function */
    luaL_newmetatable(L, "imgui.dummy_mt");
    lua_pushcfunction(L, l_imgui_dummy_index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
    return 1;
}
#endif

#ifdef LUB3D_HAS_BC7ENC
extern int luaopen_bc7enc(lua_State *L);
#endif

#ifdef LUB3D_HAS_BOX2D
extern int luaopen_b2d(lua_State *L);
#endif

#ifdef LUB3D_HAS_JOLT
extern int luaopen_jolt(lua_State *L);
#endif

/* Write float array to lightuserdata buffer (for audio stream_cb) */
static int l_write_floats(lua_State *L)
{
    float* buffer = (float*)lua_touserdata(L, 1);
    if (!buffer) return luaL_error(L, "buffer is nil");

    luaL_checktype(L, 2, LUA_TTABLE);
    int len = (int)luaL_len(L, 2);

    for (int i = 0; i < len; i++) {
        lua_rawgeti(L, 2, i + 1);
        buffer[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return 0;
}

void lub3d_lua_register_all(lua_State *L)
{
    luaL_requiref(L, "sokol.gfx", luaopen_sokol_gfx, 0);
    lua_pop(L, 1);
#ifdef SOKOL_DUMMY_BACKEND
    /* headless: use Lua-based headless_app as sokol.app */
    luaL_dostring(L, "package.preload['sokol.app'] = function() return require('lib.headless_app') end");
#else
    luaL_requiref(L, "sokol.app", luaopen_sokol_app, 0);
    lua_pop(L, 1);
#endif
    luaL_requiref(L, "sokol.glue", luaopen_sokol_glue, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.log", luaopen_sokol_log, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.time", luaopen_sokol_time, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.gl", luaopen_sokol_gl, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.debugtext", luaopen_sokol_debugtext, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.audio", luaopen_sokol_audio, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.shape", luaopen_sokol_shape, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "lub3d.licenses", luaopen_lub3d_licenses, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "stb.image", luaopen_stb_image, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "miniaudio", luaopen_miniaudio, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "lub3d.fs", luaopen_lub3d_fs, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "mane3d.encoding", luaopen_mane3d_encoding, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "lib.glm", luaopen_lib_glm, 0);
    lua_pop(L, 1);

    /* Export write_floats for audio stream_cb */
    lua_pushcfunction(L, l_write_floats);
    lua_setglobal(L, "write_floats");

#ifdef LUB3D_HAS_SHDC
    luaL_requiref(L, "shdc", luaopen_shdc, 0);
    lua_pop(L, 1);
#endif

#ifdef LUB3D_HAS_IMGUI
    luaL_requiref(L, "sokol.imgui", luaopen_sokol_imgui, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "imgui", luaopen_imgui, 0);
    lua_pop(L, 1);
#else
    luaL_requiref(L, "imgui", luaopen_imgui_dummy, 0);
    lua_pop(L, 1);
#endif

#ifdef LUB3D_HAS_BC7ENC
    luaL_requiref(L, "bc7enc", luaopen_bc7enc, 0);
    lua_pop(L, 1);
#endif

#ifdef LUB3D_HAS_BOX2D
    luaL_requiref(L, "b2d", luaopen_b2d, 0);
    lua_pop(L, 1);
#endif

#ifdef LUB3D_HAS_JOLT
    luaL_requiref(L, "jolt", luaopen_jolt, 0);
    lua_pop(L, 1);
#endif
}

void lub3d_lua_setup_path(lua_State *L, const char *script_dir)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "path");
    const char *old_path = lua_tostring(L, -1);
    char new_path[2048];
    snprintf(new_path, sizeof(new_path), "%s/?.lua;%s/../lib/?.lua;%s",
             script_dir, script_dir, old_path ? old_path : "");
    lua_pop(L, 1);
    lua_pushstring(L, new_path);
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
}
