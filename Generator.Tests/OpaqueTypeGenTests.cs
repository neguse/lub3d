using Generator;
using Generator.CBinding;
using Generator.LuaCats;

namespace Generator.Tests;

public class OpaqueTypeGenTests
{
    private static ModuleSpec OpaqueSpec() => new(
        "miniaudio", "ma_",
        ["miniaudio.h"],
        null,
        [], [], [],
        [],
        OpaqueTypes:
        [
            new OpaqueTypeBinding(
                "ma_engine", "Engine", "miniaudio.Engine", "miniaudio.Engine",
                InitFunc: "ma_engine_init",
                UninitFunc: "ma_engine_uninit",
                ConfigType: "ma_engine_config",
                ConfigInitFunc: "ma_engine_config_init",
                Methods:
                [
                    new MethodBinding("ma_engine_start", "Start", [],
                        new BindingType.Void(), null),
                    new MethodBinding("ma_engine_set_volume", "SetVolume",
                        [new ParamBinding("volume", new BindingType.Float())],
                        new BindingType.Void(), null),
                    new MethodBinding("ma_engine_get_volume", "GetVolume", [],
                        new BindingType.Float(), null),
                ],
                SourceLink: null
            )
        ]
    );

    // ===== CBindingGen: Opaque type =====

    [Fact]
    public void C_ContainsCheckHelper()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("ma_engine* check_ma_engine(lua_State *L, int idx)", code);
        Assert.Contains("luaL_checkudata(L, idx, \"miniaudio.Engine\")", code);
    }

    [Fact]
    public void C_ContainsConstructor()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_new", code);
        Assert.Contains("malloc(sizeof(ma_engine))", code);
        Assert.Contains("ma_engine_config_init()", code);
        Assert.Contains("ma_engine_init(", code);
        Assert.Contains("luaL_setmetatable(L, \"miniaudio.Engine\")", code);
    }

    [Fact]
    public void C_ContainsDestructor()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_gc", code);
        Assert.Contains("ma_engine_uninit(", code);
        Assert.Contains("free(", code);
    }

    [Fact]
    public void C_ContainsVoidMethod()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_start", code);
        Assert.Contains("ma_engine_start(", code);
    }

    [Fact]
    public void C_ContainsSetterMethod()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_set_volume", code);
        Assert.Contains("luaL_checknumber(L, 2)", code);
        Assert.Contains("ma_engine_set_volume(", code);
    }

    [Fact]
    public void C_ContainsGetterMethod()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_get_volume", code);
        Assert.Contains("lua_pushnumber(L, ma_engine_get_volume(", code);
    }

    [Fact]
    public void C_ContainsMethodTable()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("ma_engine_methods[]", code);
        Assert.Contains("{\"Start\", l_ma_engine_start}", code);
        Assert.Contains("{\"SetVolume\", l_ma_engine_set_volume}", code);
        Assert.Contains("{\"GetVolume\", l_ma_engine_get_volume}", code);
    }

    [Fact]
    public void C_ContainsMetatableWithGcAndIndex()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("\"miniaudio.Engine\"", code);
        Assert.Contains("\"__gc\"", code);
        Assert.Contains("\"__index\"", code);
    }

    [Fact]
    public void C_ContainsLuaOpenWithConstructor()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("luaopen_miniaudio", code);
        Assert.Contains("{\"EngineInit\", l_ma_engine_new}", code);
    }

    [Fact]
    public void C_OpaqueMethodParamStartsAt2()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        // self is at index 1, first user param at index 2
        Assert.Contains("check_ma_engine(L, 1)", code);
    }

    // ===== Constructor error handling =====

    [Fact]
    public void C_Constructor_ChecksResult()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("MA_SUCCESS", code);
        Assert.Contains("luaL_error", code);
    }

    // ===== No opaque types → no change =====

    [Fact]
    public void C_EmptyOpaqueTypes_NoChange()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [], [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.DoesNotContain("check_", code);
        Assert.DoesNotContain("malloc", code);
    }

    // ===== LuaCatsGen: Opaque type =====

    [Fact]
    public void Lua_ContainsOpaqueClass()
    {
        var code = LuaCatsGen.Generate(OpaqueSpec());
        Assert.Contains("---@class miniaudio.Engine", code);
    }

    [Fact]
    public void Lua_ContainsMethodAnnotations()
    {
        var code = LuaCatsGen.Generate(OpaqueSpec());
        Assert.Contains("---@field Start fun(self: miniaudio.Engine)", code);
        Assert.Contains("---@field SetVolume fun(self: miniaudio.Engine, volume: number)", code);
        Assert.Contains("---@field GetVolume fun(self: miniaudio.Engine): number", code);
    }

    [Fact]
    public void Lua_ContainsConstructorInModule()
    {
        var code = LuaCatsGen.Generate(OpaqueSpec());
        Assert.Contains("---@field EngineInit fun(): miniaudio.Engine", code);
    }

    [Fact]
    public void Lua_EmptyOpaqueTypes_NoChange()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [], [], [], []);
        var code = LuaCatsGen.Generate(spec);
        Assert.DoesNotContain("---@class sokol.test.Engine", code);
    }
}
