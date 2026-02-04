namespace Generator.CBinding;

/// <summary>
/// C バインディング文字列生成
/// </summary>
public static class CBindingGen
{
    /// <summary>
    /// ファイルヘッダ (includes, マクロ定義)
    /// </summary>
    public static string Header(IEnumerable<string> includes)
    {
        var userIncludes = string.Join("\n", includes.Select(h => $"#include \"{h}\""));
        return $$"""
            /* machine generated, do not edit */
            #include <lua.h>
            #include <lauxlib.h>
            #include <lualib.h>
            #include <string.h>

            {{userIncludes}}

            #ifndef MANE3D_API
              #ifdef _WIN32
                #ifdef MANE3D_EXPORTS
                  #define MANE3D_API __declspec(dllexport)
                #else
                  #define MANE3D_API __declspec(dllimport)
                #endif
              #else
                #define MANE3D_API
              #endif
            #endif

            """;
    }

    /// <summary>
    /// 構造体の new 関数
    /// </summary>
    public static string StructNew(string structName, string metatable, IEnumerable<FieldInit> fields)
    {
        var fieldInits = string.Join("\n", fields.Select(GenFieldInit));
        return $$"""
            static int l_{{structName}}_new(lua_State *L) {
                {{structName}}* ud = ({{structName}}*)lua_newuserdatauv(L, sizeof({{structName}}), 1);
                memset(ud, 0, sizeof({{structName}}));
                luaL_setmetatable(L, "{{metatable}}");
                if (lua_istable(L, 1)) {
                    /* Store original table as uservalue for callback access */
                    lua_pushvalue(L, 1);
                    lua_setiuservalue(L, -2, 1);
            {{fieldInits}}
                }
                return 1;
            }

            """;
    }

    /// <summary>
    /// 関数バインディング
    /// </summary>
    public static string Func(string funcName, IEnumerable<Param> parameters, Type ret, string metatable, string? ifdef = null)
    {
        var paramList = parameters.ToList();
        var paramDecls = string.Join("\n", paramList.Select((p, i) => GenParamDecl(p, i + 1, metatable)).Where(s => s != ""));
        var argNames = string.Join(", ", paramList.Select(p => p.Name));
        var call = ret switch
        {
            Type.Void => $"    {funcName}({argNames});\n    return 0;",
            Type.Int => $"    lua_pushinteger(L, {funcName}({argNames}));\n    return 1;",
            Type.Bool => $"    lua_pushboolean(L, {funcName}({argNames}));\n    return 1;",
            Type.Float => $"    lua_pushnumber(L, {funcName}({argNames}));\n    return 1;",
            _ => $"    {funcName}({argNames});\n    return 0;"
        };
        var ifdefStr = ifdef != null ? $"    #ifdef {ifdef}\n    (void)L;\n    return 0;\n    #else\n" : "";
        var endifStr = ifdef != null ? "\n    #endif" : "";

        return $$"""
            static int l_{{funcName}}(lua_State *L) {
            {{ifdefStr}}{{paramDecls}}
            {{call}}{{endifStr}}
            }

            """;
    }

    /// <summary>
    /// Enum の Lua テーブル生成
    /// </summary>
    public static string Enum(string cEnumName, string luaEnumName, IEnumerable<(string luaName, string cConstName)> items)
    {
        var itemLines = string.Join("\n", items.Select(item =>
            $"        lua_pushinteger(L, {item.cConstName}); lua_setfield(L, -2, \"{item.luaName}\");"));
        return $$"""
            static void register_{{cEnumName}}(lua_State *L) {
                lua_newtable(L);
            {{itemLines}}
                lua_setfield(L, -2, "{{luaEnumName}}");
            }

            """;
    }

    /// <summary>
    /// luaL_Reg 配列
    /// </summary>
    public static string LuaReg(string arrayName, IEnumerable<(string luaName, string cFunc)> entries)
    {
        var lines = entries.Select(e => $"    {{\"{e.luaName}\", {e.cFunc}}},");
        return $$"""
            static const luaL_Reg {{arrayName}}[] = {
            {{string.Join("\n", lines)}}
                {NULL, NULL}
            };

            """;
    }

    /// <summary>
    /// luaopen 関数
    /// </summary>
    public static string LuaOpen(string funcName, string regArray) => $$"""
        MANE3D_API int luaopen_{{funcName}}(lua_State *L) {
            register_metatables(L);
            luaL_newlib(L, {{regArray}});
            return 1;
        }
        """;

