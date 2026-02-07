/*
 * lub3d_lua.h - Shared Lua module registration
 *
 * Provides common functions for registering sokol and lub3d Lua modules.
 * Used by both the main example and the test runner.
 */
#ifndef LUB3D_LUA_H
#define LUB3D_LUA_H

#include <lua.h>

/* Register all sokol and lub3d Lua modules */
void lub3d_lua_register_all(lua_State *L);

/* Setup package.path with script directory */
void lub3d_lua_setup_path(lua_State *L, const char *script_dir);

#endif /* LUB3D_LUA_H */
