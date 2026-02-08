-- lub3d example: Simple Triangle with ImGui
-- Minimal example showing basic rendering pipeline
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local log = require("lib.log")
local shaderMod = require("lib.shader")
local imgui = require("imgui")

-- Triangle color (adjustable via ImGui)
local triangle_color = { 1.0, 0.5, 0.2 }
local rotation = 0.0
local rotation_speed = 1.0
local auto_rotate = true

-- Graphics resources
local shader = nil
---@type sokol.gfx.Pipeline
local pipeline = nil
local vbuf = nil

-- Simple triangle shader with vertex colors
local shader_source = [[
@vs vs
in vec2 pos;
in vec3 color;

out vec3 v_color;

layout(binding=0) uniform vs_params {
    vec4 tint;      // xyz = color tint, w = unused
    float rotation; // rotation angle in radians
};

void main() {
    float c = cos(rotation);
    float s = sin(rotation);
    vec2 rotated = vec2(
        pos.x * c - pos.y * s,
        pos.x * s + pos.y * c
    );
    gl_Position = vec4(rotated, 0.0, 1.0);
    v_color = color * tint.xyz;
}
@end

@fs fs
in vec3 v_color;

out vec4 frag_color;

void main() {
    frag_color = vec4(v_color, 1.0);
}
@end

@program simple vs fs
]]

local M = {}
M.width = 800
M.height = 600
M.window_title = "Lub3d - Simple Triangle with ImGui"

function M:init()
    log.info("Simple triangle example init")

    -- Initialize sokol.gfx
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    -- Setup ImGui
    imgui.Setup()

    -- Create triangle vertex buffer
    -- Each vertex: pos (x, y), color (r, g, b)
    local vertices = {
        -- pos          -- color
        0.0, 0.5, 1.0, 0.0, 0.0,       -- top (red)
        0.5, -0.5, 0.0, 1.0, 0.0,      -- bottom right (green)
        -0.5, -0.5, 0.0, 0.0, 1.0,     -- bottom left (blue)
    }
    local data = string.pack(string.rep("f", #vertices), table.unpack(vertices))
    vbuf = gfx.MakeBuffer(gfx.BufferDesc({
        data = gfx.Range(data),
    }))

    -- Compile shader
    local shader_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 32, -- 1 vec4 (16) + 1 float padded to 16 = 32 bytes
                glsl_uniforms = {
                    { glsl_name = "tint",     type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "rotation", type = gfx.UniformType.FLOAT },
                },
            },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    shader = shaderMod.compile_full(shader_source, "simple", shader_desc)
    if not shader then
        log.error("Failed to compile shader")
        return
    end

    -- Create pipeline
    pipeline = gfx.MakePipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 }, -- pos
                { format = gfx.VertexFormat.FLOAT3 }, -- color
            },
        },
    }))

    log.info("init() complete")
end

function M:frame()
    imgui.NewFrame()

    -- Update rotation
    if auto_rotate then
        rotation = rotation + rotation_speed * (1.0 / 60.0)
    end

    -- === RENDER PASS ===
    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 },
            } },
        }),
        swapchain = glue.Swapchain(),
    }))

    gfx.ApplyPipeline(pipeline)

    gfx.ApplyBindings(gfx.Bindings({
        vertex_buffers = { vbuf },
    }))

    -- Apply uniforms: tint color + rotation
    -- Note: rotation needs padding to align to 16 bytes
    local uniform_data = string.pack("ffff ffff",
        triangle_color[1], triangle_color[2], triangle_color[3], 1.0,
        rotation, 0.0, 0.0, 0.0
    )
    gfx.ApplyUniforms(0, gfx.Range(uniform_data))

    gfx.Draw(0, 3, 1)

    -- ImGui UI
    if imgui.Begin("Triangle Controls") then
        imgui.TextUnformatted("Simple Triangle Example")
        imgui.Separator()

        local clicked, new_val = imgui.Checkbox("Auto Rotate", auto_rotate)
        if clicked then auto_rotate = new_val end

        local changed, new_speed = imgui.SliderFloat("Rotation Speed", rotation_speed, 0.0, 5.0)
        if changed then rotation_speed = new_speed end

        if not auto_rotate then
            local rot_changed, new_rot = imgui.SliderFloat("Rotation", rotation, 0.0, 6.28318)
            if rot_changed then rotation = new_rot end
        end

        imgui.Separator()

        local col_changed, new_col = imgui.ColorEdit3("Tint Color", triangle_color)
        if col_changed then
            triangle_color = new_col
        end

        imgui.Separator()
        imgui.TextUnformatted(string.format("Rotation: %.2f rad", rotation))
    end
    imgui.End()

    imgui.Render()

    gfx.EndPass()
    gfx.Commit()
end

function M:cleanup()
    imgui.Shutdown()
    gfx.Shutdown()
    log.info("cleanup")
end

function M:event(ev)
    -- Let ImGui handle events first
    if imgui.HandleEvent(ev) then
        return
    end

    -- ESC to quit
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE then
            app.RequestQuit()
        end
    end
end

return M
