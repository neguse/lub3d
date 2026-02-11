using Generator;
using Generator.CBinding;

namespace Generator.Tests;

public class GenTests
{
    private static ModuleSpec MakeTestSpec() => new(
        ModuleName: "sokol_app",
        Prefix: "sapp_",
        CIncludes: ["sokol_log.h", "sokol_app.h"],
        ExtraCCode: null,
        Structs: [
            new StructBinding(
                CName: "sapp_desc",
                PascalName: "Desc",
                Metatable: "sokol_app.Desc",
                HasMetamethods: true,
                Fields: [
                    new FieldBinding("width", "width", new BindingType.Int()),
                    new FieldBinding("height", "height", new BindingType.Int()),
                    new FieldBinding("window_title", "window_title", new BindingType.Str()),
                    new FieldBinding("init_cb", "init_cb", new BindingType.Callback([], null))
                ],
                SourceLink: null)
        ],
        Funcs: [
            new FuncBinding(
                CName: "sapp_run",
                LuaName: "Run",
                Params: [new ParamBinding("desc", new BindingType.ConstPtr(new BindingType.Struct("sapp_desc", "sokol_app.Desc", "sokol_app.Desc")))],
                ReturnType: new BindingType.Void(),
                SourceLink: null),
            new FuncBinding(
                CName: "sapp_width",
                LuaName: "Width",
                Params: [],
                ReturnType: new BindingType.Int(),
                SourceLink: null)
        ],
        Enums: [
            new EnumBinding(
                CName: "sapp_event_type",
                LuaName: "sokol_app.EventType",
                FieldName: "EventType",
                Items: [
                    new EnumItemBinding("INVALID", "SAPP_EVENTTYPE_INVALID", 0),
                    new EnumItemBinding("KEY_DOWN", "SAPP_EVENTTYPE_KEY_DOWN", 1),
                    new EnumItemBinding("KEY_UP", "SAPP_EVENTTYPE_KEY_UP", 2)
                ],
                SourceLink: null)
        ],
        ExtraLuaRegs: []
    );

    [Fact]
    public void Header_ContainsIncludes()
    {
        var code = CBindingGen.Generate(MakeTestSpec());
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_app.h\"", code);
    }

    [Fact]
    public void Enum_ContainsValues()
    {
        var code = CBindingGen.Generate(MakeTestSpec());
        Assert.Contains("INVALID", code);
        Assert.Contains("KEY_DOWN", code);
    }

    [Fact]
    public void LuaReg_ContainsEntries()
    {
        var code = CBindingGen.Generate(MakeTestSpec());
        Assert.Contains("{\"Desc\", l_sapp_desc_new}", code);
        Assert.Contains("{\"Run\", l_sapp_run}", code);
        Assert.Contains("{NULL, NULL}", code);
    }

    [Fact]
    public void LuaOpen_ContainsOpenFunction()
    {
        var code = CBindingGen.Generate(MakeTestSpec());
        Assert.Contains("int luaopen_sokol_app(lua_State *L)", code);
        Assert.Contains("luaL_newlib(L, sokol_app_funcs)", code);
    }
}
