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
                var itemName = Pipeline.EnumItemName(i.Name, e.Name, Prefix);
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
                f.Name,
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
            structs, [], enums,
            [("SoundInitFromFile", "l_ma_sound_new"), ("VfsNew", "l_ma_vfs_new")],
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
                new FuncBinding("l_ma_vfs_new", "VfsNew",
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
            ma_sound** pp = (ma_sound**)lua_newuserdatauv(L, sizeof(ma_sound*), 0);
            *pp = p;
            luaL_setmetatable(L, "miniaudio.Sound");
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
