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
    public static string Footer(string moduleName) => $"return {moduleName}\n";

    /// <summary>
    /// 構造体の LuaCATS クラス定義
    /// </summary>
    public static string StructClass(string className, IEnumerable<(string name, Type type)> fields)
    {
        var fieldLines = string.Join("\n", fields.Select(f =>
            $"---@field {f.name}? {TypeToString(f.type)}"));
        return $"""
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
        local {{moduleName}} = {}

        """;

    /// <summary>
    /// 関数の LuaCATS フィールド定義
    /// </summary>
    public static string FuncField(string name, IEnumerable<(string name, Type type)> parameters, Type? ret)
    {
        var args = string.Join(", ", parameters.Select(p => $"{p.name}: {TypeToString(p.type)}"));
        return ret == null
            ? $"---@field {name} fun({args})"
            : $"---@field {name} fun({args}): {TypeToString(ret)}";
    }

    /// <summary>
    /// Enum の LuaCATS 定義
    /// </summary>
    public static string EnumDef(string enumName, IEnumerable<(string name, int value)> items)
    {
        var itemLines = string.Join("\n", items.Select(item => $"    {item.name} = {item.value},"));
        return $$"""
            ---@enum {{enumName}}
            {{enumName}} = {
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
