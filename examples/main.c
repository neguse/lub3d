/* mane3d example: runs a Lua script with sokol bindings */
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include "sokol_gl.h"
#include "sokol_debugtext.h"
#include "sokol_time.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>

/* declare luaopen functions from generated bindings */
extern int luaopen_sokol_gfx(lua_State *L);
extern int luaopen_sokol_app(lua_State *L);
extern int luaopen_sokol_glue(lua_State *L);
extern int luaopen_sokol_log(lua_State *L);
extern int luaopen_sokol_time(lua_State *L);
extern int luaopen_sokol_gl(lua_State *L);
extern int luaopen_sokol_debugtext(lua_State *L);

static lua_State *L = NULL;

static void call_lua(const char *func)
{
    lua_getglobal(L, func);
    if (lua_isfunction(L, -1))
    {
        if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        {
            slog_func("lua", 0, 0, lua_tostring(L, -1), 0, func, 0);
            lua_pop(L, 1);
        }
    }
    else
    {
        lua_pop(L, 1);
    }
}

static void init(void)
{
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    sgl_setup(&(sgl_desc_t){
        .logger.func = slog_func,
    });
    call_lua("init");
}

static void frame(void)
{
    call_lua("frame");
}

static void cleanup(void)
{
    call_lua("cleanup");
    sgl_shutdown();
    sg_shutdown();
    lua_close(L);
}

static void event(const sapp_event *ev)
{
    lua_getglobal(L, "event");
    if (lua_isfunction(L, -1))
    {
        /* Push event as userdata with generated binding */
        sapp_event *ud = (sapp_event *)lua_newuserdatauv(L, sizeof(sapp_event), 0);
        *ud = *ev;
        luaL_setmetatable(L, "sokol.Event");

        if (lua_pcall(L, 1, 0, 0) != LUA_OK)
        {
            fprintf(stderr, "Lua error in event: %s\n", lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }
    else
    {
        lua_pop(L, 1);
    }
}

sapp_desc sokol_main(int argc, char *argv[])
{
    L = luaL_newstate();
    luaL_openlibs(L);

    /* Register generated sokol modules */
    luaL_requiref(L, "sokol.gfx", luaopen_sokol_gfx, 0);
    lua_pop(L, 1);
    luaL_requiref(L, "sokol.app", luaopen_sokol_app, 0);
    lua_pop(L, 1);
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

    /* Load script */
    const char *script = (argc > 1) ? argv[1] : "main.lua";
    slog_func("lua", 1, 0, "Loading script", 0, script, 0);
    if (luaL_dofile(L, script) != LUA_OK)
    {
        slog_func("lua", 0, 0, lua_tostring(L, -1), 0, script, 0);
        lua_pop(L, 1);
    }

    return (sapp_desc){
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .window_title = "Måne3D",
        .logger.func = slog_func,
    };
}
