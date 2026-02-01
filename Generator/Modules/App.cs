namespace Generator.Modules;

using Generator;
using Generator.ClangAst;
using Generator.CBinding;
using Generator.LuaCats;

/// <summary>
/// app モジュールの生成定義
/// </summary>
public static class App
{
    private const string ModuleName = "app";
    private const string Prefix = "sapp_";
    private const string DescMetatable = "sokol.Desc";
    private const string EventMetatable = "sokol.Event";
    private const string LogFunc = "slog_func";

    // ===== App 固有ヘルパー (sokol_app の構造を知っている) =====

    /// <summary>
    /// コールバックコンテキスト構造体
    /// </summary>
    private static string ContextStruct() => """
        typedef struct {
            lua_State* L;
            int table_ref;
        } LuaCallbackContext;

        """;

    /// <summary>
    /// 引数なしトランポリン (init, frame, cleanup)
    /// </summary>
    private static string Trampoline(string name, string luaField) => $$"""
        static void trampoline_{{name}}(void* user_data) {
            LuaCallbackContext* ctx = (LuaCallbackContext*)user_data;
            lua_State* L = ctx->L;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "{{luaField}}");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
            if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
                {{LogFunc}}("callback", 0, 0, lua_tostring(L, -1), 0, "{{luaField}}", 0);
                lua_pop(L, 1);
            }
        }

        """;

    /// <summary>
    /// event トランポリン (引数あり)
    /// </summary>
    private static string TrampolineEvent() => $$"""
        static void trampoline_event(const sapp_event* e, void* user_data) {
            LuaCallbackContext* ctx = (LuaCallbackContext*)user_data;
            lua_State* L = ctx->L;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "event");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
            sapp_event* ud_ev = (sapp_event*)lua_newuserdatauv(L, sizeof(sapp_event), 0);
            *ud_ev = *e;
            luaL_setmetatable(L, "{{EventMetatable}}");
            if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
                {{LogFunc}}("callback", 0, 0, lua_tostring(L, -1), 0, "event", 0);
                lua_pop(L, 1);
            }
        }

        """;

    /// <summary>
    /// Run 関数 (user_data 形式でコールバック設定)
    /// </summary>
    private static string RunFunc() => $$"""
        static int l_sapp_run(lua_State *L) {
        #ifdef SOKOL_DUMMY_BACKEND
            (void)L;
            return 0;
        #else
            sapp_desc* desc = (sapp_desc*)luaL_checkudata(L, 1, "{{DescMetatable}}");

            // context を userdata として作成 (GC で回収されないよう registry に保持)
            LuaCallbackContext* ctx = (LuaCallbackContext*)lua_newuserdatauv(L, sizeof(LuaCallbackContext), 1);
            ctx->L = L;

            // 引数1 (テーブル) を uservalue として保持
            lua_pushvalue(L, 1);
            lua_setiuservalue(L, -2, 1);
            ctx->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);

            // user_data 形式でコールバック設定
            desc->user_data = ctx;
            desc->init_userdata_cb = trampoline_init;
            desc->frame_userdata_cb = trampoline_frame;
            desc->cleanup_userdata_cb = trampoline_cleanup;
            desc->event_userdata_cb = trampoline_event;

            sapp_run(desc);
            return 0;
        #endif
        }

        """;

    // ===== LuaCATS ヘルパー =====

    /// <summary>
    /// コールバックフィールド名を短い名前に変換
    /// </summary>
    private static readonly Dictionary<string, string> CallbackNames = new()
    {
        ["init_cb"] = "init",
        ["frame_cb"] = "frame",
        ["cleanup_cb"] = "cleanup",
        ["event_cb"] = "event",
    };

    private static string MapFieldName(string name) =>
        CallbackNames.TryGetValue(name, out var n) ? n : name;

    // ===== 生成メソッド =====

