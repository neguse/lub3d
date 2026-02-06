using Generator;
using Generator.ClangAst;
using Generator.Modules.Sokol;

namespace Generator.Tests;

/// <summary>
/// テスト用の最小 SokolModule 実装
/// </summary>
file class TestModule : SokolModule
{
    public override string ModuleName => "sokol.test";
    public override string Header => "sokol/sokol_test.h";
    public override string Prefix => "stest_";

    // DefaultResolveType をテストから呼べるように公開
    public static BindingType TestResolveType(Types t, string moduleName, string prefix) =>
        DefaultResolveType(t, moduleName, prefix);
}

/// <summary>
/// カスタム hooks 付きテスト用モジュール
/// </summary>
file class CustomTestModule : SokolModule
{
    public override string ModuleName => "sokol.app";
    public override string Header => "sokol/sokol_app.h";
    public override string Prefix => "sapp_";
    public override IReadOnlyList<string> DepPrefixes => ["slog_"];

    protected override bool ShouldGenerateFunc(Funcs f) => f.Name != "sapp_run";
    protected override bool HasMetamethods(Structs s) => s.Name == "sapp_event";
    protected override string MapFieldName(string name) => name switch
    {
        "init_cb" => "init",
        _ => name
    };
    protected override IEnumerable<(string LuaName, string CFunc)> ExtraLuaRegs =>
        [("Run", "l_sapp_run")];
    protected override string? ExtraCCode(TypeRegistry reg) => "/* custom */\n";
}

public class SokolModuleTests
{
    // ===== DefaultResolveType =====

    [Fact]
    public void ResolveType_Int_ReturnsBindingInt()
    {
        var result = TestModule.TestResolveType(new Types.Int(), "m", "p_");
        Assert.IsType<BindingType.Int>(result);
    }

    [Fact]
    public void ResolveType_Float_ReturnsBindingFloat()
    {
        var result = TestModule.TestResolveType(new Types.Float(), "m", "p_");
        Assert.IsType<BindingType.Float>(result);
    }

    [Fact]
    public void ResolveType_Bool_ReturnsBindingBool()
    {
        var result = TestModule.TestResolveType(new Types.Bool(), "m", "p_");
        Assert.IsType<BindingType.Bool>(result);
    }

    [Fact]
    public void ResolveType_String_ReturnsBindingStr()
    {
        var result = TestModule.TestResolveType(new Types.String(), "m", "p_");
        Assert.IsType<BindingType.Str>(result);
    }

    [Fact]
    public void ResolveType_VoidPtr_ReturnsBindingVoidPtr()
    {
        var result = TestModule.TestResolveType(new Types.Ptr(new Types.Void()), "m", "p_");
        Assert.IsType<BindingType.VoidPtr>(result);
    }

    [Fact]
    public void ResolveType_StructRef_ReturnsBindingStruct()
    {
        var result = TestModule.TestResolveType(new Types.StructRef("sapp_desc"), "sokol.app", "sapp_");
        var s = Assert.IsType<BindingType.Struct>(result);
        Assert.Equal("sapp_desc", s.CName);
        Assert.Equal("sokol.app.Desc", s.Metatable);
        Assert.Equal("sokol.app.Desc", s.LuaClassName);
    }

    [Fact]
    public void ResolveType_FuncPtr_ReturnsCallback()
    {
        var result = TestModule.TestResolveType(
            new Types.FuncPtr([new Types.Int()], new Types.Void()), "m", "p_");
        var cb = Assert.IsType<BindingType.Callback>(result);
        Assert.Single(cb.Params);
        Assert.Equal("arg0", cb.Params[0].Name);
        Assert.IsType<BindingType.Int>(cb.Params[0].Type);
        Assert.Null(cb.Ret);
    }

    [Fact]
    public void ResolveType_FuncPtrWithReturn_ReturnsCallbackWithRet()
    {
        var result = TestModule.TestResolveType(
            new Types.FuncPtr([], new Types.Int()), "m", "p_");
        var cb = Assert.IsType<BindingType.Callback>(result);
        Assert.Empty(cb.Params);
        Assert.IsType<BindingType.Int>(cb.Ret);
    }

