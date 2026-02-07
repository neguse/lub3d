using Generator.ClangAst;

namespace Generator.Tests;

public class CppAstParseTests
{
    // Minimal C++ AST JSON with namespace, default args, enum
    private const string CppAstJson = """
    {
      "id": "0x1",
      "kind": "TranslationUnitDecl",
      "inner": [
        {
          "id": "0x10",
          "kind": "NamespaceDecl",
          "name": "ImGui",
          "inner": [
            {
              "id": "0x11",
              "kind": "FunctionDecl",
              "name": "Begin",
              "type": { "qualType": "bool (const char *, bool *, int)" },
              "loc": { "line": 100 },
              "inner": [
                {
                  "kind": "ParmVarDecl",
                  "name": "name",
                  "type": { "qualType": "const char *" }
                },
                {
                  "kind": "ParmVarDecl",
                  "name": "p_open",
                  "type": { "qualType": "bool *" },
                  "inner": [
                    { "kind": "CXXDefaultArgExpr" }
                  ]
                },
                {
                  "kind": "ParmVarDecl",
                  "name": "flags",
                  "type": { "qualType": "int" },
                  "inner": [
                    { "kind": "IntegerLiteral", "value": "0" }
                  ]
                }
              ]
            },
            {
              "id": "0x12",
              "kind": "FunctionDecl",
              "name": "End",
              "type": { "qualType": "void ()" },
              "loc": { "line": 110 }
            },
            {
              "id": "0x13",
              "kind": "FunctionDecl",
              "name": "Text",
              "type": { "qualType": "void (const char *, ...)" },
              "loc": { "line": 120 },
              "inner": [
                {
                  "kind": "ParmVarDecl",
                  "name": "fmt",
                  "type": { "qualType": "const char *" }
                }
              ]
            }
          ]
        },
        {
          "id": "0x20",
          "kind": "EnumDecl",
          "name": "ImGuiWindowFlags_",
          "loc": { "line": 50 },
          "inner": [
            { "kind": "EnumConstantDecl", "name": "ImGuiWindowFlags_None", "inner": [{ "kind": "ConstantExpr", "value": "0" }] },
            { "kind": "EnumConstantDecl", "name": "ImGuiWindowFlags_NoTitleBar", "inner": [{ "kind": "ConstantExpr", "value": "1" }] }
          ]
        },
        {
          "id": "0x30",
          "kind": "FunctionDecl",
          "name": "some_global_func",
          "type": { "qualType": "void ()" },
          "loc": { "line": 200 }
        }
      ]
    }
    """;

