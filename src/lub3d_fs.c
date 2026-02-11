/*
 * lub3d_fs.c - Unified file system module for lub3d
 */
#include "lub3d_fs.h"
#include <lauxlib.h>
#include <lualib.h>
#include <stdlib.h>
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

/* ===== Platform-specific implementations ===== */

#ifdef __EMSCRIPTEN__

/* Synchronous XHR fetch (binary-safe).
   Uses arraybuffer responseType if supported (Workers), otherwise
   falls back to overrideMimeType x-user-defined for main thread. */
EM_JS(char *, js_fetch_file, (const char *url, int *out_len), {
    var urlStr = UTF8ToString(url);

    /* Strategy 1: Try synchronous XHR with arraybuffer (works in Workers) */
    var xhr = new XMLHttpRequest();
    xhr.open("GET", urlStr, false);
    var useArrayBuffer = false;
    try {
        xhr.responseType = "arraybuffer";
        useArrayBuffer = (xhr.responseType === "arraybuffer");
    } catch(e) {}

    if (useArrayBuffer) {
        try {
            xhr.send();
            if (xhr.status === 200 && xhr.response instanceof ArrayBuffer) {
                var arr = new Uint8Array(xhr.response);
                var len = arr.length;
                var ptr = _malloc(len);
                HEAPU8.set(arr, ptr);
                HEAP32[out_len >> 2] = len;
                return ptr;
            }
        } catch(e) {
            console.error("Fetch error (arraybuffer):", e);
        }
        HEAP32[out_len >> 2] = 0;
        return 0;
    }

    /* Strategy 2: Synchronous XHR with x-user-defined + responseText.
       To avoid Content-Encoding corruption, request no compression. */
    var xhr2 = new XMLHttpRequest();
    xhr2.open("GET", urlStr, false);
    xhr2.overrideMimeType("text/plain; charset=x-user-defined");
    try {
        xhr2.send();
        if (xhr2.status === 200) {
            var text = xhr2.responseText;
            var len = text.length;
            var ptr = _malloc(len);
            for (var i = 0; i < len; i++) {
                HEAPU8[ptr + i] = text.charCodeAt(i) & 0xff;
            }
            HEAP32[out_len >> 2] = len;
            return ptr;
        }
    } catch(e) {
        console.error("Fetch error (text):", e);
    }
    HEAP32[out_len >> 2] = 0;
    return 0;
});

/* Synchronous XHR HEAD request */
EM_JS(int, js_head_status, (const char *url), {
    var xhr = new XMLHttpRequest();
    xhr.open("HEAD", UTF8ToString(url), false);
    try {
        xhr.send();
        return xhr.status;
    } catch(e) {
        return 0;
    }
});

/* Synchronous XHR HEAD request returning Last-Modified as Unix timestamp */
EM_JS(double, js_head_mtime, (const char *url), {
    var xhr = new XMLHttpRequest();
    xhr.open("HEAD", UTF8ToString(url), false);
    try {
        xhr.send();
        if (xhr.status === 200) {
            var lm = xhr.getResponseHeader("Last-Modified");
            if (lm) {
                var ts = Date.parse(lm);
                if (!isNaN(ts)) return ts / 1000.0;
            }
        }
    } catch(e) {}
    return 0;
});

char *lub3d_fs_fetch_file(const char *url, size_t *out_len)
{
    int len = 0;
    char *data = js_fetch_file(url, &len);
    *out_len = (size_t)len;
    return data;
}

static int l_fs_read(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    size_t len;
    char *data = lub3d_fs_fetch_file(path, &len);
    if (data && len > 0) {
        lua_pushlstring(L, data, len);
        free(data);
        return 1;
    }
    if (data) free(data);
    lua_pushnil(L);
    return 1;
}

static int l_fs_write(lua_State *L)
{
    (void)L;
    lua_pushboolean(L, 0);
    return 1;
}

