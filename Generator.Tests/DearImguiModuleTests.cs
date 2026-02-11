using Generator;
using Generator.ClangAst;
using Generator.Modules.Imgui;

namespace Generator.Tests;

public class DearImguiModuleTests
{
    private static readonly Dictionary<string, string> EmptyPrefixToModule = new();

    private static TypeRegistry MakeRegistry()
    {
        // Minimal C++ AST parse result simulating ImGui namespace
        var decls = new List<Decl>
        {
            // Functions in ImGui namespace
            new Funcs("Begin", "bool (const char *, bool *, int)",
                [new Param("name", "const char *"),
                 new Param("p_open", "bool *", HasDefault: true),
                 new Param("flags", "int", HasDefault: true)],
                false, null, 100, "ImGui"),
            new Funcs("End", "void ()", [], false, null, 110, "ImGui"),
            new Funcs("Text", "void (const char *, ...)",
                [new Param("fmt", "const char *")],
                false, null, 120, "ImGui"),
            new Funcs("Button", "bool (const char *, const ImVec2 &)",
                [new Param("label", "const char *"),
                 new Param("size", "const ImVec2 &", HasDefault: true)],
                false, null, 130, "ImGui"),
            new Funcs("SetCursorPos", "void (const ImVec2 &)",
                [new Param("local_pos", "const ImVec2 &")],
                false, null, 140, "ImGui"),
            new Funcs("GetCursorPos", "ImVec2 ()", [], false, null, 150, "ImGui"),
            new Funcs("ColorEdit4", "bool (const char *, float *)",
                [new Param("label", "const char *"),
                 new Param("col", "float *")],
                false, null, 160, "ImGui"),
            new Funcs("DragFloat2", "bool (const char *, float *, float, float, float, const char *, int)",
                [new Param("label", "const char *"),
                 new Param("v", "float *"),
                 new Param("v_speed", "float", HasDefault: true),
                 new Param("v_min", "float", HasDefault: true),
                 new Param("v_max", "float", HasDefault: true),
                 new Param("format", "const char *", HasDefault: true),
                 new Param("flags", "int", HasDefault: true)],
                false, null, 170, "ImGui"),
            new Funcs("SliderFloat", "bool (const char *, float *, float, float, const char *, int)",
                [new Param("label", "const char *"),
                 new Param("v", "float *"),
                 new Param("v_min", "float"),
                 new Param("v_max", "float"),
                 new Param("format", "const char *", HasDefault: true),
                 new Param("flags", "int", HasDefault: true)],
                false, null, 180, "ImGui"),
            // Vararg function — should be skipped
            new Funcs("TextColored", "void (const ImVec4 &, const char *, ...)",
                [new Param("col", "const ImVec4 &"),
                 new Param("fmt", "const char *")],
                false, null, 190, "ImGui"),
            // Overloaded functions — PushID
            new Funcs("PushID", "void (const char *)",
                [new Param("str_id", "const char *")],
                false, null, 200, "ImGui"),
            new Funcs("PushID", "void (int)",
                [new Param("int_id", "int")],
                false, null, 210, "ImGui"),
            // GetStyleColorVec4 — returns ImVec4
            new Funcs("GetStyleColorVec4", "const ImVec4 & (int)",
                [new Param("idx", "int")],
                false, null, 220, "ImGui"),
            // Checkbox — bool output param
            new Funcs("Checkbox", "bool (const char *, bool *)",
                [new Param("label", "const char *"),
                 new Param("v", "bool *")],
                false, null, 230, "ImGui"),
            // SliderInt — int output param
            new Funcs("SliderInt", "bool (const char *, int *, int, int, const char *, int)",
                [new Param("label", "const char *"),
                 new Param("v", "int *"),
                 new Param("v_min", "int"),
                 new Param("v_max", "int"),
                 new Param("format", "const char *", HasDefault: true),
                 new Param("flags", "int", HasDefault: true)],
                false, null, 240, "ImGui"),
            // Internal function — should be skipped (starts with Internal)
            // Actually handled by skip list, not prefix; skip GetIO instead
            new Funcs("GetIO", "ImGuiIO & ()", [], false, null, 250, "ImGui"),

            // Enums
            new Enums("ImGuiWindowFlags_",
                [new EnumItem("ImGuiWindowFlags_None", "0"),
                 new EnumItem("ImGuiWindowFlags_NoTitleBar", "1"),
                 new EnumItem("ImGuiWindowFlags_NoResize", "2")],
                false, null, 50),
            new Enums("ImGuiCol_",
                [new EnumItem("ImGuiCol_Text", "0"),
                 new EnumItem("ImGuiCol_WindowBg", "2")],
                false, null, 60),
        };

        return TypeRegistry.FromModule(new Module("imgui", "", [], decls));
    }

