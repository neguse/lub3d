-- doc.lua
-- Documentation display for lub3d CLI (stdout output, no GUI)
--
-- Globals:
--   _lub3d_doc_topic (string or nil) - specific module to inspect

---@type string?
local topic = _lub3d_doc_topic ---@diagnostic disable-line: undefined-global

local modules = {
    { name = "sokol.gfx",       desc = "Graphics/rendering" },
    { name = "sokol.app",       desc = "Window and events" },
    { name = "sokol.glue",      desc = "App-Gfx glue" },
    { name = "sokol.log",       desc = "Logging" },
    { name = "sokol.time",      desc = "Timing" },
    { name = "sokol.gl",        desc = "Immediate-mode graphics" },
    { name = "sokol.debugtext",  desc = "Debug text" },
    { name = "sokol.audio",     desc = "Audio playback" },
    { name = "sokol.shape",     desc = "Shape generation" },
    { name = "miniaudio",       desc = "Audio engine" },
    { name = "stb.image",       desc = "Image loading" },
    { name = "lub3d.fs",        desc = "File system abstraction" },
    { name = "lub3d.licenses",  desc = "Third-party license info" },
    { name = "imgui",           desc = "Dear ImGui API (optional)" },
    { name = "shdc",            desc = "Runtime shader compiler (optional)" },
    { name = "bc7enc",          desc = "BC7 texture encoder (optional)" },
    { name = "lib.glm",        desc = "vec2/vec3/vec4/mat4 math" },
    { name = "lib.gpu",        desc = "GC-safe GPU resource wrappers" },
    { name = "lib.util",       desc = "Shader compilation, texture loading helpers" },
    { name = "lib.audio",      desc = "Shared miniaudio engine creation" },
    { name = "lib.shader",     desc = "Shader utilities" },
    { name = "lib.texture",    desc = "Texture utilities" },
    { name = "lib.hotreload",  desc = "File-watching hot reload" },
    { name = "lib.notify",     desc = "Notification utilities" },
    { name = "lib.log",        desc = "Logging utilities" },
    { name = "lib.render_pipeline", desc = "Render pass management" },
    { name = "lib.render_pass",     desc = "Render pass abstraction" },
    { name = "lib.render_target",   desc = "Render target utilities" },
    { name = "lib.sprite",     desc = "Sprite utilities" },
}

if not topic then
    -- List all modules
    print("lub3d modules:")
    print("")
    for _, m in ipairs(modules) do
        print(string.format("  %-24s %s", m.name, m.desc))
    end
    print("")
    print("Usage: lub3d doc <module>   (e.g. lub3d doc sokol.gfx)")
else
    -- Show exports for a specific module
    local ok, mod = pcall(require, topic)
    if not ok then
        print("Module not found: " .. topic)
        print("(Some modules require optional build flags to be enabled)")
        os.exit(1)
    end
    if type(mod) ~= "table" then
        print(topic .. " = " .. tostring(mod))
        os.exit(0)
    end

    print(topic .. " exports:")
    print("")

    -- Collect and sort keys
    local keys = {}
    for k in pairs(mod) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local v = mod[k]
        local vtype = type(v)
        if vtype == "function" then
            print(string.format("  %s()", k))
        elseif vtype == "table" then
            print(string.format("  %s  [table]", k))
        elseif vtype == "number" or vtype == "string" or vtype == "boolean" then
            print(string.format("  %s = %s", k, tostring(v)))
        else
            print(string.format("  %s  [%s]", k, vtype))
        end
    end
end
