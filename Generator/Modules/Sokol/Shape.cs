namespace Generator.Modules.Sokol;

using Generator.ClangAst;

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

    private static readonly List<SkipEntry> SkippedFuncs = [
        new("sshape_mat4", "returns raw float[16]: use lib/glm.lua mat4 instead"),
        new("sshape_mat4_transpose", "returns raw float[16]: use lib/glm.lua mat4 instead"),
    ];

    public override SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, SkippedFuncs, [], []);
}
