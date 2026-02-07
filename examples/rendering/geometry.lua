-- examples/rendering/geometry.lua
-- G-Buffer geometry pass
local gfx = require("sokol.gfx")
local render_pass = require("lib.render_pass")

---@class rendering.Mesh
---@field vbuf gpu.Buffer Vertex buffer
---@field ibuf gpu.Buffer Index buffer
---@field num_indices integer
---@field diffuse_view any Diffuse texture view handle
---@field diffuse_smp any Diffuse sampler handle
---@field normal_view any Normal texture view handle
---@field normal_smp any Normal sampler handle
---@field specular_view any Specular texture view handle
---@field specular_smp any Specular sampler handle

local M = {}

M.name = "geometry"

M.shader_source = [[
@vs geom_vs
in vec3 pos;
in vec3 normal;
in vec2 uv;
in vec3 tangent;

out vec3 v_view_pos;
out vec3 v_view_normal;
out vec3 v_view_tangent;
out vec3 v_view_bitangent;
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
    v_view_tangent = normalize(normal_mat * tangent);
    v_view_bitangent = cross(v_view_normal, v_view_tangent);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs geom_fs
in vec3 v_view_pos;
in vec3 v_view_normal;
in vec3 v_view_tangent;
in vec3 v_view_bitangent;
in vec2 v_uv;

layout(location=0) out vec4 out_position;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_albedo;
layout(location=3) out vec4 out_specular;

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;
layout(binding=2) uniform texture2D specular_tex;
layout(binding=2) uniform sampler specular_smp;

void main() {
    vec4 albedo = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    vec4 specular = texture(sampler2D(specular_tex, specular_smp), v_uv);

    // Normal mapping: transform from tangent space to view space
    vec3 normal_map = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb * 2.0 - 1.0;
    mat3 tbn = mat3(v_view_tangent, v_view_bitangent, v_view_normal);
    vec3 view_normal = normalize(tbn * normal_map);

    out_position = vec4(v_view_pos, 1.0);
    out_normal = vec4(view_normal * 0.5 + 0.5, 1.0);
    out_albedo = albedo;
    out_specular = specular;
}
@end

@program geom geom_vs geom_fs
]]

M.shader_desc = {
    uniform_blocks = {
        { stage = gfx.ShaderStage.VERTEX, size = 192 }, -- 3x mat4
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
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "diffuse_tex_diffuse_smp" },
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "specular_tex_specular_smp" },
    },
    attrs = {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 2 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 3 },
    },
}

-- Setup common resource management (on_reload, destroy, ensure_resources)
render_pass.setup(M, {
    shader_name = "geom",
    pipeline_desc = function(shader_handle)
        return gfx.PipelineDesc({
            shader = shader_handle,
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
            color_count = 4,
            colors = {
                { pixel_format = gfx.PixelFormat.RGBA32F },  -- position
                { pixel_format = gfx.PixelFormat.RGBA16F },  -- normal
                { pixel_format = gfx.PixelFormat.RGBA8 },    -- albedo
                { pixel_format = gfx.PixelFormat.RGBA8 },    -- specular
            },
            index_type = gfx.IndexType.UINT32,
            label = "geom_pipeline",
        })
    end,
})

---Get pass descriptor for G-Buffer rendering
---@param ctx rendering.Context
---@return any? desc Pass descriptor, nil to skip
function M.get_pass_desc(ctx)
    if not M.ensure_resources() then return nil end

    return gfx.Pass({
        action = gfx.PassAction({
            colors = {
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.5, g = 0.5, b = 0.5, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
            },
            depth = { load_action = gfx.LoadAction.CLEAR, clear_value = 1.0 },
        }),
        attachments = {
            colors = {
                ctx.targets.gbuf_position.attach.handle,
                ctx.targets.gbuf_normal.attach.handle,
                ctx.targets.gbuf_albedo.attach.handle,
                ctx.targets.gbuf_specular.attach.handle,
            },
            depth_stencil = ctx.targets.depth.attach.handle,
        },
    })
end

---Execute geometry pass, writing to G-Buffer
---@param ctx rendering.Context
---@param frame_data {meshes: rendering.Mesh[], view: mat4, proj: mat4, model: mat4}
function M.execute(ctx, frame_data)
    local meshes = frame_data.meshes
    local view_matrix = frame_data.view
    local proj_matrix = frame_data.proj
    local model_matrix = frame_data.model

    gfx.ApplyPipeline(M.resources.pipeline.handle)

    local mvp = proj_matrix * view_matrix * model_matrix
    local vs_uniforms = mvp:pack() .. model_matrix:pack() .. view_matrix:pack()

    for _, mesh in ipairs(meshes) do
        gfx.ApplyBindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf.handle },
            index_buffer = mesh.ibuf.handle,
            views = { mesh.diffuse_view, mesh.normal_view, mesh.specular_view },
            samplers = { mesh.diffuse_smp, mesh.normal_smp, mesh.specular_smp },
        }))
        gfx.ApplyUniforms(0, gfx.Range(vs_uniforms))
        gfx.Draw(0, mesh.num_indices, 1)
    end

    -- Set outputs for downstream passes
    ctx.outputs.gbuf_position = ctx.targets.gbuf_position.tex
    ctx.outputs.gbuf_normal = ctx.targets.gbuf_normal.tex
    ctx.outputs.gbuf_albedo = ctx.targets.gbuf_albedo.tex
    ctx.outputs.gbuf_specular = ctx.targets.gbuf_specular.tex
end

return M
