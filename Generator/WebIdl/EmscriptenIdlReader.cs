using System.Text;
using System.Text.RegularExpressions;

namespace Generator.WebIdl;

/// <summary>
/// Emscripten WebIDL binder 方言を読み、lub3d の IdlFile IR に変換する。
/// JoltJS.idl, ammo.idl 等で使われる Emscripten 拡張 WebIDL をパースする。
/// </summary>
public static class EmscriptenIdlReader
{
    /// <summary>
    /// Emscripten WebIDL テキストをパースし、EmscriptenIdlFile を返す。
    /// </summary>
    public static EmscriptenIdlFile Parse(string source)
    {
        var interfaces = new List<EmInterface>();
        var enums = new List<EmEnum>();
        var implements = new List<(string Child, string Parent)>();

        var lines = source.Split('\n');
        var i = 0;

        while (i < lines.Length)
        {
            var line = lines[i].Trim();

            // Skip comments and empty lines
            if (string.IsNullOrEmpty(line) || line.StartsWith("//"))
            {
                i++;
                continue;
            }

            // ExtAttrs on their own line (applies to next declaration)
            var extAttrs = new Dictionary<string, string?>();
            if (line.StartsWith('['))
            {
                extAttrs = ParseExtAttrs(line);
                i++;
                if (i >= lines.Length) break;
                line = lines[i].Trim();
            }

            // enum
            if (line.StartsWith("enum "))
            {
                var (e, nextI) = ParseEnum(lines, i);
                enums.Add(e);
                i = nextI;
                continue;
            }

            // interface
            if (line.StartsWith("interface "))
            {
                var (iface, nextI) = ParseInterface(lines, i, extAttrs);
                interfaces.Add(iface);
                i = nextI;
                continue;
            }

            // "ChildInterface implements ParentInterface;"
            var implMatch = Regex.Match(line, @"^(\w+)\s+implements\s+(\w+)\s*;");
            if (implMatch.Success)
            {
                implements.Add((implMatch.Groups[1].Value, implMatch.Groups[2].Value));
                i++;
                continue;
            }

            i++;
        }

        return new EmscriptenIdlFile(interfaces, enums, implements);
    }

    /// <summary>
    /// EmscriptenIdlFile を lub3d の WebIdlFormatter で出力可能な IDL テキストに変換。
    /// </summary>
    public static string ToLub3dIdl(EmscriptenIdlFile file)
    {
        var sb = new StringBuilder();
        sb.AppendLine("// Auto-generated from Emscripten WebIDL");
        sb.AppendLine("// Manual review and subset selection recommended");
        sb.AppendLine();

        // Build inheritance map
        var parentMap = new Dictionary<string, string>();
        foreach (var (child, parent) in file.Implements)
            parentMap[child] = parent;

        // Enums
        foreach (var e in file.Enums)
        {
            sb.AppendLine($"enum {e.Name} {{");
            for (var i = 0; i < e.Values.Count; i++)
            {
                var comma = i < e.Values.Count - 1 ? "," : "";
                sb.AppendLine($"    \"{e.Values[i]}\" = {i}{comma}");
            }
            sb.AppendLine("};");
            sb.AppendLine();
        }

        // Interfaces
        foreach (var iface in file.Interfaces)
        {
            // ExtAttrs line
            var attrs = new List<string>();
            if (iface.ExtAttrs.ContainsKey("NoDelete"))
                attrs.Add("NoDelete");
            if (iface.ExtAttrs.ContainsKey("JSImplementation"))
                attrs.Add($"JSImplementation=\"{iface.ExtAttrs["JSImplementation"]}\"");

            var hasConstructor = iface.Members.Any(m => m.Kind == EmMemberKind.Constructor);
            if (hasConstructor)
                attrs.Add("Constructor");

            if (attrs.Count > 0)
                sb.AppendLine($"[{string.Join(", ", attrs)}]");

            // interface declaration with optional inheritance
            var inherit = parentMap.TryGetValue(iface.Name, out var parent) ? $" : {parent}" : "";
            sb.AppendLine($"interface {iface.Name}{inherit} {{");

            foreach (var member in iface.Members)
            {
                switch (member.Kind)
                {
                    case EmMemberKind.Constructor:
                        // Skip constructors (represented by [Constructor] ExtAttr)
                        break;
                    case EmMemberKind.Method:
                        var parms = string.Join(", ", member.Params.Select(FormatParam));
                        var retType = FormatType(member.ReturnType!, member.ReturnAttrs);
                        var methodAttrs = FormatMethodAttrs(member);
                        if (methodAttrs.Length > 0) methodAttrs += " ";
                        var staticKw = member.IsStatic ? "static " : "";
                        sb.AppendLine($"    {methodAttrs}{staticKw}{retType} {member.Name}({parms});");
                        break;
                    case EmMemberKind.Attribute:
                        var attrType = FormatType(member.ReturnType!, member.ReturnAttrs);
                        sb.AppendLine($"    {attrType} {member.Name};");
                        break;
                }
            }

            sb.AppendLine("};");
            sb.AppendLine();
        }

        return sb.ToString();
    }

