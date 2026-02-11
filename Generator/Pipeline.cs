namespace Generator;

/// <summary>
/// 文字列ヘルパー
/// </summary>
public static class Pipeline
{
    public static string ToPascalCase(string s) =>
        string.Concat(s.Split('_').Select(p => p.Length > 0 ? char.ToUpper(p[0]) + p[1..] : ""));

    public static string StripPrefix(string name, string prefix) =>
        name.StartsWith(prefix) ? name[prefix.Length..] : name;

    public static string StripTypeSuffix(string name) =>
        name.EndsWith("_t") ? name[..^2] : name;

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
}
