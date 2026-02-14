namespace Generator;

/// <summary>
/// 統一型システム — C gen と LuaCATS gen の共通型表現
/// C gen はキャスト区別、Lua gen は integer/number に潰す
/// </summary>
public abstract record BindingType
{
    // 数値型
    public sealed record Int : BindingType;
    public sealed record Int64 : BindingType;
    public sealed record UInt32 : BindingType;
    public sealed record UInt64 : BindingType;
    public sealed record Size : BindingType;
    public sealed record UIntPtr : BindingType;
    public sealed record IntPtr : BindingType;
    public sealed record Float : BindingType;
    public sealed record Double : BindingType;

    // 単純型
    public sealed record Bool : BindingType;
    public sealed record Str : BindingType;
    public sealed record VoidPtr : BindingType;
    public sealed record Void : BindingType;

    // 複合型
    public sealed record Ptr(BindingType Inner) : BindingType;
    public sealed record ConstPtr(BindingType Inner) : BindingType;
    public sealed record Struct(string CName, string Metatable, string LuaClassName) : BindingType;
    public sealed record Enum(string CName, string LuaName) : BindingType;
    public sealed record FixedArray(BindingType Inner, int Length) : BindingType;
    public sealed record Callback(List<(string Name, BindingType Type)> Params, BindingType? Ret) : BindingType;

    // C++ ImGui 用型
    public sealed record Vec2 : BindingType;               // ImVec2 → table {x, y}
    public sealed record Vec4 : BindingType;               // ImVec4 → table {x, y, z, w}
    public sealed record FloatArray(int Length) : BindingType; // float[N] → table

    // 値型構造体 — table ⇔ C struct 変換を構造化データから生成
    public sealed record ValueStruct(
        string CTypeName, string LuaCatsType,
        List<ValueStructField> Fields,
        bool Settable = true) : BindingType;

    public abstract record ValueStructField(string CAccessor);
    public sealed record ScalarField(string CAccessor) : ValueStructField(CAccessor);
    public sealed record NestedFields(string CAccessor, List<string> SubAccessors) : ValueStructField(CAccessor);

    // エスケープハッチ — sg_range 等の自動演繹不可な型
    public sealed record Custom(
        string CTypeName, string LuaCatsType,
        string? InitCode, string? CheckCode,
        string? PushCode, string? SetCode) : BindingType;
}