    [Fact]
    public void ParseCpp_ExtractsNamespaceFunctions()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var funcs = module.Decls.OfType<Funcs>().ToList();
        Assert.Contains(funcs, f => f.Name == "Begin" && f.Namespace == "ImGui");
        Assert.Contains(funcs, f => f.Name == "End" && f.Namespace == "ImGui");
        Assert.Contains(funcs, f => f.Name == "Text" && f.Namespace == "ImGui");
    }

    [Fact]
    public void ParseCpp_FunctionsAreNotDep()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var funcs = module.Decls.OfType<Funcs>().Where(f => f.Namespace == "ImGui").ToList();
        Assert.All(funcs, f => Assert.False(f.IsDep));
    }

    [Fact]
    public void ParseCpp_DetectsDefaultArgs()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var begin = module.Decls.OfType<Funcs>().First(f => f.Name == "Begin");
        // name has no default
        Assert.False(begin.Params[0].HasDefault);
        // p_open has CXXDefaultArgExpr
        Assert.True(begin.Params[1].HasDefault);
        // flags has IntegerLiteral
        Assert.True(begin.Params[2].HasDefault);
    }

    [Fact]
    public void ParseCpp_ExtractsEnums()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var enums = module.Decls.OfType<Enums>().ToList();
        Assert.Single(enums);
        Assert.Equal("ImGuiWindowFlags_", enums[0].Name);
    }

    [Fact]
    public void ParseCpp_IgnoresGlobalFuncsNotInNamespace()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var funcs = module.Decls.OfType<Funcs>().ToList();
        Assert.DoesNotContain(funcs, f => f.Name == "some_global_func");
    }

    [Fact]
    public void ParseCpp_PreservesLine()
    {
        var module = ClangRunner.ParseCppAstJson(CppAstJson, ["ImGui"]);
        var begin = module.Decls.OfType<Funcs>().First(f => f.Name == "Begin");
        Assert.Equal(100, begin.Line);
    }

    // ===== Default value detection edge cases =====

    private const string DefaultValueJson = """
    {
      "id": "0x1",
      "kind": "TranslationUnitDecl",
      "inner": [
        {
          "id": "0x10",
          "kind": "NamespaceDecl",
          "name": "ImGui",
          "inner": [
            {
              "id": "0x11",
              "kind": "FunctionDecl",
              "name": "SetNextWindowPos",
              "type": { "qualType": "void (const ImVec2 &, int, const ImVec2 &)" },
              "inner": [
                {
                  "kind": "ParmVarDecl",
                  "name": "pos",
                  "type": { "qualType": "const ImVec2 &" }
                },
                {
                  "kind": "ParmVarDecl",
                  "name": "cond",
                  "type": { "qualType": "int" },
                  "inner": [
                    { "kind": "ImplicitCastExpr", "inner": [{ "kind": "IntegerLiteral", "value": "0" }] }
                  ]
                },
                {
                  "kind": "ParmVarDecl",
                  "name": "pivot",
                  "type": { "qualType": "const ImVec2 &" },
                  "inner": [
                    { "kind": "CXXConstructExpr" }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """;

    [Fact]
    public void ParseCpp_ImplicitCastExpr_DetectsDefault()
    {
        var module = ClangRunner.ParseCppAstJson(DefaultValueJson, ["ImGui"]);
        var func = module.Decls.OfType<Funcs>().First();
        // cond has ImplicitCastExpr with IntegerLiteral
        Assert.True(func.Params[1].HasDefault);
    }

    [Fact]
    public void ParseCpp_CXXConstructExpr_DetectsDefault()
    {
        var module = ClangRunner.ParseCppAstJson(DefaultValueJson, ["ImGui"]);
        var func = module.Decls.OfType<Funcs>().First();
        // pivot has CXXConstructExpr
        Assert.True(func.Params[2].HasDefault);
    }

    [Fact]
    public void ParseCpp_NoDefault_FalseForRequired()
    {
        var module = ClangRunner.ParseCppAstJson(DefaultValueJson, ["ImGui"]);
        var func = module.Decls.OfType<Funcs>().First();
        // pos has no default
        Assert.False(func.Params[0].HasDefault);
    }

    // ===== StringLiteral default detection =====

    private const string StringDefaultJson = """
    {
      "id": "0x1",
      "kind": "TranslationUnitDecl",
      "inner": [
        {
          "id": "0x10",
          "kind": "NamespaceDecl",
          "name": "ImGui",
          "inner": [
            {
              "id": "0x11",
              "kind": "FunctionDecl",
              "name": "SliderFloat",
              "type": { "qualType": "bool (const char *, float *, float, float, const char *, int)" },
              "inner": [
                { "kind": "ParmVarDecl", "name": "label", "type": { "qualType": "const char *" } },
                { "kind": "ParmVarDecl", "name": "v", "type": { "qualType": "float *" } },
                { "kind": "ParmVarDecl", "name": "v_min", "type": { "qualType": "float" } },
                { "kind": "ParmVarDecl", "name": "v_max", "type": { "qualType": "float" } },
                {
                  "kind": "ParmVarDecl", "name": "format", "type": { "qualType": "const char *" },
                  "init": "c",
                  "inner": [
                    { "kind": "ImplicitCastExpr", "inner": [
                      { "kind": "StringLiteral", "value": "\"%.3f\"" }
                    ] }
                  ]
                },
                {
                  "kind": "ParmVarDecl", "name": "flags", "type": { "qualType": "int" },
                  "init": "c",
                  "inner": [
                    { "kind": "IntegerLiteral", "value": "0" }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """;

    [Fact]
    public void ParseCpp_StringLiteral_DetectsDefault()
    {
        var module = ClangRunner.ParseCppAstJson(StringDefaultJson, ["ImGui"]);
        var func = module.Decls.OfType<Funcs>().First(f => f.Name == "SliderFloat");
        // format has StringLiteral inside ImplicitCastExpr
        Assert.True(func.Params[4].HasDefault);
    }

    [Fact]
    public void ParseCpp_InitProperty_DetectsDefault()
    {
        var module = ClangRunner.ParseCppAstJson(StringDefaultJson, ["ImGui"]);
        var func = module.Decls.OfType<Funcs>().First(f => f.Name == "SliderFloat");
        // flags has "init" property
        Assert.True(func.Params[5].HasDefault);
        // label has no "init" property and no default
        Assert.False(func.Params[0].HasDefault);
    }
}
