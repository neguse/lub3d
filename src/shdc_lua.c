// Lua bindings for sokol-shdc wrapper
#include <lua.h>
#include <lauxlib.h>
#include "shdc_wrapper.h"

// shdc.init()
static int l_shdc_init(lua_State* L) {
    shdc_init();
    return 0;
}

// shdc.shutdown()
static int l_shdc_shutdown(lua_State* L) {
    shdc_shutdown();
    return 0;
}

// shdc.compile(source, program_name, slang)
// Returns table with:
//   success: boolean
//   error: string or nil
//   vs_source: string
//   fs_source: string
//   vs_bytecode: string (binary) or nil
//   fs_bytecode: string (binary) or nil
static int l_shdc_compile(lua_State* L) {
    const char* source = luaL_checkstring(L, 1);
    const char* program_name = luaL_checkstring(L, 2);
    const char* slang = luaL_checkstring(L, 3);

    shdc_compile_result_t result = shdc_compile(source, program_name, slang);

    lua_newtable(L);

    lua_pushboolean(L, result.success);
    lua_setfield(L, -2, "success");

    if (result.error_msg && result.error_msg[0]) {
        lua_pushstring(L, result.error_msg);
        lua_setfield(L, -2, "error");
    }

    if (result.vs_source && result.vs_source_len > 0) {
        lua_pushlstring(L, result.vs_source, result.vs_source_len);
        lua_setfield(L, -2, "vs_source");
    }

    if (result.fs_source && result.fs_source_len > 0) {
        lua_pushlstring(L, result.fs_source, result.fs_source_len);
        lua_setfield(L, -2, "fs_source");
    }

    if (result.vs_bytecode && result.vs_bytecode_len > 0) {
        lua_pushlstring(L, result.vs_bytecode, result.vs_bytecode_len);
        lua_setfield(L, -2, "vs_bytecode");
    }

    if (result.fs_bytecode && result.fs_bytecode_len > 0) {
        lua_pushlstring(L, result.fs_bytecode, result.fs_bytecode_len);
        lua_setfield(L, -2, "fs_bytecode");
    }

    shdc_free_result(&result);

    return 1;
}

static const luaL_Reg shdc_funcs[] = {
    {"init", l_shdc_init},
    {"shutdown", l_shdc_shutdown},
    {"compile", l_shdc_compile},
    {NULL, NULL}
};

int luaopen_shdc(lua_State* L) {
    luaL_newlib(L, shdc_funcs);
    return 1;
}
