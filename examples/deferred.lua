-- mane3d example: Deferred Rendering + Fog
-- Based on lettier/3d-game-shaders-for-beginners
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local util = require("util")
local glm = require("glm")
local imgui = require("imgui")

-- Camera
local camera_pos = glm.vec3(0, -20, 10)
local camera_yaw = 0
local camera_pitch = 0.3

-- Light
local light_pos = glm.vec3(10, -10, 20)
local light_color = glm.vec3(1.5, 1.4, 1.3)
local ambient_color = glm.vec3(0.2, 0.2, 0.25)

-- Fog parameters
local fog_enabled = true
local fog_color = { 0.5, 0.6, 0.7 }
local fog_near = 20.0
local fog_far = 150.0

-- Blur parameters
local blur_enabled = false
local blur_size = 2
local blur_separation = 1.0

-- Graphics resources
local geom_shader = nil
---@type gfx.Pipeline
local geom_pipeline = nil
local light_shader = nil
---@type gfx.Pipeline
local light_pipeline = nil
local meshes = {}
local textures_cache = {}

-- G-Buffer resources
local gbuf_position_img = nil
local gbuf_normal_img = nil
local gbuf_albedo_img = nil
local gbuf_depth_img = nil
-- Color attachment views (for rendering to G-Buffer)
local gbuf_position_attach = nil
local gbuf_normal_attach = nil
local gbuf_albedo_attach = nil
local gbuf_depth_attach = nil
-- Texture views (for reading from G-Buffer)
local gbuf_position_tex = nil
local gbuf_normal_tex = nil
local gbuf_albedo_tex = nil
local gbuf_sampler = nil

-- Full-screen quad
local quad_vbuf = nil

-- Scene render target (for post-processing)
local scene_img = nil
local scene_attach = nil
local scene_tex = nil
local scene_depth_img = nil
local scene_depth_attach = nil

-- Blur shader/pipeline
local blur_shader = nil
---@type gfx.Pipeline
local blur_pipeline = nil

-- Time
local t = 0

-- Input
local keys_down = {}
local mouse_captured = false

-- Geometry Pass Shader: outputs to G-Buffer (MRT)
local geom_shader_source = [[
@vs geom_vs
in vec3 pos;
in vec3 normal;
in vec2 uv;
in vec3 tangent;

out vec3 v_world_pos;
out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_bitangent;
out vec2 v_uv;

layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
};

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_world_pos = (model * vec4(pos, 1.0)).xyz;
    mat3 normal_mat = mat3(model);
    v_normal = normalize(normal_mat * normal);
    v_tangent = normalize(normal_mat * tangent);
    v_bitangent = cross(v_normal, v_tangent);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs geom_fs
in vec3 v_world_pos;
in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_bitangent;
in vec2 v_uv;

layout(location=0) out vec4 out_position;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_albedo;

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;

void main() {
    // Sample textures
    vec4 albedo = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    vec3 normal_map = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb;

    // Unpack and transform normal
    vec3 n_tangent = normalize(normal_map * 2.0 - 1.0);
    mat3 tbn = mat3(v_tangent, v_bitangent, v_normal);
    vec3 n = normalize(tbn * n_tangent);

    // Output to G-Buffer
    out_position = vec4(v_world_pos, 1.0);
    out_normal = vec4(n * 0.5 + 0.5, 1.0);  // Pack to [0,1]
    out_albedo = albedo;
}
@end

@program geom geom_vs geom_fs
]]

-- Lighting Pass Shader: reads G-Buffer and computes lighting
local light_shader_source = [[
@vs light_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);  // Flip V for render target
}
@end

@fs light_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D position_tex;
layout(binding=0) uniform sampler position_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;
layout(binding=2) uniform texture2D albedo_tex;
layout(binding=2) uniform sampler albedo_smp;

layout(binding=0) uniform fs_params {
    vec4 light_pos;
    vec4 light_color;
    vec4 ambient_color;
    vec4 camera_pos;
    vec4 fog_color;      // rgb = color, a = enabled
    vec4 fog_params;     // x = near, y = far
};

