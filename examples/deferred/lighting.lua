-- examples/deferred/lighting.lua
-- Deferred lighting pass
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gpu = require("lib.gpu")

---@class deferred.LightingPass : RenderPass
---@field name string Pass name
---@field shader_source string GLSL shader source
---@field shader_desc table Shader descriptor
---@field resources deferred.LightingResources? Compiled shader/pipeline
---@field get_pass_desc fun(ctx: deferred.Context): any? Get pass descriptor
---@field execute fun(ctx: deferred.Context, frame_data: table) Execute drawing
---@field destroy fun() Destroy resources
local M = {}

M.name = "lighting"

M.shader_source = [[
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

M.shader_desc = {
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

---@class deferred.LightingResources
---@field shader gpu.Shader
---@field pipeline gpu.Pipeline

-- Resources stored in module table to survive hotreload
---@type deferred.LightingResources?
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

    local shader = gpu.shader(M.shader_source, "light", M.shader_desc)
    if not shader then return false end

    local pipeline = gpu.pipeline(gfx.PipelineDesc({
        shader = shader.handle,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 }, -- pos
                { format = gfx.VertexFormat.FLOAT2 }, -- uv
            },
        },
        label = "light_pipeline",
    }))

    M.resources = { shader = shader, pipeline = pipeline }
    return true
end

---Get pass descriptor for lighting (renders to swapchain)
---Returns nil if shader failed or G-Buffer not ready
---@param ctx deferred.Context
---@return any? desc Pass descriptor, nil to skip
function M.get_pass_desc(ctx)
    if not ensure_resources() then return nil end

    -- Check if G-Buffer outputs are available
    if not ctx.outputs.gbuf_position then return nil end

    return gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 } } },
        }),
        swapchain = glue.swapchain(),
    })
end

---Execute lighting pass, rendering to swapchain
---Called between begin_pass/end_pass by pipeline
---@param ctx deferred.Context
---@param frame_data {light_uniforms: string}
function M.execute(ctx, frame_data)
    gfx.apply_pipeline(M.resources.pipeline.handle)
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { ctx.quad_vbuf.handle },
        views = {
            ctx.outputs.gbuf_position.handle,
            ctx.outputs.gbuf_normal.handle,
            ctx.outputs.gbuf_albedo.handle,
        },
        samplers = {
            ctx.gbuf_sampler.handle,
            ctx.gbuf_sampler.handle,
            ctx.gbuf_sampler.handle,
        },
    }))

    gfx.apply_uniforms(0, gfx.Range(frame_data.light_uniforms))
    gfx.draw(0, 6, 1)
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
