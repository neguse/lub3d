-- mane3d example: Section 8 - Lighting
-- Based on lettier/3d-game-shaders-for-beginners
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local log = require("lib.log")
local shaderMod = require("lib.shader")
local util = require("lib.util")
local glm = require("lib.glm")

-- Camera
local camera_pos = glm.vec3(0, -15, 8)
local camera_target = glm.vec3(0, 0, 3)
local camera_up = glm.vec3(0, 0, 1) -- Z-up coordinate system
local camera_yaw = 0
local camera_pitch = 0.3

-- Light
local light_pos = glm.vec3(5, -5, 10)
local light_color = glm.vec3(2, 1.9, 1.8)     -- brighter
local ambient_color = glm.vec3(0.5, 0.5, 0.5) -- brighter

-- Graphics resources
local shader = nil
---@type sokol.gfx.Pipeline
local pipeline = nil
local cube_vbuf = nil
local cube_ibuf = nil
local cube_data = nil
local sphere_vbuf = nil
local sphere_ibuf = nil
---@type {index_count: integer}
local sphere_data

-- Time
local t = 0

-- Input
local keys_down = {}
local mouse_captured = false
local last_mouse_x, last_mouse_y = 0, 0

-- Shader: Phong lighting with texture support
local shader_source = [[
@vs vs
in vec3 pos;
in vec3 normal;
in vec2 uv;

out vec3 v_normal;
out vec3 v_world_pos;
out vec4 v_diffuse;
out vec4 v_light_pos;
out vec4 v_light_color;
out vec4 v_ambient;
out vec4 v_camera_pos;
out vec4 v_specular;

layout(binding=0) uniform params {
    mat4 mvp;
    mat4 model;
    vec4 light_pos;
    vec4 light_color;
    vec4 ambient_color;
    vec4 camera_pos;
    vec4 material_diffuse;
    vec4 material_specular;  // w = shininess
};

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_normal = normalize(mat3(model) * normal);
    v_world_pos = (model * vec4(pos, 1.0)).xyz;
    v_diffuse = material_diffuse;
    v_light_pos = light_pos;
    v_light_color = light_color;
    v_ambient = ambient_color;
    v_camera_pos = camera_pos;
    v_specular = material_specular;
}
@end

@fs fs
in vec3 v_normal;
in vec3 v_world_pos;
in vec4 v_diffuse;
in vec4 v_light_pos;
in vec4 v_light_color;
in vec4 v_ambient;
in vec4 v_camera_pos;
in vec4 v_specular;

out vec4 frag_color;

// Cel shading helper: quantize to steps
float cel_step(float v, float steps) {
    return floor(v * steps) / steps;
}

void main() {
    vec3 n = normalize(v_normal);
    vec3 light_dir = normalize(v_light_pos.xyz - v_world_pos);
    vec3 view_dir = normalize(v_camera_pos.xyz - v_world_pos);

    // Ambient
    vec3 ambient = v_ambient.rgb * v_diffuse.rgb * 0.3;

    // Diffuse with cel shading
    float diff = max(dot(n, light_dir), 0.0);
    diff = cel_step(diff, 3.0);  // 3 bands
    vec3 diffuse = v_light_color.rgb * diff * v_diffuse.rgb;

    // Specular (Blinn-Phong) with cel shading
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(n, halfway), 0.0), v_specular.w);
    spec = step(0.5, spec);  // hard cutoff for toon specular

    // Fresnel factor (Schlick's approximation)
    float fresnel = pow(1.0 - max(dot(halfway, view_dir), 0.0), 5.0);
    vec3 spec_color = mix(v_specular.rgb, vec3(1.0), fresnel);

    vec3 specular = v_light_color.rgb * spec * spec_color;

    // Rim lighting with cel shading
    float rim_intensity = 1.0 - max(dot(view_dir, n), 0.0);
    rim_intensity = smoothstep(0.6, 0.7, rim_intensity);  // hard edge rim
    vec3 rim_light = rim_intensity * v_diffuse.rgb * 0.5;

    vec3 result = ambient + diffuse + specular + rim_light;
    frag_color = vec4(result, 1.0);
}
@end