    /// <summary>
    /// 構造体の __index メタメソッド生成
    /// </summary>
    public static string StructIndex(string structName, string metatable, IEnumerable<FieldInit> fields)
    {
        var branches = fields
            .Where(f => f.Type is not Type.FuncPtr)
            .Select(f => $"    if (strcmp(key, \"{f.LuaFieldName}\") == 0) {{ {GenPush(f)}; return 1; }}");
        return $$"""
            static int l_{{structName}}__index(lua_State *L) {
                {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
                const char* key = luaL_checkstring(L, 2);
            {{string.Join("\n", branches)}}
                return 0;
            }

            """;
    }

    /// <summary>
    /// 構造体の __pairs メタメソッド生成 (next関数 + イテレータ)
    /// </summary>
    public static string StructPairs(string structName, string metatable, IEnumerable<FieldInit> fields)
    {
        var accessibleFields = fields.Where(f => f.Type is not Type.FuncPtr).ToList();
        var fieldNames = string.Join(",\n", accessibleFields.Select(f =>
            $"        \"{f.LuaFieldName}\""));
        return $$"""
            static int l_{{structName}}__pairs_next(lua_State *L) {
                static const char* fields[] = {
            {{fieldNames}}
                };
                static const int nfields = {{accessibleFields.Count}};
                {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
                int idx = 0;
                if (!lua_isnil(L, 2)) {
                    const char* key = lua_tostring(L, 2);
                    for (int i = 0; i < nfields; i++) {
                        if (strcmp(key, fields[i]) == 0) { idx = i + 1; break; }
                    }
                }
                if (idx >= nfields) return 0;
                lua_pushstring(L, fields[idx]);
                lua_pushvalue(L, 1);
                lua_pushstring(L, fields[idx]);
                lua_gettable(L, -2);
                lua_remove(L, -2);
                return 2;
            }
            static int l_{{structName}}__pairs(lua_State *L) {
                lua_pushcfunction(L, l_{{structName}}__pairs_next);
                lua_pushvalue(L, 1);
                lua_pushnil(L);
                return 3;
            }

            """;
    }

    /// <summary>
    /// 構造体の __newindex メタメソッド生成
    /// </summary>
    public static string StructNewindex(string structName, string metatable, IEnumerable<FieldInit> fields)
    {
        var branches = fields
            .Where(f => f.Type is not Type.FuncPtr)
            .Select(f => $"    if (strcmp(key, \"{f.LuaFieldName}\") == 0) {{ {GenSet(f)}; return 0; }}");
        return $$"""
            static int l_{{structName}}__newindex(lua_State *L) {
                {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
                const char* key = luaL_checkstring(L, 2);
            {{string.Join("\n", branches)}}
                return luaL_error(L, "unknown field: %s", key);
            }

            """;
    }

    /// <summary>
    /// メタテーブル登録関数
    /// </summary>
    /// <param name="metatables">
    /// (metatable名, __index関数名 or null, __newindex関数名 or null, __pairs関数名 or null)
    /// </param>
    public static string RegisterMetatables(IEnumerable<(string metatable, string? indexFunc, string? newindexFunc, string? pairsFunc)> metatables)
    {
        var lines = metatables.Select(m =>
        {
            var sb = $"    luaL_newmetatable(L, \"{m.metatable}\");";
            if (m.indexFunc != null)
                sb += $"\n    lua_pushcfunction(L, {m.indexFunc}); lua_setfield(L, -2, \"__index\");";
            if (m.newindexFunc != null)
                sb += $"\n    lua_pushcfunction(L, {m.newindexFunc}); lua_setfield(L, -2, \"__newindex\");";
            if (m.pairsFunc != null)
                sb += $"\n    lua_pushcfunction(L, {m.pairsFunc}); lua_setfield(L, -2, \"__pairs\");";
            sb += "\n    lua_pop(L, 1);";
            return sb;
        });
        return $$"""
            static void register_metatables(lua_State *L) {
            {{string.Join("\n", lines)}}
            }

            """;
    }

    // ===== ヘルパー関数 =====

    /// <summary>
    /// フィールドの getter 式 (lua_push*)
    /// </summary>
    private static string GenPush(FieldInit f) => f.Type switch
    {
        Type.Int or Type.Int64 or Type.UInt32 or Type.UInt64 or Type.Size or Type.UIntPtr or Type.IntPtr
            => $"lua_pushinteger(L, (lua_Integer)self->{f.FieldName})",
        Type.Float or Type.Double
            => $"lua_pushnumber(L, (lua_Number)self->{f.FieldName})",
        Type.Bool
            => $"lua_pushboolean(L, self->{f.FieldName})",
        Type.String or Type.ConstPointer(Type.String)
            => $"lua_pushstring(L, self->{f.FieldName})",
        Type.Struct(_)
            => $"lua_pushinteger(L, (lua_Integer)self->{f.FieldName})",
        _ => $"lua_pushnil(L)"
    };

