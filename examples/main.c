/* lub3d example: runs a Lua script with sokol bindings
 * Lua controls entry point - scripts call app.run() directly
 */
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include "sokol_gl.h"
#include "sokol_debugtext.h"
#include "sokol_time.h"
#include "sokol_audio.h"
#include "sokol_shape.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>

/* Get script path from URL query parameter (?script=path/to/script.lua) */
EM_JS(void, js_get_script_param, (char *out, int max_len), {
    var params = new URLSearchParams(window.location.search);
    var script = params.get("script") || "main.lua";
    stringToUTF8(script, out, max_len);
});
/* Check if running in playground mode */
EM_JS(int, js_is_playground_mode, (void), {
    return typeof window.getEditorCode === 'function' ? 1 : 0;
});

/* Get editor code via callback (for playground mode) */
EM_JS(char *, js_get_editor_code, (int *out_len), {
    if (typeof window.getEditorCode === 'function') {
        var code = window.getEditorCode();
        if (code) {
            var len = lengthBytesUTF8(code) + 1;
            var ptr = _malloc(len);
            stringToUTF8(code, ptr, len);
            HEAP32[out_len >> 2] = len - 1;
            return ptr;
        }
    }
    HEAP32[out_len >> 2] = 0;
    return 0;
});

/* Notify JS that WASM is ready */
EM_JS(void, js_notify_ready, (void), {
    if (typeof window.onWasmReady === 'function') {
        window.onWasmReady();
    }
});

/* Get canvas resolution from JS globals */
EM_JS(int, js_get_canvas_width, (void), {
    return window._canvasWidth || 480;
});
EM_JS(int, js_get_canvas_height, (void), {
    return window._canvasHeight || 360;
});
/* Get display scale for CSS transform scaling */
EM_JS(double, js_get_display_scale_x, (void), {
    return window._displayScaleX || 1.0;
});
EM_JS(double, js_get_display_scale_y, (void), {
    return window._displayScaleY || 1.0;
});
#endif

/* Shared Lua module registration */
#include "lub3d_lua.h"

#ifdef LUB3D_HAS_SHDC
extern void shdc_init(void);
extern void shdc_shutdown(void);
#endif

static lua_State *L = NULL;
static char g_script_path[512] = {0};
static char g_script_dir[512] = {0};

/* Extract directory from path */
static void extract_dir(const char *path, char *dir, size_t dir_size)
{
    strncpy(dir, path, dir_size - 1);
    dir[dir_size - 1] = '\0';
    /* Find last separator */
    char *last_sep = NULL;
    for (char *p = dir; *p; p++)
    {
        if (*p == '/' || *p == '\\')
            last_sep = p;
    }
    if (last_sep)
    {
        *last_sep = '\0';
    }
    else
    {
        strcpy(dir, ".");
    }
}

static time_t get_file_mtime(const char *path)
{
    struct stat st;
    if (stat(path, &st) == 0)
    {
        return st.st_mtime;
    }
    return 0;
}

/* Lua binding for get_file_mtime */
static int l_get_mtime(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    time_t mtime = get_file_mtime(path);
    lua_pushinteger(L, (lua_Integer)mtime);
    return 1;
}