    [Fact]
    public void BuildSpec_IsCppTrue()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.True(spec.IsCpp);
    }

    [Fact]
    public void BuildSpec_EntryPoint()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.Equal("luaopen_imgui_gen", spec.EntryPoint);
    }

    [Fact]
    public void BuildSpec_StructsEmpty()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.Empty(spec.Structs);
    }

    [Fact]
    public void BuildSpec_ContainsBegin()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.Contains(spec.Funcs, f => f.CName == "Begin" && f.CppNamespace == "ImGui");
    }

    [Fact]
    public void BuildSpec_SkipsVarargs()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        // TextColored has varargs → skipped (Text does too but should be in skip list or handled)
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "TextColored");
    }

    [Fact]
    public void BuildSpec_SkipsGetIO()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "GetIO");
    }

    [Fact]
    public void BuildSpec_OverloadSuffix()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var pushIds = spec.Funcs.Where(f => f.LuaName.StartsWith("PushID")).ToList();
        Assert.Equal(2, pushIds.Count);
        Assert.True(pushIds[0].LuaName != pushIds[1].LuaName,
            "Overloaded PushID should have different Lua names");
    }

    [Fact]
    public void BuildSpec_Vec2Required()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var setCursor = spec.Funcs.First(f => f.CName == "SetCursorPos");
        Assert.IsType<BindingType.Vec2>(setCursor.Params[0].Type);
        Assert.False(setCursor.Params[0].IsOptional);
    }

    [Fact]
    public void BuildSpec_Vec2Optional()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var button = spec.Funcs.First(f => f.CName == "Button");
        Assert.IsType<BindingType.Vec2>(button.Params[1].Type);
        Assert.True(button.Params[1].IsOptional);
    }

    [Fact]
    public void BuildSpec_Vec2Return()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var getCursor = spec.Funcs.First(f => f.CName == "GetCursorPos");
        Assert.IsType<BindingType.Vec2>(getCursor.ReturnType);
    }

    [Fact]
    public void BuildSpec_Vec4Return()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var getStyle = spec.Funcs.First(f => f.CName == "GetStyleColorVec4");
        Assert.IsType<BindingType.Vec4>(getStyle.ReturnType);
    }

    [Fact]
    public void BuildSpec_FloatArrayHeuristic()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var colorEdit = spec.Funcs.First(f => f.CName == "ColorEdit4");
        // col param should be FloatArray(4)
        Assert.IsType<BindingType.FloatArray>(colorEdit.Params[1].Type);
        Assert.Equal(4, ((BindingType.FloatArray)colorEdit.Params[1].Type).Length);
    }

    [Fact]
    public void BuildSpec_FloatArrayOutput()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var colorEdit = spec.Funcs.First(f => f.CName == "ColorEdit4");
        Assert.True(colorEdit.Params[1].IsOutput);
    }

    [Fact]
    public void BuildSpec_DragFloatArray()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var drag = spec.Funcs.First(f => f.CName == "DragFloat2");
        // v param should be FloatArray(2)
        Assert.IsType<BindingType.FloatArray>(drag.Params[1].Type);
        Assert.Equal(2, ((BindingType.FloatArray)drag.Params[1].Type).Length);
    }

    [Fact]
    public void BuildSpec_OutputBoolParam()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var checkbox = spec.Funcs.First(f => f.CName == "Checkbox");
        Assert.True(checkbox.Params[1].IsOutput);
        Assert.IsType<BindingType.Bool>(checkbox.Params[1].Type);
    }

    [Fact]
    public void BuildSpec_OutputIntParam()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var slider = spec.Funcs.First(f => f.CName == "SliderInt");
        Assert.True(slider.Params[1].IsOutput);
        Assert.IsType<BindingType.Int>(slider.Params[1].Type);
    }

    [Fact]
    public void BuildSpec_IsOptionalScalar()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var begin = spec.Funcs.First(f => f.CName == "Begin");
        // flags has HasDefault → IsOptional
        var flagsParam = begin.Params.First(p => p.Name == "flags");
        Assert.True(flagsParam.IsOptional);
    }

    [Fact]
    public void BuildSpec_EnumPrefixStripping()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var winFlags = spec.Enums.First(e => e.CName == "ImGuiWindowFlags_");
        Assert.Equal("WindowFlags", winFlags.FieldName);
        Assert.Contains(winFlags.Items, i => i.LuaName == "None");
        Assert.Contains(winFlags.Items, i => i.LuaName == "NoTitleBar");
    }

    [Fact]
    public void BuildSpec_EnumCName()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        Assert.Contains(spec.Enums, e => e.CName == "ImGuiCol_");
    }

    [Fact]
    public void BuildSpec_SliderFloatOutputParam()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        var slider = spec.Funcs.First(f => f.CName == "SliderFloat");
        // v is float* → output float param
        Assert.True(slider.Params[1].IsOutput);
        Assert.IsType<BindingType.Float>(slider.Params[1].Type);
    }

    // ===== GenerateC / GenerateLua =====

    [Fact]
    public void GenerateC_ContainsImGuiNamespace()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateC(MakeRegistry(), EmptyPrefixToModule);
        Assert.Contains("ImGui::Begin(", code);
        Assert.Contains("ImGui::End()", code);
    }

    [Fact]
    public void GenerateC_ContainsExternC()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateC(MakeRegistry(), EmptyPrefixToModule);
        Assert.Contains("extern \"C\"", code);
        Assert.Contains("luaopen_imgui_gen", code);
    }

    [Fact]
    public void GenerateLua_ContainsModule()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateLua(MakeRegistry(), EmptyPrefixToModule);
        Assert.Contains("---@meta", code);
        Assert.Contains("---@class imgui", code);
    }

    [Fact]
    public void GenerateLua_ContainsFuncs()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateLua(MakeRegistry(), EmptyPrefixToModule);
        Assert.Contains("Begin", code);
        Assert.Contains("End", code);
    }

    [Fact]
    public void GenerateLua_ContainsEnums()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateLua(MakeRegistry(), EmptyPrefixToModule);
        Assert.Contains("WindowFlags", code);
    }

    [Fact]
    public void BuildSpec_TextSkippedAsVararg()
    {
        var mod = new ImguiModule();
        var spec = mod.BuildSpec(MakeRegistry());
        // Text has varargs "void (const char *, ...)" → should be skipped
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "Text");
    }

    // ===== Smoke tests: GenerateC / GenerateLua produce non-trivial output =====

    [Fact]
    public void GenerateC_NonEmpty()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateC(MakeRegistry(), EmptyPrefixToModule);
        Assert.NotEmpty(code);
        Assert.True(code.Length > 100, $"Expected substantial C++ output, got {code.Length} chars");
    }

    [Fact]
    public void GenerateLua_NonEmpty()
    {
        var mod = new ImguiModule();
        var code = mod.GenerateLua(MakeRegistry(), EmptyPrefixToModule);
        Assert.NotEmpty(code);
        Assert.True(code.Length > 100, $"Expected substantial LuaCATS output, got {code.Length} chars");
    }
}