    private static string FormatParam(EmParam p)
    {
        var type = FormatType(p.Type, p.Attrs);
        var opt = p.IsOptional ? "?" : "";
        return $"{type}{opt} {p.Name}";
    }

    private static string FormatType(string type, HashSet<string>? attrs)
    {
        // Keep type as-is for lub3d IDL
        return type;
    }

    private static string FormatMethodAttrs(EmMember member)
    {
        var attrs = new List<string>();
        if (member.ReturnAttrs?.Contains("Value") == true)
            attrs.Add("Value");
        if (member.ExtAttrs?.ContainsKey("Operator") == true)
            attrs.Add($"Operator=\"{member.ExtAttrs["Operator"]}\"");
        if (member.ExtAttrs?.ContainsKey("BindTo") == true)
            attrs.Add($"CppFunc=\"{member.ExtAttrs["BindTo"]}\"");
        return attrs.Count > 0 ? $"[{string.Join(", ", attrs)}]" : "";
    }

    // --- Parsing helpers ---

    private static Dictionary<string, string?> ParseExtAttrs(string line)
    {
        var attrs = new Dictionary<string, string?>();
        // Match [Key1, Key2="val", Key3]
        var match = Regex.Match(line, @"^\[(.+)\]");
        if (!match.Success) return attrs;

        var content = match.Groups[1].Value;
        foreach (var part in SplitAttrs(content))
        {
            var trimmed = part.Trim();
            var eqIdx = trimmed.IndexOf('=');
            if (eqIdx > 0)
            {
                var key = trimmed[..eqIdx].Trim();
                var val = trimmed[(eqIdx + 1)..].Trim().Trim('"');
                attrs[key] = val;
            }
            else
            {
                attrs[trimmed] = null;
            }
        }
        return attrs;
    }

    /// <summary>
    /// Split comma-separated attrs, respecting quotes
    /// </summary>
    private static List<string> SplitAttrs(string s)
    {
        var parts = new List<string>();
        var current = new StringBuilder();
        var inQuote = false;
        foreach (var c in s)
        {
            if (c == '"') inQuote = !inQuote;
            if (c == ',' && !inQuote)
            {
                parts.Add(current.ToString());
                current.Clear();
            }
            else
            {
                current.Append(c);
            }
        }
        if (current.Length > 0) parts.Add(current.ToString());
        return parts;
    }

    private static (EmEnum, int nextI) ParseEnum(string[] lines, int i)
    {
        // "enum Name {"
        var match = Regex.Match(lines[i].Trim(), @"^enum\s+(\w+)\s*\{");
        var name = match.Groups[1].Value;
        var values = new List<string>();
        i++;

        while (i < lines.Length)
        {
            var line = lines[i].Trim();
            if (line == "};") { i++; break; }

            var valMatch = Regex.Match(line, @"""([^""]+)""");
            if (valMatch.Success)
                values.Add(valMatch.Groups[1].Value);
            i++;
        }

        return (new EmEnum(name, values), i);
    }

    private static (EmInterface, int nextI) ParseInterface(string[] lines, int startI,
        Dictionary<string, string?> extAttrs)
    {
        var headerLine = lines[startI].Trim();
        var match = Regex.Match(headerLine, @"^interface\s+(\w+)\s*\{");
        var name = match.Groups[1].Value;

        var members = new List<EmMember>();
        var i = startI + 1;

        while (i < lines.Length)
        {
            var line = lines[i].Trim();
            if (line == "};") { i++; break; }
            if (string.IsNullOrEmpty(line) || line.StartsWith("//")) { i++; continue; }

            var member = ParseMember(line, name);
            if (member != null) members.Add(member);
            i++;
        }

        var ifaceAttrs = new Dictionary<string, string?>(
            extAttrs.Select(kv => new KeyValuePair<string, string?>(kv.Key, kv.Value)));

        return (new EmInterface(name, members, ifaceAttrs), i);
    }

