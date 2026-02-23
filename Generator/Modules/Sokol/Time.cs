namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// sokol.time モジュールの生成定義
/// </summary>
public class Time : SokolModule
{
    public override string ModuleName => "sokol.time";
    public override string Prefix => "stm_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string> { "stm_laptime" };

    private static readonly List<SkipEntry> SkippedFuncs = [
        new("stm_laptime", "mutates pointer arg: not idiomatic in Lua, use stm_since instead"),
    ];

    public override SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, SkippedFuncs, [], []);
}
