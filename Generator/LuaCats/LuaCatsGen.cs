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
    public static string StructCtor(string name, string moduleName, bool allowStringInit = false) =>
        allowStringInit
            ? $"---@field {name} fun(t?: {moduleName}.{name}|string): {moduleName}.{name}"
            : $"---@field {name} fun(t?: {moduleName}.{name}): {moduleName}.{name}";

    /// <summary>
    /// モジュール名 → モジュールテーブルクラス名 (---@meta との衝突回避)
    /// </summary>
    public static string ModuleTableClassName(string moduleName) =>
        moduleName.Replace('.', '_') + "_module";

    /// <summary>
    /// モジュールクラス定義
    /// </summary>
    public static string ModuleClass(string moduleName, IEnumerable<string> fields)
    {
        var cls = ModuleTableClassName(moduleName);
        return $$"""
            ---@class {{cls}}
            {{string.Join("\n", fields)}}
            ---@type {{cls}}
            local M = {}

            """;
    }

    /// <summary>
    /// 関数の LuaCATS フィールド定義 (複数戻り値対応)
    /// </summary>
    public static string FuncField(string name, IEnumerable<(string name, Type type)> parameters, IEnumerable<Type> retTypes, string? sourceLink = null)
    {
        var args = string.Join(", ", parameters.Select(p => $"{p.name}: {TypeToString(p.type)}"));
        var retList = retTypes.ToList();
        var retStr = retList.Count > 0 ? ": " + string.Join(", ", retList.Select(TypeToString)) : "";
        var suffix = sourceLink != null ? $" [source]({sourceLink})" : "";
        return $"---@field {name} fun({args}){retStr}{suffix}";
    }

    /// <summary>
    /// 関数の LuaCATS フィールド定義 (単一戻り値 — 後方互換)
    /// </summary>
    public static string FuncField(string name, IEnumerable<(string name, Type type)> parameters, Type? ret, string? sourceLink = null)
    {
        var retTypes = ret != null ? [ret] : Array.Empty<Type>();
        return FuncField(name, parameters, retTypes, sourceLink);
    }

    /// <summary>
    /// Enum の LuaCATS 定義 (---@class + ---@field で enum テーブルを表現)
    /// </summary>
    public static string EnumDef(string enumName, string fieldName, IEnumerable<(string name, int value)> items, string? sourceLink = null)
    {
        var fieldLines = string.Join("\n", items.Select(item => $"---@field {item.name} {enumName}"));
        return SourceComment(sourceLink) + $"""
            ---@class {enumName}
            ---@operator bor({enumName}): {enumName}
            ---@operator band({enumName}): {enumName}
            ---@operator bnot: {enumName}
            {fieldLines}

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

        // Opaque type classes
        foreach (var ot in spec.OpaqueTypes)
        {
            var methodFields = ot.Methods.Select(m =>
            {
                var selfParam = new List<(string name, Type type)> { ("self", new Type.Class(ot.LuaClassName)) };
                var otherParams = m.Params.Select(p => (p.Name, ToLuaCatsType(p.Type)));
                var allParams = selfParam.Concat(otherParams);
                var ret = m.ReturnType is BindingType.Void ? null : ToLuaCatsType(m.ReturnType);
                return FuncField(m.LuaName, allParams, ret, m.SourceLink);
            });
            sb += SourceComment(ot.SourceLink) + $"---@class {ot.LuaClassName}\n";
            sb += string.Join("\n", methodFields) + "\n\n";
        }

        // Module class with struct ctors + funcs + opaque ctors
        var moduleFields = new List<string>();
        foreach (var s in spec.Structs)
            moduleFields.Add(StructCtor(s.PascalName, spec.ModuleName, s.AllowStringInit));
        foreach (var ot in spec.OpaqueTypes)
        {
            if (ot.InitFunc == null) continue;
            if (ot.ConfigType != null)
            {
                var configStruct = spec.Structs.FirstOrDefault(s => s.CName == ot.ConfigType);
                var configClass = configStruct != null
                    ? $"{spec.ModuleName}.{configStruct.PascalName}"
                    : "any";
                var initName = Pipeline.StripPrefix(ot.InitFunc, spec.Prefix);
                moduleFields.Add($"---@field {initName} fun(config?: {configClass}): {ot.LuaClassName}");
            }
            else
            {
                var initName = Pipeline.StripPrefix(ot.InitFunc, spec.Prefix);
                moduleFields.Add($"---@field {initName} fun(): {ot.LuaClassName}");
            }
        }
        foreach (var f in spec.Funcs)
        {
            var parms = f.Params
                .Select(p => (p.IsOptional || p.IsOutput ? p.Name + "?" : p.Name, ToLuaCatsType(p.Type)));
            var retTypes = new List<Type>();
            if (f.ReturnType is not BindingType.Void)
                retTypes.Add(ToLuaCatsType(f.ReturnType));
            foreach (var op in f.Params.Where(p => p.IsOutput))
                retTypes.Add(ToLuaCatsType(op.Type));
            moduleFields.Add(FuncField(f.LuaName, parms, retTypes, f.SourceLink));
        }
        foreach (var f in spec.ExtraLuaFuncs)
        {
            var parms = f.Params
                .Select(p => (p.IsOptional || p.IsOutput ? p.Name + "?" : p.Name, ToLuaCatsType(p.Type)));
            var retTypes = new List<Type>();
            if (f.ReturnType is not BindingType.Void)
                retTypes.Add(ToLuaCatsType(f.ReturnType));
            foreach (var op in f.Params.Where(p => p.IsOutput))
                retTypes.Add(ToLuaCatsType(op.Type));
            moduleFields.Add(FuncField(f.LuaName, parms, retTypes, f.SourceLink));
        }
        foreach (var aa in spec.ArrayAdapters)
        {
            var parms = aa.InputParams.Select(p => (p.Name, ToLuaCatsType(p.Type)));
            var elemType = ToLuaCatsType(aa.ElementType);
            var arrayType = new Type.Class(TypeToString(elemType) + "[]");
            moduleFields.Add(FuncField(aa.LuaName, parms, arrayType));
        }
        foreach (var e in spec.Enums)
            moduleFields.Add($"---@field {e.FieldName} {e.LuaName}");
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
        BindingType.Vec2 => new Type.Primitive("number[]"),
        BindingType.Vec4 => new Type.Primitive("number[]"),
        BindingType.FloatArray(_) => new Type.Primitive("number[]"),
        BindingType.ValueStruct(_, var luaCatsType, _, _)
            => new Type.Primitive(luaCatsType),
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
