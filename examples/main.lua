-- mane3d example: rotating colored triangle
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local util = require("lib.util")
local licenses = require("mane3d.licenses")

local t = 0
---@type gfx.Shader?
local shader = nil
---@type gfx.Pipeline?
local pipeline = nil
---@type gfx.Buffer?
local vbuf = nil

-- Shader source (inline GLSL)
local shader_source = [[
@vs vs
in vec2 pos;
in vec4 color0;
out vec4 color;

void main() {
    gl_Position = vec4(pos, 0.5, 1.0);
    color = color0;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program triangle vs fs
]]

function init()
    -- Log license information
    util.log("=== Third-party licenses ===")
    for _, lib in ipairs(licenses.libraries()) do
        util.log(string.format("  %s (%s)", lib.name, lib.type))
    end

    shader = util.compile_shader(shader_source, "triangle")
    if not shader then
        util.log("Shader compilation failed!")
        return
    end

    pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },
                { format = gfx.VertexFormat.FLOAT4 },
            }
        },
        primitive_type = gfx.PrimitiveType.TRIANGLES,
    }))

    if gfx.query_pipeline_state(pipeline) ~= gfx.ResourceState.VALID then
        util.log("Pipeline creation failed!")
        return
    end

    -- Stream buffer for animated vertices
    vbuf = gfx.make_buffer(gfx.BufferDesc({
        size = 18 * 4, -- 18 floats
        usage = { vertex_buffer = true, stream_update = true }
    }))
end

function frame()
    t = t + 1.0 / 60.0
    if not pipeline or not vbuf then return end

    -- Animate vertices
    local vertices = {}
    for i = 0, 2 do
        local angle = t + i * (math.pi * 2 / 3)
        local x = math.cos(angle) * 0.5
        local y = math.sin(angle) * 0.5
        table.insert(vertices, x)
        table.insert(vertices, y)
        local r = math.sin(t + i * 2.0) * 0.5 + 0.5
        local g = math.sin(t + i * 2.0 + 2.0) * 0.5 + 0.5
        local b = math.sin(t + i * 2.0 + 4.0) * 0.5 + 0.5
        table.insert(vertices, r)
        table.insert(vertices, g)
        table.insert(vertices, b)
        table.insert(vertices, 1.0)
    end
    gfx.update_buffer(vbuf, gfx.Range(util.pack_floats(vertices)))

    -- Render
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.2, a = 1.0 }
            } }
        }),
        swapchain = glue.swapchain()
    }))
    gfx.apply_pipeline(pipeline)
    gfx.apply_bindings(gfx.Bindings({ vertex_buffers = { vbuf } }))
    gfx.draw(0, 3, 1)
    gfx.end_pass()
    gfx.commit()
end

function cleanup()
end

function event(ev)
    if ev.type == app.EventType.KEY_DOWN and ev.key_code == app.Keycode.Q then
        app.quit()
    end
end
