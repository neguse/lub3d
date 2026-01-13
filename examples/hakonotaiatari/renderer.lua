-- hakonotaiatari renderer
-- Supports two rendering modes: wireframe and shading

local gfx = require("sokol.gfx")
local gl = require("sokol.gl")
local app = require("sokol.app")
local glue = require("sokol.glue")
local shaderMod = require("lib.shader")
local util = require("lib.util")
local glm = require("lib.glm")
local log = require("lib.log")
local const = require("examples.hakonotaiatari.const")

local M = {}

-- Rendering mode
M.MODE_WIREFRAME = 1
M.MODE_SHADED = 2
local current_mode = M.MODE_WIREFRAME

-- Graphics resources for shaded mode
---@type gfx.Shader?
local shaded_shader = nil
---@type gfx.Pipeline?
local shaded_pipeline = nil
---@type gfx.Buffer?
local shaded_vbuf = nil
---@type gfx.Buffer?
local shaded_ibuf = nil

-- Graphics resources for wireframe mode (using sokol.gl)
---@type gl.Pipeline?
local wireframe_pipeline = nil

-- Gakugaku (wobble) state
local gakugaku = 0.0
local gakugaku_time = 0.0

-- Simple hash for pseudo-random (matches shader)
local function hash(x, y)
    local dot = x * 127.1 + y * 311.7
    return (math.sin(dot) * 43758.5453) % 1.0
end

-- Generate gakugaku offset for a vertex (like original RandomSwing)
-- Returns dx, dy, dz offset to add to vertex position
local function get_gakugaku_offset(vx, vy, vz)
    if gakugaku <= 0 then return 0, 0, 0 end

    -- Original uses rand() - truly random each call
    local rand_angle = math.random() * 6.28318
    local rand_radius = math.random() * gakugaku

    -- Scale: 1 pixel on 240px screen ≈ 2.5 world units (field 600 / screen 240)
    -- Original gakugaku 1.0 = 1 pixel offset
    local world_scale = 2.5
    local dx = math.cos(rand_angle) * rand_radius * world_scale
    local dz = math.sin(rand_angle) * rand_radius * world_scale

    return dx, 0, dz
end

-- Shader for shaded cube rendering
local shaded_shader_source = [[
@vs vs
in vec3 pos;
in vec3 normal;

out vec3 v_normal;
out vec3 v_world_pos;
out vec4 v_color;

layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    vec4 color;
    vec4 gakugaku_params;  // x=amount, y=time, z=screen_width, w=screen_height
};

// Simple hash function for pseudo-random
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec4 clip_pos = mvp * vec4(pos, 1.0);

    // Gakugaku effect: add random offset in clip space
    float gaku_amount = gakugaku_params.x;
    float gaku_time = gakugaku_params.y;
    vec2 screen_size = gakugaku_params.zw;

    if (gaku_amount > 0.0) {
        // Generate random offset based on world position and time
        vec3 world_pos = (model * vec4(pos, 1.0)).xyz;
        vec2 seed = world_pos.xy + world_pos.yz + vec2(gaku_time);
        float rand_angle = hash(seed) * 6.28318;
        float rand_radius = hash(seed + vec2(1.0, 0.0)) * gaku_amount;

        // Convert pixel offset to clip space offset
        vec2 pixel_offset = vec2(cos(rand_angle), sin(rand_angle)) * rand_radius;
        vec2 clip_offset = pixel_offset * 2.0 / screen_size * clip_pos.w;

        clip_pos.xy += clip_offset;
    }

    gl_Position = clip_pos;
    v_normal = normalize(mat3(model) * normal);
    v_world_pos = (model * vec4(pos, 1.0)).xyz;
    v_color = color;
}
@end

@fs fs
in vec3 v_normal;
in vec3 v_world_pos;
in vec4 v_color;

out vec4 frag_color;

void main() {
    vec3 light_dir = normalize(vec3(0.3, 1.0, 0.5));
    vec3 n = normalize(v_normal);

    // Ambient
    float ambient = 0.3;

    // Diffuse
    float diff = max(dot(n, light_dir), 0.0);

    vec3 result = v_color.rgb * (ambient + diff * 0.7);
    frag_color = vec4(result, v_color.a);
}
@end

@program hakotai_shaded vs fs
]]

