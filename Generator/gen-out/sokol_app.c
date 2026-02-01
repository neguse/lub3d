/* machine generated, do not edit */
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <string.h>

#include "sokol_log.h"
#include "sokol_app.h"

#ifndef MANE3D_API
  #ifdef _WIN32
    #ifdef MANE3D_EXPORTS
      #define MANE3D_API __declspec(dllexport)
    #else
      #define MANE3D_API __declspec(dllimport)
    #endif
  #else
    #define MANE3D_API
  #endif
#endif
static lua_State* g_sapp_desc_L = NULL;
static int g_sapp_desc_table_ref = LUA_NOREF;
static void trampoline_sapp_desc_init_cb(void) {
    if (g_sapp_desc_table_ref == LUA_NOREF) return;
    lua_State* L = g_sapp_desc_L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_sapp_desc_table_ref);
    lua_getfield(L, -1, "init_cb");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) { slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "init_cb", 0); lua_pop(L, 1); }
}
static void trampoline_sapp_desc_frame_cb(void) {
    if (g_sapp_desc_table_ref == LUA_NOREF) return;
    lua_State* L = g_sapp_desc_L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_sapp_desc_table_ref);
    lua_getfield(L, -1, "frame_cb");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) { slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "frame_cb", 0); lua_pop(L, 1); }
}
static void trampoline_sapp_desc_cleanup_cb(void) {
    if (g_sapp_desc_table_ref == LUA_NOREF) return;
    lua_State* L = g_sapp_desc_L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_sapp_desc_table_ref);
    lua_getfield(L, -1, "cleanup_cb");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) { slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "cleanup_cb", 0); lua_pop(L, 1); }
}
static void trampoline_sapp_desc_event_cb(const sapp_event* arg0) {
    if (g_sapp_desc_table_ref == LUA_NOREF) return;
    lua_State* L = g_sapp_desc_L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_sapp_desc_table_ref);
    lua_getfield(L, -1, "event_cb");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
    sapp_event* ud_cb_0 = (sapp_event*)lua_newuserdatauv(L, sizeof(sapp_event), 0); *ud_cb_0 = *arg0; luaL_setmetatable(L, "sokol.Event");
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) { slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "event_cb", 0); lua_pop(L, 1); }
}
static int l_sapp_desc_new(lua_State *L) {
    sapp_desc* ud = (sapp_desc*)lua_newuserdatauv(L, sizeof(sapp_desc), 0);
    memset(ud, 0, sizeof(sapp_desc));
    luaL_setmetatable(L, "sokol.Desc");
    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "init_cb");
        if (lua_isfunction(L, -1)) {
            if (g_sapp_desc_table_ref == LUA_NOREF) {
                lua_pushvalue(L, 1);
                g_sapp_desc_table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                g_sapp_desc_L = L;
            }
            ud->init_cb = trampoline_sapp_desc_init_cb;
        }
        lua_pop(L, 1);
        lua_getfield(L, 1, "frame_cb");
        if (lua_isfunction(L, -1)) {
            if (g_sapp_desc_table_ref == LUA_NOREF) {
                lua_pushvalue(L, 1);
                g_sapp_desc_table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                g_sapp_desc_L = L;
            }
            ud->frame_cb = trampoline_sapp_desc_frame_cb;
        }
        lua_pop(L, 1);
        lua_getfield(L, 1, "cleanup_cb");
        if (lua_isfunction(L, -1)) {
            if (g_sapp_desc_table_ref == LUA_NOREF) {
                lua_pushvalue(L, 1);
                g_sapp_desc_table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                g_sapp_desc_L = L;
            }
            ud->cleanup_cb = trampoline_sapp_desc_cleanup_cb;
        }
        lua_pop(L, 1);
        lua_getfield(L, 1, "event_cb");
        if (lua_isfunction(L, -1)) {
            if (g_sapp_desc_table_ref == LUA_NOREF) {
                lua_pushvalue(L, 1);
                g_sapp_desc_table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                g_sapp_desc_L = L;
            }
            ud->event_cb = trampoline_sapp_desc_event_cb;
        }
        lua_pop(L, 1);
        lua_getfield(L, 1, "width");
        if (!lua_isnil(L, -1)) ud->width = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "height");
        if (!lua_isnil(L, -1)) ud->height = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "window_title");
        if (!lua_isnil(L, -1)) ud->window_title = lua_tostring(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "high_dpi");
        if (!lua_isnil(L, -1)) ud->high_dpi = lua_toboolean(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "fullscreen");
        if (!lua_isnil(L, -1)) ud->fullscreen = lua_toboolean(L, -1);
        lua_pop(L, 1);
    }
    return 1;
}
static int l_sapp_event_new(lua_State *L) {
    sapp_event* ud = (sapp_event*)lua_newuserdatauv(L, sizeof(sapp_event), 0);
    memset(ud, 0, sizeof(sapp_event));
    luaL_setmetatable(L, "sokol.Desc");
    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "frame_count");
        if (!lua_isnil(L, -1)) ud->frame_count = (uint64_t)lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "type");
        lua_pop(L, 1);
        lua_getfield(L, 1, "mouse_x");
        if (!lua_isnil(L, -1)) ud->mouse_x = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 1, "mouse_y");
        if (!lua_isnil(L, -1)) ud->mouse_y = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return 1;
}
static int l_sapp_run(lua_State *L) {
    #ifdef SOKOL_DUMMY_BACKEND
    (void)L;
    return 0;
    #else
    const sapp_desc* desc = (const sapp_desc*)luaL_checkudata(L, 1, "sokol.Desc");
    sapp_run(desc);
    return 0;
    #endif
}
static int l_sapp_width(lua_State *L) {

    lua_pushinteger(L, sapp_width());
    return 1;
}
static int l_sapp_height(lua_State *L) {

    lua_pushinteger(L, sapp_height());
    return 1;
}
static void register_sapp_event_type(lua_State *L) {
    lua_newtable(L);
        lua_pushinteger(L, 0); lua_setfield(L, -2, "INVALID");
        lua_pushinteger(L, 1); lua_setfield(L, -2, "KEY_DOWN");
        lua_pushinteger(L, 2); lua_setfield(L, -2, "KEY_UP");
        lua_pushinteger(L, 3); lua_setfield(L, -2, "MOUSE_DOWN");
        lua_pushinteger(L, 4); lua_setfield(L, -2, "QUIT_REQUESTED");
    lua_setfield(L, -2, "EventType");
}
static void register_metatables(lua_State *L) {
    luaL_newmetatable(L, "sokol.Desc"); lua_pop(L, 1);
}
static const luaL_Reg app_funcs[] = {
    {"Desc", l_sapp_desc_new},
    {"Event", l_sapp_event_new},
    {"Run", l_sapp_run},
    {"Width", l_sapp_width},
    {"Height", l_sapp_height},
    {NULL, NULL}
};
MANE3D_API int luaopen_sokol_app(lua_State *L) {
    register_metatables(L);
    luaL_newlib(L, app_funcs);
    return 1;
}