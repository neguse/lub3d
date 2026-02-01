namespace Generator.LuaCats;

/// <summary>
/// LuaCATS 型表現
/// https://luals.github.io/wiki/annotations/
/// </summary>
public abstract record Type
{
    /// <summary>
    /// 基本型: nil, any, boolean, string, number, integer, function, table, thread, userdata, lightuserdata
    /// </summary>
    public sealed record Primitive(string Name) : Type;

    /// <summary>
    /// 関数型: fun(arg0: T, arg1: U): R
    /// </summary>
    public sealed record Fun(List<(string Name, Type Type)> Args, Type? Ret) : Type;

    /// <summary>
    /// クラス型: ModuleName.ClassName
    /// </summary>
    public sealed record Class(string FullName) : Type;
}
