static int l_stbi_load(lua_State *L) {
    const char *filename = luaL_checkstring(L, 1);
    int desired_channels = (int)luaL_optinteger(L, 2, 4);
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
    lua_pushlstring(L, (const char *)data, (size_t)width * height * desired_channels);
    stbi_image_free(data);
    return 4;
}

static int l_stbi_load_from_memory(lua_State *L) {
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
    lua_pushlstring(L, (const char *)data, (size_t)width * height * desired_channels);
    stbi_image_free(data);
    return 4;
}

static int l_stbi_info(lua_State *L) {
    const char *filename = luaL_checkstring(L, 1);
    int width, height, channels;
    int ok = stbi_info(filename, &width, &height, &channels);
    if (!ok) {
        lua_pushnil(L);
        lua_pushstring(L, stbi_failure_reason());
        return 2;
    }
    lua_pushinteger(L, width);
    lua_pushinteger(L, height);
    lua_pushinteger(L, channels);
    return 3;
}
