using Generator.ClangAst;

namespace Generator.Tests;

public class CTypeParserTests
{
    [Theory]
    [InlineData("int", typeof(Types.Int))]
    [InlineData("int32_t", typeof(Types.Int))]
    [InlineData("int64_t", typeof(Types.Int64))]
    [InlineData("uint32_t", typeof(Types.UInt32))]
    [InlineData("uint8_t", typeof(Types.UInt32))]
    [InlineData("uint16_t", typeof(Types.UInt32))]
    [InlineData("int8_t", typeof(Types.Int))]
    [InlineData("int16_t", typeof(Types.Int))]
    [InlineData("uint64_t", typeof(Types.UInt64))]
    [InlineData("size_t", typeof(Types.Size))]
    [InlineData("uintptr_t", typeof(Types.UIntPtr))]
    [InlineData("intptr_t", typeof(Types.IntPtr))]
    [InlineData("float", typeof(Types.Float))]
    [InlineData("double", typeof(Types.Double))]
    [InlineData("bool", typeof(Types.Bool))]
    [InlineData("char", typeof(Types.String))]
    [InlineData("void", typeof(Types.Void))]
    public void Parse_Primitives(string input, System.Type expected)
    {
        var result = CTypeParser.Parse(input);
        Assert.IsType(expected, result);
    }

    [Fact]
    public void Parse_Pointer()
    {
        var result = CTypeParser.Parse("int *");
        Assert.IsType<Types.Ptr>(result);
        Assert.IsType<Types.Int>(((Types.Ptr)result).Inner);
    }

    [Fact]
    public void Parse_VoidPointer()
    {
        var result = CTypeParser.Parse("void *");
        Assert.IsType<Types.Ptr>(result);
        Assert.IsType<Types.Void>(((Types.Ptr)result).Inner);
    }

    [Fact]
    public void Parse_ConstPointer()
    {
        var result = CTypeParser.Parse("const int *");
        Assert.IsType<Types.ConstPtr>(result);
        Assert.IsType<Types.Int>(((Types.ConstPtr)result).Inner);
    }

    [Fact]
    public void Parse_ConstCharPointer()
    {
        var result = CTypeParser.Parse("const char *");
        Assert.IsType<Types.ConstPtr>(result);
        Assert.IsType<Types.String>(((Types.ConstPtr)result).Inner);
    }

    [Fact]
    public void Parse_ConstVoidPointer_BecomesVoidPtr()
    {
        var result = CTypeParser.Parse("const void *");
        Assert.IsType<Types.Ptr>(result);
        Assert.IsType<Types.Void>(((Types.Ptr)result).Inner);
    }

    [Fact]
    public void Parse_Struct()
    {
        var result = CTypeParser.Parse("sapp_desc");
        Assert.IsType<Types.StructRef>(result);
        Assert.Equal("sapp_desc", ((Types.StructRef)result).Name);
    }

    [Fact]
    public void Parse_ConstStructPointer()
    {
        var result = CTypeParser.Parse("const sapp_desc *");
        Assert.IsType<Types.ConstPtr>(result);
        var inner = ((Types.ConstPtr)result).Inner;
        Assert.IsType<Types.StructRef>(inner);
        Assert.Equal("sapp_desc", ((Types.StructRef)inner).Name);
    }

    [Fact]
    public void Parse_Array()
    {
        var result = CTypeParser.Parse("int[16]");
        var arr = Assert.IsType<Types.Array>(result);
        Assert.IsType<Types.Int>(arr.Inner);
        Assert.Equal(16, arr.Length);
    }

    [Fact]
    public void Parse_VoidFuncPtr()
    {
        var result = CTypeParser.Parse("void (*)(void)");
        Assert.IsType<Types.FuncPtr>(result);
        var fp = (Types.FuncPtr)result;
        Assert.Empty(fp.Args);
        Assert.IsType<Types.Void>(fp.Ret);
    }

    [Fact]
    public void Parse_FuncPtrWithArgs()
    {
        var result = CTypeParser.Parse("void (*)(int, float)");
        Assert.IsType<Types.FuncPtr>(result);
        var fp = (Types.FuncPtr)result;
        Assert.Equal(2, fp.Args.Count);
        Assert.IsType<Types.Int>(fp.Args[0]);
        Assert.IsType<Types.Float>(fp.Args[1]);
        Assert.IsType<Types.Void>(fp.Ret);
    }

    [Fact]
    public void Parse_FuncPtrWithReturn()
    {
        var result = CTypeParser.Parse("int (*)(void)");
        Assert.IsType<Types.FuncPtr>(result);
        var fp = (Types.FuncPtr)result;
        Assert.Empty(fp.Args);
        Assert.IsType<Types.Int>(fp.Ret);
    }

    [Fact]
    public void Parse_FuncPtrWithStructArg()
    {
        var result = CTypeParser.Parse("void (*)(const sapp_event *)");
        Assert.IsType<Types.FuncPtr>(result);
        var fp = (Types.FuncPtr)result;
        Assert.Single(fp.Args);
        Assert.IsType<Types.ConstPtr>(fp.Args[0]);
    }

    [Fact]
    public void ParseReturnType_Void()
    {
        var result = CTypeParser.ParseReturnType("void (const sapp_desc *)");
        Assert.IsType<Types.Void>(result);
    }

    [Fact]
    public void ParseReturnType_Int()
    {
        var result = CTypeParser.ParseReturnType("int (void)");
        Assert.IsType<Types.Int>(result);
    }
}
