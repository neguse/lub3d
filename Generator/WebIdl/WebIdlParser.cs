namespace Generator.WebIdl;

/// <summary>
/// WebIDL サブセットの再帰下降パーサ。
/// namespace, enum, dictionary をサポート。
/// </summary>
public static class WebIdlParser
{
    private enum TokenKind { Identifier, StringLiteral, Number, Punctuation, Eof }

    private record Token(TokenKind Kind, string Value, int Line);

    /// <summary>
    /// PoC 互換 — 単一 namespace 定義のみ含むソースをパースする。
    /// </summary>
    public static IdlFile Parse(string source)
    {
        return ParseFile(source);
    }

    /// <summary>
    /// IDL ファイル全体をパースする。
    /// </summary>
    public static IdlFile ParseFile(string source)
    {
        var tokens = Tokenize(source);
        var cursor = 0;

        var extAttrs = new Dictionary<string, string>();
        IdlNamespace? ns = null;
        var enums = new List<IdlEnum>();
        var dicts = new List<IdlDictionary>();
        var interfaces = new List<IdlInterface>();
        var callbacks = new List<IdlCallback>();
        var eventAdapters = new List<IdlEventAdapter>();

        // ファイル先頭の拡張属性
        if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
            extAttrs = ParseExtAttrs(tokens, ref cursor);

        // 複数定義をパース
        while (Peek(tokens, cursor).Kind != TokenKind.Eof)
        {
            // 定義ごとの拡張属性
            Dictionary<string, string>? defAttrs = null;
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
                defAttrs = ParseExtAttrs(tokens, ref cursor);

            var tok = Peek(tokens, cursor);

            if (tok.Kind != TokenKind.Identifier)
                throw new FormatException(
                    $"Line {tok.Line}: expected 'namespace', 'enum', 'dictionary', 'interface', 'callback', or 'event', got {tok.Kind} '{tok.Value}'");

            switch (tok.Value)
            {
                case "namespace":
                    if (ns != null)
                        throw new FormatException($"Line {tok.Line}: multiple namespaces in one file");
                    ns = ParseNamespace(tokens, ref cursor);
                    break;
                case "enum":
                    enums.Add(ParseEnum(tokens, ref cursor, defAttrs));
                    break;
                case "dictionary":
                    dicts.Add(ParseDictionary(tokens, ref cursor, defAttrs));
                    break;
                case "interface":
                    interfaces.Add(ParseInterface(tokens, ref cursor, defAttrs));
                    break;
                case "callback":
                    callbacks.Add(ParseCallback(tokens, ref cursor, defAttrs));
                    break;
                case "event":
                    eventAdapters.Add(ParseEventAdapter(tokens, ref cursor, defAttrs));
                    break;
                default:
                    throw new FormatException(
                        $"Line {tok.Line}: expected 'namespace', 'enum', 'dictionary', 'interface', 'callback', or 'event', got '{tok.Value}'");
            }
        }

        return new IdlFile(extAttrs, ns, enums, dicts, interfaces, callbacks, eventAdapters);
    }

    // ─── Tokenizer ───

