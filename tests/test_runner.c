/*
 * lub3d headless test runner
 *
 * Usage: lub3d-test <script.lua> [num_frames]
 *
 * Runs a Lua script for the specified number of frames (default: 10)
 * without creating a window or using real graphics APIs.
 * The script's app.Run() drives the init/frame/cleanup lifecycle.
 *
 * Exit codes:
 *   0 - Success
 *   1 - Lua error
 *   2 - Script file not found
 *   3 - Usage error
 *   4 - Native crash (access violation, etc.)
 */
#include "lub3d_lua.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <signal.h>

#ifdef _WIN32
#include <windows.h>
#endif

/* sokol logger — all test runner output goes through this */
extern void slog_func(const char* tag, unsigned int log_level, unsigned int log_item,
                       const char* message, unsigned int line_nr,
                       const char* filename, void* user_data);

/* Log levels matching sokol conventions */
#define LOG_PANIC   0
#define LOG_ERROR   1
#define LOG_WARNING 2
#define LOG_INFO    3

static void test_log(unsigned int level, const char* fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    slog_func("test", level, 0, buf, 0, NULL, NULL);
}

#ifdef LUB3D_HAS_SHDC
extern void shdc_init(void);
extern void shdc_shutdown(void);
#endif

static void extract_dir(const char *path, char *dir, size_t dir_size)
{
    strncpy(dir, path, dir_size - 1);
    dir[dir_size - 1] = '\0';
    char *last_sep = NULL;
    for (char *p = dir; *p; p++)
    {
        if (*p == '/' || *p == '\\')
            last_sep = p;
    }
    if (last_sep)
        *last_sep = '\0';
    else
        strcpy(dir, ".");
}

/* Lua panic handler: last resort before abort */
static int panic_handler(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    test_log(LOG_PANIC, "[PANIC] %s", msg ? msg : "(no message)");
    return 0; /* will call abort() */
}

/* Lua message handler: adds traceback on error */
static int msghandler(lua_State *L)
{
    const char *msg = lua_tostring(L, 1);
    if (msg)
        luaL_traceback(L, L, msg, 1);
    else
        lua_pushliteral(L, "(non-string error)");
    return 1;
}

/* Run a Lua script with traceback error handler */
static int run_script(lua_State *L, const char *script)
{
    lua_pushcfunction(L, msghandler);
    int msgh = lua_gettop(L);

    int status = luaL_loadfile(L, script);
    if (status != LUA_OK)
    {
        test_log(LOG_ERROR, "%s", lua_tostring(L, -1));
        return 1;
    }

    status = lua_pcall(L, 0, 0, msgh);
    if (status != LUA_OK)
    {
        test_log(LOG_ERROR, "%s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    lua_remove(L, msgh);
    return (status != LUA_OK) ? 1 : 0;
}

static int run_test(int argc, char *argv[])
{
    if (argc < 2)
    {
        fprintf(stderr, "Usage: %s <script.lua> [num_frames]\n", argv[0]);
        return 3;
    }

    const char *script = argv[1];
    int num_frames = (argc > 2) ? atoi(argv[2]) : 10;

    test_log(LOG_INFO, "[TEST] Running %s for %d frames", script, num_frames);

    /* Check file exists */
    FILE *f = fopen(script, "r");
    if (!f)
    {
        test_log(LOG_ERROR, "Script not found: %s", script);
        return 2;
    }
    fclose(f);

    /* Setup Lua */
    lua_State *L = luaL_newstate();
    lua_atpanic(L, panic_handler);
    luaL_openlibs(L);

    char script_dir[512];
    extract_dir(script, script_dir, sizeof(script_dir));
    lub3d_lua_setup_path(L, script_dir);
    lub3d_lua_register_all(L);

    /* Set _headless_frames global before running script */
    lua_pushinteger(L, num_frames);
    lua_setglobal(L, "_headless_frames");

#ifdef LUB3D_HAS_SHDC
    shdc_init();
#endif

    /* Run script with traceback handler */
    int result = run_script(L, script);

#ifdef LUB3D_HAS_SHDC
    shdc_shutdown();
#endif
    lua_close(L);

    if (result == 0)
        test_log(LOG_INFO, "[PASS] %s", script);
    return result;
}

int main(int argc, char *argv[])
{
#ifdef _WIN32
    /* Suppress abort() dialog and Watson crash dialog */
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
#endif
    signal(SIGABRT, SIG_DFL);

#if defined(_WIN32) && defined(_MSC_VER)
    /* SEH: catch native crashes (access violation, etc.) */
    __try
    {
        return run_test(argc, argv);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        DWORD code = GetExceptionCode();
        char msg[256];
        if (code == EXCEPTION_ACCESS_VIOLATION)
            snprintf(msg, sizeof(msg), "Native exception 0x%08lX (access violation)", code);
        else if (code == EXCEPTION_BREAKPOINT)
            snprintf(msg, sizeof(msg), "Native exception 0x%08lX (breakpoint/assert)", code);
        else
            snprintf(msg, sizeof(msg), "Native exception 0x%08lX", code);
        slog_func("crash", LOG_PANIC, 0, msg, 0, NULL, NULL);
        return 4;
    }
#else
    return run_test(argc, argv);
#endif
}
