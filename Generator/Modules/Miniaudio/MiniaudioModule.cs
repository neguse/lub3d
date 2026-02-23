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
            // ma_vfs = typedef void ma_vfs → ma_vfs* = void*
            Types.Ptr(Types.StructRef("ma_vfs")) => new BindingType.VoidPtr(),
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
                var itemName = Pipeline.EnumItemName(i.Name, e.Name, Prefix).ToUpper();
                return new EnumItemBinding(itemName, i.Name, resolvedVal);
            }).ToList();
            enums.Add(new EnumBinding(e.Name, luaName, fieldName, items, GetLink(e, sourceLink)));
        }

        // Structs — ma_engine_config のみ
        var structs = new List<StructBinding>();
        var allowedStructs = new HashSet<string> { "ma_engine_config" };
        foreach (var s in reg.OwnStructs)
        {
            if (!allowedStructs.Contains(s.Name)) continue;
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(Pipeline.StripPrefix(s.Name, Prefix)));
            var metatable = $"{ModuleName}.{pascalName}";
            var fields = s.Fields.Select(f => new FieldBinding(
                f.Name,
                Pipeline.ToSnakeCase(f.Name),
                Resolve(f.ParsedType)
            )).ToList();
            structs.Add(new StructBinding(
                s.Name, pascalName, metatable,
                false, fields, null));
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
                var luaName = Pipeline.StripPrefix(f.Name, otDef.CName + "_");
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
            structs, [], enums,
            [("sound_init_from_file", "l_ma_sound_new"), ("vfs_new", "l_ma_vfs_new")],
            opaqueTypes,
            ExtraLuaFuncs:
            [
                new FuncBinding("l_ma_sound_new", "sound_init_from_file",
                    [
                        new ParamBinding("engine", new BindingType.Struct("ma_engine", "miniaudio.Engine", "miniaudio.Engine")),
                        new ParamBinding("filePath", new BindingType.Str()),
                        new ParamBinding("flags", new BindingType.Int(), IsOptional: true),
                    ],
                    new BindingType.Struct("ma_sound", "miniaudio.Sound", "miniaudio.Sound"), null),
                new FuncBinding("l_ma_vfs_new", "vfs_new",
                    [
                        new ParamBinding("callbacks", new BindingType.Custom(
                            "lua_State*", "table",
                            null, null, null, null)),
                    ],
                    new BindingType.VoidPtr(), null),
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
            ma_sound** pp = (ma_sound**)lua_newuserdatauv(L, sizeof(ma_sound*), 1);
            *pp = p;
            luaL_setmetatable(L, "miniaudio.Sound");
            lua_pushvalue(L, 1);
            lua_setiuservalue(L, -2, 1);
            return 1;
        }

        /*
         * LuaVfsContext — Lua callback VFS for miniaudio
         *
         * Same pattern as sokol_app LuaCallbackContext:
         * - Lua table with onOpen/onRead/onSeek/onTell/onClose/onInfo callbacks
         * - C trampolines call Lua functions via registry ref
         * - File handles are Lua values stored as registry refs
         */
        typedef struct {
            ma_vfs_callbacks cb;
            lua_State* L;
            int table_ref;  /* registry ref to callback table */
        } LuaVfsContext;

        static ma_result lua_vfs_onOpen(ma_vfs* pVFS, const char* pFilePath, ma_uint32 openMode, ma_vfs_file* pFile) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            (void)openMode;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onOpen");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_ERROR; }
            lua_pushstring(L, pFilePath);
            if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
            if (lua_isnil(L, -1)) { lua_pop(L, 1); return MA_DOES_NOT_EXIST; }
            /* Store returned handle as registry ref */
            int ref = luaL_ref(L, LUA_REGISTRYINDEX);
            *pFile = (ma_vfs_file)(intptr_t)ref;
            return MA_SUCCESS;
        }

        static ma_result lua_vfs_onOpenW(ma_vfs* pVFS, const wchar_t* pFilePath, ma_uint32 openMode, ma_vfs_file* pFile) {
            (void)pVFS; (void)pFilePath; (void)openMode; (void)pFile;
            return MA_NOT_IMPLEMENTED;
        }

        static ma_result lua_vfs_onClose(ma_vfs* pVFS, ma_vfs_file file) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            int ref = (int)(intptr_t)file;
            /* Call onClose if provided */
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onClose");
            lua_remove(L, -2);
            if (lua_isfunction(L, -1)) {
                lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
                lua_pcall(L, 1, 0, 0);
            } else {
                lua_pop(L, 1);
            }
            luaL_unref(L, LUA_REGISTRYINDEX, ref);
            return MA_SUCCESS;
        }

        static ma_result lua_vfs_onRead(ma_vfs* pVFS, ma_vfs_file file, void* pDst, size_t sizeInBytes, size_t* pBytesRead) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            int ref = (int)(intptr_t)file;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onRead");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_ERROR; }
            lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
            lua_pushinteger(L, (lua_Integer)sizeInBytes);
            if (lua_pcall(L, 2, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
            if (lua_isnil(L, -1)) { lua_pop(L, 1); if (pBytesRead) *pBytesRead = 0; return MA_AT_END; }
            size_t len;
            const char* data = lua_tolstring(L, -1, &len);
            if (len > sizeInBytes) len = sizeInBytes;
            memcpy(pDst, data, len);
            if (pBytesRead) *pBytesRead = len;
            lua_pop(L, 1);
            return MA_SUCCESS;
        }

        static ma_result lua_vfs_onWrite(ma_vfs* pVFS, ma_vfs_file file, const void* pSrc, size_t sizeInBytes, size_t* pBytesWritten) {
            (void)pVFS; (void)file; (void)pSrc; (void)sizeInBytes; (void)pBytesWritten;
            return MA_NOT_IMPLEMENTED;
        }

        static ma_result lua_vfs_onSeek(ma_vfs* pVFS, ma_vfs_file file, ma_int64 offset, ma_seek_origin origin) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            int ref = (int)(intptr_t)file;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onSeek");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
            lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
            lua_pushinteger(L, (lua_Integer)offset);
            lua_pushinteger(L, (lua_Integer)origin);
            if (lua_pcall(L, 3, 0, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
            return MA_SUCCESS;
        }

        static ma_result lua_vfs_onTell(ma_vfs* pVFS, ma_vfs_file file, ma_int64* pCursor) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            int ref = (int)(intptr_t)file;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onTell");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
            lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
            if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
            *pCursor = (ma_int64)lua_tointeger(L, -1);
            lua_pop(L, 1);
            return MA_SUCCESS;
        }

        static ma_result lua_vfs_onInfo(ma_vfs* pVFS, ma_vfs_file file, ma_file_info* pInfo) {
            LuaVfsContext* ctx = (LuaVfsContext*)pVFS;
            lua_State* L = ctx->L;
            int ref = (int)(intptr_t)file;
            lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->table_ref);
            lua_getfield(L, -1, "onInfo");
            lua_remove(L, -2);
            if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return MA_NOT_IMPLEMENTED; }
            lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
            if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return MA_ERROR; }
            pInfo->sizeInBytes = (ma_uint64)lua_tointeger(L, -1);
            lua_pop(L, 1);
            return MA_SUCCESS;
        }

        /* VfsNew({onOpen=..., onRead=..., ...}) -> lightuserdata (ma_vfs*) */
        static int l_ma_vfs_new(lua_State *L) {
            luaL_checktype(L, 1, LUA_TTABLE);
            LuaVfsContext* ctx = (LuaVfsContext*)lua_newuserdatauv(L, sizeof(LuaVfsContext), 1);
            memset(ctx, 0, sizeof(LuaVfsContext));
            ctx->L = L;
            ctx->cb.onOpen  = lua_vfs_onOpen;
            ctx->cb.onOpenW = lua_vfs_onOpenW;
            ctx->cb.onClose = lua_vfs_onClose;
            ctx->cb.onRead  = lua_vfs_onRead;
            ctx->cb.onWrite = lua_vfs_onWrite;
            ctx->cb.onSeek  = lua_vfs_onSeek;
            ctx->cb.onTell  = lua_vfs_onTell;
            ctx->cb.onInfo  = lua_vfs_onInfo;
            /* Store callback table as registry ref */
            lua_pushvalue(L, 1);
            ctx->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
            /* Also store table as uservalue to prevent GC */
            lua_pushvalue(L, 1);
            lua_setiuservalue(L, -2, 1);
            /* Return the userdata itself (keeps ctx alive via GC) */
            return 1;
        }

        """;

    // ===== Skip declarations =====

    /// <summary>
    /// Prefix-based categorization for unbound functions
    /// </summary>
    private static readonly (string Prefix, string Reason)[] FuncSkipRules = [
        // Memory / allocator
        ("ma_malloc", "low-level allocator: not useful from Lua"),
        ("ma_free", "low-level allocator: not useful from Lua"),
        ("ma_calloc", "low-level allocator: not useful from Lua"),
        ("ma_realloc", "low-level allocator: not useful from Lua"),
        ("ma_aligned_malloc", "low-level allocator: not useful from Lua"),
        ("ma_aligned_free", "low-level allocator: not useful from Lua"),
        // OS primitives
        ("ma_mutex_", "OS primitive: Lua is single-threaded"),
        ("ma_event_", "OS primitive: threading not exposed"),
        ("ma_semaphore_", "OS primitive: threading not exposed"),
        ("ma_spinlock_", "OS primitive: threading not exposed"),
        ("ma_fence_", "OS primitive: threading not exposed"),
        // PCM conversion / DSP primitives
        ("ma_pcm_s16_to_", "PCM format conversion: low-level DSP"),
        ("ma_pcm_s24_to_", "PCM format conversion: low-level DSP"),
        ("ma_pcm_s32_to_", "PCM format conversion: low-level DSP"),
        ("ma_pcm_u8_to_", "PCM format conversion: low-level DSP"),
        ("ma_pcm_f32_to_", "PCM format conversion: low-level DSP"),
        ("ma_pcm_convert", "PCM format conversion: low-level DSP"),
        ("ma_pcm_rb_", "PCM ring buffer: low-level DSP"),
        ("ma_convert_pcm_frames", "PCM format conversion: low-level DSP"),
        ("ma_convert_frames", "frame conversion: low-level DSP"),
        ("ma_interleave_", "PCM interleave: low-level DSP"),
        ("ma_deinterleave_", "PCM deinterleave: low-level DSP"),
        ("ma_mix_pcm_frames", "PCM mixing: low-level DSP"),
        // Volume / clip / silence / copy / blend
        ("ma_apply_volume_factor_", "volume DSP: low-level sample processing"),
        ("ma_copy_and_apply_volume_", "volume DSP: low-level sample processing"),
        ("ma_clip_", "sample clipping: low-level DSP"),
        ("ma_silence_pcm_frames", "PCM silence: low-level DSP"),
        ("ma_copy_pcm_frames", "PCM copy: low-level DSP"),
        ("ma_blend_f32", "sample blend: low-level DSP"),
        ("ma_offset_pcm_frames_", "PCM pointer offset: low-level DSP"),
        // Ring buffer
        ("ma_rb_", "ring buffer: low-level DSP infrastructure"),
        ("ma_duplex_rb_", "duplex ring buffer: low-level device infrastructure"),
        // Filter / DSP nodes
        ("ma_biquad", "biquad filter: low-level DSP node"),
        ("ma_bpf", "band-pass filter: low-level DSP node"),
        ("ma_hpf", "high-pass filter: low-level DSP node"),
        ("ma_lpf", "low-pass filter: low-level DSP node"),
        ("ma_hishelf", "high-shelf filter: low-level DSP node"),
        ("ma_loshelf", "low-shelf filter: low-level DSP node"),
        ("ma_notch", "notch filter: low-level DSP node"),
        ("ma_peak", "peaking EQ filter: low-level DSP node"),
        ("ma_delay", "delay effect: low-level DSP node"),
        // Resampler
        ("ma_resampler_", "resampler: low-level DSP"),
        ("ma_linear_resampler_", "linear resampler: low-level DSP"),
        // Channel converter / map
        ("ma_channel_converter_", "channel converter: low-level DSP"),
        ("ma_channel_map_", "channel map: low-level DSP"),
        ("ma_channel_position_to_string", "channel utils: low-level DSP"),
        // Data converter
        ("ma_data_converter_", "data converter: low-level DSP pipeline"),
        // Data source
        ("ma_data_source_", "data source: low-level node graph API"),
        // Audio buffer
        ("ma_audio_buffer_", "audio buffer: low-level DSP, engine handles internally"),
        // Paged audio buffer
        ("ma_paged_audio_buffer_", "paged audio buffer: low-level resource manager internal"),
        // Panner / fader / gainer / spatializer (low-level DSP, engine handles internally)
        ("ma_panner_", "panner: low-level DSP, engine handles spatialization"),
        ("ma_fader_", "fader: low-level DSP, engine handles fading"),
        ("ma_gainer_", "gainer: low-level DSP, engine handles gain"),
        ("ma_spatializer_listener_", "spatializer listener: low-level DSP, use engine listener API"),
        ("ma_spatializer_", "spatializer: low-level DSP, engine handles spatialization"),
        // Waveform / noise / pulse generators
        ("ma_waveform_", "waveform generator: low-level DSP node"),
        ("ma_noise_", "noise generator: low-level DSP node"),
        ("ma_pulsewave_", "pulse wave generator: low-level DSP node"),
        // Node graph
        ("ma_node_graph_", "node graph: low-level DSP infrastructure"),
        ("ma_node_", "audio node: low-level DSP infrastructure"),
        ("ma_splitter_node_", "splitter node: low-level DSP infrastructure"),
        // Decoder / encoder
        ("ma_decoder_", "decoder: low-level, engine handles decoding"),
        ("ma_encoder_", "encoder: recording not exposed"),
        ("ma_decode_", "decode helper: low-level, engine handles decoding"),
        ("ma_decoding_backend_", "decoding backend: low-level internal"),
        // Device / context
        ("ma_device_", "device API: engine abstracts device management"),
        ("ma_context_", "context API: engine abstracts context management"),
        // Resource manager
        ("ma_resource_manager_", "resource manager: engine handles resources internally"),
        // Job system
        ("ma_job_", "job system: internal threading infrastructure"),
        // Slot allocator
        ("ma_slot_allocator_", "slot allocator: internal memory infrastructure"),
        // Log
        ("ma_log_", "log API: use sokol.log instead"),
        // VFS
        ("ma_vfs_", "VFS API: bound via custom vfs_new wrapper"),
        ("ma_default_vfs_", "VFS API: bound via custom vfs_new wrapper"),
        // Async notification
        ("ma_async_notification_", "async notification: internal threading infrastructure"),
        // Misc utility
        ("ma_get_backend_", "backend query: engine abstracts backends"),
        ("ma_get_bytes_per_", "format utility: low-level DSP"),
        ("ma_get_enabled_backends", "backend query: engine abstracts backends"),
        ("ma_get_format_name", "format utility: low-level DSP"),
        ("ma_is_backend_enabled", "backend query: engine abstracts backends"),
        ("ma_is_loopback_supported", "loopback query: device-level feature"),
        ("ma_calculate_buffer_size_", "buffer size calc: low-level device utility"),
        ("ma_version", "version query: not useful from Lua"),
        ("ma_result_description", "error description: use Lua error handling"),
        ("ma_device_id_equal", "device ID comparison: device API not exposed"),
    ];

    /// <summary>
    /// Specific function names with reasons (for items not matching prefix rules)
    /// </summary>
    private static readonly Dictionary<string, string> FuncSkipNames = new()
    {
        // Engine internals not in high-level API
        ["ma_engine_get_device"] = "engine internal: device access not exposed",
        ["ma_engine_get_endpoint"] = "engine internal: endpoint node not exposed",
        ["ma_engine_get_log"] = "engine internal: use sokol.log",
        ["ma_engine_get_node_graph"] = "engine internal: node graph not exposed",
        ["ma_engine_get_resource_manager"] = "engine internal: resource manager not exposed",
        ["ma_engine_get_time"] = "engine internal: raw engine time, use stm_ timing",
        ["ma_engine_set_time"] = "engine internal: raw engine time, use stm_ timing",
        ["ma_engine_read_pcm_frames"] = "engine internal: low-level PCM read",
        ["ma_engine_play_sound_ex"] = "engine internal: extended play, use play_sound",
        ["ma_engine_node_config_init"] = "engine node: internal DSP node",
        ["ma_engine_node_get_heap_size"] = "engine node: internal DSP node",
        ["ma_engine_node_init"] = "engine node: internal DSP node",
        ["ma_engine_node_init_preallocated"] = "engine node: internal DSP node",
        ["ma_engine_node_uninit"] = "engine node: internal DSP node",
        ["ma_engine_listener_get_cone"] = "output pointer: cone get via multiple out params",
        ["ma_engine_listener_set_cone"] = "cone set: too many params for Lua convenience",
        // Sound internals
        ["ma_sound_config_init"] = "sound config: init handled by sound_init_from_file wrapper",
        ["ma_sound_config_init_2"] = "sound config: init handled by sound_init_from_file wrapper",
        ["ma_sound_init_from_file_w"] = "wide-char variant: not needed, use UTF-8",
        ["ma_sound_init_from_data_source"] = "data source init: low-level, use sound_init_from_file",
        ["ma_sound_init_from_file"] = "bound via custom l_ma_sound_new ExtraCCode wrapper",
        ["ma_sound_init_copy"] = "sound copy: complex ownership, not exposed",
        ["ma_sound_init_ex"] = "extended init: complex config, use sound_init_from_file",
        ["ma_sound_get_cone"] = "output pointer: cone get via multiple out params",
        ["ma_sound_set_cone"] = "cone set: too many params for Lua convenience",
        ["ma_sound_get_cursor_in_pcm_frames"] = "output pointer: returns ma_result + uint64 out param",
        ["ma_sound_get_cursor_in_seconds"] = "output pointer: returns ma_result + float out param",
        ["ma_sound_get_data_format"] = "output pointer: multiple out params",
        ["ma_sound_get_data_source"] = "internal: data source pointer not exposed",
        ["ma_sound_get_direction_to_listener"] = "derived value: compute in Lua if needed",
        ["ma_sound_get_engine"] = "internal: engine pointer not exposed",
        ["ma_sound_get_length_in_pcm_frames"] = "output pointer: returns ma_result + uint64 out param",
        ["ma_sound_get_length_in_seconds"] = "output pointer: returns ma_result + float out param",
        ["ma_sound_set_end_callback"] = "callback: end callback not exposed",
        ["ma_sound_set_fade_start_in_pcm_frames"] = "advanced fade: use set_fade_in_pcm_frames",
        ["ma_sound_set_fade_start_in_milliseconds"] = "advanced fade: use set_fade_in_milliseconds",
        ["ma_sound_set_stop_time_with_fade_in_pcm_frames"] = "advanced fade+stop: use separate set_stop_time + set_fade",
        ["ma_sound_set_stop_time_with_fade_in_milliseconds"] = "advanced fade+stop: use separate set_stop_time + set_fade",
        ["ma_sound_stop_with_fade_in_pcm_frames"] = "advanced fade+stop: use set_fade + stop",
        ["ma_sound_stop_with_fade_in_milliseconds"] = "advanced fade+stop: use set_fade + stop",
        ["ma_sound_reset_fade"] = "advanced fade control: rarely needed",
        ["ma_sound_reset_start_time"] = "advanced timing: rarely needed",
        ["ma_sound_reset_stop_time"] = "advanced timing: rarely needed",
        ["ma_sound_reset_stop_time_and_fade"] = "advanced timing: rarely needed",
        // Sound group (parallel to sound, engine manages internally)
        ["ma_sound_group_config_init"] = "sound group: not exposed, use engine directly",
        ["ma_sound_group_config_init_2"] = "sound group: not exposed",
        ["ma_sound_group_init"] = "sound group: not exposed",
        ["ma_sound_group_init_ex"] = "sound group: not exposed",
        ["ma_sound_group_uninit"] = "sound group: not exposed",
        ["ma_sound_group_start"] = "sound group: not exposed",
        ["ma_sound_group_stop"] = "sound group: not exposed",
        ["ma_sound_group_set_volume"] = "sound group: not exposed",
        ["ma_sound_group_get_volume"] = "sound group: not exposed",
        ["ma_sound_group_set_pan"] = "sound group: not exposed",
        ["ma_sound_group_get_pan"] = "sound group: not exposed",
        ["ma_sound_group_set_pan_mode"] = "sound group: not exposed",
        ["ma_sound_group_get_pan_mode"] = "sound group: not exposed",
        ["ma_sound_group_set_pitch"] = "sound group: not exposed",
        ["ma_sound_group_get_pitch"] = "sound group: not exposed",
        ["ma_sound_group_set_spatialization_enabled"] = "sound group: not exposed",
        ["ma_sound_group_is_spatialization_enabled"] = "sound group: not exposed",
        ["ma_sound_group_set_pinned_listener_index"] = "sound group: not exposed",
        ["ma_sound_group_get_pinned_listener_index"] = "sound group: not exposed",
        ["ma_sound_group_get_listener_index"] = "sound group: not exposed",
        ["ma_sound_group_set_position"] = "sound group: not exposed",
        ["ma_sound_group_get_position"] = "sound group: not exposed",
        ["ma_sound_group_set_direction"] = "sound group: not exposed",
        ["ma_sound_group_get_direction"] = "sound group: not exposed",
        ["ma_sound_group_set_velocity"] = "sound group: not exposed",
        ["ma_sound_group_get_velocity"] = "sound group: not exposed",
        ["ma_sound_group_set_attenuation_model"] = "sound group: not exposed",
        ["ma_sound_group_get_attenuation_model"] = "sound group: not exposed",
        ["ma_sound_group_set_positioning"] = "sound group: not exposed",
        ["ma_sound_group_get_positioning"] = "sound group: not exposed",
        ["ma_sound_group_set_rolloff"] = "sound group: not exposed",
        ["ma_sound_group_get_rolloff"] = "sound group: not exposed",
        ["ma_sound_group_set_min_gain"] = "sound group: not exposed",
        ["ma_sound_group_get_min_gain"] = "sound group: not exposed",
        ["ma_sound_group_set_max_gain"] = "sound group: not exposed",
        ["ma_sound_group_get_max_gain"] = "sound group: not exposed",
        ["ma_sound_group_set_min_distance"] = "sound group: not exposed",
        ["ma_sound_group_get_min_distance"] = "sound group: not exposed",
        ["ma_sound_group_set_max_distance"] = "sound group: not exposed",
        ["ma_sound_group_get_max_distance"] = "sound group: not exposed",
        ["ma_sound_group_set_doppler_factor"] = "sound group: not exposed",
        ["ma_sound_group_get_doppler_factor"] = "sound group: not exposed",
        ["ma_sound_group_get_directional_attenuation_factor"] = "sound group: not exposed",
        ["ma_sound_group_set_directional_attenuation_factor"] = "sound group: not exposed",
        ["ma_sound_group_set_fade_in_pcm_frames"] = "sound group: not exposed",
        ["ma_sound_group_set_fade_in_milliseconds"] = "sound group: not exposed",
        ["ma_sound_group_set_start_time_in_pcm_frames"] = "sound group: not exposed",
        ["ma_sound_group_set_start_time_in_milliseconds"] = "sound group: not exposed",
        ["ma_sound_group_set_stop_time_in_pcm_frames"] = "sound group: not exposed",
        ["ma_sound_group_set_stop_time_in_milliseconds"] = "sound group: not exposed",
        ["ma_sound_group_is_playing"] = "sound group: not exposed",
        ["ma_sound_group_get_time_in_pcm_frames"] = "sound group: not exposed",
        ["ma_sound_group_get_current_fade_volume"] = "sound group: not exposed",
        ["ma_sound_group_get_cone"] = "sound group: not exposed",
        ["ma_sound_group_set_cone"] = "sound group: not exposed",
        ["ma_sound_group_get_direction_to_listener"] = "sound group: not exposed",
        ["ma_sound_group_get_engine"] = "sound group: not exposed",
        // Sound inlined struct
        ["ma_sound_inlined"] = "internal: inlined sound struct",
        // Engine config (bound via config struct)
        ["ma_engine_config_init"] = "bound via EngineConfig struct init",
        // Stack allocator
        ["ma_stack"] = "internal: stack allocator",
    };

    SkipReport IModule.CollectSkips(TypeRegistry reg)
    {
        // Build bound func set
        var boundFuncs = new HashSet<string>();
        foreach (var ot in OpaqueTypeDefs)
        {
            if (ot.InitFunc != null) boundFuncs.Add(ot.InitFunc);
            if (ot.UninitFunc != null) boundFuncs.Add(ot.UninitFunc);
            if (ot.ConfigInitFunc != null) boundFuncs.Add(ot.ConfigInitFunc);
            var whitelist = FuncWhitelist.GetValueOrDefault(ot.CName) ?? [];
            foreach (var name in whitelist) boundFuncs.Add(name);
        }

        var skipFuncs = new List<SkipEntry>();
        foreach (var f in reg.OwnFuncs)
        {
            if (boundFuncs.Contains(f.Name)) continue;

            // Check name-specific reasons first
            if (FuncSkipNames.TryGetValue(f.Name, out var nameReason))
            {
                skipFuncs.Add(new SkipEntry(f.Name, nameReason));
                continue;
            }

            // Check prefix-based rules
            var matched = false;
            foreach (var (prefix, reason) in FuncSkipRules)
            {
                if (f.Name.StartsWith(prefix) || f.Name == prefix)
                {
                    skipFuncs.Add(new SkipEntry(f.Name, reason));
                    matched = true;
                    break;
                }
            }
            if (!matched)
            {
                skipFuncs.Add(new SkipEntry(f.Name, "low-level internal: not in high-level engine API scope"));
            }
        }

        // Build bound struct set
        var boundStructs = new HashSet<string> { "ma_engine_config" };
        foreach (var ot in OpaqueTypeDefs)
            boundStructs.Add(ot.CName);

        var skipStructReasons = new Dictionary<string, string>
        {
            ["ma_sound_config"] = "sound config: handled internally by sound_init_from_file",
            ["ma_sound_group_config"] = "sound group: not exposed",
            ["ma_engine_node_config"] = "engine node: internal DSP node config",
            ["ma_engine_node"] = "engine node: internal DSP node",
            ["ma_vec3f"] = "math type: internal 3D vector, use lib/glm.lua",
        };

        var skipStructs = new List<SkipEntry>();
        foreach (var s in reg.OwnStructs)
        {
            if (boundStructs.Contains(s.Name)) continue;
            var reason = skipStructReasons.GetValueOrDefault(s.Name, "low-level internal: not in high-level engine API scope");
            skipStructs.Add(new SkipEntry(s.Name, reason));
        }

        // Build bound enum set
        var skipEnums = new List<SkipEntry>();
        foreach (var e in reg.OwnEnums)
        {
            if (AllowedEnums.Contains(e.Name)) continue;
            skipEnums.Add(new SkipEntry(e.Name, "low-level internal: not in high-level engine API scope"));
        }

        return new SkipReport(ModuleName, skipFuncs, skipStructs, skipEnums);
    }

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