    [Fact]
    public void ResolveType_Void_ReturnsBindingVoid()
    {
        var result = TestModule.TestResolveType(new Types.Void(), "m", "p_");
        Assert.IsType<BindingType.Void>(result);
    }

    [Theory]
    [InlineData(typeof(BindingType.Int64), typeof(Types.Int64))]
    [InlineData(typeof(BindingType.UInt32), typeof(Types.UInt32))]
    [InlineData(typeof(BindingType.UInt64), typeof(Types.UInt64))]
    [InlineData(typeof(BindingType.Size), typeof(Types.Size))]
    [InlineData(typeof(BindingType.UIntPtr), typeof(Types.UIntPtr))]
    [InlineData(typeof(BindingType.IntPtr), typeof(Types.IntPtr))]
    [InlineData(typeof(BindingType.Double), typeof(Types.Double))]
    public void ResolveType_NumericTypes(System.Type expectedBt, System.Type inputType)
    {
        var input = (Types)Activator.CreateInstance(inputType)!;
        var result = TestModule.TestResolveType(input, "m", "p_");
        Assert.IsType(expectedBt, result);
    }

    [Fact]
    public void ResolveType_ConstPtr_Unwraps()
    {
        var result = TestModule.TestResolveType(
            new Types.ConstPtr(new Types.String()), "m", "p_");
        var cp = Assert.IsType<BindingType.ConstPtr>(result);
        Assert.IsType<BindingType.Str>(cp.Inner);
    }

    // ===== BuildSpec — 基本 =====

