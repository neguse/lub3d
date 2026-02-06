using Generator;
using Generator.LuaCats;

namespace Generator.Tests;

public class LuaCatsGenSpecTests
{
    private static ModuleSpec MinimalSpec() => new(
        "sokol.test", "stest_",
        ["sokol_test.h"],
        null,
        [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
            [new FieldBinding("width", "width", new BindingType.Int()),
             new FieldBinding("title", "title", new BindingType.Str())],
            null)],
        [new FuncBinding("stest_init", "Init",
            [new ParamBinding("desc", new BindingType.Struct("stest_desc", "sokol.test.Desc", "sokol.test.Desc"))],
            new BindingType.Void(), null),
         new FuncBinding("stest_width", "Width", [], new BindingType.Int(), null)],
        [new EnumBinding("stest_mode", "sokol.test.Mode", "Mode",
            [new EnumItemBinding("DEFAULT", "STEST_MODE_DEFAULT", 0),
             new EnumItemBinding("FAST", "STEST_MODE_FAST", 5)],
            null)],
        []);

    [Fact]
    public void Generate_ContainsHeader()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@meta", code);
        Assert.Contains("sokol.test", code);
    }

    [Fact]
    public void Generate_ContainsStructClass()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@class sokol.test.Desc", code);
        Assert.Contains("---@field width? integer", code);
        Assert.Contains("---@field title? string", code);
    }

    [Fact]
    public void Generate_ContainsStructCtor()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@field Desc fun(t?: sokol.test.Desc): sokol.test.Desc", code);
    }

    [Fact]
    public void Generate_ContainsModuleClass()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@class sokol.test", code);
        Assert.Contains("local M = {}", code);
    }

    [Fact]
    public void Generate_ContainsFuncField_VoidReturn()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@field Init fun(desc: sokol.test.Desc)", code);
    }

    [Fact]
    public void Generate_ContainsFuncField_IntReturn()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@field Width fun(): integer", code);
    }

    [Fact]
    public void Generate_ContainsEnumDef()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("---@enum sokol.test.Mode", code);
        Assert.Contains("M.Mode = {", code);
        Assert.Contains("DEFAULT = 0", code);
        Assert.Contains("FAST = 5", code);
    }

    [Fact]
    public void Generate_ContainsFooter()
    {
        var code = LuaCatsGen.Generate(MinimalSpec());
        Assert.Contains("return M", code);
    }

    // ===== BindingType → LuaCats.Type 変換 =====

    [Fact]
    public void Generate_BoolField()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("enabled", "enabled", new BindingType.Bool())], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field enabled? boolean", code);
    }

    [Fact]
    public void Generate_FloatField()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("scale", "scale", new BindingType.Float())], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field scale? number", code);
    }

    [Fact]
    public void Generate_VoidPtrField()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("user_data", "user_data", new BindingType.VoidPtr())], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field user_data? lightuserdata?", code);
    }

    [Fact]
    public void Generate_CallbackField()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("init_cb", "init", new BindingType.Callback([], null))], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field init? fun()", code);
    }

    [Fact]
    public void Generate_CallbackFieldWithArgs()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("event_cb", "event",
                    new BindingType.Callback(
                        [("arg0", new BindingType.Int())], null))], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field event? fun(arg0: integer)", code);
    }

    // ===== Enum 型フィールド =====

    [Fact]
    public void Generate_EnumField()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_event", "Event", "sokol.test.Event", false,
                [new FieldBinding("type", "type",
                    new BindingType.Enum("stest_event_type", "sokol.test.EventType"))], null)],
            [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field type? sokol.test.EventType", code);
    }

    [Fact]
    public void Generate_EnumReturn()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_get_mode", "GetMode", [],
                new BindingType.Enum("stest_mode", "sokol.test.Mode"), null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field GetMode fun(): sokol.test.Mode", code);
    }

    [Fact]
    public void Generate_EnumParam()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_set_mode", "SetMode",
                [new ParamBinding("mode", new BindingType.Enum("stest_mode", "sokol.test.Mode"))],
                new BindingType.Void(), null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field SetMode fun(mode: sokol.test.Mode)", code);
    }

    // ===== SourceLink =====

    [Fact]
    public void Generate_WithSourceLink()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("width", "width", new BindingType.Int())],
                "https://github.com/test#L42")],
            [new FuncBinding("stest_init", "Init", [], new BindingType.Void(),
                "https://github.com/test#L100")],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("[source](https://github.com/test#L42)", code);
        Assert.Contains("[source](https://github.com/test#L100)", code);
    }

    // ===== Empty module =====

    [Fact]
    public void Generate_EmptyModule()
    {
        var spec = new ModuleSpec(
            "sokol.empty", "sempty_", ["sokol_empty.h"], null,
            [], [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@meta", code);
        Assert.Contains("---@class sokol.empty", code);
        Assert.Contains("return M", code);
    }
}
