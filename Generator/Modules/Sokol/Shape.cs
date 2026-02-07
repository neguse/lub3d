namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.shape モジュールの生成定義
/// </summary>
public class Shape : SokolModule
{
    public override string ModuleName => "sokol.shape";
    public override string Prefix => "sshape_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string>
    {
        "sshape_mat4",
        "sshape_mat4_transpose",
    };
}