    private static List<Token> Tokenize(string source)
    {
        var tokens = new List<Token>();
        var i = 0;
        var line = 1;

        while (i < source.Length)
        {
            var ch = source[i];

            // newline
            if (ch == '\n') { line++; i++; continue; }

            // whitespace
            if (char.IsWhiteSpace(ch)) { i++; continue; }

            // line comment
            if (i + 1 < source.Length && ch == '/' && source[i + 1] == '/')
            {
                while (i < source.Length && source[i] != '\n') i++;
                continue;
            }

            // string literal
            if (ch == '"')
            {
                var start = ++i;
                while (i < source.Length && source[i] != '"')
                {
                    if (source[i] == '\n') line++;
                    i++;
                }
                if (i >= source.Length)
                    throw new FormatException($"Line {line}: unterminated string literal");
                tokens.Add(new Token(TokenKind.StringLiteral, source[start..i], line));
                i++; // skip closing "
                continue;
            }

            // number (integer, possibly negative)
            if (char.IsDigit(ch) || (ch == '-' && i + 1 < source.Length && char.IsDigit(source[i + 1])))
            {
                var start = i;
                if (ch == '-') i++;
                while (i < source.Length && char.IsDigit(source[i])) i++;
                tokens.Add(new Token(TokenKind.Number, source[start..i], line));
                continue;
            }

            // punctuation
            if ("[]{}();,=:".Contains(ch))
            {
                tokens.Add(new Token(TokenKind.Punctuation, ch.ToString(), line));
                i++;
                continue;
            }

            // identifier / keyword
            if (char.IsLetter(ch) || ch == '_')
            {
                var start = i;
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_'))
                    i++;
                tokens.Add(new Token(TokenKind.Identifier, source[start..i], line));
                continue;
            }

            throw new FormatException($"Line {line}: unexpected character '{ch}'");
        }

        tokens.Add(new Token(TokenKind.Eof, "", line));
        return tokens;
    }

    // ─── Parser helpers ───

    private static Token Peek(List<Token> tokens, int cursor)
        => cursor < tokens.Count ? tokens[cursor] : tokens[^1];

    private static Token Expect(List<Token> tokens, ref int cursor, TokenKind kind, string? value = null)
    {
        var tok = Peek(tokens, cursor);
        if (tok.Kind != kind || (value != null && tok.Value != value))
            throw new FormatException(
                $"Line {tok.Line}: expected {kind}{(value != null ? $" '{value}'" : "")}, got {tok.Kind} '{tok.Value}'");
        cursor++;
        return tok;
    }

    private static bool TryConsume(List<Token> tokens, ref int cursor, TokenKind kind, string value)
    {
        var tok = Peek(tokens, cursor);
        if (tok.Kind == kind && tok.Value == value)
        {
            cursor++;
            return true;
        }
        return false;
    }

    // ─── Grammar ───