    /// <summary>
    /// フィールドの setter 式 (luaL_check*)
    /// </summary>
    private static string GenSet(FieldInit f) => f.Type switch
    {
        Type.Int or Type.Int64 or Type.UInt32 or Type.UInt64 or Type.Size or Type.UIntPtr or Type.IntPtr
            => $"self->{f.FieldName} = ({TypeToString(f.Type)})luaL_checkinteger(L, 3)",
        Type.Float or Type.Double
            => $"self->{f.FieldName} = ({TypeToString(f.Type)})luaL_checknumber(L, 3)",
        Type.Bool
            => $"self->{f.FieldName} = lua_toboolean(L, 3)",
        Type.String or Type.ConstPointer(Type.String)
            => $"self->{f.FieldName} = luaL_checkstring(L, 3)",
        Type.Struct(var name)
            => $"self->{f.FieldName} = ({name})luaL_checkinteger(L, 3)",
        _ => $"luaL_error(L, \"unsupported type for field: %s\", key)"
    };

    private static string TypeToString(Type typ) => typ switch
    {
        Type.Int => "int",
        Type.Int64 => "int64_t",
        Type.UInt32 => "uint32_t",
        Type.UInt64 => "uint64_t",
        Type.Size => "size_t",
        Type.UIntPtr => "uintptr_t",
        Type.IntPtr => "intptr_t",
        Type.Float => "float",
        Type.Double => "double",
        Type.Bool => "bool",
        Type.String => "const char*",
        Type.Pointer(var t) => $"{TypeToString(t)}*",
        Type.ConstPointer(var t) => $"const {TypeToString(t)}*",
        Type.FuncPtr(var args, var ret) =>
            $"{TypeToString(ret)} (*)({(args.Count == 0 ? "void" : string.Join(", ", args.Select(TypeToString)))})",
        Type.Struct(var name) => name,
        Type.Void => "void",
        _ => throw new ArgumentException($"Unknown type: {typ}")
    };

    private static string GenFieldInit(FieldInit field)
    {
        var luaName = field.LuaFieldName;
        var cName = field.FieldName;
        var typ = field.Type;
        var getField = $"        lua_getfield(L, 1, \"{luaName}\");";

        // カスタム初期化コードが指定されている場合
        if (field.InitCode != null)
        {
            if (field.InitCode == "")
                return $"{getField}\n        lua_pop(L, 1);";
            return $"{getField}\n{field.InitCode}";
        }

        // コールバック (FuncPtr) は StructNew では設定しない
        if (typ is Type.FuncPtr)
            return $"{getField}\n        lua_pop(L, 1);";

        var body = typ switch
        {
            Type.Int or Type.Int64 or Type.UInt32 or Type.UInt64 or Type.Size or Type.UIntPtr or Type.IntPtr => $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{TypeToString(typ)}})lua_tointeger(L, -1);
                        lua_pop(L, 1);
                """,
            Type.Float or Type.Double => $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{TypeToString(typ)}})lua_tonumber(L, -1);
                        lua_pop(L, 1);
                """,
            Type.ConstPointer(Type.String) or Type.String => $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = lua_tostring(L, -1);
                        lua_pop(L, 1);
                """,
            Type.Bool => $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = lua_toboolean(L, -1);
                        lua_pop(L, 1);
                """,
            _ => "        lua_pop(L, 1);"
        };
        return $"{getField}\n{body}";
    }

    private static string GenParamDecl(Param p, int idx, string metatable)
    {
        // カスタムチェックコードが指定されている場合
        if (p.CheckCode != null)
            return p.CheckCode;

        return p.Type switch
        {
            Type.ConstPointer(Type.Struct(var sn)) => $"    const {sn}* {p.Name} = (const {sn}*)luaL_checkudata(L, {idx}, \"{metatable}\");",
            Type.ConstPointer(Type.String) or Type.String => $"    const char* {p.Name} = luaL_checkstring(L, {idx});",
            Type.Int => $"    int {p.Name} = (int)luaL_checkinteger(L, {idx});",
            Type.UInt32 => $"    uint32_t {p.Name} = (uint32_t)luaL_checkinteger(L, {idx});",
            Type.Pointer(Type.Void) => $"    void* {p.Name} = lua_touserdata(L, {idx});",
            _ => ""
        };
    }
}
