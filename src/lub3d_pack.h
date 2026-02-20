/*
 * lub3d_pack.h - Embedded pack data lookup and preload registration
 *
 * Generated pack data (gen/pack.c) contains lib/*.lua, examples, and assets.
 * This header provides:
 *   lub3d_pack_find()             - look up embedded data by path
 *   lub3d_pack_register_preload() - register all .lua entries in package.preload
 */
#ifndef LUB3D_PACK_H
#define LUB3D_PACK_H

#include <lua.h>
#include <lauxlib.h>
#include <string.h>

/* lub3d_pack_entry_t is defined in gen/pack.c (also typedef'd there).
 * Redeclare the struct here so the header is self-contained. */
typedef struct {
    const char *path;
    const unsigned char *data;
    unsigned int size;
} lub3d_pack_entry_t;

extern const lub3d_pack_entry_t lub3d_pack_entries[];
extern const int lub3d_pack_count;

/* Look up a path in pack data. Returns data pointer and sets *out_size,
 * or NULL if not found. */
static inline const unsigned char *lub3d_pack_find(const char *path, unsigned int *out_size)
{
    for (int i = 0; i < lub3d_pack_count; i++) {
        if (strcmp(lub3d_pack_entries[i].path, path) == 0) {
            *out_size = lub3d_pack_entries[i].size;
            return lub3d_pack_entries[i].data;
        }
    }
    *out_size = 0;
    return NULL;
}

/* Preload loader: called by require(), loads from pack data.
 * Upvalue 1 = data (lightuserdata), upvalue 2 = size (integer),
 * upvalue 3 = chunkname (string). */
static int lub3d_pack_loader(lua_State *L)
{
    const char *data = (const char *)lua_touserdata(L, lua_upvalueindex(1));
    int size = (int)lua_tointeger(L, lua_upvalueindex(2));
    const char *chunkname = lua_tostring(L, lua_upvalueindex(3));
    if (luaL_loadbuffer(L, data, (size_t)size, chunkname) != LUA_OK) {
        return lua_error(L);
    }
    lua_call(L, 0, 1);
    return 1;
}

/* Convert a file path like "lib/boot.lua" or "deps/lume/lume.lua"
 * to a Lua module name like "lib.boot" or "deps.lume.lume".
 * Strips the .lua suffix and replaces / with . */
static void lub3d_pack_path_to_modname(const char *path, char *out, size_t out_size)
{
    size_t len = strlen(path);
    /* Strip .lua suffix */
    size_t copy_len = len;
    if (len > 4 && strcmp(path + len - 4, ".lua") == 0) {
        copy_len = len - 4;
    }
    if (copy_len >= out_size) copy_len = out_size - 1;
    for (size_t i = 0; i < copy_len; i++) {
        out[i] = (path[i] == '/') ? '.' : path[i];
    }
    out[copy_len] = '\0';
}

/* Register all .lua pack entries as package.preload loaders.
 * After this, require("lib.boot") etc. will load from embedded data. */
static inline void lub3d_pack_register_preload(lua_State *L)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");  /* package.preload */
    for (int i = 0; i < lub3d_pack_count; i++) {
        const char *path = lub3d_pack_entries[i].path;
        size_t plen = strlen(path);
        /* Only register .lua files */
        if (plen < 5 || strcmp(path + plen - 4, ".lua") != 0) continue;

        char modname[256];
        lub3d_pack_path_to_modname(path, modname, sizeof(modname));

        /* Push closure with (data, size, chunkname) */
        lua_pushlightuserdata(L, (void *)lub3d_pack_entries[i].data);
        lua_pushinteger(L, (lua_Integer)lub3d_pack_entries[i].size);
        lua_pushstring(L, path);
        lua_pushcclosure(L, lub3d_pack_loader, 3);

        lua_setfield(L, -2, modname);  /* package.preload[modname] = loader */
    }
    lua_pop(L, 2);  /* pop preload, package */
}

#endif /* LUB3D_PACK_H */
