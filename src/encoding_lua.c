/*
 * encoding_lua.c - Shift_JIS to UTF-8 conversion using Windows API
 */

#include <lua.h>
#include <lauxlib.h>

#ifdef _WIN32
#include <windows.h>

/* Convert Shift_JIS to UTF-8 using Windows API */
static int l_sjis_to_utf8(lua_State *L) {
    size_t input_len;
    const char *input = luaL_checklstring(L, 1, &input_len);

    if (input_len == 0) {
        lua_pushliteral(L, "");
        return 1;
    }

    /* First, convert Shift_JIS to UTF-16 */
    int wide_len = MultiByteToWideChar(932, 0, input, (int)input_len, NULL, 0);
    if (wide_len == 0) {
        /* Conversion failed, return original string */
        lua_pushvalue(L, 1);
        return 1;
    }

    wchar_t *wide_buf = (wchar_t *)malloc(wide_len * sizeof(wchar_t));
    if (!wide_buf) {
        return luaL_error(L, "out of memory");
    }

    MultiByteToWideChar(932, 0, input, (int)input_len, wide_buf, wide_len);

    /* Then, convert UTF-16 to UTF-8 */
    int utf8_len = WideCharToMultiByte(CP_UTF8, 0, wide_buf, wide_len, NULL, 0, NULL, NULL);
    if (utf8_len == 0) {
        free(wide_buf);
        lua_pushvalue(L, 1);
        return 1;
    }

    char *utf8_buf = (char *)malloc(utf8_len + 1);
    if (!utf8_buf) {
        free(wide_buf);
        return luaL_error(L, "out of memory");
    }

    WideCharToMultiByte(CP_UTF8, 0, wide_buf, wide_len, utf8_buf, utf8_len, NULL, NULL);
    utf8_buf[utf8_len] = '\0';

    lua_pushlstring(L, utf8_buf, utf8_len);

    free(wide_buf);
    free(utf8_buf);

    return 1;
}

#else
/* Non-Windows: just return the original string */
static int l_sjis_to_utf8(lua_State *L) {
    lua_pushvalue(L, 1);
    return 1;
}
#endif

static const luaL_Reg encoding_funcs[] = {
    {"sjis_to_utf8", l_sjis_to_utf8},
    {NULL, NULL}
};

int luaopen_mane3d_encoding(lua_State *L) {
    luaL_newlib(L, encoding_funcs);
    return 1;
}
