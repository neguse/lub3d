-- Simple Triangle - Basic rendering example
-- Hot-reload safe: uses self.xxx for runtime state
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local shader = require("lib.shader")

local shader_source = [[
@vs vs
in vec2 position;
in vec3 color;
out vec3 v_color;

layout(binding=0) uniform vs_params {
    float rotation;
};

void main() {
    float c = cos(rotation);
    float s = sin(rotation);
    vec2 rotated = vec2(
        position.x * c - position.y * s,
        position.x * s + position.y * c
    );
    gl_Position = vec4(rotated, 0.0, 1.0);
    v_color = color;
}
@end

@fs fs
in vec3 v_color;
out vec4 frag_color;

void main() {
    frag_color = vec4(v_color, 1.0);
}
@end

@program triangle vs fs
]]

local M = {}

M.width = 800
M.height = 600
M.window_title = "Lub3d - Simple Triangle"

function M:init()
    -- Initialize sokol.gfx (once only, cannot be called twice)
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))
    self:create_resources()
end

function M:create_resources()
    -- Compile shader using lib.shader (auto-detects backend language)
    self.shd = shader.compile(shader_source, "triangle", {
        {
            stage = gfx.ShaderStage.VERTEX,
            size = 16, -- rotation (float) padded to 16 bytes
        }
    })
    if not self.shd then
        print("Shader compile error")
        return
    end

    self.pip = gfx.MakePipeline(gfx.PipelineDesc({
        shader = self.shd,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 }, -- position
                { format = gfx.VertexFormat.FLOAT3 }, -- color
            }
        }
    }))

    -- Triangle vertices: position (x, y) + color (r, g, b)
    local vertices = {
        0.0, 0.5, 1.0, 0.0, 0.0,   -- top (red)
        0.5, -0.5, 0.0, 1.0, 0.0,  -- bottom right (green)
        -0.5, -0.5, 0.0, 0.0, 1.0, -- bottom left (blue)
    }
    local data = string.pack(string.rep("f", #vertices), table.unpack(vertices))
    self.bind = {
        vertex_buffers = { gfx.MakeBuffer(gfx.BufferDesc({ data = gfx.Range(data) })) }
    }
    self.time = self.time or 0
end

function M:frame()
    self.time = (self.time or 0) + 1 / 60

    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1 }
            } }
        }),
        swapchain = glue.Swapchain()
    }))

    gfx.ApplyPipeline(self.pip)
    gfx.ApplyBindings(gfx.Bindings(self.bind))

    -- Pack uniform: rotation (float) padded to 16 bytes
    local uniform_data = string.pack("ffff", self.time, 0, 0, 0)
    gfx.ApplyUniforms(0, gfx.Range(uniform_data))

    gfx.Draw(0, 3, 1)
    gfx.EndPass()
    gfx.Commit()
end

function M:cleanup()
    gfx.Shutdown()
end

function M:event(ev)
    if ev.type == app.EventType.KEY_DOWN and ev.key_code == app.Keycode.Q then
        app.Quit()
    end
end

function M:on_reload()
    self:create_resources()
end

return M