    public static string GenerateC(TypeRegistry reg)
    {
        var descStruct = reg.GetStruct("sapp_desc");
        var eventStruct = reg.GetStruct("sapp_event");
        var widthFunc = reg.GetFunc("sapp_width");
        var heightFunc = reg.GetFunc("sapp_height");
        var eventTypeEnum = reg.GetEnum("sapp_event_type");

        return CBindingGen.Header(["sokol_log.h", "sokol_app.h"]) +
            ContextStruct() +
            Trampoline("init", "init") +
            Trampoline("frame", "frame") +
            Trampoline("cleanup", "cleanup") +
            TrampolineEvent() +
            CBindingGen.StructNew("sapp_desc", DescMetatable, Pipeline.ToCFieldInits(descStruct)) +
            CBindingGen.StructNew("sapp_event", EventMetatable, Pipeline.ToCFieldInits(eventStruct)) +
            RunFunc() +
            CBindingGen.Func("sapp_width", Pipeline.ToCParams(widthFunc), Pipeline.ToCReturnType(widthFunc), DescMetatable) +
            CBindingGen.Func("sapp_height", Pipeline.ToCParams(heightFunc), Pipeline.ToCReturnType(heightFunc), DescMetatable) +
            CBindingGen.Enum("sapp_event_type",
                Pipeline.ToPascalCase(Pipeline.StripPrefix(eventTypeEnum.Name, Prefix)),
                Pipeline.ToEnumItems(eventTypeEnum, Prefix)) +
            CBindingGen.RegisterMetatables([DescMetatable, EventMetatable]) +
            CBindingGen.LuaReg("app_funcs",
                [("Desc", "l_sapp_desc_new"),
                 ("Event", "l_sapp_event_new"),
                 ("Run", "l_sapp_run"),
                 ("Width", "l_sapp_width"),
                 ("Height", "l_sapp_height")]) +
            CBindingGen.LuaOpen("sokol_app", "app_funcs");
    }

    public static string GenerateLua(TypeRegistry reg)
    {
        var descStruct = reg.GetStruct("sapp_desc");
        var eventStruct = reg.GetStruct("sapp_event");
        var runFunc = reg.GetFunc("sapp_run");
        var widthFunc = reg.GetFunc("sapp_width");
        var heightFunc = reg.GetFunc("sapp_height");
        var eventTypeEnum = reg.GetEnum("sapp_event_type");

        // Desc 構造体のフィールド名変換 (init_cb → init など)
        var descFields = descStruct.Fields.Select(f =>
            (MapFieldName(f.Name), Pipeline.ToLuaCatsType(f.ParsedType, ModuleName, Prefix)));

        // Event 構造体は変換なし
        var eventFields = Pipeline.ToLuaCatsFields(eventStruct, ModuleName, Prefix);

        return LuaCatsGen.Header(ModuleName) +
            LuaCatsGen.StructClass(Pipeline.ToLuaCatsClassName(descStruct, ModuleName, Prefix), descFields) +
            LuaCatsGen.StructClass(Pipeline.ToLuaCatsClassName(eventStruct, ModuleName, Prefix), eventFields) +
            LuaCatsGen.ModuleClass(ModuleName,
                [LuaCatsGen.StructCtor("Desc", ModuleName),
                 LuaCatsGen.StructCtor("Event", ModuleName),
                 LuaCatsGen.FuncField(
                     Pipeline.ToLuaCatsFuncName(runFunc, Prefix),
                     Pipeline.ToLuaCatsParams(runFunc, ModuleName, Prefix),
                     Pipeline.ToLuaCatsReturnType(runFunc, ModuleName, Prefix)),
                 LuaCatsGen.FuncField(
                     Pipeline.ToLuaCatsFuncName(widthFunc, Prefix),
                     Pipeline.ToLuaCatsParams(widthFunc, ModuleName, Prefix),
                     Pipeline.ToLuaCatsReturnType(widthFunc, ModuleName, Prefix)),
                 LuaCatsGen.FuncField(
                     Pipeline.ToLuaCatsFuncName(heightFunc, Prefix),
                     Pipeline.ToLuaCatsParams(heightFunc, ModuleName, Prefix),
                     Pipeline.ToLuaCatsReturnType(heightFunc, ModuleName, Prefix))]) +
            LuaCatsGen.EnumDef(
                Pipeline.ToLuaCatsEnumName(eventTypeEnum, ModuleName, Prefix),
                Pipeline.ToEnumItems(eventTypeEnum, Prefix)) +
            LuaCatsGen.Footer(ModuleName);
    }
}
