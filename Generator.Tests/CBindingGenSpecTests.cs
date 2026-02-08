using Generator;
using Generator.CBinding;

namespace Generator.Tests;

public class CBindingGenSpecTests
{
    private static ModuleSpec MinimalSpec() => new(
        "sokol.test", "stest_",
        ["sokol_test.h"],
        null,
        [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
            [new FieldBinding("width", "width", new BindingType.Int()),
             new FieldBinding("title", "title", new BindingType.ConstPtr(new BindingType.Str()))],
            null)],
        [new FuncBinding("stest_init", "Init",
            [new ParamBinding("desc", new BindingType.ConstPtr(
                new BindingType.Struct("stest_desc", "sokol.test.Desc", "sokol.test.Desc")))],
            new BindingType.Void(), null)],
        [new EnumBinding("stest_mode", "sokol.test.Mode", "Mode",
            [new EnumItemBinding("DEFAULT", "STEST_MODE_DEFAULT", 0),
             new EnumItemBinding("FAST", "STEST_MODE_FAST", 5)],
            null)],
        []);

    [Fact]
    public void Generate_ContainsHeader()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_test.h\"", code);
    }

    [Fact]
    public void Generate_ContainsStructNew()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("l_stest_desc_new", code);
        Assert.Contains("lua_getfield(L, 1, \"width\")", code);
    }

    [Fact]
    public void Generate_ContainsFunc()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("l_stest_init", code);
    }

    [Fact]
    public void Generate_ContainsEnum()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_stest_mode", code);
        Assert.Contains("STEST_MODE_DEFAULT", code);
        Assert.Contains("STEST_MODE_FAST", code);
    }

    [Fact]
    public void Generate_ContainsLuaReg()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("sokol_test_funcs[]", code);
        Assert.Contains("{\"Desc\", l_stest_desc_new}", code);
        Assert.Contains("{\"Init\", l_stest_init}", code);
    }

    [Fact]
    public void Generate_ContainsLuaOpen()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("luaopen_sokol_test", code);
    }

    [Fact]
    public void Generate_ContainsMetatableRegistration()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_metatables", code);
        Assert.Contains("sokol.test.Desc", code);
    }

    [Fact]
    public void Generate_EnumInLuaOpen()
    {
        var code = CBindingGen.Generate(MinimalSpec());
        Assert.Contains("register_stest_mode(L)", code);
    }

    // ===== Metamethods =====

    private static ModuleSpec SpecWithMetamethods() => new(
        "sokol.test", "stest_",
        ["sokol_test.h"],
        null,
        [new StructBinding("stest_event", "Event", "sokol.test.Event", true,
            [new FieldBinding("type", "type", new BindingType.Int()),
             new FieldBinding("key", "key", new BindingType.Int())],
            null)],
        [], [], []);

    [Fact]
    public void Generate_WithMetamethods_ContainsIndex()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__index", code);
        Assert.Contains("strcmp(key, \"type\")", code);
    }

    [Fact]
    public void Generate_WithMetamethods_ContainsNewindex()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__newindex", code);
    }

    [Fact]
    public void Generate_WithMetamethods_ContainsPairs()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("l_stest_event__pairs", code);
    }

    [Fact]
    public void Generate_WithMetamethods_RegistersInMetatables()
    {
        var code = CBindingGen.Generate(SpecWithMetamethods());
        Assert.Contains("lua_setfield(L, -2, \"__index\")", code);
        Assert.Contains("lua_setfield(L, -2, \"__newindex\")", code);
        Assert.Contains("lua_setfield(L, -2, \"__pairs\")", code);
    }

    // ===== ExtraCCode / ExtraLuaRegs =====

    private static ModuleSpec SpecWithExtras() => new(
        "sokol.app", "sapp_",
        ["sokol_log.h", "sokol_app.h"],
        "/* extra C code */\n",
        [],
        [],
        [],
        [("Run", "l_sapp_run")]);

    [Fact]
    public void Generate_ContainsExtraCCode()
    {
        var code = CBindingGen.Generate(SpecWithExtras());
        Assert.Contains("/* extra C code */", code);
    }

    [Fact]
    public void Generate_ContainsExtraLuaRegs()
    {
        var code = CBindingGen.Generate(SpecWithExtras());
        Assert.Contains("{\"Run\", l_sapp_run}", code);
    }

    // ===== No enums =====

    private static ModuleSpec SpecNoEnums() => new(
        "sokol.log", "slog_",
        ["sokol_log.h"],
        null,
        [],
        [new FuncBinding("slog_func", "Func", [], new BindingType.Void(), null)],
        [],
        []);

    [Fact]
    public void Generate_NoEnums_UsesSimpleLuaOpen()
    {
        var code = CBindingGen.Generate(SpecNoEnums());
        Assert.Contains("luaopen_sokol_log", code);
        Assert.Contains("luaL_newlib", code);
    }

    // ===== Return types =====

    [Fact]
    public void Generate_IntReturn_PushesInteger()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_width", "Width", [], new BindingType.Int(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushinteger(L, stest_width())", code);
    }

    [Fact]
    public void Generate_BoolReturn_PushesBoolean()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_valid", "Valid", [], new BindingType.Bool(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushboolean(L, stest_valid())", code);
    }

    [Fact]
    public void Generate_FloatReturn_PushesNumber()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_scale", "Scale", [], new BindingType.Float(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushnumber(L, stest_scale())", code);
    }

    // ===== 追加 return 型 =====

    [Fact]
    public void Generate_DoubleReturn_PushesNumber()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_duration", "Duration", [], new BindingType.Double(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushnumber(L, (lua_Number)stest_duration())", code);
    }

    [Fact]
    public void Generate_StringReturn_PushesString()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_name", "Name", [], new BindingType.Str(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushstring(L, stest_name())", code);
    }

    [Fact]
    public void Generate_UInt64Return_PushesInteger()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_count", "Count", [], new BindingType.UInt64(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushinteger(L, (lua_Integer)stest_count())", code);
    }

    [Fact]
    public void Generate_VoidPtrReturn_PushesLightuserdata()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_userdata", "Userdata", [], new BindingType.VoidPtr(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushlightuserdata(L, (void*)stest_userdata())", code);
    }

    [Fact]
    public void Generate_EnumReturn_PushesInteger()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_get_mode", "GetMode", [],
                new BindingType.Enum("stest_mode", "sokol.test.Mode"), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_pushinteger(L, (lua_Integer)stest_get_mode())", code);
    }

    // ===== パラメータ型 =====

    [Fact]
    public void Generate_BoolParam_ChecksBoolean()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_show", "Show",
                [new ParamBinding("visible", new BindingType.Bool())],
                new BindingType.Void(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_toboolean(L, 1)", code);
    }

    [Fact]
    public void Generate_FloatParam_ChecksNumber()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_set_scale", "SetScale",
                [new ParamBinding("scale", new BindingType.Float())],
                new BindingType.Void(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("luaL_checknumber(L, 1)", code);
    }

    [Fact]
    public void Generate_EnumParam_ChecksInteger()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_set_mode", "SetMode",
                [new ParamBinding("mode", new BindingType.Enum("stest_mode", "sokol.test.Mode"))],
                new BindingType.Void(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("luaL_checkinteger(L, 1)", code);
    }

    // ===== Enum フィールド初期化 =====

    [Fact]
    public void Generate_EnumField_InitFromTable()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("mode", "mode", new BindingType.Enum("stest_mode", "sokol.test.Mode"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_getfield(L, 1, \"mode\")", code);
        Assert.Contains("lua_tointeger", code);
    }

    // ===== ConstPtr(Struct) パラメータ — 正しいメタテーブル =====

    [Fact]
    public void Generate_StructParam_CorrectMetatable()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false, [], null),
             new StructBinding("stest_other", "Other", "sokol.test.Other", false, [], null)],
            [new FuncBinding("stest_use_other", "UseOther",
                [new ParamBinding("other", new BindingType.ConstPtr(
                    new BindingType.Struct("stest_other", "sokol.test.Other", "sokol.test.Other")))],
                new BindingType.Void(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("luaL_checkudata(L, 1, \"sokol.test.Other\")", code);
    }

    // ===== Struct フィールド（ネスト構造体）自動構築 =====

    [Fact]
    public void Generate_StructField_AutoConstructFromTable()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_range", "Range", "sokol.test.Range", false, [], null),
             new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("range", "range",
                    new BindingType.Struct("stest_range", "sokol.test.Range", "sokol.test.Range"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_getfield(L, 1, \"range\")", code);
        Assert.Contains("lua_istable(L, -1)", code);
        Assert.Contains("l_stest_range_new", code);
        Assert.Contains("lua_isuserdata(L, -1)", code);
        Assert.Contains("luaL_checkudata(L, -1, \"sokol.test.Range\")", code);
        Assert.DoesNotContain("lua_tointeger", code);
    }

    [Fact]
    public void Generate_StructField_FallbackForUnknownStruct()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("data", "data",
                    new BindingType.Struct("uint8_t", "uint8_t", "uint8_t"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_isuserdata(L, -1)", code);
        Assert.DoesNotContain("l_uint8_t_new", code);
        Assert.DoesNotContain("lua_istable(L, -1)", code);
    }

    [Fact]
    public void Generate_ArrayOfStructField_AutoConstructFromTable()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_item", "Item", "sokol.test.Item", false, [], null),
             new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("items", "items",
                    new BindingType.FixedArray(
                        new BindingType.Struct("stest_item", "sokol.test.Item", "sokol.test.Item"), 4))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_istable(L, -1)", code);
        Assert.Contains("l_stest_item_new", code);
        Assert.Contains("lua_isuserdata(L, -1)", code);
        Assert.Contains("luaL_checkudata(L, -1, \"sokol.test.Item\")", code);
    }

    [Fact]
    public void Generate_ArrayOfStructField_FallbackForUnknownStruct()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", false,
                [new FieldBinding("data", "data",
                    new BindingType.FixedArray(
                        new BindingType.Struct("uint16_t", "uint16_t", "uint16_t"), 8))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_isuserdata(L, -1)", code);
        Assert.DoesNotContain("l_uint16_t_new", code);
    }

    [Fact]
    public void Generate_StructField_NonOwnStruct_CopiesInIndex()
    {
        // 非 ownStructs の struct フィールドは userdata コピーで __index 対応
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", true,
                [new FieldBinding("range", "range",
                    new BindingType.Struct("stest_range", "sokol.test.Range", "sokol.test.Range"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_newuserdatauv(L, sizeof(stest_range), 0)", code);
        Assert.Contains("*_ud = self->range", code);
        Assert.Contains("luaL_setmetatable(L, \"sokol.test.Range\")", code);
    }

    [Fact]
    public void Generate_StructField_NonOwnStruct_CopiesInNewindex()
    {
        // 非 ownStructs の struct フィールドは userdata コピーで __newindex 対応
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [new StructBinding("stest_desc", "Desc", "sokol.test.Desc", true,
                [new FieldBinding("range", "range",
                    new BindingType.Struct("stest_range", "sokol.test.Range", "sokol.test.Range"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("luaL_checkudata(L, 3, \"sokol.test.Range\")", code);
    }

    // ===== 構造体 return — userdata 生成 =====

    [Fact]
    public void Generate_StructReturn_CreatesUserdata()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_query_desc", "QueryDesc", [],
                new BindingType.Struct("stest_desc", "sokol.test.Desc", "sokol.test.Desc"), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("stest_desc result = stest_query_desc()", code);
        Assert.Contains("lua_newuserdatauv(L, sizeof(stest_desc), 0)", code);
        Assert.Contains("*ud = result", code);
        Assert.Contains("luaL_setmetatable(L, \"sokol.test.Desc\")", code);
    }

    // ===== void* return — (void*) cast =====

    [Fact]
    public void Generate_VoidPtrReturn_HasVoidCast()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_get_display", "GetDisplay", [],
                new BindingType.VoidPtr(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("(void*)stest_get_display()", code);
    }

    // ===== ConstPtr(Void) return — (void*) cast =====

    [Fact]
    public void Generate_ConstVoidPtrReturn_HasVoidCast()
    {
        var spec = new ModuleSpec(
            "sokol.test", "stest_", ["sokol_test.h"], null,
            [],
            [new FuncBinding("stest_get_context", "GetContext", [],
                new BindingType.ConstPtr(new BindingType.Void()), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("(void*)stest_get_context()", code);
    }

    // ===== sg_range string 対応 =====

    [Fact]
    public void Generate_SgRange_ConstructorHandlesString()
    {
        var spec = new ModuleSpec(
            "sokol.gfx", "sg_", ["sokol_gfx.h"], null,
            [new StructBinding("sg_range", "Range", "sokol.gfx.Range", false,
                [new FieldBinding("size", "size", new BindingType.Size())],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("l_sg_range_new", code);
        Assert.Contains("lua_isstring(L, 1)", code);
        Assert.Contains("lua_tolstring(L, 1, &len)", code);
        Assert.Contains("lua_setiuservalue", code);
    }

    [Fact]
    public void Generate_SgRangeField_ChecksIsString()
    {
        var spec = new ModuleSpec(
            "sokol.gfx", "sg_", ["sokol_gfx.h"], null,
            [new StructBinding("sg_range", "Range", "sokol.gfx.Range", false,
                [new FieldBinding("size", "size", new BindingType.Size())],
                null),
             new StructBinding("sg_desc", "Desc", "sokol.gfx.Desc", false,
                [new FieldBinding("bytecode", "bytecode",
                    new BindingType.Struct("sg_range", "sokol.gfx.Range", "sokol.gfx.Range"))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_isstring(L, -1) || lua_istable(L, -1)", code);
    }

    [Fact]
    public void Generate_SgRangeArrayField_ChecksIsString()
    {
        var spec = new ModuleSpec(
            "sokol.gfx", "sg_", ["sokol_gfx.h"], null,
            [new StructBinding("sg_range", "Range", "sokol.gfx.Range", false,
                [new FieldBinding("size", "size", new BindingType.Size())],
                null),
             new StructBinding("sg_desc", "Desc", "sokol.gfx.Desc", false,
                [new FieldBinding("mip_levels", "mip_levels",
                    new BindingType.FixedArray(
                        new BindingType.Struct("sg_range", "sokol.gfx.Range", "sokol.gfx.Range"), 4))],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("lua_isstring(L, -1) || lua_istable(L, -1)", code);
    }

    // ===== Custom 型フィールド — PushCode / SetCode =====

    [Fact]
    public void Generate_CustomField_UsesPushCodeInIndex()
    {
        var customType = new BindingType.Custom(
            "b2Vec2", "number[]", null,
            "    b2Vec2 {name} = *(b2Vec2*)luaL_checkudata(L, {idx}, \"b2Vec2\");",
            "lua_newtable(L);\n        lua_pushnumber(L, {value}.x); lua_rawseti(L, -2, 1);\n        lua_pushnumber(L, {value}.y); lua_rawseti(L, -2, 2);\n        return 1",
            "luaL_checktype(L, 3, LUA_TTABLE);\n            lua_rawgeti(L, 3, 1); self->{fieldName}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n            lua_rawgeti(L, 3, 2); self->{fieldName}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1)");
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null,
            [new StructBinding("b2BodyDef", "BodyDef", "b2d.BodyDef", true,
                [new FieldBinding("position", "position", customType)],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        // __index uses PushCode with {value} replaced by self->position
        Assert.Contains("self->position.x", code);
        Assert.Contains("self->position.y", code);
        Assert.Contains("lua_newtable(L)", code);
    }

    [Fact]
    public void Generate_CustomField_UsesSetCodeInNewindex()
    {
        var customType = new BindingType.Custom(
            "b2Vec2", "number[]", null, null,
            "lua_newtable(L);\n        lua_pushnumber(L, {value}.x); lua_rawseti(L, -2, 1);\n        return 1",
            "luaL_checktype(L, 3, LUA_TTABLE);\n            lua_rawgeti(L, 3, 1); self->{fieldName}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n            lua_rawgeti(L, 3, 2); self->{fieldName}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1)");
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null,
            [new StructBinding("b2BodyDef", "BodyDef", "b2d.BodyDef", true,
                [new FieldBinding("gravity", "gravity", customType)],
                null)],
            [], [], []);
        var code = CBindingGen.Generate(spec);
        // __newindex uses SetCode with {fieldName} replaced by gravity
        Assert.Contains("self->gravity.x", code);
        Assert.Contains("self->gravity.y", code);
        Assert.Contains("luaL_checktype(L, 3, LUA_TTABLE)", code);
    }

    // ===== Custom 型パラメータ =====

    [Fact]
    public void Generate_CustomParam_UsesCheckCode()
    {
        var customType = new BindingType.Custom(
            "b2Vec2", "number[]", null,
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n    b2Vec2 {name};\n    lua_rawgeti(L, {idx}, 1); {name}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n    lua_rawgeti(L, {idx}, 2); {name}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);",
            null, null);
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null,
            [],
            [new FuncBinding("b2Body_SetPosition", "BodySetPosition",
                [new ParamBinding("pos", customType)],
                new BindingType.Void(), null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("luaL_checktype(L, 1, LUA_TTABLE)", code);
        Assert.Contains("b2Vec2 pos", code);
        Assert.Contains("pos.x = (float)lua_tonumber(L, -1)", code);
    }

    // ===== Custom 型戻り値 =====

    [Fact]
    public void Generate_CustomReturn_UsesPushCode()
    {
        var customType = new BindingType.Custom(
            "b2Vec2", "number[]", null, null,
            "b2Vec2 _tmp = {value};\n    lua_newtable(L);\n    lua_pushnumber(L, _tmp.x); lua_rawseti(L, -2, 1);\n    lua_pushnumber(L, _tmp.y); lua_rawseti(L, -2, 2);",
            null);
        var spec = new ModuleSpec(
            "b2d", "b2", ["box2d.h"], null,
            [],
            [new FuncBinding("b2Body_GetPosition", "BodyGetPosition",
                [new ParamBinding("bodyId", new BindingType.Struct("b2BodyId", "b2d.BodyId", "b2d.BodyId"))],
                customType, null)],
            [], []);
        var code = CBindingGen.Generate(spec);
        Assert.Contains("b2Body_GetPosition(bodyId)", code);
        Assert.Contains("lua_newtable(L)", code);
        Assert.Contains("lua_pushnumber(L, _tmp.x)", code);
        Assert.Contains("return 1", code);
    }
}
