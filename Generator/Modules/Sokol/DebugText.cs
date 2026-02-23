namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// sokol.debugtext モジュールの生成定義
/// </summary>
public class DebugText : SokolModule
{
    public override string ModuleName => "sokol.debugtext";
    public override string Prefix => "sdtx_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string>
    {
        "sdtx_printf",
        "sdtx_vprintf",
        "sdtx_putc",
    };

    private static readonly List<SkipEntry> SkippedFuncs = [
        new("sdtx_printf", "varargs: Lua has string.format + sdtx_puts"),
        new("sdtx_vprintf", "varargs: Lua has string.format + sdtx_puts"),
        new("sdtx_putc", "single char: use sdtx_puts instead"),
    ];

    public override SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, SkippedFuncs, [], []);
}
