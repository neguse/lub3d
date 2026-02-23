namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// sokol.imgui モジュールの生成定義 (sokol_imgui.h / simgui_*)
/// </summary>
public class Imgui : SokolModule
{
    public override string ModuleName => "sokol.imgui";
    public override string Prefix => "simgui_";

    protected override IReadOnlySet<string> Ignores => new HashSet<string>
    {
        "simgui_allocator_t", "simgui_logger_t",
    };

    private static readonly List<SkipEntry> SkippedStructs = [
        new("simgui_allocator_t", "internal allocator config: managed by framework"),
        new("simgui_logger_t", "internal logger config: managed by framework"),
    ];

    public override SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, [], SkippedStructs, []);
}
