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
    List<EventAdapterBinding>? EventAdapters = null,
    /// <summary>
    /// luaopen 内で luaL_newlib の後に挿入される追加コード。
    /// モジュールテーブルがスタックトップにある状態で実行される。
    /// </summary>
    string? ExtraInitCode = null
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
    bool AllowStringInit = false,
    List<PropertyBinding>? Properties = null
);

public record FieldBinding(
    string CName,
    string LuaName,
    BindingType Type
);

/// <summary>
/// 計算プロパティ — 複数の C フィールドを1つの Lua プロパティとして露出する。
/// GetterCode/SetterCode 内の {self} は構造体ポインタに展開される。
/// SetterCode 内の {value_idx} は Lua スタック上の値インデックスに展開される。
/// </summary>
public record PropertyBinding(
    string LuaName,
    BindingType Type,
    string GetterCode,
    string? SetterCode = null
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

/// <summary>
/// 親子ライフタイム依存: コンストラクタ引数を uservalue スロットに保持し、
/// 親が子より先に GC されるのを防ぐ (sol3 self_dependency 相当)
/// </summary>
public record DependencyBinding(
    int ConstructorArgIndex,  // コンストラクタでの Lua スタック位置 (1-indexed)
    int UservalueSlot,        // uservalue スロット番号 (1-indexed)
    string Name               // 可読名 ("engine" 等)
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
    string? SourceLink,
    List<DependencyBinding>? Dependencies = null,
    /// <summary>
    /// __gc/destroy の本体をカスタム記述する。{pp} は TYPE** ポインタ変数名に展開される。
    /// 未指定時は従来の UninitFunc(*pp) + free(*pp) パターン。
    /// </summary>
    string? CustomDestructorCode = null
)
{
    public List<DependencyBinding> Dependencies { get; init; } = Dependencies ?? [];
}

public record MethodBinding(
    string CName,
    string LuaName,
    List<ParamBinding> Params,
    BindingType ReturnType,
    string? SourceLink,
    /// <summary>
    /// メソッド本体の call + push 部分を置き換えるカスタムコード。
    /// {self} は self ポインタ変数名、{param_name} は宣言済みパラメータ変数名に展開される。
    /// </summary>
    string? CustomCallCode = null,
    /// <summary>
    /// return 文の戻り値数。-1=自動 (Void→0, 他→1), 0以上=明示指定。
    /// CustomCallCode 内で lua_push* し、ReturnCount で return N を決定する。
    /// </summary>
    int ReturnCount = -1
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
