using Generator;
using Generator.CBinding;

namespace Generator.Tests;

public class CppModeGenTests
{
    private static ModuleSpec CppSpec() => new(
        "imgui", "",
        ["imgui.h"],
        null,
        [], // Structs = empty (no struct gen for C++ ImGui)
        [
            new FuncBinding("Begin", "Begin",
                [new ParamBinding("name", new BindingType.Str()),
                 new ParamBinding("p_open", new BindingType.Bool(), IsOptional: false, IsOutput: true),
                 new ParamBinding("flags", new BindingType.Int(), IsOptional: true)],
                new BindingType.Bool(), null, CppNamespace: "ImGui"),
            new FuncBinding("End", "End", [], new BindingType.Void(), null, CppNamespace: "ImGui"),
            new FuncBinding("Text", "Text",
                [new ParamBinding("text", new BindingType.Str())],
                new BindingType.Void(), null, CppNamespace: "ImGui"),
        ],
        [new EnumBinding("ImGuiWindowFlags_", "imgui.WindowFlags", "WindowFlags",
            [new EnumItemBinding("None", "ImGuiWindowFlags_None", 0),
             new EnumItemBinding("NoTitleBar", "ImGuiWindowFlags_NoTitleBar", 1)],
            null)],
        [],
        IsCpp: true,
        EntryPoint: "luaopen_imgui_gen");

    // ===== Header / includes =====

    [Fact]
    public void CppMode_ImguiIncludeOutsideExternC()
    {
        var code = CBindingGen.Generate(CppSpec());
        // imgui.h should be included
        Assert.Contains("#include \"imgui.h\"", code);
        // Lua headers should be inside extern "C"
        Assert.Contains("extern \"C\" {", code);
        Assert.Contains("#include <lua.h>", code);
    }

    [Fact]
    public void CppMode_NoStdBoolInclude()
    {
        var code = CBindingGen.Generate(CppSpec());
        // C++ mode should not include C-specific stdbool.h
        Assert.DoesNotContain("#include <stdbool.h>", code);
    }

    // ===== Namespace call =====

