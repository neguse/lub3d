using Generator;
using Generator.CBinding;
using Generator.LuaCats;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlValueTypeTests
{
    // ─── StripNamespace ───

    [Theory]
    [InlineData("JPH::Vec3", "Vec3")]
    [InlineData("JPH::Body::BodyID", "BodyID")]
    [InlineData("Vec3", "Vec3")]
    [InlineData("", "")]
    public void StripNamespace(string input, string expected)
    {
        Assert.Equal(expected, Pipeline.StripNamespace(input));
    }

    // ─── ValueType check helper (inline userdata) ───

    [Fact]
    public void ValueType_CheckHelper_DirectCast()
    {
        var code = BuildValueTypeCode();
        // ValueType check: direct cast, no double-indirect
        Assert.Contains("(JPH::Vec3*)luaL_checkudata(L, idx, \"jolt.Vec3\")", code);
        // Should NOT contain double-indirect
        Assert.DoesNotContain("JPH::Vec3** pp", code);
    }

    [Fact]
    public void ValueType_Constructor_PlacementNew()
    {
        var code = BuildValueTypeCode();
        Assert.Contains("lua_newuserdatauv(L, sizeof(JPH::Vec3), 0)", code);
        Assert.Contains("new(p) JPH::Vec3(x, y, z)", code);
        // Should NOT contain heap allocation
        Assert.DoesNotContain("new JPH::Vec3(", code);
    }

    [Fact]
    public void ValueType_Destructor_ExplicitDtor()
    {
        var code = BuildValueTypeCode();
        Assert.Contains("p->~Vec3()", code);
        // Should NOT contain delete
        Assert.DoesNotContain("delete *pp", code);
    }

    [Fact]
    public void ValueType_NoDestroyMethod()
    {
        var code = BuildValueTypeCode();
        Assert.DoesNotContain("l_Vec3_destroy", code);
    }

    [Fact]
    public void ValueType_MethodTable_NoDestroy()
    {
        var code = BuildValueTypeCode();
        Assert.Contains("Vec3_methods[]", code);
        Assert.DoesNotContain("{\"destroy\"", code);
    }

    // ─── OpaqueRef parameter ───

    [Fact]
    public void OpaqueRef_ParamDecl_ValueType()
    {
        var code = BuildOpaqueRefParamCode();
        // OpaqueRef param uses check function
        Assert.Contains("check_Vec3(L, 2)", code);
        // ValueType param is dereferenced in method call
        Assert.Contains("self->SetGravity(*gravity)", code);
    }

    [Fact]
    public void OpaqueRef_ReturnValue_ValueType()
    {
        var code = BuildOpaqueRefParamCode();
        // Return value creates inline userdata
        Assert.Contains("JPH::Vec3 _result = self->GetGravity()", code);
        Assert.Contains("new(_ud) JPH::Vec3(_result)", code);
        Assert.Contains("luaL_setmetatable(L, \"jolt.Vec3\")", code);
    }

    [Fact]
    public void OpaqueRef_ParamDecl_PtrType()
    {
        var code = BuildOpaqueRefPtrCode();
        // PtrType param uses check function
        Assert.Contains("check_Shape(L, 2)", code);
        // PtrType param is NOT dereferenced
        Assert.Contains("self->SetShape(shape)", code);
    }

    // ─── Inheritance ───

    [Fact]
    public void Inheritance_ParentMethodsCopied()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Shape", Constructor]
            interface Shape {
                boolean IsValid();
                unsigned long GetType();
            };
            [CppClass="JPH::SphereShape", Constructor]
            interface SphereShape : Shape {
                float GetRadius();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var sphere = spec.OpaqueTypes.First(o => o.CName == "SphereShape");
        // Should have inherited methods + own methods
        Assert.Equal(3, sphere.Methods.Count);
        Assert.Equal("IsValid", sphere.Methods[0].LuaName);
        Assert.Equal("GetType", sphere.Methods[1].LuaName);
        Assert.Equal("GetRadius", sphere.Methods[2].LuaName);
    }

    [Fact]
    public void Inheritance_ChildOverridesParent()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Base"]
            interface Base {
                long GetType();
            };
            [CppClass="JPH::Child"]
            interface Child : Base {
                long GetType();
                float GetValue();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        var child = spec.OpaqueTypes.First(o => o.CName == "Child");
        // GetType defined in child should NOT be duplicated
        Assert.Equal(2, child.Methods.Count);
        Assert.Equal("GetType", child.Methods[0].LuaName);
        Assert.Equal("GetValue", child.Methods[1].LuaName);
    }

    // ─── OpaqueRef in LuaCATS ───

    [Fact]
    public void OpaqueRef_LuaCATS_ParamType()
    {
        var code = BuildOpaqueRefLuaCATS();
        Assert.Contains("jolt.Vec3", code);
    }

    [Fact]
    public void OpaqueRef_LuaCATS_ConstructorWithParams()
    {
        var code = BuildOpaqueRefLuaCATS();
        // Vec3 constructor with params
        Assert.Contains("---@field Vec3 fun(x: number, y: number, z: number): jolt.Vec3", code);
    }

    // ─── Helpers ───

    private static string BuildValueTypeCode()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Vec3", ValueType]
            interface Vec3 {
                [Constructor]
                void create(float x, float y, float z);
                float GetX();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        Assert.True(spec.OpaqueTypes[0].IsValueType);
        return CBindingGen.Generate(spec);
    }

    private static string BuildOpaqueRefParamCode()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Vec3", ValueType]
            interface Vec3 {
                [Constructor]
                void create(float x, float y, float z);
            };
            [CppClass="JPH::World", Constructor]
            interface World {
                void SetGravity(Vec3 gravity);
                Vec3 GetGravity();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        return CBindingGen.Generate(spec);
    }

    private static string BuildOpaqueRefPtrCode()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Shape", NoDelete]
            interface Shape {
                boolean IsValid();
            };
            [CppClass="JPH::Body", Constructor]
            interface Body {
                void SetShape(Shape shape);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        return CBindingGen.Generate(spec);
    }

    private static string BuildOpaqueRefLuaCATS()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="jolt_", IsCpp]
            [CppClass="JPH::Vec3", ValueType]
            interface Vec3 {
                [Constructor]
                void create(float x, float y, float z);
                float GetX();
            };
            [CppClass="JPH::World", Constructor]
            interface World {
                void SetGravity(Vec3 gravity);
                Vec3 GetGravity();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "jolt");
        return LuaCatsGen.Generate(spec);
    }
}
