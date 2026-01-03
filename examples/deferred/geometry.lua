-- examples/deferred/geometry.lua
-- G-Buffer geometry pass
local gfx = require("sokol.gfx")
local gpu = require("lib.gpu")

---@class deferred.Mesh
---@field vbuf gpu.Buffer Vertex buffer
---@field ibuf gpu.Buffer Index buffer
---@field num_indices integer
---@field tex_view any Texture view handle
---@field tex_smp any Sampler handle

---@class deferred.GeometryPass : RenderPass
---@field name string Pass name
---@field shader_source string GLSL shader source
---@field shader_desc table Shader descriptor
---@field resources deferred.GeometryResources? Compiled shader/pipeline
---@field get_pass_desc fun(ctx: deferred.Context): any? Get pass descriptor
---@field execute fun(ctx: deferred.Context, frame_data: table) Execute drawing
---@field destroy fun() Destroy resources
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

M.shader_desc = {
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

---@class deferred.GeometryResources
---@field shader gpu.Shader
---@field pipeline gpu.Pipeline

-- Resources stored in module table to survive hotreload
---@type deferred.GeometryResources?
M.resources = M.resources

-- Track if we've attempted compilation (reset on hotreload by shader_source change)
M._last_shader_source = M._last_shader_source

---Lazy init resources
---@return boolean success
local function ensure_resources()
    if M.resources then return true end

    -- Don't retry if same shader source already failed
    if M._last_shader_source == M.shader_source then return false end
    M._last_shader_source = M.shader_source

    local shader = gpu.shader(M.shader_source, "geom", M.shader_desc)
    if not shader then return false end

    local pipeline = gpu.pipeline(gfx.PipelineDesc({
        shader = shader.handle,
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

    M.resources = { shader = shader, pipeline = pipeline }
    return true
end

---Get pass descriptor for G-Buffer rendering
---Returns nil if shader failed to compile, skipping this pass
---@param ctx deferred.Context
---@return any? desc Pass descriptor, nil to skip
function M.get_pass_desc(ctx)
    if not ensure_resources() then return nil end

    return gfx.Pass({
        action = gfx.PassAction({
            colors = {
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.5, g = 0.5, b = 0.5, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
            },
            depth = { load_action = gfx.LoadAction.CLEAR, clear_value = 1.0 },
        }),
        attachments = {
            colors = {
                ctx.targets.gbuf_position.attach.handle,
                ctx.targets.gbuf_normal.attach.handle,
                ctx.targets.gbuf_albedo.attach.handle,
            },
            depth_stencil = ctx.targets.depth.attach.handle,
        },
    })
end

---Execute geometry pass, writing to G-Buffer
---Called between begin_pass/end_pass by pipeline
---@param ctx deferred.Context
---@param frame_data {meshes: deferred.Mesh[], view: mat4, proj: mat4, model: mat4}
function M.execute(ctx, frame_data)
    local meshes = frame_data.meshes
    local view_matrix = frame_data.view
    local proj_matrix = frame_data.proj
    local model_matrix = frame_data.model

    gfx.apply_pipeline(M.resources.pipeline.handle)

    local mvp = proj_matrix * view_matrix * model_matrix
    local vs_uniforms = mvp:pack() .. model_matrix:pack() .. view_matrix:pack()

    for _, mesh in ipairs(meshes) do
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf.handle },
            index_buffer = mesh.ibuf.handle,
            views = { mesh.tex_view },
            samplers = { mesh.tex_smp },
        }))
        gfx.apply_uniforms(0, gfx.Range(vs_uniforms))
        gfx.draw(0, mesh.num_indices, 1)
    end

    -- Set outputs for downstream passes
    ctx.outputs.gbuf_position = ctx.targets.gbuf_position.tex
    ctx.outputs.gbuf_normal = ctx.targets.gbuf_normal.tex
    ctx.outputs.gbuf_albedo = ctx.targets.gbuf_albedo.tex
end

---Destroy pass resources
function M.destroy()
    if M.resources then
        M.resources.pipeline:destroy()
        M.resources.shader:destroy()
        M.resources = nil
    end
end

return M
