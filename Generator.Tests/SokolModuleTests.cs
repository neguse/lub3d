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
