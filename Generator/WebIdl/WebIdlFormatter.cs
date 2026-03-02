using System.Text;
using System.Text.RegularExpressions;

namespace Generator.WebIdl;

/// <summary>
/// WebIDL ソースのフォーマッタ。
/// コメントを保持したまま、editorconfig ベースでインデント・改行コード・空行を整形する。
/// </summary>
public static partial class WebIdlFormatter
{
    public record FormatOptions(
        string Indent,        // インデント1段分の文字列 (e.g. "    ", "\t")
        string Eol,           // 改行コード ("\n", "\r\n", "\r")
        bool TrimTrailing,    // 末尾空白除去
        bool FinalNewline     // ファイル末尾改行
    )
    {
        /// <summary>editorconfig のデフォルト値</summary>
        public static FormatOptions Default => new("    ", "\n", true, true);
    }

    /// <summary>
    /// .editorconfig ファイルから FormatOptions を構築する。
    /// [*] セクション(または *.idl がマッチするセクション)の設定を使う。
    /// </summary>
    public static FormatOptions LoadEditorConfig(string editorconfigPath)
    {
        var settings = ParseEditorConfig(editorconfigPath);

        var indentStyle = settings.GetValueOrDefault("indent_style", "space");
        var indentSize = int.TryParse(settings.GetValueOrDefault("indent_size", "4"), out var sz) ? sz : 4;
        var indent = indentStyle == "tab" ? "\t" : new string(' ', indentSize);

        var eolSetting = settings.GetValueOrDefault("end_of_line", "lf");
        var eol = eolSetting switch
        {
            "crlf" => "\r\n",
            "cr" => "\r",
            _ => "\n"
        };

        var trimTrailing = settings.GetValueOrDefault("trim_trailing_whitespace", "true") == "true";
        var finalNewline = settings.GetValueOrDefault("insert_final_newline", "true") == "true";

        return new FormatOptions(indent, eol, trimTrailing, finalNewline);
    }

    /// <summary>
    /// WebIDL ソースを整形する。コメントはそのまま保持される。
    /// </summary>
    public static string Format(string source, FormatOptions options)
    {
        // 改行で分割 (任意の改行コードに対応)
        var lines = SplitLines(source);

        var result = new List<string>();
        var depth = 0;
        var prevBlank = false;

        foreach (var rawLine in lines)
        {
            var trimmed = rawLine.Trim();

            // 空行: 連続する空行は1つにまとめる
            if (trimmed.Length == 0)
            {
                if (!prevBlank && result.Count > 0)
                    result.Add("");
                prevBlank = true;
                continue;
            }
            prevBlank = false;

            // "}" を含む行 → 先にインデント下げ
            if (trimmed.StartsWith('}'))
                depth = Math.Max(0, depth - 1);

            // インデント適用
            var indented = depth > 0
                ? string.Concat(Enumerable.Repeat(options.Indent, depth)) + trimmed
                : trimmed;

            // 末尾空白除去
            if (options.TrimTrailing)
                indented = indented.TrimEnd();

            result.Add(indented);

            // "{" を含む行 → 次の行からインデント上げ
            // ただし "{}" が同じ行にある場合は上げない
            if (trimmed.Contains('{') && !trimmed.Contains('}'))
                depth++;
        }

        // 末尾の空行を除去
        while (result.Count > 0 && result[^1].Length == 0)
            result.RemoveAt(result.Count - 1);

        var sb = new StringBuilder();
        for (var i = 0; i < result.Count; i++)
        {
            sb.Append(result[i]);
            sb.Append(options.Eol);
        }

        // ファイル末尾改行: 既にEolが付いているので、
        // FinalNewline=false なら最後のEolを除去
        if (!options.FinalNewline && sb.Length >= options.Eol.Length)
            sb.Remove(sb.Length - options.Eol.Length, options.Eol.Length);

        return sb.ToString();
    }

    // ─── helpers ───

    private static string[] SplitLines(string source)
        => SplitLinesRegex().Split(source);

    [GeneratedRegex(@"\r\n|\r|\n")]
    private static partial Regex SplitLinesRegex();

    /// <summary>
    /// 簡易 .editorconfig パーサ。[*] と *.idl にマッチするセクションの設定を返す。
    /// </summary>
    private static Dictionary<string, string> ParseEditorConfig(string path)
    {
        var settings = new Dictionary<string, string>();
        var inMatchingSection = false;

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#') || line.StartsWith(';'))
                continue;

            // セクションヘッダ
            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                var pattern = line[1..^1].Trim();
                inMatchingSection = SectionMatchesIdl(pattern);
                continue;
            }

            // key = value
            if (inMatchingSection)
            {
                var eqIdx = line.IndexOf('=');
                if (eqIdx > 0)
                {
                    var key = line[..eqIdx].Trim().ToLowerInvariant();
                    var val = line[(eqIdx + 1)..].Trim().ToLowerInvariant();
                    settings[key] = val;
                }
            }
        }

        return settings;
    }

    /// <summary>
    /// editorconfig セクションパターンが .idl ファイルにマッチするか判定。
    /// [*], [*.idl], [{*.idl,*.webidl}] などにマッチ。
    /// </summary>
    private static bool SectionMatchesIdl(string pattern)
    {
        if (pattern == "*") return true;
        if (pattern == "*.idl") return true;
        if (pattern.Contains("*.idl")) return true;
        return false;
    }
}
