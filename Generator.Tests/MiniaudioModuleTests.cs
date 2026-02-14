using Generator;
using Generator.ClangAst;
using Generator.Modules.Miniaudio;

namespace Generator.Tests;

public class MiniaudioModuleTests
{
    private static readonly Dictionary<string, string> PrefixToModule = new()
    {
        ["ma_"] = "miniaudio",
    };

    /// <summary>
    /// miniaudio の主要 API を模した最小 JSON fixture
    /// </summary>
    private static string MiniaudioJson => """
    {
        "module": "miniaudio",
        "prefix": "ma_",
        "dep_prefixes": [],
        "decls": [
            {
                "kind": "enum",
                "name": "ma_result",
                "items": [
                    {"name": "MA_SUCCESS", "value": "0"},
                    {"name": "MA_ERROR", "value": "-1"}
                ],
                "is_dep": false
            },
            {
                "kind": "enum",
                "name": "ma_sound_flags",
                "items": [
                    {"name": "MA_SOUND_FLAG_STREAM", "value": "1"},
                    {"name": "MA_SOUND_FLAG_DECODE", "value": "2"}
                ],
                "is_dep": false
            },
            {
                "kind": "enum",
                "name": "ma_format",
                "items": [
                    {"name": "ma_format_f32", "value": "5"}
                ],
                "is_dep": false
            },
            {
                "kind": "struct",
                "name": "ma_engine",
                "fields": [],
                "is_dep": false
            },
            {
                "kind": "struct",
                "name": "ma_engine_config",
                "fields": [],
                "is_dep": false
            },
            {
                "kind": "struct",
                "name": "ma_sound",
                "fields": [],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_config_init",
                "type": "ma_engine_config (void)",
                "params": [],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_init",
                "type": "ma_result (const ma_engine_config *, ma_engine *)",
                "params": [
                    {"name": "pConfig", "type": "const ma_engine_config *"},
                    {"name": "pEngine", "type": "ma_engine *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_uninit",
                "type": "void (ma_engine *)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_start",
                "type": "ma_result (ma_engine *)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_stop",
                "type": "ma_result (ma_engine *)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_set_volume",
                "type": "ma_result (ma_engine *, float)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"},
                    {"name": "volume", "type": "float"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_get_volume",
                "type": "float (ma_engine *)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_engine_play_sound",
                "type": "ma_result (ma_engine *, const char *, ma_sound_group *)",
                "params": [
                    {"name": "pEngine", "type": "ma_engine *"},
                    {"name": "pFilePath", "type": "const char *"},
                    {"name": "pGroup", "type": "ma_sound_group *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_sound_start",
                "type": "ma_result (ma_sound *)",
                "params": [
                    {"name": "pSound", "type": "ma_sound *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_sound_set_volume",
                "type": "void (ma_sound *, float)",
                "params": [
                    {"name": "pSound", "type": "ma_sound *"},
                    {"name": "volume", "type": "float"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_sound_get_volume",
                "type": "float (const ma_sound *)",
                "params": [
                    {"name": "pSound", "type": "const ma_sound *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_sound_is_looping",
                "type": "bool (const ma_sound *)",
                "params": [
                    {"name": "pSound", "type": "const ma_sound *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_sound_set_looping",
                "type": "void (ma_sound *, bool)",
                "params": [
                    {"name": "pSound", "type": "ma_sound *"},
                    {"name": "isLooping", "type": "bool"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_device_init",
                "type": "ma_result (ma_context *, const ma_device_config *, ma_device *)",
                "params": [
                    {"name": "pContext", "type": "ma_context *"},
                    {"name": "pConfig", "type": "const ma_device_config *"},
                    {"name": "pDevice", "type": "ma_device *"}
                ],
                "is_dep": false
            },
            {
                "kind": "func",
                "name": "ma_decoder_init_file",
                "type": "ma_result (const char *, const ma_decoder_config *, ma_decoder *)",
                "params": [
                    {"name": "pFilePath", "type": "const char *"},
                    {"name": "pConfig", "type": "const ma_decoder_config *"},
                    {"name": "pDecoder", "type": "ma_decoder *"}
                ],
                "is_dep": false
            }
        ]
    }
    """;

