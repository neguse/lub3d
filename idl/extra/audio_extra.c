static int l_saudio_push(lua_State *L) {
    size_t len;
    const char* data = luaL_checklstring(L, 1, &len);
    int num_frames = (int)luaL_checkinteger(L, 2);
    int result = saudio_push((const float*)data, num_frames);
    lua_pushinteger(L, result);
    return 1;
}
