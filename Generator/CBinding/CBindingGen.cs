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
    private static string StructNew(string structName, string metatable, IEnumerable<FieldBinding> fields, Dictionary<string, StructBinding> structBindings)
    {
        var fieldInits = string.Join("\n", fields.Select(f => GenBindingFieldInit(f, structBindings)));
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
    private static string StructIndex(string structName, string metatable, IEnumerable<FieldBinding> fields)
    {
        var branches = fields
            .Where(f => f.Type is not BindingType.Callback)
            .Select(f => $"    if (strcmp(key, \"{f.LuaName}\") == 0) {{ {GenBindingPush(f)}; return 1; }}");
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
    private static string StructPairs(string structName, string metatable, IEnumerable<FieldBinding> fields)
    {
        var accessibleFields = fields.Where(f => f.Type is not BindingType.Callback).ToList();
        var fieldEntries = accessibleFields.Select(f =>
            $"        \"{f.LuaName}\"").ToList();
        // Avoid empty array initializer (triggers MSVC ICE)
        if (fieldEntries.Count == 0) fieldEntries.Add("        NULL");
        var fieldNames = string.Join(",\n", fieldEntries);
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
    private static string StructNewindex(string structName, string metatable, IEnumerable<FieldBinding> fields, Dictionary<string, StructBinding> structBindings)
    {
        var branches = fields
            .Where(f => f.Type is not BindingType.Callback)
            .Select(f => $"    if (strcmp(key, \"{f.LuaName}\") == 0) {{ {GenBindingSet(f, structBindings)}; return 0; }}");
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
                if (p.Type is BindingType.Callback)
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
                sb += SgRangeNew(s.CName, s.Metatable, s.Fields, structBindings);
            else
                sb += StructNew(s.CName, s.Metatable, s.Fields, structBindings);
            if (s.HasMetamethods)
            {
                sb += StructIndex(s.CName, s.Metatable, s.Fields);
                sb += StructNewindex(s.CName, s.Metatable, s.Fields, structBindings);
                sb += StructPairs(s.CName, s.Metatable, s.Fields);
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
            sb += GenBindingFunc(f);

        // Opaque types
        foreach (var ot in spec.OpaqueTypes)
        {
            sb += OpaqueCheckHelper(ot);
            if (ot.InitFunc != null)
                sb += OpaqueConstructor(ot, structBindings);
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
    private static string SgRangeNew(string structName, string metatable, IEnumerable<FieldBinding> fields, Dictionary<string, StructBinding> structBindings)
    {
        var fieldInits = string.Join("\n", fields.Select(f => GenBindingFieldInit(f, structBindings)));
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
        var entries = ot.Methods.Select(m => $"    {{\"{m.LuaName}\", l_{m.CName}}},");
        return $$"""
            static const luaL_Reg {{ot.CName}}_methods[] = {
            {{string.Join("\n", entries)}}
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
        BindingType.Custom(_, _, _, _, var pushCode, _) when pushCode != null =>
            $"    {pushCode.Replace("{value}", callExpr)}\n    return 1;",
        BindingType.Custom(_, _, _, _, null, _) =>
            $"    {callExpr};\n    return 0;",
        _ => throw new InvalidOperationException($"Unsupported return type: {ret}")
    };

    private static string GenBindingFunc(FuncBinding f)
    {
        var paramDecls = string.Join("\n", f.Params.Select((p, i) =>
            GenBindingParamDecl(p, i + 1)).Where(s => s != ""));
        var argNames = string.Join(", ", f.Params.Select(p => p.Name));
        var call = GenBindingReturnPush(f.ReturnType, $"{f.CName}({argNames})");

        return $$"""
            static int l_{{f.CName}}(lua_State *L) {
            {{paramDecls}}
            {{call}}
            }

            """;
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

            // Custom type: just pop (Custom fields use PushCode/SetCode in index/newindex only)
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
}