    private ModuleSpec BuildTestSpec()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        return mod.BuildSpec(reg, PrefixToModule);
    }

    // ===== Enum tests =====

    [Fact]
    public void BuildSpec_ContainsAllowedEnums()
    {
        var spec = BuildTestSpec();
        Assert.Contains(spec.Enums, e => e.CName == "ma_result");
        Assert.Contains(spec.Enums, e => e.CName == "ma_sound_flags");
    }

    [Fact]
    public void BuildSpec_ExcludesNonAllowedEnums()
    {
        var spec = BuildTestSpec();
        Assert.DoesNotContain(spec.Enums, e => e.CName == "ma_format");
    }

    [Fact]
    public void BuildSpec_EnumItems()
    {
        var spec = BuildTestSpec();
        var result = spec.Enums.First(e => e.CName == "ma_result");
        Assert.Contains(result.Items, i => i.CConstName == "MA_SUCCESS");
        Assert.Contains(result.Items, i => i.CConstName == "MA_ERROR");
    }

    // ===== Opaque type: Engine =====

    [Fact]
    public void BuildSpec_ContainsEngineOpaqueType()
    {
        var spec = BuildTestSpec();
        Assert.Contains(spec.OpaqueTypes, ot => ot.CName == "ma_engine");
    }

    [Fact]
    public void BuildSpec_Engine_HasLifecycle()
    {
        var spec = BuildTestSpec();
        var engine = spec.OpaqueTypes.First(ot => ot.CName == "ma_engine");
        Assert.Equal("ma_engine_init", engine.InitFunc);
        Assert.Equal("ma_engine_uninit", engine.UninitFunc);
        Assert.Equal("ma_engine_config", engine.ConfigType);
        Assert.Equal("ma_engine_config_init", engine.ConfigInitFunc);
    }

    [Fact]
    public void BuildSpec_Engine_HasMethods()
    {
        var spec = BuildTestSpec();
        var engine = spec.OpaqueTypes.First(ot => ot.CName == "ma_engine");
        Assert.Contains(engine.Methods, m => m.CName == "ma_engine_start");
        Assert.Contains(engine.Methods, m => m.CName == "ma_engine_stop");
        Assert.Contains(engine.Methods, m => m.CName == "ma_engine_set_volume");
        Assert.Contains(engine.Methods, m => m.CName == "ma_engine_get_volume");
        Assert.Contains(engine.Methods, m => m.CName == "ma_engine_play_sound");
    }

    [Fact]
    public void BuildSpec_Engine_Method_SelfExcluded()
    {
        var spec = BuildTestSpec();
        var engine = spec.OpaqueTypes.First(ot => ot.CName == "ma_engine");
        var start = engine.Methods.First(m => m.CName == "ma_engine_start");
        Assert.Empty(start.Params);
    }

    [Fact]
    public void BuildSpec_Engine_SetVolume_HasParam()
    {
        var spec = BuildTestSpec();
        var engine = spec.OpaqueTypes.First(ot => ot.CName == "ma_engine");
        var setVol = engine.Methods.First(m => m.CName == "ma_engine_set_volume");
        Assert.Single(setVol.Params);
        Assert.Equal("volume", setVol.Params[0].Name);
        Assert.IsType<BindingType.Float>(setVol.Params[0].Type);
    }

    [Fact]
    public void BuildSpec_Engine_PlaySound_MethodName()
    {
        var spec = BuildTestSpec();
        var engine = spec.OpaqueTypes.First(ot => ot.CName == "ma_engine");
        var playSound = engine.Methods.First(m => m.CName == "ma_engine_play_sound");
        Assert.Equal("play_sound", playSound.LuaName);
    }

    // ===== Opaque type: Sound =====

    [Fact]
    public void BuildSpec_ContainsSoundOpaqueType()
    {
        var spec = BuildTestSpec();
        Assert.Contains(spec.OpaqueTypes, ot => ot.CName == "ma_sound");
    }

    [Fact]
    public void BuildSpec_Sound_HasNoInit()
    {
        var spec = BuildTestSpec();
        var sound = spec.OpaqueTypes.First(ot => ot.CName == "ma_sound");
        Assert.Null(sound.InitFunc);
        Assert.Equal("ma_sound_uninit", sound.UninitFunc);
    }

    [Fact]
    public void BuildSpec_Sound_HasMethods()
    {
        var spec = BuildTestSpec();
        var sound = spec.OpaqueTypes.First(ot => ot.CName == "ma_sound");
        Assert.Contains(sound.Methods, m => m.CName == "ma_sound_start");
        Assert.Contains(sound.Methods, m => m.CName == "ma_sound_set_volume");
        Assert.Contains(sound.Methods, m => m.CName == "ma_sound_get_volume");
        Assert.Contains(sound.Methods, m => m.CName == "ma_sound_is_looping");
        Assert.Contains(sound.Methods, m => m.CName == "ma_sound_set_looping");
    }

    // ===== Negative: excluded APIs =====

    [Fact]
    public void BuildSpec_ExcludesDeviceFuncs()
    {
        var spec = BuildTestSpec();
        var allMethods = spec.OpaqueTypes.SelectMany(ot => ot.Methods).ToList();
        Assert.DoesNotContain(allMethods, m => m.CName == "ma_device_init");
    }

    [Fact]
    public void BuildSpec_ExcludesDecoderFuncs()
    {
        var spec = BuildTestSpec();
        var allMethods = spec.OpaqueTypes.SelectMany(ot => ot.Methods).ToList();
        Assert.DoesNotContain(allMethods, m => m.CName == "ma_decoder_init_file");
    }

    // ===== C code generation =====

    [Fact]
    public void GenerateC_ContainsCheckEngineHelper()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateC(reg, PrefixToModule);
        Assert.Contains("check_ma_engine(lua_State *L, int idx)", code);
    }

    [Fact]
    public void GenerateC_ContainsSoundCustomConstructor()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateC(reg, PrefixToModule);
        Assert.Contains("l_ma_sound_new", code);
        Assert.Contains("ma_sound_init_from_file(", code);
    }

    [Fact]
    public void GenerateC_ContainsLuaOpen()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateC(reg, PrefixToModule);
        Assert.Contains("luaopen_miniaudio", code);
    }

    // ===== Lua code generation =====

    [Fact]
    public void GenerateLua_ContainsEngineClass()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@class miniaudio.Engine", code);
    }

    [Fact]
    public void GenerateLua_ContainsSoundClass()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@class miniaudio.Sound", code);
    }

    [Fact]
    public void GenerateLua_ContainsEnums()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@class miniaudio.Result", code);
        Assert.Contains("---@class miniaudio.SoundFlags", code);
    }

    [Fact]
    public void GenerateLua_ContainsModuleClass()
    {
        var reg = TypeRegistry.FromJson(MiniaudioJson);
        var mod = new MiniaudioModule();
        var code = mod.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@class miniaudio", code);
        Assert.Contains("---@field engine_init fun(config?: miniaudio.EngineConfig): miniaudio.Engine", code);
    }
}