#ifdef __EMSCRIPTEN__
/* Fetch file synchronously using XHR */
EM_JS(char *, js_fetch_file, (const char *url, int *out_len), {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", UTF8ToString(url), false);
    xhr.overrideMimeType("text/plain; charset=x-user-defined");
    try
    {
        xhr.send();
        if (xhr.status === 200)
        {
            var text = xhr.responseText;
            var len = text.length;
            var ptr = _malloc(len);
            for (var i = 0; i < len; i++)
            {
                HEAPU8[ptr + i] = text.charCodeAt(i) & 0xff;
            }
            HEAP32[out_len >> 2] = len;
            return ptr;
        }
    }
    catch(e)
    {
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
/* Convert module name dots to path slashes */
static void name_to_path(const char *name, char *path, size_t path_size)
{
    size_t i = 0;
    for (; *name && i < path_size - 1; name++, i++)
    {
        path[i] = (*name == '.') ? '/' : *name;
    }
    path[i] = '\0';
}

static int fetch_searcher(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    char modpath[256];
    name_to_path(name, modpath, sizeof(modpath));
    char url[512];
    /* Try script directory first */
    snprintf(url, sizeof(url), "%s/%s.lua", g_script_dir, modpath);

    size_t len;
    char *data = fetch_file(url, &len);
    if (!data)
    {
        /* Try lib directory (sibling to script dir) */
        snprintf(url, sizeof(url), "%s/../lib/%s.lua", g_script_dir, modpath);
        data = fetch_file(url, &len);
    }
    if (!data)
    {
        /* Fallback to root */
        snprintf(url, sizeof(url), "%s.lua", modpath);
        data = fetch_file(url, &len);
    }
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

/* Lua wrapper for fetch_file */
static int l_fetch_file(lua_State *L)
{
    const char *url = luaL_checkstring(L, 1);
    size_t len;
    char *data = fetch_file(url, &len);
    if (data && len > 0)
    {
        lua_pushlstring(L, data, len);
        free(data);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

/* Lua wrapper for display scale (for CSS transform scaling) */
static int l_get_display_scale(lua_State *L)
{
    lua_pushnumber(L, js_get_display_scale_x());
    lua_pushnumber(L, js_get_display_scale_y());
    return 2;
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

static int lub3d_main(int argc, char *argv[])
{
    slog_func("main", 3, 0, "=== lub3d starting (Lua entry point) ===", 0, "", 0);
    L = luaL_newstate();
    luaL_openlibs(L);

#ifdef __EMSCRIPTEN__
    setup_fetch_searcher(L);

    /* Expose fetch_file to Lua for texture loading etc. */
    lua_pushcfunction(L, (lua_CFunction)l_fetch_file);
    lua_setglobal(L, "fetch_file");

    /* Expose display scale for CSS transform scaling */
    lua_pushcfunction(L, (lua_CFunction)l_get_display_scale);
    lua_setglobal(L, "get_display_scale");
#endif

#ifdef LUB3D_HAS_SHDC
    shdc_init();
#endif

    /* Register all sokol and lub3d modules */
    lub3d_lua_register_all(L);

    /* Load script */
#ifdef __EMSCRIPTEN__
    js_get_script_param(g_script_path, sizeof(g_script_path));
    const char *script = g_script_path;
#else
    const char *script = (argc > 1) ? argv[1] : "main.lua";
    strncpy(g_script_path, script, sizeof(g_script_path) - 1);
#endif
    extract_dir(script, g_script_dir, sizeof(g_script_dir));
    slog_func("lua", 3, 0, "Loading script", 0, script, 0);
    slog_func("lua", 3, 0, "Script directory", 0, g_script_dir, 0);

    /* Export get_mtime to Lua for hot reload */
    lua_pushcfunction(L, l_get_mtime);
    lua_setglobal(L, "get_mtime");

#ifndef __EMSCRIPTEN__
    /* Add script directory and project root to package.path */
    {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        const char *old_path = lua_tostring(L, -1);
        char new_path[2048];
        /* Add: script_dir/?.lua, script_dir/../?.lua (project root), old_path */
        snprintf(new_path, sizeof(new_path), "%s/?.lua;%s/../?.lua;%s",
                 g_script_dir, g_script_dir, old_path ? old_path : "");
        lua_pop(L, 1);
        lua_pushstring(L, new_path);
        lua_setfield(L, -2, "path");
        lua_pop(L, 1);
    }
#endif

    /* Execute Lua script - script calls app.run() to start the application */
#ifdef __EMSCRIPTEN__
    if (js_is_playground_mode())
    {
        int len = 0;
        char *code = js_get_editor_code(&len);
        if (code && len > 0)
        {
            if (luaL_loadbuffer(L, code, len, "editor") == LUA_OK)
            {
                if (lua_pcall(L, 0, LUA_MULTRET, 0) != LUA_OK)
                {
                    const char *err = lua_tostring(L, -1);
                    slog_func("lua", 0, 0, err ? err : "(no message)", 0, "editor", 0);
                    lua_pop(L, 1);
                }
            }
            else
            {
                const char *err = lua_tostring(L, -1);
                slog_func("lua", 0, 0, err ? err : "(no message)", 0, "editor", 0);
                lua_pop(L, 1);
            }
            free(code);
        }
        js_notify_ready();
    }
    else if (fetch_and_dostring(L, script) != LUA_OK)
    {
        const char *err = lua_tostring(L, -1);
        slog_func("lua", 0, 0, err ? err : "(no message)", 0, script, 0);
        lua_pop(L, 1);
    }
    /* Emscripten: sapp_run returns immediately, Lua state stays alive for callbacks */
#else
    if (luaL_dofile(L, script) != LUA_OK)
    {
        const char *err = lua_tostring(L, -1);
        fprintf(stderr, "Lua error: %s\n", err ? err : "(no message)");
        slog_func("lua", 0, 0, err ? err : "(no message)", 0, script, 0);
        lua_close(L);
        return 1;
    }
    /* Non-Emscripten: sapp_run blocks until app closes, then script returns here */
#ifdef LUB3D_HAS_SHDC
    shdc_shutdown();
#endif
    lua_close(L);
#endif

    return 0;
}

/* Platform-specific entry points */
#if defined(_WIN32)
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    (void)hInstance;
    (void)hPrevInstance;
    (void)nCmdShow;
    return lub3d_main(__argc, __argv);
}
#else
int main(int argc, char *argv[])
{
    return lub3d_main(argc, argv);
}
#endif
