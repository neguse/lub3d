namespace Generator.CBinding;

/// <summary>
/// C 型表現
/// </summary>
public abstract record Type
{
    // 整数型
    public sealed record Int : Type;           // int
    public sealed record Int64 : Type;         // int64_t
    public sealed record UInt32 : Type;        // uint32_t
    public sealed record UInt64 : Type;        // uint64_t
    public sealed record Size : Type;          // size_t
    public sealed record UIntPtr : Type;       // uintptr_t
    public sealed record IntPtr : Type;        // intptr_t

    // 浮動小数点
    public sealed record Float : Type;         // float
    public sealed record Double : Type;        // double

    // その他
    public sealed record Bool : Type;          // bool
    public sealed record String : Type;        // const char*
    public sealed record Void : Type;          // void

    // 複合型
    public sealed record Pointer(Type Inner) : Type;
    public sealed record ConstPointer(Type Inner) : Type;
    public sealed record FuncPtr(List<Type> Args, Type Ret) : Type;
    public sealed record Struct(string Name) : Type;
    public sealed record Enum(string Name) : Type;
}

/// <summary>
/// フィールド初期化の定義
/// </summary>
/// <param name="FieldName">C の構造体フィールド名</param>
/// <param name="LuaFieldName">Lua 側のフィールド名（異なる場合）</param>
/// <param name="Type">C 型</param>
/// <param name="InitCode">null ならデフォルト生成、"" なら除外（lua_pop のみ）</param>
public record FieldInit(
    string FieldName,
    string LuaFieldName,
    Type Type,
    string? InitCode
);

/// <summary>
/// 関数パラメータの定義
/// </summary>
/// <param name="Name">パラメータ名</param>
/// <param name="Type">C 型</param>
/// <param name="CheckCode">null ならデフォルト生成</param>
public record Param(
    string Name,
    Type Type,
    string? CheckCode
);
