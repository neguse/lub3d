namespace Generator.Modules.Miniaudio;

using Generator.ClangAst;

/// <summary>
/// miniaudio High-level Engine API バインディングモジュール
/// SokolModule とは独立した IModule 実装
/// </summary>
public class MiniaudioModule : IModule
{
    public string ModuleName => "miniaudio";
    public string Prefix => "ma_";

    // ===== Opaque 型定義 =====

    private record OpaqueTypeDef(
        string CName,
        string PascalName,
        string? InitFunc,
        string? UninitFunc,
        string? ConfigType,
        string? ConfigInitFunc
    );

    private static readonly OpaqueTypeDef[] OpaqueTypeDefs =
    [
        new("ma_engine", "Engine", "ma_engine_init", "ma_engine_uninit", "ma_engine_config", "ma_engine_config_init"),
        new("ma_sound", "Sound", null, "ma_sound_uninit", null, null),
    ];

    // ===== ホワイトリスト =====

    private static readonly HashSet<string> AllowedEnums = [
        "ma_result",
        "ma_sound_flags",
        "ma_attenuation_model",
        "ma_positioning",
        "ma_pan_mode",
    ];

    /// <summary>
    /// Engine メソッドとして公開する関数 (ma_engine_init/uninit/config_init を除く)
    /// </summary>
    private static readonly HashSet<string> AllowedEngineFuncs = [
        "ma_engine_start",
        "ma_engine_stop",
        "ma_engine_set_volume",
        "ma_engine_get_volume",
        "ma_engine_set_gain_db",
        "ma_engine_get_gain_db",
        "ma_engine_get_channels",
        "ma_engine_get_sample_rate",
        "ma_engine_get_time_in_pcm_frames",
        "ma_engine_get_time_in_milliseconds",
        "ma_engine_set_time_in_pcm_frames",
        "ma_engine_set_time_in_milliseconds",
        "ma_engine_get_listener_count",
        "ma_engine_find_closest_listener",
        "ma_engine_listener_set_position",
        "ma_engine_listener_get_position",
        "ma_engine_listener_set_direction",
        "ma_engine_listener_get_direction",
        "ma_engine_listener_set_velocity",
        "ma_engine_listener_get_velocity",
        "ma_engine_listener_set_world_up",
        "ma_engine_listener_get_world_up",
        "ma_engine_listener_set_enabled",
        "ma_engine_listener_is_enabled",
        "ma_engine_play_sound",
    ];

    /// <summary>
    /// Sound メソッドとして公開する関数 (ma_sound_init*/uninit を除く)
    /// </summary>
    private static readonly HashSet<string> AllowedSoundFuncs = [
        "ma_sound_start",
        "ma_sound_stop",
        "ma_sound_set_volume",
        "ma_sound_get_volume",
        "ma_sound_set_pan",
        "ma_sound_get_pan",
        "ma_sound_set_pan_mode",
        "ma_sound_get_pan_mode",
        "ma_sound_set_pitch",
        "ma_sound_get_pitch",
        "ma_sound_set_spatialization_enabled",
        "ma_sound_is_spatialization_enabled",
        "ma_sound_set_pinned_listener_index",
        "ma_sound_get_pinned_listener_index",
        "ma_sound_get_listener_index",
        "ma_sound_set_position",
        "ma_sound_get_position",
        "ma_sound_set_direction",
        "ma_sound_get_direction",
        "ma_sound_set_velocity",
        "ma_sound_get_velocity",
        "ma_sound_set_attenuation_model",
        "ma_sound_get_attenuation_model",
        "ma_sound_set_positioning",
        "ma_sound_get_positioning",
        "ma_sound_set_rolloff",
        "ma_sound_get_rolloff",
        "ma_sound_set_min_gain",
        "ma_sound_get_min_gain",
        "ma_sound_set_max_gain",
        "ma_sound_get_max_gain",
        "ma_sound_set_min_distance",
        "ma_sound_get_min_distance",
        "ma_sound_set_max_distance",
        "ma_sound_get_max_distance",
        "ma_sound_set_doppler_factor",
        "ma_sound_get_doppler_factor",
        "ma_sound_set_directional_attenuation_factor",
        "ma_sound_get_directional_attenuation_factor",
        "ma_sound_set_fade_in_pcm_frames",
        "ma_sound_set_fade_in_milliseconds",
        "ma_sound_set_start_time_in_pcm_frames",
        "ma_sound_set_start_time_in_milliseconds",
        "ma_sound_set_stop_time_in_pcm_frames",
        "ma_sound_set_stop_time_in_milliseconds",
        "ma_sound_set_looping",
        "ma_sound_is_looping",
        "ma_sound_is_playing",
        "ma_sound_at_end",
        "ma_sound_get_time_in_pcm_frames",
        "ma_sound_get_time_in_milliseconds",
        "ma_sound_seek_to_pcm_frame",
        "ma_sound_seek_to_second",
        "ma_sound_get_current_fade_volume",
    ];

