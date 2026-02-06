namespace Generator.Modules.Sokol;

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
}
