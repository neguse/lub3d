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
#include <stdlib.h>
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

/* declare luaopen functions from generated bindings */
extern int luaopen_sokol_gfx(lua_State *L);
extern int luaopen_sokol_app(lua_State *L);
extern int luaopen_sokol_glue(lua_State *L);
extern int luaopen_sokol_log(lua_State *L);
extern int luaopen_sokol_time(lua_State *L);
extern int luaopen_sokol_gl(lua_State *L);
extern int luaopen_sokol_debugtext(lua_State *L);
extern int luaopen_mane3d_licenses(lua_State *L);

#ifdef MANE3D_HAS_SHDC
extern int luaopen_shdc(lua_State *L);
extern void shdc_init(void);
extern void shdc_shutdown(void);
#endif

static lua_State *L = NULL;

#ifdef __EMSCRIPTEN__
/* Fetch file synchronously using XHR */
EM_JS(char *, js_fetch_file, (const char *url, int *out_len), {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", UTF8ToString(url), false);
    xhr.overrideMimeType("text/plain; charset=x-user-defined");
    try {
        xhr.send();
        if (xhr.status === 200) {
            var text = xhr.responseText;
            var len = text.length;
            var ptr = _malloc(len);
            for (var i = 0; i < len; i++) {
                HEAPU8[ptr + i] = text.charCodeAt(i) & 0xff;
            }
            HEAP32[out_len >> 2] = len;
            return ptr;
        }
    } catch (e) {
        console.error("Fetch error:", e);
    }
    HEAP32[out_len >> 2] = 0;
    return 0;
});

static char *fetch_file(const char *url, size_t *out_len)
{
    int len = 0;
    char *data = js_fetch_file(url, &len);
    *out_len = len;
    return data;
}

static int fetch_and_dostring(lua_State *L, const char *url)
{
    size_t len;
    char *data = fetch_file(url, &len);
    if (data)
    {
        int result = luaL_loadbuffer(L, data, len, url);
        free(data);
        if (result == LUA_OK)
        {
            result = lua_pcall(L, 0, LUA_MULTRET, 0);
        }
        return result;
    }
    lua_pushfstring(L, "fetch failed: %s", url);
    return LUA_ERRFILE;
}

/* Custom require searcher that uses fetch */
static int fetch_searcher(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    char url[256];
    snprintf(url, sizeof(url), "%s.lua", name);

    size_t len;
    char *data = fetch_file(url, &len);
    if (data)
    {
        if (luaL_loadbuffer(L, data, len, url) == LUA_OK)
        {
            free(data);
            lua_pushstring(L, url);
            return 2;
        }
        free(data);
        lua_pushfstring(L, "error loading '%s'", url);
        return 1;
    }
    lua_pushfstring(L, "cannot fetch '%s'", url);
    return 1;
}

static void setup_fetch_searcher(lua_State *L)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "searchers");
    /* Insert at position 2 (after preload) */
    int len = luaL_len(L, -1);
    for (int i = len; i >= 2; i--)
    {
        lua_rawgeti(L, -1, i);
        lua_rawseti(L, -2, i + 1);
    }
    lua_pushcfunction(L, fetch_searcher);
    lua_rawseti(L, -2, 2);
    lua_pop(L, 2);
}
#endif

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
#ifdef MANE3D_HAS_SHDC
    shdc_shutdown();
#endif
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

#ifdef __EMSCRIPTEN__
    setup_fetch_searcher(L);
#endif

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
    luaL_requiref(L, "mane3d.licenses", luaopen_mane3d_licenses, 0);
    lua_pop(L, 1);

#ifdef MANE3D_HAS_SHDC
    shdc_init();
    luaL_requiref(L, "shdc", luaopen_shdc, 0);
    lua_pop(L, 1);
#endif

    /* Load script */
    const char *script = (argc > 1) ? argv[1] : "main.lua";
    slog_func("lua", 1, 0, "Loading script", 0, script, 0);
#ifdef __EMSCRIPTEN__
    if (fetch_and_dostring(L, script) != LUA_OK)
#else
    if (luaL_dofile(L, script) != LUA_OK)
#endif
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
