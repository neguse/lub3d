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
    /// 関数の LuaCATS フィールド定義
    /// </summary>
    public static string FuncField(string name, IEnumerable<(string name, Type type)> parameters, Type? ret, string? sourceLink = null)
    {
        var args = string.Join(", ", parameters.Select(p => $"{p.name}: {TypeToString(p.type)}"));
        var suffix = sourceLink != null ? $" [source]({sourceLink})" : "";
        return ret == null
            ? $"---@field {name} fun({args}){suffix}"
            : $"---@field {name} fun({args}): {TypeToString(ret)}{suffix}";
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

    // ===== ModuleSpec ベース生成 =====

    /// <summary>
    /// ModuleSpec から LuaCATS 型スタブ全体を生成
    /// </summary>
    public static string Generate(ModuleSpec spec)
    {
        var sb = Header(spec.ModuleName);

        // Struct classes
        foreach (var s in spec.Structs)
        {
            var fields = s.Fields.Select(f =>
                (f.LuaName, ToLuaCatsType(f.Type)));
            sb += StructClass(
                $"{spec.ModuleName}.{s.PascalName}",
                fields,
                s.SourceLink);
        }

        // Module class with struct ctors + funcs
        var moduleFields = new List<string>();
        foreach (var s in spec.Structs)
            moduleFields.Add(StructCtor(s.PascalName, spec.ModuleName));
        foreach (var f in spec.Funcs)
        {
            var parms = f.Params.Select(p => (p.Name, ToLuaCatsType(p.Type)));
            var ret = f.ReturnType is BindingType.Void ? null : ToLuaCatsType(f.ReturnType);
            moduleFields.Add(FuncField(f.LuaName, parms, ret, f.SourceLink));
        }
        sb += ModuleClass(spec.ModuleName, moduleFields);

        // Enums
        foreach (var e in spec.Enums)
        {
            var items = e.Items.Select(i => (i.LuaName, value: i.Value ?? 0));
            sb += EnumDef(e.LuaName, e.FieldName, items, e.SourceLink);
        }

        sb += Footer(spec.ModuleName);
        return sb;
    }

    // ===== BindingType → LuaCats.Type 変換 =====

    internal static Type ToLuaCatsType(BindingType bt) => bt switch
    {
        BindingType.Int or BindingType.Int64 or BindingType.UInt32 or BindingType.UInt64
            or BindingType.Size or BindingType.UIntPtr or BindingType.IntPtr
            => new Type.Primitive("integer"),
        BindingType.Float or BindingType.Double
            => new Type.Primitive("number"),
        BindingType.Bool
            => new Type.Primitive("boolean"),
        BindingType.Str
            => new Type.Primitive("string"),
        BindingType.VoidPtr
            => new Type.Primitive("lightuserdata?"),
        BindingType.Void
            => new Type.Primitive("nil"),
        BindingType.Ptr(var inner)
            => ToLuaCatsType(inner),
        BindingType.ConstPtr(var inner)
            => ToLuaCatsType(inner),
        BindingType.FixedArray(var inner, _)
            => new Type.Class(TypeToString(ToLuaCatsType(inner)) + "[]"),
        BindingType.Struct(_, _, var luaClassName)
            => new Type.Class(luaClassName),
        BindingType.Enum(_, var luaName)
            => new Type.Class(luaName),
        BindingType.Callback(var parms, var ret)
            => new Type.Fun(
                parms.Select(p => (p.Name, ToLuaCatsType(p.Type))).ToList(),
                ret != null ? ToLuaCatsType(ret) : null),
        BindingType.Custom(_, var luaCatsType, _, _, _, _)
            => new Type.Primitive(luaCatsType),
        _ => new Type.Primitive("any")
    };

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
