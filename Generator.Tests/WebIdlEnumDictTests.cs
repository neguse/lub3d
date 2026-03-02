using Generator;
using Generator.CBinding;
using Generator.LuaCats;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlEnumDictTests
{
    // ─── Parser: enum ───

    [Fact]
    public void Parse_SimpleEnum()
    {
        var file = WebIdlParser.Parse("""
            enum test_color {
                "RED" = 0,
                "GREEN" = 1,
                "BLUE" = 2,
            };
            """);
        Assert.Single(file.Enums);
        var e = file.Enums[0];
        Assert.Equal("test_color", e.CName);
        Assert.Equal(3, e.Values.Count);
        Assert.Equal("RED", e.Values[0].Name);
        Assert.Equal(0, e.Values[0].Value);
        Assert.Equal("BLUE", e.Values[2].Name);
        Assert.Equal(2, e.Values[2].Value);
    }

    [Fact]
    public void Parse_EnumNoTrailingComma()
    {
        var file = WebIdlParser.Parse("""
            enum test_mode {
                "A" = 0,
                "B" = 1
            };
            """);
        Assert.Equal(2, file.Enums[0].Values.Count);
    }

    [Fact]
    public void Parse_EnumNegativeValues()
    {
        var file = WebIdlParser.Parse("""
            enum test_sign {
                "NEG" = -1,
                "ZERO" = 0,
                "POS" = 1,
            };
            """);
        Assert.Equal(-1, file.Enums[0].Values[0].Value);
        Assert.Equal(0, file.Enums[0].Values[1].Value);
        Assert.Equal(1, file.Enums[0].Values[2].Value);
    }

    // ─── Parser: dictionary ───

    [Fact]
    public void Parse_SimpleDictionary()
    {
        var file = WebIdlParser.Parse("""
            dictionary test_color {
                float r;
                float g;
                float b;
                float a;
            };
            """);
        Assert.Single(file.Dictionaries);
        var d = file.Dictionaries[0];
        Assert.Equal("test_color", d.CName);
        Assert.Equal(4, d.Fields.Count);
        Assert.Equal("r", d.Fields[0].Name);
        Assert.Equal("float", d.Fields[0].Type.Name);
    }

    [Fact]
    public void Parse_DictionaryMixedTypes()
    {
        var file = WebIdlParser.Parse("""
            dictionary test_desc {
                long width;
                long height;
                DOMString title;
                boolean fullscreen;
            };
            """);
        var d = file.Dictionaries[0];
        Assert.Equal("long", d.Fields[0].Type.Name);
        Assert.Equal("DOMString", d.Fields[2].Type.Name);
        Assert.Equal("boolean", d.Fields[3].Type.Name);
    }

    // ─── Parser: mixed file ───

    [Fact]
    public void Parse_MixedFile()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_", CInclude="test.h"]
            enum test_mode {
                "A" = 0,
                "B" = 1,
            };
            dictionary test_color {
                float r;
                float g;
                float b;
            };
            namespace test {
                void setup();
                test_color get_color();
            };
            """);
        Assert.Equal("test_", file.ExtAttrs["Prefix"]);
        Assert.Single(file.Enums);
        Assert.Single(file.Dictionaries);
        Assert.NotNull(file.Namespace);
        Assert.Equal(2, file.Namespace!.Operations.Count);
    }

    [Fact]
    public void Parse_TypeReference()
    {
        var file = WebIdlParser.Parse("""
            namespace test {
                sg_color get_color();
                void set_mode(test_mode mode);
            };
            """);
        Assert.Equal("sg_color", file.Namespace!.Operations[0].ReturnType.Name);
        Assert.Equal("test_mode", file.Namespace!.Operations[1].Params[0].Type.Name);
    }

    // ─── Converter: enum ───

    [Fact]
    public void Convert_EnumBinding()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            enum sg_pixel_format {
                "SG_PIXELFORMAT_DEFAULT" = 0,
                "SG_PIXELFORMAT_NONE" = 1,
                "SG_PIXELFORMAT_R8" = 2,
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        Assert.Single(spec.Enums);
        var e = spec.Enums[0];
        Assert.Equal("sg_pixel_format", e.CName);
        Assert.Equal("sokol.gfx.PixelFormat", e.LuaName);
        Assert.Equal(3, e.Items.Count);
    }

    [Fact]
    public void Convert_EnumValues()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            enum sg_pixel_format {
                "SG_PIXELFORMAT_DEFAULT" = 0,
                "SG_PIXELFORMAT_R8" = 2,
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        Assert.Equal(0, spec.Enums[0].Items[0].Value);
        Assert.Equal(2, spec.Enums[0].Items[1].Value);
        Assert.Equal("SG_PIXELFORMAT_DEFAULT", spec.Enums[0].Items[0].CConstName);
    }

    // ─── Converter: dictionary ───

    [Fact]
    public void Convert_DictionaryToStruct()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            dictionary sg_color {
                float r;
                float g;
                float b;
                float a;
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        Assert.Single(spec.Structs);
        var s = spec.Structs[0];
        Assert.Equal("sg_color", s.CName);
        Assert.Equal("Color", s.PascalName);
        Assert.Equal("sokol.gfx.Color", s.Metatable);
        Assert.Equal(4, s.Fields.Count);
        Assert.Equal("r", s.Fields[0].CName);
        Assert.IsType<BindingType.Float>(s.Fields[0].Type);
    }

    // ─── Converter: type references ───

    [Fact]
    public void Convert_EnumTypeReference()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            enum test_mode {
                "TEST_MODE_A" = 0,
                "TEST_MODE_B" = 1,
            };
            namespace test {
                void set_mode(test_mode mode);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        var param = spec.Funcs[0].Params[0];
        Assert.IsType<BindingType.Enum>(param.Type);
        var enumType = (BindingType.Enum)param.Type;
        Assert.Equal("test_mode", enumType.CName);
    }

    [Fact]
    public void Convert_DictTypeReference()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            dictionary test_color {
                float r;
                float g;
                float b;
            };
            namespace test {
                test_color get_color();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        var retType = spec.Funcs[0].ReturnType;
        Assert.IsType<BindingType.Struct>(retType);
        var structType = (BindingType.Struct)retType;
        Assert.Equal("test_color", structType.CName);
    }

    [Fact]
    public void Convert_CrossModuleStructRef()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sglue_", CInclude="sokol_glue.h"]
            namespace sglue {
                sg_environment environment();
                sg_swapchain swapchain();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.glue");
        var envRet = spec.Funcs[0].ReturnType;
        Assert.IsType<BindingType.Struct>(envRet);
        var envStruct = (BindingType.Struct)envRet;
        Assert.Equal("sg_environment", envStruct.CName);
        Assert.Equal("sokol.gfx.Environment", envStruct.Metatable);
    }

    // ─── E2E: enum + dictionary C generation ───

    [Fact]
    public void E2E_CBinding_EnumTable()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_", CInclude="sokol_gfx.h"]
            enum sg_pixel_format {
                "SG_PIXELFORMAT_DEFAULT" = 0,
                "SG_PIXELFORMAT_R8" = 2,
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        var code = CBindingGen.Generate(spec);
        Assert.Contains("SG_PIXELFORMAT_DEFAULT", code);
        Assert.Contains("SG_PIXELFORMAT_R8", code);
    }

    [Fact]
    public void E2E_CBinding_StructMetatable()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_", CInclude="sokol_gfx.h"]
            dictionary sg_color {
                float r;
                float g;
                float b;
                float a;
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        var code = CBindingGen.Generate(spec);
        Assert.Contains("sokol.gfx.Color", code);
        Assert.Contains("sg_color", code);
    }

    [Fact]
    public void E2E_LuaCats_EnumClass()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_", CInclude="sokol_gfx.h"]
            enum sg_pixel_format {
                "SG_PIXELFORMAT_DEFAULT" = 0,
                "SG_PIXELFORMAT_R8" = 2,
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        var lua = LuaCatsGen.Generate(spec);
        Assert.Contains("---@class sokol.gfx.PixelFormat", lua);
    }

    [Fact]
    public void E2E_LuaCats_StructClass()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_", CInclude="sokol_gfx.h"]
            dictionary sg_color {
                float r;
                float g;
                float b;
                float a;
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gfx");
        var lua = LuaCatsGen.Generate(spec);
        Assert.Contains("---@class sokol.gfx.Color", lua);
        Assert.Contains("---@field r? number", lua);
    }

    // ─── ExtraCCode parameter ───

    [Fact]
    public void Convert_ExtraCCode()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            namespace test {
                void setup();
            };
            """);
        var extra = "/* custom C code */\n";
        var spec = WebIdlToSpec.Convert(file, "mymod", extraCCode: extra);
        Assert.Equal(extra, spec.ExtraCCode);
    }

    // ─── Phase 2: operation ExtAttrs ───

    [Fact]
    public void Parse_OperationExtAttrs()
    {
        var file = WebIdlParser.Parse("""
            namespace test {
                [Ignore]
                void internal_func();
                void public_func();
            };
            """);
        var ops = file.Namespace!.Operations;
        Assert.Equal(2, ops.Count);
        Assert.NotNull(ops[0].ExtAttrs);
        Assert.True(ops[0].ExtAttrs!.ContainsKey("Ignore"));
        Assert.Null(ops[1].ExtAttrs);
    }

    [Fact]
    public void Convert_IgnoreOperation()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            namespace test {
                [Ignore]
                void skipped();
                void kept();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        Assert.Single(spec.Funcs);
        Assert.Equal("kept", spec.Funcs[0].LuaName);
    }

    // ─── Phase 2: dictionary ExtAttrs ───

    [Fact]
    public void Parse_DictionaryExtAttrs()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            [HasMetamethods]
            dictionary sg_event {
                long type;
            };
            """);
        Assert.NotNull(file.Dictionaries[0].ExtAttrs);
        Assert.True(file.Dictionaries[0].ExtAttrs!.ContainsKey("HasMetamethods"));
    }

    [Fact]
    public void Convert_HasMetamethods()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            [HasMetamethods]
            dictionary sg_event {
                long type;
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        Assert.True(spec.Structs[0].HasMetamethods);
    }

    [Fact]
    public void Convert_AllowStringInit()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sg_"]
            [AllowStringInit]
            dictionary sg_range {
                ConstVoidPtr ptr;
                Size size;
            };
            namespace sg {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        Assert.True(spec.Structs[0].AllowStringInit);
    }

    // ─── Phase 2: FixedArray ───

    [Fact]
    public void Parse_FixedArrayField()
    {
        var file = WebIdlParser.Parse("""
            dictionary test_desc {
                float[8] data;
            };
            """);
        var field = file.Dictionaries[0].Fields[0];
        Assert.Equal("float", field.Type.Name);
        Assert.Equal(8, field.Type.ArrayLength);
    }

    [Fact]
    public void Convert_FixedArrayField()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            dictionary test_desc {
                float[16] values;
            };
            namespace test {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        var field = spec.Structs[0].Fields[0];
        Assert.IsType<BindingType.FixedArray>(field.Type);
        var arr = (BindingType.FixedArray)field.Type;
        Assert.IsType<BindingType.Float>(arr.Inner);
        Assert.Equal(16, arr.Length);
    }

    // ─── Phase 2: Callback type ───

    [Fact]
    public void Parse_CallbackField()
    {
        var file = WebIdlParser.Parse("""
            dictionary test_desc {
                Callback stream_cb;
                VoidPtr user_data;
            };
            """);
        Assert.Equal("Callback", file.Dictionaries[0].Fields[0].Type.Name);
    }

    [Fact]
    public void Convert_CallbackField()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            dictionary test_desc {
                Callback on_data;
            };
            namespace test {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        var field = spec.Structs[0].Fields[0];
        Assert.IsType<BindingType.Callback>(field.Type);
    }

    // ─── Phase 2: ExtraLuaReg ───

    [Fact]
    public void Convert_ExtraLuaReg()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_", ExtraLuaReg="push:l_test_push,info:l_test_info"]
            namespace test {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        Assert.Equal(2, spec.ExtraLuaRegs.Count);
        Assert.Equal("push", spec.ExtraLuaRegs[0].LuaName);
        Assert.Equal("l_test_push", spec.ExtraLuaRegs[0].CFunc);
        Assert.Equal("info", spec.ExtraLuaRegs[1].LuaName);
        Assert.Equal("l_test_info", spec.ExtraLuaRegs[1].CFunc);
    }

    // ─── Phase 2: Flag ExtAttrs (no value) ───

    [Fact]
    public void Parse_FlagExtAttr()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_", CInclude="test.h"]
            [Ignore]
            dictionary test_internal {
                long x;
            };
            """);
        var dict = file.Dictionaries[0];
        Assert.NotNull(dict.ExtAttrs);
        Assert.True(dict.ExtAttrs!.ContainsKey("Ignore"));
        Assert.Equal("", dict.ExtAttrs["Ignore"]);
    }

    // ─── Phase 2: Cross-module enum reference ───

    [Fact]
    public void Convert_CrossModuleEnumRef()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="sgl_"]
            dictionary sgl_desc {
                sg_pixel_format color_format;
            };
            namespace sgl {
                void setup(sgl_desc desc);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "sokol.gl");
        var field = spec.Structs[0].Fields[0];
        Assert.IsType<BindingType.Enum>(field.Type);
        var enumType = (BindingType.Enum)field.Type;
        Assert.Equal("sg_pixel_format", enumType.CName);
        Assert.Equal("sokol.gfx.PixelFormat", enumType.LuaName);
    }

    // ─── Phase 2: MapFieldName ───

    [Fact]
    public void Convert_MapFieldName()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            [MapFieldName="init_cb:init,frame_cb:frame"]
            dictionary test_desc {
                Callback init_cb;
                Callback frame_cb;
                long width;
            };
            namespace test {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        Assert.Equal("init", spec.Structs[0].Fields[0].LuaName);
        Assert.Equal("frame", spec.Structs[0].Fields[1].LuaName);
        Assert.Equal("width", spec.Structs[0].Fields[2].LuaName);
    }

    // ─── Phase 2: ConstVoidPtr ───

    [Fact]
    public void Convert_ConstVoidPtr()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            dictionary test_range {
                ConstVoidPtr ptr;
                Size size;
            };
            namespace test {
                void setup();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "mymod");
        var ptrField = spec.Structs[0].Fields[0];
        Assert.IsType<BindingType.ConstPtr>(ptrField.Type);
        var sizeField = spec.Structs[0].Fields[1];
        Assert.IsType<BindingType.Size>(sizeField.Type);
    }

    // ─── Phase 2: Enum ExtAttrs ───

    [Fact]
    public void Parse_EnumExtAttrs()
    {
        var file = WebIdlParser.Parse("""
            [Prefix="test_"]
            [Ignore]
            enum test_internal {
                "A" = 0,
            };
            enum test_public {
                "B" = 0,
            };
            """);
        Assert.NotNull(file.Enums[0].ExtAttrs);
        Assert.True(file.Enums[0].ExtAttrs!.ContainsKey("Ignore"));
        Assert.Null(file.Enums[1].ExtAttrs);
    }
}
