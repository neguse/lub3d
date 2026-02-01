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
    bool IsDep, string? DepPrefix
) : Decl(IsDep, DepPrefix);

public record Funcs(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("type")] string TypeStr,
    [property: JsonPropertyName("params")] List<Param> Params,
    bool IsDep, string? DepPrefix
) : Decl(IsDep, DepPrefix);

public record Enums(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("items")] List<EnumItem> Items,
    bool IsDep, string? DepPrefix
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
