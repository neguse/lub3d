namespace Generator;

/// <summary>
/// 統一型システム — CBinding.Type と LuaCats.Type を統合
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

    // エスケープハッチ — sg_range 等の自動演繹不可な型
    public sealed record Custom(
        string CTypeName, string LuaCatsType,
        string? InitCode, string? CheckCode,
        string? PushCode, string? SetCode) : BindingType;
}
