using Generator.WebIdl;

namespace Generator.Tests;

public class EmscriptenIdlReaderTests
{
    [Fact]
    public void Parse_SimpleInterface()
    {
        var source = """
            interface Foo {
                void Foo();
                void Bar(long x);
                float GetValue();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Single(file.Interfaces);
        var iface = file.Interfaces[0];
        Assert.Equal("Foo", iface.Name);
        Assert.Equal(3, iface.Members.Count);
        Assert.Equal(EmMemberKind.Constructor, iface.Members[0].Kind);
        Assert.Equal(EmMemberKind.Method, iface.Members[1].Kind);
        Assert.Equal("Bar", iface.Members[1].Name);
        Assert.Equal("void", iface.Members[1].ReturnType);
        Assert.Single(iface.Members[1].Params);
        Assert.Equal("x", iface.Members[1].Params[0].Name);
        Assert.Equal("long", iface.Members[1].Params[0].Type);
    }

    [Fact]
    public void Parse_Enum()
    {
        var source = """
            enum EBodyType {
                "EBodyType_RigidBody",
                "EBodyType_SoftBody"
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Single(file.Enums);
        Assert.Equal("EBodyType", file.Enums[0].Name);
        Assert.Equal(2, file.Enums[0].Values.Count);
        Assert.Equal("EBodyType_RigidBody", file.Enums[0].Values[0]);
        Assert.Equal("EBodyType_SoftBody", file.Enums[0].Values[1]);
    }

    [Fact]
    public void Parse_Implements()
    {
        var source = """
            interface Shape {
                boolean IsValid();
            };
            interface ConvexShape {
                float GetRadius();
            };
            ConvexShape implements Shape;
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Equal(2, file.Interfaces.Count);
        Assert.Single(file.Implements);
        Assert.Equal("ConvexShape", file.Implements[0].Child);
        Assert.Equal("Shape", file.Implements[0].Parent);
    }

    [Fact]
    public void Parse_ExtAttrs_NoDelete()
    {
        var source = """
            [NoDelete]
            interface Body {
                boolean IsActive();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Single(file.Interfaces);
        Assert.True(file.Interfaces[0].ExtAttrs.ContainsKey("NoDelete"));
    }

    [Fact]
    public void Parse_ExtAttrs_JSImplementation()
    {
        var source = """
            [JSImplementation="ContactListenerEm"]
            interface ContactListenerJS {
                void ContactListenerJS();
                void OnContactAdded(long id);
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Single(file.Interfaces);
        Assert.Equal("ContactListenerEm", file.Interfaces[0].ExtAttrs["JSImplementation"]);
    }

    [Fact]
    public void Parse_StaticMethod()
    {
        var source = """
            interface Vec3 {
                void Vec3();
                [Value] static Vec3 sZero();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        var sZero = file.Interfaces[0].Members[1];
        Assert.True(sZero.IsStatic);
        Assert.Equal("sZero", sZero.Name);
        Assert.Equal("Vec3", sZero.ReturnType);
        Assert.Contains("Value", sZero.ReturnAttrs!);
    }

    [Fact]
    public void Parse_ParamAttrs()
    {
        var source = """
            interface Foo {
                void Bar([Const, Ref] Vec3 inValue);
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        var param = file.Interfaces[0].Members[0].Params[0];
        Assert.Equal("inValue", param.Name);
        Assert.Equal("Vec3", param.Type);
        Assert.Contains("Const", param.Attrs!);
        Assert.Contains("Ref", param.Attrs!);
    }

    [Fact]
    public void Parse_OptionalParam()
    {
        var source = """
            interface Foo {
                void Bar(float x, optional float tolerance);
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.False(file.Interfaces[0].Members[0].Params[0].IsOptional);
        Assert.True(file.Interfaces[0].Members[0].Params[1].IsOptional);
    }

    [Fact]
    public void Parse_Attribute()
    {
        var source = """
            interface Settings {
                attribute float mRadius;
                [Value] attribute Vec3 mPosition;
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Equal(2, file.Interfaces[0].Members.Count);
        Assert.Equal(EmMemberKind.Attribute, file.Interfaces[0].Members[0].Kind);
        Assert.Equal("mRadius", file.Interfaces[0].Members[0].Name);
        Assert.Equal("float", file.Interfaces[0].Members[0].ReturnType);
        Assert.Equal(EmMemberKind.Attribute, file.Interfaces[0].Members[1].Kind);
        Assert.Equal("mPosition", file.Interfaces[0].Members[1].Name);
    }

    [Fact]
    public void Parse_OperatorAttr()
    {
        var source = """
            interface Vec3 {
                [Operator="*", Value] Vec3 MulFloat(float inV);
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        var member = file.Interfaces[0].Members[0];
        Assert.Equal("MulFloat", member.Name);
        Assert.True(member.ExtAttrs!.ContainsKey("Operator"));
        Assert.Equal("*", member.ExtAttrs["Operator"]);
        Assert.Contains("Value", member.ReturnAttrs!);
    }

    [Fact]
    public void Parse_EmptyInterface()
    {
        var source = """
            interface MemRef {
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Single(file.Interfaces);
        Assert.Equal("MemRef", file.Interfaces[0].Name);
        Assert.Empty(file.Interfaces[0].Members);
    }

    [Fact]
    public void Parse_UnsignedLongType()
    {
        var source = """
            interface Foo {
                void Bar(unsigned long x);
                unsigned long GetCount();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);

        Assert.Equal("unsigned long", file.Interfaces[0].Members[0].Params[0].Type);
        Assert.Equal("unsigned long", file.Interfaces[0].Members[1].ReturnType);
    }

    [Fact]
    public void Parse_JoltJS_SmokeTest()
    {
        // Parse the actual JoltJS.idl if available
        var path = "/tmp/JoltJS.idl";
        if (!File.Exists(path)) return;  // Skip if not downloaded

        var source = File.ReadAllText(path);
        var file = EmscriptenIdlReader.Parse(source);

        // JoltJS.idl has 333 interfaces, 28 enums, ~50+ implements
        Assert.True(file.Interfaces.Count > 300, $"Expected 300+ interfaces, got {file.Interfaces.Count}");
        Assert.True(file.Enums.Count >= 28, $"Expected 28+ enums, got {file.Enums.Count}");
        Assert.True(file.Implements.Count > 40, $"Expected 40+ implements, got {file.Implements.Count}");
    }

    [Fact]
    public void ToLub3dIdl_BasicConversion()
    {
        var source = """
            enum EMotion {
                "EMotion_Static",
                "EMotion_Dynamic"
            };
            interface Body {
                void Body();
                boolean IsActive();
                [Value] Vec3 GetPosition();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);
        var idl = EmscriptenIdlReader.ToLub3dIdl(file);

        Assert.Contains("enum EMotion", idl);
        Assert.Contains("\"EMotion_Static\" = 0", idl);
        Assert.Contains("\"EMotion_Dynamic\" = 1", idl);
        Assert.Contains("[Constructor]", idl);
        Assert.Contains("interface Body", idl);
        Assert.Contains("boolean IsActive()", idl);
        Assert.Contains("[Value] Vec3 GetPosition()", idl);
    }

    [Fact]
    public void ToLub3dIdl_Inheritance()
    {
        var source = """
            interface Shape {
                boolean IsValid();
            };
            interface SphereShape {
                float GetRadius();
            };
            SphereShape implements Shape;
            """;
        var file = EmscriptenIdlReader.Parse(source);
        var idl = EmscriptenIdlReader.ToLub3dIdl(file);

        Assert.Contains("interface SphereShape : Shape", idl);
    }

    [Fact]
    public void ToLub3dIdl_NoDelete()
    {
        var source = """
            [NoDelete]
            interface Body {
                boolean IsActive();
            };
            """;
        var file = EmscriptenIdlReader.Parse(source);
        var idl = EmscriptenIdlReader.ToLub3dIdl(file);

        Assert.Contains("[NoDelete]", idl);
    }
}
