namespace Generator.Modules.Stb;

using Generator.ClangAst;

/// <summary>
/// stb_image Lua バインディングモジュール
/// Clang AST パースで関数を取得し、単純な関数は自動生成、
/// malloc+output params の特殊パターンは ExtraCCode でカスタムラッパー
/// </summary>
public class StbImageModule : IModule
{
    public string ModuleName => "stb.image";
    public string Prefix => "stbi_";

    /// <summary>
    /// 自動生成する関数 (Clang AST から型情報を取得して CBindingGen で生成)
    /// </summary>
    private static readonly HashSet<string> AllowedFuncs =
    [
        "stbi_is_hdr",
        "stbi_is_hdr_from_memory",
        "stbi_is_16_bit",
        "stbi_is_16_bit_from_memory",
        "stbi_failure_reason",
        "stbi_set_flip_vertically_on_load",
        "stbi_set_flip_vertically_on_load_thread",
        "stbi_set_unpremultiply_on_load",
        "stbi_set_unpremultiply_on_load_thread",
        "stbi_convert_iphone_png_to_rgb",
        "stbi_convert_iphone_png_to_rgb_thread",
        "stbi_hdr_to_ldr_gamma",
        "stbi_hdr_to_ldr_scale",
        "stbi_ldr_to_hdr_gamma",
        "stbi_ldr_to_hdr_scale",
    ];

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        // Clang AST から自動生成する関数を抽出
        var funcs = new List<FuncBinding>();
        foreach (var f in reg.OwnFuncs)
        {
            if (!AllowedFuncs.Contains(f.Name)) continue;

            var retType = Resolve(CTypeParser.ParseReturnType(f.TypeStr));
            var parms = f.Params.Select(p => new ParamBinding(p.Name, Resolve(p.ParsedType))).ToList();
            var luaName = Pipeline.StripPrefix(f.Name, Prefix);
            funcs.Add(new FuncBinding(f.Name, luaName, parms, retType, GetLink(f, sourceLink)));
        }

