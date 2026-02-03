#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include "sokol_log.h"

#ifdef _WIN32
#include <windows.h>
#endif

extern int luaopen_sokol_app(lua_State *L);

/* slog(message) - log via sokol_log */
static int l_slog(lua_State *L)
{
    const char *msg = luaL_checkstring(L, 1);
    slog_func("lua", 3, 0, msg, 0, "", 0);
    return 0;
}

static int run_main(int argc, char *argv[])
{
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    luaL_requiref(L, "sokol.app", luaopen_sokol_app, 0);
    lua_pop(L, 1);

    lua_pushcfunction(L, l_slog);
    lua_setglobal(L, "slog");

    const char *script = (argc > 1) ? argv[1] : "test_app.lua";
    if (luaL_dofile(L, script) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        slog_func("lua", 0, 0, err ? err : "(no message)", 0, script, 0);
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}

#if defined(_WIN32)
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    (void)hInstance;
    (void)hPrevInstance;
    (void)lpCmdLine;
    (void)nCmdShow;
    return run_main(__argc, __argv);
}
#else
int main(int argc, char *argv[])
{
    return run_main(argc, argv);
}
#endif
