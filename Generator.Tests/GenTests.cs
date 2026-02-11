using Generator;
using Generator.ClangAst;
using Generator.CBinding;

namespace Generator.Tests;

public class GenTests
{
    private const string TestJson = """
    {
      "module": "app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        {
          "kind": "struct",
          "name": "sapp_desc",
          "fields": [
            { "name": "width", "type": "int" },
            { "name": "height", "type": "int" },
            { "name": "window_title", "type": "const char *" },
            { "name": "init_cb", "type": "void (*)(void)" }
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
          "kind": "enum",
          "name": "sapp_event_type",
          "items": [
            { "name": "SAPP_EVENTTYPE_INVALID" },
            { "name": "SAPP_EVENTTYPE_KEY_DOWN" },
            { "name": "SAPP_EVENTTYPE_KEY_UP" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void Header_ContainsIncludes()
    {
        var header = CBindingGen.Header(["sokol_log.h", "sokol_app.h"]);
        Assert.Contains("#include <lua.h>", header);
        Assert.Contains("#include \"sokol_app.h\"", header);
    }

    [Fact]
    public void Enum_ContainsValues()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var e = reg.GetEnum("sapp_event_type");
        var code = CBindingGen.Enum("sapp_event_type", "EventType", Pipeline.ToEnumItemsC(e, "sapp_"));
        Assert.Contains("INVALID", code);
        Assert.Contains("KEY_DOWN", code);
    }

    [Fact]
    public void LuaReg_ContainsEntries()
    {
        var code = CBindingGen.LuaReg("app_funcs", [("Desc", "l_sapp_desc_new"), ("Run", "l_sapp_run")]);
        Assert.Contains("{\"Desc\", l_sapp_desc_new}", code);
        Assert.Contains("{\"Run\", l_sapp_run}", code);
        Assert.Contains("{NULL, NULL}", code);
    }

    [Fact]
    public void LuaOpen_ContainsOpenFunction()
    {
        var code = CBindingGen.LuaOpen("sokol_app", "app_funcs");
        Assert.Contains("int luaopen_sokol_app(lua_State *L)", code);
        Assert.Contains("luaL_newlib(L, app_funcs)", code);
    }
}
