/* Lua bindings for stb_image */
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include <lua.h>
#include <lauxlib.h>

/* Load image from file
 * Returns: width, height, channels, data (as string)
 * Or nil, error_message on failure
 */
static int l_load(lua_State *L) {
    const char *filename = luaL_checkstring(L, 1);
    int desired_channels = (int)luaL_optinteger(L, 2, 4); /* default RGBA */

    int width, height, channels;
    unsigned char *data = stbi_load(filename, &width, &height, &channels, desired_channels);

    if (!data) {
        lua_pushnil(L);
        lua_pushstring(L, stbi_failure_reason());
        return 2;
    }

    lua_pushinteger(L, width);
    lua_pushinteger(L, height);
    lua_pushinteger(L, desired_channels);
    lua_pushlstring(L, (const char *)data, width * height * desired_channels);

    stbi_image_free(data);

    return 4;
}

/* Load image from memory (string)
 * Returns: width, height, channels, data (as string)
 * Or nil, error_message on failure
 */
static int l_load_from_memory(lua_State *L) {
    size_t len;
    const char *buffer = luaL_checklstring(L, 1, &len);
    int desired_channels = (int)luaL_optinteger(L, 2, 4);

    int width, height, channels;
    unsigned char *data = stbi_load_from_memory(
        (const unsigned char *)buffer, (int)len,
        &width, &height, &channels, desired_channels
    );

    if (!data) {
        lua_pushnil(L);
        lua_pushstring(L, stbi_failure_reason());
        return 2;
    }

    lua_pushinteger(L, width);
    lua_pushinteger(L, height);
    lua_pushinteger(L, desired_channels);
    lua_pushlstring(L, (const char *)data, width * height * desired_channels);

    stbi_image_free(data);

    return 4;
}

static const luaL_Reg stb_image_funcs[] = {
    {"load", l_load},
    {"load_from_memory", l_load_from_memory},
    {NULL, NULL}
};

int luaopen_stb_image(lua_State *L) {
    luaL_newlib(L, stb_image_funcs);
    return 1;
}
