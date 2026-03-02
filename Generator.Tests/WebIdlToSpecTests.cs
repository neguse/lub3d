using Generator;
using Generator.CBinding;
using Generator.LuaCats;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlToSpecTests
{
    private const string SokolTimeIdl = """
        // sokol_time — timing functions
        [Prefix="stm_", CInclude="sokol_time.h"]
        namespace stm {
            void setup();
            unsigned long long now();
            unsigned long long diff(unsigned long long new_ticks, unsigned long long old_ticks);
            unsigned long long since(unsigned long long start_ticks);
            unsigned long long round_to_common_refresh_rate(unsigned long long frame_ticks);
            double sec(unsigned long long ticks);
            double ms(unsigned long long ticks);
            double us(unsigned long long ticks);
            double ns(unsigned long long ticks);
        };
        """;

    private static ModuleSpec BuildSpec()
    {
        var def = WebIdlParser.Parse(SokolTimeIdl);
        return WebIdlToSpec.Convert(def, "sokol.time");
    }

    // ─── Converter unit tests ───

    [Fact]
    public void Convert_ModuleName()
    {
        var spec = BuildSpec();
        Assert.Equal("sokol.time", spec.ModuleName);
    }

    [Fact]
    public void Convert_Prefix()
    {
        var spec = BuildSpec();
        Assert.Equal("stm_", spec.Prefix);
    }

    [Fact]
    public void Convert_CIncludes()
    {
        var spec = BuildSpec();
        Assert.Contains("sokol_time.h", spec.CIncludes);
    }

    [Fact]
    public void Convert_FuncCount()
    {
        var spec = BuildSpec();
        Assert.Equal(9, spec.Funcs.Count);
    }

    [Fact]
    public void Convert_CNames()
    {
        var spec = BuildSpec();
        var names = spec.Funcs.Select(f => f.CName).ToList();
        Assert.Contains("stm_setup", names);
        Assert.Contains("stm_now", names);
        Assert.Contains("stm_diff", names);
        Assert.Contains("stm_since", names);
        Assert.Contains("stm_round_to_common_refresh_rate", names);
        Assert.Contains("stm_sec", names);
        Assert.Contains("stm_ms", names);
        Assert.Contains("stm_us", names);
        Assert.Contains("stm_ns", names);
    }

    [Fact]
    public void Convert_LuaNames()
    {
        var spec = BuildSpec();
        var names = spec.Funcs.Select(f => f.LuaName).ToList();
        Assert.Contains("setup", names);
        Assert.Contains("now", names);
        Assert.Contains("diff", names);
        Assert.Contains("sec", names);
    }

    [Fact]
    public void Convert_EmptyStructsAndEnums()
    {
        var spec = BuildSpec();
        Assert.Empty(spec.Structs);
        Assert.Empty(spec.Enums);
        Assert.Empty(spec.OpaqueTypes);
    }

    [Fact]
    public void Convert_ReturnTypes()
    {
        var spec = BuildSpec();
        Assert.IsType<BindingType.Void>(spec.Funcs.First(f => f.LuaName == "setup").ReturnType);
        Assert.IsType<BindingType.UInt64>(spec.Funcs.First(f => f.LuaName == "now").ReturnType);
        Assert.IsType<BindingType.Double>(spec.Funcs.First(f => f.LuaName == "sec").ReturnType);
    }

    [Fact]
    public void Convert_ParamTypes()
    {
        var spec = BuildSpec();
        var diff = spec.Funcs.First(f => f.LuaName == "diff");
        Assert.Equal(2, diff.Params.Count);
        Assert.IsType<BindingType.UInt64>(diff.Params[0].Type);
        Assert.IsType<BindingType.UInt64>(diff.Params[1].Type);
        Assert.Equal("new_ticks", diff.Params[0].Name);
        Assert.Equal("old_ticks", diff.Params[1].Name);
    }

    // ─── E2E: CBindingGen output ───

    [Fact]
    public void E2E_CBinding_ContainsLuaHeader()
    {
        var code = CBindingGen.Generate(BuildSpec());
        Assert.Contains("#include <lua.h>", code);
        Assert.Contains("#include \"sokol_time.h\"", code);
    }

    [Fact]
    public void E2E_CBinding_ContainsFunctions()
    {
        var code = CBindingGen.Generate(BuildSpec());
        Assert.Contains("l_stm_setup", code);
        Assert.Contains("l_stm_now", code);
        Assert.Contains("l_stm_diff", code);
        Assert.Contains("l_stm_since", code);
        Assert.Contains("l_stm_round_to_common_refresh_rate", code);
        Assert.Contains("l_stm_sec", code);
        Assert.Contains("l_stm_ms", code);
        Assert.Contains("l_stm_us", code);
        Assert.Contains("l_stm_ns", code);
    }

    [Fact]
    public void E2E_CBinding_VoidFunction()
    {
        var code = CBindingGen.Generate(BuildSpec());
        // setup() は引数なし、戻り値void
        Assert.Contains("stm_setup()", code);
        Assert.Contains("return 0;", code);
    }

    [Fact]
    public void E2E_CBinding_UInt64Params()
    {
        var code = CBindingGen.Generate(BuildSpec());
        // uint64_t 引数は luaL_checkinteger でチェック
        Assert.Contains("uint64_t new_ticks = (uint64_t)luaL_checkinteger(L, 1)", code);
        Assert.Contains("uint64_t old_ticks = (uint64_t)luaL_checkinteger(L, 2)", code);
    }

    [Fact]
    public void E2E_CBinding_UInt64Return()
    {
        var code = CBindingGen.Generate(BuildSpec());
        // uint64_t 戻り値は lua_pushinteger
        Assert.Contains("lua_pushinteger(L, (lua_Integer)stm_now())", code);
    }

    [Fact]
    public void E2E_CBinding_DoubleReturn()
    {
        var code = CBindingGen.Generate(BuildSpec());
        // double 戻り値は lua_pushnumber
        Assert.Contains("lua_pushnumber(L, (lua_Number)stm_sec(ticks))", code);
    }

    [Fact]
    public void E2E_CBinding_FuncTable()
    {
        var code = CBindingGen.Generate(BuildSpec());
        Assert.Contains("sokol_time_funcs[]", code);
        Assert.Contains("{\"setup\", l_stm_setup}", code);
        Assert.Contains("{\"now\", l_stm_now}", code);
        Assert.Contains("{NULL, NULL}", code);
    }

    [Fact]
    public void E2E_CBinding_Luaopen()
    {
        var code = CBindingGen.Generate(BuildSpec());
        Assert.Contains("luaopen_sokol_time", code);
        Assert.Contains("luaL_newlib(L, sokol_time_funcs)", code);
    }

    // ─── E2E: LuaCatsGen output ───

    [Fact]
    public void E2E_LuaCats_ContainsMeta()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@meta", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsClass()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@class sokol_time_module", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsVoidFunc()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@field setup fun()", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsIntegerReturn()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@field now fun(): integer", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsIntegerParams()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@field diff fun(new_ticks: integer, old_ticks: integer): integer", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsNumberReturn()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("---@field sec fun(ticks: integer): number", lua);
    }

    [Fact]
    public void E2E_LuaCats_ContainsReturnM()
    {
        var lua = LuaCatsGen.Generate(BuildSpec());
        Assert.Contains("return M", lua);
    }
}
