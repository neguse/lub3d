namespace Generator.Modules.Sokol;

using Generator.ClangAst;

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

    private static readonly List<SkipEntry> SkippedFuncs = [
        new("sgl_load_matrix", "raw float[16] pointer: use lib/glm.lua mat4 instead"),
        new("sgl_load_transpose_matrix", "raw float[16] pointer: use lib/glm.lua mat4 instead"),
        new("sgl_mult_matrix", "raw float[16] pointer: use lib/glm.lua mat4 instead"),
        new("sgl_mult_transpose_matrix", "raw float[16] pointer: use lib/glm.lua mat4 instead"),
    ];

    public override SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, SkippedFuncs, [], []);
}
