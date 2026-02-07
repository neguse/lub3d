using Generator.ClangAst;
using Generator.Modules.Sokol;

namespace Generator.Tests;

public class ImguiModuleTests
{
    private readonly Imgui _imgui = new();
    private static readonly Dictionary<string, string> PrefixToModule = new()
    {
        ["simgui_"] = "sokol.imgui",
        ["sg_"] = "sokol.gfx",
        ["sapp_"] = "sokol.app",
    };

    private const string ImguiJson = """
    {
      "module": "sokol.imgui",
      "prefix": "simgui_",
      "dep_prefixes": ["sg_", "sapp_"],
      "decls": [
        {
          "kind": "struct",
          "name": "sg_pixel_format",
          "fields": [],
          "is_dep": true,
          "dep_prefix": "sg_"
        },
        {
          "kind": "struct",
          "name": "sg_filter",
          "fields": [],
          "is_dep": true,
          "dep_prefix": "sg_"
        },
        {
          "kind": "struct",
          "name": "sg_view",
          "fields": [],
          "is_dep": true,
          "dep_prefix": "sg_"
        },
        {
          "kind": "struct",
          "name": "sg_sampler",
          "fields": [
            { "name": "id", "type": "uint32_t" }
          ],
          "is_dep": true,
          "dep_prefix": "sg_"
        },
        {
          "kind": "struct",
          "name": "sapp_event",
          "fields": [],
          "is_dep": true,
          "dep_prefix": "sapp_"
        },
        {
          "kind": "enum",
          "name": "sapp_keycode",
          "items": [],
          "is_dep": true,
          "dep_prefix": "sapp_"
        },
        {
          "kind": "struct",
          "name": "simgui_desc_t",
          "fields": [
            { "name": "max_vertices", "type": "int" },
            { "name": "color_format", "type": "sg_pixel_format" },
            { "name": "depth_format", "type": "sg_pixel_format" },
            { "name": "sample_count", "type": "int" },
            { "name": "no_default_font", "type": "bool" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "simgui_frame_desc_t",
          "fields": [
            { "name": "width", "type": "int" },
            { "name": "height", "type": "int" },
            { "name": "delta_time", "type": "double" },
            { "name": "dpi_scale", "type": "float" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "simgui_font_tex_desc_t",
          "fields": [
            { "name": "min_filter", "type": "sg_filter" },
            { "name": "mag_filter", "type": "sg_filter" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "simgui_allocator_t",
          "fields": [
            { "name": "user_data", "type": "void *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "struct",
          "name": "simgui_logger_t",
          "fields": [
            { "name": "user_data", "type": "void *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "enum",
          "name": "simgui_log_item_t",
          "items": [
            { "name": "SIMGUI_LOGITEM_OK", "value": "0" },
            { "name": "SIMGUI_LOGITEM_MALLOC_FAILED", "value": "1" },
            { "name": "SIMGUI_LOGITEM_BUFFER_OVERFLOW", "value": "2" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_setup",
          "type": "void (const simgui_desc_t *)",
          "params": [
            { "name": "desc", "type": "const simgui_desc_t *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_new_frame",
          "type": "void (const simgui_frame_desc_t *)",
          "params": [
            { "name": "desc", "type": "const simgui_frame_desc_t *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_render",
          "type": "void (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_shutdown",
          "type": "void (void)",
          "params": [],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_handle_event",
          "type": "bool (const sapp_event *)",
          "params": [
            { "name": "ev", "type": "const sapp_event *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "simgui_imtextureid",
          "type": "uint64_t (sg_view)",
          "params": [
            { "name": "tex_view", "type": "sg_view" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void GenerateC_ContainsHeader()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("#include \"sokol_imgui.h\"", code);
    }

    [Fact]
    public void GenerateC_ContainsSetupFunc()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("l_simgui_setup", code);
        Assert.Contains("simgui_setup", code);
    }

    [Fact]
    public void GenerateC_ContainsRenderFunc()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("l_simgui_render", code);
    }

    [Fact]
    public void GenerateC_ContainsHandleEvent()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("l_simgui_handle_event", code);
        Assert.Contains("sapp_event", code);
    }

    [Fact]
    public void GenerateC_ContainsDescStruct()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("simgui_desc_t", code);
        Assert.Contains("sokol.imgui.Desc", code);
    }

    [Fact]
    public void GenerateC_IgnoresAllocatorAndLogger()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.DoesNotContain("simgui_allocator_t", code);
        Assert.DoesNotContain("simgui_logger_t", code);
    }

    [Fact]
    public void GenerateC_ContainsEnum()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("MALLOC_FAILED", code);
        Assert.Contains("BUFFER_OVERFLOW", code);
    }

    [Fact]
    public void GenerateC_ContainsLuaOpen()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateC(reg, PrefixToModule);
        Assert.Contains("luaopen_sokol_imgui", code);
    }

    [Fact]
    public void GenerateLua_ContainsLuaCATS()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateLua(reg, PrefixToModule);
        Assert.Contains("---@meta", code);
        Assert.Contains("---@class sokol.imgui", code);
    }

    [Fact]
    public void GenerateLua_ContainsFuncs()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateLua(reg, PrefixToModule);
        Assert.Contains("Setup", code);
        Assert.Contains("Render", code);
        Assert.Contains("Shutdown", code);
        Assert.Contains("HandleEvent", code);
    }

    [Fact]
    public void GenerateLua_ContainsStructs()
    {
        var reg = TypeRegistry.FromJson(ImguiJson);
        var code = _imgui.GenerateLua(reg, PrefixToModule);
        Assert.Contains("sokol.imgui.Desc", code);
        Assert.Contains("sokol.imgui.FrameDesc", code);
        Assert.Contains("sokol.imgui.FontTexDesc", code);
    }
}
