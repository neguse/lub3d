using Generator;
using Generator.ClangAst;
using Generator.Modules.Jolt;

namespace Generator.Tests;

public class JoltModuleTests
{
    private static readonly Dictionary<string, string> PrefixToModule = new()
    {
        ["jolt_"] = "jolt",
    };

    private static TypeRegistry EmptyRegistry()
    {
        var module = new Module("jolt", "jolt_", [], []);
        return TypeRegistry.FromModule(module);
    }

    [Fact]
    public void ModuleName_IsJolt()
    {
        var module = new JoltModule();
        Assert.Equal("jolt", module.ModuleName);
    }

    [Fact]
    public void BuildSpec_HasWorldOpaqueType()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        Assert.Single(spec.OpaqueTypes);
        Assert.Equal("JoltWorld", spec.OpaqueTypes[0].CName);
        Assert.Equal("World", spec.OpaqueTypes[0].PascalName);
        Assert.Equal("jolt.World", spec.OpaqueTypes[0].LuaClassName);
    }

    [Fact]
    public void BuildSpec_WorldHasDestroyMethod()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        var world = spec.OpaqueTypes[0];
        Assert.NotNull(world.UninitFunc);
    }

    [Fact]
    public void BuildSpec_WorldMethods_ContainsCorePhysics()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        var methods = spec.OpaqueTypes[0].Methods;

        var names = methods.Select(m => m.LuaName).ToHashSet();
        Assert.Contains("set_gravity", names);
        Assert.Contains("get_gravity", names);
        Assert.Contains("update", names);
        Assert.Contains("optimize", names);
        Assert.Contains("create_box", names);
        Assert.Contains("create_sphere", names);
        Assert.Contains("remove_body", names);
        Assert.Contains("get_position", names);
        Assert.Contains("get_rotation", names);
        Assert.Contains("set_linear_velocity", names);
        Assert.Contains("add_impulse", names);
        Assert.Contains("is_active", names);
        Assert.Contains("body_count", names);
    }

    [Fact]
    public void BuildSpec_HasInitExtraLuaFunc()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        Assert.Single(spec.ExtraLuaFuncs);
        Assert.Equal("init", spec.ExtraLuaFuncs[0].LuaName);
    }

    [Fact]
    public void BuildSpec_InitHasOptionalParams()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        var initFunc = spec.ExtraLuaFuncs[0];
        Assert.Equal(3, initFunc.Params.Count);
        Assert.True(initFunc.Params.All(p => p.IsOptional));
    }

    [Fact]
    public void BuildSpec_IsCpp()
    {
        var module = new JoltModule();
        var spec = module.BuildSpec(EmptyRegistry(), PrefixToModule);
        Assert.True(spec.IsCpp);
    }

    [Fact]
    public void GenerateC_ReturnsEmpty()
    {
        var module = new JoltModule();
        var code = module.GenerateC(EmptyRegistry(), PrefixToModule);
        Assert.Equal("", code);
    }

    [Fact]
    public void GenerateLua_ContainsWorldClass()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        Assert.Contains("---@class jolt.World", lua);
    }

    [Fact]
    public void GenerateLua_ContainsDestroyMethod()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        Assert.Contains("destroy", lua);
        Assert.Contains("fun(self: jolt.World)", lua);
    }

    [Fact]
    public void GenerateLua_ContainsMultiReturnMethods()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        // get_position returns 3 numbers
        Assert.Contains("get_position", lua);
        Assert.Contains("number, number, number", lua);
        // get_rotation returns 4 numbers
        Assert.Contains("get_rotation", lua);
        Assert.Contains("number, number, number, number", lua);
    }

    [Fact]
    public void GenerateLua_ContainsInitFunction()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        Assert.Contains("---@field init", lua);
        Assert.Contains("jolt.World", lua);
    }

    [Fact]
    public void GenerateLua_ContainsMotionTypeConstants()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        Assert.Contains("STATIC", lua);
        Assert.Contains("KINEMATIC", lua);
        Assert.Contains("DYNAMIC", lua);
    }

    [Fact]
    public void GenerateLua_ContainsModuleReturn()
    {
        var module = new JoltModule();
        var lua = module.GenerateLua(EmptyRegistry(), PrefixToModule);
        Assert.Contains("return M", lua);
    }

    [Fact]
    public void CollectSkips_ReturnsEmpty()
    {
        var module = (IModule)new JoltModule();
        var skips = module.CollectSkips(EmptyRegistry());
        Assert.Equal("jolt", skips.ModuleName);
        Assert.Empty(skips.Funcs);
        Assert.Empty(skips.Structs);
        Assert.Empty(skips.Enums);
    }
}
