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
        [("run", "l_sapp_run")];

    protected override IEnumerable<FuncBinding> ExtraLuaFuncs =>
        [new FuncBinding("l_sapp_run", "run",
            [new ParamBinding("desc", new BindingType.Struct("sapp_desc", "sokol.app.Desc", $"{ModuleName}.Desc"))],
            new BindingType.Void(), null)];

    protected override string? ExtraCCode(TypeRegistry reg) =>
        ContextStruct() +
        Trampoline("init", "init") +
        Trampoline("frame", "frame") +
        TrampolineCleanup() +
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
        /*
         * LuaCallbackContext — sokol_app コールバックと Lua 状態の橋渡し
         *
         * sapp_run() に渡す user_data として、この構造体を Lua userdata で確保する。
         * table_ref: コールバック関数テーブル (init/frame/cleanup/event) へのレジストリ参照。
         * self_ref:  この userdata 自身へのレジストリ参照 (GC 防止用)。
         *
         * ■ なぜ self_ref が必要か
         *   ネイティブでは sapp_run() がアプリ終了までブロックするため、
         *   l_sapp_run のスタックフレームが ctx を保持し続ける。
         *   Emscripten では sapp_run() が即座に return し、コールバックは
         *   ブラウザのイベントループから非同期に呼ばれる。l_sapp_run の
         *   スタックフレームが消えると ctx への強参照がなくなり、GC が回収
         *   → コールバック時に memory access out of bounds でクラッシュする。
         *
         * ■ 代案の比較
         *   (A) C 側 static 変数で保持 (static LuaCallbackContext *g_ctx)
         *       - 長所: シンプル、Lua レジストリ不要
         *       - 短所: シングルトン強制 (複数 lua_State 不可)、
         *               C ポインタだけでは GC を止められず luaL_ref も必要になるため
         *               結局レジストリ参照が要る。static 変数が増えるだけで利点なし。
         *   (B) Lua グローバル変数で保持 (_G._sapp_ctx = ctx)
         *       - 長所: Lua 側から可視、デバッグしやすい
         *       - 短所: グローバル名前空間を汚染、Lua コードから上書き可能で脆弱。
         *   (C) レジストリ self_ref (現採用)
         *       - 長所: Lua メモリ管理と統合、名前空間汚染なし、
         *               cleanup で unref するだけで自然に解放される。
         *       - 短所: userdata が自身を参照する形になるが、cleanup で
         *               明示的に unref するため循環参照問題は起きない。
         *
         * ■ ライフサイクル
         *   l_sapp_run:         ctx 作成 → table_ref, self_ref をレジストリに登録
         *   trampoline_*:       table_ref 経由でコールバック関数を取得・呼出
         *   trampoline_cleanup: コールバック実行後 table_ref, self_ref を unref → GC 可能に
         */
        typedef struct {
            lua_State* L;
            int table_ref;  /* registry ref: callback table (init/frame/cleanup/event) */
            int self_ref;   /* registry ref: this userdata itself (prevents GC) */
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

    private static string TrampolineCleanup() => $$"""
        /* cleanup トランポリン: Lua 側 cleanup() を呼んだ後、レジストリ参照を解放して
         * ctx userdata を GC 可能にする。self_ref の unref がここで初めて行われるため、
         * アプリ生存期間中は ctx が確実に生き続ける。 */
        static void trampoline_cleanup(void* user_data) {
            LuaCallbackContext* ctx = (LuaCallbackContext*)user_data;
            lua_State* L = ctx->L;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "cleanup");
            lua_remove(L, -2);
            if (lua_isfunction(L, -1)) {
                if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
                    {{LogFunc}}("callback", 0, 0, lua_tostring(L, -1), 0, "cleanup", 0);
                    lua_pop(L, 1);
                }
            } else {
                lua_pop(L, 1);
            }
            /* Release both registry refs → ctx becomes GC-eligible */
            luaL_unref(L, LUA_REGISTRYINDEX, ctx->table_ref);
            luaL_unref(L, LUA_REGISTRYINDEX, ctx->self_ref);
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

            /* ctx userdata を作成し、desc の user value としても紐付ける */
            LuaCallbackContext* ctx = (LuaCallbackContext*)lua_newuserdatauv(L, sizeof(LuaCallbackContext), 1);
            ctx->L = L;

            lua_pushvalue(L, 1);
            lua_setiuservalue(L, -2, 1);

            /* コールバックテーブルをレジストリに保存 */
            lua_getiuservalue(L, 1, 1);
            ctx->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);

            /* ctx 自身をレジストリに保存して GC から保護する。
             * ネイティブ: sapp_run() がブロックするのでスタックが ctx を保持 → 不要だが無害。
             * Emscripten: sapp_run() が即 return → スタックが消えるため必須。
             * trampoline_cleanup で unref するまで GC されない。 */
            lua_pushvalue(L, -1);
            ctx->self_ref = luaL_ref(L, LUA_REGISTRYINDEX);

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
