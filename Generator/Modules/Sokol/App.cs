namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// sokol.app モジュールの生成定義
/// </summary>
public class App : SokolModule
{
    public override string ModuleName => "sokol.app";
    public override string Prefix => "sapp_";

    private const string LogFunc = "slog_func";

    // ===== カスタマイズ hooks =====

    protected override bool ShouldGenerateFunc(Funcs f) => f.Name != "sapp_run";

    protected override bool HasMetamethods(Structs s) => s.Name == "sapp_event";

    protected override string MapFieldName(string fieldName) =>
        CallbackNames.GetValueOrDefault(fieldName, fieldName);

    protected override IEnumerable<(string LuaName, string CFunc)> ExtraLuaRegs =>
        [("Run", "l_sapp_run")];

    protected override string? ExtraCCode(TypeRegistry reg) =>
        ContextStruct() +
        Trampoline("init", "init") +
        Trampoline("frame", "frame") +
        Trampoline("cleanup", "cleanup") +
        TrampolineEvent($"{ModuleName}.Event") +
        RunFunc($"{ModuleName}.Desc");

    // ===== App 固有ヘルパー =====

    private static readonly Dictionary<string, string> CallbackNames = new()
    {
        ["init_cb"] = "init",
        ["frame_cb"] = "frame",
        ["cleanup_cb"] = "cleanup",
        ["event_cb"] = "event",
    };

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
}