-- Cube vertex data (position + normal)
local function make_cube_vertices()
    local v = {}
    local faces = {
        -- front (z+)
        {{ -0.5, -0.5,  0.5}, { 0.5, -0.5,  0.5}, { 0.5,  0.5,  0.5}, {-0.5,  0.5,  0.5}, {0, 0, 1}},
        -- back (z-)
        {{ 0.5, -0.5, -0.5}, {-0.5, -0.5, -0.5}, {-0.5,  0.5, -0.5}, { 0.5,  0.5, -0.5}, {0, 0, -1}},
        -- top (y+)
        {{-0.5,  0.5,  0.5}, { 0.5,  0.5,  0.5}, { 0.5,  0.5, -0.5}, {-0.5,  0.5, -0.5}, {0, 1, 0}},
        -- bottom (y-)
        {{-0.5, -0.5, -0.5}, { 0.5, -0.5, -0.5}, { 0.5, -0.5,  0.5}, {-0.5, -0.5,  0.5}, {0, -1, 0}},
        -- right (x+)
        {{ 0.5, -0.5,  0.5}, { 0.5, -0.5, -0.5}, { 0.5,  0.5, -0.5}, { 0.5,  0.5,  0.5}, {1, 0, 0}},
        -- left (x-)
        {{-0.5, -0.5, -0.5}, {-0.5, -0.5,  0.5}, {-0.5,  0.5,  0.5}, {-0.5,  0.5, -0.5}, {-1, 0, 0}},
    }

    for _, face in ipairs(faces) do
        local n = face[5]
        for i = 1, 4 do
            local p = face[i]
            -- pos
            table.insert(v, p[1])
            table.insert(v, p[2])
            table.insert(v, p[3])
            -- normal
            table.insert(v, n[1])
            table.insert(v, n[2])
            table.insert(v, n[3])
        end
    end
    return v
end

local function make_cube_indices()
    local indices = {}
    for face = 0, 5 do
        local base = face * 4
        table.insert(indices, base + 0)
        table.insert(indices, base + 1)
        table.insert(indices, base + 2)
        table.insert(indices, base + 0)
        table.insert(indices, base + 2)
        table.insert(indices, base + 3)
    end
    return indices
end

local function pack_indices(indices)
    return string.pack(string.rep("H", #indices), table.unpack(indices))
end

-- Original game resolution (for gakugaku scaling)
local ORIGINAL_RES = 240.0

-- Pack uniforms for shaded mode (mat4 + mat4 + vec4 + vec4 = 160 bytes)
local function pack_uniforms(mvp, model, r, g, b, a)
    local data = {}
    for i = 1, 16 do data[i] = mvp[i] end
    for i = 1, 16 do data[16 + i] = model[i] end
    data[33] = r
    data[34] = g
    data[35] = b
    data[36] = a or 1.0
    -- gakugaku_params: amount, time, screen_width, screen_height
    -- Scale gakugaku based on resolution (original was 240x240)
    local screen_w = app.widthf()
    local screen_h = app.heightf()
    local scale = math.min(screen_w, screen_h) / ORIGINAL_RES
    data[37] = gakugaku * scale
    data[38] = gakugaku_time
    data[39] = screen_w
    data[40] = screen_h
    return util.pack_floats(data)
end

-- Cube wireframe edges (8 vertices, 12 edges = 24 line indices)
local cube_vertices = {
    glm.vec3(-0.5, -0.5, -0.5),
    glm.vec3( 0.5, -0.5, -0.5),
    glm.vec3( 0.5,  0.5, -0.5),
    glm.vec3(-0.5,  0.5, -0.5),
    glm.vec3(-0.5, -0.5,  0.5),
    glm.vec3( 0.5, -0.5,  0.5),
    glm.vec3( 0.5,  0.5,  0.5),
    glm.vec3(-0.5,  0.5,  0.5),
}

local cube_edges = {
    {1, 2}, {2, 3}, {3, 4}, {4, 1},  -- back face
    {5, 6}, {6, 7}, {7, 8}, {8, 5},  -- front face
    {1, 5}, {2, 6}, {3, 7}, {4, 8},  -- connecting edges
}

-- Initialize renderer
function M.init()
    -- Note: gl.setup() is called in init.lua before this

    -- Create wireframe pipeline for sokol.gl
    wireframe_pipeline = gl.make_pipeline(gfx.PipelineDesc({
        depth = {
            compare = gfx.CompareFunc.LESS_EQUAL,
            write_enabled = true,
        },
        primitive_type = gfx.PrimitiveType.LINES,
    }))

    -- Compile shaded shader
    shaded_shader = shaderMod.compile(shaded_shader_source, "hakotai_shaded", {
        {
            stage = gfx.ShaderStage.VERTEX,
            size = 160,
            glsl_uniforms = {
                { type = gfx.UniformType.MAT4, glsl_name = "mvp" },
                { type = gfx.UniformType.MAT4, glsl_name = "model" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "color" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "gakugaku_params" },
            }
        }
    }, {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
    })

    if not shaded_shader then
        log.error("Shaded shader compilation failed!")
        return false
    end

    -- Create shaded pipeline
    shaded_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shaded_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 },  -- pos
                { format = gfx.VertexFormat.FLOAT3 },  -- normal
            }
        },
        index_type = gfx.IndexType.UINT16,
        cull_mode = gfx.CullMode.FRONT,
        depth = {
            compare = gfx.CompareFunc.LESS_EQUAL,
            write_enabled = true,
        },
        primitive_type = gfx.PrimitiveType.TRIANGLES,
    }))

    if gfx.query_pipeline_state(shaded_pipeline) ~= gfx.ResourceState.VALID then
        log.error("Shaded pipeline creation failed!")
        return false
    end

    -- Create vertex buffer
    local vertices = make_cube_vertices()
    shaded_vbuf = gfx.make_buffer(gfx.BufferDesc({
        data = gfx.Range(util.pack_floats(vertices))
    }))

    -- Create index buffer
    local indices = make_cube_indices()
    shaded_ibuf = gfx.make_buffer(gfx.BufferDesc({
        usage = { index_buffer = true },
        data = gfx.Range(pack_indices(indices))
    }))

    log.info("Renderer initialized")
    return true