    /// <summary>
    /// Opaque 型ごとの関数 prefix → ホワイトリスト マッピング
    /// </summary>
    private static readonly Dictionary<string, HashSet<string>> FuncWhitelist = new()
    {
        ["ma_engine"] = AllowedEngineFuncs,
        ["ma_sound"] = AllowedSoundFuncs,
    };

    // ===== 型の除外リスト =====

    private static readonly HashSet<string> Ignores = [
        "ma_engine_config",
        "ma_sound_config",
        "ma_sound_group_config",
        "ma_engine_node_config",
        "ma_engine_node",
        "ma_vec3f",
    ];

    // ===== BuildSpec =====

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var enumNames = reg.AllDecls.OfType<Enums>().Select(e => e.Name).ToHashSet();

        // miniaudio typedef → プリミティブ型マッピング
        BindingType Resolve(Types t) => t switch
        {
            Types.Int => new BindingType.Int(),
            Types.Int64 => new BindingType.Int64(),
            Types.UInt32 => new BindingType.UInt32(),
            Types.UInt64 => new BindingType.UInt64(),
            Types.Size => new BindingType.Size(),
            Types.UIntPtr => new BindingType.UIntPtr(),
            Types.IntPtr => new BindingType.IntPtr(),
            Types.Float => new BindingType.Float(),
            Types.Double => new BindingType.Double(),
            Types.Bool => new BindingType.Bool(),
            Types.String => new BindingType.Str(),
            Types.Ptr(Types.Void) => new BindingType.VoidPtr(),
            Types.Ptr(var inner) => new BindingType.Ptr(Resolve(inner)),
            Types.ConstPtr(var inner) => new BindingType.ConstPtr(Resolve(inner)),
            // miniaudio typedef 型
            Types.StructRef("ma_uint8") => new BindingType.UInt32(),
            Types.StructRef("ma_uint16") => new BindingType.UInt32(),
            Types.StructRef("ma_uint32") => new BindingType.UInt32(),
            Types.StructRef("ma_uint64") => new BindingType.UInt64(),
            Types.StructRef("ma_int8") => new BindingType.Int(),
            Types.StructRef("ma_int16") => new BindingType.Int(),
            Types.StructRef("ma_int32") => new BindingType.Int(),
            Types.StructRef("ma_int64") => new BindingType.Int64(),
            Types.StructRef("ma_bool32") => new BindingType.Bool(),
            Types.StructRef("ma_bool8") => new BindingType.Bool(),
            // enum 型
            Types.StructRef(var name) when enumNames.Contains(name) =>
                new BindingType.Enum(name, $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, Prefix))}"),
            // struct 型
            Types.StructRef(var name) =>
                new BindingType.Struct(name,
                    $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(Pipeline.StripPrefix(name, Prefix)))}",
                    $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(Pipeline.StripPrefix(name, Prefix)))}"),
            Types.Void => new BindingType.Void(),
            _ => new BindingType.Void(),
        };

        // Enums
        var enums = new List<EnumBinding>();
        foreach (var e in reg.OwnEnums)
        {
            if (!AllowedEnums.Contains(e.Name)) continue;
            var luaName = $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix))}";
            var fieldName = Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix));
            var next = 0;
            var items = e.Items.Where(i => !i.Name.StartsWith("_")).Select(i =>
            {
                int? val = i.Value != null && int.TryParse(i.Value, out var v) ? v : null;
                var resolvedVal = val ?? next;
                next = resolvedVal + 1;
                var itemName = Pipeline.EnumItemName(i.Name, e.Name, Prefix);
                return new EnumItemBinding(itemName, i.Name, resolvedVal);
            }).ToList();
            enums.Add(new EnumBinding(e.Name, luaName, fieldName, items, GetLink(e, sourceLink)));
        }

        // Opaque types — TypeRegistry の関数を分類
        var opaqueTypes = new List<OpaqueTypeBinding>();
        foreach (var otDef in OpaqueTypeDefs)
        {
            var whitelist = FuncWhitelist.GetValueOrDefault(otDef.CName) ?? [];
            var methods = new List<MethodBinding>();

            foreach (var f in reg.OwnFuncs)
            {
                if (!whitelist.Contains(f.Name)) continue;

                // self パラメータ (第1引数) を除外
                var allParams = f.Params.ToList();
                var methodParams = allParams.Count > 0
                    ? allParams.Skip(1).Select(p => new ParamBinding(p.Name, Resolve(p.ParsedType))).ToList()
                    : [];
                var retType = Resolve(CTypeParser.ParseReturnType(f.TypeStr));
                var luaName = Pipeline.ToPascalCase(
                    Pipeline.StripPrefix(f.Name, otDef.CName + "_"));
                methods.Add(new MethodBinding(f.Name, luaName, methodParams, retType, GetLink(f, sourceLink)));
            }

            opaqueTypes.Add(new OpaqueTypeBinding(
                otDef.CName,
                otDef.PascalName,
                $"{ModuleName}.{otDef.PascalName}",
                $"{ModuleName}.{otDef.PascalName}",
                otDef.InitFunc,
                otDef.UninitFunc,
                otDef.ConfigType,
                otDef.ConfigInitFunc,
                methods,
                null));
        }

        return new ModuleSpec(
            ModuleName, Prefix,
            ["miniaudio.h"],
            ExtraCCode(),
            [], [], enums,
            [("SoundInitFromFile", "l_ma_sound_new")],
            opaqueTypes,
            ExtraLuaFuncs:
            [
                new FuncBinding("l_ma_sound_new", "SoundInitFromFile",
                    [
                        new ParamBinding("engine", new BindingType.Struct("ma_engine", "miniaudio.Engine", "miniaudio.Engine")),
                        new ParamBinding("filePath", new BindingType.Str()),
                        new ParamBinding("flags", new BindingType.Int(), IsOptional: true),
                    ],
                    new BindingType.Struct("ma_sound", "miniaudio.Sound", "miniaudio.Sound"), null),
            ]);
    }

    // ===== IModule 実装 =====

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        var spec = BuildSpec(reg, prefixToModule);
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec(reg, prefixToModule, sourceLink);
        return LuaCats.LuaCatsGen.Generate(spec);
    }

    // ===== ma_sound カスタムコンストラクタ =====

    private static string ExtraCCode() => """
        static ma_sound** check_ma_sound_ptr(lua_State *L, int idx) {
            return (ma_sound**)luaL_checkudata(L, idx, "miniaudio.Sound");
        }

        static int l_ma_sound_new(lua_State *L) {
            ma_engine* engine = check_ma_engine(L, 1);
            const char* filePath = luaL_checkstring(L, 2);
            ma_uint32 flags = (ma_uint32)luaL_optinteger(L, 3, 0);
            ma_sound* p = (ma_sound*)malloc(sizeof(ma_sound));
            memset(p, 0, sizeof(ma_sound));
            ma_result result = ma_sound_init_from_file(engine, filePath, flags, NULL, NULL, p);
            if (result != MA_SUCCESS) {
                free(p);
                return luaL_error(L, "ma_sound_init_from_file failed: %d", result);
            }
            ma_sound** pp = (ma_sound**)lua_newuserdatauv(L, sizeof(ma_sound*), 0);
            *pp = p;
            luaL_setmetatable(L, "miniaudio.Sound");
            return 1;
        }

        """;

    // ===== ヘルパー =====

    private static string? GetLink(Decl d, SourceLink? sourceLink)
    {
        if (sourceLink == null) return null;
        var line = d switch
        {
            Funcs f => f.Line,
            Enums e => e.Line,
            _ => null
        };
        return line is int l ? sourceLink.GetLink(l) : null;
    }
}
