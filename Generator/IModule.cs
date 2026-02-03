namespace Generator;

using Generator.ClangAst;

public interface IModule
{
    string ModuleName { get; }
    /// ヘッダファイルパス (deps dir からの相対)
    string Header { get; }
    /// clang に渡す include ディレクトリ (deps dir からの相対)
    IReadOnlyList<string> IncludeDirs { get; }
    string Prefix { get; }
    IReadOnlyList<string> DepPrefixes { get; }

    string GenerateC(TypeRegistry reg);
    string GenerateLua(TypeRegistry reg, SourceLink? sourceLink = null);
}
