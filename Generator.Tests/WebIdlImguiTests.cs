using Generator;
using Generator.CBinding;
using Generator.LuaCats;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlImguiTests
{
    // ─── Step 1: Parser tests for optional/output params ───

    [Fact]
    public void Parse_OptionalParam()
    {
        var def = WebIdlParser.Parse("""
            namespace test {
                boolean show_demo_window(boolean? p_open);
            };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Single(op.Params);
        Assert.True(op.Params[0].IsOptional);
        Assert.Equal("boolean", op.Params[0].Type.Name);
        Assert.Equal("p_open", op.Params[0].Name);
    }

    [Fact]
    public void Parse_OutputParam()
    {
        var def = WebIdlParser.Parse("""
            namespace test {
                boolean begin_window(DOMString name, [Output] boolean? p_open, long? flags);
            };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Equal(3, op.Params.Count);

        // name: required, no ExtAttrs
        Assert.False(op.Params[0].IsOptional);
        Assert.Null(op.Params[0].ExtAttrs);

        // p_open: optional, [Output]
        Assert.True(op.Params[1].IsOptional);
        Assert.NotNull(op.Params[1].ExtAttrs);
        Assert.True(op.Params[1].ExtAttrs!.ContainsKey("Output"));

        // flags: optional, no ExtAttrs
        Assert.True(op.Params[2].IsOptional);
        Assert.Null(op.Params[2].ExtAttrs);
    }

    [Fact]
    public void Parse_FixedArrayParam()
    {
        var def = WebIdlParser.Parse("""
            namespace test {
                boolean color_edit4(DOMString label, [Output] float col[4], long? flags);
            };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Equal(3, op.Params.Count);

        // col: [Output], float[4]
        Assert.Equal("float", op.Params[1].Type.Name);
        Assert.Equal(4, op.Params[1].Type.ArrayLength);
        Assert.True(op.Params[1].ExtAttrs!.ContainsKey("Output"));

        // flags: optional
        Assert.True(op.Params[2].IsOptional);
    }

    [Fact]
    public void Parse_CppFuncExtAttr()
    {
        var def = WebIdlParser.Parse("""
            namespace test {
                [CppFunc="Begin"]
                boolean begin_window(DOMString name);
            };
            """);
        var op = def.Namespace!.Operations[0];
        Assert.Equal("begin_window", op.Name);
        Assert.Equal("Begin", op.ExtAttrs!["CppFunc"]);
    }

    [Fact]
    public void Parse_IsCppFileAttr()
    {
        var def = WebIdlParser.Parse("""
            [Prefix="", CInclude="imgui.h", IsCpp, CppNamespace="ImGui", EntryPoint="luaopen_imgui_gen"]
            namespace imgui {
                void end_window();
            };
            """);
        Assert.True(def.ExtAttrs.ContainsKey("IsCpp"));
        Assert.Equal("ImGui", def.ExtAttrs["CppNamespace"]);
        Assert.Equal("luaopen_imgui_gen", def.ExtAttrs["EntryPoint"]);
        Assert.Equal("", def.ExtAttrs["Prefix"]);
    }

    // ─── Step 2: Converter tests ───

    private const string ImguiMiniIdl = """
        [Prefix="", CInclude="imgui.h", IsCpp, CppNamespace="ImGui",
         EntryPoint="luaopen_imgui_gen", EnumPrefix="ImGui"]

        [ValueStruct]
        dictionary ImVec2 { float x; float y; };

        [ValueStruct]
        dictionary ImVec4 { float x; float y; float z; float w; };

        enum ImGuiWindowFlags_ {
            "ImGuiWindowFlags_None" = 0,
            "ImGuiWindowFlags_NoTitleBar" = 1,
            "ImGuiWindowFlags_NoResize" = 2
        };

        namespace imgui {
            boolean show_demo_window([Output] boolean? p_open);

            [CppFunc="Begin"]
            boolean begin_window(DOMString name, [Output] boolean? p_open, long? flags);

            [CppFunc="End"]
            void end_window();

            [CppFunc="BeginChild"]
            boolean begin_child_str_vec2_x_x(DOMString str_id, ImVec2? size,
                long? child_flags, long? window_flags);

            boolean color_edit4(DOMString label, [Output] float col[4], long? flags);
        };
        """;

    private static ModuleSpec BuildImguiSpec()
    {
        var def = WebIdlParser.ParseFile(ImguiMiniIdl);
        return WebIdlToSpec.Convert(def, "imgui");
    }

    [Fact]
    public void Convert_IsCpp()
    {
        var spec = BuildImguiSpec();
        Assert.True(spec.IsCpp);
    }

    [Fact]
    public void Convert_EntryPoint()
    {
        var spec = BuildImguiSpec();
        Assert.Equal("luaopen_imgui_gen", spec.EntryPoint);
    }

    [Fact]
    public void Convert_EmptyPrefix()
    {
        var spec = BuildImguiSpec();
        Assert.Equal("", spec.Prefix);
    }

    [Fact]
    public void Convert_CppNamespace()
    {
        var spec = BuildImguiSpec();
        // All functions should have CppNamespace set
        foreach (var f in spec.Funcs)
            Assert.Equal("ImGui", f.CppNamespace);
    }

    [Fact]
    public void Convert_CppFuncName_Explicit()
    {
        var spec = BuildImguiSpec();
        var beginWindow = spec.Funcs.First(f => f.LuaName == "begin_window");
        Assert.Equal("Begin", beginWindow.CppFuncName);
    }

    [Fact]
    public void Convert_CppFuncName_Auto()
    {
        var spec = BuildImguiSpec();
        // show_demo_window → auto ToPascalCase → ShowDemoWindow
        var showDemo = spec.Funcs.First(f => f.LuaName == "show_demo_window");
        Assert.Equal("ShowDemoWindow", showDemo.CppFuncName);
    }

    [Fact]
    public void Convert_OptionalParam()
    {
        var spec = BuildImguiSpec();
        var beginWindow = spec.Funcs.First(f => f.LuaName == "begin_window");
        Assert.False(beginWindow.Params[0].IsOptional); // name
        Assert.True(beginWindow.Params[1].IsOptional);  // p_open
        Assert.True(beginWindow.Params[2].IsOptional);  // flags
    }

    [Fact]
    public void Convert_OutputParam()
    {
        var spec = BuildImguiSpec();
        var beginWindow = spec.Funcs.First(f => f.LuaName == "begin_window");
        Assert.False(beginWindow.Params[0].IsOutput); // name
        Assert.True(beginWindow.Params[1].IsOutput);  // p_open
        Assert.False(beginWindow.Params[2].IsOutput); // flags
    }

    [Fact]
    public void Convert_FloatArrayOutput()
    {
        var spec = BuildImguiSpec();
        var colorEdit = spec.Funcs.First(f => f.LuaName == "color_edit4");
        Assert.True(colorEdit.Params[1].IsOutput);
        // [Output] float[N] → FloatArray(N) for C++ float array params
        Assert.IsType<BindingType.FloatArray>(colorEdit.Params[1].Type);
        var fa = (BindingType.FloatArray)colorEdit.Params[1].Type;
        Assert.Equal(4, fa.Length);
    }

    [Fact]
    public void Convert_ValueStruct_ImVec2()
    {
        var spec = BuildImguiSpec();
        var beginChild = spec.Funcs.First(f => f.LuaName == "begin_child_str_vec2_x_x");
        // ImVec2? → optional ValueStruct
        Assert.True(beginChild.Params[1].IsOptional);
        Assert.IsType<BindingType.ValueStruct>(beginChild.Params[1].Type);
    }

    [Fact]
    public void Convert_EnumWithEnumPrefix()
    {
        var spec = BuildImguiSpec();
        Assert.Single(spec.Enums);
        var e = spec.Enums[0];
        Assert.Equal("ImGuiWindowFlags_", e.CName);
        Assert.Equal("imgui.WindowFlags", e.LuaName);
        Assert.Equal("WindowFlags", e.FieldName);
    }

    [Fact]
    public void Convert_EnumItemNames()
    {
        var spec = BuildImguiSpec();
        var e = spec.Enums[0];
        Assert.Equal(3, e.Items.Count);
        Assert.Equal("NONE", e.Items[0].LuaName);
        Assert.Equal("NO_TITLE_BAR", e.Items[1].LuaName);
        Assert.Equal("NO_RESIZE", e.Items[2].LuaName);
    }

    // ─── E2E: CBindingGen output for C++ mode ───

    [Fact]
    public void E2E_CppBinding_CppNamespaceCall()
    {
        var code = CBindingGen.Generate(BuildImguiSpec());
        Assert.Contains("ImGui::ShowDemoWindow(", code);
        Assert.Contains("ImGui::Begin(", code);
        Assert.Contains("ImGui::End()", code);
    }

    [Fact]
    public void E2E_CppBinding_FuncTable()
    {
        var code = CBindingGen.Generate(BuildImguiSpec());
        Assert.Contains("{\"show_demo_window\",", code);
        Assert.Contains("{\"begin_window\",", code);
        Assert.Contains("{\"end_window\",", code);
    }

    [Fact]
    public void E2E_CppBinding_EntryPoint()
    {
        var code = CBindingGen.Generate(BuildImguiSpec());
        Assert.Contains("luaopen_imgui_gen", code);
    }

    [Fact]
    public void E2E_LuaCats_OptionalParam()
    {
        var lua = LuaCatsGen.Generate(BuildImguiSpec());
        Assert.Contains("p_open?:", lua);
        Assert.Contains("flags?:", lua);
    }

    [Fact]
    public void E2E_LuaCats_EnumField()
    {
        var lua = LuaCatsGen.Generate(BuildImguiSpec());
        Assert.Contains("imgui.WindowFlags", lua);
    }

    // ─── Step 3: Full IDL file parse + convert ───

    private static string FindIdlPath()
    {
        var dir = new System.IO.DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !System.IO.File.Exists(System.IO.Path.Combine(dir.FullName, "idl", "imgui.idl")))
            dir = dir.Parent;
        return System.IO.Path.Combine(dir!.FullName, "idl", "imgui.idl");
    }

    [Fact]
    public void FullIdl_Parses()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        Assert.NotNull(def.Namespace);
    }

    [Fact]
    public void FullIdl_FuncCount()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        Assert.Equal(299, def.Namespace!.Operations.Count);
    }

    [Fact]
    public void FullIdl_EnumCount()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        Assert.Equal(37, def.Enums.Count);
    }

    [Fact]
    public void FullIdl_Converts()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        var spec = WebIdlToSpec.Convert(def, "imgui");
        Assert.Equal("imgui", spec.ModuleName);
        Assert.True(spec.IsCpp);
        Assert.Equal("luaopen_imgui_gen", spec.EntryPoint);
        Assert.Equal(299, spec.Funcs.Count);
        Assert.Equal(37, spec.Enums.Count);
    }

    [Fact]
    public void FullIdl_LuaNames_Match()
    {
        // Compare lua names from IDL with the registry in gen/imgui_gen.cpp
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        var spec = WebIdlToSpec.Convert(def, "imgui");

        // Known lua names from the registry
        var expectedNames = new[]
        {
            "show_demo_window", "begin_window", "end_window",
            "begin_child_str_vec2_x_x", "begin_child_x_vec2_x_x",
            "color_edit4", "begin_table", "is_mouse_clicked",
            "get_clipboard_text", "debug_check_version_and_data_layout"
        };
        var luaNames = spec.Funcs.Select(f => f.LuaName).ToHashSet();
        foreach (var expected in expectedNames)
            Assert.Contains(expected, luaNames);
    }

    [Fact]
    public void FullIdl_CppBindingGenerates()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        var spec = WebIdlToSpec.Convert(def, "imgui");
        var code = CBindingGen.Generate(spec);
        Assert.Contains("ImGui::ShowDemoWindow(", code);
        Assert.Contains("ImGui::Begin(", code);
        Assert.Contains("luaopen_imgui_gen", code);
    }

    [Fact]
    public void FullIdl_LuaCatsGenerates()
    {
        var source = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(source);
        var spec = WebIdlToSpec.Convert(def, "imgui");
        var lua = LuaCatsGen.Generate(spec);
        Assert.Contains("---@meta", lua);
        Assert.Contains("imgui.WindowFlags", lua);
        Assert.Contains("show_demo_window", lua);
    }

    // ─── Step 4: E2E comparison with existing gen/ output ───

    private static HashSet<string> ExtractLuaNamesFromCpp(string cppCode)
    {
        var names = new HashSet<string>();
        foreach (System.Text.RegularExpressions.Match m in
            System.Text.RegularExpressions.Regex.Matches(cppCode, @"\{""(\w+)"",\s*l_\w+\}"))
        {
            names.Add(m.Groups[1].Value);
        }
        return names;
    }

    private static HashSet<string> ExtractEnumRegistersFromCpp(string cppCode)
    {
        var names = new HashSet<string>();
        foreach (System.Text.RegularExpressions.Match m in
            System.Text.RegularExpressions.Regex.Matches(cppCode, @"register_(\w+)\(L\)"))
        {
            names.Add(m.Groups[1].Value);
        }
        return names;
    }

    [Fact]
    public void E2E_LuaNames_ExactMatch()
    {
        // Read original gen/imgui_gen.cpp
        var dir = new System.IO.DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !System.IO.File.Exists(System.IO.Path.Combine(dir.FullName, "gen", "imgui_gen.cpp")))
            dir = dir.Parent;
        if (dir == null) return; // Skip if gen/ not available
        var origCpp = System.IO.File.ReadAllText(
            System.IO.Path.Combine(dir.FullName, "gen", "imgui_gen.cpp"));

        // Generate from IDL
        var idlSource = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(idlSource);
        var spec = WebIdlToSpec.Convert(def, "imgui");
        var newCpp = CBindingGen.Generate(spec);

        // Compare lua names in registry
        var origNames = ExtractLuaNamesFromCpp(origCpp);
        var newNames = ExtractLuaNamesFromCpp(newCpp);

        // All original names should be present
        var missing = origNames.Except(newNames).ToList();
        var extra = newNames.Except(origNames).ToList();

        Assert.Empty(missing);
        Assert.Empty(extra);
    }

    [Fact]
    public void E2E_EnumNames_ExactMatch()
    {
        var dir = new System.IO.DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !System.IO.File.Exists(System.IO.Path.Combine(dir.FullName, "gen", "imgui_gen.cpp")))
            dir = dir.Parent;
        if (dir == null) return;
        var origCpp = System.IO.File.ReadAllText(
            System.IO.Path.Combine(dir.FullName, "gen", "imgui_gen.cpp"));

        var idlSource = System.IO.File.ReadAllText(FindIdlPath());
        var def = WebIdlParser.ParseFile(idlSource);
        var spec = WebIdlToSpec.Convert(def, "imgui");
        var newCpp = CBindingGen.Generate(spec);

        var origEnums = ExtractEnumRegistersFromCpp(origCpp);
        var newEnums = ExtractEnumRegistersFromCpp(newCpp);

        var missing = origEnums.Except(newEnums).ToList();
        var extra = newEnums.Except(origEnums).ToList();

        Assert.Empty(missing);
        Assert.Empty(extra);
    }
}
