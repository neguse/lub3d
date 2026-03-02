namespace Generator.WebIdl;

/// <summary>
/// WebIDL 型参照 (e.g. "void", "unsigned long long", "sg_color")
/// ArrayLength が非 null の場合は FixedArray (e.g. "float[8]")
/// </summary>
public record IdlType(string Name, int? ArrayLength = null);

/// <summary>
/// 関数パラメータ
/// </summary>
public record IdlParam(string Name, IdlType Type);

/// <summary>
/// namespace 内のオペレーション (関数)
/// </summary>
public record IdlOperation(string Name, IdlType ReturnType, List<IdlParam> Params,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// WebIDL namespace 定義
/// </summary>
public record IdlNamespace(string Name, List<IdlOperation> Operations);

/// <summary>
/// enum 値 (整数値付き)
/// </summary>
public record IdlEnumValue(string Name, int Value);

/// <summary>
/// WebIDL enum 定義 (整数値付き拡張)
/// </summary>
public record IdlEnum(string CName, List<IdlEnumValue> Values,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// dictionary フィールド (C struct のフィールドに対応)
/// ExtAttrs: per-field 属性 ([Ignore] 等)
/// </summary>
public record IdlField(string Name, IdlType Type, Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// WebIDL dictionary 定義 (C struct に対応)
/// </summary>
public record IdlDictionary(string CName, List<IdlField> Fields,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// interface 内のメソッド (self パラメータは暗黙)
/// </summary>
public record IdlMethod(string Name, IdlType ReturnType, List<IdlParam> Params,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// WebIDL interface 定義 (opaque type に対応)
/// </summary>
public record IdlInterface(string CName, List<IdlMethod> Methods,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// Callback 型定義 (e.g. callback b2OverlapResultFcn = boolean (b2ShapeId shapeId);)
/// </summary>
public record IdlCallback(string CName, List<IdlParam> Params, IdlType ReturnType,
    Dictionary<string, string>? ExtAttrs = null);

/// <summary>
/// EventAdapter 内の配列フィールド定義
/// </summary>
public record IdlEventArrayDef(string LuaFieldName, string CArrayAccessor, string CCountAccessor,
    List<IdlEventFieldDef> Fields);

/// <summary>
/// EventAdapter 内の要素フィールド定義
/// </summary>
public record IdlEventFieldDef(string LuaName, string CAccessor, IdlType Type);

/// <summary>
/// EventAdapter 定義 (event キーワード)
/// CFunc: 明示指定時の C 関数名 (null の場合は prefix + PascalCase(LuaName) で生成)
/// </summary>
public record IdlEventAdapter(string LuaName, string CReturnType,
    List<IdlParam> Params, List<IdlEventArrayDef> Arrays,
    string? CFunc = null);

/// <summary>
/// IDL ファイル全体 — 拡張属性 + namespace + enum + dictionary + interface + callback + event を保持
/// </summary>
public record IdlFile(
    Dictionary<string, string> ExtAttrs,
    IdlNamespace? Namespace,
    List<IdlEnum> Enums,
    List<IdlDictionary> Dictionaries,
    List<IdlInterface> Interfaces,
    List<IdlCallback> Callbacks = default!,
    List<IdlEventAdapter> EventAdapters = default!
)
{
    public List<IdlCallback> Callbacks { get; init; } = Callbacks ?? [];
    public List<IdlEventAdapter> EventAdapters { get; init; } = EventAdapters ?? [];
}
