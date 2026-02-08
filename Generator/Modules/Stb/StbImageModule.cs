namespace Generator.Modules.Stb;

using Generator.ClangAst;

/// <summary>
/// stb_image Lua バインディングモジュール
/// Clang AST パース不要 — ModuleSpec を直接構築
/// </summary>
public class StbImageModule : IModule
{
    public string ModuleName => "stb.image";
    public string Prefix => "stbi_";

    public ModuleSpec BuildSpec()
    {
        return new ModuleSpec(
            ModuleName, Prefix,
            ["stb_image.h"],
            ExtraCCode(),
            [], [], [],
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

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        var spec = BuildSpec();
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec();
        return GenerateLuaManual(sourceLink);
    }

    /// <summary>
    /// LuaCATS 型注釈を手書き生成
    /// ExtraLuaFuncs の多値返却パターンは LuaCatsGen の FuncField では表現しにくいため直接生成
    /// </summary>
    private string GenerateLuaManual(SourceLink? sourceLink)
    {
        var src = sourceLink != null ? $" [source]({sourceLink.GetLink(0)})" : "";
        return $$"""
            ---@meta
            -- LuaCATS type definitions for stb.image
            -- Auto-generated, do not edit

            ---@class stb.image
            ---@field load fun(filename: string, desired_channels?: integer): integer, integer, integer, string | nil, string{{src}}
            ---@field load_from_memory fun(buffer: string, desired_channels?: integer): integer, integer, integer, string | nil, string{{src}}
            ---@field info fun(filename: string): integer, integer, integer | nil, string{{src}}
            ---@type stb.image
            local M = {}

            return M
            """;
    }

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
}
