namespace Generator;

using Generator.ClangAst;
using LuaCatsTypes = Generator.LuaCats.Type;
using CBindingTypes = Generator.CBinding.Type;

/// <summary>
/// ClangAst → LuaCats/CBinding 変換のデフォルト実装
/// </summary>
public static class Pipeline
{
    // ===== 文字列ヘルパー =====

    public static string ToPascalCase(string s) =>
        string.Concat(s.Split('_').Select(p => p.Length > 0 ? char.ToUpper(p[0]) + p[1..] : ""));

    public static string StripPrefix(string name, string prefix) =>
        name.StartsWith(prefix) ? name[prefix.Length..] : name;

    public static string StripTypeSuffix(string name) =>
        name.EndsWith("_t") ? name[..^2] : name;

    // ===== LuaCATS 変換 =====

    /// <summary>
    /// ClangAst.Types → LuaCats.Type 変換
    /// </summary>
    public static LuaCatsTypes ToLuaCatsType(Types typ, string moduleName, string prefix) => typ switch
    {
        Types.Int or Types.Int64 or Types.UInt32 or Types.UInt64
            or Types.Size or Types.UIntPtr or Types.IntPtr
            => new LuaCats.Type.Primitive("integer"),
        Types.Float or Types.Double
            => new LuaCats.Type.Primitive("number"),
        Types.Bool
            => new LuaCats.Type.Primitive("boolean"),
        Types.String
            => new LuaCats.Type.Primitive("string"),
        Types.Ptr(Types.Void)
            => new LuaCats.Type.Primitive("lightuserdata?"),
        Types.Ptr(var t)
            => ToLuaCatsType(t, moduleName, prefix),
        Types.ConstPtr(var t)
            => ToLuaCatsType(t, moduleName, prefix),
        Types.FuncPtr(var args, var ret)
            => new LuaCats.Type.Fun(
                args.Select((t, i) => ($"arg{i}", ToLuaCatsType(t, moduleName, prefix))).ToList(),
                ret is Types.Void ? null : ToLuaCatsType(ret, moduleName, prefix)),
        Types.StructRef(var name)
            => new LuaCats.Type.Class($"{moduleName}.{ToPascalCase(StripPrefix(name, prefix))}"),
        Types.Void
            => new LuaCats.Type.Primitive("nil"),
        _
            => new LuaCats.Type.Primitive("any")
    };

    /// <summary>
    /// Structs → LuaCATS クラス名
    /// </summary>
    public static string ToLuaCatsClassName(Structs s, string moduleName, string prefix) =>
        $"{moduleName}.{ToPascalCase(StripPrefix(s.Name, prefix))}";

    /// <summary>
    /// Structs → LuaCATS フィールド一覧
    /// </summary>
    public static IEnumerable<(string name, LuaCatsTypes type)> ToLuaCatsFields(Structs s, string moduleName, string prefix) =>
        s.Fields.Select(f => (f.Name, ToLuaCatsType(f.ParsedType, moduleName, prefix)));

    /// <summary>
    /// Funcs → LuaCATS パラメータ一覧
    /// </summary>
    public static IEnumerable<(string name, LuaCatsTypes type)> ToLuaCatsParams(Funcs f, string moduleName, string prefix) =>
        f.Params.Select(p => (p.Name, ToLuaCatsType(p.ParsedType, moduleName, prefix)));

    /// <summary>
    /// Funcs → LuaCATS 戻り値型
    /// </summary>
    public static LuaCatsTypes? ToLuaCatsReturnType(Funcs f, string moduleName, string prefix)
    {
        var ret = CTypeParser.ParseReturnType(f.TypeStr);
        return ret is Types.Void ? null : ToLuaCatsType(ret, moduleName, prefix);
    }

    /// <summary>
    /// Funcs → LuaCATS 関数名
    /// </summary>
    public static string ToLuaCatsFuncName(Funcs f, string prefix) =>
        ToPascalCase(StripPrefix(f.Name, prefix));

    /// <summary>
    /// Enums → LuaCATS enum 名
    /// </summary>
    public static string ToLuaCatsEnumName(Enums e, string moduleName, string prefix) =>
        $"{moduleName}.{ToPascalCase(StripPrefix(e.Name, prefix))}";

