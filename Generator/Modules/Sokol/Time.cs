namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.time モジュールの生成定義
/// </summary>
public class Time : SokolModule
{
    public override string ModuleName => "sokol.time";
    public override string Header => "sokol/sokol_time.h";
    public override string Prefix => "stm_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string> { "stm_laptime" };
}