    [Fact]
    public void CppMode_NamespaceCall()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("ImGui::Begin(", code);
        Assert.Contains("ImGui::End()", code);
        Assert.Contains("ImGui::Text(", code);
    }

    // ===== Vec2 input (required) =====

    private static ModuleSpec Vec2Spec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("SetCursorPos", "SetCursorPos",
            [new ParamBinding("pos", new BindingType.Vec2())],
            new BindingType.Void(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_Vec2Input_ChecksTable()
    {
        var code = CBindingGen.Generate(Vec2Spec());
        Assert.Contains("luaL_checktype(L,", code);
        Assert.Contains("LUA_TTABLE", code);
        Assert.Contains("ImVec2", code);
    }

    [Fact]
    public void CppMode_Vec2Input_ReadsXY()
    {
        var code = CBindingGen.Generate(Vec2Spec());
        Assert.Contains("lua_rawgeti(L,", code);
        Assert.Contains("lua_tonumber(L, -1)", code);
    }

    // ===== Vec2 optional input =====

    private static ModuleSpec Vec2OptionalSpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("SetNextWindowPos", "SetNextWindowPos",
            [new ParamBinding("pos", new BindingType.Vec2()),
             new ParamBinding("pivot", new BindingType.Vec2(), IsOptional: true)],
            new BindingType.Void(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_Vec2Optional_UsesIstable()
    {
        var code = CBindingGen.Generate(Vec2OptionalSpec());
        Assert.Contains("lua_istable(L,", code);
        Assert.Contains("ImVec2(0, 0)", code);
    }

    // ===== Vec2 return =====

    private static ModuleSpec Vec2ReturnSpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("GetCursorPos", "GetCursorPos", [],
            new BindingType.Vec2(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_Vec2Return_CreatesTable()
    {
        var code = CBindingGen.Generate(Vec2ReturnSpec());
        Assert.Contains("lua_newtable(L)", code);
        Assert.Contains("lua_rawseti(L, -2, 1)", code);
        Assert.Contains("lua_rawseti(L, -2, 2)", code);
    }

    // ===== Vec4 return =====

    private static ModuleSpec Vec4ReturnSpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("GetStyleColor", "GetStyleColor",
            [new ParamBinding("idx", new BindingType.Int())],
            new BindingType.Vec4(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_Vec4Return_CreatesTable()
    {
        var code = CBindingGen.Generate(Vec4ReturnSpec());
        Assert.Contains("lua_newtable(L)", code);
        Assert.Contains("lua_rawseti(L, -2, 4)", code);
    }

    // ===== FloatArray input/output =====

    private static ModuleSpec FloatArraySpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("ColorEdit4", "ColorEdit4",
            [new ParamBinding("label", new BindingType.Str()),
             new ParamBinding("col", new BindingType.FloatArray(4), IsOutput: true)],
            new BindingType.Bool(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_FloatArray_ReadsFromTable()
    {
        var code = CBindingGen.Generate(FloatArraySpec());
        Assert.Contains("float col[4]", code);
        Assert.Contains("lua_rawgeti(L,", code);
    }

    [Fact]
    public void CppMode_FloatArray_WritesBackToTable()
    {
        var code = CBindingGen.Generate(FloatArraySpec());
        // Write back using absolute table index (2)
        Assert.Contains("lua_rawseti(L, 2, 1)", code);
        Assert.Contains("lua_rawseti(L, 2, 4)", code);
        // Push modified table as return value
        Assert.Contains("lua_pushvalue(L, 2)", code);
    }

    // ===== IsOptional scalar =====

    [Fact]
    public void CppMode_OptionalInt_UsesLuaLOpt()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("luaL_optinteger(L,", code);
    }

    // ===== IsOutput bool =====

    [Fact]
    public void CppMode_OutputBool_PushesExtraReturn()
    {
        var code = CBindingGen.Generate(CppSpec());
        // p_open is IsOutput → should have extra push
        Assert.Contains("p_open", code);
        Assert.Contains("lua_pushboolean(L,", code);
    }

    // ===== luaopen format =====

    [Fact]
    public void CppMode_LuaOpen_ExternC()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("extern \"C\"", code);
        Assert.Contains("luaopen_imgui_gen", code);
    }

    [Fact]
    public void CppMode_LuaOpen_TableIdx()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("lua_absindex", code);
        Assert.Contains("luaL_setfuncs", code);
    }

    [Fact]
    public void CppMode_LuaOpen_VoidReturn()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("extern \"C\" void luaopen_imgui_gen(lua_State *L, int table_idx)", code);
    }

    // ===== Optional output bool (p_open) =====

    private static ModuleSpec OptionalOutputBoolSpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("Begin", "Begin",
            [new ParamBinding("name", new BindingType.Str()),
             new ParamBinding("p_open", new BindingType.Bool(), IsOptional: true, IsOutput: true),
             new ParamBinding("flags", new BindingType.Int(), IsOptional: true)],
            new BindingType.Bool(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_OptionalOutputBool_UsesPointerVar()
    {
        var code = CBindingGen.Generate(OptionalOutputBoolSpec());
        // Should pass p_open (the pointer, can be NULL) not &p_open_val
        Assert.Contains("ImGui::Begin(name, p_open, flags)", code);
    }

    [Fact]
    public void CppMode_RequiredOutputBool_UsesAddressOfVal()
    {
        // Use the original CppSpec where p_open is IsOutput but NOT IsOptional
        var code = CBindingGen.Generate(CppSpec());
        Assert.Contains("&p_open_val", code);
    }

    // ===== Optional string =====

    private static ModuleSpec OptionalStringSpec() => new(
        "imgui", "", ["imgui.h"], null,
        [],
        [new FuncBinding("SliderFloat", "SliderFloat",
            [new ParamBinding("label", new BindingType.Str()),
             new ParamBinding("v", new BindingType.Float(), IsOutput: true),
             new ParamBinding("v_min", new BindingType.Float()),
             new ParamBinding("v_max", new BindingType.Float()),
             new ParamBinding("format", new BindingType.Str(), IsOptional: true),
             new ParamBinding("flags", new BindingType.Int(), IsOptional: true)],
            new BindingType.Bool(), null, CppNamespace: "ImGui")],
        [], [],
        IsCpp: true, EntryPoint: "luaopen_imgui_gen");

    [Fact]
    public void CppMode_OptionalString_UsesLuaLOptString()
    {
        var code = CBindingGen.Generate(OptionalStringSpec());
        Assert.Contains("luaL_optstring(L,", code);
    }

    // ===== No struct generation =====

    [Fact]
    public void CppMode_NoStructs()
    {
        var code = CBindingGen.Generate(CppSpec());
        Assert.DoesNotContain("lua_newuserdatauv", code);
        Assert.DoesNotContain("memset", code);
    }
}
