/*
 * lub3d_cli.c - CLI entry point for lub3d
 *
 * Subcommands:
 *   lub3d run [path]       Run a Lua project (default: current directory)
 *   lub3d doc [topic]      Show module/API documentation
 *   lub3d example [name]   List or run built-in examples
 *   lub3d                  Same as "lub3d run ."
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

#include "lub3d_lua.h"
#include "lub3d_fs.h"
#include "lub3d_pack.h"

#ifdef LUB3D_HAS_SHDC
extern void shdc_init(void);
extern void shdc_shutdown(void);
#endif

static lua_State *L = NULL;

/* Run boot.lua from pack data */
static int run_boot_from_pack(lua_State *L)
{
    unsigned int size;
    const unsigned char *data = lub3d_pack_find("lib/boot.lua", &size);
    if (!data) {
        fprintf(stderr, "error: lib/boot.lua not found in pack data\n");
        return -1;
    }
    if (luaL_loadbuffer(L, (const char *)data, size, "lib/boot.lua") != LUA_OK ||
        lua_pcall(L, 0, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        fprintf(stderr, "error: %s\n", err ? err : "(no message)");
        lua_pop(L, 1);
        return -1;
    }
    return 0;
}

/* ===== cmd_run ===== */

static int file_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0;
}

static int cmd_run(const char *path)
{
    /* Resolve script file */
    char script_file[1024] = {0};
    char user_dir[1024] = {0};
    struct stat st;

    if (!path) path = ".";

    if (stat(path, &st) == 0 && (st.st_mode & S_IFDIR)) {
        /* Directory: look for main.lua then init.lua */
        snprintf(script_file, sizeof(script_file), "%s/main.lua", path);
        if (!file_exists(script_file)) {
            snprintf(script_file, sizeof(script_file), "%s/init.lua", path);
            if (!file_exists(script_file)) {
                fprintf(stderr, "error: no main.lua or init.lua found in %s\n", path);
                return 1;
            }
        }
        snprintf(user_dir, sizeof(user_dir), "%s", path);
    } else {
        /* Assume it's a file path */
        snprintf(script_file, sizeof(script_file), "%s", path);
        if (!file_exists(script_file)) {
            fprintf(stderr, "error: %s not found\n", path);
            return 1;
        }
        /* Extract directory */
        strncpy(user_dir, path, sizeof(user_dir) - 1);
        char *last_sep = NULL;
        for (char *p = user_dir; *p; p++) {
            if (*p == '/' || *p == '\\') last_sep = p;
        }
        if (last_sep) *last_sep = '\0';
        else strcpy(user_dir, ".");
    }

    L = luaL_newstate();
    luaL_openlibs(L);

#ifdef LUB3D_HAS_SHDC
    shdc_init();
#endif

    lub3d_lua_register_all(L);
    lub3d_pack_register_preload(L);
    lub3d_lua_setup_path(L, user_dir);

    /* Set _lub3d_script_file global */
    lua_pushstring(L, script_file);
    lua_setglobal(L, "_lub3d_script_file");

    int result = run_boot_from_pack(L);

#ifndef __EMSCRIPTEN__
#ifdef LUB3D_HAS_SHDC
    shdc_shutdown();
#endif
    lua_close(L);
#endif
    return result != 0 ? 1 : 0;
}

/* ===== cmd_example ===== */

static int cmd_example(const char *name)
{
    if (!name) {
        /* List available examples */
        printf("Available examples:\n");
        for (int i = 0; i < lub3d_pack_count; i++) {
            const char *path = lub3d_pack_entries[i].path;
            /* Match examples/*.lua (top-level) */
            if (strncmp(path, "examples/", 9) == 0) {
                const char *rest = path + 9;
                const char *slash = strchr(rest, '/');
                /* Top-level .lua file: examples/foo.lua */
                if (!slash) {
                    size_t len = strlen(rest);
                    if (len > 4 && strcmp(rest + len - 4, ".lua") == 0) {
                        /* Print without .lua suffix */
                        printf("  %.*s\n", (int)(len - 4), rest);
                    }
                }
                /* Subdirectory with init.lua: examples/foo/init.lua */
                else if (strcmp(slash + 1, "init.lua") == 0) {
                    printf("  %.*s\n", (int)(slash - rest), rest);
                }
            }
        }
        return 0;
    }

    /* Run a specific example */
    L = luaL_newstate();
    luaL_openlibs(L);

#ifdef LUB3D_HAS_SHDC
    shdc_init();
#endif

    lub3d_lua_register_all(L);
    lub3d_pack_register_preload(L);

    /* Set _lub3d_script for boot.lua */
    char modname[256];
    snprintf(modname, sizeof(modname), "examples.%s", name);
    lua_pushstring(L, modname);
    lua_setglobal(L, "_lub3d_script");

    int result = run_boot_from_pack(L);

#ifndef __EMSCRIPTEN__
#ifdef LUB3D_HAS_SHDC
    shdc_shutdown();
#endif
    lua_close(L);
#endif
    return result != 0 ? 1 : 0;
}

/* ===== cmd_doc ===== */

static int cmd_doc(const char *topic)
{
    L = luaL_newstate();
    luaL_openlibs(L);

    lub3d_lua_register_all(L);
    lub3d_pack_register_preload(L);

    /* Set _lub3d_doc_topic global */
    if (topic) {
        lua_pushstring(L, topic);
    } else {
        lua_pushnil(L);
    }
    lua_setglobal(L, "_lub3d_doc_topic");

    /* Run lib/doc.lua from pack */
    unsigned int size;
    const unsigned char *data = lub3d_pack_find("lib/doc.lua", &size);
    if (!data) {
        fprintf(stderr, "error: lib/doc.lua not found in pack data\n");
        lua_close(L);
        return 1;
    }
    int result = 0;
    if (luaL_loadbuffer(L, (const char *)data, size, "lib/doc.lua") != LUA_OK ||
        lua_pcall(L, 0, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        fprintf(stderr, "error: %s\n", err ? err : "(no message)");
        result = 1;
    }

    lua_close(L);
    return result;
}

/* ===== Usage ===== */

static void print_usage(void)
{
    printf("Usage: lub3d <command> [args]\n");
    printf("\n");
    printf("Commands:\n");
    printf("  run [path]       Run a Lua project (default: current directory)\n");
    printf("  example [name]   List or run built-in examples\n");
    printf("  doc [topic]      Show module/API documentation\n");
    printf("  --help, -h       Show this help message\n");
    printf("\n");
    printf("Running without arguments is equivalent to 'lub3d run .'\n");
}

/* ===== main ===== */

int main(int argc, char *argv[])
{
    /* Enable pack data lookup for fs.read/fs.exists */
    lub3d_fs_pack_find = lub3d_pack_find;

    if (argc < 2) {
        /* Default: run current directory */
        return cmd_run(".");
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0) {
        print_usage();
        return 0;
    }

    if (strcmp(cmd, "run") == 0) {
        return cmd_run(argc > 2 ? argv[2] : ".");
    }

    if (strcmp(cmd, "example") == 0) {
        return cmd_example(argc > 2 ? argv[2] : NULL);
    }

    if (strcmp(cmd, "doc") == 0) {
        return cmd_doc(argc > 2 ? argv[2] : NULL);
    }

    /* Unknown command */
    fprintf(stderr, "Unknown command: %s\n\n", cmd);
    print_usage();
    return 1;
}