end

-- Cleanup renderer
function M.cleanup()
    gl.shutdown()
end

-- Set rendering mode
function M.set_mode(mode)
    current_mode = mode
end

-- Get current mode
function M.get_mode()
    return current_mode
end

-- Toggle rendering mode
function M.toggle_mode()
    if current_mode == M.MODE_WIREFRAME then
        current_mode = M.MODE_SHADED
    else
        current_mode = M.MODE_WIREFRAME
    end
    return current_mode
end

-- Calculate square viewport centered in window (for 1:1 aspect ratio)
local function calc_square_viewport()
    local w = app.widthf()
    local h = app.heightf()
    local size = math.min(w, h)
    local x = math.floor((w - size) / 2)
    local y = math.floor((h - size) / 2)
    return x, y, math.floor(size), math.floor(size)
end

-- Get current viewport (for external use)
function M.get_viewport()
    return calc_square_viewport()
end

-- Begin frame
function M.begin_frame(clear_r, clear_g, clear_b)
    clear_r = clear_r or 0.0
    clear_g = clear_g or 0.0
    clear_b = clear_b or 0.05

    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = clear_r, g = clear_g, b = clear_b, a = 1.0 }
            } },
            depth = {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = 1.0
            }
        }),
        swapchain = glue.swapchain()
    }))

    -- Apply square viewport for 1:1 aspect ratio
    local vx, vy, vw, vh = calc_square_viewport()
    gfx.apply_viewport(vx, vy, vw, vh, true)
    -- Set scissor to full window (allow drawing outside viewport)
    gfx.apply_scissor_rect(0, 0, math.floor(app.widthf()), math.floor(app.heightf()), true)

    if current_mode == M.MODE_SHADED and shaded_pipeline then
        gfx.apply_pipeline(shaded_pipeline)
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { shaded_vbuf },
            index_buffer = shaded_ibuf
        }))
    end
end

-- End frame
function M.end_frame()
    -- Always draw sokol.gl content (used for UI in both modes)
    gl.draw()
    gfx.end_pass()
    gfx.commit()
end

-- Set camera using eye and lookat positions (works for both modes)
function M.set_camera_lookat(eye, lookat, aspect)
    -- Always set up sokol.gl matrices (used for field, particles, UI in both modes)
    gl.defaults()
    if wireframe_pipeline then gl.load_pipeline(wireframe_pipeline) end
    gl.matrix_mode_projection()
    gl.perspective(math.rad(45), aspect, 1.0, 5000.0)
    gl.matrix_mode_modelview()
    gl.lookat(eye.x, eye.y, eye.z, lookat.x, lookat.y, lookat.z, 0, 1, 0)
end

