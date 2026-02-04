namespace Generator.Modules.Sokol;

using Generator;
using Generator.ClangAst;
using Generator.CBinding;
using Generator.LuaCats;

/// <summary>
/// sokol.log モジュールの生成定義
/// </summary>
public class Log : IModule
{
    public string ModuleName => "sokol.log";
    public string Header => "sokol/sokol_log.h";
    public IReadOnlyList<string> IncludeDirs => ["sokol"];
    public string Prefix => "slog_";
    public IReadOnlyList<string> DepPrefixes => [];

    private static string ToUnderscore(string moduleName) =>
        moduleName.Replace('.', '_');

    public string GenerateC(TypeRegistry reg)
    {
        var funcArrayName = $"{ToUnderscore(ModuleName)}_funcs";
        var luaOpenName = ToUnderscore(ModuleName);

        var slogFunc = reg.GetFunc("slog_func");

        return CBindingGen.Header(["sokol_log.h"]) +
            CBindingGen.Func("slog_func", Pipeline.ToCParams(slogFunc), Pipeline.ToCReturnType(slogFunc), "") +
            CBindingGen.RegisterMetatables([]) +
            CBindingGen.LuaReg(funcArrayName,
                [("Func", "l_slog_func")]) +
            CBindingGen.LuaOpen(luaOpenName, funcArrayName);
    }

    public string GenerateLua(TypeRegistry reg, SourceLink? sourceLink = null)
    {
        var slogFunc = reg.GetFunc("slog_func");

        string? Link(Decl d) => d is { } decl && sourceLink != null
            ? (decl switch { Funcs f => f.Line, _ => null })
                is int line ? sourceLink.GetLink(line) : null
            : null;

        return LuaCatsGen.Header(ModuleName) +
            LuaCatsGen.ModuleClass(ModuleName,
                [LuaCatsGen.FuncField(
                    Pipeline.ToLuaCatsFuncName(slogFunc, Prefix),
                    Pipeline.ToLuaCatsParams(slogFunc, ModuleName, Prefix),
                    Pipeline.ToLuaCatsReturnType(slogFunc, ModuleName, Prefix),
                    Link(slogFunc))]) +
            LuaCatsGen.Footer(ModuleName);
    }
}