void main() {
    // Sample G-Buffer
    vec3 world_pos = texture(sampler2D(position_tex, position_smp), v_uv).rgb;
    vec3 normal = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb * 2.0 - 1.0;  // Unpack
    vec4 albedo = texture(sampler2D(albedo_tex, albedo_smp), v_uv);

    // Skip if no geometry
    if (albedo.a < 0.01) {
        frag_color = vec4(0.1, 0.1, 0.15, 1.0);  // Background
        return;
    }

    vec3 light_dir = normalize(light_pos.xyz - world_pos);
    vec3 view_dir = normalize(camera_pos.xyz - world_pos);
    vec3 n = normalize(normal);

    // Ambient
    vec3 ambient = ambient_color.rgb * albedo.rgb;

    // Diffuse
    float diff = max(dot(n, light_dir), 0.0);
    vec3 diffuse = light_color.rgb * diff * albedo.rgb;

    // Specular (Blinn-Phong)
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(n, halfway), 0.0), 32.0);
    vec3 specular = light_color.rgb * spec * vec3(0.3);

    vec3 result = ambient + diffuse + specular;

    // Apply fog
    if (fog_color.a > 0.5) {
        float dist = length(world_pos - camera_pos.xyz);
        float fog_intensity = clamp((dist - fog_params.x) / (fog_params.y - fog_params.x), 0.0, 0.97);
        result = mix(result, fog_color.rgb, fog_intensity);
    }

    frag_color = vec4(result, 1.0);
}
@end

@program light light_vs light_fs
]]

-- Box Blur Shader
local blur_shader_source = [[
@vs blur_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);  // Flip V for render target
}
@end

@fs blur_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D color_tex;
layout(binding=0) uniform sampler color_smp;

layout(binding=0) uniform fs_params {
    vec4 params;  // x = size, y = separation, z = enabled
};

void main() {
    vec2 tex_size = vec2(textureSize(sampler2D(color_tex, color_smp), 0));

    int size = int(params.x);
    float separation = params.y;
    float enabled = params.z;

    if (enabled < 0.5 || size <= 0) {
        frag_color = texture(sampler2D(color_tex, color_smp), v_uv);
        return;
    }

    separation = max(separation, 1.0);

    vec4 color = vec4(0.0);
    float count = 0.0;

    for (int i = -size; i <= size; ++i) {
        for (int j = -size; j <= size; ++j) {
            vec2 offset = vec2(float(i), float(j)) * separation / tex_size;
            color += texture(sampler2D(color_tex, color_smp), v_uv + offset);
            count += 1.0;
        }
    }

    frag_color = color / count;
}
@end

@program blur blur_vs blur_fs
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

local function create_gbuffer(w, h)
    util.info("Creating G-Buffer " .. w .. "x" .. h)

    -- Position buffer (RGBA16F for world position)
    gbuf_position_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA16F,
    }))
    gbuf_position_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = gbuf_position_img },
    }))
    gbuf_position_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = gbuf_position_img },
    }))

    -- Normal buffer (RGBA8 is enough for normalized vectors)
    gbuf_normal_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    gbuf_normal_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = gbuf_normal_img },
    }))
    gbuf_normal_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = gbuf_normal_img },
    }))

    -- Albedo buffer
    gbuf_albedo_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    gbuf_albedo_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = gbuf_albedo_img },
    }))
    gbuf_albedo_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = gbuf_albedo_img },
    }))

    -- Depth buffer
    gbuf_depth_img = gfx.make_image(gfx.ImageDesc({
        usage = { depth_stencil_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.DEPTH,
    }))
    gbuf_depth_attach = gfx.make_view(gfx.ViewDesc({
        depth_stencil_attachment = { image = gbuf_depth_img },
    }))

    -- Sampler for reading G-Buffer
    gbuf_sampler = gfx.make_sampler(gfx.SamplerDesc({
        min_filter = gfx.Filter.NEAREST,
        mag_filter = gfx.Filter.NEAREST,
        wrap_u = gfx.Wrap.CLAMP_TO_EDGE,
        wrap_v = gfx.Wrap.CLAMP_TO_EDGE,
    }))

    -- Scene render target (for post-processing)
    scene_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    scene_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = scene_img },
    }))
    scene_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = scene_img },
    }))
end

