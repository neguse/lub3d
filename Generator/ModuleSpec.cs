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
    List<(string LuaName, string CFunc)> ExtraLuaRegs,
    List<OpaqueTypeBinding> OpaqueTypes = default!,
    bool IsCpp = false,
    string? EntryPoint = null,
    List<FuncBinding>? ExtraLuaFuncs = null,
    List<ArrayAdapterBinding>? ArrayAdapters = null,
    List<EventAdapterBinding>? EventAdapters = null
)
{
    public List<OpaqueTypeBinding> OpaqueTypes { get; init; } = OpaqueTypes ?? [];
    public List<FuncBinding> ExtraLuaFuncs { get; init; } = ExtraLuaFuncs ?? [];
    public List<ArrayAdapterBinding> ArrayAdapters { get; init; } = ArrayAdapters ?? [];
    public List<EventAdapterBinding> EventAdapters { get; init; } = EventAdapters ?? [];
}

/// <summary>
/// メタメソッド生成指示 — 変換層が展開し、CBindingGen が消費する
/// </summary>
public record MetamethodSpec(string Name, string Kind);

public record StructBinding(
    string CName,
    string PascalName,
    string Metatable,
    bool HasMetamethods,
    List<FieldBinding> Fields,
    string? SourceLink,
    bool IsHandleType = false,
    List<MetamethodSpec>? ExtraMetamethods = null,
    /// <summary>
    /// true にすると Lua 文字列を受け取り ptr/size に展開するコンストラクタを生成する。
    /// ptr (const void*) + size (size_t) を持つ構造体にのみ適用可能 (例: sg_range)。
    /// </summary>
    bool AllowStringInit = false
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
    string? SourceLink,
    string? CppNamespace = null,
    string? CppFuncName = null,
    List<PostCallPatch>? PostCallPatches = null
);

public enum CallbackBridgeMode { None, Immediate, Persistent }

public record ParamBinding(
    string Name,
    BindingType Type,
    bool IsOptional = false,
    bool IsOutput = false,
    CallbackBridgeMode CallbackBridge = CallbackBridgeMode.None
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

public record OpaqueTypeBinding(
    string CName,
    string PascalName,
    string Metatable,
    string LuaClassName,
    string? InitFunc,
    string? UninitFunc,
    string? ConfigType,
    string? ConfigInitFunc,
    List<MethodBinding> Methods,
    string? SourceLink
);

public record MethodBinding(
    string CName,
    string LuaName,
    List<ParamBinding> Params,
    BindingType ReturnType,
    string? SourceLink
);

public record ArrayAdapterBinding(
    string LuaName,
    string CountFuncCName,
    string FillFuncCName,
    List<ParamBinding> InputParams,
    BindingType ElementType
);

public record PostCallPatch(string FieldName, string CExpression);

public record EventAdapterBinding(
    string LuaName,
    string CFuncName,
    string CReturnType,
    List<ParamBinding> InputParams,
    List<EventArrayField> ArrayFields
);

public record EventArrayField(
    string LuaFieldName,
    string CArrayAccessor,
    string CCountAccessor,
    List<EventElementField> ElementFields
);

public record EventElementField(string LuaFieldName, string CAccessor, BindingType Type);
