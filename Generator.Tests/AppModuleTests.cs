using Generator.ClangAst;
using Generator.Modules.Sokol;

namespace Generator.Tests;

public class AppModuleTests
{
    private const string AppJson = """
    {
      "module": "app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        {
          "kind": "enum",
          "name": "sapp_event_type",
          "items": [
            { "name": "SAPP_EVENTTYPE_INVALID" },
            { "name": "SAPP_EVENTTYPE_KEY_DOWN" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "sapp_event",
          "fields": [
            { "name": "type", "type": "sapp_event_type" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "sapp_desc",
          "fields": [
            { "name": "init_cb", "type": "void (*)(void)" },
            { "name": "width", "type": "int" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_run",
          "type": "void (const sapp_desc *)",
          "params": [
            { "name": "desc", "type": "const sapp_desc *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_width",
          "type": "int (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_height",
          "type": "int (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void Generate_ContainsHeader()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_app.h\"", code);
    }

    [Fact]
    public void Generate_ContainsStructs()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("l_sapp_desc_new", code);
        Assert.Contains("l_sapp_event_new", code);
    }

    [Fact]
    public void Generate_ContainsFunctions()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("l_sapp_run", code);
        Assert.Contains("l_sapp_width", code);
    }

    [Fact]
    public void Generate_ContainsEnum()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("register_sapp_event_type", code);
    }

    [Fact]
    public void Generate_ContainsLuaReg()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("app_funcs[]", code);
        Assert.Contains("{\"Desc\", l_sapp_desc_new}", code);
    }

    [Fact]
    public void GenerateC_ContainsLuaOpen()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("luaopen_sokol_app", code);
    }

    [Fact]
    public void GenerateC_ContainsContextStruct()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        Assert.Contains("typedef struct {", code);
        Assert.Contains("LuaCallbackContext", code);
        Assert.Contains("lua_State* L;", code);
        Assert.Contains("int table_ref;", code);
    }

    [Fact]
    public void GenerateC_ContainsUserDataTrampolines()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        // user_data 形式のトランポリン
        Assert.Contains("trampoline_init(void* user_data)", code);
        Assert.Contains("trampoline_frame(void* user_data)", code);
        Assert.Contains("trampoline_cleanup(void* user_data)", code);
        Assert.Contains("trampoline_event(const sapp_event* e, void* user_data)", code);
    }

    [Fact]
    public void GenerateC_RunFuncUsesUserDataCallbacks()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        // Run 関数が user_data 形式のコールバックを設定
        Assert.Contains("desc->user_data = ctx;", code);
        Assert.Contains("desc->init_userdata_cb = trampoline_init;", code);
        Assert.Contains("desc->frame_userdata_cb = trampoline_frame;", code);
        Assert.Contains("desc->cleanup_userdata_cb = trampoline_cleanup;", code);
        Assert.Contains("desc->event_userdata_cb = trampoline_event;", code);
    }

    [Fact]
    public void GenerateC_NoGlobalVariables()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateC(reg);
        // グローバル変数を使用しない
        Assert.DoesNotContain("g_sapp_desc_L", code);
        Assert.DoesNotContain("g_sapp_desc_table_ref", code);
    }

    [Fact]
    public void GenerateLua_ContainsLuaCATS()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateLua(reg);
        Assert.Contains("---@meta", code);
        Assert.Contains("---@class app.Desc", code);
        Assert.Contains("---@enum app.EventType", code);
    }

    [Fact]
    public void GenerateLua_CallbackFieldsRenamed()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var code = App.GenerateLua(reg);
        // init_cb → init に変換される
        Assert.Contains("---@field init? fun()", code);
        Assert.DoesNotContain("init_cb", code);
    }
}
