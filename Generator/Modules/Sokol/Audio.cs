namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.audio モジュールの生成定義
/// </summary>
public class Audio : SokolModule
{
    public override string ModuleName => "sokol.audio";
    public override string Prefix => "saudio_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string> { "saudio_push" };
}
