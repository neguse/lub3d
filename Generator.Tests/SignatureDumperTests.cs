using Generator.ClangAst;

namespace Generator.Tests;

public class SignatureDumperTests
{
    private static TypeRegistry MakeRegistry(string prefix, string moduleName, List<Decl> decls)
    {
        var module = new Module(moduleName, prefix, [], decls);
        return TypeRegistry.FromModule(module);
    }

    [Fact]
    public void Dump_Functions_FormatsCorrectly()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx",
        [
            new Funcs("sg_setup", "void (const sg_desc *)",
                [new Param("desc", "const sg_desc *")], false, null),
            new Funcs("sg_shutdown", "void (void)", [], false, null),
        ]);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("# sg_ (sokol.gfx)", result);
        Assert.Contains("## Functions (2)", result);
        Assert.Contains("sg_setup(desc: const sg_desc *) -> void", result);
        Assert.Contains("sg_shutdown() -> void", result);
    }

    [Fact]
    public void Dump_Enums_FormatsCorrectly()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx",
        [
            new Enums("sg_pixel_format",
            [
                new EnumItem("_SG_PIXELFORMAT_DEFAULT", "0"),
                new EnumItem("SG_PIXELFORMAT_R8", "1"),
                new EnumItem("SG_PIXELFORMAT_R8SN", "2"),
            ], false, null),
        ]);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("## Enums (1)", result);
        Assert.Contains("sg_pixel_format { _SG_PIXELFORMAT_DEFAULT=0, SG_PIXELFORMAT_R8=1, SG_PIXELFORMAT_R8SN=2 }", result);
    }

    [Fact]
    public void Dump_Structs_FormatsCorrectly()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx",
        [
            new Structs("sg_desc",
            [
                new Field("buffer_pool_size", "int"),
                new Field("logger", "sg_logger"),
            ], false, null),
        ]);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("## Structs (1)", result);
        Assert.Contains("sg_desc { buffer_pool_size: int, logger: sg_logger }", result);
    }

    [Fact]
    public void Dump_ExcludesDependencyDecls()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx",
        [
            new Funcs("sg_setup", "void (void)", [], false, null),
            new Funcs("slog_func", "void (void)", [], true, "slog_"),  // dep
        ]);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("## Functions (1)", result);
        Assert.Contains("sg_setup", result);
        Assert.DoesNotContain("slog_func", result);
    }

    [Fact]
    public void Dump_EmptyRegistry_NoSections()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx", []);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("# sg_ (sokol.gfx)", result);
        Assert.DoesNotContain("## Functions", result);
        Assert.DoesNotContain("## Enums", result);
        Assert.DoesNotContain("## Structs", result);
    }

    [Fact]
    public void Dump_MultipleReturnTypes()
    {
        var reg = MakeRegistry("sg_", "sokol.gfx",
        [
            new Funcs("sg_make_buffer", "sg_buffer (const sg_buffer_desc *)",
                [new Param("desc", "const sg_buffer_desc *")], false, null),
            new Funcs("sg_query_features", "sg_features (void)", [], false, null),
        ]);

        var result = SignatureDumper.Dump(reg);

        Assert.Contains("sg_make_buffer(desc: const sg_buffer_desc *) -> sg_buffer", result);
        Assert.Contains("sg_query_features() -> sg_features", result);
    }
}
