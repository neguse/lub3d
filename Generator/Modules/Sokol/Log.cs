namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.log モジュールの生成定義
/// </summary>
public class Log : SokolModule
{
    public override string ModuleName => "sokol.log";
    public override string Header => "sokol/sokol_log.h";
    public override string Prefix => "slog_";
}