    private static EmMember? ParseMember(string line, string interfaceName)
    {
        // Parse member-level ExtAttrs
        Dictionary<string, string?>? memberAttrs = null;
        var returnAttrs = new HashSet<string>();
        if (line.StartsWith('['))
        {
            var bracketEnd = FindMatchingBracket(line, 0);
            if (bracketEnd > 0)
            {
                var attrStr = line[..(bracketEnd + 1)];
                memberAttrs = ParseExtAttrs(attrStr);
                // Value, Const, Ref are return-type attrs
                foreach (var key in new[] { "Value", "Const", "Ref" })
                {
                    if (memberAttrs.ContainsKey(key))
                        returnAttrs.Add(key);
                }
                line = line[(bracketEnd + 1)..].Trim();
            }
        }

        // attribute
        var attrMatch = Regex.Match(line, @"^(?:readonly\s+)?attribute\s+(.+?)\s+(\w+)\s*;");
        if (attrMatch.Success)
        {
            return new EmMember(EmMemberKind.Attribute, attrMatch.Groups[2].Value,
                attrMatch.Groups[1].Value, returnAttrs, [], false, memberAttrs);
        }

        // Parse method: [static] ReturnType Name(params);
        var isStatic = false;
        if (line.StartsWith("static "))
        {
            isStatic = true;
            line = line["static ".Length..];
        }

        // returnType methodName(params);
        var methodMatch = Regex.Match(line, @"^(.+?)\s+(\w+)\s*\(([^)]*)\)\s*;");
        if (!methodMatch.Success) return null;

        var retType = methodMatch.Groups[1].Value.Trim();
        var methodName = methodMatch.Groups[2].Value;
        var paramStr = methodMatch.Groups[3].Value.Trim();

        // Constructor: void InterfaceName(...)
        if (retType == "void" && methodName == interfaceName)
        {
            var ctorParams = ParseParams(paramStr);
            return new EmMember(EmMemberKind.Constructor, methodName,
                "void", returnAttrs, ctorParams, false, memberAttrs);
        }

        var parms = ParseParams(paramStr);
        return new EmMember(EmMemberKind.Method, methodName,
            retType, returnAttrs, parms, isStatic, memberAttrs);
    }

    private static List<EmParam> ParseParams(string paramStr)
    {
        if (string.IsNullOrWhiteSpace(paramStr)) return [];

        var parms = new List<EmParam>();
        foreach (var part in SplitParams(paramStr))
        {
            var p = part.Trim();
            if (string.IsNullOrEmpty(p)) continue;

            var attrs = new HashSet<string>();
            // Parse param-level attrs: [Const, Ref] Type name
            if (p.StartsWith('['))
            {
                var bracketEnd = FindMatchingBracket(p, 0);
                if (bracketEnd > 0)
                {
                    var attrContent = p[1..bracketEnd];
                    foreach (var a in attrContent.Split(','))
                        attrs.Add(a.Trim());
                    p = p[(bracketEnd + 1)..].Trim();
                }
            }

            var isOptional = false;
            if (p.StartsWith("optional "))
            {
                isOptional = true;
                p = p["optional ".Length..];
            }

            // "unsigned long name" or "Type name" — last word is name
            var lastSpace = p.LastIndexOf(' ');
            if (lastSpace <= 0) continue;

            var type = p[..lastSpace].Trim();
            var name = p[(lastSpace + 1)..].Trim();

            parms.Add(new EmParam(name, type, attrs, isOptional));
        }
        return parms;
    }

    private static List<string> SplitParams(string s)
    {
        var parts = new List<string>();
        var current = new StringBuilder();
        var bracketDepth = 0;
        foreach (var c in s)
        {
            if (c == '[') bracketDepth++;
            if (c == ']') bracketDepth--;
            if (c == ',' && bracketDepth == 0)
            {
                parts.Add(current.ToString());
                current.Clear();
            }
            else
            {
                current.Append(c);
            }
        }
        if (current.Length > 0) parts.Add(current.ToString());
        return parts;
    }

    private static int FindMatchingBracket(string s, int start)
    {
        var depth = 0;
        for (var i = start; i < s.Length; i++)
        {
            if (s[i] == '[') depth++;
            if (s[i] == ']') { depth--; if (depth == 0) return i; }
        }
        return -1;
    }
}

// --- Emscripten IDL IR types ---

public record EmscriptenIdlFile(
    List<EmInterface> Interfaces,
    List<EmEnum> Enums,
    List<(string Child, string Parent)> Implements);

public record EmInterface(
    string Name,
    List<EmMember> Members,
    Dictionary<string, string?> ExtAttrs);

public record EmEnum(string Name, List<string> Values);

public enum EmMemberKind { Constructor, Method, Attribute }

public record EmMember(
    EmMemberKind Kind,
    string Name,
    string? ReturnType,
    HashSet<string>? ReturnAttrs,
    List<EmParam> Params,
    bool IsStatic,
    Dictionary<string, string?>? ExtAttrs);

public record EmParam(
    string Name,
    string Type,
    HashSet<string>? Attrs,
    bool IsOptional);
