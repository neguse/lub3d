using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Generator.ClangAst;

/// <summary>
/// Module definition (root of JSON)
/// </summary>
public record Module(
    [property: JsonPropertyName("module")] string Name,
    [property: JsonPropertyName("prefix")] string Prefix,
    [property: JsonPropertyName("dep_prefixes")] List<string> DepPrefixes,
    [property: JsonPropertyName("decls")] List<Decl> Decls
);

/// <summary>
/// Declaration types
/// </summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "kind")]
[JsonDerivedType(typeof(Structs), "struct")]
[JsonDerivedType(typeof(Funcs), "func")]
[JsonDerivedType(typeof(Enums), "enum")]
[JsonDerivedType(typeof(Consts), "consts")]
public abstract record Decl(
    [property: JsonPropertyName("is_dep")] bool IsDep,
    [property: JsonPropertyName("dep_prefix")] string? DepPrefix
);

public record Structs(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("fields")] List<Field> Fields,
    bool IsDep, string? DepPrefix,
    [property: JsonPropertyName("line")] int? Line = null
) : Decl(IsDep, DepPrefix);

public record Funcs(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("type")] string TypeStr,
    [property: JsonPropertyName("params")] List<Param> Params,
    bool IsDep, string? DepPrefix,
    [property: JsonPropertyName("line")] int? Line = null
) : Decl(IsDep, DepPrefix);

public record Enums(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("items")] List<EnumItem> Items,
    bool IsDep, string? DepPrefix,
    [property: JsonPropertyName("line")] int? Line = null
) : Decl(IsDep, DepPrefix);

public record Consts(
    [property: JsonPropertyName("items")] List<EnumItem> Items,
    bool IsDep, string? DepPrefix
) : Decl(IsDep, DepPrefix);

/// <summary>
/// Field in a struct (type is C type string, parsed on demand)
/// </summary>
public record Field(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("type")] string TypeStr
)
{
    public Types ParsedType => CTypeParser.Parse(TypeStr);
}

/// <summary>
/// Parameter in a function
/// </summary>
public record Param(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("type")] string TypeStr
)
{
    public Types ParsedType => CTypeParser.Parse(TypeStr);
}

/// <summary>
/// Enum item
/// </summary>
public record EnumItem(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("value")] string? Value
);

/// <summary>
/// Represents C types in the AST (parsed from type strings)
/// </summary>
public abstract record Types
{
    public sealed record Int : Types;
    public sealed record Int64 : Types;
    public sealed record UInt32 : Types;
    public sealed record UInt64 : Types;
    public sealed record Size : Types;
    public sealed record UIntPtr : Types;
    public sealed record IntPtr : Types;
    public sealed record Float : Types;
    public sealed record Double : Types;
    public sealed record Bool : Types;
    public sealed record String : Types;
    public sealed record Ptr(Types Inner) : Types;
    public sealed record ConstPtr(Types Inner) : Types;
    public sealed record FuncPtr(List<Types> Args, Types Ret) : Types;
    public sealed record StructRef(string Name) : Types;
    public sealed record Void : Types;
}

/// <summary>
/// Clang を実行してヘッダファイルから Module を構築する
/// </summary>
public static class ClangRunner
{
    /// <summary>
    /// clang を実行して AST JSON を取得し、Module に変換する
    /// </summary>
    public static Module ParseHeader(
        string clangPath,
        string headerPath,
        string moduleName,
        string prefix,
        List<string> depPrefixes,
        List<string> includePaths)
    {
        var json = RunClang(clangPath, headerPath, includePaths);
        return ParseAstJson(json, moduleName, prefix, depPrefixes);
    }

    private static string RunClang(string clangPath, string headerPath, List<string> includePaths)
    {
        var wrapperPath = Path.Combine(Path.GetTempPath(), "generator_wrapper.c");
        File.WriteAllText(wrapperPath, $"""
            #include <stdbool.h>
            #include <stdint.h>
            #include <stddef.h>
            #include "{Path.GetFileName(headerPath)}"
            """);

        var args = new List<string>
        {
            "-Xclang", "-ast-dump=json",
            "-fsyntax-only"
        };
        var headerDir = Path.GetDirectoryName(headerPath);
        if (headerDir != null)
            args.AddRange(["-I", headerDir]);
        foreach (var inc in includePaths)
            args.AddRange(["-I", inc]);
        args.Add(wrapperPath);

        var psi = new ProcessStartInfo
        {
            FileName = clangPath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var arg in args)
            psi.ArgumentList.Add(arg);

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start clang: {clangPath}");
        var stdout = proc.StandardOutput.ReadToEnd();
        var stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit();

        if (proc.ExitCode != 0)
            throw new InvalidOperationException($"clang failed (exit {proc.ExitCode}):\n{stderr}");

        return stdout;
    }

