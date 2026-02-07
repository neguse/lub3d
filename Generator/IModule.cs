namespace Generator;

using Generator.ClangAst;

public interface IModule
{
    string ModuleName { get; }
    string Prefix { get; }

    string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule);
    string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null);
}
