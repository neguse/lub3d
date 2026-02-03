namespace Generator.LuaCats;

/// <summary>
/// LuaCATS 文字列生成
/// </summary>
public static class LuaCatsGen
{
    /// <summary>
    /// LuaCATS ファイルヘッダ
    /// </summary>
    public static string Header(string moduleName) => $$"""
        ---@meta
        -- LuaCATS type definitions for {{moduleName}}
        -- Auto-generated, do not edit

        """;

    /// <summary>
    /// LuaCATS ファイルフッタ
    /// </summary>
    public static string Footer(string moduleName) => "return M\n";

    /// <summary>
    /// ソースリンクコメント行 (nullable)
    /// </summary>
    public static string SourceComment(string? link) =>
        link != null ? $"--- [source]({link})\n---@see {link}\n" : "";

    /// <summary>
    /// 構造体の LuaCATS クラス定義
    /// </summary>
    public static string StructClass(string className, IEnumerable<(string name, Type type)> fields, string? sourceLink = null)
    {
        var fieldLines = string.Join("\n", fields.Select(f =>
            $"---@field {f.name}? {TypeToString(f.type)}"));
        return SourceComment(sourceLink) + $"""
            ---@class {className}
            {fieldLines}

            """;
    }

    /// <summary>
    /// 構造体コンストラクタの LuaCATS フィールド定義
    /// </summary>
    public static string StructCtor(string name, string moduleName) =>
        $"---@field {name} fun(t?: {moduleName}.{name}): {moduleName}.{name}";

    /// <summary>
    /// モジュールクラス定義
    /// </summary>
    public static string ModuleClass(string moduleName, IEnumerable<string> fields) => $$"""
        ---@class {{moduleName}}
        {{string.Join("\n", fields)}}
        ---@type {{moduleName}}
        local M = {}

        """;

    /// <summary>
    /// 関数の LuaCATS フィールド定義 (ModuleClass 内に埋め込む用)
    /// </summary>
    public static string FuncField(string name, IEnumerable<(string name, Type type)> parameters, Type? ret)
    {
        var args = string.Join(", ", parameters.Select(p => $"{p.name}: {TypeToString(p.type)}"));
        return ret == null
            ? $"---@field {name} fun({args})"
            : $"---@field {name} fun({args}): {TypeToString(ret)}";
    }

    /// <summary>
    /// 関数の LuaCATS 定義 (function M.Xxx() end 形式、個別にコメント付与可能)
    /// </summary>
    public static string FuncDef(string name, IEnumerable<(string name, Type type)> parameters, Type? ret, string? sourceLink = null)
    {
        var paramList = parameters.ToList();
        var lines = new List<string>();
        var source = SourceComment(sourceLink);
        if (source.Length > 0)
            lines.AddRange(source.TrimEnd('\n').Split('\n'));
        foreach (var p in paramList)
            lines.Add($"---@param {p.name} {TypeToString(p.type)}");
        if (ret != null)
            lines.Add($"---@return {TypeToString(ret)}");
        var argNames = string.Join(", ", paramList.Select(p => p.name));
        lines.Add($"function M.{name}({argNames}) end");
        return string.Join("\n", lines) + "\n\n";
    }

    /// <summary>
    /// Enum の LuaCATS 定義
    /// </summary>
    public static string EnumDef(string enumName, string fieldName, IEnumerable<(string name, int value)> items, string? sourceLink = null)
    {
        var itemLines = string.Join("\n", items.Select(item => $"    {item.name} = {item.value},"));
        return SourceComment(sourceLink) + $$"""
            ---@enum {{enumName}}
            M.{{fieldName}} = {
            {{itemLines}}
            }

            """;
    }

    private static string TypeToString(Type typ) => typ switch
    {
        Type.Primitive(var name) => name,
        Type.Class(var fullName) => fullName,
        Type.Fun(var args, var ret) =>
            args.Count == 0 && ret == null ? "fun()"
            : $"fun({string.Join(", ", args.Select(a => $"{a.Name}: {TypeToString(a.Type)}"))})" +
              (ret == null ? "" : $": {TypeToString(ret)}"),
        _ => "any"
    };
}
