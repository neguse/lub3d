-- mane3d example: Model loading with normal mapping
-- Based on lettier/3d-game-shaders-for-beginners
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local log = require("lib.log")
local shaderMod = require("lib.shader")
local texture = require("lib.texture")
local util = require("lib.util")
local glm = require("lib.glm")

-- Camera
local camera_pos = glm.vec3(0, -20, 10)
local camera_yaw = 0
local camera_pitch = 0.3

-- Light
local light_pos = glm.vec3(10, -10, 20)
local light_color = glm.vec3(1.5, 1.4, 1.3)
local ambient_color = glm.vec3(0.2, 0.2, 0.25)

-- Graphics resources
local shader = nil
---@type gfx.Pipeline
local pipeline = nil
local meshes = {}  -- { vbuf, index_count, diffuse_img, diffuse_smp, normal_img, normal_smp, material }
---@type table<string, {img: gpu.Image, view: gpu.View, smp: gpu.Sampler}>
local textures_cache = {}

-- Time
local t = 0

-- Input
local keys_down = {}
local mouse_captured = false

-- Shader with normal mapping
local shader_source = [[
@vs vs
in vec3 pos;
in vec3 normal;
in vec2 uv;
in vec3 tangent;

out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_bitangent;
out vec3 v_world_pos;
out vec2 v_uv;
out vec4 v_light_pos;
out vec4 v_light_color;
out vec4 v_ambient;
out vec4 v_camera_pos;
out vec4 v_material;  // diffuse.rgb, shininess

layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    vec4 light_pos;
    vec4 light_color;
    vec4 ambient_color;
    vec4 camera_pos;
    vec4 material;  // diffuse.rgb + shininess
};

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    mat3 normal_mat = mat3(model);
    v_normal = normalize(normal_mat * normal);
    v_tangent = normalize(normal_mat * tangent);
    v_bitangent = cross(v_normal, v_tangent);
    v_world_pos = (model * vec4(pos, 1.0)).xyz;
    v_uv = vec2(uv.x, 1.0 - uv.y);  // Flip V (stb_image top-left vs Panda3D bottom-left origin)
    v_light_pos = light_pos;
    v_light_color = light_color;
    v_ambient = ambient_color;
    v_camera_pos = camera_pos;
    v_material = material;
}
@end

@fs fs
in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_bitangent;
in vec3 v_world_pos;
in vec2 v_uv;
in vec4 v_light_pos;
in vec4 v_light_color;
in vec4 v_ambient;
in vec4 v_camera_pos;
in vec4 v_material;

out vec4 frag_color;

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;

void main() {
    // Sample textures
    vec4 diffuse_color = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    vec3 normal_map = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb;

    // Unpack normal map: [0,1] -> [-1,1]
    vec3 n_tangent = normalize(normal_map * 2.0 - 1.0);

    // Transform from tangent space to world space
    mat3 tbn = mat3(v_tangent, v_bitangent, v_normal);
    vec3 n = normalize(tbn * n_tangent);

    vec3 light_dir = normalize(v_light_pos.xyz - v_world_pos);
    vec3 view_dir = normalize(v_camera_pos.xyz - v_world_pos);

    // Ambient
    vec3 ambient = v_ambient.rgb * diffuse_color.rgb;

    // Diffuse
    float diff = max(dot(n, light_dir), 0.0);
    vec3 diffuse = v_light_color.rgb * diff * diffuse_color.rgb;

    // Specular (Blinn-Phong)
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(n, halfway), 0.0), v_material.w);
    vec3 specular = v_light_color.rgb * spec * vec3(0.3);

    vec3 result = ambient + diffuse + specular;
    frag_color = vec4(result, diffuse_color.a);
}
@end

@program model vs fs
]]