@program lighting vs fs
]]

-- Generate a simple cube for testing
local function make_cube_vertices()
    local v = {}
    local faces = {
        -- front (z+)
        { { -0.5, -0.5, 0.5 }, { 0.5, -0.5, 0.5 }, { 0.5, 0.5, 0.5 },  { -0.5, 0.5, 0.5 }, { 0, 0, 1 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
        -- back (z-)
        { { 0.5, -0.5, -0.5 }, { -0.5, -0.5, -0.5 }, { -0.5, 0.5, -0.5 }, { 0.5, 0.5, -0.5 }, { 0, 0, -1 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
        -- top (y+)
        { { -0.5, 0.5, 0.5 },  { 0.5, 0.5, 0.5 },  { 0.5, 0.5, -0.5 }, { -0.5, 0.5, -0.5 }, { 0, 1, 0 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
        -- bottom (y-)
        { { -0.5, -0.5, -0.5 }, { 0.5, -0.5, -0.5 }, { 0.5, -0.5, 0.5 }, { -0.5, -0.5, 0.5 }, { 0, -1, 0 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
        -- right (x+)
        { { 0.5, -0.5, 0.5 },  { 0.5, -0.5, -0.5 }, { 0.5, 0.5, -0.5 }, { 0.5, 0.5, 0.5 }, { 1, 0, 0 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
        -- left (x-)
        { { -0.5, -0.5, -0.5 }, { -0.5, -0.5, 0.5 }, { -0.5, 0.5, 0.5 }, { -0.5, 0.5, -0.5 }, { -1, 0, 0 }, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
    }

    for _, face in ipairs(faces) do
        local n = face[5]
        local uvs = face[6]
        for i = 1, 4 do
            local p = face[i]
            -- pos (3) + normal (3) + uv (2) = 8 floats
            table.insert(v, p[1])
            table.insert(v, p[2])
            table.insert(v, p[3])
            table.insert(v, n[1])
            table.insert(v, n[2])
            table.insert(v, n[3])
            table.insert(v, uvs[i][1])
            table.insert(v, uvs[i][2])
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

-- Generate UV sphere
local function make_sphere_vertices(segments, rings)
    segments = segments or 32
    rings = rings or 16
    local v = {}

    for ring = 0, rings do
        local theta = math.pi * ring / rings
        local sin_theta = math.sin(theta)
        local cos_theta = math.cos(theta)

        for seg = 0, segments do
            local phi = 2 * math.pi * seg / segments
            local sin_phi = math.sin(phi)
            local cos_phi = math.cos(phi)

            -- Position (on unit sphere)
            local x = cos_phi * sin_theta
            local y = sin_phi * sin_theta
            local z = cos_theta

            -- Normal = position for unit sphere
            -- UV
            local u = seg / segments
            local v_coord = ring / rings

            -- pos (3) + normal (3) + uv (2)
            table.insert(v, x)
            table.insert(v, y)
            table.insert(v, z)
            table.insert(v, x) -- normal = pos
            table.insert(v, y)
            table.insert(v, z)
            table.insert(v, u)
            table.insert(v, v_coord)
        end
    end
    return v, segments, rings
end

local function make_sphere_indices(segments, rings)
    local indices = {}
    for ring = 0, rings - 1 do
        for seg = 0, segments - 1 do
            local curr = ring * (segments + 1) + seg
            local next_ring = (ring + 1) * (segments + 1) + seg

            table.insert(indices, curr)
            table.insert(indices, next_ring)
            table.insert(indices, curr + 1)

            table.insert(indices, curr + 1)
            table.insert(indices, next_ring)
            table.insert(indices, next_ring + 1)
        end
    end
    return indices
end

local function init_game()
    log.info("Lighting example init")

    -- Initialize sokol.gfx
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    -- Compile shader
    -- Single uniform block: 2 mat4 + 6 vec4 = 128 + 96 = 224 bytes
    shader = shaderMod.compile(shader_source, "lighting", {
        {
            stage = gfx.ShaderStage.VERTEX,
            size = 224,
            glsl_uniforms = {
                { type = gfx.UniformType.MAT4,   glsl_name = "mvp" },
                { type = gfx.UniformType.MAT4,   glsl_name = "model" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "light_pos" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "light_color" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "ambient_color" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "camera_pos" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "material_diffuse" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "material_specular" },
            },
        },
    }, {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 2 },
    })

    if not shader then
        log.error("Failed to compile shader")
        return
    end

    -- Create pipeline
    pipeline = gfx.MakePipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 }, -- pos
                { format = gfx.VertexFormat.FLOAT3 }, -- normal
                { format = gfx.VertexFormat.FLOAT2 }, -- uv
            },
        },
        index_type = gfx.IndexType.UINT16,
        cull_mode = gfx.CullMode.BACK,
        depth = {
            write_enabled = true,
            compare = gfx.CompareFunc.LESS_EQUAL,
        },
    }))

    -- Create cube geometry
    local cube_verts = make_cube_vertices()
    local cube_indices = make_cube_indices()

    cube_vbuf = gfx.MakeBuffer(gfx.BufferDesc({
        data = gfx.Range(util.pack_floats(cube_verts)),
    }))

    cube_ibuf = gfx.MakeBuffer(gfx.BufferDesc({
        usage = { index_buffer = true },
        data = gfx.Range(pack_indices(cube_indices)),
    }))

    cube_data = {
        index_count = #cube_indices,
    }

    -- Create sphere geometry
    local sphere_verts, segs, rings = make_sphere_vertices(24, 12)
    local sphere_indices = make_sphere_indices(segs, rings)

    sphere_vbuf = gfx.MakeBuffer(gfx.BufferDesc({
        data = gfx.Range(util.pack_floats(sphere_verts)),
    }))

    sphere_ibuf = gfx.MakeBuffer(gfx.BufferDesc({
        usage = { index_buffer = true },
        data = gfx.Range(pack_indices(sphere_indices)),
    }))

    sphere_data = {
        index_count = #sphere_indices,
    }

    log.info("Init complete")
end

local function update_frame()
    t = t + 1 / 60

    -- Update camera based on input
    local move_speed = 0.2
    local forward = glm.vec3(
        math.sin(camera_yaw) * math.cos(camera_pitch),
        math.cos(camera_yaw) * math.cos(camera_pitch),
        math.sin(camera_pitch)
    )
    local right = glm.normalize(glm.cross(forward, camera_up))

    if keys_down["W"] then camera_pos = camera_pos + forward * move_speed end
    if keys_down["S"] then camera_pos = camera_pos - forward * move_speed end
    if keys_down["A"] then camera_pos = camera_pos - right * move_speed end
    if keys_down["D"] then camera_pos = camera_pos + right * move_speed end
    if keys_down["SPACE"] then camera_pos = camera_pos + camera_up * move_speed end
    if keys_down["LEFT_SHIFT"] then camera_pos = camera_pos - camera_up * move_speed end

    -- Animate light
    light_pos = glm.vec3(
        math.sin(t * 0.5) * 8,
        math.cos(t * 0.5) * 8,
        6 + math.sin(t * 0.3) * 2
    )

    -- Matrices
    local w = app.Width()
    local h = app.Height()
    local aspect = w / h

    local proj = glm.perspective(math.rad(60), aspect, 0.1, 100)
    -- Simple fixed camera looking at origin
    local eye = glm.vec3(0, -10, 5)
    local center = glm.vec3(0, 0, 0)
    local up = glm.vec3(0, 0, 1)
    local view = glm.lookat(eye, center, up)
    camera_pos = eye -- for lighting calculation

    -- Begin pass
    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 }
            } },
            depth = {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = 1.0
            },
        }),
        swapchain = glue.Swapchain(),
    }))

    gfx.ApplyPipeline(pipeline)

    -- Draw spheres (better for showing Fresnel)
    gfx.ApplyBindings(gfx.Bindings({
        vertex_buffers = { sphere_vbuf },
        index_buffer = sphere_ibuf,
    }))

    local sphere_positions = {
        { 0,  0,  0 },
        { 4,  0,  0 },
        { -4, 0,  0 },
        { 0,  4,  0 },
        { 0,  -4, 0 },
    }

    local sphere_colors = {
        { 1,   0.3, 0.3 },
        { 0.3, 1,   0.3 },
        { 0.3, 0.3, 1 },
        { 1,   1,   0.3 },
        { 0.3, 1,   1 },
    }

    for i, pos in ipairs(sphere_positions) do
        local model = glm.translate(glm.vec3(pos[1], pos[2], pos[3])) * glm.scale(glm.vec3(1.5, 1.5, 1.5))
        local mvp = proj * view * model

        local color = sphere_colors[i]

        local uniforms = mvp:pack() .. model:pack() .. util.pack_floats({
            light_pos.x, light_pos.y, light_pos.z, 1,
            light_color.x, light_color.y, light_color.z, 1,
            ambient_color.x, ambient_color.y, ambient_color.z, 1,
            camera_pos.x, camera_pos.y, camera_pos.z, 1,
            color[1], color[2], color[3], 1, -- diffuse
            0.3, 0.3, 0.3, 64,               -- specular + shininess
        })

        gfx.ApplyUniforms(0, gfx.Range(uniforms))
        gfx.Draw(0, sphere_data.index_count, 1)
    end

    -- Draw light indicator (small bright sphere)
    local light_model = glm.translate(light_pos) * glm.scale(glm.vec3(0.3, 0.3, 0.3))
    local light_mvp = proj * view * light_model

    local uniforms = light_mvp:pack() .. light_model:pack() .. util.pack_floats({
        light_pos.x, light_pos.y, light_pos.z, 1,
        1, 1, 1, 1,
        5, 5, 5, 1, -- high ambient = emissive
        camera_pos.x, camera_pos.y, camera_pos.z, 1,
        1, 0.9, 0.7, 1,
        0, 0, 0, 1,
    })

    gfx.ApplyUniforms(0, gfx.Range(uniforms))
    gfx.Draw(0, sphere_data.index_count, 1)

    gfx.EndPass()
    gfx.Commit()