-- Set up 2D orthographic projection for UI rendering
function M.setup_ui_projection()
    gl.defaults()
    if wireframe_pipeline then gl.load_pipeline(wireframe_pipeline) end
    gl.matrix_mode_projection()
    gl.ortho(-1, 1, -1, 1, -1, 1)
    gl.matrix_mode_modelview()
    gl.load_identity()
end

-- Draw a cube at given position with given size and color
-- pos: glm.vec3 position
-- size: glm.vec3 scale
-- angle: rotation angle in radians (around Y axis)
-- r, g, b: color (0-1)
-- proj, view: projection and view matrices (for shaded mode)
function M.draw_cube(pos, size, angle, r, g, b, proj, view)
    if current_mode == M.MODE_WIREFRAME then
        M.draw_cube_wireframe(pos, size, angle, r, g, b)
    else
        M.draw_cube_shaded(pos, size, angle, r, g, b, proj, view)
    end
end

-- Draw cube in wireframe mode using sokol.gl
function M.draw_cube_wireframe(pos, size, angle, r, g, b)
    -- Pre-compute world-space vertices with gakugaku offsets
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    local world_verts = {}

    for i, v in ipairs(cube_vertices) do
        -- Scale
        local sx = v.x * size.x
        local sy = v.y * size.y
        local sz = v.z * size.z
        -- Rotate around Y
        local rx = sx * cos_a + sz * sin_a
        local rz = -sx * sin_a + sz * cos_a
        -- Translate
        local wx = pos.x + rx
        local wy = pos.y + sy
        local wz = pos.z + rz
        -- Add gakugaku offset in world space
        local dx, dy, dz = get_gakugaku_offset(wx, wy, wz)
        world_verts[i] = { wx + dx, wy + dy, wz + dz }
    end

    gl.begin_lines()
    for _, edge in ipairs(cube_edges) do
        local v1 = world_verts[edge[1]]
        local v2 = world_verts[edge[2]]
        gl.v3f_c3f(v1[1], v1[2], v1[3], r, g, b)
        gl.v3f_c3f(v2[1], v2[2], v2[3], r, g, b)
    end
    gl["end"]()
end

-- Draw cube in shaded mode using sokol.gfx
function M.draw_cube_shaded(pos, size, angle, r, g, b, proj, view)
    local model = glm.translate(pos) * glm.rotate(angle, glm.vec3(0, 1, 0)) * glm.scale(size)
    local mvp = proj * view * model

    gfx.apply_uniforms(0, gfx.Range(pack_uniforms(mvp, model, r, g, b, 1.0)))
    gfx.draw(0, 36, 1)
end

-- Draw a line between two points (uses sokol.gl in both modes)
function M.draw_line(p1, p2, r, g, b)
    local dx1, dy1, dz1 = get_gakugaku_offset(p1.x, p1.y, p1.z)
    local dx2, dy2, dz2 = get_gakugaku_offset(p2.x, p2.y, p2.z)
    gl.begin_lines()
    gl.v3f_c3f(p1.x + dx1, p1.y + dy1, p1.z + dz1, r, g, b)
    gl.v3f_c3f(p2.x + dx2, p2.y + dy2, p2.z + dz2, r, g, b)
    gl["end"]()
end

-- Draw a point/particle
function M.draw_point(pos, size, r, g, b)
    if current_mode == M.MODE_WIREFRAME then
        local dx, dy, dz = get_gakugaku_offset(pos.x, pos.y, pos.z)
        gl.point_size(size)
        gl.begin_points()
        gl.v3f_c3f(pos.x + dx, pos.y + dy, pos.z + dz, r, g, b)
        gl["end"]()
    else
        -- Draw as small cube
        local s = size * 0.5
        M.draw_cube_shaded(pos, glm.vec3(s, s, s), 0, r, g, b, M._proj, M._view)
    end
end

-- Store matrices for particle drawing in shaded mode
M._proj = nil
M._view = nil

function M.set_matrices(proj, view)
    M._proj = proj
    M._view = view
end

-- Helper: convert ARGB color to RGB (0-1 range)
function M.argb_to_rgb(argb)
    return const.argb_to_rgb(argb)
end

-- Gakugaku (wobble) effect functions
function M.set_gakugaku(value)
    gakugaku = value
end

function M.get_gakugaku()
    return gakugaku
end

function M.update_gakugaku_time(dt)
    gakugaku_time = gakugaku_time + dt
end

-- Get 2D gakugaku offset (for font/UI) - like original RandomSwing
function M.get_gakugaku_offset_2d()
    return (math.random() - 0.5) * 2.0  -- Range -1 to 1
end

return M
