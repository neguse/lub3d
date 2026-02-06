namespace Generator;

/// <summary>
/// 中間データモデル — BuildSpec で全決定が完了し、ジェネレータは文字列生成のみ行う
/// </summary>
public record ModuleSpec(
    string ModuleName,
    string Prefix,
    List<string> CIncludes,
    string? ExtraCCode,
    List<StructBinding> Structs,
    List<FuncBinding> Funcs,
    List<EnumBinding> Enums,
    List<(string LuaName, string CFunc)> ExtraLuaRegs
);

public record StructBinding(
    string CName,
    string PascalName,
    string Metatable,
    bool HasMetamethods,
    List<FieldBinding> Fields,
    string? SourceLink
);

public record FieldBinding(
    string CName,
    string LuaName,
    BindingType Type
);

public record FuncBinding(
    string CName,
    string LuaName,
    List<ParamBinding> Params,
    BindingType ReturnType,
    string? SourceLink
);

public record ParamBinding(
    string Name,
    BindingType Type
);

public record EnumBinding(
    string CName,
    string LuaName,
    string FieldName,
    List<EnumItemBinding> Items,
    string? SourceLink
);

public record EnumItemBinding(
    string LuaName,
    string CConstName,
    int? Value
);