-- Compute tangent vectors for a triangle
local function compute_tangent(p1, p2, p3, uv1, uv2, uv3)
    local edge1 = { p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3] }
    local edge2 = { p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3] }
    local duv1 = { uv2[1] - uv1[1], uv2[2] - uv1[2] }
    local duv2 = { uv3[1] - uv1[1], uv3[2] - uv1[2] }

    local f = duv1[1] * duv2[2] - duv2[1] * duv1[2]
    if math.abs(f) < 0.0001 then f = 1.0 end
    f = 1.0 / f

    local tx = f * (duv2[2] * edge1[1] - duv1[2] * edge2[1])
    local ty = f * (duv2[2] * edge1[2] - duv1[2] * edge2[2])
    local tz = f * (duv2[2] * edge1[3] - duv1[2] * edge2[3])

    local len = math.sqrt(tx*tx + ty*ty + tz*tz)
    if len > 0.0001 then
        tx, ty, tz = tx/len, ty/len, tz/len
    else
        tx, ty, tz = 1, 0, 0
    end

    return tx, ty, tz
end

-- Process mesh vertices and add tangents
-- Input: flat array of (x,y,z,nx,ny,nz,u,v) * N
-- Output: flat array of (x,y,z,nx,ny,nz,u,v,tx,ty,tz) * N
local function add_tangents(vertices)
    local result = {}
    local stride = 8  -- input stride
    local vertex_count = #vertices / stride

    -- Process triangles (assuming triangle list)
    for i = 0, vertex_count - 1, 3 do
        local base1 = i * stride
        local base2 = (i + 1) * stride
        local base3 = (i + 2) * stride

        if base3 + stride <= #vertices then
            local p1 = { vertices[base1 + 1], vertices[base1 + 2], vertices[base1 + 3] }
            local p2 = { vertices[base2 + 1], vertices[base2 + 2], vertices[base2 + 3] }
            local p3 = { vertices[base3 + 1], vertices[base3 + 2], vertices[base3 + 3] }
            local uv1 = { vertices[base1 + 7], vertices[base1 + 8] }
            local uv2 = { vertices[base2 + 7], vertices[base2 + 8] }
            local uv3 = { vertices[base3 + 7], vertices[base3 + 8] }

            local tx, ty, tz = compute_tangent(p1, p2, p3, uv1, uv2, uv3)

            -- Add all 3 vertices with same tangent
            for j = 0, 2 do
                local base = (i + j) * stride
                for k = 1, 8 do
                    table.insert(result, vertices[base + k])
                end
                table.insert(result, tx)
                table.insert(result, ty)
                table.insert(result, tz)
            end
        end
    end

    return result
end

-- Load texture with caching (returns raw handles for bindings)
---@return gfx.View?, gfx.Sampler?
local function load_texture_cached(path)
    if textures_cache[path] then
        return textures_cache[path].view.handle, textures_cache[path].smp.handle
    end

    local full_path = "textures/" .. path
    local tex = texture.load(full_path)
    if tex then
        textures_cache[path] = tex
        return tex.view.handle, tex.smp.handle
    end
    return nil, nil
end

-- Create a default 1x1 texture (returns view, sampler)
local function create_default_texture(r, g, b)
    local pixels = string.char(
        math.floor(r * 255),
        math.floor(g * 255),
        math.floor(b * 255),
        255
    )
    local img = gfx.make_image(gfx.ImageDesc({
        width = 1,
        height = 1,
        pixel_format = gfx.PixelFormat.RGBA8,
        data = { mip_levels = { pixels } },
    }))
    local view = gfx.make_view(gfx.ViewDesc({
        texture = { image = img },
    }))
    local smp = gfx.make_sampler(gfx.SamplerDesc({
        min_filter = gfx.Filter.NEAREST,
        mag_filter = gfx.Filter.NEAREST,
    }))
    return view, smp
end

local default_diffuse_view, default_diffuse_smp
local default_normal_view, default_normal_smp

