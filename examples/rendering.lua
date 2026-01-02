-- Simple Deferred Rendering Tutorial
-- Minimal G-Buffer + Lighting pass with WASD camera
local hotreload = require("hotreload")
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local util = require("util")
local glm = require("glm")
local imgui = require("imgui")

-- Modules (hot-reloadable)
local camera = require("rendering.camera")
local light = require("rendering.light")

-- Graphics resources
---@type gfx.Shader?
local geom_shader = nil
---@type gfx.Pipeline?
local geom_pipeline = nil
---@type gfx.Shader?
local light_shader = nil
---@type gfx.Pipeline?
local light_pipeline = nil
local meshes = {}
local textures_cache = {}

-- G-Buffer resources
local gbuf_position_img = nil
local gbuf_normal_img = nil
local gbuf_albedo_img = nil
local gbuf_depth_img = nil
local gbuf_position_attach = nil
local gbuf_normal_attach = nil
local gbuf_albedo_attach = nil
local gbuf_depth_attach = nil
local gbuf_position_tex = nil
local gbuf_normal_tex = nil
local gbuf_albedo_tex = nil
local gbuf_sampler = nil

-- Full-screen quad
local quad_vbuf = nil

-- G-Buffer Shader: outputs position, normal, albedo
local geom_shader_source = [[
@vs geom_vs
in vec3 pos;
in vec3 normal;
in vec2 uv;
in vec3 tangent;

out vec3 v_view_pos;
out vec3 v_view_normal;
out vec2 v_uv;

layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    mat4 view;
};

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    vec4 world_pos = model * vec4(pos, 1.0);
    v_view_pos = (view * world_pos).xyz;
    mat3 normal_mat = mat3(view * model);
    v_view_normal = normalize(normal_mat * normal);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs geom_fs
in vec3 v_view_pos;
in vec3 v_view_normal;
in vec2 v_uv;

layout(location=0) out vec4 out_position;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_albedo;

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;

void main() {
    vec4 albedo = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    out_position = vec4(v_view_pos, 1.0);
    out_normal = vec4(v_view_normal * 0.5 + 0.5, 1.0);
    out_albedo = albedo;
}
@end

@program geom geom_vs geom_fs
]]

-- Lighting Pass Shader: simple diffuse + ambient
local light_shader_source = [[
@vs light_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
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
    vec4 light_pos_view;
    vec4 light_color;
    vec4 ambient_color;
};

void main() {
    vec4 position = texture(sampler2D(position_tex, position_smp), v_uv);
    vec3 view_pos = position.rgb;
    vec3 view_normal = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb * 2.0 - 1.0;
    vec4 albedo = texture(sampler2D(albedo_tex, albedo_smp), v_uv);

    // Sky background if no geometry
    if (position.a < 0.01) {
        frag_color = vec4(0.4, 0.5, 0.7, 1.0);
        return;
    }

    vec3 light_dir = normalize(light_pos_view.xyz - view_pos);
    vec3 n = normalize(view_normal);

    // Simple diffuse + ambient
    float diff = max(dot(n, light_dir), 0.0);
    vec3 diffuse = diff * light_color.rgb * albedo.rgb;
    vec3 ambient = ambient_color.rgb * albedo.rgb;

    vec3 color = ambient + diffuse;
    frag_color = vec4(color, 1.0);
}
@end

@program light light_vs light_fs
]]

local function create_gbuffer(w, h)
    -- Clean up old resources
    if gbuf_position_img then gfx.destroy_image(gbuf_position_img) end
    if gbuf_normal_img then gfx.destroy_image(gbuf_normal_img) end
    if gbuf_albedo_img then gfx.destroy_image(gbuf_albedo_img) end
    if gbuf_depth_img then gfx.destroy_image(gbuf_depth_img) end
    if gbuf_position_attach then gfx.destroy_view(gbuf_position_attach) end
    if gbuf_normal_attach then gfx.destroy_view(gbuf_normal_attach) end
    if gbuf_albedo_attach then gfx.destroy_view(gbuf_albedo_attach) end
    if gbuf_depth_attach then gfx.destroy_view(gbuf_depth_attach) end
    if gbuf_position_tex then gfx.destroy_view(gbuf_position_tex) end
    if gbuf_normal_tex then gfx.destroy_view(gbuf_normal_tex) end
    if gbuf_albedo_tex then gfx.destroy_view(gbuf_albedo_tex) end

    -- Position buffer (RGBA32F)
    gbuf_position_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA32F,
    }))
    gbuf_position_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = gbuf_position_img },
    }))
    gbuf_position_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = gbuf_position_img },
    }))

    -- Normal buffer (RGBA16F)
    gbuf_normal_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA16F,
    }))
    gbuf_normal_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = gbuf_normal_img },
    }))
    gbuf_normal_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = gbuf_normal_img },
    }))

    -- Albedo buffer (RGBA8)
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
    if not gbuf_sampler then
        gbuf_sampler = gfx.make_sampler(gfx.SamplerDesc({
            min_filter = gfx.Filter.NEAREST,
            mag_filter = gfx.Filter.NEAREST,
            wrap_u = gfx.Wrap.CLAMP_TO_EDGE,
            wrap_v = gfx.Wrap.CLAMP_TO_EDGE,
        }))
    end