    /// <summary>
    /// Enums → C バインディング用 (luaName, cConstName) 一覧
    /// C 定数名をそのまま使い、値の解決はコンパイラに任せる
    /// </summary>
    public static IEnumerable<(string luaName, string cConstName)> ToEnumItemsC(Enums e, string prefix) =>
        e.Items.Where(i => !i.Name.StartsWith("_"))
            .Select(i => (EnumItemName(i.Name, e.Name, prefix), i.Name));

    /// <summary>
    /// Enums → LuaCATS 用 (name, value) 一覧
    /// 値が取れない場合はインクリメンタルに推定
    /// </summary>
    public static IEnumerable<(string name, int value)> ToEnumItems(Enums e, string prefix)
    {
        var next = 0;
        foreach (var item in e.Items.Where(i => !i.Name.StartsWith("_")))
        {
            var val = item.Value != null && int.TryParse(item.Value, out var v) ? (next = v + 1, v).v : next++;
            yield return (EnumItemName(item.Name, e.Name, prefix), val);
        }
    }

    /// <summary>
    /// Enum アイテム名からプレフィックスを除去
    /// </summary>
    public static string EnumItemName(string itemName, string enumName, string prefix)
    {
        var enumUpper = enumName.ToUpper();
        var fullPrefix = StripPrefix(enumUpper, prefix.ToUpper().TrimEnd('_')).Replace("_", "") + "_";
        fullPrefix = prefix.ToUpper() + fullPrefix;
        if (itemName.StartsWith(fullPrefix, StringComparison.OrdinalIgnoreCase))
            return itemName[fullPrefix.Length..];
        var simple = enumUpper + "_";
        if (itemName.StartsWith(simple, StringComparison.OrdinalIgnoreCase))
            return itemName[simple.Length..];
        return itemName;
    }

    // ===== C バインダー変換 =====

    /// <summary>
    /// ClangAst.Types → CBinding.Type 変換
    /// </summary>
    public static CBindingTypes ToCType(Types typ) => typ switch
    {
        Types.Int => new CBinding.Type.Int(),
        Types.Int64 => new CBinding.Type.Int64(),
        Types.UInt32 => new CBinding.Type.UInt32(),
        Types.UInt64 => new CBinding.Type.UInt64(),
        Types.Size => new CBinding.Type.Size(),
        Types.UIntPtr => new CBinding.Type.UIntPtr(),
        Types.IntPtr => new CBinding.Type.IntPtr(),
        Types.Float => new CBinding.Type.Float(),
        Types.Double => new CBinding.Type.Double(),
        Types.Bool => new CBinding.Type.Bool(),
        Types.String => new CBinding.Type.String(),
        Types.Ptr(var t) => new CBinding.Type.Pointer(ToCType(t)),
        Types.ConstPtr(var t) => new CBinding.Type.ConstPointer(ToCType(t)),
        Types.FuncPtr(var args, var ret) => new CBinding.Type.FuncPtr(args.Select(ToCType).ToList(), ToCType(ret)),
        Types.StructRef(var name) => new CBinding.Type.Struct(name),
        Types.Void => new CBinding.Type.Void(),
        _ => throw new ArgumentException($"Unknown type: {typ}")
    };

    /// <summary>
    /// Structs → CBinding.FieldInit 一覧（デフォルト変換）
    /// </summary>
    public static IEnumerable<CBinding.FieldInit> ToCFieldInits(Structs s) =>
        s.Fields.Select(f => new CBinding.FieldInit(f.Name, f.Name, ToCType(f.ParsedType), null));

    /// <summary>
    /// Funcs → CBinding.Param 一覧（デフォルト変換）
    /// </summary>
    public static IEnumerable<CBinding.Param> ToCParams(Funcs f) =>
        f.Params.Select(p => new CBinding.Param(p.Name, ToCType(p.ParsedType), null));

    /// <summary>
    /// Funcs → 戻り値の CBinding.Type
    /// </summary>
    public static CBindingTypes ToCReturnType(Funcs f) =>
        ToCType(CTypeParser.ParseReturnType(f.TypeStr));
}
