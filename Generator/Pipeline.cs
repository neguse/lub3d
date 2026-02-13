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
    /// PascalCase / CamelCase を snake_case に変換
    /// 例: "ShowDemoWindow" → "show_demo_window", "GetID" → "get_id"
    /// </summary>
    public static string ToSnakeCase(string s)
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            var c = s[i];
            if (c == '_') { sb.Append('_'); continue; }
            if (i > 0 && char.IsUpper(c) && s[i - 1] != '_' &&
                (char.IsLower(s[i - 1]) ||
                 (i + 1 < s.Length && char.IsLower(s[i + 1]))))
                sb.Append('_');
            sb.Append(char.ToLower(c));
        }
        return sb.ToString();
    }

    /// <summary>
    /// CamelCase / PascalCase を UPPER_SNAKE_CASE に変換
    /// 例: "NoTitleBar" → "NO_TITLE_BAR"
    /// </summary>
    public static string ToUpperSnakeCase(string s)
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            var c = s[i];
            if (i > 0 && char.IsUpper(c) && (char.IsLower(s[i - 1]) ||
                (i + 1 < s.Length && char.IsLower(s[i + 1]))))
                sb.Append('_');
            sb.Append(char.ToUpper(c));
        }
        return sb.ToString();
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
}
