namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.gl モジュールの生成定義
/// </summary>
public class Gl : SokolModule
{
    public override string ModuleName => "sokol.gl";
    public override string Prefix => "sgl_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string>
    {
        "sgl_load_matrix",
        "sgl_load_transpose_matrix",
        "sgl_mult_matrix",
        "sgl_mult_transpose_matrix",
    };
}