    private const string SimpleJson = """
    {
      "module": "sokol.test",
      "prefix": "stest_",
      "dep_prefixes": [],
      "decls": [
        {
          "kind": "struct",
          "name": "stest_desc",
          "fields": [
            { "name": "width", "type": "int" },
            { "name": "title", "type": "const char *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "stest_init",
          "type": "void (const stest_desc *)",
          "params": [
            { "name": "desc", "type": "const stest_desc *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "enum",
          "name": "stest_mode",
          "items": [
            { "name": "STEST_MODE_DEFAULT" },
            { "name": "STEST_MODE_FAST", "value": "5" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void BuildSpec_ModuleName()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Equal("sokol.test", spec.ModuleName);
    }

    [Fact]
    public void BuildSpec_Prefix()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Equal("stest_", spec.Prefix);
    }

    [Fact]
    public void BuildSpec_CIncludes()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Contains("sokol_test.h", spec.CIncludes);
    }

    [Fact]
    public void BuildSpec_Structs()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Single(spec.Structs);
        var s = spec.Structs[0];
        Assert.Equal("stest_desc", s.CName);
        Assert.Equal("Desc", s.PascalName);
        Assert.Equal("sokol.test.Desc", s.Metatable);
        Assert.False(s.HasMetamethods);
    }

    [Fact]
    public void BuildSpec_StructFields()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        var fields = spec.Structs[0].Fields;
        Assert.Equal(2, fields.Count);
        Assert.Equal("width", fields[0].CName);
        Assert.Equal("width", fields[0].LuaName);
        Assert.IsType<BindingType.Int>(fields[0].Type);
        Assert.Equal("title", fields[1].CName);
        Assert.IsType<BindingType.ConstPtr>(fields[1].Type);
    }

    [Fact]
    public void BuildSpec_Funcs()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Single(spec.Funcs);
        var f = spec.Funcs[0];
        Assert.Equal("stest_init", f.CName);
        Assert.Equal("Init", f.LuaName);
        Assert.Single(f.Params);
        Assert.Equal("desc", f.Params[0].Name);
        Assert.IsType<BindingType.Void>(f.ReturnType);
    }

    [Fact]
    public void BuildSpec_Enums()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Single(spec.Enums);
        var e = spec.Enums[0];
        Assert.Equal("stest_mode", e.CName);
        Assert.Equal("sokol.test.Mode", e.LuaName);
        Assert.Equal("Mode", e.FieldName);
        Assert.Equal(2, e.Items.Count);
        Assert.Equal("DEFAULT", e.Items[0].LuaName);
        Assert.Equal(0, e.Items[0].Value);
        Assert.Equal("FAST", e.Items[1].LuaName);
        Assert.Equal(5, e.Items[1].Value);
    }

    [Fact]
    public void BuildSpec_ExtraCCodeNull()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Null(spec.ExtraCCode);
    }

    [Fact]
    public void BuildSpec_ExtraLuaRegsEmpty()
    {
        var reg = TypeRegistry.FromJson(SimpleJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Empty(spec.ExtraLuaRegs);
    }

    // ===== BuildSpec — カスタム hooks =====

    private const string AppJson = """
    {
      "module": "sokol.app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        {
          "kind": "struct",
          "name": "sapp_event",
          "fields": [
            { "name": "type", "type": "sapp_event_type" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "sapp_desc",
          "fields": [
            { "name": "init_cb", "type": "void (*)(void)" },
            { "name": "width", "type": "int" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_run",
          "type": "void (const sapp_desc *)",
          "params": [
            { "name": "desc", "type": "const sapp_desc *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_width",
          "type": "int (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void BuildSpec_ShouldGenerateFunc_Filters()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "sapp_run");
        Assert.Contains(spec.Funcs, f => f.CName == "sapp_width");
    }

    [Fact]
    public void BuildSpec_HasMetamethods_SetCorrectly()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var eventStruct = spec.Structs.First(s => s.CName == "sapp_event");
        var descStruct = spec.Structs.First(s => s.CName == "sapp_desc");
        Assert.True(eventStruct.HasMetamethods);
        Assert.False(descStruct.HasMetamethods);
    }

    [Fact]
    public void BuildSpec_MapFieldName_Renames()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var descStruct = spec.Structs.First(s => s.CName == "sapp_desc");
        var initField = descStruct.Fields.First(f => f.CName == "init_cb");
        Assert.Equal("init", initField.LuaName);
    }

    [Fact]
    public void BuildSpec_ExtraLuaRegs_Added()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.Contains(spec.ExtraLuaRegs, r => r.LuaName == "Run" && r.CFunc == "l_sapp_run");
    }

    [Fact]
    public void BuildSpec_ExtraCCode_Included()
    {
        var reg = TypeRegistry.FromJson(AppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.Equal("/* custom */\n", spec.ExtraCCode);
    }

    // ===== BuildSpec — enum StructRef 解決 =====

    private const string EnumFieldJson = """
    {
      "module": "sokol.test",
      "prefix": "stest_",
      "dep_prefixes": [],
      "decls": [
        {
          "kind": "struct",
          "name": "stest_event",
          "fields": [
            { "name": "type", "type": "stest_event_type" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "enum",
          "name": "stest_event_type",
          "items": [
            { "name": "STEST_EVENT_TYPE_INVALID" },
            { "name": "STEST_EVENT_TYPE_KEY_DOWN" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void BuildSpec_EnumFieldType_ResolvesAsEnum()
    {
        var reg = TypeRegistry.FromJson(EnumFieldJson);
        var spec = new TestModule().BuildSpec(reg);
        var eventStruct = spec.Structs.First(s => s.CName == "stest_event");
        var typeField = eventStruct.Fields.First(f => f.CName == "type");
        var enumType = Assert.IsType<BindingType.Enum>(typeField.Type);
        Assert.Equal("stest_event_type", enumType.CName);
        Assert.Equal("sokol.test.EventType", enumType.LuaName);
    }

    [Fact]
    public void BuildSpec_EnumFieldType_EnumStillGenerated()
    {
        var reg = TypeRegistry.FromJson(EnumFieldJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.Single(spec.Enums);
        Assert.Equal("stest_event_type", spec.Enums[0].CName);
    }

    // ===== BuildSpec — フル App API =====

    private const string FullAppJson = """
    {
      "module": "sokol.app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        { "kind": "enum", "name": "sapp_event_type", "items": [
          { "name": "SAPP_EVENTTYPE_INVALID" },
          { "name": "SAPP_EVENTTYPE_KEY_DOWN" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "enum", "name": "sapp_keycode", "items": [
          { "name": "SAPP_KEYCODE_INVALID", "value": "0" },
          { "name": "SAPP_KEYCODE_SPACE", "value": "32" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "enum", "name": "sapp_mousebutton", "items": [
          { "name": "SAPP_MOUSEBUTTON_LEFT" },
          { "name": "SAPP_MOUSEBUTTON_RIGHT" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "enum", "name": "sapp_mouse_cursor", "items": [
          { "name": "SAPP_MOUSECURSOR_DEFAULT" },
          { "name": "SAPP_MOUSECURSOR_ARROW" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "enum", "name": "sapp_pixel_format", "items": [
          { "name": "_SAPP_PIXELFORMAT_DEFAULT" },
          { "name": "SAPP_PIXELFORMAT_NONE" },
          { "name": "SAPP_PIXELFORMAT_RGBA8" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "struct", "name": "sapp_event", "fields": [
          { "name": "frame_count", "type": "uint64_t" },
          { "name": "type", "type": "sapp_event_type" },
          { "name": "key_code", "type": "sapp_keycode" },
          { "name": "char_code", "type": "uint32_t" },
          { "name": "key_repeat", "type": "bool" },
          { "name": "modifiers", "type": "uint32_t" },
          { "name": "mouse_button", "type": "sapp_mousebutton" },
          { "name": "mouse_x", "type": "float" },
          { "name": "scroll_x", "type": "float" },
          { "name": "num_touches", "type": "int" },
          { "name": "window_width", "type": "int" },
          { "name": "framebuffer_width", "type": "int" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "struct", "name": "sapp_desc", "fields": [
          { "name": "init_cb", "type": "void (*)(void)" },
          { "name": "frame_cb", "type": "void (*)(void)" },
          { "name": "cleanup_cb", "type": "void (*)(void)" },
          { "name": "event_cb", "type": "void (*)(const sapp_event *)" },
          { "name": "user_data", "type": "void *" },
          { "name": "width", "type": "int" },
          { "name": "height", "type": "int" },
          { "name": "high_dpi", "type": "bool" },
          { "name": "fullscreen", "type": "bool" },
          { "name": "window_title", "type": "const char *" },
          { "name": "sample_count", "type": "int" },
          { "name": "enable_clipboard", "type": "bool" },
          { "name": "clipboard_size", "type": "int" }
        ], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_run", "type": "void (const sapp_desc *)",
          "params": [{ "name": "desc", "type": "const sapp_desc *" }],
          "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_isvalid", "type": "bool (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_width", "type": "int (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_widthf", "type": "float (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_frame_count", "type": "uint64_t (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_frame_duration", "type": "double (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_color_format", "type": "sapp_pixel_format (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_get_mouse_cursor", "type": "sapp_mouse_cursor (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_get_clipboard_string", "type": "const char * (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_userdata", "type": "void * (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_show_keyboard", "type": "void (bool)",
          "params": [{ "name": "show", "type": "bool" }],
          "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_set_mouse_cursor", "type": "void (sapp_mouse_cursor)",
          "params": [{ "name": "cursor", "type": "sapp_mouse_cursor" }],
          "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_set_window_title", "type": "void (const char *)",
          "params": [{ "name": "str", "type": "const char *" }],
          "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_request_quit", "type": "void (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_keyboard_shown", "type": "bool (void)",
          "params": [], "is_dep": false, "dep_prefix": null },
        { "kind": "func", "name": "sapp_dpi_scale", "type": "float (void)",
          "params": [], "is_dep": false, "dep_prefix": null }
      ]
    }
    """;

    [Fact]
    public void FullApp_AllEnumsPresent()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.Equal(5, spec.Enums.Count);
        Assert.Contains(spec.Enums, e => e.CName == "sapp_event_type");
        Assert.Contains(spec.Enums, e => e.CName == "sapp_keycode");
        Assert.Contains(spec.Enums, e => e.CName == "sapp_pixel_format");
    }

    [Fact]
    public void FullApp_EventEnumFields_ResolveAsEnum()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var ev = spec.Structs.First(s => s.CName == "sapp_event");
        var typeField = ev.Fields.First(f => f.CName == "type");
        var keyField = ev.Fields.First(f => f.CName == "key_code");
        var btnField = ev.Fields.First(f => f.CName == "mouse_button");
        Assert.IsType<BindingType.Enum>(typeField.Type);
        Assert.IsType<BindingType.Enum>(keyField.Type);
        Assert.IsType<BindingType.Enum>(btnField.Type);
    }

    [Fact]
    public void FullApp_EventHasMetamethods()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var ev = spec.Structs.First(s => s.CName == "sapp_event");
        var desc = spec.Structs.First(s => s.CName == "sapp_desc");
        Assert.True(ev.HasMetamethods);
        Assert.False(desc.HasMetamethods);
    }

    [Fact]
    public void FullApp_DescCallbackFields()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var desc = spec.Structs.First(s => s.CName == "sapp_desc");
        var initField = desc.Fields.First(f => f.CName == "init_cb");
        Assert.Equal("init", initField.LuaName);
        Assert.IsType<BindingType.Callback>(initField.Type);
    }

    [Fact]
    public void FullApp_RunFiltered_ExtraRegAdded()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "sapp_run");
        Assert.Contains(spec.ExtraLuaRegs, r => r.LuaName == "Run");
    }

    [Fact]
    public void FullApp_AllReturnTypes()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        Assert.IsType<BindingType.Bool>(spec.Funcs.First(f => f.CName == "sapp_isvalid").ReturnType);
        Assert.IsType<BindingType.Int>(spec.Funcs.First(f => f.CName == "sapp_width").ReturnType);
        Assert.IsType<BindingType.Float>(spec.Funcs.First(f => f.CName == "sapp_widthf").ReturnType);
        Assert.IsType<BindingType.UInt64>(spec.Funcs.First(f => f.CName == "sapp_frame_count").ReturnType);
        Assert.IsType<BindingType.Double>(spec.Funcs.First(f => f.CName == "sapp_frame_duration").ReturnType);
        Assert.IsType<BindingType.Enum>(spec.Funcs.First(f => f.CName == "sapp_color_format").ReturnType);
        Assert.IsType<BindingType.Enum>(spec.Funcs.First(f => f.CName == "sapp_get_mouse_cursor").ReturnType);
        Assert.IsType<BindingType.VoidPtr>(spec.Funcs.First(f => f.CName == "sapp_userdata").ReturnType);
    }

    [Fact]
    public void FullApp_StringReturnType()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var f = spec.Funcs.First(f => f.CName == "sapp_get_clipboard_string");
        Assert.IsType<BindingType.ConstPtr>(f.ReturnType);
        var inner = Assert.IsType<BindingType.ConstPtr>(f.ReturnType);
        Assert.IsType<BindingType.Str>(inner.Inner);
    }

    [Fact]
    public void FullApp_ParamTypes()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var showKb = spec.Funcs.First(f => f.CName == "sapp_show_keyboard");
        Assert.IsType<BindingType.Bool>(showKb.Params[0].Type);
        var setCursor = spec.Funcs.First(f => f.CName == "sapp_set_mouse_cursor");
        Assert.IsType<BindingType.Enum>(setCursor.Params[0].Type);
        var setTitle = spec.Funcs.First(f => f.CName == "sapp_set_window_title");
        Assert.IsType<BindingType.ConstPtr>(setTitle.Params[0].Type);
    }

    [Fact]
    public void FullApp_CGen_EnumFieldInit()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = CBinding.CBindingGen.Generate(spec);
        // enum fields should be initialized with lua_tointeger
        Assert.Contains("(sapp_event_type)lua_tointeger", code);
    }

    [Fact]
    public void FullApp_CGen_ReturnTypes()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = CBinding.CBindingGen.Generate(spec);
        Assert.Contains("lua_pushboolean(L, sapp_isvalid())", code);
        Assert.Contains("lua_pushinteger(L, sapp_width())", code);
        Assert.Contains("lua_pushnumber(L, sapp_widthf())", code);
        Assert.Contains("lua_pushinteger(L, (lua_Integer)sapp_frame_count())", code);
        Assert.Contains("lua_pushnumber(L, (lua_Number)sapp_frame_duration())", code);
        Assert.Contains("lua_pushinteger(L, (lua_Integer)sapp_color_format())", code);
        Assert.Contains("lua_pushstring(L, sapp_get_clipboard_string())", code);
        Assert.Contains("lua_pushlightuserdata(L, (void*)sapp_userdata())", code);
    }

    [Fact]
    public void FullApp_CGen_ParamTypes()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = CBinding.CBindingGen.Generate(spec);
        Assert.Contains("lua_toboolean(L, 1)", code);
        Assert.Contains("(sapp_mouse_cursor)luaL_checkinteger(L, 1)", code);
        Assert.Contains("luaL_checkstring(L, 1)", code);
    }

    [Fact]
    public void FullApp_CGen_EventMetamethods()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = CBinding.CBindingGen.Generate(spec);
        Assert.Contains("l_sapp_event__index", code);
        Assert.Contains("l_sapp_event__newindex", code);
        Assert.Contains("l_sapp_event__pairs", code);
    }

    [Fact]
    public void FullApp_LuaCats_EnumFieldTypes()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = LuaCats.LuaCatsGen.Generate(spec);
        Assert.Contains("---@field type? sokol.app.EventType", code);
        Assert.Contains("---@field key_code? sokol.app.Keycode", code);
        Assert.Contains("---@field mouse_button? sokol.app.Mousebutton", code);
    }

    [Fact]
    public void FullApp_LuaCats_EnumReturn()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = LuaCats.LuaCatsGen.Generate(spec);
        Assert.Contains("---@field ColorFormat fun(): sokol.app.PixelFormat", code);
        Assert.Contains("---@field GetMouseCursor fun(): sokol.app.MouseCursor", code);
    }

    [Fact]
    public void FullApp_LuaCats_CallbackField()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var code = LuaCats.LuaCatsGen.Generate(spec);
        Assert.Contains("---@field init? fun()", code);
        Assert.Contains("---@field frame_cb? fun()", code);
    }

    [Fact]
    public void FullApp_PixelFormat_UnderscorePrefixFiltered()
    {
        var reg = TypeRegistry.FromJson(FullAppJson);
        var spec = new CustomTestModule().BuildSpec(reg);
        var pf = spec.Enums.First(e => e.CName == "sapp_pixel_format");
        // Items starting with _ should be filtered
        Assert.DoesNotContain(pf.Items, i => i.CConstName == "_SAPP_PIXELFORMAT_DEFAULT");
        Assert.Contains(pf.Items, i => i.LuaName == "NONE");
        Assert.Contains(pf.Items, i => i.LuaName == "RGBA8");
    }

    // ===== BuildSpec — dep フィルタリング =====

    private const string DepJson = """
    {
      "module": "sokol.test",
      "prefix": "stest_",
      "dep_prefixes": ["sdep_"],
      "decls": [
        {
          "kind": "struct",
          "name": "stest_desc",
          "fields": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "sdep_thing",
          "fields": [],
          "is_dep": true,
          "dep_prefix": "sdep_"
        },
        {
          "kind": "func",
          "name": "stest_init",
          "type": "void (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sdep_func",
          "type": "void (void)",
          "params": [],
          "is_dep": true,
          "dep_prefix": "sdep_"
        }
      ]
    }
    """;

    [Fact]
    public void BuildSpec_ExcludesDepStructs()
    {
        var reg = TypeRegistry.FromJson(DepJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.DoesNotContain(spec.Structs, s => s.CName == "sdep_thing");
        Assert.Contains(spec.Structs, s => s.CName == "stest_desc");
    }

    [Fact]
    public void BuildSpec_ExcludesDepFuncs()
    {
        var reg = TypeRegistry.FromJson(DepJson);
        var spec = new TestModule().BuildSpec(reg);
        Assert.DoesNotContain(spec.Funcs, f => f.CName == "sdep_func");
        Assert.Contains(spec.Funcs, f => f.CName == "stest_init");
    }
}