function init()
    log.info("Model loading example init")

    -- Create default textures
    default_diffuse_view, default_diffuse_smp = create_default_texture(0.8, 0.8, 0.8)
    default_normal_view, default_normal_smp = create_default_texture(0.5, 0.5, 1.0)  -- flat normal

    -- Compile shader
    -- vs_params: 2 mat4 + 5 vec4 = 128 + 80 = 208 bytes
    local shader_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 208,
                glsl_uniforms = {
                    { type = gfx.UniformType.MAT4, glsl_name = "mvp" },
                    { type = gfx.UniformType.MAT4, glsl_name = "model" },
                    { type = gfx.UniformType.FLOAT4, glsl_name = "light_pos" },
                    { type = gfx.UniformType.FLOAT4, glsl_name = "light_color" },
                    { type = gfx.UniformType.FLOAT4, glsl_name = "ambient_color" },
                    { type = gfx.UniformType.FLOAT4, glsl_name = "camera_pos" },
                    { type = gfx.UniformType.FLOAT4, glsl_name = "material" },
                },
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "diffuse_tex_diffuse_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 2 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 3 },
        },
    }
    shader = shaderMod.compile_full(shader_source, "model", shader_desc)

    if not shader then
        log.error("Failed to compile shader")
        return
    end

    -- Create pipeline
    pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 },  -- pos
                { format = gfx.VertexFormat.FLOAT3 },  -- normal
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
                { format = gfx.VertexFormat.FLOAT3 },  -- tangent
            },
        },
        cull_mode = gfx.CullMode.FRONT,
        depth = {
            write_enabled = true,
            compare = gfx.CompareFunc.LESS_EQUAL,
        },
    }))

    -- Load model
    log.info("Loading mill-scene...")
    local model_path = "mill-scene.lua"  -- same directory as exe
    local model_func, err = loadfile(model_path)
    if not model_func then
        log.error("Failed to load model: " .. tostring(err))
        return
    end

    local scene = model_func()
    log.info("Model loaded, processing meshes...")

    -- Process each mesh
    local mesh_count = 0
    for name, mesh in pairs(scene.meshes) do
        if mesh.vertices and #mesh.vertices > 0 then
            -- Add tangent vectors
            local verts_with_tangents = add_tangents(mesh.vertices)

            if #verts_with_tangents > 0 then
                local vbuf = gfx.make_buffer(gfx.BufferDesc({
                    data = gfx.Range(util.pack_floats(verts_with_tangents)),
                }))

                -- Get textures (views)
                ---@type gfx.View, gfx.Sampler
                local diffuse_view, diffuse_smp = default_diffuse_view, default_diffuse_smp
                ---@type gfx.View, gfx.Sampler
                local normal_view, normal_smp = default_normal_view, default_normal_smp

                if mesh.textures and #mesh.textures > 0 then
                    local tex_info = scene.textures[mesh.textures[1]]
                    if tex_info then
                        local view, smp = load_texture_cached(tex_info.path)
                        if view and smp then
                            diffuse_view, diffuse_smp = view, smp
                        end
                    end

                    if mesh.textures[2] then
                        local nrm_info = scene.textures[mesh.textures[2]]
                        if nrm_info then
                            local view, smp = load_texture_cached(nrm_info.path)
                            if view and smp then
                                normal_view, normal_smp = view, smp
                            end
                        end
                    end
                end

                -- Get material
                local mat = scene.materials[name] or { diffuse = {0.8, 0.8, 0.8}, shininess = 32 }

                table.insert(meshes, {
                    vbuf = vbuf,
                    vertex_count = #verts_with_tangents / 11,  -- 11 floats per vertex now
                    diffuse_view = diffuse_view,
                    diffuse_smp = diffuse_smp,
                    normal_view = normal_view,
                    normal_smp = normal_smp,
                    material = mat,
                    name = name,
                })
                mesh_count = mesh_count + 1
            end
        end
    end

    log.info("Loaded " .. mesh_count .. " meshes")
    log.info("init() complete - events should work now")
end

