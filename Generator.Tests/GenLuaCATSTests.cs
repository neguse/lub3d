using Generator;
using Generator.LuaCats;

namespace Generator.Tests;

public class GenLuaCATSTests
{
    private static ModuleSpec MakeTestSpec() => new(
        ModuleName: "app",
        Prefix: "sapp_",
        CIncludes: [],
        ExtraCCode: null,
        Structs: [
            new StructBinding(
                CName: "sapp_desc",
                PascalName: "Desc",
                Metatable: "app.Desc",
                HasMetamethods: true,
                Fields: [
                    new FieldBinding("width", "width", new BindingType.Int()),
                    new FieldBinding("init_cb", "init_cb", new BindingType.Callback([], null))
                ],
                SourceLink: null)
        ],
        Funcs: [
            new FuncBinding(
                CName: "sapp_run",
                LuaName: "Run",
                Params: [new ParamBinding("desc", new BindingType.Struct("sapp_desc", "app.Desc", "app.Desc"))],
                ReturnType: new BindingType.Void(),
                SourceLink: null),
            new FuncBinding(
                CName: "sapp_width",
                LuaName: "Width",
                Params: [],
                ReturnType: new BindingType.Int(),
                SourceLink: null)
        ],
        Enums: [
            new EnumBinding(
                CName: "sapp_event_type",
                LuaName: "app.EventType",
                FieldName: "EventType",
                Items: [
                    new EnumItemBinding("INVALID", "SAPP_EVENTTYPE_INVALID", 0),
                    new EnumItemBinding("KEY_DOWN", "SAPP_EVENTTYPE_KEY_DOWN", 1)
                ],
                SourceLink: null)
        ],
        ExtraLuaRegs: []
    );

    [Fact]
    public void StructClass_ContainsFields()
    {
        var code = LuaCatsGen.Generate(MakeTestSpec());
        Assert.Contains("---@class app.Desc", code);
        Assert.Contains("---@field width? integer", code);
        Assert.Contains("---@field init_cb? fun()", code);
    }

    [Fact]
    public void FuncField_VoidReturn()
    {
        var code = LuaCatsGen.Generate(MakeTestSpec());
        Assert.Contains("---@field Run fun(desc: app.Desc)", code);
    }

    [Fact]
    public void FuncField_IntReturn()
    {
        var code = LuaCatsGen.Generate(MakeTestSpec());
        Assert.Contains("---@field Width fun(): integer", code);
    }

    [Fact]
    public void EnumDef_ContainsValues()
    {
        var code = LuaCatsGen.Generate(MakeTestSpec());
        Assert.Contains("---@class app.EventType", code);
        Assert.Contains("---@field INVALID app.EventType", code);
        Assert.Contains("---@field KEY_DOWN app.EventType", code);
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
