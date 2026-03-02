static ma_sound** check_ma_sound_ptr(lua_State *L, int idx) {
    return (ma_sound**)luaL_checkudata(L, idx, "miniaudio.Sound");
}

static int l_ma_sound_new(lua_State *L) {
    ma_engine* engine = check_ma_engine(L, 1);
    const char* filePath = luaL_checkstring(L, 2);
    ma_uint32 flags = (ma_uint32)luaL_optinteger(L, 3, 0);
    ma_sound* p = (ma_sound*)malloc(sizeof(ma_sound));
    memset(p, 0, sizeof(ma_sound));
    ma_result result = ma_sound_init_from_file(engine, filePath, flags, NULL, NULL, p);
    if (result != MA_SUCCESS) {
        free(p);
        return luaL_error(L, "ma_sound_init_from_file failed: %d", result);
    }
    ma_sound** pp = (ma_sound**)lua_newuserdatauv(L, sizeof(ma_sound*), 1);
    *pp = p;
    luaL_setmetatable(L, "miniaudio.Sound");
    lua_pushvalue(L, 1);
    lua_setiuservalue(L, -2, 1);
    return 1;
}

/*
 * LuaVfsContext — Lua callback VFS for miniaudio
 *
 * Same pattern as sokol_app LuaCallbackContext:
 * - Lua table with onOpen/onRead/onSeek/onTell/onClose/onInfo callbacks
 * - C trampolines call Lua functions via registry ref
 * - File handles are Lua values stored as registry refs
 */
typedef struct {
    ma_vfs_callbacks cb;
    lua_State* L;
    int table_ref;  /* registry ref to callback table */
} LuaVfsContext;

static ma_result lua_vfs_onOpen(ma_vfs* pVFS, const char* pFilePath, ma_uint32 openMode, ma_vfs_file* pFile) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    (void)openMode;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onOpen");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_ERROR; }
    lua_pushstring(L, pFilePath);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
    if (lua_isnil(L, -1)) { lua_pop(L, 1); return MA_DOES_NOT_EXIST; }
    /* Store returned handle as registry ref */
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    *pFile = (ma_vfs_file)(intptr_t)ref;
    return MA_SUCCESS;
}

static ma_result lua_vfs_onOpenW(ma_vfs* pVFS, const wchar_t* pFilePath, ma_uint32 openMode, ma_vfs_file* pFile) {
    (void)pVFS; (void)pFilePath; (void)openMode; (void)pFile;
    return MA_NOT_IMPLEMENTED;
}

static ma_result lua_vfs_onClose(ma_vfs* pVFS, ma_vfs_file file) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    int ref = (int)(intptr_t)file;
    /* Call onClose if provided */
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onClose");
    lua_remove(L, -2);
    if (lua_isfunction(L, -1)) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
        lua_pcall(L, 1, 0, 0);
    } else {
        lua_pop(L, 1);
    }
    luaL_unref(L, LUA_REGISTRYINDEX, ref);
    return MA_SUCCESS;
}

static ma_result lua_vfs_onRead(ma_vfs* pVFS, ma_vfs_file file, void* pDst, size_t sizeInBytes, size_t* pBytesRead) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    int ref = (int)(intptr_t)file;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onRead");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_ERROR; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    lua_pushinteger(L, (lua_Integer)sizeInBytes);
    if (lua_pcall(L, 2, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
    if (lua_isnil(L, -1)) { lua_pop(L, 1); if (pBytesRead) *pBytesRead = 0; return MA_AT_END; }
    size_t len;
    const char* data = lua_tolstring(L, -1, &len);
    if (len > sizeInBytes) len = sizeInBytes;
    memcpy(pDst, data, len);
    if (pBytesRead) *pBytesRead = len;
    lua_pop(L, 1);
    return MA_SUCCESS;
}

static ma_result lua_vfs_onWrite(ma_vfs* pVFS, ma_vfs_file file, const void* pSrc, size_t sizeInBytes, size_t* pBytesWritten) {
    (void)pVFS; (void)file; (void)pSrc; (void)sizeInBytes; (void)pBytesWritten;
    return MA_NOT_IMPLEMENTED;
}

static ma_result lua_vfs_onSeek(ma_vfs* pVFS, ma_vfs_file file, ma_int64 offset, ma_seek_origin origin) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    int ref = (int)(intptr_t)file;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onSeek");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    lua_pushinteger(L, (lua_Integer)offset);
    lua_pushinteger(L, (lua_Integer)origin);
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
    return MA_SUCCESS;
}

static ma_result lua_vfs_onTell(ma_vfs* pVFS, ma_vfs_file file, ma_int64* pCursor) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    int ref = (int)(intptr_t)file;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onTell");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
    *pCursor = (ma_int64)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return MA_SUCCESS;
}

static ma_result lua_vfs_onInfo(ma_vfs* pVFS, ma_vfs_file file, ma_file_info* pInfo) {
    LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
    lua_State* L = ctx->L;
    int ref = (int)(intptr_t)file;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
    lua_getfield(L, -1, "onInfo");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
    pInfo->sizeInBytes = (ma_uint64)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return MA_SUCCESS;
}

/* VfsNew({onOpen=..., onRead=..., ...}) -> lightuserdata (ma_vfs*) */
static int l_ma_vfs_new(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    LuaVfsContext* ctx = (LuaVfsContext*)lua_newuserdatauv(L, sizeof(LuaVfsContext), 1);
    memset(ctx, 0, sizeof(LuaVfsContext));
    ctx->L = L;
    ctx->cb.onOpen  = lua_vfs_onOpen;
    ctx->cb.onOpenW = lua_vfs_onOpenW;
    ctx->cb.onClose = lua_vfs_onClose;
    ctx->cb.onRead  = lua_vfs_onRead;
    ctx->cb.onWrite = lua_vfs_onWrite;
    ctx->cb.onSeek  = lua_vfs_onSeek;
    ctx->cb.onTell  = lua_vfs_onTell;
    ctx->cb.onInfo  = lua_vfs_onInfo;
    /* Store callback table as registry ref */
    lua_pushvalue(L, 1);
    ctx->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    /* Also store table as uservalue to prevent GC */
    lua_pushvalue(L, 1);
    lua_setiuservalue(L, -2, 1);
    /* Return the userdata itself (keeps ctx alive via GC) */
    return 1;
}
