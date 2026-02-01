using Generator;
using Generator.ClangAst;
using LuaCatsType = Generator.LuaCats.Type;
using CBindingType = Generator.CBinding.Type;

namespace Generator.Tests;

public class PipelineTests
{
    private const string TestJson = """
    {
      "module": "app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        {
          "kind": "struct",
          "name": "sapp_desc",
          "fields": [
            { "name": "width", "type": "int" },
            { "name": "init_cb", "type": "void (*)(void)" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_run",
          "type": "void (const sapp_desc *)",
          "params": [
            { "name": "desc", "type": "const sapp_desc *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_width",
          "type": "int (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "enum",
          "name": "sapp_event_type",
          "items": [
            { "name": "SAPP_EVENTTYPE_INVALID" },
            { "name": "SAPP_EVENTTYPE_KEY_DOWN", "value": "5" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    // ===== String Helpers =====

    [Theory]
    [InlineData("sapp_desc", "Desc")]
    [InlineData("sapp_event_type", "EventType")]
    [InlineData("width", "Width")]
    [InlineData("", "")]
    public void ToPascalCase_ConvertsCorrectly(string input, string expected)
    {
        var result = Pipeline.ToPascalCase(Pipeline.StripPrefix(input, "sapp_"));
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("sapp_desc", "sapp_", "desc")]
    [InlineData("sapp_event_type", "sapp_", "event_type")]
    [InlineData("other", "sapp_", "other")]
    public void StripPrefix_StripsCorrectly(string input, string prefix, string expected)
    {
        Assert.Equal(expected, Pipeline.StripPrefix(input, prefix));
    }

    // ===== LuaCATS Type Conversion =====

    [Fact]
    public void ToLuaCatsType_Int_ReturnsInteger()
    {
        var typ = new Types.Int();
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Primitive("integer"), result);
    }

    [Fact]
    public void ToLuaCatsType_Float_ReturnsNumber()
    {
        var typ = new Types.Float();
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Primitive("number"), result);
    }

    [Fact]
    public void ToLuaCatsType_Bool_ReturnsBoolean()
    {
        var typ = new Types.Bool();
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Primitive("boolean"), result);
    }

    [Fact]
    public void ToLuaCatsType_String_ReturnsString()
    {
        var typ = new Types.String();
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Primitive("string"), result);
    }

    [Fact]
    public void ToLuaCatsType_VoidPtr_ReturnsLightuserdata()
    {
        var typ = new Types.Ptr(new Types.Void());
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Primitive("lightuserdata?"), result);
    }

    [Fact]
    public void ToLuaCatsType_Struct_ReturnsClass()
    {
        var typ = new Types.StructRef("sapp_desc");
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.Equal(new LuaCatsType.Class("app.Desc"), result);
    }

    [Fact]
    public void ToLuaCatsType_FuncPtr_ReturnsFun()
    {
        var typ = new Types.FuncPtr([], new Types.Void());
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.IsType<LuaCatsType.Fun>(result);
        var fun = (LuaCatsType.Fun)result;
        Assert.Empty(fun.Args);
        Assert.Null(fun.Ret);
    }

    [Fact]
    public void ToLuaCatsType_FuncPtrWithArgs_ReturnsFunWithArgs()
    {
        var typ = new Types.FuncPtr([new Types.Int()], new Types.Int());
        var result = Pipeline.ToLuaCatsType(typ, "app", "sapp_");
        Assert.IsType<LuaCatsType.Fun>(result);
        var fun = (LuaCatsType.Fun)result;
        Assert.Single(fun.Args);
        Assert.Equal("arg0", fun.Args[0].Name);
        Assert.Equal(new LuaCatsType.Primitive("integer"), fun.Args[0].Type);
        Assert.Equal(new LuaCatsType.Primitive("integer"), fun.Ret);
    }

    // ===== C Type Conversion =====

    [Fact]
    public void ToCType_Int_ReturnsCTypeInt()
    {
        var typ = new Types.Int();
        var result = Pipeline.ToCType(typ);
        Assert.IsType<CBindingType.Int>(result);
    }

    [Fact]
    public void ToCType_ConstPtrStruct_ReturnsConstPointer()
    {
        var typ = new Types.ConstPtr(new Types.StructRef("sapp_desc"));
        var result = Pipeline.ToCType(typ);
        Assert.IsType<CBindingType.ConstPointer>(result);
        var ptr = (CBindingType.ConstPointer)result;
        Assert.IsType<CBindingType.Struct>(ptr.Inner);
    }

    [Fact]
    public void ToCType_FuncPtr_ReturnsFuncPtr()
    {
        var typ = new Types.FuncPtr([new Types.Int()], new Types.Void());
        var result = Pipeline.ToCType(typ);
        Assert.IsType<CBindingType.FuncPtr>(result);
        var fp = (CBindingType.FuncPtr)result;
        Assert.Single(fp.Args);
        Assert.IsType<CBindingType.Void>(fp.Ret);
    }

    // ===== Field/Param Conversion =====

    [Fact]
    public void ToCFieldInits_ReturnsAllFields()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var s = reg.GetStruct("sapp_desc");
        var fields = Pipeline.ToCFieldInits(s).ToList();
        Assert.Equal(2, fields.Count);
        Assert.Equal("width", fields[0].FieldName);
        Assert.Equal("init_cb", fields[1].FieldName);
    }

    [Fact]
    public void ToCParams_ReturnsAllParams()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var f = reg.GetFunc("sapp_run");
        var params_ = Pipeline.ToCParams(f).ToList();
        Assert.Single(params_);
        Assert.Equal("desc", params_[0].Name);
    }

    // ===== Enum Items =====

    [Fact]
    public void ToEnumItems_StripsPrefix()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var e = reg.GetEnum("sapp_event_type");
        var items = Pipeline.ToEnumItems(e, "sapp_").ToList();
        Assert.Equal(2, items.Count);
        Assert.Equal("INVALID", items[0].name);
        Assert.Equal("KEY_DOWN", items[1].name);
    }

    [Fact]
    public void ToEnumItems_ParsesValues()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var e = reg.GetEnum("sapp_event_type");
        var items = Pipeline.ToEnumItems(e, "sapp_").ToList();
        Assert.Equal(0, items[0].value);
        Assert.Equal(5, items[1].value);
    }
}