    private static Module ParseAstJson(string json, string moduleName, string prefix, List<string> depPrefixes)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var decls = new List<Decl>();
        var allPrefixes = new List<string> { prefix };
        allPrefixes.AddRange(depPrefixes);

        foreach (var node in root.GetProperty("inner").EnumerateArray())
        {
            var kind = node.GetProperty("kind").GetString() ?? "";
            var name = node.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";

            var matchedPrefix = allPrefixes.FirstOrDefault(p => name.StartsWith(p));
            if (matchedPrefix == null) continue;
            if (kind == "TypedefDecl") continue;

            var isDep = matchedPrefix != prefix;
            string? depPrefix = isDep ? matchedPrefix : null;

            var line = GetLine(node);

            switch (kind)
            {
                case "FunctionDecl":
                    decls.Add(ParseFunc(node, isDep, depPrefix, line));
                    break;
                case "RecordDecl":
                    if (node.TryGetProperty("tagUsed", out var tag) && tag.GetString() == "struct")
                        decls.Add(ParseStruct(node, isDep, depPrefix, line));
                    break;
                case "EnumDecl":
                    decls.Add(ParseEnum(node, isDep, depPrefix, line));
                    break;
            }
        }

        return new Module(moduleName, prefix, depPrefixes, decls);
    }

    private static int? GetLine(JsonElement node)
    {
        if (node.TryGetProperty("loc", out var loc) && loc.TryGetProperty("line", out var line))
            return line.GetInt32();
        return null;
    }

    private static Funcs ParseFunc(JsonElement node, bool isDep, string? depPrefix, int? line)
    {
        var name = node.GetProperty("name").GetString()!;
        var typeStr = node.GetProperty("type").GetProperty("qualType").GetString()!;
        var parms = new List<Param>();

        if (node.TryGetProperty("inner", out var inner))
        {
            foreach (var child in inner.EnumerateArray())
            {
                if (child.GetProperty("kind").GetString() != "ParmVarDecl") continue;
                var pName = child.TryGetProperty("name", out var pn) ? pn.GetString() ?? "" : "";
                var pType = child.GetProperty("type").GetProperty("qualType").GetString()!;
                parms.Add(new Param(pName, pType));
            }
        }

        return new Funcs(name, typeStr, parms, isDep, depPrefix, line);
    }

    private static Structs ParseStruct(JsonElement node, bool isDep, string? depPrefix, int? line)
    {
        var name = node.GetProperty("name").GetString()!;
        var fields = new List<Field>();

        if (node.TryGetProperty("inner", out var inner))
        {
            foreach (var child in inner.EnumerateArray())
            {
                if (child.GetProperty("kind").GetString() != "FieldDecl") continue;
                var fName = child.GetProperty("name").GetString()!;
                var fType = child.GetProperty("type").GetProperty("qualType").GetString()!;
                fields.Add(new Field(fName, fType));
            }
        }

        return new Structs(name, fields, isDep, depPrefix, line);
    }

    private static Enums ParseEnum(JsonElement node, bool isDep, string? depPrefix, int? line)
    {
        var name = node.GetProperty("name").GetString()!;
        var items = new List<EnumItem>();

        if (node.TryGetProperty("inner", out var inner))
        {
            foreach (var child in inner.EnumerateArray())
            {
                if (child.GetProperty("kind").GetString() != "EnumConstantDecl") continue;
                var iName = child.GetProperty("name").GetString()!;
                var value = TryGetEnumValue(child);
                items.Add(new EnumItem(iName, value));
            }
        }

        return new Enums(name, items, isDep, depPrefix, line);
    }

    private static string? TryGetEnumValue(JsonElement node)
    {
        if (!node.TryGetProperty("inner", out var inner)) return null;

        foreach (var child in inner.EnumerateArray())
        {
            var kind = child.GetProperty("kind").GetString();

            if (kind == "ConstantExpr" && child.TryGetProperty("value", out var val))
                return val.GetString();

            if (kind == "ImplicitCastExpr" && child.TryGetProperty("inner", out var castInner))
            {
                foreach (var castChild in castInner.EnumerateArray())
                {
                    if (castChild.GetProperty("kind").GetString() == "ConstantExpr"
                        && castChild.TryGetProperty("value", out var castVal))
                        return castVal.GetString();
                }
            }
        }

        return null;
    }
}

