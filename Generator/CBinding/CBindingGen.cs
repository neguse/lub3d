namespace Generator.CBinding;

/// <summary>
/// C バインディング文字列生成
/// </summary>
public static class CBindingGen
{
    /// <summary>
    /// ファイルヘッダ (includes, マクロ定義)
    /// </summary>
    private static string Header(IEnumerable<string> includes)
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

            #ifndef LUB3D_API
              #ifdef _WIN32
                #ifdef LUB3D_EXPORTS
                  #define LUB3D_API __declspec(dllexport)
                #else
                  #define LUB3D_API __declspec(dllimport)
                #endif
              #else
                #define LUB3D_API
              #endif
            #endif

            """;
    }

    /// <summary>
    /// C++ モード用ヘッダ — imgui.h は extern "C" の外、Lua ヘッダは中
    /// </summary>
    private static string CppHeader(IEnumerable<string> includes)
    {
        var userIncludes = string.Join("\n", includes.Select(h => $"#include \"{h}\""));
        return $$"""
            /* machine generated, do not edit */
            {{userIncludes}}

            extern "C" {
            #include <lua.h>
            #include <lauxlib.h>
            #include <lualib.h>
            }  /* extern "C" */

            #include <string.h>
            #include <stdint.h>
            #include <stdlib.h>

            #ifndef LUB3D_API
              #ifdef _WIN32
                #ifdef LUB3D_EXPORTS
                  #define LUB3D_API __declspec(dllexport)
                #else
                  #define LUB3D_API __declspec(dllimport)
                #endif
              #else
                #define LUB3D_API
              #endif
            #endif

