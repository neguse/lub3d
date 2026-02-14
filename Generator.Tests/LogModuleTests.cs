using Generator.ClangAst;
using Generator.Modules.Sokol;

namespace Generator.Tests;

public class LogModuleTests
{
    private readonly Log _log = new();
    private static readonly Dictionary<string, string> PrefixToModule = new()
    {
        ["slog_"] = "sokol.log",
    };

    private const string LogJson = """
    {
      "module": "sokol.log",
      "prefix": "slog_",
      "dep_prefixes": [],
      "decls": [
        {
          "kind": "func",
          "name": "slog_func",
          "type": "void (const char *, uint32_t, uint32_t, const char *, uint32_t, const char *, void *)",
          "params": [
            { "name": "tag", "type": "const char *" },
            { "name": "log_level", "type": "uint32_t" },
            { "name": "log_item", "type": "uint32_t" },
            { "name": "message", "type": "const char *" },
            { "name": "line_nr", "type": "uint32_t" },
            { "name": "filename", "type": "const char *" },
            { "name": "user_data", "type": "void *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void GenerateC_ContainsHeader()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateC(reg, PrefixToModule);
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_log.h\"", code);
    }

    [Fact]
    public void GenerateC_ContainsFunc()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateC(reg, PrefixToModule);
        Assert.Contains("l_slog_func", code);
    }

    [Fact]
    public void GenerateC_ContainsLuaReg()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateC(reg, PrefixToModule);
        Assert.Contains("sokol_log_funcs[]", code);
        Assert.Contains("{\"func\", l_slog_func}", code);
    }

    [Fact]
    public void GenerateC_ContainsLuaOpen()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateC(reg, PrefixToModule);
        Assert.Contains("luaopen_sokol_log", code);
    }

    [Fact]
    public void GenerateLua_ContainsLuaCATS()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@meta", code);
        Assert.Contains("---@class sokol_log_module", code);
    }

    [Fact]
    public void GenerateLua_ContainsFuncField()
    {
        var reg = TypeRegistry.FromJson(LogJson);
        var code = _log.GenerateLua(reg, PrefixToModule);
        Assert.Contains("func", code);
        Assert.Contains("tag: string", code);
        Assert.Contains("log_level: integer", code);
        Assert.Contains("message: string", code);
    }
}