/// <summary>
/// Parses C type strings into Types
/// </summary>
public static partial class CTypeParser
{
    [GeneratedRegex(@"^void\s*\(\*\)\s*\(void\)$")]
    private static partial Regex VoidFuncPtrRegex();

    [GeneratedRegex(@"^void\s*\(\*\)\s*\((.+)\)$")]
    private static partial Regex VoidRetFuncPtrRegex();

    [GeneratedRegex(@"^(.+?)\s*\(\*\)\s*\((.+)\)$")]
    private static partial Regex FuncPtrRegex();

    [GeneratedRegex(@"^(.+?)\s*\(\*\)\s*\(void\)$")]
    private static partial Regex FuncPtrNoArgsRegex();

    [GeneratedRegex(@"^const\s+(.+)\s*\*$")]
    private static partial Regex ConstPtrRegex();

    [GeneratedRegex(@"^(.+)\s*\*$")]
    private static partial Regex PtrRegex();

    [GeneratedRegex(@"^(.+)\s*\[\d+\]$")]
    private static partial Regex ArrayRegex();

    public static Types Parse(string typeStr)
    {
        typeStr = typeStr.Trim();

        if (VoidFuncPtrRegex().IsMatch(typeStr))
            return new Types.FuncPtr([], new Types.Void());

        var voidRetMatch = VoidRetFuncPtrRegex().Match(typeStr);
        if (voidRetMatch.Success)
            return new Types.FuncPtr(ParseParams(voidRetMatch.Groups[1].Value), new Types.Void());

        var funcPtrNoArgsMatch = FuncPtrNoArgsRegex().Match(typeStr);
        if (funcPtrNoArgsMatch.Success)
            return new Types.FuncPtr([], Parse(funcPtrNoArgsMatch.Groups[1].Value.Trim()));

        var funcPtrMatch = FuncPtrRegex().Match(typeStr);
        if (funcPtrMatch.Success)
            return new Types.FuncPtr(
                ParseParams(funcPtrMatch.Groups[2].Value),
                Parse(funcPtrMatch.Groups[1].Value.Trim()));

        var constPtrMatch = ConstPtrRegex().Match(typeStr);
        if (constPtrMatch.Success)
        {
            var inner = constPtrMatch.Groups[1].Value.Trim();
            return inner == "void"
                ? new Types.Ptr(new Types.Void())
                : new Types.ConstPtr(Parse(inner));
        }

        var ptrMatch = PtrRegex().Match(typeStr);
        if (ptrMatch.Success)
        {
            var inner = ptrMatch.Groups[1].Value.Trim();
            return inner == "void"
                ? new Types.Ptr(new Types.Void())
                : new Types.Ptr(Parse(inner));
        }

        var arrayMatch = ArrayRegex().Match(typeStr);
        if (arrayMatch.Success)
            return new Types.Ptr(Parse(arrayMatch.Groups[1].Value));

        return typeStr switch
        {
            "void" => new Types.Void(),
            "int" or "int32_t" => new Types.Int(),
            "int64_t" => new Types.Int64(),
            "uint32_t" => new Types.UInt32(),
            "uint64_t" => new Types.UInt64(),
            "size_t" => new Types.Size(),
            "uintptr_t" => new Types.UIntPtr(),
            "intptr_t" => new Types.IntPtr(),
            "float" => new Types.Float(),
            "double" => new Types.Double(),
            "bool" => new Types.Bool(),
            "char" or "const char" => new Types.String(),
            _ => new Types.StructRef(typeStr)
        };
    }

    private static List<Types> ParseParams(string paramsStr)
    {
        if (string.IsNullOrWhiteSpace(paramsStr) || paramsStr == "void")
            return [];

        var result = new List<Types>();
        var depth = 0;
        var current = "";

        foreach (var c in paramsStr)
        {
            if (c == '(' || c == '[') depth++;
            else if (c == ')' || c == ']') depth--;
            else if (c == ',' && depth == 0)
            {
                if (!string.IsNullOrWhiteSpace(current))
                    result.Add(Parse(current.Trim()));
                current = "";
                continue;
            }
            current += c;
        }

        if (!string.IsNullOrWhiteSpace(current))
            result.Add(Parse(current.Trim()));

        return result;
    }

    /// <summary>
    /// Extract return type from function type string like "void (const sapp_desc *)"
    /// </summary>
    public static Types ParseReturnType(string funcType)
    {
        var parenIdx = funcType.IndexOf('(');
        return parenIdx > 0 ? Parse(funcType[..parenIdx].Trim()) : new Types.Void();
    }
}