end

local function compute_tangent(p1, p2, p3, uv1, uv2, uv3)
    local e1 = { p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3] }
    local e2 = { p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3] }
    local duv1 = { uv2[1] - uv1[1], uv2[2] - uv1[2] }
    local duv2 = { uv3[1] - uv1[1], uv3[2] - uv1[2] }
    local f = duv1[1] * duv2[2] - duv2[1] * duv1[2]
    if math.abs(f) < 0.0001 then f = 1 end
    f = 1.0 / f
    return f * (duv2[2] * e1[1] - duv1[2] * e2[1]),
        f * (duv2[2] * e1[2] - duv1[2] * e2[2]),
        f * (duv2[2] * e1[3] - duv1[2] * e2[3])
end

function init()
    util.info("Simple Deferred Rendering init")
    imgui.setup()
    meshes = {}
    textures_cache = {}


    local width, height = app.width(), app.height()
    create_gbuffer(width, height)

    -- Create full-screen quad
    local quad_vertices = {
        -1, -1, 0, 0,
        1, -1, 1, 0,
        1, 1, 1, 1,
        -1, -1, 0, 0,
        1, 1, 1, 1,
        -1, 1, 0, 1,
    }
    local quad_data = string.pack(string.rep("f", #quad_vertices), table.unpack(quad_vertices))
    quad_vbuf = gfx.make_buffer(gfx.BufferDesc({ data = gfx.Range(quad_data) }))

    -- Compile G-Buffer shader
    local geom_desc = {
        uniform_blocks = {
            { stage = gfx.ShaderStage.VERTEX, size = 192 }, -- 3x mat4
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "diffuse_tex_diffuse_smp" },
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
        util.error("Failed to compile geom shader")
        return
    end

    geom_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = geom_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 }, -- pos
                { format = gfx.VertexFormat.FLOAT3 }, -- normal
                { format = gfx.VertexFormat.FLOAT2 }, -- uv
                { format = gfx.VertexFormat.FLOAT3 }, -- tangent
            },
        },
        depth = {
            write_enabled = true,
            compare = gfx.CompareFunc.LESS_EQUAL,
            pixel_format = gfx.PixelFormat.DEPTH,
        },
        cull_mode = gfx.CullMode.FRONT,
        color_count = 3,
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA32F },
            { pixel_format = gfx.PixelFormat.RGBA16F },
            { pixel_format = gfx.PixelFormat.RGBA8 },
        },
        index_type = gfx.IndexType.UINT32,
        label = "geom_pipeline",
    }))

    -- Compile lighting shader
    local light_desc = {
        uniform_blocks = {
            { stage = gfx.ShaderStage.FRAGMENT, size = 48 }, -- 3x vec4
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
        util.error("Failed to compile light shader")
        return
    end

    light_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = light_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 }, -- pos
                { format = gfx.VertexFormat.FLOAT2 }, -- uv
            },
        },
        label = "light_pipeline",
    }))

    -- Load model
    util.info("Loading mill-scene...")
    local model = require("mill-scene")
    util.info("Model loaded, processing meshes...")

    local default_texture = nil

    for mat_name, mesh_data in pairs(model.meshes) do
        local vertices = mesh_data.vertices
        local indices = mesh_data.indices

        -- Compute tangents
        local in_stride = 8
        local vertex_count = #vertices / in_stride
        local tangents = {}
        for i = 0, vertex_count - 1 do
            tangents[i] = { 0, 0, 0 }
        end

        for i = 1, #indices, 3 do
            local i1, i2, i3 = indices[i], indices[i + 1], indices[i + 2]
            local base1, base2, base3 = i1 * in_stride, i2 * in_stride, i3 * in_stride
            local p1 = { vertices[base1 + 1], vertices[base1 + 2], vertices[base1 + 3] }
            local p2 = { vertices[base2 + 1], vertices[base2 + 2], vertices[base2 + 3] }
            local p3 = { vertices[base3 + 1], vertices[base3 + 2], vertices[base3 + 3] }
            local uv1 = { vertices[base1 + 7], vertices[base1 + 8] }
            local uv2 = { vertices[base2 + 7], vertices[base2 + 8] }
            local uv3 = { vertices[base3 + 7], vertices[base3 + 8] }
            local tx, ty, tz = compute_tangent(p1, p2, p3, uv1, uv2, uv3)
            for _, idx in ipairs({ i1, i2, i3 }) do
                tangents[idx][1] = tangents[idx][1] + tx
                tangents[idx][2] = tangents[idx][2] + ty
                tangents[idx][3] = tangents[idx][3] + tz
            end
        end

        -- Build vertex buffer with tangents
        local verts = {}
        for i = 0, vertex_count - 1 do
            local base = i * in_stride
            local t = tangents[i]
            local len = math.sqrt(t[1] * t[1] + t[2] * t[2] + t[3] * t[3])
            if len > 0.0001 then
                t[1], t[2], t[3] = t[1] / len, t[2] / len, t[3] / len
            else
                t[1], t[2], t[3] = 1, 0, 0
            end
            -- pos(3) + normal(3) + uv(2) + tangent(3) = 11 floats
            table.insert(verts, vertices[base + 1])
            table.insert(verts, vertices[base + 2])
            table.insert(verts, vertices[base + 3])
            table.insert(verts, vertices[base + 4])
            table.insert(verts, vertices[base + 5])
            table.insert(verts, vertices[base + 6])
            table.insert(verts, vertices[base + 7])
            table.insert(verts, vertices[base + 8])
            table.insert(verts, t[1])
            table.insert(verts, t[2])
            table.insert(verts, t[3])
        end

        local vdata = util.pack_floats(verts)
        local vbuf = gfx.make_buffer(gfx.BufferDesc({ data = gfx.Range(vdata) }))

        local idata = util.pack_u32(indices)
        local ibuf = gfx.make_buffer(gfx.BufferDesc({
            usage = { index_buffer = true },
            data = gfx.Range(idata),
        }))

        -- Load texture
        local tex_view, tex_smp
        if mesh_data.textures and #mesh_data.textures > 0 then
            local tex_info = model.textures[mesh_data.textures[1]]
            if tex_info then
                local path = util.resolve_path(tex_info.path)
                if not textures_cache[path] then
                    local view, smp = util.load_texture(path)
                    if view then
                        textures_cache[path] = { view = view, smp = smp }
                    end
                end
                if textures_cache[path] then
                    tex_view = textures_cache[path].view
                    tex_smp = textures_cache[path].smp
                end
            end
        end

        -- Create default white texture if needed
        if not tex_view then
            util.info("Using default white texture for material: " .. mat_name)
            if not default_texture then
                local white = string.pack("BBBB", 255, 255, 255, 255)
                local img = gfx.make_image(gfx.ImageDesc({
                    width = 1,
                    height = 1,
                    pixel_format = gfx.PixelFormat.RGBA8,
                    data = { mip_levels = { white } },
                }))
                local view = gfx.make_view(gfx.ViewDesc({
                    texture = { image = img },
                }))
                local smp = gfx.make_sampler(gfx.SamplerDesc({
                    min_filter = gfx.Filter.NEAREST,
                    mag_filter = gfx.Filter.NEAREST,
                }))
                default_texture = { img = img, view = view, smp = smp }
            end
            tex_view = default_texture.view
            tex_smp = default_texture.smp
        end

        -- Skip water meshes
        if not mat_name:find("water") and not mat_name:find("Water") then
            table.insert(meshes, {
                vbuf = vbuf,
                ibuf = ibuf,
                num_indices = #indices,
                tex_view = tex_view,
                tex_smp = tex_smp,
            })
        end
    end

    util.info("Loaded " .. #meshes .. " meshes")
end

function frame()
    hotreload.update()

    local width, height = app.width(), app.height()

    -- Camera update
    camera.update()
    local view = camera.view_matrix()
    local proj = camera.projection_matrix(width, height)
    local model_mat = glm.mat4()

    imgui.new_frame()

    -- G-Buffer Pass
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

    if geom_pipeline then
        gfx.apply_pipeline(geom_pipeline)
    end

    local mvp = proj * view * model_mat
    local vs_uniforms = mvp:pack() .. model_mat:pack() .. view:pack()

    for _, mesh in ipairs(meshes) do
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf },
            index_buffer = mesh.ibuf,
            views = { mesh.tex_view },
            samplers = { mesh.tex_smp },
        }))
        gfx.apply_uniforms(0, gfx.Range(vs_uniforms))
        gfx.draw(0, mesh.num_indices, 1)
    end

    gfx.end_pass()

    -- Lighting Pass
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 } } },
        }),
        swapchain = glue.swapchain(),
    }))

    if light_pipeline then
        gfx.apply_pipeline(light_pipeline)
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { quad_vbuf },
            views = { gbuf_position_tex, gbuf_normal_tex, gbuf_albedo_tex },
            samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler },
        }))
    end

    local fs_uniforms = light.pack_uniforms(view)
    gfx.apply_uniforms(0, gfx.Range(fs_uniforms))
    gfx.draw(0, 6, 1)

    -- ImGui
    if imgui.Begin("Deferred Rendering") then
        imgui.Text("Simple Deferred Rendering Tutorial")
        imgui.Separator()
        imgui.Text(string.format("Camera: %.1f, %.1f, %.1f", camera.pos.x, camera.pos.y, camera.pos.z))
        imgui.Text("WASD: Move, Mouse: Look (right-click to capture)")
        imgui.Separator()

        local lx, ly, lz, lchanged = imgui.InputFloat3("Light Pos", light.pos.x, light.pos.y, light.pos.z)
        if lchanged then light.pos = glm.vec3(lx, ly, lz) end

        local lr, lg, lb, lcchanged = imgui.ColorEdit3("Light Color", light.color.x, light.color.y, light.color.z)
        if lcchanged then light.color = glm.vec3(lr, lg, lb) end

        local ar, ag, ab, achanged = imgui.ColorEdit3("Ambient", light.ambient.x, light.ambient.y, light.ambient.z)
        if achanged then light.ambient = glm.vec3(ar, ag, ab) end
    end
    imgui.End()

    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function cleanup()
    imgui.shutdown()
    -- Clean up G-Buffer
    if gbuf_position_img then gfx.destroy_image(gbuf_position_img) end
    if gbuf_normal_img then gfx.destroy_image(gbuf_normal_img) end
    if gbuf_albedo_img then gfx.destroy_image(gbuf_albedo_img) end
    if gbuf_depth_img then gfx.destroy_image(gbuf_depth_img) end
    if gbuf_position_attach then gfx.destroy_view(gbuf_position_attach) end
    if gbuf_normal_attach then gfx.destroy_view(gbuf_normal_attach) end
    if gbuf_albedo_attach then gfx.destroy_view(gbuf_albedo_attach) end
    if gbuf_depth_attach then gfx.destroy_view(gbuf_depth_attach) end
    if gbuf_position_tex then gfx.destroy_view(gbuf_position_tex) end
    if gbuf_normal_tex then gfx.destroy_view(gbuf_normal_tex) end
    if gbuf_albedo_tex then gfx.destroy_view(gbuf_albedo_tex) end
    if gbuf_sampler then gfx.destroy_sampler(gbuf_sampler) end
    -- Clean up pipelines and shaders
    if geom_pipeline then gfx.destroy_pipeline(geom_pipeline) end
    if geom_shader then gfx.destroy_shader(geom_shader) end
    if light_pipeline then gfx.destroy_pipeline(light_pipeline) end
    if light_shader then gfx.destroy_shader(light_shader) end
    if quad_vbuf then gfx.destroy_buffer(quad_vbuf) end
    -- Clean up meshes
    for _, mesh in ipairs(meshes) do
        gfx.destroy_buffer(mesh.vbuf)
        gfx.destroy_buffer(mesh.ibuf)
    end
    -- Clean up textures
    for _, tex in pairs(textures_cache) do
        gfx.destroy_view(tex.view)
        gfx.destroy_sampler(tex.smp)
    end
    util.info("cleanup")
end

function event(ev)
    if imgui.handle_event(ev) then
        return
    end

    -- Camera handles most input
    if camera.handle_event(ev) then
        return
    end

    -- ESC to quit (when camera not captured)
    if ev.type == app.EventType.KEY_DOWN and ev.key_code == app.Keycode.ESCAPE then
        app.request_quit()
    end
end
