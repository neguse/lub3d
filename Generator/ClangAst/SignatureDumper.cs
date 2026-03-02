using System.Text;

namespace Generator.ClangAst;

/// <summary>
/// TypeRegistry からコンパクトなテキスト要約を生成する。
/// Claude が読める分量に API 情報を圧縮する目的。
/// </summary>
public static class SignatureDumper
{
    public static string Dump(TypeRegistry reg)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"# {reg.Prefix} ({reg.ModuleName})");
        sb.AppendLine();

        var funcs = reg.OwnFuncs.ToList();
        if (funcs.Count > 0)
        {
            sb.AppendLine($"## Functions ({funcs.Count})");
            foreach (var f in funcs)
            {
                var retType = FormatReturnType(f.TypeStr);
                var parms = string.Join(", ", f.Params.Select(p => $"{p.Name}: {FormatType(p.TypeStr)}"));
                sb.AppendLine($"{f.Name}({parms}) -> {retType}");
            }
            sb.AppendLine();
        }

        var enums = reg.OwnEnums.ToList();
        if (enums.Count > 0)
        {
            sb.AppendLine($"## Enums ({enums.Count})");
            foreach (var e in enums)
            {
                var items = string.Join(", ", e.Items.Select(i =>
                    i.Value != null ? $"{i.Name}={i.Value}" : i.Name));
                sb.AppendLine($"{e.Name} {{ {items} }}");
            }
            sb.AppendLine();
        }

        var structs = reg.OwnStructs.ToList();
        if (structs.Count > 0)
        {
            sb.AppendLine($"## Structs ({structs.Count})");
            foreach (var s in structs)
            {
                var fields = string.Join(", ", s.Fields.Select(f => $"{f.Name}: {FormatType(f.TypeStr)}"));
                sb.AppendLine($"{s.Name} {{ {fields} }}");
            }
            sb.AppendLine();
        }

        return sb.ToString();
    }

    /// <summary>
    /// 関数の型文字列から戻り値型を抽出する。
    /// Clang の関数型は "returnType (paramTypes...)" 形式。
    /// </summary>
    private static string FormatReturnType(string funcTypeStr)
    {
        // "void (const sg_desc *)" → "void"
        // "sg_buffer (const sg_buffer_desc *)" → "sg_buffer"
        var parenIdx = funcTypeStr.IndexOf('(');
        if (parenIdx > 0)
            return funcTypeStr[..parenIdx].Trim();
        return funcTypeStr.Trim();
    }

    /// <summary>
    /// C 型文字列をそのまま使う (十分にコンパクト)
    /// </summary>
    private static string FormatType(string typeStr) => typeStr;
}
