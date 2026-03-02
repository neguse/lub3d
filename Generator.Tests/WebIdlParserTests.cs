using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlParserTests
{
    [Fact]
    public void Parse_VoidFunction()
    {
        var def = WebIdlParser.Parse("""
            namespace test { void setup(); };
            """);
        Assert.Single(def.Namespace!.Operations);
        var op = def.Namespace!.Operations[0];
        Assert.Equal("setup", op.Name);
        Assert.Equal("void", op.ReturnType.Name);
        Assert.Empty(op.Params);
    }

    [Fact]
    public void Parse_FunctionWithParams()
    {
        var def = WebIdlParser.Parse("""
            namespace test {
                unsigned long long diff(unsigned long long a, unsigned long long b);
            };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Equal("diff", op.Name);
        Assert.Equal("unsigned long long", op.ReturnType.Name);
        Assert.Equal(2, op.Params.Count);
        Assert.Equal("a", op.Params[0].Name);
        Assert.Equal("unsigned long long", op.Params[0].Type.Name);
        Assert.Equal("b", op.Params[1].Name);
    }

    [Fact]
    public void Parse_DoubleReturnType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { double sec(unsigned long long ticks); };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Equal("double", op.ReturnType.Name);
        Assert.Equal("unsigned long long", op.Params[0].Type.Name);
    }

    [Fact]
    public void Parse_ExtendedAttributes()
    {
        var def = WebIdlParser.Parse("""
            [Prefix="stm_", CInclude="sokol_time.h"]
            namespace stm { void setup(); };
            """);
        Assert.Equal("stm_", def.ExtAttrs["Prefix"]);
        Assert.Equal("sokol_time.h", def.ExtAttrs["CInclude"]);
        Assert.Equal("stm", def.Namespace!.Name);
    }

    [Fact]
    public void Parse_FullSokolTimeIdl()
    {
        var idl = """
            // sokol_time — timing functions
            [Prefix="stm_", CInclude="sokol_time.h"]
            namespace stm {
                void setup();
                unsigned long long now();
                unsigned long long diff(unsigned long long new_ticks, unsigned long long old_ticks);
                unsigned long long since(unsigned long long start_ticks);
                unsigned long long round_to_common_refresh_rate(unsigned long long frame_ticks);
                double sec(unsigned long long ticks);
                double ms(unsigned long long ticks);
                double us(unsigned long long ticks);
                double ns(unsigned long long ticks);
            };
            """;
        var def = WebIdlParser.Parse(idl);
        Assert.Equal(9, def.Namespace!.Operations.Count);
        Assert.Equal("setup", def.Namespace!.Operations[0].Name);
        Assert.Equal("ns", def.Namespace!.Operations[8].Name);
    }

    [Fact]
    public void Parse_CommentsIgnored()
    {
        var def = WebIdlParser.Parse("""
            // this is a comment
            namespace test {
                // another comment
                void setup();
            };
            """);
        Assert.Single(def.Namespace!.Operations);
    }

    [Fact]
    public void Parse_InvalidInput_Throws()
    {
        Assert.Throws<FormatException>(() => WebIdlParser.Parse("not valid idl"));
    }

    [Fact]
    public void Parse_LongType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { long foo(); };
            """);
        Assert.Equal("long", def.Namespace!.Operations[0].ReturnType.Name);
    }

    [Fact]
    public void Parse_LongLongType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { long long foo(); };
            """);
        Assert.Equal("long long", def.Namespace!.Operations[0].ReturnType.Name);
    }

    [Fact]
    public void Parse_UnsignedLongType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { unsigned long foo(); };
            """);
        Assert.Equal("unsigned long", def.Namespace!.Operations[0].ReturnType.Name);
    }

    [Fact]
    public void Parse_FloatType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { float foo(); };
            """);
        Assert.Equal("float", def.Namespace!.Operations[0].ReturnType.Name);
    }

    [Fact]
    public void Parse_BooleanType()
    {
        var def = WebIdlParser.Parse("""
            namespace test { boolean foo(); };
            """);
        Assert.Equal("boolean", def.Namespace!.Operations[0].ReturnType.Name);
    }
}