static int l_fs_mtime(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    double ts = js_head_mtime(path);
    if (ts > 0) {
        lua_pushinteger(L, (lua_Integer)ts);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int l_fs_exists(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    int status = js_head_status(path);
    lua_pushboolean(L, status == 200);
    return 1;
}

static int l_fs_dir(lua_State *L)
{
    (void)L;
    lua_pushnil(L);
    return 1;
}

#else /* Native */

#include <stdio.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dirent.h>
#endif

static int l_fs_read(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    FILE *f = fopen(path, "rb");
    if (!f) {
        lua_pushnil(L);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size <= 0) {
        fclose(f);
        lua_pushliteral(L, "");
        return 1;
    }
    char *buf = (char *)malloc((size_t)size);
    if (!buf) {
        fclose(f);
        lua_pushnil(L);
        return 1;
    }
    size_t read = fread(buf, 1, (size_t)size, f);
    fclose(f);
    lua_pushlstring(L, buf, read);
    free(buf);
    return 1;
}

static int l_fs_write(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    FILE *f = fopen(path, "wb");
    if (!f) {
        lua_pushboolean(L, 0);
        return 1;
    }
    size_t written = fwrite(data, 1, len, f);
    fclose(f);
    lua_pushboolean(L, written == len);
    return 1;
}

static int l_fs_mtime(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    struct stat st;
    if (stat(path, &st) == 0 && st.st_mtime != 0) {
        lua_pushinteger(L, (lua_Integer)st.st_mtime);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int l_fs_exists(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    struct stat st;
    lua_pushboolean(L, stat(path, &st) == 0);
    return 1;
}

/* Directory iterator */
#ifdef _WIN32

typedef struct {
    HANDLE hFind;
    WIN32_FIND_DATAA ffd;
    int first;
} DirIter;

static int dir_iter(lua_State *L)
{
    DirIter *d = (DirIter *)lua_touserdata(L, lua_upvalueindex(1));
    if (d->first) {
        d->first = 0;
        if (d->hFind == INVALID_HANDLE_VALUE) return 0;
        lua_pushstring(L, d->ffd.cFileName);
        return 1;
    }
    if (FindNextFileA(d->hFind, &d->ffd)) {
        lua_pushstring(L, d->ffd.cFileName);
        return 1;
    }
    return 0;
}

static int dir_gc(lua_State *L)
{
    DirIter *d = (DirIter *)lua_touserdata(L, 1);
    if (d->hFind != INVALID_HANDLE_VALUE) {
        FindClose(d->hFind);
        d->hFind = INVALID_HANDLE_VALUE;
    }
    return 0;
}

static int l_fs_dir(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char pattern[MAX_PATH];
    snprintf(pattern, sizeof(pattern), "%s\\*", path);

    DirIter *d = (DirIter *)lua_newuserdatauv(L, sizeof(DirIter), 0);
    d->hFind = FindFirstFileA(pattern, &d->ffd);
    d->first = 1;

    if (luaL_newmetatable(L, "lub3d.fs.dir")) {
        lua_pushcfunction(L, dir_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    lua_pushcclosure(L, dir_iter, 1);
    return 1;
}

#else /* POSIX */

typedef struct {
    DIR *dp;
} DirIter;

static int dir_iter(lua_State *L)
{
    DirIter *d = (DirIter *)lua_touserdata(L, lua_upvalueindex(1));
    if (!d->dp) return 0;
    struct dirent *ep = readdir(d->dp);
    if (ep) {
        lua_pushstring(L, ep->d_name);
        return 1;
    }
    return 0;
}

static int dir_gc(lua_State *L)
{
    DirIter *d = (DirIter *)lua_touserdata(L, 1);
    if (d->dp) {
        closedir(d->dp);
        d->dp = NULL;
    }
    return 0;
}

static int l_fs_dir(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    DirIter *d = (DirIter *)lua_newuserdatauv(L, sizeof(DirIter), 0);
    d->dp = opendir(path);

    if (!d->dp) {
        lua_pushnil(L);
        return 1;
    }

    if (luaL_newmetatable(L, "lub3d.fs.dir")) {
        lua_pushcfunction(L, dir_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    lua_pushcclosure(L, dir_iter, 1);
    return 1;
}

#endif /* _WIN32 / POSIX */

#endif /* __EMSCRIPTEN__ / Native */

/* ===== Module registration ===== */

static const luaL_Reg fs_funcs[] = {
    {"read", l_fs_read},
    {"write", l_fs_write},
    {"mtime", l_fs_mtime},
    {"exists", l_fs_exists},
    {"dir", l_fs_dir},
    {NULL, NULL}
};

int luaopen_lub3d_fs(lua_State *L)
{
    luaL_newlib(L, fs_funcs);
    return 1;
}
