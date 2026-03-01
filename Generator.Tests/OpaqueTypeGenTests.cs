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
        Assert.Contains("{\"engine_init\", l_ma_engine_new}", code);
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
        Assert.Contains("---@field engine_init fun(config?: any): miniaudio.Engine", code);
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

    // ===== destroy method generation =====

    [Fact]
    public void C_UninitFunc_GeneratesDestroyMethod()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("l_ma_engine_destroy", code);
        Assert.Contains("ma_engine_uninit(*pp)", code);
    }

    [Fact]
    public void C_UninitFunc_MethodTableContainsDestroy()
    {
        var code = CBindingGen.Generate(OpaqueSpec());
        Assert.Contains("{\"destroy\", l_ma_engine_destroy}", code);
    }

    [Fact]
    public void Lua_UninitFunc_ContainsDestroyField()
    {
        var code = LuaCatsGen.Generate(OpaqueSpec());
        Assert.Contains("---@field destroy fun(self: miniaudio.Engine)", code);
    }

    // ===== dependency uservalue slots =====

    private static ModuleSpec OpaqueSpecWithDeps() => new(
        "miniaudio", "ma_",
        ["miniaudio.h"],
        null,
        [], [], [],
        [],
        OpaqueTypes:
        [
            new OpaqueTypeBinding(
                "ma_sound", "Sound", "miniaudio.Sound", "miniaudio.Sound",
                InitFunc: "ma_sound_init",
                UninitFunc: "ma_sound_uninit",
                ConfigType: null,
                ConfigInitFunc: null,
                Methods: [],
                SourceLink: null,
                Dependencies:
                [
                    new DependencyBinding(1, 1, "engine")
                ]
            )
        ]
    );

    [Fact]
    public void C_Dependencies_GeneratesUservalueSlots()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithDeps());
        Assert.Contains("lua_newuserdatauv(L, sizeof(ma_sound*), 1)", code);
        Assert.Contains("lua_pushvalue(L, 1)", code);
        Assert.Contains("lua_setiuservalue(L, -2, 1)", code);
    }

    // ===== CustomCallCode =====

    private static ModuleSpec OpaqueSpecWithCustomCall() => new(
        "test", "test_",
        ["test.h"],
        null,
        [], [], [],
        [],
        OpaqueTypes:
        [
            new OpaqueTypeBinding(
                "TestObj", "Obj", "test.Obj", "test.Obj",
                InitFunc: null, UninitFunc: "test_obj_uninit",
                ConfigType: null, ConfigInitFunc: null,
                Methods:
                [
                    new MethodBinding("l_test_custom", "custom_method",
                        [new ParamBinding("x", new BindingType.Float())],
                        new BindingType.Void(), null,
                        CustomCallCode: "    {self}->DoThing({x});",
                        ReturnCount: 0),
                    new MethodBinding("l_test_multi", "multi_return",
                        [], new BindingType.Void(), null,
                        CustomCallCode: """
                                lua_pushnumber(L, {self}->GetX());
                                lua_pushnumber(L, {self}->GetY());
                                lua_pushnumber(L, {self}->GetZ());
                            """,
                        ReturnCount: 3),
                ],
                SourceLink: null
            )
        ]
    );

    [Fact]
    public void C_CustomCallCode_AppearsInOutput()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomCall());
        Assert.Contains("self->DoThing(x)", code);
        Assert.DoesNotContain("l_test_custom(self", code);
    }

    [Fact]
    public void C_CustomCallCode_ReturnCount()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomCall());
        // multi_return should have return 3
        Assert.Contains("return 3;", code);
        // custom_method should have return 0
        Assert.Contains("return 0;", code);
    }

    [Fact]
    public void C_CustomCallCode_MultiReturn_PushesValues()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomCall());
        Assert.Contains("lua_pushnumber(L, self->GetX())", code);
        Assert.Contains("lua_pushnumber(L, self->GetY())", code);
        Assert.Contains("lua_pushnumber(L, self->GetZ())", code);
    }

    // ===== CustomDestructorCode =====

    private static ModuleSpec OpaqueSpecWithCustomDestructor() => new(
        "test", "test_",
        ["test.h"],
        null,
        [], [], [],
        [],
        OpaqueTypes:
        [
            new OpaqueTypeBinding(
                "TestObj", "Obj", "test.Obj", "test.Obj",
                InitFunc: null, UninitFunc: null,
                ConfigType: null, ConfigInitFunc: null,
                Methods: [],
                SourceLink: null,
                CustomDestructorCode: "custom_free(*{pp});\n        *{pp} = NULL;"
            )
        ]
    );

    [Fact]
    public void C_CustomDestructorCode_AppearsInGc()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomDestructor());
        Assert.Contains("l_TestObj_gc", code);
        Assert.Contains("custom_free(*pp)", code);
    }

    [Fact]
    public void C_CustomDestructorCode_GeneratesDestroyMethod()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomDestructor());
        Assert.Contains("l_TestObj_destroy", code);
        Assert.Contains("custom_free(*pp)", code);
    }

    [Fact]
    public void C_CustomDestructorCode_MethodTableContainsDestroy()
    {
        var code = CBindingGen.Generate(OpaqueSpecWithCustomDestructor());
        Assert.Contains("{\"destroy\", l_TestObj_destroy}", code);
    }

    // ===== C++ mode with OpaqueTypes =====

    private static ModuleSpec CppOpaqueSpec() => new(
        "test_cpp", "test_",
        ["test.h"],
        "// extra code here\n",
        [], [], [],
        [("init", "l_test_init")],
        OpaqueTypes:
        [
            new OpaqueTypeBinding(
                "TestObj", "Obj", "test.Obj", "test.Obj",
                InitFunc: null, UninitFunc: null,
                ConfigType: null, ConfigInitFunc: null,
                Methods:
                [
                    new MethodBinding("l_test_method", "method",
                        [], new BindingType.Void(), null,
                        CustomCallCode: "    {self}->DoIt();",
                        ReturnCount: 0),
                ],
                SourceLink: null,
                CustomDestructorCode: "delete *{pp}; *{pp} = NULL;"
            )
        ],
        IsCpp: true
    );

    [Fact]
    public void Cpp_OpaqueType_GeneratesExternCLuaOpen()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("extern \"C\" LUB3D_API int luaopen_test_cpp(lua_State *L)", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsRegisterMetatables()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("register_metatables(L)", code);
        Assert.Contains("luaL_newmetatable(L, \"test.Obj\")", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsExtraCCode()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("// extra code here", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsCheckHelper()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("TestObj* check_TestObj(lua_State *L, int idx)", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsCustomMethod()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("self->DoIt()", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsCustomDestructor()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("delete *pp; *pp = NULL;", code);
    }

    [Fact]
    public void Cpp_OpaqueType_ContainsLuaRegWithExtraRegs()
    {
        var code = CBindingGen.Generate(CppOpaqueSpec());
        Assert.Contains("{\"init\", l_test_init}", code);
    }
}