        return new ModuleSpec(
            ModuleName, Prefix,
            ["stb_image.h"],
            ExtraCCode(),
            [], funcs, [],
            [
                ("load", "l_stbi_load"),
                ("load_from_memory", "l_stbi_load_from_memory"),
                ("info", "l_stbi_info"),
            ],
            [],
            ExtraLuaFuncs:
            [
                new FuncBinding("l_stbi_load", "load",
                    [
                        new ParamBinding("filename", new BindingType.Str()),
                        new ParamBinding("desired_channels", new BindingType.Int(), IsOptional: true),
                    ],
                    new BindingType.Void(), null),
                new FuncBinding("l_stbi_load_from_memory", "load_from_memory",
                    [
                        new ParamBinding("buffer", new BindingType.Str()),
                        new ParamBinding("desired_channels", new BindingType.Int(), IsOptional: true),
                    ],
                    new BindingType.Void(), null),
                new FuncBinding("l_stbi_info", "info",
                    [
                        new ParamBinding("filename", new BindingType.Str()),
                    ],
                    new BindingType.Void(), null),
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

    // ===== 型解決 =====

    private static BindingType Resolve(Types t) => t switch
    {
        Types.Int => new BindingType.Int(),
        Types.Float => new BindingType.Float(),
        Types.Bool => new BindingType.Bool(),
        Types.String => new BindingType.Str(),
        Types.Void => new BindingType.Void(),
        Types.ConstPtr(Types.String) => new BindingType.Str(),
        Types.Ptr(Types.Void) => new BindingType.VoidPtr(),
        // stbi_uc = unsigned char, stbi_us = unsigned short — treat as int
        Types.StructRef("stbi_uc") => new BindingType.Int(),
        Types.StructRef("stbi_us") => new BindingType.Int(),
        Types.ConstPtr(Types.StructRef("stbi_uc")) => new BindingType.Str(),
        _ => new BindingType.Void(),
    };

    // ===== カスタムラッパー (malloc + output params) =====

    private static string ExtraCCode() => """
        /* Load image from file
         * Returns: width, height, channels, data (as string)
         * Or nil, error_message on failure
         */
        static int l_stbi_load(lua_State *L) {
            const char *filename = luaL_checkstring(L, 1);
            int desired_channels = (int)luaL_optinteger(L, 2, 4);

            int width, height, channels;
            unsigned char *data = stbi_load(filename, &width, &height, &channels, desired_channels);

            if (!data) {
                lua_pushnil(L);
                lua_pushstring(L, stbi_failure_reason());
                return 2;
            }

            lua_pushinteger(L, width);
            lua_pushinteger(L, height);
            lua_pushinteger(L, desired_channels);
            lua_pushlstring(L, (const char *)data, (size_t)width * height * desired_channels);

            stbi_image_free(data);

            return 4;
        }

        /* Load image from memory (string)
         * Returns: width, height, channels, data (as string)
         * Or nil, error_message on failure
         */
        static int l_stbi_load_from_memory(lua_State *L) {
            size_t len;
            const char *buffer = luaL_checklstring(L, 1, &len);
            int desired_channels = (int)luaL_optinteger(L, 2, 4);

            int width, height, channels;
            unsigned char *data = stbi_load_from_memory(
                (const unsigned char *)buffer, (int)len,
                &width, &height, &channels, desired_channels
            );

            if (!data) {
                lua_pushnil(L);
                lua_pushstring(L, stbi_failure_reason());
                return 2;
            }

            lua_pushinteger(L, width);
            lua_pushinteger(L, height);
            lua_pushinteger(L, desired_channels);
            lua_pushlstring(L, (const char *)data, (size_t)width * height * desired_channels);

            stbi_image_free(data);

            return 4;
        }

        /* Get image info without loading pixel data
         * Returns: width, height, channels
         * Or nil, error_message on failure
         */
        static int l_stbi_info(lua_State *L) {
            const char *filename = luaL_checkstring(L, 1);

            int width, height, channels;
            int ok = stbi_info(filename, &width, &height, &channels);

            if (!ok) {
                lua_pushnil(L);
                lua_pushstring(L, stbi_failure_reason());
                return 2;
            }

            lua_pushinteger(L, width);
            lua_pushinteger(L, height);
            lua_pushinteger(L, channels);

            return 3;
        }

        """;

    // ===== Skip declarations =====

    private static readonly List<SkipEntry> SkippedFuncs = [
        // Handled by custom wrapper (l_stbi_load etc.) — stbi_load, stbi_load_from_memory, stbi_info
        // are tracked as bound via ExtraLuaRegs name recovery
        new("stbi_image_free", "internal: handled by l_stbi_load wrappers"),
        new("stbi_info_from_memory", "output pointer params: use l_stbi_info with file path"),
        // Callback-based I/O
        new("stbi_load_from_callbacks", "callback I/O: Lua has lub3d.fs, use load/load_from_memory"),
        new("stbi_info_from_callbacks", "callback I/O: not useful from Lua"),
        new("stbi_is_hdr_from_callbacks", "callback I/O: not useful from Lua"),
        new("stbi_is_16_bit_from_callbacks", "callback I/O: not useful from Lua"),
        new("stbi_loadf_from_callbacks", "callback I/O: not useful from Lua"),
        new("stbi_load_16_from_callbacks", "callback I/O: not useful from Lua"),
        // FILE*-based I/O (not portable to WASM)
        new("stbi_load_from_file", "FILE* I/O: not portable to WASM, use load"),
        new("stbi_load_from_file_16", "FILE* I/O: not portable to WASM"),
        new("stbi_loadf_from_file", "FILE* I/O: not portable to WASM"),
        new("stbi_info_from_file", "FILE* I/O: not portable to WASM, use info"),
        new("stbi_is_hdr_from_file", "FILE* I/O: not portable to WASM"),
        new("stbi_is_16_bit_from_file", "FILE* I/O: not portable to WASM"),
        // 16-bit / HDR / GIF loading (uncommon use cases)
        new("stbi_load_16", "16-bit loading: uncommon, not needed for game textures"),
        new("stbi_load_16_from_memory", "16-bit loading: uncommon"),
        new("stbi_loadf", "HDR float loading: uncommon"),
        new("stbi_loadf_from_memory", "HDR float loading: uncommon"),
        new("stbi_load_gif_from_memory", "GIF animation: uncommon use case"),
        // zlib internals
        new("stbi_zlib_decode_malloc", "zlib internal: not useful from Lua"),
        new("stbi_zlib_decode_malloc_guesssize", "zlib internal: not useful from Lua"),
        new("stbi_zlib_decode_malloc_guesssize_headerflag", "zlib internal: not useful from Lua"),
        new("stbi_zlib_decode_buffer", "zlib internal: not useful from Lua"),
        new("stbi_zlib_decode_noheader_malloc", "zlib internal: not useful from Lua"),
        new("stbi_zlib_decode_noheader_buffer", "zlib internal: not useful from Lua"),
    ];

    private static readonly List<SkipEntry> SkippedStructs = [
        new("stbi_io_callbacks", "callback I/O struct: not needed, use load/load_from_memory"),
    ];

    SkipReport IModule.CollectSkips(TypeRegistry reg) => new(ModuleName, SkippedFuncs, SkippedStructs, []);

    // ===== ヘルパー =====

    private static string? GetLink(Decl d, SourceLink? sourceLink)
    {
        if (sourceLink == null) return null;
        var line = d switch
        {
            Funcs f => f.Line,
            _ => null
        };
        return line is int l ? sourceLink.GetLink(l) : null;
    }
}
