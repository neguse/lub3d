using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlFormatterTests
{
    private static readonly WebIdlFormatter.FormatOptions Opts = WebIdlFormatter.FormatOptions.Default;

    // ─── インデント ───

    [Fact]
    public void Format_IndentsNamespaceBody()
    {
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.Contains("    void setup();\n", output);
    }

    [Fact]
    public void Format_FixesBadIndent()
    {
        var input = "namespace test {\n      void setup();\n  void now();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.Contains("    void setup();\n", output);
        Assert.Contains("    void now();\n", output);
    }

    [Fact]
    public void Format_ClosingBraceAtTopLevel()
    {
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.StartsWith("namespace test {", output);
        Assert.Contains("\n};\n", output);
    }

    [Fact]
    public void Format_TabIndent()
    {
        var opts = new WebIdlFormatter.FormatOptions("\t", "\n", true, true);
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, opts);
        Assert.Contains("\tvoid setup();\n", output);
    }

    // ─── コメント保持 ───

    [Fact]
    public void Format_PreservesLineComments()
    {
        var input = "// header comment\nnamespace test {\n// inner comment\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.Contains("// header comment\n", output);
        Assert.Contains("    // inner comment\n", output);
    }

    [Fact]
    public void Format_PreservesInlineComments()
    {
        var input = "namespace test {\nvoid setup(); // init timing\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.Contains("    void setup(); // init timing\n", output);
    }

    // ─── 空行 ───

    [Fact]
    public void Format_CollapsesMultipleBlankLines()
    {
        var input = "// first\n\n\n\n// second\nnamespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        // 連続空行は1つに
        Assert.DoesNotContain("\n\n\n", output);
    }

    [Fact]
    public void Format_PreservesSingleBlankLine()
    {
        var input = "// section 1\n\n// section 2\nnamespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.Contains("// section 1\n\n// section 2\n", output);
    }

    [Fact]
    public void Format_RemovesTrailingBlankLines()
    {
        var input = "namespace test {\nvoid setup();\n};\n\n\n";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.EndsWith("};\n", output);
    }

    // ─── 改行コード ───

    [Fact]
    public void Format_NormalizesToLF()
    {
        var input = "namespace test {\r\nvoid setup();\r\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.DoesNotContain("\r\n", output);
        Assert.Contains("\n", output);
    }

    [Fact]
    public void Format_NormalizesToCRLF()
    {
        var opts = new WebIdlFormatter.FormatOptions("    ", "\r\n", true, true);
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, opts);
        Assert.Contains("\r\n", output);
        Assert.DoesNotContain("\n\n", output.Replace("\r\n", ""));
    }

    // ─── 末尾空白除去 ───

    [Fact]
    public void Format_TrimsTrailingWhitespace()
    {
        var input = "namespace test {   \n    void setup();   \n};   ";
        var output = WebIdlFormatter.Format(input, Opts);
        foreach (var line in output.Split('\n'))
        {
            if (line.Length > 0)
                Assert.Equal(line.TrimEnd(), line);
        }
    }

    // ─── ファイル末尾改行 ───

    [Fact]
    public void Format_InsertsFinalNewline()
    {
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, Opts);
        Assert.EndsWith("\n", output);
    }

    [Fact]
    public void Format_NoFinalNewlineWhenDisabled()
    {
        var opts = new WebIdlFormatter.FormatOptions("    ", "\n", true, false);
        var input = "namespace test {\nvoid setup();\n};";
        var output = WebIdlFormatter.Format(input, opts);
        Assert.False(output.EndsWith("\n"));
    }

    // ─── editorconfig 読み込み ───

    [Fact]
    public void LoadEditorConfig_ReadsProjectSettings()
    {
        // プロジェクトの .editorconfig を読む
        var editorconfigPath = Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", ".editorconfig");
        editorconfigPath = Path.GetFullPath(editorconfigPath);

        if (!File.Exists(editorconfigPath))
            return; // CI等で見つからない場合はスキップ

        var opts = WebIdlFormatter.LoadEditorConfig(editorconfigPath);
        Assert.Equal("    ", opts.Indent);       // indent_size=4, indent_style=space
        Assert.Equal("\n", opts.Eol);             // end_of_line=lf
        Assert.True(opts.TrimTrailing);
        Assert.True(opts.FinalNewline);
    }

    // ─── E2E: sokol_time.idl の整形 ───

    [Fact]
    public void Format_SokolTimeIdl_Roundtrip()
    {
        var input = """
            // sokol_time — timing functions
            [Prefix="stm_", CInclude="sokol_time.h"]
            namespace stm {
                void setup();
                unsigned long long now();
                unsigned long long diff(unsigned long long new_ticks, unsigned long long old_ticks);
                unsigned long long since(unsigned long long start_ticks);
                unsigned long long round_to_common_refresh_rate(unsigned long long frame_ticks);
                double sec(unsigned long long ticks);
                double ms(unsigned long long ticks);
                double us(unsigned long long ticks);
                double ns(unsigned long long ticks);
            };
            """;
        var formatted = WebIdlFormatter.Format(input, Opts);

        // 2回フォーマットしても変わらない (冪等性)
        var formatted2 = WebIdlFormatter.Format(formatted, Opts);
        Assert.Equal(formatted, formatted2);

        // 構造の確認
        Assert.Contains("// sokol_time", formatted);
        Assert.Contains("[Prefix=\"stm_\",", formatted);
        Assert.Contains("namespace stm {\n", formatted);
        Assert.Contains("    void setup();\n", formatted);
        Assert.Contains("    double ns(unsigned long long ticks);\n", formatted);
        Assert.Contains("};\n", formatted);
        Assert.EndsWith("};\n", formatted);
    }

    [Fact]
    public void Format_MessyInput_ProducesCleanOutput()
    {
        // 乱雑なインデント、CRLF混在、連続空行、末尾空白
        var input =
            "// comment   \r\n" +
            "\r\n" +
            "\r\n" +
            "\r\n" +
            "[Prefix=\"stm_\", CInclude=\"sokol_time.h\"]\r\n" +
            "namespace stm {\r\n" +
            "      void setup();   \r\n" +
            "  unsigned long long now();\r\n" +
            "\r\n" +
            "\r\n" +
            "   double sec(unsigned long long ticks);\r\n" +
            "};\r\n" +
            "\r\n";

        var output = WebIdlFormatter.Format(input, Opts);

        // LF正規化
        Assert.DoesNotContain("\r", output);
        // 連続空行なし
        Assert.DoesNotContain("\n\n\n", output);
        // 正しいインデント
        Assert.Contains("    void setup();\n", output);
        Assert.Contains("    unsigned long long now();\n", output);
        Assert.Contains("    double sec(unsigned long long ticks);\n", output);
        // 末尾空白なし
        Assert.DoesNotContain("   \n", output);
        // ファイル末尾改行
        Assert.EndsWith("};\n", output);
        // コメント保持
        Assert.Contains("// comment\n", output);
    }
}
