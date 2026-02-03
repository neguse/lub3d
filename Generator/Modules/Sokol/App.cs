namespace Generator.Modules.Sokol;

using Generator;
using Generator.ClangAst;
using Generator.CBinding;
using Generator.LuaCats;

/// <summary>
/// sokol.app モジュールの生成定義
/// </summary>
public class App : IModule
{
    public string ModuleName => "sokol.app";
    public string Header => "sokol/sokol_app.h";
    public IReadOnlyList<string> IncludeDirs => ["sokol"];
    public string Prefix => "sapp_";
    public IReadOnlyList<string> DepPrefixes => ["slog_"];

    private const string LogFunc = "slog_func";

    private static string Metatable(string moduleName, string typeName) =>
        $"{moduleName}.{typeName}";

    private static string ToUnderscore(string moduleName) =>
        moduleName.Replace('.', '_');

    // ===== App 固有ヘルパー =====

    private static string ContextStruct() => """
        typedef struct {
            lua_State* L;
            int table_ref;
        } LuaCallbackContext;

        """;

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

    private static string TrampolineEvent(string eventMetatable) => $$"""
        static void trampoline_event(const sapp_event* e, void* user_data) {
            LuaCallbackContext* ctx = (LuaCallbackContext*)user_data;
            lua_State* L = ctx->L;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "event");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return; }
            sapp_event* ud_ev = (sapp_event*)lua_newuserdatauv(L, sizeof(sapp_event), 0);
            *ud_ev = *e;
            luaL_setmetatable(L, "{{eventMetatable}}");
            if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
                {{LogFunc}}("callback", 0, 0, lua_tostring(L, -1), 0, "event", 0);
                lua_pop(L, 1);
            }
        }

        """;

    private static string RunFunc(string descMetatable) => $$"""
        static int l_sapp_run(lua_State *L) {
        #ifdef SOKOL_DUMMY_BACKEND
            (void)L;
            return 0;
        #else
            sapp_desc* desc = (sapp_desc*)luaL_checkudata(L, 1, "{{descMetatable}}");

            LuaCallbackContext* ctx = (LuaCallbackContext*)lua_newuserdatauv(L, sizeof(LuaCallbackContext), 1);
            ctx->L = L;

            lua_pushvalue(L, 1);
            lua_setiuservalue(L, -2, 1);

            lua_getiuservalue(L, 1, 1);
            ctx->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);

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

    public string GenerateC(TypeRegistry reg)
    {
        var descMetatable = Metatable(ModuleName, "Desc");
        var eventMetatable = Metatable(ModuleName, "Event");
        var funcArrayName = $"{ToUnderscore(ModuleName)}_funcs";
        var luaOpenName = ToUnderscore(ModuleName);

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
            TrampolineEvent(eventMetatable) +
            CBindingGen.StructNew("sapp_desc", descMetatable, Pipeline.ToCFieldInits(descStruct)) +
            CBindingGen.StructNew("sapp_event", eventMetatable, Pipeline.ToCFieldInits(eventStruct)) +
            RunFunc(descMetatable) +
            CBindingGen.Func("sapp_width", Pipeline.ToCParams(widthFunc), Pipeline.ToCReturnType(widthFunc), descMetatable) +
            CBindingGen.Func("sapp_height", Pipeline.ToCParams(heightFunc), Pipeline.ToCReturnType(heightFunc), descMetatable) +
            CBindingGen.Enum("sapp_event_type",
                Pipeline.ToPascalCase(Pipeline.StripPrefix(eventTypeEnum.Name, Prefix)),
                Pipeline.ToEnumItemsC(eventTypeEnum, Prefix)) +
            CBindingGen.RegisterMetatables([descMetatable, eventMetatable]) +
            CBindingGen.LuaReg(funcArrayName,
                [("Desc", "l_sapp_desc_new"),
                 ("Event", "l_sapp_event_new"),
                 ("Run", "l_sapp_run"),
                 ("Width", "l_sapp_width"),
                 ("Height", "l_sapp_height")]) +
            CBindingGen.LuaOpen(luaOpenName, funcArrayName);
    }

    public string GenerateLua(TypeRegistry reg, SourceLink? sourceLink = null)
    {
        var descStruct = reg.GetStruct("sapp_desc");
        var eventStruct = reg.GetStruct("sapp_event");
        var runFunc = reg.GetFunc("sapp_run");
        var widthFunc = reg.GetFunc("sapp_width");
        var heightFunc = reg.GetFunc("sapp_height");
        var eventTypeEnum = reg.GetEnum("sapp_event_type");

        string? Link(Decl d) => d is { } decl && sourceLink != null
            ? (decl switch { Structs s => s.Line, Funcs f => f.Line, Enums e => e.Line, _ => null })
                is int line ? sourceLink.GetLink(line) : null
            : null;

        var descFields = descStruct.Fields.Select(f =>
            (MapFieldName(f.Name), Pipeline.ToLuaCatsType(f.ParsedType, ModuleName, Prefix)));

        var eventFields = Pipeline.ToLuaCatsFields(eventStruct, ModuleName, Prefix);

        return LuaCatsGen.Header(ModuleName) +
            LuaCatsGen.StructClass(Pipeline.ToLuaCatsClassName(descStruct, ModuleName, Prefix), descFields, Link(descStruct)) +
            LuaCatsGen.StructClass(Pipeline.ToLuaCatsClassName(eventStruct, ModuleName, Prefix), eventFields, Link(eventStruct)) +
            LuaCatsGen.ModuleClass(ModuleName,
                [LuaCatsGen.StructCtor("Desc", ModuleName),
                 LuaCatsGen.StructCtor("Event", ModuleName)]) +
            LuaCatsGen.FuncDef(
                Pipeline.ToLuaCatsFuncName(runFunc, Prefix),
                Pipeline.ToLuaCatsParams(runFunc, ModuleName, Prefix),
                Pipeline.ToLuaCatsReturnType(runFunc, ModuleName, Prefix),
                Link(runFunc)) +
            LuaCatsGen.FuncDef(
                Pipeline.ToLuaCatsFuncName(widthFunc, Prefix),
                Pipeline.ToLuaCatsParams(widthFunc, ModuleName, Prefix),
                Pipeline.ToLuaCatsReturnType(widthFunc, ModuleName, Prefix),
                Link(widthFunc)) +
            LuaCatsGen.FuncDef(
                Pipeline.ToLuaCatsFuncName(heightFunc, Prefix),
                Pipeline.ToLuaCatsParams(heightFunc, ModuleName, Prefix),
                Pipeline.ToLuaCatsReturnType(heightFunc, ModuleName, Prefix),
                Link(heightFunc)) +
            LuaCatsGen.EnumDef(
                Pipeline.ToLuaCatsEnumName(eventTypeEnum, ModuleName, Prefix),
                Pipeline.ToPascalCase(Pipeline.StripPrefix(eventTypeEnum.Name, Prefix)),
                Pipeline.ToEnumItems(eventTypeEnum, Prefix),
                Link(eventTypeEnum)) +
            LuaCatsGen.Footer(ModuleName);
    }
}
