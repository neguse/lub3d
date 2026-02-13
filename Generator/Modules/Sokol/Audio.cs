namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.audio モジュールの生成定義
/// </summary>
public class Audio : SokolModule
{
    public override string ModuleName => "sokol.audio";
    public override string Prefix => "saudio_";
    protected override IReadOnlySet<string> Ignores => new HashSet<string> { "saudio_push" };

    protected override IEnumerable<(string LuaName, string CFunc)> ExtraLuaRegs =>
        [("push", "l_saudio_push")];

    protected override string? ExtraCCode(ClangAst.TypeRegistry reg) => """
        static int l_saudio_push(lua_State *L) {
            size_t len;
            const char* data = luaL_checklstring(L, 1, &len);
            int num_frames = (int)luaL_checkinteger(L, 2);
            int result = saudio_push((const float*)data, num_frames);
            lua_pushinteger(L, result);
            return 1;
        }

        """;
}
