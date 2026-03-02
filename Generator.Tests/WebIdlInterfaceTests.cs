using Generator;
using Generator.CBinding;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlInterfaceTests
{
    [Fact]
    public void Parse_SimpleInterface()
    {
        var def = WebIdlParser.ParseFile("""
            interface ma_engine {
                void start();
                float get_volume();
            };
            """);
        Assert.Single(def.Interfaces);
        var iface = def.Interfaces[0];
        Assert.Equal("ma_engine", iface.CName);
        Assert.Equal(2, iface.Methods.Count);
        Assert.Equal("start", iface.Methods[0].Name);
        Assert.Equal("void", iface.Methods[0].ReturnType.Name);
        Assert.Equal("get_volume", iface.Methods[1].Name);
        Assert.Equal("float", iface.Methods[1].ReturnType.Name);
    }

    [Fact]
    public void Parse_InterfaceWithExtAttrs()
    {
        var def = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            enum ma_result { "MA_SUCCESS" = 0 };
            [InitFunc="ma_engine_init", UninitFunc="ma_engine_uninit"]
            interface ma_engine {
                void start();
            };
            """);
        var iface = def.Interfaces[0];
        Assert.Equal("ma_engine_init", iface.ExtAttrs!["InitFunc"]);
        Assert.Equal("ma_engine_uninit", iface.ExtAttrs!["UninitFunc"]);
    }

    [Fact]
    public void Parse_InterfaceMethodWithParams()
    {
        var def = WebIdlParser.ParseFile("""
            interface ma_sound {
                void set_position(float x, float y, float z);
                ma_result seek_to_pcm_frame(unsigned long long frameIndex);
            };
            """);
        var m0 = def.Interfaces[0].Methods[0];
        Assert.Equal("set_position", m0.Name);
        Assert.Equal(3, m0.Params.Count);
        Assert.Equal("float", m0.Params[0].Type.Name);
        var m1 = def.Interfaces[0].Methods[1];
        Assert.Equal("unsigned long long", m1.Params[0].Type.Name);
    }

    [Fact]
    public void Parse_MultipleDefinitions()
    {
        var def = WebIdlParser.ParseFile("""
            enum ma_result { "MA_SUCCESS" = 0 };
            dictionary ma_engine_config { unsigned long channels; };
            [InitFunc="ma_engine_init"]
            interface ma_engine { void start(); };
            """);
        Assert.Single(def.Enums);
        Assert.Single(def.Dictionaries);
        Assert.Single(def.Interfaces);
    }

    [Fact]
    public void Convert_InterfaceToOpaqueType()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            [InitFunc="ma_engine_init", UninitFunc="ma_engine_uninit",
             ConfigType="ma_engine_config", ConfigInitFunc="ma_engine_config_init"]
            interface ma_engine {
                float get_volume();
                void set_volume(float volume);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "miniaudio");
        Assert.NotNull(spec.OpaqueTypes);
        Assert.Single(spec.OpaqueTypes);
        var ot = spec.OpaqueTypes[0];
        Assert.Equal("ma_engine", ot.CName);
        Assert.Equal("Engine", ot.PascalName);
        Assert.Equal("miniaudio.Engine", ot.Metatable);
        Assert.Equal("ma_engine_init", ot.InitFunc);
        Assert.Equal("ma_engine_uninit", ot.UninitFunc);
        Assert.Equal("ma_engine_config", ot.ConfigType);
        Assert.Equal("ma_engine_config_init", ot.ConfigInitFunc);
        Assert.Equal(2, ot.Methods.Count);
        Assert.Equal("ma_engine_get_volume", ot.Methods[0].CName);
        Assert.Equal("get_volume", ot.Methods[0].LuaName);
    }

    [Fact]
    public void Convert_InterfaceWithDependency()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            [UninitFunc="ma_sound_uninit", Dependency="engine:1"]
            interface ma_sound {
                void start();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "miniaudio");
        var ot = spec.OpaqueTypes![0];
        Assert.Null(ot.InitFunc);
        Assert.Equal("ma_sound_uninit", ot.UninitFunc);
        Assert.NotNull(ot.Dependencies);
        Assert.Single(ot.Dependencies);
        Assert.Equal("engine", ot.Dependencies[0].Name);
        Assert.Equal(1, ot.Dependencies[0].ConstructorArgIndex);
    }

    [Fact]
    public void Convert_CamelCaseDictionary()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            [CamelCase]
            dictionary ma_engine_config {
                unsigned long listenerCount;
                unsigned long sampleRate;
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "miniaudio");
        var s = spec.Structs[0];
        Assert.Equal("listener_count", s.Fields[0].LuaName);
        Assert.Equal("listenerCount", s.Fields[0].CName);
        Assert.Equal("sample_rate", s.Fields[1].LuaName);
        Assert.Equal("sampleRate", s.Fields[1].CName);
    }

    [Fact]
    public void Convert_InterfaceTypeReference()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            [InitFunc="ma_engine_init"]
            interface ma_engine {
                void start();
            };
            [UninitFunc="ma_sound_uninit"]
            interface ma_sound {
                void stop();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "miniaudio");
        Assert.Equal(2, spec.OpaqueTypes!.Count);
        Assert.Equal("Engine", spec.OpaqueTypes[0].PascalName);
        Assert.Equal("Sound", spec.OpaqueTypes[1].PascalName);
    }

    [Fact]
    public void Convert_EnumItemNameUppercase()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="ma_"]
            enum ma_pan_mode {
                "ma_pan_mode_balance" = 0,
                "ma_pan_mode_pan" = 1,
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "miniaudio");
        Assert.Equal("BALANCE", spec.Enums[0].Items[0].LuaName);
        Assert.Equal("PAN", spec.Enums[0].Items[1].LuaName);
    }

    [Fact]
    public void Parse_NegativeEnumValues()
    {
        var def = WebIdlParser.ParseFile("""
            enum ma_result {
                "MA_SUCCESS" = 0,
                "MA_ERROR" = -1,
                "MA_INVALID_ARGS" = -2,
            };
            """);
        Assert.Equal(3, def.Enums[0].Values.Count);
        Assert.Equal(0, def.Enums[0].Values[0].Value);
        Assert.Equal(-1, def.Enums[0].Values[1].Value);
        Assert.Equal(-2, def.Enums[0].Values[2].Value);
    }

    // ─── Inheritance ───

    [Fact]
    public void Parse_InterfaceInheritance()
    {
        var def = WebIdlParser.ParseFile("""
            interface Shape {
                boolean IsValid();
            };
            interface SphereShape : Shape {
                float GetRadius();
            };
            """);
        Assert.Equal(2, def.Interfaces.Count);
        Assert.Null(def.Interfaces[0].ParentName);
        Assert.Equal("Shape", def.Interfaces[1].ParentName);
    }

    // ─── CppClass ───

    [Fact]
    public void Convert_CppClass_BasicInterface()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::PhysicsSystem", Constructor]
            interface PhysicsSystem {
                void OptimizeBroadPhase();
                unsigned long GetNumActiveBodies();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        Assert.Single(spec.OpaqueTypes);
        var ot = spec.OpaqueTypes[0];
        Assert.Equal("PhysicsSystem", ot.CName);
        Assert.Equal("JPH::PhysicsSystem", ot.CppClassName);
        Assert.Equal("PhysicsSystem", ot.PascalName);
        Assert.Equal("jolt.PhysicsSystem", ot.Metatable);
        Assert.NotNull(ot.ConstructorParams);
        Assert.Empty(ot.ConstructorParams);
        Assert.False(ot.NoDelete);
        Assert.Equal(2, ot.Methods.Count);
        Assert.Equal("OptimizeBroadPhase", ot.Methods[0].CppMethodName);
        Assert.Equal("GetNumActiveBodies", ot.Methods[1].CppMethodName);
    }

    [Fact]
    public void Convert_CppClass_NoDelete()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_"]
            [CppClass="JPH::BodyInterface", NoDelete]
            interface BodyInterface {
                boolean IsActive(unsigned long bodyID);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var ot = spec.OpaqueTypes[0];
        Assert.True(ot.NoDelete);
        Assert.Null(ot.ConstructorParams);
    }

    [Fact]
    public void Convert_CppClass_ConstructorWithParams()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_"]
            [CppClass="JPH::SphereShape"]
            interface SphereShape {
                [Constructor]
                void create(float radius);
                float GetRadius();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var ot = spec.OpaqueTypes[0];
        Assert.NotNull(ot.ConstructorParams);
        Assert.Single(ot.ConstructorParams);
        Assert.Equal("radius", ot.ConstructorParams[0].Name);
        // Constructor method should be excluded from methods list
        Assert.Single(ot.Methods);
        Assert.Equal("GetRadius", ot.Methods[0].LuaName);
    }

    [Fact]
    public void Convert_CppClass_PascalCaseToSnakeCase()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp, FuncNaming="PascalCase"]
            [CppClass="JPH::PhysicsSystem", Constructor]
            interface PhysicsSystem {
                void OptimizeBroadPhase();
                unsigned long GetNumActiveBodies();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var ot = spec.OpaqueTypes[0];
        Assert.Equal("optimize_broad_phase", ot.Methods[0].LuaName);
        Assert.Equal("OptimizeBroadPhase", ot.Methods[0].CppMethodName);
        Assert.Equal("get_num_active_bodies", ot.Methods[1].LuaName);
    }

    // ─── E2E: CppClass C++ code generation ───

    [Fact]
    public void E2E_CppClass_GeneratesCheckHelper()
    {
        var code = BuildCppClassCode();
        Assert.Contains("JPH::PhysicsSystem* check_PhysicsSystem(lua_State *L, int idx)", code);
        Assert.Contains("luaL_checkudata(L, idx, \"jolt.PhysicsSystem\")", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesConstructor()
    {
        var code = BuildCppClassCode();
        Assert.Contains("l_PhysicsSystem_new", code);
        Assert.Contains("new JPH::PhysicsSystem()", code);
        Assert.Contains("luaL_setmetatable(L, \"jolt.PhysicsSystem\")", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesDestructor()
    {
        var code = BuildCppClassCode();
        Assert.Contains("l_PhysicsSystem_gc", code);
        Assert.Contains("delete *pp", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesMethod()
    {
        var code = BuildCppClassCode();
        Assert.Contains("l_PhysicsSystem_OptimizeBroadPhase", code);
        Assert.Contains("self->OptimizeBroadPhase()", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesMethodWithReturn()
    {
        var code = BuildCppClassCode();
        Assert.Contains("l_PhysicsSystem_GetNumActiveBodies", code);
        Assert.Contains("self->GetNumActiveBodies()", code);
        Assert.Contains("lua_pushinteger", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesMethodTable()
    {
        var code = BuildCppClassCode();
        Assert.Contains("PhysicsSystem_methods[]", code);
        Assert.Contains("{\"destroy\", l_PhysicsSystem_destroy}", code);
        Assert.Contains("{\"OptimizeBroadPhase\", l_PhysicsSystem_OptimizeBroadPhase}", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesMetatable()
    {
        var code = BuildCppClassCode();
        Assert.Contains("register_metatables", code);
        Assert.Contains("luaL_newmetatable(L, \"jolt.PhysicsSystem\")", code);
        Assert.Contains("l_PhysicsSystem_gc", code);
    }

    [Fact]
    public void E2E_CppClass_GeneratesLuaReg()
    {
        var code = BuildCppClassCode();
        Assert.Contains("{\"PhysicsSystem\", l_PhysicsSystem_new}", code);
    }

    [Fact]
    public void E2E_CppClass_NoDelete_SkipsDestructor()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::BodyInterface", NoDelete]
            interface BodyInterface {
                boolean IsActive(unsigned long bodyID);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var code = CBindingGen.Generate(spec);
        Assert.DoesNotContain("l_BodyInterface_gc", code);
        Assert.DoesNotContain("l_BodyInterface_destroy", code);
        Assert.DoesNotContain("l_BodyInterface_new", code);
        Assert.Contains("self->IsActive(bodyID)", code);
    }

    [Fact]
    public void E2E_CppClass_ConstructorWithParams()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::SphereShape"]
            interface SphereShape {
                [Constructor]
                void create(float radius);
                float GetRadius();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var code = CBindingGen.Generate(spec);
        Assert.Contains("new JPH::SphereShape(radius)", code);
        Assert.Contains("float radius = (float)luaL_checknumber(L, 1)", code);
        Assert.Contains("self->GetRadius()", code);
    }

    // ─── Jolt IDL E2E ───

    [Fact]
    public void E2E_JoltIdl_ParseAndGenerate()
    {
        // Find repo root by walking up from test assembly location
        var dir = AppContext.BaseDirectory;
        while (dir != null && !File.Exists(Path.Combine(dir, "CLAUDE.md")))
            dir = Path.GetDirectoryName(dir);
        if (dir == null) return;
        var idlPath = Path.Combine(dir, "idl", "jolt.idl");
        if (!File.Exists(idlPath)) return;

        var source = File.ReadAllText(idlPath);
        var file = WebIdlParser.ParseFile(source);

        Assert.Single(file.Enums);
        Assert.Equal("EMotionType", file.Enums[0].CName);
        Assert.Single(file.Interfaces);
        Assert.Equal("World", file.Interfaces[0].CName);

        var spec = WebIdlToSpec.Convert(file, "jolt");
        Assert.True(spec.IsCpp);
        Assert.True(spec.StandaloneEntry);
        Assert.Single(spec.OpaqueTypes);
        var ot = spec.OpaqueTypes[0];
        Assert.Equal("JoltWorld", ot.CppClassName);
        Assert.Null(ot.ConstructorParams); // Constructor handled via ExtraLuaReg
        Assert.NotNull(ot.ExtraMethods);
        Assert.Equal(3, ot.ExtraMethods.Count);

        // Generate code — should not throw
        var code = CBindingGen.Generate(spec);
        Assert.Contains("self->set_gravity(x, y, z)", code);
        Assert.Contains("self->update(dt, steps)", code);
        Assert.Contains("self->create_box(", code);
        Assert.Contains("{\"get_gravity\", l_jolt_get_gravity}", code);
        Assert.Contains("{\"get_position\", l_jolt_get_position}", code);
        Assert.Contains("register_metatables", code);
        Assert.Contains("{\"World\", l_jolt_World_new}", code);
        // Standalone entry: standard Lua CFunction signature
        Assert.Contains("int luaopen_jolt(lua_State *L)", code);
    }

    private static string BuildCppClassCode()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::PhysicsSystem", Constructor]
            interface PhysicsSystem {
                void OptimizeBroadPhase();
                unsigned long GetNumActiveBodies();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        return CBindingGen.Generate(spec);
    }
}
