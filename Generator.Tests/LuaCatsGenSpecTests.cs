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
        Assert.Contains("---@class sokol.test.Mode", code);
        Assert.Contains("---@field Mode sokol.test.Mode", code);
        Assert.Contains("---@field DEFAULT sokol.test.Mode", code);
        Assert.Contains("---@field FAST sokol.test.Mode", code);
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
        Assert.Contains("---@class sokol_empty_module", code);
        Assert.Contains("return M", code);
    }

    // ===== Output params + multi-return =====

    [Fact]
    public void Generate_OutputParam_IncludedAsOptionalInput()
    {
        var spec = new ModuleSpec(
            "imgui", "ImGui_", ["imgui.h"], null,
            [],
            [new FuncBinding("ImGui_Checkbox", "Checkbox",
                [new ParamBinding("label", new BindingType.Str()),
                 new ParamBinding("v", new BindingType.Bool(), IsOutput: true)],
                new BindingType.Bool(), null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("fun(label: string, v?: boolean): boolean, boolean", code);
    }

    [Fact]
    public void Generate_MultiReturn_AllTypesListed()
    {
        var spec = new ModuleSpec(
            "imgui", "ImGui_", ["imgui.h"], null,
            [],
            [new FuncBinding("ImGui_SliderFloat", "SliderFloat",
                [new ParamBinding("label", new BindingType.Str()),
                 new ParamBinding("v", new BindingType.Float(), IsOutput: true),
                 new ParamBinding("v_min", new BindingType.Float()),
                 new ParamBinding("v_max", new BindingType.Float())],
                new BindingType.Bool(), null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("fun(label: string, v?: number, v_min: number, v_max: number): boolean, number", code);
    }

    [Fact]
    public void Generate_NoOutputParam_SingleReturn()
    {
        var spec = new ModuleSpec(
            "imgui", "ImGui_", ["imgui.h"], null,
            [],
            [new FuncBinding("ImGui_Begin", "Begin",
                [new ParamBinding("name", new BindingType.Str())],
                new BindingType.Bool(), null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("fun(name: string): boolean", code);
    }

    // ===== ValueStruct =====

    [Fact]
    public void Generate_ValueStruct_Type()
    {
        var vsType = new BindingType.ValueStruct("b2Vec2", "number[]",
            [new BindingType.ScalarField("x"), new BindingType.ScalarField("y")]);
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null,
            [],
            [new FuncBinding("b2Body_GetPosition", "BodyGetPosition",
                [new ParamBinding("bodyId", new BindingType.Struct("b2BodyId", "b2d.BodyId", "b2d.BodyId"))],
                vsType, null)],
            [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("fun(bodyId: b2d.BodyId): number[]", code);
    }

    // ===== ArrayAdapter =====

    [Fact]
    public void Generate_ArrayAdapter_GeneratesArrayReturnType()
    {
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null, [], [], [], [],
            ArrayAdapters:
            [
                new ArrayAdapterBinding("body_get_shapes", "b2Body_GetShapeCount", "b2Body_GetShapes",
                    [new ParamBinding("bodyId", new BindingType.Struct("b2BodyId", "b2d.BodyId", "b2d.BodyId"))],
                    new BindingType.Struct("b2ShapeId", "b2d.ShapeId", "b2d.ShapeId")),
            ]);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("---@field body_get_shapes fun(bodyId: b2d.BodyId): b2d.ShapeId[]", code);
    }

    // ===== ExtraLuaFuncs =====

    [Fact]
    public void Generate_ExtraLuaFuncs_IncludedInModule()
    {
        var spec = new ModuleSpec(
            "miniaudio", "ma_", ["miniaudio.h"], null,
            [], [], [], [],
            ExtraLuaFuncs:
            [
                new FuncBinding("l_ma_sound_new", "SoundInitFromFile",
                    [new ParamBinding("engine", new BindingType.Struct("ma_engine", "miniaudio.Engine", "miniaudio.Engine")),
                     new ParamBinding("filePath", new BindingType.Str()),
                     new ParamBinding("flags", new BindingType.Int(), IsOptional: true)],
                    new BindingType.Struct("ma_sound", "miniaudio.Sound", "miniaudio.Sound"), null),
            ]);
        var code = LuaCatsGen.Generate(spec);
        Assert.Contains("SoundInitFromFile fun(engine: miniaudio.Engine, filePath: string, flags?: integer): miniaudio.Sound", code);
    }
}