            """;
    }

    /// <summary>
    /// 構造体の new 関数
    /// </summary>
    private static string StructNew(string structName, string metatable, IEnumerable<FieldBinding> fields,
        Dictionary<string, StructBinding> structBindings, IEnumerable<PropertyBinding>? properties = null)
    {
        var fieldInits = string.Join("\n", fields.Select(f => GenBindingFieldInit(f, structBindings)));
        var extraUV = (properties ?? []).Count(p => p.SetterCode != null);
        var nuvalue = 1 + extraUV;
        return $$"""
            static int l_{{structName}}_new(lua_State *L) {
                {{structName}}* ud = ({{structName}}*)lua_newuserdatauv(L, sizeof({{structName}}), {{nuvalue}});
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
    /// Enum の Lua テーブル生成
    /// </summary>
    private static string Enum(string cEnumName, string luaEnumName, IEnumerable<(string luaName, string cConstName)> items)
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
    private static string LuaReg(string arrayName, IEnumerable<(string luaName, string cFunc)> entries)
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
    private static string LuaOpen(string funcName, string regArray) => $$"""
        LUB3D_API int luaopen_{{funcName}}(lua_State *L) {
            register_metatables(L);
            luaL_newlib(L, {{regArray}});
            return 1;
        }
        """;

    /// <summary>
    /// 構造体の __index メタメソッド生成
    /// </summary>
    private static string StructIndex(string structName, string metatable, IEnumerable<FieldBinding> fields,
        IEnumerable<PropertyBinding>? properties = null)
    {
        var branches = fields
            .Where(f => f.Type is not BindingType.Callback)
            .Select(f => $"    if (strcmp(key, \"{f.LuaName}\") == 0) {{ {GenBindingPush(f)}; return 1; }}");
        var propBranches = (properties ?? [])
            .Select(p => $"    if (strcmp(key, \"{p.LuaName}\") == 0) {{ {p.GetterCode.Replace("{self}", "self")}; return 1; }}");
        return $$"""
            static int l_{{structName}}__index(lua_State *L) {
                {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
                const char* key = luaL_checkstring(L, 2);
            {{string.Join("\n", branches.Concat(propBranches))}}
                return 0;
            }

            """;
    }

    /// <summary>
    /// 構造体の __pairs メタメソッド生成 (next関数 + イテレータ)
    /// </summary>
    private static string StructPairs(string structName, string metatable, IEnumerable<FieldBinding> fields,
        IEnumerable<PropertyBinding>? properties = null)
    {
        var accessibleFields = fields.Where(f => f.Type is not BindingType.Callback).ToList();
        var fieldEntries = accessibleFields.Select(f =>
            $"        \"{f.LuaName}\"").ToList();
        // プロパティ名も列挙に含める
        foreach (var prop in properties ?? [])
            fieldEntries.Add($"        \"{prop.LuaName}\"");
        var totalCount = fieldEntries.Count;
        // Avoid empty array initializer (triggers MSVC ICE)
        if (fieldEntries.Count == 0) fieldEntries.Add("        NULL");
        var fieldNames = string.Join(",\n", fieldEntries);
        return $$"""
            static int l_{{structName}}__pairs_next(lua_State *L) {
                static const char* fields[] = {
            {{fieldNames}}
                };
                static const int nfields = {{totalCount}};
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
    private static string StructNewindex(string structName, string metatable, IEnumerable<FieldBinding> fields,
        Dictionary<string, StructBinding> structBindings, IEnumerable<PropertyBinding>? properties = null)
    {
        var branches = fields
            .Where(f => f.Type is not BindingType.Callback)
            .Select(f => $"    if (strcmp(key, \"{f.LuaName}\") == 0) {{ {GenBindingSet(f, structBindings)}; return 0; }}");
        var propBranches = (properties ?? [])
            .Select(p => p.SetterCode != null
                ? $"    if (strcmp(key, \"{p.LuaName}\") == 0) {{ {p.SetterCode.Replace("{self}", "self").Replace("{value_idx}", "3")}; return 0; }}"
                : $"    if (strcmp(key, \"{p.LuaName}\") == 0) return luaL_error(L, \"read-only property: %s\", key);");
        return $$"""
            static int l_{{structName}}__newindex(lua_State *L) {
                {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
                const char* key = luaL_checkstring(L, 2);
            {{string.Join("\n", branches.Concat(propBranches))}}
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
    private static string RegisterMetatables(IEnumerable<(string metatable, string? indexFunc, string? newindexFunc, string? pairsFunc)> metatables)
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

    // ===== ExtraMetamethods 生成 =====

    /// <summary>
    /// memcmp ベースの __eq メタメソッド
    /// </summary>
    private static string StructEq(string structName, string metatable) => $$"""
        static int l_{{structName}}__eq(lua_State *L) {
            {{structName}}* a = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
            {{structName}}* b = ({{structName}}*)luaL_checkudata(L, 2, "{{metatable}}");
            lua_pushboolean(L, memcmp(a, b, sizeof({{structName}})) == 0);
            return 1;
        }

        """;

    /// <summary>
    /// バイト列 hex 表現の __tostring メタメソッド
    /// </summary>
    private static string StructTostring(string structName, string metatable) => $$"""
        static int l_{{structName}}__tostring(lua_State *L) {
            {{structName}}* self = ({{structName}}*)luaL_checkudata(L, 1, "{{metatable}}");
            const unsigned char* bytes = (const unsigned char*)self;
            size_t sz = sizeof({{structName}});
            luaL_Buffer buf;
            luaL_buffinit(L, &buf);
            luaL_addstring(&buf, "{{metatable}}:");
            for (size_t i = 0; i < sz; i++) {
                char hex[3];
                hex[0] = "0123456789abcdef"[bytes[i] >> 4];
                hex[1] = "0123456789abcdef"[bytes[i] & 0x0f];
                hex[2] = '\0';
                luaL_addstring(&buf, hex);
            }
            luaL_pushresult(&buf);
            return 1;
        }

        """;

    // ===== ModuleSpec ベース生成 =====

    /// <summary>
    /// ModuleSpec から C バインディングコード全体を生成
    /// </summary>
    public static string Generate(ModuleSpec spec)
    {
        // Validation (共通: C/C++ 両モード)
        foreach (var f in spec.Funcs)
        {
            foreach (var p in f.Params)
            {
                if (p.Type is BindingType.Callback && p.CallbackBridge == CallbackBridgeMode.None)
                    throw new InvalidOperationException(
                        $"Function '{f.CName}' has Callback parameter '{p.Name}'. " +
                        "Callback parameters must be excluded from spec.Funcs (use ExtraLuaFuncs + ExtraCCode instead).");
                if (p.Type is BindingType.FixedArray)
                    throw new InvalidOperationException(
                        $"Function '{f.CName}' has FixedArray parameter '{p.Name}'. " +
                        "FixedArray is field-only (C array parameters decay to pointers).");
            }
            if (f.ReturnType is BindingType.Callback)
                throw new InvalidOperationException(
                    $"Function '{f.CName}' has Callback return type. " +
                    "Callback return types must be excluded from spec.Funcs.");
            if (f.ReturnType is BindingType.FixedArray)
                throw new InvalidOperationException(
                    $"Function '{f.CName}' has FixedArray return type. " +
                    "FixedArray is field-only (C functions do not return arrays).");
        }

        if (spec.IsCpp)
            return GenerateCpp(spec);

        var sb = Header(spec.CIncludes);

        // ExtraCCode は Struct/Opaque 型生成の後に出力 (依存関係のため)
        // ただし opaque 型がない場合は先に出力
        if (spec.ExtraCCode != null && spec.OpaqueTypes.Count == 0)
            sb += spec.ExtraCCode;

        // Struct new / metamethods
        var structBindings = spec.Structs.ToDictionary(s => s.CName);
        foreach (var s in spec.Structs)
        {
            if (s.AllowStringInit)
                sb += SgRangeNew(s.CName, s.Metatable, s.Fields, structBindings, s.Properties);
            else
                sb += StructNew(s.CName, s.Metatable, s.Fields, structBindings, s.Properties);
            if (s.HasMetamethods)
            {
                sb += StructIndex(s.CName, s.Metatable, s.Fields, s.Properties);
                sb += StructNewindex(s.CName, s.Metatable, s.Fields, structBindings, s.Properties);
                sb += StructPairs(s.CName, s.Metatable, s.Fields, s.Properties);
            }
            if (s.ExtraMetamethods != null)
            {
                foreach (var mm in s.ExtraMetamethods)
                {
                    sb += mm.Kind switch
                    {
                        "memcmp_eq" => StructEq(s.CName, s.Metatable),
                        "hex_tostring" => StructTostring(s.CName, s.Metatable),
                        _ => ""
                    };
                }
            }
        }

        // Functions
        foreach (var f in spec.Funcs)
        {
            if (f.Params.Any(p => p.CallbackBridge == CallbackBridgeMode.Immediate))
                sb += GenCallbackBridgeCode(f);
            else if (f.Params.Any(p => p.CallbackBridge == CallbackBridgeMode.Persistent))
                sb += GenPersistentCallbackCode(f);
            else
                sb += GenBindingFunc(f);
        }

        // Array adapters
        foreach (var aa in spec.ArrayAdapters)
            sb += GenArrayAdapterFunc(spec.ModuleName, aa);

        // Event adapters
        foreach (var ea in spec.EventAdapters)
            sb += GenEventAdapterFunc(spec.ModuleName, ea);

        // Opaque types
        foreach (var ot in spec.OpaqueTypes)
        {
            sb += OpaqueCheckHelper(ot);
            if (ot.InitFunc != null)
                sb += OpaqueConstructor(ot, structBindings);
            sb += OpaqueDestructor(ot);
            sb += OpaqueDestroyMethod(ot);
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
        var metatables = spec.Structs.Select(s =>
        {
            var extra = new Dictionary<string, string>();
            if (s.ExtraMetamethods != null)
            {
                foreach (var mm in s.ExtraMetamethods)
                {
                    var funcName = mm.Kind switch
                    {
                        "memcmp_eq" => $"l_{s.CName}__eq",
                        "hex_tostring" => $"l_{s.CName}__tostring",
                        _ => (string?)null
                    };
                    if (funcName != null) extra[mm.Name] = funcName;
                }
            }
            return s.HasMetamethods
                ? (s.Metatable, (string?)$"l_{s.CName}__index", (string?)$"l_{s.CName}__newindex", (string?)$"l_{s.CName}__pairs", extra)
                : (s.Metatable, null, null, null, extra);
        }).ToList();
        foreach (var ot in spec.OpaqueTypes)
            metatables.Add((ot.Metatable, null, null, null, new Dictionary<string, string>()));
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
                regEntries.Add((Pipeline.StripPrefix(ot.InitFunc, spec.Prefix), $"l_{ot.CName}_new"));
        }

        // Extra lua regs (before functions for consistent ordering)
        regEntries.AddRange(spec.ExtraLuaRegs);

        // Functions
        foreach (var f in spec.Funcs)
            regEntries.Add((f.LuaName, $"l_{f.CName}"));

        // Array adapters
        foreach (var aa in spec.ArrayAdapters)
            regEntries.Add((aa.LuaName, $"l_{spec.ModuleName}_array_{aa.LuaName}"));

        // Event adapters
        foreach (var ea in spec.EventAdapters)
            regEntries.Add((ea.LuaName, $"l_{spec.ModuleName}_event_{ea.LuaName}"));

        sb += LuaReg(funcArrayName, regEntries);

        // Enum registrations in luaopen
        var enumRegs = spec.Enums.Select(e => $"    register_{e.CName}(L);").ToList();
        if (enumRegs.Count > 0 || spec.OpaqueTypes.Count > 0)
        {
            sb += $$"""
                LUB3D_API int luaopen_{{luaOpenName}}(lua_State *L) {
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

    // ===== C++ モード生成 =====

    private static string GenerateCpp(ModuleSpec spec)
    {
        var sb = CppHeader(spec.CIncludes);

        // Functions
        foreach (var f in spec.Funcs)
            sb += CppFunc(f);

        // Enums
        foreach (var e in spec.Enums)
        {
            var items = e.Items.Select(i => (i.LuaName, i.CConstName));
            sb += Enum(e.CName, e.FieldName, items);
        }

        // LuaReg
        var funcArrayName = spec.EntryPoint != null
            ? $"{spec.EntryPoint.Replace("luaopen_", "")}_funcs"
            : $"{spec.ModuleName.Replace('.', '_')}_funcs";
        var regEntries = spec.Funcs.Select(f => (f.LuaName, $"l_{f.CName}")).ToList();
        regEntries.AddRange(spec.ExtraLuaRegs);
        sb += LuaReg(funcArrayName, regEntries);

        // luaopen — extern "C" void luaopen_X(L, int table_idx)
        var enumRegs = spec.Enums.Select(e => $"    register_{e.CName}(L);").ToList();
        var entryPoint = spec.EntryPoint ?? $"luaopen_{spec.ModuleName.Replace('.', '_')}";
        sb += $$"""
            extern "C" void {{entryPoint}}(lua_State *L, int table_idx) {
                int abs_idx = lua_absindex(L, table_idx);
                lua_pushvalue(L, abs_idx);
                luaL_setfuncs(L, {{funcArrayName}}, 0);
            {{string.Join("\n", enumRegs)}}
                lua_pop(L, 1);
            }
            """;

        return sb;
    }

    /// <summary>
    /// C++ モード関数バインディング
    /// </summary>
    private static string CppFunc(FuncBinding f)
    {
        var sb = $"static int l_{f.CName}(lua_State *L) {{\n";
        var argNames = new List<string>();
        var outputParams = new List<(string name, BindingType type, int idx)>();
        var idx = 1;

        foreach (var p in f.Params)
        {
            if (p.IsOutput)
            {
                sb += GenCppOutputParamDecl(p, idx, out var argExpr);
                argNames.Add(argExpr);
                outputParams.Add((p.Name, p.Type, idx));
                idx++;
            }
            else if (p.IsOptional)
            {
                sb += GenCppOptionalParamDecl(p, idx);
                argNames.Add(p.Name);
                idx++;
            }
            else
            {
                sb += GenCppParamDecl(p, idx);
                argNames.Add(p.Name);
                idx++;
            }
        }

        var callName = f.CppFuncName ?? f.CName;
        var callExpr = f.CppNamespace != null
            ? $"{f.CppNamespace}::{callName}({string.Join(", ", argNames)})"
            : $"{callName}({string.Join(", ", argNames)})";

        var retCount = 0;

        // Return value handling
        if (f.ReturnType is not BindingType.Void)
        {
            sb += GenCppReturnCapture(f.ReturnType, callExpr);
            retCount++;
        }
        else
        {
            sb += $"    {callExpr};\n";
        }

        // Output params push
        foreach (var (name, type, tableIdx) in outputParams)
        {
            sb += GenCppOutputPush(name, type, tableIdx);
            retCount++;
        }

        sb += $"    return {retCount};\n}}\n\n";
        return sb;
    }

    private static string GenCppParamDecl(ParamBinding p, int idx) => p.Type switch
    {
        BindingType.Int => $"    int {p.Name} = (int)luaL_checkinteger(L, {idx});\n",
        BindingType.Int64 => $"    int64_t {p.Name} = (int64_t)luaL_checkinteger(L, {idx});\n",
        BindingType.UInt32 => $"    uint32_t {p.Name} = (uint32_t)luaL_checkinteger(L, {idx});\n",
        BindingType.UInt64 => $"    uint64_t {p.Name} = (uint64_t)luaL_checkinteger(L, {idx});\n",
        BindingType.Size => $"    size_t {p.Name} = (size_t)luaL_checkinteger(L, {idx});\n",
        BindingType.Float => $"    float {p.Name} = (float)luaL_checknumber(L, {idx});\n",
        BindingType.Double => $"    double {p.Name} = (double)luaL_checknumber(L, {idx});\n",
        BindingType.Bool => $"    bool {p.Name} = lua_toboolean(L, {idx});\n",
        BindingType.Str => $"    const char* {p.Name} = luaL_checkstring(L, {idx});\n",
        BindingType.Enum(var cName, _) => $"    {cName} {p.Name} = ({cName})luaL_checkinteger(L, {idx});\n",
        BindingType.VoidPtr => $"    void* {p.Name} = lua_touserdata(L, {idx});\n",
        BindingType.Vec2 => $$"""
                luaL_checktype(L, {{idx}}, LUA_TTABLE);
                ImVec2 {{p.Name}};
                lua_rawgeti(L, {{idx}}, 1); {{p.Name}}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                lua_rawgeti(L, {{idx}}, 2); {{p.Name}}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);

            """,
        BindingType.Vec4 => $$"""
                luaL_checktype(L, {{idx}}, LUA_TTABLE);
                ImVec4 {{p.Name}};
                lua_rawgeti(L, {{idx}}, 1); {{p.Name}}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                lua_rawgeti(L, {{idx}}, 2); {{p.Name}}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                lua_rawgeti(L, {{idx}}, 3); {{p.Name}}.z = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                lua_rawgeti(L, {{idx}}, 4); {{p.Name}}.w = (float)lua_tonumber(L, -1); lua_pop(L, 1);

            """,
        BindingType.FloatArray(var len) => GenCppFloatArrayInput(p.Name, idx, len, required: true),
        _ => $"    /* unsupported param type for {p.Name} */\n"
    };

    private static string GenCppOptionalParamDecl(ParamBinding p, int idx) => p.Type switch
    {
        BindingType.Int => $"    int {p.Name} = (int)luaL_optinteger(L, {idx}, 0);\n",
        BindingType.Float => $"    float {p.Name} = (float)luaL_optnumber(L, {idx}, 0.0);\n",
        BindingType.Double => $"    double {p.Name} = (double)luaL_optnumber(L, {idx}, 0.0);\n",
        BindingType.Bool => $"    bool {p.Name} = lua_toboolean(L, {idx});\n",
        BindingType.Str => $"    const char* {p.Name} = luaL_optstring(L, {idx}, NULL);\n",
        BindingType.Enum(var cName, _) => $"    {cName} {p.Name} = ({cName})luaL_optinteger(L, {idx}, 0);\n",
        BindingType.Vec2 => $$"""
                ImVec2 {{p.Name}} = ImVec2(0, 0);
                if (lua_istable(L, {{idx}})) {
                    lua_rawgeti(L, {{idx}}, 1); {{p.Name}}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                    lua_rawgeti(L, {{idx}}, 2); {{p.Name}}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                }

            """,
        BindingType.Vec4 => $$"""
                ImVec4 {{p.Name}} = ImVec4(0, 0, 0, 0);
                if (lua_istable(L, {{idx}})) {
                    lua_rawgeti(L, {{idx}}, 1); {{p.Name}}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                    lua_rawgeti(L, {{idx}}, 2); {{p.Name}}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                    lua_rawgeti(L, {{idx}}, 3); {{p.Name}}.z = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                    lua_rawgeti(L, {{idx}}, 4); {{p.Name}}.w = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                }

            """,
        BindingType.FloatArray(var len) => GenCppFloatArrayInput(p.Name, idx, len, required: false),
        _ => $"    /* unsupported optional param type for {p.Name} */\n"
    };

    private static string GenCppOutputParamDecl(ParamBinding p, int idx, out string argExpr)
    {
        // Output params: declare local, pass pointer
        switch (p.Type)
        {
            case BindingType.Bool:
                // Optional bool* (e.g. p_open) → pass pointer (can be NULL)
                // Required bool* (e.g. Checkbox v) → pass &val (always valid)
                argExpr = p.IsOptional ? p.Name : $"&{p.Name}_val";
                return $$"""
                        bool {{p.Name}}_val = true;
                        bool* {{p.Name}} = NULL;
                        if (lua_isboolean(L, {{idx}})) {
                            {{p.Name}}_val = lua_toboolean(L, {{idx}});
                            {{p.Name}} = &{{p.Name}}_val;
                        }

                    """;
            case BindingType.Int:
                argExpr = $"&{p.Name}_val";
                return $$"""
                        int {{p.Name}}_val = 0;
                        if (lua_isinteger(L, {{idx}})) {{p.Name}}_val = (int)lua_tointeger(L, {{idx}});

                    """;
            case BindingType.Float:
                argExpr = $"&{p.Name}_val";
                return $$"""
                        float {{p.Name}}_val = 0.0f;
                        if (lua_isnumber(L, {{idx}})) {{p.Name}}_val = (float)lua_tonumber(L, {{idx}});

                    """;
            case BindingType.UInt32:
                argExpr = $"&{p.Name}_val";
                return $$"""
                        unsigned int {{p.Name}}_val = 0;
                        if (lua_isinteger(L, {{idx}})) {{p.Name}}_val = (unsigned int)lua_tointeger(L, {{idx}});

                    """;
            case BindingType.Double:
                argExpr = $"&{p.Name}_val";
                return $$"""
                        double {{p.Name}}_val = 0.0;
                        if (lua_isnumber(L, {{idx}})) {{p.Name}}_val = (double)lua_tonumber(L, {{idx}});

                    """;
            case BindingType.FloatArray(var len):
                argExpr = p.Name;
                return GenCppFloatArrayInput(p.Name, idx, len, required: true);
            default:
                argExpr = p.Name;
                return $"    /* unsupported output param type for {p.Name} */\n";
        }
    }

    private static string GenCppOutputPush(string name, BindingType type, int tableIdx) => type switch
    {
        BindingType.Bool => $"    lua_pushboolean(L, {name}_val);\n",
        BindingType.Int => $"    lua_pushinteger(L, {name}_val);\n",
        BindingType.UInt32 => $"    lua_pushinteger(L, {name}_val);\n",
        BindingType.Float => $"    lua_pushnumber(L, {name}_val);\n",
        BindingType.Double => $"    lua_pushnumber(L, {name}_val);\n",
        BindingType.FloatArray(var len) => GenCppFloatArrayOutput(name, tableIdx, len),
        _ => $"    /* unsupported output push for {name} */\n"
    };

    private static string GenCppFloatArrayInput(string name, int idx, int len, bool required)
    {
        var sb = $"    float {name}[{len}] = {{0}};\n";
        if (required)
            sb += $"    luaL_checktype(L, {idx}, LUA_TTABLE);\n";
        else
            sb += $"    if (lua_istable(L, {idx}))\n";
        var indent = required ? "    " : "        ";
        if (!required) sb += "    {\n";
        for (var i = 0; i < len; i++)
            sb += $"{indent}lua_rawgeti(L, {idx}, {i + 1}); {name}[{i}] = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n";
        if (!required) sb += "    }\n";
        return sb;
    }

    private static string GenCppFloatArrayOutput(string name, int tableIdx, int len)
    {
        var sb = "";
        // Write modified values back to the input table
        for (var i = 0; i < len; i++)
            sb += $"    lua_pushnumber(L, {name}[{i}]); lua_rawseti(L, {tableIdx}, {i + 1});\n";
        // Push the modified table as return value
        sb += $"    lua_pushvalue(L, {tableIdx});\n";
        return sb;
    }

    private static string GenCppReturnCapture(BindingType retType, string callExpr) => retType switch
    {
        BindingType.Int => $"    lua_pushinteger(L, {callExpr});\n",
        BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64 or BindingType.Size
            => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n",
        BindingType.Bool => $"    lua_pushboolean(L, {callExpr});\n",
        BindingType.Float => $"    lua_pushnumber(L, {callExpr});\n",
        BindingType.Double => $"    lua_pushnumber(L, (lua_Number){callExpr});\n",
        BindingType.Str => $"    lua_pushstring(L, {callExpr});\n",
        BindingType.Enum(_, _) => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n",
        BindingType.VoidPtr => $"    lua_pushlightuserdata(L, (void*){callExpr});\n",
        BindingType.Vec2 => $$"""
                ImVec2 _result = {{callExpr}};
                lua_newtable(L);
                lua_pushnumber(L, _result.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, _result.y); lua_rawseti(L, -2, 2);

            """,
        BindingType.Vec4 => $$"""
                ImVec4 _result = {{callExpr}};
                lua_newtable(L);
                lua_pushnumber(L, _result.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, _result.y); lua_rawseti(L, -2, 2);
                lua_pushnumber(L, _result.z); lua_rawseti(L, -2, 3);
                lua_pushnumber(L, _result.w); lua_rawseti(L, -2, 4);

            """,
        _ => $"    {callExpr};\n"
    };

    /// <summary>
    /// AllowStringInit 構造体コンストラクタ (string / table 両対応)
    /// </summary>
    private static string SgRangeNew(string structName, string metatable, IEnumerable<FieldBinding> fields,
        Dictionary<string, StructBinding> structBindings, IEnumerable<PropertyBinding>? properties = null)
    {
        var fieldInits = string.Join("\n", fields.Select(f => GenBindingFieldInit(f, structBindings)));
        var extraUV = (properties ?? []).Count(p => p.SetterCode != null);
        var nuvalue = 1 + extraUV;
        return $$"""
            static int l_{{structName}}_new(lua_State *L) {
                {{structName}}* ud = ({{structName}}*)lua_newuserdatauv(L, sizeof({{structName}}), {{nuvalue}});
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

    private static string OpaqueCheckHelper(OpaqueTypeBinding ot) => $$"""
        static {{ot.CName}}* check_{{ot.CName}}(lua_State *L, int idx) {
            {{ot.CName}}** pp = ({{ot.CName}}**)luaL_checkudata(L, idx, "{{ot.Metatable}}");
            if (*pp == NULL) luaL_error(L, "{{ot.CName}} already freed");
            return *pp;
        }

        """;

    private static string OpaqueConstructor(OpaqueTypeBinding ot, Dictionary<string, StructBinding> structBindings)
    {
        // Check if config struct has a binding (metatable) we can look up
        var configMetatable = ot.ConfigType != null && structBindings.TryGetValue(ot.ConfigType, out var configStruct)
            ? configStruct.Metatable : null;

        string configInit;
        if (ot.ConfigInitFunc != null && ot.ConfigType != null && configMetatable != null)
        {
            // Config struct has a binding: accept optional userdata argument
            configInit = $$"""
                    {{ot.ConfigType}} config;
                    if (lua_isuserdata(L, 1)) {
                        config = *({{ot.ConfigType}}*)luaL_checkudata(L, 1, "{{configMetatable}}");
                    } else {
                        config = {{ot.ConfigInitFunc}}();
                    }

                """;
        }
        else if (ot.ConfigInitFunc != null && ot.ConfigType != null)
        {
            configInit = $"    {ot.ConfigType} config = {ot.ConfigInitFunc}();\n";
        }
        else
        {
            configInit = "";
        }

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
        var nuv = ot.Dependencies.Count;
        var depCode = "";
        foreach (var dep in ot.Dependencies)
        {
            depCode += $"    lua_pushvalue(L, {dep.ConstructorArgIndex});\n";
            depCode += $"    lua_setiuservalue(L, -2, {dep.UservalueSlot});\n";
        }
        return $$"""
            static int l_{{ot.CName}}_new(lua_State *L) {
                {{ot.CName}}* p = ({{ot.CName}}*)malloc(sizeof({{ot.CName}}));
                memset(p, 0, sizeof({{ot.CName}}));
            {{configInit}}{{initCall}}
                {{ot.CName}}** pp = ({{ot.CName}}**)lua_newuserdatauv(L, sizeof({{ot.CName}}*), {{nuv}});
                *pp = p;
                luaL_setmetatable(L, "{{ot.Metatable}}");
            {{depCode}}    return 1;
            }

            """;
    }

    private static string OpaqueDestructor(OpaqueTypeBinding ot)
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

    private static string OpaqueDestroyMethod(OpaqueTypeBinding ot)
    {
        if (ot.UninitFunc == null) return "";
        var uninitCall = $"        {ot.UninitFunc}(*pp);\n";
        return $$"""
            static int l_{{ot.CName}}_destroy(lua_State *L) {
                {{ot.CName}}** pp = ({{ot.CName}}**)luaL_checkudata(L, 1, "{{ot.Metatable}}");
                if (*pp != NULL) {
            {{uninitCall}}        free(*pp);
                    *pp = NULL;
                }
                return 0;
            }

            """;
    }

    private static string OpaqueMethod(OpaqueTypeBinding ot, MethodBinding m)
    {
        var paramDecls = new List<string>
        {
            $"    {ot.CName}* self = check_{ot.CName}(L, 1);"
        };
        foreach (var (p, i) in m.Params.Select((p, i) => (p, i)))
        {
            var idx = i + 2; // self is 1
            paramDecls.Add(GenBindingParamDecl(p, idx));
        }
        var argNames = new List<string> { "self" };
        argNames.AddRange(m.Params.Select(p => p.Name));
        var args = string.Join(", ", argNames);

        var call = GenBindingReturnPush(m.ReturnType, $"{m.CName}({args})");

        return $$"""
            static int l_{{m.CName}}(lua_State *L) {
            {{string.Join("\n", paramDecls)}}
            {{call}}
            }

            """;
    }

    private static string OpaqueMethodTable(OpaqueTypeBinding ot)
    {
        var allEntries = new List<string>();
        if (ot.UninitFunc != null)
            allEntries.Add($"    {{\"destroy\", l_{ot.CName}_destroy}},");
        allEntries.AddRange(ot.Methods.Select(m => $"    {{\"{m.LuaName}\", l_{m.CName}}},"));
        return $$"""
            static const luaL_Reg {{ot.CName}}_methods[] = {
            {{string.Join("\n", allEntries)}}
                {NULL, NULL}
            };

            """;
    }

    private static string RegisterOpaqueMetatables(
        List<OpaqueTypeBinding> opaqueTypes,
        List<(string metatable, string? indexFunc, string? newindexFunc, string? pairsFunc, Dictionary<string, string> extraMetamethods)> metatables)
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
            foreach (var (name, func) in m.extraMetamethods)
                sb += $"\n    lua_pushcfunction(L, {func}); lua_setfield(L, -2, \"{name}\");";
            sb += "\n    lua_pop(L, 1);";
            return sb;
        });
        return $$"""
            static void register_metatables(lua_State *L) {
            {{string.Join("\n", lines)}}
            }

            """;
    }

    // ===== BindingType ベース パラメータ/戻り値生成 =====

    private static string GenBindingParamDecl(ParamBinding p, int idx) => p.Type switch
    {
        BindingType.Custom(_, _, _, var cc, _, _) when cc != null =>
            cc.Replace("{idx}", idx.ToString()).Replace("{name}", p.Name),
        BindingType.Int => $"    int {p.Name} = (int)luaL_checkinteger(L, {idx});",
        BindingType.Int64 => $"    int64_t {p.Name} = (int64_t)luaL_checkinteger(L, {idx});",
        BindingType.UInt32 => $"    uint32_t {p.Name} = (uint32_t)luaL_checkinteger(L, {idx});",
        BindingType.UInt64 => $"    uint64_t {p.Name} = (uint64_t)luaL_checkinteger(L, {idx});",
        BindingType.Size => $"    size_t {p.Name} = (size_t)luaL_checkinteger(L, {idx});",
        BindingType.UIntPtr => $"    uintptr_t {p.Name} = (uintptr_t)luaL_checkinteger(L, {idx});",
        BindingType.IntPtr => $"    intptr_t {p.Name} = (intptr_t)luaL_checkinteger(L, {idx});",
        BindingType.Float => $"    float {p.Name} = (float)luaL_checknumber(L, {idx});",
        BindingType.Double => $"    double {p.Name} = (double)luaL_checknumber(L, {idx});",
        BindingType.Bool => $"    bool {p.Name} = lua_toboolean(L, {idx});",
        BindingType.Str => $"    const char* {p.Name} = luaL_checkstring(L, {idx});",
        BindingType.ConstPtr(BindingType.Str) => $"    const char* {p.Name} = luaL_checkstring(L, {idx});",
        BindingType.Enum(var eName, _) => $"    {eName} {p.Name} = ({eName})luaL_checkinteger(L, {idx});",
        BindingType.VoidPtr => $"    void* {p.Name} = lua_touserdata(L, {idx});",
        BindingType.Ptr(BindingType.Void) => $"    void* {p.Name} = lua_touserdata(L, {idx});",
        BindingType.ConstPtr(BindingType.Void) => $"    const void* {p.Name} = lua_touserdata(L, {idx});",
        BindingType.Ptr(BindingType.Struct(var cName, var mt, _)) =>
            $"    {cName}* {p.Name} = ({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        BindingType.ConstPtr(BindingType.Struct(var cName, var mt, _)) =>
            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        BindingType.Ptr(BindingType.Custom(var cName, _, _, _, _, _)) =>
            $"    {cName}* {p.Name} = ({cName}*)luaL_checkudata(L, {idx}, \"\");",
        BindingType.ConstPtr(BindingType.Custom(var cName, _, _, _, _, _)) =>
            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"\");",
        BindingType.Struct(var cName, var mt, _) =>
            $"    {cName} {p.Name} = *({cName}*)luaL_checkudata(L, {idx}, \"{mt}\");",
        BindingType.ValueStruct(var cType, _, var vsFields, _) =>
            GenValueStructParamDecl(p.Name, idx, cType, vsFields),
        BindingType.ValueStructArray(var cType, _, var vsFields, var maxElems) =>
            GenValueStructArrayParamDecl(p.Name, idx, cType, vsFields, maxElems),
        BindingType.Ptr(BindingType.ValueStruct(var cName, _, _, _)) =>
            $"    {cName}* {p.Name} = ({cName}*)luaL_checkudata(L, {idx}, \"\");",
        BindingType.ConstPtr(BindingType.ValueStruct(var cName, _, _, _)) =>
            $"    const {cName}* {p.Name} = (const {cName}*)luaL_checkudata(L, {idx}, \"\");",
        _ => throw new InvalidOperationException($"Unsupported parameter type: {p.Type} for '{p.Name}'")
    };

    private static string GenBindingReturnPush(BindingType ret, string callExpr) => ret switch
    {
        BindingType.Void => $"    {callExpr};\n    return 0;",
        BindingType.Int => $"    lua_pushinteger(L, {callExpr});\n    return 1;",
        BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64 or BindingType.Size
            or BindingType.UIntPtr or BindingType.IntPtr
            => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n    return 1;",
        BindingType.Bool => $"    lua_pushboolean(L, {callExpr});\n    return 1;",
        BindingType.Float => $"    lua_pushnumber(L, {callExpr});\n    return 1;",
        BindingType.Double => $"    lua_pushnumber(L, (lua_Number){callExpr});\n    return 1;",
        BindingType.Str or BindingType.ConstPtr(BindingType.Str)
            => $"    lua_pushstring(L, {callExpr});\n    return 1;",
        BindingType.VoidPtr or BindingType.Ptr(BindingType.Void)
            or BindingType.ConstPtr(BindingType.Void)
            => $"    lua_pushlightuserdata(L, (void*){callExpr});\n    return 1;",
        BindingType.Enum(_, _)
            => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n    return 1;",
        BindingType.Struct(var retCName, var retMt, _) =>
            $"    {retCName} result = {callExpr};\n" +
            $"    {retCName}* ud = ({retCName}*)lua_newuserdatauv(L, sizeof({retCName}), 0);\n" +
            $"    *ud = result;\n" +
            $"    luaL_setmetatable(L, \"{retMt}\");\n" +
            $"    return 1;",
        BindingType.ValueStruct(var cType, _, var vsFields, _) =>
            GenValueStructReturnPush(callExpr, cType, vsFields),
        BindingType.Custom(_, _, _, _, var pushCode, _) when pushCode != null =>
            $"    {pushCode.Replace("{value}", callExpr)}\n    return 1;",
        BindingType.Custom(_, _, _, _, null, _) =>
            $"    {callExpr};\n    return 0;",
        _ => throw new InvalidOperationException($"Unsupported return type: {ret}")
    };

    private static string GenBindingFunc(FuncBinding f)
    {
        // Output param がある場合は専用パスへ
        if (f.Params.Any(p => p.IsOutput))
            return GenBindingFuncWithOutput(f);

        var paramDecls = string.Join("\n", f.Params.Select((p, i) =>
            GenBindingParamDecl(p, i + 1)).Where(s => s != ""));
        var argNames = string.Join(", ", f.Params.Select(p => p.Name));

        // ValueStructArray + Int count バリデーション
        var countChecks = new List<string>();
        for (int i = 0; i < f.Params.Count - 1; i++)
        {
            if (f.Params[i].Type is BindingType.ValueStructArray && f.Params[i + 1].Type is BindingType.Int)
            {
                var arrName = f.Params[i].Name;
                var cntName = f.Params[i + 1].Name;
                var cntIdx = i + 2; // 1-based Lua index
                countChecks.Add($"    luaL_argcheck(L, {cntName} >= 0 && {cntName} <= _{arrName}_len, {cntIdx}, \"count out of range\");");
            }
        }
        var countCheckStr = countChecks.Count > 0 ? "\n" + string.Join("\n", countChecks) : "";

        // PostCallPatch: Struct return の場合、*ud = result と luaL_setmetatable の間にパッチを挿入
        if (f.PostCallPatches is { Count: > 0 } && f.ReturnType is BindingType.Struct(var retCName, var retMt, _))
        {
            var patchLines = string.Join("\n", f.PostCallPatches.Select(p =>
                $"    ud->{p.FieldName} = {p.CExpression};"));
            return $$"""
                static int l_{{f.CName}}(lua_State *L) {
                {{paramDecls}}{{countCheckStr}}
                    {{retCName}} result = {{f.CName}}({{argNames}});
                    {{retCName}}* ud = ({{retCName}}*)lua_newuserdatauv(L, sizeof({{retCName}}), 0);
                    *ud = result;
                {{patchLines}}
                    luaL_setmetatable(L, "{{retMt}}");
                    return 1;
                }

                """;
        }

        var call = GenBindingReturnPush(f.ReturnType, $"{f.CName}({argNames})");

        return $$"""
            static int l_{{f.CName}}(lua_State *L) {
            {{paramDecls}}{{countCheckStr}}
            {{call}}
            }

            """;
    }

    /// <summary>
    /// IsOutput パラメータを含む C モード関数バインディング
    /// </summary>
    private static string GenBindingFuncWithOutput(FuncBinding f)
    {
        var sb = $"static int l_{f.CName}(lua_State *L) {{\n";
        var argNames = new List<string>();
        var outputParams = new List<(string name, BindingType type)>();
        var idx = 1;

        foreach (var p in f.Params)
        {
            if (p.IsOutput)
            {
                sb += GenCOutputParamDecl(p, idx, out var argExpr);
                argNames.Add(argExpr);
                outputParams.Add((p.Name, p.Type));
                idx++;
            }
            else
            {
                var decl = GenBindingParamDecl(p, idx);
                if (decl != "") sb += decl + "\n";
                argNames.Add(p.Name);
                idx++;
            }
        }

        var callExpr = $"{f.CName}({string.Join(", ", argNames)})";
        var retCount = 0;

        // Return value handling
        if (f.ReturnType is not BindingType.Void)
        {
            sb += GenCReturnCapture(f.ReturnType, callExpr);
            retCount++;
        }
        else
        {
            sb += $"    {callExpr};\n";
        }

        // Output params push
        foreach (var (name, type) in outputParams)
        {
            sb += GenCOutputPush(name, type);
            retCount++;
        }

        sb += $"    return {retCount};\n}}\n\n";
        return sb;
    }

    /// <summary>
    /// C モード output param 宣言: ローカル変数宣言 + Lua スタックから初期値読み取り
    /// </summary>
    private static string GenCOutputParamDecl(ParamBinding p, int idx, out string argExpr)
    {
        switch (p.Type)
        {
            case BindingType.Bool:
                argExpr = $"&{p.Name}_val";
                return $"    bool {p.Name}_val = lua_toboolean(L, {idx});\n";
            case BindingType.Int:
                argExpr = $"&{p.Name}_val";
                return $"    int {p.Name}_val = (int)luaL_optinteger(L, {idx}, 0);\n";
            case BindingType.Float:
                argExpr = $"&{p.Name}_val";
                return $"    float {p.Name}_val = (float)luaL_optnumber(L, {idx}, 0.0);\n";
            case BindingType.UInt32:
                argExpr = $"&{p.Name}_val";
                return $"    unsigned int {p.Name}_val = (unsigned int)luaL_optinteger(L, {idx}, 0);\n";
            case BindingType.Double:
                argExpr = $"&{p.Name}_val";
                return $"    double {p.Name}_val = (double)luaL_optnumber(L, {idx}, 0.0);\n";
            default:
                argExpr = p.Name;
                return $"    /* unsupported output param type for {p.Name} */\n";
        }
    }

    /// <summary>
    /// C モード output param push: 関数呼び出し後に output 値を Lua スタックへ push
    /// </summary>
    private static string GenCOutputPush(string name, BindingType type) => type switch
    {
        BindingType.Bool => $"    lua_pushboolean(L, {name}_val);\n",
        BindingType.Int => $"    lua_pushinteger(L, {name}_val);\n",
        BindingType.UInt32 => $"    lua_pushinteger(L, {name}_val);\n",
        BindingType.Float => $"    lua_pushnumber(L, {name}_val);\n",
        BindingType.Double => $"    lua_pushnumber(L, {name}_val);\n",
        _ => $"    /* unsupported output push for {name} */\n"
    };

    /// <summary>
    /// C モード戻り値キャプチャ: 関数呼び出し結果を変数に格納 + Lua スタックへ push
    /// </summary>
    private static string GenCReturnCapture(BindingType ret, string callExpr) => ret switch
    {
        BindingType.Int => $"    lua_pushinteger(L, {callExpr});\n",
        BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64 or BindingType.Size
            or BindingType.UIntPtr or BindingType.IntPtr
            => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n",
        BindingType.Bool => $"    lua_pushboolean(L, {callExpr});\n",
        BindingType.Float => $"    lua_pushnumber(L, {callExpr});\n",
        BindingType.Double => $"    lua_pushnumber(L, (lua_Number){callExpr});\n",
        BindingType.Str or BindingType.ConstPtr(BindingType.Str)
            => $"    lua_pushstring(L, {callExpr});\n",
        BindingType.VoidPtr or BindingType.Ptr(BindingType.Void) or BindingType.ConstPtr(BindingType.Void)
            => $"    lua_pushlightuserdata(L, (void*){callExpr});\n",
        BindingType.Enum(_, _) => $"    lua_pushinteger(L, (lua_Integer){callExpr});\n",
        BindingType.Struct(var cName, var mt, _) =>
            $"    {cName} _result = {callExpr};\n" +
            $"    {cName}* ud = ({cName}*)lua_newuserdatauv(L, sizeof({cName}), 0);\n" +
            $"    *ud = _result;\n" +
            $"    luaL_setmetatable(L, \"{mt}\");\n",
        BindingType.ValueStruct(var cType, _, var vsFields, _) =>
            GenValueStructReturnCapture(callExpr, cType, vsFields),
        BindingType.Custom(_, _, _, _, var pushCode, _) when pushCode != null =>
            $"    {pushCode.Replace("{value}", callExpr)}\n",
        _ => $"    {callExpr};\n"
    };

    // ===== Immediate Callback Bridge =====

    /// <summary>
    /// Immediate callback bridge: context struct + trampoline + binding func を生成
    /// </summary>
    private static string GenCallbackBridgeCode(FuncBinding f)
    {
        var cbParam = f.Params.First(p => p.CallbackBridge == CallbackBridgeMode.Immediate);
        var cbType = (BindingType.Callback)cbParam.Type;
        var ctxName = $"{f.CName}_cb_ctx";
        var trampolineName = $"{f.CName}_trampoline";

        var sb = "";
        sb += GenContextStruct(ctxName);
        sb += GenTrampolineFunc(f.CName, ctxName, trampolineName, cbType);
        sb += GenBindingFuncWithCallback(f, cbParam, ctxName, trampolineName);
        return sb;
    }

    private static string GenContextStruct(string ctxName, bool isPersistent = false)
    {
        var field = isPersistent ? "callback_ref" : "callback_idx";
        return $"typedef struct {{ lua_State* L; int {field}; }} {ctxName};\n\n";
    }

    private static string GenTrampolineFunc(string funcName, string ctxName, string trampolineName,
        BindingType.Callback cbType, bool isPersistent = false)
    {
        var retCType = cbType.Ret switch
        {
            BindingType.Bool => "bool",
            BindingType.Float => "float",
            _ => "bool"
        };

        // Build C parameter list
        var cParams = new List<string>();
        foreach (var (name, type) in cbType.Params)
            cParams.Add($"{BindingTypeToString(type)} {name}");
        cParams.Add("void* context");

        var sb = $"static {retCType} {trampolineName}({string.Join(", ", cParams)}) {{\n";

        if (isPersistent)
        {
            var defaultRet = cbType.Ret is BindingType.Float ? "1.0f" : "true";
            sb += "    (void)context;\n";
            sb += $"    {ctxName}* ctx = &_{funcName}_static_ctx;\n";
            sb += $"    if (!ctx->L || ctx->callback_ref == LUA_NOREF) return {defaultRet};\n";
            sb += "    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->callback_ref);\n";
        }
        else
        {
            sb += $"    {ctxName}* ctx = ({ctxName}*)context;\n";
            sb += "    lua_pushvalue(ctx->L, ctx->callback_idx);\n";
        }

        // Push each callback argument onto Lua stack
        foreach (var (name, type) in cbType.Params)
            sb += GenCallbackArgPush(type, name);

        var argCount = cbType.Params.Count;
        sb += $"    lua_call(ctx->L, {argCount}, 1);\n";

        // Extract return value
        sb += GenCallbackReturnExtract(cbType.Ret);

        sb += "}\n\n";
        return sb;
    }

    /// <summary>C 値を Lua スタックへ push (trampoline 内用)</summary>
    private static string GenCallbackArgPush(BindingType type, string varName) => type switch
    {
        BindingType.Struct(var cName, _, var mt) =>
            $"    {cName}* _ud_{varName} = ({cName}*)lua_newuserdatauv(ctx->L, sizeof({cName}), 0);\n" +
            $"    *_ud_{varName} = {varName};\n" +
            $"    luaL_setmetatable(ctx->L, \"{mt}\");\n",
        BindingType.ValueStruct(_, _, var vsFields, _) =>
            GenCallbackValueStructPush(varName, vsFields),
        BindingType.Float =>
            $"    lua_pushnumber(ctx->L, {varName});\n",
        BindingType.Double =>
            $"    lua_pushnumber(ctx->L, {varName});\n",
        BindingType.Bool =>
            $"    lua_pushboolean(ctx->L, {varName});\n",
        BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
            or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr =>
            $"    lua_pushinteger(ctx->L, (lua_Integer){varName});\n",
        BindingType.Str =>
            $"    lua_pushstring(ctx->L, {varName});\n",
        _ => $"    lua_pushlightuserdata(ctx->L, (void*){varName});\n"
    };

    private static string GenCallbackValueStructPush(string varName, List<BindingType.ValueStructField> fields)
    {
        var sb = "    lua_newtable(ctx->L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"    lua_pushnumber(ctx->L, {varName}.{acc}); lua_rawseti(ctx->L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "    lua_newtable(ctx->L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"    lua_pushnumber(ctx->L, {varName}.{acc}.{sub}); lua_rawseti(ctx->L, -2, {si});\n";
                        si++;
                    }
                    sb += $"    lua_rawseti(ctx->L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        return sb;
    }

    /// <summary>Lua 戻り値を C 型に変換し return</summary>
    private static string GenCallbackReturnExtract(BindingType? retType) => retType switch
    {
        BindingType.Bool =>
            "    bool _cb_ret = lua_toboolean(ctx->L, -1);\n" +
            "    lua_pop(ctx->L, 1);\n" +
            "    return _cb_ret;\n",
        BindingType.Float =>
            "    float _cb_ret = (float)lua_tonumber(ctx->L, -1);\n" +
            "    lua_pop(ctx->L, 1);\n" +
            "    return _cb_ret;\n",
        _ =>
            "    bool _cb_ret = lua_toboolean(ctx->L, -1);\n" +
            "    lua_pop(ctx->L, 1);\n" +
            "    return _cb_ret;\n"
    };

    // ===== Persistent Callback Bridge =====

    /// <summary>
    /// Persistent callback bridge: static context + trampoline + setter 関数を生成
    /// </summary>
    private static string GenPersistentCallbackCode(FuncBinding f)
    {
        var cbParam = f.Params.First(p => p.CallbackBridge == CallbackBridgeMode.Persistent);
        var cbType = (BindingType.Callback)cbParam.Type;
        var ctxName = $"{f.CName}_cb_ctx";
        var trampolineName = $"{f.CName}_trampoline";

        var sb = "";
        sb += GenContextStruct(ctxName, isPersistent: true);
        sb += $"static {ctxName} _{f.CName}_static_ctx = {{ NULL, LUA_NOREF }};\n\n";
        sb += GenTrampolineFunc(f.CName, ctxName, trampolineName, cbType, isPersistent: true);
        sb += GenPersistentSetter(f, cbParam, ctxName, trampolineName);
        return sb;
    }

    /// <summary>
    /// Persistent callback setter: nil → unregister, function → register + C setter 呼び出し
    /// </summary>
    private static string GenPersistentSetter(FuncBinding f, ParamBinding cbParam, string ctxName, string trampolineName)
    {
        var sb = $"static int l_{f.CName}(lua_State *L) {{\n";
        var preCallbackArgs = new List<string>();
        var idx = 1;

        // Non-callback parameters before the callback
        foreach (var p in f.Params)
        {
            if (p.CallbackBridge == CallbackBridgeMode.Persistent)
                break;
            sb += GenBindingParamDecl(p, idx) + "\n";
            preCallbackArgs.Add(p.Name);
            idx++;
        }

        // Unref previous callback if any
        sb += $"    if (_{f.CName}_static_ctx.callback_ref != LUA_NOREF) {{\n";
        sb += $"        luaL_unref(L, LUA_REGISTRYINDEX, _{f.CName}_static_ctx.callback_ref);\n";
        sb += $"        _{f.CName}_static_ctx.callback_ref = LUA_NOREF;\n";
        sb += $"        _{f.CName}_static_ctx.L = NULL;\n";
        sb += "    }\n";

        // Build arg list strings
        var preArgs = preCallbackArgs.Count > 0 ? string.Join(", ", preCallbackArgs) + ", " : "";

        // nil branch → unregister
        sb += $"    if (lua_isnil(L, {idx}) || lua_isnone(L, {idx})) {{\n";
        sb += $"        {f.CName}({preArgs}NULL, NULL);\n";
        sb += "    } else {\n";

        // function branch → register
        sb += $"        luaL_checktype(L, {idx}, LUA_TFUNCTION);\n";
        sb += $"        lua_pushvalue(L, {idx});\n";
        sb += $"        _{f.CName}_static_ctx.callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);\n";
        sb += $"        _{f.CName}_static_ctx.L = L;\n";
        sb += $"        {f.CName}({preArgs}{trampolineName}, NULL);\n";
        sb += "    }\n";
        sb += "    return 0;\n}\n\n";
        return sb;
    }

    /// <summary>callback 付き binding 関数を生成</summary>
    private static string GenBindingFuncWithCallback(FuncBinding f, ParamBinding cbParam, string ctxName, string trampolineName)
    {
        var sb = $"static int l_{f.CName}(lua_State *L) {{\n";
        var argNames = new List<string>();
        var idx = 1;

        foreach (var p in f.Params)
        {
            if (p.CallbackBridge == CallbackBridgeMode.Immediate)
            {
                sb += $"    luaL_checktype(L, {idx}, LUA_TFUNCTION);\n";
                sb += $"    {ctxName} _cb_ctx = {{ L, {idx} }};\n";
                argNames.Add(trampolineName);
                argNames.Add("&_cb_ctx");
                idx++;
            }
            else
            {
                sb += GenBindingParamDecl(p, idx) + "\n";
                argNames.Add(p.Name);
                idx++;
            }
        }

        var args = string.Join(", ", argNames);
        sb += GenBindingReturnPush(f.ReturnType, $"{f.CName}({args})");
        sb += "\n}\n\n";
        return sb;
    }

    // ===== ArrayAdapter 生成 =====

    /// <summary>
    /// 配列アダプタ関数を生成: count → malloc → fill → table → free
    /// </summary>
    private static string GenArrayAdapterFunc(string moduleName, ArrayAdapterBinding aa)
    {
        var funcName = $"l_{moduleName}_array_{aa.LuaName}";
        var sb = $"static int {funcName}(lua_State *L) {{\n";

        // 1. 入力パラメータを decode
        var argNames = new List<string>();
        foreach (var (p, i) in aa.InputParams.Select((p, i) => (p, i)))
        {
            sb += GenBindingParamDecl(p, i + 1) + "\n";
            argNames.Add(p.Name);
        }
        var args = string.Join(", ", argNames);

        // 2. count = CountFunc(inputParams...)
        sb += $"    int _count = {aa.CountFuncCName}({args});\n";

        // 3. ElementType* _buf = malloc(...)
        var elemCType = BindingTypeToString(aa.ElementType);
        sb += $"    {elemCType}* _buf = ({elemCType}*)malloc(_count * sizeof({elemCType}));\n";

        // 4. FillFunc(inputParams..., _buf, _count)
        sb += $"    {aa.FillFuncCName}({args}, _buf, _count);\n";

        // 5. lua_newtable + loop
        sb += "    lua_newtable(L);\n";
        sb += "    for (int _i = 0; _i < _count; _i++) {\n";
        sb += GenArrayAdapterElementPush(aa.ElementType);
        sb += "        lua_rawseti(L, -2, _i + 1);\n";
        sb += "    }\n";

        // 6. free
        sb += "    free(_buf);\n";
        sb += "    return 1;\n}\n\n";
        return sb;
    }

    /// <summary>
    /// 配列アダプタの要素 push コード生成
    /// </summary>
    private static string GenArrayAdapterElementPush(BindingType elemType) => elemType switch
    {
        BindingType.Struct(var cName, var mt, _) =>
            $"        {cName}* _ud = ({cName}*)lua_newuserdatauv(L, sizeof({cName}), 0);\n" +
            $"        *_ud = _buf[_i];\n" +
            $"        luaL_setmetatable(L, \"{mt}\");\n",
        BindingType.ValueStruct(_, _, var vsFields, _) =>
            GenArrayAdapterValueStructPush(vsFields),
        BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
            or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr =>
            "        lua_pushinteger(L, (lua_Integer)_buf[_i]);\n",
        BindingType.Float or BindingType.Double =>
            "        lua_pushnumber(L, (lua_Number)_buf[_i]);\n",
        BindingType.Bool =>
            "        lua_pushboolean(L, _buf[_i]);\n",
        _ => "        lua_pushnil(L); /* unsupported element type */\n"
    };

    private static string GenArrayAdapterValueStructPush(List<BindingType.ValueStructField> fields)
    {
        var sb = "        lua_newtable(L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"        lua_pushnumber(L, _buf[_i].{acc}); lua_rawseti(L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "        lua_newtable(L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"        lua_pushnumber(L, _buf[_i].{acc}.{sub}); lua_rawseti(L, -2, {si});\n";
                        si++;
                    }
                    sb += $"        lua_rawseti(L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        return sb;
    }

    // ===== EventAdapter 生成 =====

    /// <summary>
    /// イベントアダプタ関数を生成: C関数呼出 → outer table → array field ループ → element push
    /// </summary>
    private static string GenEventAdapterFunc(string moduleName, EventAdapterBinding ea)
    {
        var funcName = $"l_{moduleName}_event_{ea.LuaName}";
        var sb = $"static int {funcName}(lua_State *L) {{\n";

        // 1. 入力パラメータを decode
        var argNames = new List<string>();
        foreach (var (p, i) in ea.InputParams.Select((p, i) => (p, i)))
        {
            sb += GenBindingParamDecl(p, i + 1) + "\n";
            argNames.Add(p.Name);
        }
        var args = string.Join(", ", argNames);

        // 2. C 関数呼出
        sb += $"    {ea.CReturnType} _events = {ea.CFuncName}({args});\n";

        // 3. outer table
        sb += "    lua_newtable(L);\n";

        // 4. array field ループ
        foreach (var af in ea.ArrayFields)
        {
            sb += "    lua_newtable(L);\n";
            sb += $"    for (int _i = 0; _i < _events.{af.CCountAccessor}; _i++) {{\n";
            sb += "        lua_newtable(L);\n";
            foreach (var ef in af.ElementFields)
            {
                sb += GenEventElementFieldPush($"_events.{af.CArrayAccessor}[_i]", ef);
            }
            sb += "        lua_rawseti(L, -2, _i + 1);\n";
            sb += "    }\n";
            sb += $"    lua_setfield(L, -2, \"{af.LuaFieldName}\");\n";
        }

        sb += "    return 1;\n}\n\n";
        return sb;
    }

    /// <summary>
    /// イベント要素フィールドの push コード生成
    /// </summary>
    private static string GenEventElementFieldPush(string arrayAccessor, EventElementField ef) => ef.Type switch
    {
        BindingType.Struct(var cName, var mt, _) =>
            $"        {cName}* _ef_{ef.LuaFieldName} = ({cName}*)lua_newuserdatauv(L, sizeof({cName}), 0);\n" +
            $"        *_ef_{ef.LuaFieldName} = {arrayAccessor}.{ef.CAccessor};\n" +
            $"        luaL_setmetatable(L, \"{mt}\");\n" +
            $"        lua_setfield(L, -2, \"{ef.LuaFieldName}\");\n",
        BindingType.ValueStruct(_, _, var vsFields, _) =>
            GenEventValueStructPush(arrayAccessor, ef.CAccessor, ef.LuaFieldName, vsFields),
        BindingType.Float or BindingType.Double =>
            $"        lua_pushnumber(L, {arrayAccessor}.{ef.CAccessor});\n" +
            $"        lua_setfield(L, -2, \"{ef.LuaFieldName}\");\n",
        BindingType.Bool =>
            $"        lua_pushboolean(L, {arrayAccessor}.{ef.CAccessor});\n" +
            $"        lua_setfield(L, -2, \"{ef.LuaFieldName}\");\n",
        BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
            or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr =>
            $"        lua_pushinteger(L, (lua_Integer){arrayAccessor}.{ef.CAccessor});\n" +
            $"        lua_setfield(L, -2, \"{ef.LuaFieldName}\");\n",
        _ => $"        lua_pushnil(L); /* unsupported event element type */\n" +
             $"        lua_setfield(L, -2, \"{ef.LuaFieldName}\");\n"
    };

    /// <summary>
    /// イベント要素の ValueStruct push
    /// </summary>
    private static string GenEventValueStructPush(string arrayAccessor, string cAccessor, string luaFieldName, List<BindingType.ValueStructField> fields)
    {
        var prefix = $"{arrayAccessor}.{cAccessor}";
        var sb = "        lua_newtable(L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"        lua_pushnumber(L, {prefix}.{acc}); lua_rawseti(L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "        lua_newtable(L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"        lua_pushnumber(L, {prefix}.{acc}.{sub}); lua_rawseti(L, -2, {si});\n";
                        si++;
                    }
                    sb += $"        lua_rawseti(L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        sb += $"        lua_setfield(L, -2, \"{luaFieldName}\");\n";
        return sb;
    }

    // ===== BindingType ベース フィールド処理 =====

    private static string BindingTypeToString(BindingType bt) => bt switch
    {
        BindingType.Int => "int",
        BindingType.Int64 => "int64_t",
        BindingType.UInt32 => "uint32_t",
        BindingType.UInt64 => "uint64_t",
        BindingType.Size => "size_t",
        BindingType.UIntPtr => "uintptr_t",
        BindingType.IntPtr => "intptr_t",
        BindingType.Float => "float",
        BindingType.Double => "double",
        BindingType.Bool => "bool",
        BindingType.Str => "const char*",
        BindingType.Void => "void",
        BindingType.Enum(var cName, _) => cName,
        BindingType.Struct(var cName, _, _) => cName,
        BindingType.ValueStruct(var cName, _, _, _) => cName,
        BindingType.Ptr(var inner) => $"{BindingTypeToString(inner)}*",
        BindingType.ConstPtr(var inner) => $"const {BindingTypeToString(inner)}*",
        BindingType.Custom(var cName, _, _, _, _, _) => cName,
        _ => throw new ArgumentException($"Unknown BindingType: {bt}")
    };

    /// <summary>
    /// フィールドの __index getter 式 (BindingType ベース)
    /// </summary>
    private static string GenBindingPush(FieldBinding f)
    {
        return f.Type switch
        {
            BindingType.ValueStruct(_, _, var vsFields, _) =>
                GenValueStructPushExpr($"self->{f.CName}", vsFields),
            BindingType.Custom(_, _, _, _, var pushCode, _) when pushCode != null =>
                pushCode.Replace("{value}", $"self->{f.CName}"),
            BindingType.Struct(var cName, var mt, _) =>
                $"{cName}* _ud = ({cName}*)lua_newuserdatauv(L, sizeof({cName}), 0);\n" +
                $"        *_ud = self->{f.CName};\n" +
                $"        luaL_setmetatable(L, \"{mt}\");\n" +
                $"        return 1",
            BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
                or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr
                => $"lua_pushinteger(L, (lua_Integer)self->{f.CName})",
            BindingType.Float or BindingType.Double
                => $"lua_pushnumber(L, (lua_Number)self->{f.CName})",
            BindingType.Bool
                => $"lua_pushboolean(L, self->{f.CName})",
            BindingType.Str or BindingType.ConstPtr(BindingType.Str)
                => $"lua_pushstring(L, self->{f.CName})",
            BindingType.Enum(_, _)
                => $"lua_pushinteger(L, (lua_Integer)self->{f.CName})",
            BindingType.FixedArray(BindingType.ValueStruct(_, _, var vsFields, _), var vsLen) =>
                GenFixedArrayOfValueStructPush(f.CName, vsFields, vsLen),
            BindingType.FixedArray(BindingType.Struct(var arrCName, var arrMt, _), var sLen) =>
                GenFixedArrayOfStructPush(f.CName, arrCName, arrMt, sLen),
            _ => $"lua_pushnil(L)"
        };
    }

    /// <summary>
    /// フィールドの __newindex setter 式 (BindingType ベース)
    /// </summary>
    private static string GenBindingSet(FieldBinding f, Dictionary<string, StructBinding>? structBindings = null)
    {
        return f.Type switch
        {
            BindingType.ValueStruct(_, _, var vsFields, true) =>
                GenValueStructSetCode(f.CName, vsFields),
            BindingType.Custom(_, _, _, _, _, var setCode) when setCode != null =>
                setCode.Replace("{fieldName}", f.CName),
            BindingType.Struct(var cName, var mt, _) when structBindings != null && structBindings.ContainsKey(cName) =>
                $"if (lua_istable(L, 3)) {{\n" +
                $"            lua_pushcfunction(L, l_{cName}_new); lua_pushvalue(L, 3); lua_call(L, 1, 1);\n" +
                $"            self->{f.CName} = *({cName}*)luaL_checkudata(L, -1, \"{mt}\"); lua_pop(L, 1);\n" +
                $"        }} else {{\n" +
                $"            self->{f.CName} = *({cName}*)luaL_checkudata(L, 3, \"{mt}\");\n" +
                $"        }}",
            BindingType.Struct(var cName, var mt, _) =>
                $"self->{f.CName} = *({cName}*)luaL_checkudata(L, 3, \"{mt}\")",
            BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
                or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr
                => $"self->{f.CName} = ({BindingTypeToString(f.Type)})luaL_checkinteger(L, 3)",
            BindingType.Float or BindingType.Double
                => $"self->{f.CName} = ({BindingTypeToString(f.Type)})luaL_checknumber(L, 3)",
            BindingType.Bool
                => $"self->{f.CName} = lua_toboolean(L, 3)",
            BindingType.Str or BindingType.ConstPtr(BindingType.Str)
                => $"self->{f.CName} = luaL_checkstring(L, 3)",
            BindingType.Enum(var name, _)
                => $"self->{f.CName} = ({name})luaL_checkinteger(L, 3)",
            _ => $"luaL_error(L, \"unsupported type for field: %s\", key)"
        };
    }

    /// <summary>
    /// フィールド初期化コード生成 (BindingType ベース)
    /// </summary>
    private static string GenBindingFieldInit(FieldBinding f, Dictionary<string, StructBinding> structBindings)
    {
        var luaName = f.LuaName;
        var cName = f.CName;
        var getField = $"        lua_getfield(L, 1, \"{luaName}\");";

        return f.Type switch
        {
            // Own struct: auto-construct from table
            BindingType.Struct(var sName, var mt, _) when structBindings.ContainsKey(sName) =>
                GenOwnStructFieldInit(getField, cName, sName, mt,
                    structBindings[sName].AllowStringInit),

            // Non-own struct: only accept userdata
            BindingType.Struct(var sName, var mt, _) =>
                $"{getField}\n" +
                $"        if (lua_isuserdata(L, -1)) ud->{cName} = *({sName}*)luaL_checkudata(L, -1, \"{mt}\");\n        lua_pop(L, 1);",

            // ValueStruct: read table and set struct fields
            BindingType.ValueStruct(_, _, var vsFields, _) =>
                GenValueStructFieldInit(getField, cName, vsFields),

            // Custom type: if InitCode is provided, use it with {fieldName} expansion; otherwise just pop
            BindingType.Custom(_, _, var initCode, _, _, _) when initCode != null =>
                $"{getField}\n        {initCode.Replace("{fieldName}", cName)}",
            BindingType.Custom(_, _, _, _, _, _) =>
                $"{getField}\n        lua_pop(L, 1);",

            // FixedArray of struct
            BindingType.FixedArray(BindingType.Struct(var arrCName, var arrMt, _), var len) =>
                $"{getField}\n" +
                GenBindingArrayFieldInit(cName, arrCName, arrMt, len,
                    structBindings.ContainsKey(arrCName),
                    structBindings.TryGetValue(arrCName, out var asb) && asb.AllowStringInit),

            // FixedArray of non-struct: just pop
            BindingType.FixedArray(_, _) =>
                $"{getField}\n        lua_pop(L, 1);",

            // Callback: just pop (callbacks are set via uservalue table)
            BindingType.Callback(_, _) =>
                $"{getField}\n        lua_pop(L, 1);",

            // Basic types
            BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
                or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{BindingTypeToString(f.Type)}})lua_tointeger(L, -1);
                        lua_pop(L, 1);
                """,

            BindingType.Float or BindingType.Double =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{BindingTypeToString(f.Type)}})lua_tonumber(L, -1);
                        lua_pop(L, 1);
                """,

            BindingType.Str or BindingType.ConstPtr(BindingType.Str) =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = lua_tostring(L, -1);
                        lua_pop(L, 1);
                """,

            BindingType.Bool =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = lua_toboolean(L, -1);
                        lua_pop(L, 1);
                """,

            BindingType.Enum(var enumName, _) =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = ({{enumName}})lua_tointeger(L, -1);
                        lua_pop(L, 1);
                """,

            // Pointer types: lightuserdata
            BindingType.VoidPtr or BindingType.Ptr(BindingType.Void) or BindingType.ConstPtr(BindingType.Void) =>
                $"{getField}\n" +
                $$"""
                        if (!lua_isnil(L, -1)) ud->{{cName}} = lua_touserdata(L, -1);
                        lua_pop(L, 1);
                """,

            // Fallback: just pop
            _ => $"{getField}\n        lua_pop(L, 1);"
        };
    }

    private static string GenOwnStructFieldInit(string getField, string cName, string sName, string mt, bool allowStringInit)
    {
        var condition = allowStringInit ? "lua_isstring(L, -1) || lua_istable(L, -1)" : "lua_istable(L, -1)";
        return $"{getField}\n" +
            $"        if ({condition}) {{\n" +
            $"            lua_pushcfunction(L, l_{sName}_new);\n" +
            $"            lua_pushvalue(L, -2);\n" +
            $"            lua_call(L, 1, 1);\n" +
            $"            ud->{cName} = *({sName}*)luaL_checkudata(L, -1, \"{mt}\");\n" +
            $"            lua_pop(L, 1);\n" +
            $"        }} else if (lua_isuserdata(L, -1)) {{\n" +
            $"            ud->{cName} = *({sName}*)luaL_checkudata(L, -1, \"{mt}\");\n" +
            $"        }}\n" +
            $"        lua_pop(L, 1);";
    }

    private static string GenBindingArrayFieldInit(string fieldName, string cName, string mt, int size, bool autoConstruct, bool allowStringInit)
    {
        var elementCondition = allowStringInit ? "lua_isstring(L, -1) || lua_istable(L, -1)" : "lua_istable(L, -1)";
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

    // ===== ValueStruct ヘルパー =====

    private static string GenValueStructParamDecl(string name, int idx, string cType, List<BindingType.ValueStructField> fields)
    {
        var lines = new List<string>
        {
            $"    luaL_checktype(L, {idx}, LUA_TTABLE);",
            $"    {cType} {name};"
        };
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    lines.Add($"    lua_rawgeti(L, {idx}, {fi}); {name}.{acc} = (float)lua_tonumber(L, -1); lua_pop(L, 1);");
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    lines.Add($"    lua_rawgeti(L, {idx}, {fi}); luaL_checktype(L, -1, LUA_TTABLE);");
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        lines.Add($"    lua_rawgeti(L, -1, {si}); {name}.{acc}.{sub} = (float)lua_tonumber(L, -1); lua_pop(L, 1);");
                        si++;
                    }
                    lines.Add("    lua_pop(L, 1);");
                    break;
            }
            fi++;
        }
        return string.Join("\n", lines);
    }

    private static string GenValueStructArrayParamDecl(string name, int idx, string cType,
        List<BindingType.ValueStructField> fields, int maxElems)
    {
        var lines = new List<string>
        {
            $"    luaL_checktype(L, {idx}, LUA_TTABLE);",
            $"    int _{name}_len = (int)lua_rawlen(L, {idx});",
            $"    luaL_argcheck(L, _{name}_len <= {maxElems}, {idx}, \"array too large (max {maxElems})\");",
            $"    {cType} _{name}_buf[{maxElems}];",
            $"    for (int _i = 0; _i < _{name}_len; _i++) {{",
            $"        lua_rawgeti(L, {idx}, _i + 1);",
            $"        luaL_checktype(L, -1, LUA_TTABLE);"
        };
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    lines.Add($"        lua_rawgeti(L, -1, {fi}); _{name}_buf[_i].{acc} = (float)lua_tonumber(L, -1); lua_pop(L, 1);");
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    lines.Add($"        lua_rawgeti(L, -1, {fi}); luaL_checktype(L, -1, LUA_TTABLE);");
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        lines.Add($"        lua_rawgeti(L, -1, {si}); _{name}_buf[_i].{acc}.{sub} = (float)lua_tonumber(L, -1); lua_pop(L, 1);");
                        si++;
                    }
                    lines.Add("        lua_pop(L, 1);");
                    break;
            }
            fi++;
        }
        lines.Add("        lua_pop(L, 1);");
        lines.Add("    }");
        lines.Add($"    const {cType}* {name} = _{name}_buf;");
        return string.Join("\n", lines);
    }

    private static string GenValueStructReturnPush(string callExpr, string cType, List<BindingType.ValueStructField> fields)
    {
        var sb = GenValueStructReturnCapture(callExpr, cType, fields);
        sb += "    return 1;";
        return sb;
    }

    /// <summary>
    /// ValueStruct 戻り値をキャプチャして Lua テーブルへ push (return 文なし — output param 併用時用)
    /// </summary>
    private static string GenValueStructReturnCapture(string callExpr, string cType, List<BindingType.ValueStructField> fields)
    {
        var sb = $"    {cType} _v = {callExpr};\n";
        sb += "    lua_newtable(L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"    lua_pushnumber(L, _v.{acc}); lua_rawseti(L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "    lua_newtable(L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"    lua_pushnumber(L, _v.{acc}.{sub}); lua_rawseti(L, -2, {si});\n";
                        si++;
                    }
                    sb += $"    lua_rawseti(L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        return sb;
    }

    private static string GenValueStructPushExpr(string prefix, List<BindingType.ValueStructField> fields)
    {
        var sb = "lua_newtable(L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"        lua_pushnumber(L, {prefix}.{acc}); lua_rawseti(L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "        lua_newtable(L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"        lua_pushnumber(L, {prefix}.{acc}.{sub}); lua_rawseti(L, -2, {si});\n";
                        si++;
                    }
                    sb += $"        lua_rawseti(L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        sb += "        return 1";
        return sb;
    }

    private static string GenFixedArrayOfValueStructPush(string fieldName, List<BindingType.ValueStructField> fields, int length)
    {
        var sb = $"lua_newtable(L);\n";
        sb += $"        for (int _i = 0; _i < {length}; _i++) {{\n";
        sb += "            lua_newtable(L);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"            lua_pushnumber(L, self->{fieldName}[_i].{acc}); lua_rawseti(L, -2, {fi});\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += "            lua_newtable(L);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"            lua_pushnumber(L, self->{fieldName}[_i].{acc}.{sub}); lua_rawseti(L, -2, {si});\n";
                        si++;
                    }
                    sb += $"            lua_rawseti(L, -2, {fi});\n";
                    break;
            }
            fi++;
        }
        sb += "            lua_rawseti(L, -2, _i + 1);\n";
        sb += "        }\n";
        sb += "        return 1";
        return sb;
    }

    private static string GenFixedArrayOfStructPush(string fieldName, string cName, string metatable, int length)
    {
        return $"lua_newtable(L);\n" +
            $"        for (int _i = 0; _i < {length}; _i++) {{\n" +
            $"            {cName}* _ud = ({cName}*)lua_newuserdatauv(L, sizeof({cName}), 0);\n" +
            $"            *_ud = self->{fieldName}[_i];\n" +
            $"            luaL_setmetatable(L, \"{metatable}\");\n" +
            $"            lua_rawseti(L, -2, _i + 1);\n" +
            $"        }}\n" +
            $"        return 1";
    }

    private static string GenValueStructSetCode(string fieldName, List<BindingType.ValueStructField> fields)
    {
        var sb = "luaL_checktype(L, 3, LUA_TTABLE)";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $";\n            lua_rawgeti(L, 3, {fi}); self->{fieldName}.{acc} = (float)lua_tonumber(L, -1); lua_pop(L, 1)";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += $";\n            lua_rawgeti(L, 3, {fi}); luaL_checktype(L, -1, LUA_TTABLE)";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $";\n            lua_rawgeti(L, -1, {si}); self->{fieldName}.{acc}.{sub} = (float)lua_tonumber(L, -1); lua_pop(L, 1)";
                        si++;
                    }
                    sb += ";\n            lua_pop(L, 1)";
                    break;
            }
            fi++;
        }
        return sb;
    }

    private static string GenValueStructFieldInit(string getField, string cName, List<BindingType.ValueStructField> fields)
    {
        var sb = $"{getField}\n";
        sb += "        if (!lua_isnil(L, -1)) {\n";
        sb += "            luaL_checktype(L, -1, LUA_TTABLE);\n";
        var fi = 1;
        foreach (var field in fields)
        {
            switch (field)
            {
                case BindingType.ScalarField(var acc):
                    sb += $"            lua_rawgeti(L, -1, {fi}); ud->{cName}.{acc} = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n";
                    break;
                case BindingType.NestedFields(var acc, var subs):
                    sb += $"            lua_rawgeti(L, -1, {fi}); luaL_checktype(L, -1, LUA_TTABLE);\n";
                    var si = 1;
                    foreach (var sub in subs)
                    {
                        sb += $"            lua_rawgeti(L, -1, {si}); ud->{cName}.{acc}.{sub} = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n";
                        si++;
                    }
                    sb += "            lua_pop(L, 1);\n";
                    break;
            }
            fi++;
        }
        sb += "        }\n";
        sb += "        lua_pop(L, 1);";
        return sb;
    }
}
