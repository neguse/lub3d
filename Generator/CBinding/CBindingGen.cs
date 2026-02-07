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
            #include <stdbool.h>
            #include <stdint.h>
            #include <stdlib.h>

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
            Type.Int64 or Type.UInt32 or Type.UInt64 or Type.Size or Type.UIntPtr or Type.IntPtr
                => $"    lua_pushinteger(L, (lua_Integer){funcName}({argNames}));\n    return 1;",
            Type.Bool => $"    lua_pushboolean(L, {funcName}({argNames}));\n    return 1;",
            Type.Float => $"    lua_pushnumber(L, {funcName}({argNames}));\n    return 1;",
            Type.Double => $"    lua_pushnumber(L, (lua_Number){funcName}({argNames}));\n    return 1;",
            Type.String or Type.ConstPointer(Type.String)
                => $"    lua_pushstring(L, {funcName}({argNames}));\n    return 1;",
            Type.Pointer(Type.Void) or Type.ConstPointer(Type.Void)
                => $"    lua_pushlightuserdata(L, (void*){funcName}({argNames}));\n    return 1;",
            Type.Enum(_)
                => $"    lua_pushinteger(L, (lua_Integer){funcName}({argNames}));\n    return 1;",
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

    // ===== ModuleSpec ベース生成 =====

    /// <summary>
    /// ModuleSpec から C バインディングコード全体を生成
    /// </summary>
    public static string Generate(ModuleSpec spec)
    {
        var sb = Header(spec.CIncludes);

        // ExtraCCode は Struct/Opaque 型生成の後に出力 (依存関係のため)
        // ただし opaque 型がない場合は先に出力
        if (spec.ExtraCCode != null && spec.OpaqueTypes.Count == 0)
            sb += spec.ExtraCCode;

        // Struct new / metamethods
        var ownStructNames = spec.Structs.Select(s => s.CName).ToHashSet();
        foreach (var s in spec.Structs)
        {
            var fieldInits = s.Fields.Select(f => ToFieldInit(f, ownStructNames)).ToList();
            if (s.CName == "sg_range")
                sb += SgRangeNew(s.CName, s.Metatable, fieldInits);
            else
                sb += StructNew(s.CName, s.Metatable, fieldInits);
            if (s.HasMetamethods)
            {
                sb += StructIndex(s.CName, s.Metatable, fieldInits);
                sb += StructNewindex(s.CName, s.Metatable, fieldInits);
                sb += StructPairs(s.CName, s.Metatable, fieldInits);
            }
        }

        // Functions
        foreach (var f in spec.Funcs)
        {
            // 構造体 return は Func() をバイパスして直接 userdata 生成
            if (f.ReturnType is BindingType.Struct(var retCName, var retMt, _))
            {
                var parms = f.Params.Select((p, i) =>
                {
                    var idx = i + 1;
                    var checkCode = p.Type switch
                    {
                        BindingType.ConstPtr(BindingType.Struct(var cName, var mt, _)) =>
                            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
                        BindingType.Struct(var cName, var mt, _) =>
                            $"    {cName} {p.Name} = *({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
                        _ => (string?)null
                    };
                    return new Param(p.Name, ToOldType(p.Type), checkCode);
                }).ToList();
                var paramDecls = string.Join("\n", parms.Select((p, i) => GenParamDecl(p, i + 1, "")).Where(s => s != ""));
                var argNames = string.Join(", ", parms.Select(p => p.Name));
                sb += $$"""
                    static int l_{{f.CName}}(lua_State *L) {
                    {{paramDecls}}
                        {{retCName}} result = {{f.CName}}({{argNames}});
                        {{retCName}}* ud = ({{retCName}}*)lua_newuserdatauv(L, sizeof({{retCName}}), 0);
                        *ud = result;
                        luaL_setmetatable(L, "{{retMt}}");
                        return 1;
                    }

                    """;
            }
            else
            {
                var parms = f.Params.Select((p, i) =>
                {
                    var idx = i + 1;
                    var checkCode = p.Type switch
                    {
                        BindingType.ConstPtr(BindingType.Struct(var cName, var mt, _)) =>
                            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
                        BindingType.Struct(var cName, var mt, _) =>
                            $"    {cName} {p.Name} = *({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
                        _ => (string?)null
                    };
                    return new Param(p.Name, ToOldType(p.Type), checkCode);
                }).ToList();
                sb += Func(f.CName, parms, ToOldType(f.ReturnType), "");
            }
        }

        // Opaque types
        foreach (var ot in spec.OpaqueTypes)
        {
            sb += OpaqueCheckHelper(ot);
            if (ot.InitFunc != null)
                sb += OpaqueConstructor(ot);
            sb += OpaqueDestructor(ot);
            foreach (var m in ot.Methods)
                sb += OpaqueMethod(ot, m);
            sb += OpaqueMethodTable(ot);
        }

        // ExtraCCode (opaque 型の check ヘルパーに依存する場合があるため、opaque 型の後に出力)
        if (spec.ExtraCCode != null && spec.OpaqueTypes.Count > 0)
            sb += spec.ExtraCCode;

        // Enums
        foreach (var e in spec.Enums)
        {
            var items = e.Items.Select(i => (i.LuaName, i.CConstName));
            sb += Enum(e.CName, e.FieldName, items);
        }

        // Metatables (structs + opaque types)
        var metatables = spec.Structs.Select(s => s.HasMetamethods
            ? (s.Metatable, (string?)$"l_{s.CName}__index", (string?)$"l_{s.CName}__newindex", (string?)$"l_{s.CName}__pairs")
            : (s.Metatable, null, null, null)).ToList();
        foreach (var ot in spec.OpaqueTypes)
            metatables.Add((ot.Metatable, null, null, null));
        sb += RegisterOpaqueMetatables(spec.OpaqueTypes, metatables);

        // LuaReg
        var funcArrayName = $"{spec.ModuleName.Replace('.', '_')}_funcs";
        var luaOpenName = spec.ModuleName.Replace('.', '_');
        var regEntries = new List<(string, string)>();

        // Struct constructors
        foreach (var s in spec.Structs)
            regEntries.Add((s.PascalName, $"l_{s.CName}_new"));

        // Opaque type constructors (only for types with InitFunc)
        foreach (var ot in spec.OpaqueTypes)
        {
            if (ot.InitFunc != null)
                regEntries.Add(($"{ot.PascalName}Init", $"l_{ot.CName}_new"));
        }

        // Extra lua regs (before functions for consistent ordering)
        regEntries.AddRange(spec.ExtraLuaRegs);

        // Functions
        foreach (var f in spec.Funcs)
            regEntries.Add((f.LuaName, $"l_{f.CName}"));

        sb += LuaReg(funcArrayName, regEntries);

        // Enum registrations in luaopen
        var enumRegs = spec.Enums.Select(e => $"    register_{e.CName}(L);").ToList();
        if (enumRegs.Count > 0 || spec.OpaqueTypes.Count > 0)
        {
            sb += $$"""
                MANE3D_API int luaopen_{{luaOpenName}}(lua_State *L) {
                    register_metatables(L);
                    luaL_newlib(L, {{funcArrayName}});
                {{string.Join("\n", enumRegs)}}
                    return 1;
                }
                """;
        }
        else
        {
            sb += LuaOpen(luaOpenName, funcArrayName);
        }

        return sb;
    }

    /// <summary>
    /// sg_range 専用コンストラクタ (string / table 両対応)
    /// </summary>
    public static string SgRangeNew(string structName, string metatable, IEnumerable<FieldInit> fields)
    {
        var fieldInits = string.Join("\n", fields.Select(GenFieldInit));
        return $$"""
            static int l_{{structName}}_new(lua_State *L) {
                {{structName}}* ud = ({{structName}}*)lua_newuserdatauv(L, sizeof({{structName}}), 1);
                memset(ud, 0, sizeof({{structName}}));
                luaL_setmetatable(L, "{{metatable}}");
                if (lua_isstring(L, 1)) {
                    size_t len;
                    const char* data = lua_tolstring(L, 1, &len);
                    ud->ptr = data;
                    ud->size = len;
                    lua_pushvalue(L, 1);
                    lua_setiuservalue(L, -2, 1);
                } else if (lua_istable(L, 1)) {
                    lua_pushvalue(L, 1);
                    lua_setiuservalue(L, -2, 1);
            {{fieldInits}}
                }
                return 1;
            }

            """;
    }

    // ===== Opaque 型生成 =====

    public static string OpaqueCheckHelper(OpaqueTypeBinding ot) => $$"""
        static {{ot.CName}}* check_{{ot.CName}}(lua_State *L, int idx) {
            {{ot.CName}}** pp = ({{ot.CName}}**)luaL_checkudata(L, idx, "{{ot.Metatable}}");
            if (*pp == NULL) luaL_error(L, "{{ot.CName}} already freed");
            return *pp;
        }

        """;

    public static string OpaqueConstructor(OpaqueTypeBinding ot)
    {
        var configInit = ot.ConfigInitFunc != null && ot.ConfigType != null
            ? $"    {ot.ConfigType} config = {ot.ConfigInitFunc}();\n"
            : "";
        var initArg = ot.ConfigType != null ? "&config" : "NULL";
        var initCall = ot.InitFunc != null
            ? $$"""
                    ma_result result = {{ot.InitFunc}}({{initArg}}, p);
                    if (result != MA_SUCCESS) {
                        free(p);
                        return luaL_error(L, "{{ot.InitFunc}} failed: %d", result);
                    }
                """
            : "";
        return $$"""
            static int l_{{ot.CName}}_new(lua_State *L) {
                {{ot.CName}}* p = ({{ot.CName}}*)malloc(sizeof({{ot.CName}}));
                memset(p, 0, sizeof({{ot.CName}}));
            {{configInit}}{{initCall}}
                {{ot.CName}}** pp = ({{ot.CName}}**)lua_newuserdatauv(L, sizeof({{ot.CName}}*), 0);
                *pp = p;
                luaL_setmetatable(L, "{{ot.Metatable}}");
                return 1;
            }

            """;
    }

    public static string OpaqueDestructor(OpaqueTypeBinding ot)
    {
        var uninitCall = ot.UninitFunc != null
            ? $"        {ot.UninitFunc}(*pp);\n"
            : "";
        return $$"""
            static int l_{{ot.CName}}_gc(lua_State *L) {
                {{ot.CName}}** pp = ({{ot.CName}}**)luaL_checkudata(L, 1, "{{ot.Metatable}}");
                if (*pp != NULL) {
            {{uninitCall}}        free(*pp);
                    *pp = NULL;
                }
                return 0;
            }

            """;
    }

    public static string OpaqueMethod(OpaqueTypeBinding ot, MethodBinding m)
    {
        var paramDecls = new List<string>
        {
            $"    {ot.CName}* self = check_{ot.CName}(L, 1);"
        };
        foreach (var (p, i) in m.Params.Select((p, i) => (p, i)))
        {
            var idx = i + 2; // self is 1
            paramDecls.Add(GenOpaqueParamDecl(p, idx));
        }
        var argNames = new List<string> { "self" };
        argNames.AddRange(m.Params.Select(p => p.Name));
        var args = string.Join(", ", argNames);

        var call = m.ReturnType switch
        {
            BindingType.Void => $"    {m.CName}({args});\n    return 0;",
            BindingType.Int => $"    lua_pushinteger(L, {m.CName}({args}));\n    return 1;",
            BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64 or BindingType.Size
                => $"    lua_pushinteger(L, (lua_Integer){m.CName}({args}));\n    return 1;",
            BindingType.Bool => $"    lua_pushboolean(L, {m.CName}({args}));\n    return 1;",
            BindingType.Float => $"    lua_pushnumber(L, {m.CName}({args}));\n    return 1;",
            BindingType.Double => $"    lua_pushnumber(L, (lua_Number){m.CName}({args}));\n    return 1;",
            BindingType.Str => $"    lua_pushstring(L, {m.CName}({args}));\n    return 1;",
            BindingType.Enum(var eName, _) => $"    lua_pushinteger(L, (lua_Integer){m.CName}({args}));\n    return 1;",
            _ => $"    {m.CName}({args});\n    return 0;"
        };

        return $$"""
            static int l_{{m.CName}}(lua_State *L) {
            {{string.Join("\n", paramDecls)}}
            {{call}}
            }

            """;
    }

    public static string OpaqueMethodTable(OpaqueTypeBinding ot)
    {
        var entries = ot.Methods.Select(m => $"    {{\"{m.LuaName}\", l_{m.CName}}},");
        return $$"""
            static const luaL_Reg {{ot.CName}}_methods[] = {
            {{string.Join("\n", entries)}}
                {NULL, NULL}
            };

            """;
    }

    public static string RegisterOpaqueMetatables(
        List<OpaqueTypeBinding> opaqueTypes,
        List<(string metatable, string? indexFunc, string? newindexFunc, string? pairsFunc)> metatables)
    {
        var opaqueSet = opaqueTypes.ToDictionary(ot => ot.Metatable);
        var lines = metatables.Select(m =>
        {
            var sb = $"    luaL_newmetatable(L, \"{m.metatable}\");";
            if (opaqueSet.TryGetValue(m.metatable, out var ot))
            {
                // opaque type: __gc + __index = method table
                sb += $"\n    lua_pushcfunction(L, l_{ot.CName}_gc); lua_setfield(L, -2, \"__gc\");";
                sb += $"\n    luaL_newlib(L, {ot.CName}_methods); lua_setfield(L, -2, \"__index\");";
            }
            else
            {
                if (m.indexFunc != null)
                    sb += $"\n    lua_pushcfunction(L, {m.indexFunc}); lua_setfield(L, -2, \"__index\");";
                if (m.newindexFunc != null)
                    sb += $"\n    lua_pushcfunction(L, {m.newindexFunc}); lua_setfield(L, -2, \"__newindex\");";
                if (m.pairsFunc != null)
                    sb += $"\n    lua_pushcfunction(L, {m.pairsFunc}); lua_setfield(L, -2, \"__pairs\");";
            }
            sb += "\n    lua_pop(L, 1);";
            return sb;
        });
        return $$"""
            static void register_metatables(lua_State *L) {
            {{string.Join("\n", lines)}}
            }

            """;
    }

    private static string GenOpaqueParamDecl(ParamBinding p, int idx) => p.Type switch
    {
        BindingType.Int => $"    int {p.Name} = (int)luaL_checkinteger(L, {idx});",
        BindingType.Int64 => $"    int64_t {p.Name} = (int64_t)luaL_checkinteger(L, {idx});",
        BindingType.UInt32 => $"    uint32_t {p.Name} = (uint32_t)luaL_checkinteger(L, {idx});",
        BindingType.UInt64 => $"    uint64_t {p.Name} = (uint64_t)luaL_checkinteger(L, {idx});",
        BindingType.Size => $"    size_t {p.Name} = (size_t)luaL_checkinteger(L, {idx});",
        BindingType.Float => $"    float {p.Name} = (float)luaL_checknumber(L, {idx});",
        BindingType.Double => $"    double {p.Name} = (double)luaL_checknumber(L, {idx});",
        BindingType.Bool => $"    bool {p.Name} = lua_toboolean(L, {idx});",
        BindingType.Str => $"    const char* {p.Name} = luaL_checkstring(L, {idx});",
        BindingType.ConstPtr(BindingType.Str) => $"    const char* {p.Name} = luaL_checkstring(L, {idx});",
        BindingType.Enum(var eName, _) => $"    {eName} {p.Name} = ({eName})luaL_checkinteger(L, {idx});",
        BindingType.VoidPtr => $"    void* {p.Name} = lua_touserdata(L, {idx});",
        BindingType.Ptr(BindingType.Struct(var cName, var mt, _)) =>
            $"    {cName}* {p.Name} = ({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        BindingType.ConstPtr(BindingType.Struct(var cName, var mt, _)) =>
            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        BindingType.Struct(var cName, var mt, _) =>
            $"    {cName} {p.Name} = *({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        _ => $"    /* unsupported param type for {p.Name} */"
    };

    // ===== BindingType → 旧 CBinding.Type 変換 (内部用) =====

    private static FieldInit ToFieldInit(FieldBinding f, HashSet<string> ownStructs) => f.Type switch
    {
        BindingType.Struct(var cName, var mt, _) when ownStructs.Contains(cName) =>
            new(f.CName, f.LuaName, ToOldType(f.Type),
                $"        if ({(cName == "sg_range" ? "lua_isstring(L, -1) || lua_istable(L, -1)" : "lua_istable(L, -1)")}) {{\n" +
                $"            lua_pushcfunction(L, l_{cName}_new);\n" +
                $"            lua_pushvalue(L, -2);\n" +
                $"            lua_call(L, 1, 1);\n" +
                $"            ud->{f.CName} = *({cName}*)luaL_checkudata(L, -1, \"{mt}\");\n" +
                $"            lua_pop(L, 1);\n" +
                $"        }} else if (lua_isuserdata(L, -1)) {{\n" +
                $"            ud->{f.CName} = *({cName}*)luaL_checkudata(L, -1, \"{mt}\");\n" +
                $"        }}\n" +
                $"        lua_pop(L, 1);"),
        BindingType.Struct(var cName, var mt, _) =>
            new(f.CName, f.LuaName, ToOldType(f.Type),
                $"        if (lua_isuserdata(L, -1)) ud->{f.CName} = *({cName}*)luaL_checkudata(L, -1, \"{mt}\");\n        lua_pop(L, 1);"),
        BindingType.FixedArray(BindingType.Struct(var cName, var mt, _), var len) =>
            new(f.CName, f.LuaName, new Type.Pointer(ToOldType(f.Type)),
                GenerateArrayFieldInit(f.CName, cName, mt, len, ownStructs.Contains(cName))),
        _ => new(f.CName, f.LuaName, ToOldType(f.Type), null)
    };

    private static string GenerateArrayFieldInit(string fieldName, string cName, string mt, int size, bool autoConstruct)
    {
        var elementCondition = cName == "sg_range" ? "lua_isstring(L, -1) || lua_istable(L, -1)" : "lua_istable(L, -1)";
        return autoConstruct
        ? $$"""
                if (lua_istable(L, -1)) {
                    int n = (int)lua_rawlen(L, -1);
                    for (int i = 0; i < n && i < {{size}}; i++) {
                        lua_rawgeti(L, -1, i + 1);
                        if ({{elementCondition}}) {
                            lua_pushcfunction(L, l_{{cName}}_new);
                            lua_pushvalue(L, -2);
                            lua_call(L, 1, 1);
                            ud->{{fieldName}}[i] = *({{cName}}*)luaL_checkudata(L, -1, "{{mt}}");
                            lua_pop(L, 1);
                        } else if (lua_isuserdata(L, -1)) {
                            ud->{{fieldName}}[i] = *({{cName}}*)luaL_checkudata(L, -1, "{{mt}}");
                        }
                        lua_pop(L, 1);
                    }
                }
                lua_pop(L, 1);
        """
        : $$"""
                if (lua_istable(L, -1)) {
                    int n = (int)lua_rawlen(L, -1);
                    for (int i = 0; i < n && i < {{size}}; i++) {
                        lua_rawgeti(L, -1, i + 1);
                        if (lua_isuserdata(L, -1)) ud->{{fieldName}}[i] = *({{cName}}*)luaL_checkudata(L, -1, "{{mt}}");
                        lua_pop(L, 1);
                    }
                }
                lua_pop(L, 1);
        """;
    }

    internal static Type ToOldType(BindingType bt) => bt switch
    {
        BindingType.Int => new Type.Int(),
        BindingType.Int64 => new Type.Int64(),
        BindingType.UInt32 => new Type.UInt32(),
        BindingType.UInt64 => new Type.UInt64(),
        BindingType.Size => new Type.Size(),
        BindingType.UIntPtr => new Type.UIntPtr(),
        BindingType.IntPtr => new Type.IntPtr(),
        BindingType.Float => new Type.Float(),
        BindingType.Double => new Type.Double(),
        BindingType.Bool => new Type.Bool(),
        BindingType.Str => new Type.String(),
        BindingType.VoidPtr => new Type.Pointer(new Type.Void()),
        BindingType.Void => new Type.Void(),
        BindingType.Ptr(var inner) => new Type.Pointer(ToOldType(inner)),
        BindingType.ConstPtr(var inner) => new Type.ConstPointer(ToOldType(inner)),
        BindingType.Struct(var cName, _, _) => new Type.Struct(cName),
        BindingType.FixedArray(var inner, _) => new Type.Pointer(ToOldType(inner)),
        BindingType.Enum(var cName, _) => new Type.Enum(cName),
        BindingType.Callback(var parms, var ret) => new Type.FuncPtr(
            parms.Select(p => ToOldType(p.Type)).ToList(),
            ret != null ? ToOldType(ret) : new Type.Void()),
        BindingType.Custom(var cTypeName, _, _, _, _, _) => new Type.Struct(cTypeName),
        _ => new Type.Void()
    };

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
        Type.Enum(_)
            => $"lua_pushinteger(L, (lua_Integer)self->{f.FieldName})",
        Type.Struct(_) or _
            => $"lua_pushnil(L)"
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
        Type.Enum(var name)
            => $"self->{f.FieldName} = ({name})luaL_checkinteger(L, 3)",
        Type.Struct(_) or _
            => $"luaL_error(L, \"unsupported type for field: %s\", key)"
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
        Type.Enum(var name) => name,
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
            Type.Enum(var enumName) => $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{enumName}})lua_tointeger(L, -1);
                        lua_pop(L, 1);
                """,
            Type.Struct(_) or _ => "        lua_pop(L, 1);"
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
            Type.Int64 => $"    int64_t {p.Name} = (int64_t)luaL_checkinteger(L, {idx});",
            Type.UInt32 => $"    uint32_t {p.Name} = (uint32_t)luaL_checkinteger(L, {idx});",
            Type.UInt64 => $"    uint64_t {p.Name} = (uint64_t)luaL_checkinteger(L, {idx});",
            Type.Size => $"    size_t {p.Name} = (size_t)luaL_checkinteger(L, {idx});",
            Type.UIntPtr => $"    uintptr_t {p.Name} = (uintptr_t)luaL_checkinteger(L, {idx});",
            Type.IntPtr => $"    intptr_t {p.Name} = (intptr_t)luaL_checkinteger(L, {idx});",
            Type.Bool => $"    bool {p.Name} = lua_toboolean(L, {idx});",
            Type.Float => $"    float {p.Name} = (float)luaL_checknumber(L, {idx});",
            Type.Double => $"    double {p.Name} = (double)luaL_checknumber(L, {idx});",
            Type.Pointer(Type.Void) => $"    void* {p.Name} = lua_touserdata(L, {idx});",
            Type.Enum(var sn) => $"    {sn} {p.Name} = ({sn})luaL_checkinteger(L, {idx});",
            Type.Struct(_) or _ => ""
        };
    }
}