local function create_fullscreen_quad()
    local vertices = {
        -- pos (x,y), uv (u,v)
        -1, -1,  0, 0,
         1, -1,  1, 0,
         1,  1,  1, 1,
        -1, -1,  0, 0,
         1,  1,  1, 1,
        -1,  1,  0, 1,
    }
    local data = string.pack(string.rep("f", #vertices), table.unpack(vertices))
    quad_vbuf = gfx.make_buffer(gfx.BufferDesc({
        data = gfx.Range(data),
    }))
end

function init()
    util.info("Deferred rendering example init")

    -- Setup ImGui
    imgui.setup()

    -- Create G-Buffer
    local w, h = app.width(), app.height()
    create_gbuffer(w, h)

    -- Create fullscreen quad
    create_fullscreen_quad()

    -- Geometry pass shader
    local geom_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 128,  -- 2 mat4
                glsl_uniforms = {
                    { glsl_name = "mvp", type = gfx.UniformType.MAT4 },
                    { glsl_name = "model", type = gfx.UniformType.MAT4 },
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
    geom_shader = util.compile_shader_full(geom_shader_source, "geom", geom_desc)
    if not geom_shader then
        util.error("Failed to compile geometry shader")
        return
    end

    -- Geometry pipeline (outputs to 3 color targets)
    geom_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = geom_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 },  -- pos
                { format = gfx.VertexFormat.FLOAT3 },  -- normal
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
                { format = gfx.VertexFormat.FLOAT3 },  -- tangent
            },
        },
        index_type = gfx.IndexType.UINT32,
        cull_mode = gfx.CullMode.FRONT,
        depth = {
            write_enabled = true,
            compare = gfx.CompareFunc.LESS_EQUAL,
            pixel_format = gfx.PixelFormat.DEPTH,
        },
        color_count = 3,
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA16F },  -- position
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- normal
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- albedo
        },
    }))

    -- Lighting pass shader
    local light_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 96,  -- 6 vec4
                glsl_uniforms = {
                    { glsl_name = "light_pos", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "light_color", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "ambient_color", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "camera_pos", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "fog_color", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "fog_params", type = gfx.UniformType.FLOAT4 },
                },
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 2 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 2 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "albedo_tex_albedo_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    light_shader = util.compile_shader_full(light_shader_source, "light", light_desc)
    if not light_shader then
        util.error("Failed to compile lighting shader")
        return
    end

    -- Lighting pipeline (fullscreen quad to scene render target)
    light_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = light_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- pos
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
            },
        },
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA8 },
        },
        depth = {
            pixel_format = gfx.PixelFormat.NONE,
        },
    }))

    -- Blur shader
    local blur_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 16,  -- 1 vec4
                glsl_uniforms = {
                    { glsl_name = "params", type = gfx.UniformType.FLOAT4 },
                },
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "color_tex_color_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    blur_shader = util.compile_shader_full(blur_shader_source, "blur", blur_desc)
    if not blur_shader then
        util.error("Failed to compile blur shader")
        return
    end

    -- Blur pipeline (fullscreen quad to swapchain)
    blur_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = blur_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- pos
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
            },
        },
    }))

    -- Load model
    util.info("Loading mill-scene...")
    local model = require("mill-scene")
    util.info("Model loaded, processing meshes...")

    local default_normal = nil  -- Lazy create flat normal texture

    for mat_name, mesh_data in pairs(model.meshes) do
        -- Get vertices
        local vertices = mesh_data.vertices
        local indices = mesh_data.indices

        -- Compute tangents (vertices is flat array with stride 8: pos(3) + normal(3) + uv(2))
        local in_stride = 8
        local vertex_count = #vertices / in_stride
        local tangents = {}
        for i = 0, vertex_count - 1 do
            tangents[i] = {0, 0, 0}
        end

        for i = 1, #indices, 3 do
            local i1, i2, i3 = indices[i], indices[i+1], indices[i+2]
            local base1, base2, base3 = i1 * in_stride, i2 * in_stride, i3 * in_stride
            local p1 = {vertices[base1 + 1], vertices[base1 + 2], vertices[base1 + 3]}
            local p2 = {vertices[base2 + 1], vertices[base2 + 2], vertices[base2 + 3]}
            local p3 = {vertices[base3 + 1], vertices[base3 + 2], vertices[base3 + 3]}
            local uv1 = {vertices[base1 + 7], vertices[base1 + 8]}
            local uv2 = {vertices[base2 + 7], vertices[base2 + 8]}
            local uv3 = {vertices[base3 + 7], vertices[base3 + 8]}
            local tx, ty, tz = compute_tangent(p1, p2, p3, uv1, uv2, uv3)
            for _, idx in ipairs({i1, i2, i3}) do
                tangents[idx][1] = tangents[idx][1] + tx
                tangents[idx][2] = tangents[idx][2] + ty
                tangents[idx][3] = tangents[idx][3] + tz
            end
        end

        -- Normalize tangents and build vertex buffer with tangents
        local verts = {}
        for i = 0, vertex_count - 1 do
            local base = i * in_stride
            local t = tangents[i]
            local len = math.sqrt(t[1]*t[1] + t[2]*t[2] + t[3]*t[3])
            if len > 0.0001 then
                t[1], t[2], t[3] = t[1]/len, t[2]/len, t[3]/len
            else
                t[1], t[2], t[3] = 1, 0, 0
            end
            -- pos(3) + normal(3) + uv(2) + tangent(3) = 11 floats
            table.insert(verts, vertices[base + 1])  -- px
            table.insert(verts, vertices[base + 2])  -- py
            table.insert(verts, vertices[base + 3])  -- pz
            table.insert(verts, vertices[base + 4])  -- nx
            table.insert(verts, vertices[base + 5])  -- ny
            table.insert(verts, vertices[base + 6])  -- nz
            table.insert(verts, vertices[base + 7])  -- u
            table.insert(verts, vertices[base + 8])  -- v
            table.insert(verts, t[1])  -- tx
            table.insert(verts, t[2])  -- ty
            table.insert(verts, t[3])  -- tz
        end

        local vbuf = gfx.make_buffer(gfx.BufferDesc({
            data = gfx.Range(util.pack_floats(verts)),
        }))

        local ibuf = gfx.make_buffer(gfx.BufferDesc({
            usage = { index_buffer = true },
            data = gfx.Range(string.pack(string.rep("I4", #indices), table.unpack(indices))),
        }))

        -- Load textures (match model.lua approach)
        local diffuse_view, diffuse_smp
        local normal_view, normal_smp

        if mesh_data.textures and #mesh_data.textures > 0 then
            local tex_info = model.textures[mesh_data.textures[1]]
            if tex_info and tex_info.path then
                local path = "textures/" .. tex_info.path
                if not textures_cache[path] then
                    local view, smp = util.load_texture(path)
                    if view then
                        textures_cache[path] = { view = view, smp = smp }
                        util.info("Loaded diffuse: " .. path)
                    end
                end
                if textures_cache[path] then
                    diffuse_view = textures_cache[path].view
                    diffuse_smp = textures_cache[path].smp
                end
            end

            if mesh_data.textures[2] then
                local nrm_info = model.textures[mesh_data.textures[2]]
                if nrm_info and nrm_info.path then
                    local path = "textures/" .. nrm_info.path
                    if not textures_cache[path] then
                        local view, smp = util.load_texture(path)
                        if view then
                            textures_cache[path] = { view = view, smp = smp }
                            util.info("Loaded normal: " .. path)
                        end
                    end
                    if textures_cache[path] then
                        normal_view = textures_cache[path].view
                        normal_smp = textures_cache[path].smp
                    end
                end
            end
        end

        -- Create flat normal texture if needed
        if not normal_view then
            if not default_normal then
                local flat = string.pack("BBBB", 128, 128, 255, 255)
                local flat_img = gfx.make_image(gfx.ImageDesc({
                    width = 1, height = 1,
                    pixel_format = gfx.PixelFormat.RGBA8,
                    data = { mip_levels = { flat } },
                }))
                local flat_view = gfx.make_view(gfx.ViewDesc({
                    texture = { image = flat_img },
                }))
                local flat_smp = gfx.make_sampler(gfx.SamplerDesc({}))
                default_normal = { view = flat_view, smp = flat_smp }
            end
            normal_view = default_normal.view
            normal_smp = default_normal.smp
        end

        if diffuse_view then
            table.insert(meshes, {
                vbuf = vbuf,
                ibuf = ibuf,
                index_count = #indices,
                diffuse_view = diffuse_view,
                diffuse_smp = diffuse_smp,
                normal_view = normal_view,
                normal_smp = normal_smp,
            })
        end
    end

    util.info("Loaded " .. #meshes .. " meshes")
    util.info("init() complete")
end

function frame()
    imgui.new_frame()

    t = t + 1/60

    -- Camera movement
    local move_speed = 0.5
    local forward = glm.vec3(
        math.sin(camera_yaw) * math.cos(camera_pitch),
        math.cos(camera_yaw) * math.cos(camera_pitch),
        math.sin(camera_pitch)
    )
    local right = glm.normalize(glm.cross(forward, glm.vec3(0, 0, 1)))
    local camera_up = glm.vec3(0, 0, 1)

    if keys_down["W"] then camera_pos = camera_pos + forward * move_speed end
    if keys_down["S"] then camera_pos = camera_pos - forward * move_speed end
    if keys_down["A"] then camera_pos = camera_pos - right * move_speed end
    if keys_down["D"] then camera_pos = camera_pos + right * move_speed end
    if keys_down["E"] or keys_down["SPACE"] then camera_pos = camera_pos + camera_up * move_speed end
    if keys_down["Q"] or keys_down["LEFT_SHIFT"] then camera_pos = camera_pos - camera_up * move_speed end

    -- View/projection matrices
    local target = camera_pos + forward
    local view = glm.lookat(camera_pos, target, camera_up)
    local proj = glm.perspective(math.rad(60), app.widthf() / app.heightf(), 0.1, 1000.0)
    local model_mat = glm.mat4(1.0)
    local mvp = proj * view * model_mat

    -- === GEOMETRY PASS ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.5, g = 0.5, b = 0.5, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
            },
            depth = { load_action = gfx.LoadAction.CLEAR, clear_value = 1.0 },
        }),
        attachments = {
            colors = { gbuf_position_attach, gbuf_normal_attach, gbuf_albedo_attach },
            depth_stencil = gbuf_depth_attach,
        },
    }))

    gfx.apply_pipeline(geom_pipeline)

    -- Uniform data: mvp + model
    local uniform_data = mvp:pack() .. model_mat:pack()

    for _, mesh in ipairs(meshes) do
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf },
            index_buffer = mesh.ibuf,
            views = { mesh.diffuse_view, mesh.normal_view },
            samplers = { mesh.diffuse_smp, mesh.normal_smp },
        }))
        gfx.apply_uniforms(0, gfx.Range(uniform_data))
        gfx.draw(0, mesh.index_count, 1)
    end

    gfx.end_pass()
    -- === LIGHTING PASS (to scene render target) ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 },
            }},
        }),
        attachments = {
            colors = { scene_attach },
        },
    }))

    gfx.apply_pipeline(light_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { gbuf_position_tex, gbuf_normal_tex, gbuf_albedo_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    -- Lighting uniforms (including fog)
    local light_uniforms = string.pack("ffff ffff ffff ffff ffff ffff",
        light_pos.x, light_pos.y, light_pos.z, 1.0,
        light_color.x, light_color.y, light_color.z, 1.0,
        ambient_color.x, ambient_color.y, ambient_color.z, 1.0,
        camera_pos.x, camera_pos.y, camera_pos.z, 1.0,
        fog_color[1], fog_color[2], fog_color[3], fog_enabled and 1.0 or 0.0,
        fog_near, fog_far, 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(light_uniforms))
    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === BLUR PASS (to swapchain) ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            }},
        }),
        swapchain = glue.swapchain(),
    }))

    gfx.apply_pipeline(blur_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { scene_tex },
        samplers = { gbuf_sampler },
    }))

    -- Blur uniforms
    local blur_uniforms = string.pack("ffff",
        blur_size, blur_separation, blur_enabled and 1.0 or 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(blur_uniforms))
    gfx.draw(0, 6, 1)

    -- ImGui debug UI
    if imgui.Begin("Debug") then
        imgui.Text("Deferred Rendering + Fog + Blur")
        imgui.Separator()

        if imgui.CollapsingHeader("Fog") then
            fog_enabled = imgui.Checkbox("Fog Enabled", fog_enabled)

            local r, g, b, changed = imgui.ColorEdit3("Fog Color", fog_color[1], fog_color[2], fog_color[3])
            if changed then
                fog_color = { r, g, b }
            end

            fog_near = imgui.SliderFloat("Fog Near", fog_near, 0.0, 100.0)
            fog_far = imgui.SliderFloat("Fog Far", fog_far, 50.0, 300.0)
        end

        if imgui.CollapsingHeader("Blur") then
            blur_enabled = imgui.Checkbox("Blur Enabled", blur_enabled)
            blur_size = imgui.SliderInt("Blur Size", blur_size, 0, 8)
            blur_separation = imgui.SliderFloat("Separation", blur_separation, 1.0, 5.0)
        end

        imgui.Separator()
        imgui.Text(string.format("Camera: %.1f, %.1f, %.1f", camera_pos.x, camera_pos.y, camera_pos.z))
    end
    imgui.End()

    imgui.render()

    gfx.end_pass()
    gfx.commit()
end

function cleanup()
    imgui.shutdown()
    util.info("cleanup")
end

local event_logged = false
function event(ev)
    -- Let ImGui handle events first
    if imgui.handle_event(ev) then
        return
    end

    if not event_logged then
        util.info("Lua event() called!")
        event_logged = true
    end
    local evtype = ev.type
    if evtype == app.EventType.KEY_DOWN then
        local key = ev.key_code
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