end

local function handle_event(ev)
    local evtype = ev.type
    if evtype == app.EventType.KEY_DOWN then
        local key = ev.key_code
        if key == app.Keycode.ESCAPE then
            mouse_captured = false
            app.ShowMouse(true)
            app.LockMouse(false)
        elseif key == app.Keycode.W then
            keys_down["W"] = true
        elseif key == app.Keycode.S then
            keys_down["S"] = true
        elseif key == app.Keycode.A then
            keys_down["A"] = true
        elseif key == app.Keycode.D then
            keys_down["D"] = true
        elseif key == app.Keycode.SPACE then
            keys_down["SPACE"] = true
        elseif key == app.Keycode.LEFT_SHIFT then
            keys_down["LEFT_SHIFT"] = true
        end
    elseif evtype == app.EventType.KEY_UP then
        local key = ev.key_code
        if key == app.Keycode.W then
            keys_down["W"] = false
        elseif key == app.Keycode.S then
            keys_down["S"] = false
        elseif key == app.Keycode.A then
            keys_down["A"] = false
        elseif key == app.Keycode.D then
            keys_down["D"] = false
        elseif key == app.Keycode.SPACE then
            keys_down["SPACE"] = false
        elseif key == app.Keycode.LEFT_SHIFT then
            keys_down["LEFT_SHIFT"] = false
        end
    elseif evtype == app.EventType.MOUSE_DOWN then
        mouse_captured = true
        app.ShowMouse(false)
        app.LockMouse(true)
    elseif evtype == app.EventType.MOUSE_MOVE then
        if mouse_captured then
            local dx = ev.mouse_dx
            local dy = ev.mouse_dy
            camera_yaw = camera_yaw + dx * 0.003
            camera_pitch = camera_pitch - dy * 0.003
            camera_pitch = math.max(-1.5, math.min(1.5, camera_pitch))
        end
    end
end

local function cleanup_game()
    gfx.Shutdown()
    log.info("Lighting cleanup")
end

-- Run the application
app.Run(app.Desc({
    width = 1280,
    height = 720,
    window_title = "Mane3D - Lighting",
    init = init_game,
    frame = update_frame,
    cleanup = cleanup_game,
    event = handle_event,
}))
