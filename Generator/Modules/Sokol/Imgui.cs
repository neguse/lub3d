namespace Generator.Modules.Sokol;

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
}