    // Namespace = "namespace" Ident "{" Operation* "}" ";"
    private static IdlNamespace ParseNamespace(List<Token> tokens, ref int cursor)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "namespace");
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

        var operations = new List<IdlOperation>();
        while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
        {
            Dictionary<string, string>? opAttrs = null;
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
                opAttrs = ParseExtAttrs(tokens, ref cursor);
            operations.Add(ParseOperation(tokens, ref cursor, opAttrs));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlNamespace(name, operations);
    }

    // Enum = "enum" Ident "{" EnumValues "}" ";"
    // EnumValues = StringLit "=" IntLit ("," StringLit "=" IntLit)* ","?
    private static IdlEnum ParseEnum(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "enum");
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

        var values = new List<IdlEnumValue>();
        while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
        {
            var itemName = Expect(tokens, ref cursor, TokenKind.StringLiteral).Value;
            Expect(tokens, ref cursor, TokenKind.Punctuation, "=");
            var itemValue = int.Parse(Expect(tokens, ref cursor, TokenKind.Number).Value);
            values.Add(new IdlEnumValue(itemName, itemValue));

            // trailing comma
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "," })
                cursor++;
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlEnum(name, values, extAttrs);
    }

    // Dictionary = "dictionary" Ident "{" Field* "}" ";"
    // Field = Type Ident ";"
    private static IdlDictionary ParseDictionary(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "dictionary");
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

        var fields = new List<IdlField>();
        while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
        {
            // per-field ExtAttrs (e.g. [Ignore])
            Dictionary<string, string>? fieldAttrs = null;
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
                fieldAttrs = ParseExtAttrs(tokens, ref cursor);
            var fieldType = ParseType(tokens, ref cursor);
            var fieldName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
            // FixedArray: "type name[N];"
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
            {
                cursor++; // skip "["
                var arrayLen = int.Parse(Expect(tokens, ref cursor, TokenKind.Number).Value);
                Expect(tokens, ref cursor, TokenKind.Punctuation, "]");
                fieldType = fieldType with { ArrayLength = arrayLen };
            }
            Expect(tokens, ref cursor, TokenKind.Punctuation, ";");
            fields.Add(new IdlField(fieldName, fieldType, fieldAttrs));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlDictionary(name, fields, extAttrs);
    }

    // Interface = "interface" Ident "{" Method* "}" ";"
    // Method = ExtAttrs? Type Ident "(" ParamList? ")" ";"
    private static IdlInterface ParseInterface(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "interface");
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

        var methods = new List<IdlMethod>();
        while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
        {
            Dictionary<string, string>? methodAttrs = null;
            if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
                methodAttrs = ParseExtAttrs(tokens, ref cursor);
            methods.Add(ParseMethod(tokens, ref cursor, methodAttrs));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlInterface(name, methods, extAttrs);
    }

    // Method = Type Ident "(" ParamList? ")" ";"
    // Same syntax as Operation but stored as IdlMethod
    private static IdlMethod ParseMethod(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        var retType = ParseType(tokens, ref cursor);
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "(");

        var parms = new List<IdlParam>();
        if (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: ")" })
        {
            do
            {
                var pType = ParseType(tokens, ref cursor);
                var pName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                parms.Add(new IdlParam(pName, pType));
            } while (TryConsume(tokens, ref cursor, TokenKind.Punctuation, ","));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, ")");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlMethod(name, retType, parms, extAttrs);
    }

    // Callback = "callback" Ident "=" Type "(" ParamList? ")" ";"
    private static IdlCallback ParseCallback(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "callback");
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "=");
        var retType = ParseType(tokens, ref cursor);
        Expect(tokens, ref cursor, TokenKind.Punctuation, "(");

        var parms = new List<IdlParam>();
        if (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: ")" })
        {
            do
            {
                var pType = ParseType(tokens, ref cursor);
                var pName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                parms.Add(new IdlParam(pName, pType));
            } while (TryConsume(tokens, ref cursor, TokenKind.Punctuation, ","));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, ")");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlCallback(name, parms, retType, extAttrs);
    }

    // EventAdapter = "event" Ident "(" ParamList ")" ":" Ident "{" EventArray* "}" ";"
    // EventArray   = Ident "(" Ident "," Ident ")" "{" EventField* "}" ";"
    // EventField   = Type Ident "=" Ident ";"
    private static IdlEventAdapter ParseEventAdapter(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        Expect(tokens, ref cursor, TokenKind.Identifier, "event");
        var luaName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        var cFunc = extAttrs?.GetValueOrDefault("CFunc", null);
        Expect(tokens, ref cursor, TokenKind.Punctuation, "(");

        var parms = new List<IdlParam>();
        if (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: ")" })
        {
            do
            {
                var pType = ParseType(tokens, ref cursor);
                var pName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                parms.Add(new IdlParam(pName, pType));
            } while (TryConsume(tokens, ref cursor, TokenKind.Punctuation, ","));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, ")");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ":");
        var cReturnType = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

        var arrays = new List<IdlEventArrayDef>();
        while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
        {
            var arrayLuaName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
            Expect(tokens, ref cursor, TokenKind.Punctuation, "(");
            var cArrayAccessor = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
            Expect(tokens, ref cursor, TokenKind.Punctuation, ",");
            var cCountAccessor = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
            Expect(tokens, ref cursor, TokenKind.Punctuation, ")");
            Expect(tokens, ref cursor, TokenKind.Punctuation, "{");

            var fields = new List<IdlEventFieldDef>();
            while (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: "}" })
            {
                var fieldType = ParseType(tokens, ref cursor);
                var fieldLuaName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                Expect(tokens, ref cursor, TokenKind.Punctuation, "=");
                var fieldCAccessor = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                Expect(tokens, ref cursor, TokenKind.Punctuation, ";");
                fields.Add(new IdlEventFieldDef(fieldLuaName, fieldCAccessor, fieldType));
            }

            Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
            Expect(tokens, ref cursor, TokenKind.Punctuation, ";");
            arrays.Add(new IdlEventArrayDef(arrayLuaName, cArrayAccessor, cCountAccessor, fields));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, "}");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlEventAdapter(luaName, cReturnType, parms, arrays, cFunc);
    }

    // ExtAttrList = "[" ExtAttr ("," ExtAttr)* "]"
    // ExtAttr     = Ident ("=" StringLit)?
    private static Dictionary<string, string> ParseExtAttrs(List<Token> tokens, ref int cursor)
    {
        Expect(tokens, ref cursor, TokenKind.Punctuation, "[");
        var attrs = new Dictionary<string, string>();

        do
        {
            var key = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
            if (TryConsume(tokens, ref cursor, TokenKind.Punctuation, "="))
            {
                var val = Expect(tokens, ref cursor, TokenKind.StringLiteral).Value;
                attrs[key] = val;
            }
            else
            {
                // flag 属性 (e.g. [Ignore], [HasMetamethods])
                attrs[key] = "";
            }
        } while (TryConsume(tokens, ref cursor, TokenKind.Punctuation, ","));

        Expect(tokens, ref cursor, TokenKind.Punctuation, "]");
        return attrs;
    }

    // Operation = ExtAttrs? Type Ident "(" ParamList? ")" ";"
    private static IdlOperation ParseOperation(List<Token> tokens, ref int cursor,
        Dictionary<string, string>? extAttrs = null)
    {
        var retType = ParseType(tokens, ref cursor);
        var name = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
        Expect(tokens, ref cursor, TokenKind.Punctuation, "(");

        var parms = new List<IdlParam>();
        if (Peek(tokens, cursor) is not { Kind: TokenKind.Punctuation, Value: ")" })
        {
            do
            {
                var pType = ParseType(tokens, ref cursor);
                var pName = Expect(tokens, ref cursor, TokenKind.Identifier).Value;
                parms.Add(new IdlParam(pName, pType));
            } while (TryConsume(tokens, ref cursor, TokenKind.Punctuation, ","));
        }

        Expect(tokens, ref cursor, TokenKind.Punctuation, ")");
        Expect(tokens, ref cursor, TokenKind.Punctuation, ";");

        return new IdlOperation(name, retType, parms, extAttrs);
    }

    // Type = PrimitiveType | Ident (struct/enum reference)
    // 型の後に [N] があれば FixedArray
    private static IdlType ParseType(List<Token> tokens, ref int cursor)
    {
        var tok = Expect(tokens, ref cursor, TokenKind.Identifier);

        var baseType = tok.Value switch
        {
            "void" or "double" or "float" or "boolean" or "DOMString"
                or "byte" or "octet" => new IdlType(tok.Value),

            "short" => new IdlType("short"),

            "long" => Peek(tokens, cursor) is { Kind: TokenKind.Identifier, Value: "long" }
                ? (cursor++, new IdlType("long long")).Item2
                : new IdlType("long"),

            "unsigned" => ParseUnsignedType(tokens, ref cursor),

            // Any other identifier is a type reference (struct, enum, Callback, etc.)
            _ => new IdlType(tok.Value)
        };

        // FixedArray suffix: [N]
        if (Peek(tokens, cursor) is { Kind: TokenKind.Punctuation, Value: "[" })
        {
            cursor++; // skip [
            var length = int.Parse(Expect(tokens, ref cursor, TokenKind.Number).Value);
            Expect(tokens, ref cursor, TokenKind.Punctuation, "]");
            return baseType with { ArrayLength = length };
        }

        return baseType;
    }

    private static IdlType ParseUnsignedType(List<Token> tokens, ref int cursor)
    {
        var next = Expect(tokens, ref cursor, TokenKind.Identifier);
        return next.Value switch
        {
            "short" => new IdlType("unsigned short"),
            "long" => Peek(tokens, cursor) is { Kind: TokenKind.Identifier, Value: "long" }
                ? (cursor++, new IdlType("unsigned long long")).Item2
                : new IdlType("unsigned long"),
            _ => throw new FormatException(
                $"Line {next.Line}: expected 'short' or 'long' after 'unsigned', got '{next.Value}'")
        };
    }
}
