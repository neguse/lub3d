-- Simple Triangle - Basic rendering example
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local shdc = require("shdc")

local pip, bind
local time = 0

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

function init()
    -- Compile shader
    local result = shdc.compile(shader_source, "triangle", "wgsl")
    if not result.success then
        print("Shader compile error: " .. (result.error or "unknown"))
        return
    end

    local shd = gfx.make_shader(gfx.ShaderDesc({
        vertex_func = { source = result.vs_source },
        fragment_func = { source = result.fs_source },
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 16,  -- rotation (float) padded to 16 bytes
            }
        }
    }))

    pip = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shd,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- position
                { format = gfx.VertexFormat.FLOAT3 },  -- color
            }
        }
    }))

    -- Triangle vertices: position (x, y) + color (r, g, b)
    local vertices = {
         0.0,  0.5,   1.0, 0.0, 0.0,  -- top (red)
         0.5, -0.5,   0.0, 1.0, 0.0,  -- bottom right (green)
        -0.5, -0.5,   0.0, 0.0, 1.0,  -- bottom left (blue)
    }
    local data = string.pack(string.rep("f", #vertices), table.unpack(vertices))
    bind = {
        vertex_buffers = { gfx.make_buffer(gfx.BufferDesc({ data = gfx.Range(data) })) }
    }
end

function frame()
    time = time + 1/60

    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1 }
            }}
        }),
        swapchain = glue.swapchain()
    }))

    gfx.apply_pipeline(pip)
    gfx.apply_bindings(gfx.Bindings(bind))

    -- Pack uniform: rotation (float) padded to 16 bytes
    local uniform_data = string.pack("ffff", time, 0, 0, 0)
    gfx.apply_uniforms(gfx.ShaderStage.VERTEX, gfx.Range(uniform_data))

    gfx.draw(0, 3, 1)
    gfx.end_pass()
    gfx.commit()
end

function cleanup() end
function event(ev) end
