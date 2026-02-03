using Generator;
using Generator.ClangAst;
using Generator.LuaCats;

namespace Generator.Tests;

public class GenLuaCATSTests
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
            { "name": "SAPP_EVENTTYPE_KEY_DOWN" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    private const string ModuleName = "app";
    private const string Prefix = "sapp_";

    [Fact]
    public void StructClass_ContainsFields()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var s = reg.GetStruct("sapp_desc");
        var code = LuaCatsGen.StructClass(
            Pipeline.ToLuaCatsClassName(s, ModuleName, Prefix),
            Pipeline.ToLuaCatsFields(s, ModuleName, Prefix));
        Assert.Contains("---@class app.Desc", code);
        Assert.Contains("---@field width? integer", code);
        Assert.Contains("---@field init_cb? fun()", code);
    }

    [Fact]
    public void FuncField_VoidReturn()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var f = reg.GetFunc("sapp_run");
        var code = LuaCatsGen.FuncField(
            Pipeline.ToLuaCatsFuncName(f, Prefix),
            Pipeline.ToLuaCatsParams(f, ModuleName, Prefix),
            Pipeline.ToLuaCatsReturnType(f, ModuleName, Prefix));
        Assert.Contains("---@field Run fun(desc: app.Desc)", code);
    }

    [Fact]
    public void FuncField_IntReturn()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var f = reg.GetFunc("sapp_width");
        var code = LuaCatsGen.FuncField(
            Pipeline.ToLuaCatsFuncName(f, Prefix),
            Pipeline.ToLuaCatsParams(f, ModuleName, Prefix),
            Pipeline.ToLuaCatsReturnType(f, ModuleName, Prefix));
        Assert.Contains("---@field Width fun(): integer", code);
    }

    [Fact]
    public void EnumDef_ContainsValues()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var e = reg.GetEnum("sapp_event_type");
        var code = LuaCatsGen.EnumDef(
            Pipeline.ToLuaCatsEnumName(e, ModuleName, Prefix),
            Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix)),
            Pipeline.ToEnumItems(e, Prefix));
        Assert.Contains("---@enum app.EventType", code);
        Assert.Contains("INVALID = 0", code);
        Assert.Contains("KEY_DOWN = 1", code);
    }

    [Fact]
    public void StructCtor_ContainsFunSignature()
    {
        var code = LuaCatsGen.StructCtor("Desc", "app");
        Assert.Contains("---@field Desc fun(t?: app.Desc): app.Desc", code);
    }

    [Fact]
    public void ModuleClass_ContainsFields()
    {
        var code = LuaCatsGen.ModuleClass("app", ["---@field Foo fun()", "---@field Bar fun(): integer"]);
        Assert.Contains("---@class app", code);
        Assert.Contains("---@field Foo fun()", code);
        Assert.Contains("---@field Bar fun(): integer", code);
        Assert.Contains("local M = {}", code);
    }

    [Fact]
    public void Header_ContainsMeta()
    {
        var code = LuaCatsGen.Header("app");
        Assert.Contains("---@meta", code);
    }

    [Fact]
    public void Footer_ContainsReturn()
    {
        var code = LuaCatsGen.Footer("app");
        Assert.Contains("return M", code);
    }
}