local frame_count = 0
function frame()
    frame_count = frame_count + 1
    if frame_count == 1 then
        log.info("First frame!")
    end
    t = t + 1/60

    -- Camera controls
    local move_speed = 0.3
    local camera_up = glm.vec3(0, 0, 1)
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
    if keys_down["E"] or keys_down["SPACE"] then camera_pos = camera_pos + camera_up * move_speed end
    if keys_down["Q"] or keys_down["LEFT_SHIFT"] then camera_pos = camera_pos - camera_up * move_speed end

    -- Matrices
    local w = app.width()
    local h = app.height()
    local aspect = w / h

    local proj = glm.perspective(math.rad(60), aspect, 0.1, 500)
    local center = camera_pos + forward
    local view = glm.lookat(camera_pos, center, camera_up)

    local model = glm.mat4()  -- identity

    -- Begin pass
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.4, g = 0.6, b = 0.9, a = 1.0 }  -- sky blue
            }},
            depth = {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = 1.0
            },
        }),
        swapchain = glue.swapchain(),
    }))

    gfx.apply_pipeline(pipeline)

    local mvp = proj * view * model

    -- Draw all meshes
    for _, mesh in ipairs(meshes) do
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf },
            views = { mesh.diffuse_view, mesh.normal_view },
            samplers = { mesh.diffuse_smp, mesh.normal_smp },
        }))

        local mat = mesh.material
        local uniforms = mvp:pack() .. model:pack() .. util.pack_floats({
            light_pos.x, light_pos.y, light_pos.z, 1,
            light_color.x, light_color.y, light_color.z, 1,
            ambient_color.x, ambient_color.y, ambient_color.z, 1,
            camera_pos.x, camera_pos.y, camera_pos.z, 1,
            mat.diffuse[1], mat.diffuse[2], mat.diffuse[3], mat.shininess or 32,
        })

        gfx.apply_uniforms(0, gfx.Range(uniforms))
        gfx.draw(0, mesh.vertex_count, 1)
    end

    gfx.end_pass()
    gfx.commit()
end

local event_logged = false
function event(ev)
    if not event_logged then
        log.info("Lua event() called!")
        event_logged = true
    end
    local evtype = ev.type
    if evtype == app.EventType.KEY_DOWN then
        local key = ev.key_code
        log.info("KEY_DOWN: " .. tostring(key))
        if key == app.Keycode.ESCAPE then
            mouse_captured = false
            app.show_mouse(true)
            app.lock_mouse(false)
        elseif key == app.Keycode.W then keys_down["W"] = true
        elseif key == app.Keycode.S then keys_down["S"] = true
        elseif key == app.Keycode.A then keys_down["A"] = true
        elseif key == app.Keycode.D then keys_down["D"] = true
        elseif key == app.Keycode.Q then keys_down["Q"] = true
        elseif key == app.Keycode.E then keys_down["E"] = true
        elseif key == app.Keycode.SPACE then keys_down["SPACE"] = true
        elseif key == app.Keycode.LEFT_SHIFT then keys_down["LEFT_SHIFT"] = true
        end
    elseif evtype == app.EventType.KEY_UP then
        local key = ev.key_code
        if key == app.Keycode.W then keys_down["W"] = false
        elseif key == app.Keycode.S then keys_down["S"] = false
        elseif key == app.Keycode.A then keys_down["A"] = false
        elseif key == app.Keycode.D then keys_down["D"] = false
        elseif key == app.Keycode.Q then keys_down["Q"] = false
        elseif key == app.Keycode.E then keys_down["E"] = false
        elseif key == app.Keycode.SPACE then keys_down["SPACE"] = false
        elseif key == app.Keycode.LEFT_SHIFT then keys_down["LEFT_SHIFT"] = false
        end
    elseif evtype == app.EventType.MOUSE_DOWN then
        mouse_captured = true
        app.show_mouse(false)
        app.lock_mouse(true)
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

function cleanup()
    -- Destroy cached textures
    for _, tex in pairs(textures_cache) do
        tex.smp:destroy()
        tex.view:destroy()
        tex.img:destroy()
    end
    textures_cache = {}

    log.info("Model cleanup")
end
