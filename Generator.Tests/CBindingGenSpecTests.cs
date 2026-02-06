using Generator;
using Generator.CBinding;

namespace Generator.Tests;

public class CBindingGenSpecTests
{
    private static ModuleSpec MinimalSpec() => new(
        "sokol.test", "stest_",
        ["sokol_test.h"],
        null,
        [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
            [new FieldBinding("width", "width", new BindingType.Int()),
             new FieldBinding("title", "title", new BindingType.ConstPtr(new BindingType.Str()))],
            null)],
        [new FuncBinding("stest_init", "Init",
            [new ParamBinding("desc", new BindingType.ConstPtr(
                new BindingType.Struct("stest_desc", "sokol.test.Desc", "sokol.test.Desc")))],
            new BindingType.Void(), null)],
        [new EnumBinding("stest_mode", "sokol.test.Mode", "Mode",
            [new EnumItemBinding("DEFAULT", "STEST_MODE_DEFAULT", 0),
             new EnumItemBinding("FAST", "STEST_MODE_FAST", 5)],
            null)],
        []);

    [Fact]
    public void Generate_ContainsHeader()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_test.h\"", code);
    }

    [Fact]
    public void Generate_ContainsStructNew()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("l_stest_desc_new", code);
        Assert.Contains("lua_getfield(L, 1, \"width\")", code);
    }

    [Fact]
    public void Generate_ContainsFunc()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("l_stest_init", code);
    }

    [Fact]
    public void Generate_ContainsEnum()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_stest_mode", code);
        Assert.Contains("STEST_MODE_DEFAULT", code);
        Assert.Contains("STEST_MODE_FAST", code);
    }

    [Fact]
    public void Generate_ContainsLuaReg()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("sokol_test_funcs[]", code);
        Assert.Contains("{\"Desc\", l_stest_desc_new}", code);
        Assert.Contains("{\"Init\", l_stest_init}", code);
    }

    [Fact]
    public void Generate_ContainsLuaOpen()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("luaopen_sokol_test", code);
    }

    [Fact]
    public void Generate_ContainsMetatableRegistration()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_metatables", code);
        Assert.Contains("sokol.test.Desc", code);
    }

    [Fact]
    public void Generate_EnumInLuaOpen()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_stest_mode(L)", code);
    }

    // ===== Metamethods =====

    private static ModuleSpec SpecWithMetamethods() => new(
        "sokol.test", "stest_",
        ["sokol_test.h"],
        null,
        [new StructBinding("stest_event", "Event", "sokol.test.Event", true,
            [new FieldBinding("type", "type", new BindingType.Int()),
             new FieldBinding("key", "key", new BindingType.Int())],
            null)],
        [], [], []);

    [Fact]
    public void Generate_WithMetamethods_ContainsIndex()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__index", code);
        Assert.Contains("strcmp(key, \"type\")", code);
    }

    [Fact]
    public void Generate_WithMetamethods_ContainsNewindex()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__newindex", code);
    }

    [Fact]
    public void Generate_WithMetamethods_ContainsPairs()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__pairs", code);
    }

    [Fact]
    public void Generate_WithMetamethods_RegistersInMetatables()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("lua_setfield(L, -2, \"__index\")", code);
        Assert.Contains("lua_setfield(L, -2, \"__newindex\")", code);
        Assert.Contains("lua_setfield(L, -2, \"__pairs\")", code);
    }

    // ===== ExtraCCode / ExtraLuaRegs =====

    private static ModuleSpec SpecWithExtras() => new(
        "sokol.app", "sapp_",
        ["sokol_log.h", "sokol_app.h"],
        "/* extra C code */\n",
        [],
        [],
        [],
        [("Run", "l_sapp_run")]);

    [Fact]
    public void Generate_ContainsExtraCCode()
    {
        var code = CBindingGen.Generate(SpecWithExtras());
        Assert.Contains("/* extra C code */", code);
    }

    [Fact]
    public void Generate_ContainsExtraLuaRegs()
    {
        var code = CBindingGen.Generate(SpecWithExtras());
        Assert.Contains("{\"Run\", l_sapp_run}", code);
    }

    // ===== No enums =====

    private static ModuleSpec SpecNoEnums() => new(
        "sokol.log", "slog_",
        ["sokol_log.h"],
        null,
        [],
        [new FuncBinding("slog_func", "Func", [], new BindingType.Void(), null)],
        [],
        []);

    [Fact]
    public void Generate_NoEnums_UsesSimpleLuaOpen()
    {
        var code = CBindingGen.Generate(SpecNoEnums());
        Assert.Contains("luaopen_sokol_log", code);
        Assert.Contains("luaL_newlib", code);
    }

    // ===== Return types =====

    [Fact]
    public void Generate_IntReturn_PushesInteger()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_width", "Width", [], new BindingType.Int(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushinteger(L, stest_width())", code);
    }

    [Fact]
    public void Generate_BoolReturn_PushesBoolean()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_valid", "Valid", [], new BindingType.Bool(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushboolean(L, stest_valid())", code);
    }

    [Fact]
    public void Generate_FloatReturn_PushesNumber()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_scale", "Scale", [], new BindingType.Float(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushnumber(L, stest_scale())", code);
    }
}
