-- examples/rendering/lighting.lua
-- Lighting pass: p3d_LightSourceParameters based multi-light (shadow excluded)
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local render_pass = require("lib.render_pass")
local light_module = require("examples.rendering.light")

local M = {}

M.name = "lighting"
M.requires = { "gbuf_position", "gbuf_normal", "gbuf_albedo", "gbuf_specular" }

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
#define NUMBER_OF_LIGHTS 4
#define MAX_SHININESS 127.75

in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D position_tex;
layout(binding=0) uniform sampler position_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;
layout(binding=2) uniform texture2D albedo_tex;
layout(binding=2) uniform sampler albedo_smp;
layout(binding=3) uniform texture2D specular_tex;
layout(binding=3) uniform sampler specular_smp;

// p3d_LightSourceParameters equivalent - flattened for sokol-shdc
// Each light = 8 vec4 = 128 bytes, 4 lights = 512 bytes
// Layout per light:
//   [0] color
//   [1] ambient
//   [2] diffuse
//   [3] specular
//   [4] position (w=0: directional, w=1: positional)
//   [5] spot_direction (xyz=direction, w=exponent)
//   [6] spot_params (x=cutoff, y=cosCutoff)
//   [7] attenuation (x=constant, y=linear, z=quadratic)

layout(binding=0) uniform fs_params {
    vec4 light_data[NUMBER_OF_LIGHTS * 8];  // 32 vec4 = 512 bytes
    vec4 light_model_ambient;               // p3d_LightModel.ambient
    int num_lights;
    float gamma;
    float gamma_rec;                        // 1/gamma
    float pad0;
    int blinn_phong_enabled;                // 1 = Blinn-Phong, 0 = Phong
    int fresnel_enabled;                    // 1 = Fresnel, 0 = no Fresnel
    float max_fresnel_power;                // specular_map.b * this value
    int rim_light_enabled;                  // 1 = Rim Light, 0 = no Rim Light
    int debug_mode;                         // 0=off, 1=fresnel, 2=normal, 3=specular
    int pad1;
    int pad2;
    int pad3;
};

// Helper to access light fields
#define LIGHT_COLOR(i)         light_data[(i) * 8 + 0]
#define LIGHT_AMBIENT(i)       light_data[(i) * 8 + 1]
#define LIGHT_DIFFUSE(i)       light_data[(i) * 8 + 2]
#define LIGHT_SPECULAR(i)      light_data[(i) * 8 + 3]
#define LIGHT_POSITION(i)      light_data[(i) * 8 + 4]
#define LIGHT_SPOT_DIRECTION(i) light_data[(i) * 8 + 5]
#define LIGHT_SPOT_PARAMS(i)   light_data[(i) * 8 + 6]
#define LIGHT_ATTENUATION(i)   light_data[(i) * 8 + 7]

void main() {
    vec4 position_data = texture(sampler2D(position_tex, position_smp), v_uv);
    vec3 view_pos = position_data.rgb;
    vec3 view_normal = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb * 2.0 - 1.0;
    vec4 albedo = texture(sampler2D(albedo_tex, albedo_smp), v_uv);
    vec4 specular_map = texture(sampler2D(specular_tex, specular_smp), v_uv);

    // Sky background if no geometry (alpha=0 in position buffer)
    if (position_data.a < 0.01) {
        frag_color = vec4(0.4, 0.5, 0.7, 1.0);
        return;
    }

    vec3 normal = normalize(view_normal);
    vec3 eye_direction = normalize(-view_pos);

    // sRGB -> Linear (gamma correction)
    vec3 albedo_linear = pow(albedo.rgb, vec3(gamma));

    // Specular map channels (from base.frag):
    // R = specular intensity
    // G = shininess factor (0-1, multiplied by MAX_SHININESS)
    float material_specular = specular_map.r;
    float shininess = max(specular_map.g * MAX_SHININESS, 1.0);

    vec3 diffuse_total = vec3(0.0);
    vec3 specular_total = vec3(0.0);

    for (int i = 0; i < NUMBER_OF_LIGHTS; ++i) {
        if (i >= num_lights) break;

        vec4 l_position = LIGHT_POSITION(i);
        vec4 l_diffuse = LIGHT_DIFFUSE(i);
        vec4 l_specular = LIGHT_SPECULAR(i);
        vec4 l_spot_direction = LIGHT_SPOT_DIRECTION(i);
        vec4 l_spot_params = LIGHT_SPOT_PARAMS(i);
        vec4 l_attenuation = LIGHT_ATTENUATION(i);

        // Light colors: sRGB -> Linear
        vec3 light_diffuse = pow(l_diffuse.rgb, vec3(gamma));
        vec3 light_specular = pow(l_specular.rgb, vec3(gamma));

        // Light direction calculation (from base.frag line 152-155)
        // For directional: position.w = 0, so lightDirection = position.xyz
        // For positional: position.w = 1, so lightDirection = position.xyz - vertexPosition.xyz
        vec3 light_direction = l_position.xyz - view_pos * l_position.w;

        vec3 unit_light_direction = normalize(light_direction);
        float light_distance = length(light_direction);

        // Attenuation (from base.frag line 164-171)
        float attenuation = 1.0 / (
            l_attenuation.x +
            l_attenuation.y * light_distance +
            l_attenuation.z * light_distance * light_distance
        );

        if (attenuation <= 0.0) continue;

        // Diffuse intensity (from base.frag line 175)
        float diffuse_intensity = dot(normal, unit_light_direction);
        if (diffuse_intensity < 0.0) continue;

        // Diffuse color (from base.frag line 184-197)
        vec3 diffuse_temp = clamp(
            albedo_linear * light_diffuse * diffuse_intensity,
            0.0, 1.0
        );

        // Specular: Blinn-Phong or Phong (from base.frag line 199-227)
        vec3 halfway_direction = normalize(unit_light_direction + eye_direction);
        vec3 reflected_direction = normalize(-reflect(unit_light_direction, normal));
        float specular_intensity = (blinn_phong_enabled == 1)
            ? clamp(dot(normal, halfway_direction), 0.0, 1.0)
            : clamp(dot(eye_direction, reflected_direction), 0.0, 1.0);

        // Fresnel effect (from base.frag line 215-221)
        float fresnel_mat_specular = material_specular;
        if (fresnel_enabled == 1) {
            float fresnel_dot = (blinn_phong_enabled == 1)
                ? dot(halfway_direction, eye_direction)
                : dot(normal, eye_direction);
            float fresnel_factor = max(fresnel_dot, 0.0);
            fresnel_factor = 1.0 - fresnel_factor;
            fresnel_factor = pow(fresnel_factor, specular_map.b * max_fresnel_power);
            fresnel_mat_specular = mix(material_specular, 1.0, clamp(fresnel_factor, 0.0, 1.0));
        }

        // Use specular map for shininess and material specular intensity
        vec3 specular_temp = light_specular * pow(specular_intensity, shininess);
        specular_temp *= fresnel_mat_specular;
        specular_temp = clamp(specular_temp, 0.0, 1.0);

        // Spotlight check (from base.frag line 229-239)
        // spot_params.y = cosCutoff, if > -1.0, it's a spotlight
        if (l_spot_params.y > -1.0) {
            float spot_cos_cutoff = l_spot_params.y;
            vec3 spot_direction = normalize(l_spot_direction.xyz);
            float spot_dot = dot(spot_direction, -unit_light_direction);

            if (spot_dot < spot_cos_cutoff) continue;

            // Spot exponent falloff
            float spot_exponent = l_spot_direction.w;
            if (spot_exponent > 0.0) {
                float spot_factor = pow(spot_dot, spot_exponent);
                diffuse_temp *= spot_factor;
                specular_temp *= spot_factor;
            }
        }

        // Apply attenuation
        diffuse_temp *= attenuation;
        specular_temp *= attenuation;

        diffuse_total += diffuse_temp;
        specular_total += specular_temp;
    }

    // Ambient (from base.frag line 312-322, simplified)
    vec3 ambient = pow(light_model_ambient.rgb, vec3(gamma)) * albedo_linear;

    // Rim light (from base.frag line 278-294)
    vec3 rim_light = vec3(0.0);
    if (rim_light_enabled == 1) {
        float rim_factor = 1.0 - max(0.0, dot(eye_direction, normal));
        rim_light = vec3(pow(rim_factor, 2.0) * 1.2);
        rim_light *= diffuse_total;
    }

    // Final color (from base.frag line 326-330)
    vec3 color = ambient + diffuse_total + rim_light + specular_total;

    // Debug modes
    if (debug_mode == 1) {
        // Fresnel factor visualization (based on view angle)
        float fresnel_debug = 1.0 - max(0.0, dot(eye_direction, normal));
        fresnel_debug = pow(fresnel_debug, specular_map.b * max_fresnel_power);
        frag_color = vec4(vec3(fresnel_debug), 1.0);
        return;
    } else if (debug_mode == 2) {
        // Normal visualization
        frag_color = vec4(normal * 0.5 + 0.5, 1.0);
        return;
    } else if (debug_mode == 3) {
        // Specular map visualization (R=intensity, G=shininess, B=fresnel)
        frag_color = vec4(specular_map.rgb, 1.0);
        return;
    }

    // Linear -> sRGB (gamma correction)
    color = pow(color, vec3(gamma_rec));

    frag_color = vec4(color, 1.0);
}
@end

@program light light_vs light_fs
]]

M.shader_desc = {
    uniform_blocks = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            size = light_module.uniform_size(), -- 544 bytes
        },
    },
    views = {
        {
            texture = {
                stage = gfx.ShaderStage.FRAGMENT,
                image_type = gfx.ImageType["2D"],
                sample_type = gfx.ImageSampleType.FLOAT,
                hlsl_register_t_n = 0,
                wgsl_group1_binding_n = 0,
            },
        },
        {
            texture = {
                stage = gfx.ShaderStage.FRAGMENT,
                image_type = gfx.ImageType["2D"],
                sample_type = gfx.ImageSampleType.FLOAT,
                hlsl_register_t_n = 1,
                wgsl_group1_binding_n = 1,
            },
        },
        {
            texture = {
                stage = gfx.ShaderStage.FRAGMENT,
                image_type = gfx.ImageType["2D"],
                sample_type = gfx.ImageSampleType.FLOAT,
                hlsl_register_t_n = 2,
                wgsl_group1_binding_n = 2,
            },
        },
        {
            texture = {
                stage = gfx.ShaderStage.FRAGMENT,
                image_type = gfx.ImageType["2D"],
                sample_type = gfx.ImageSampleType.FLOAT,
                hlsl_register_t_n = 3,
                wgsl_group1_binding_n = 3,
            },
        },
    },
    samplers = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 0,
            wgsl_group1_binding_n = 32,
        },
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 1,
            wgsl_group1_binding_n = 33,
        },
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 2,
            wgsl_group1_binding_n = 34,
        },
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 3,
            wgsl_group1_binding_n = 35,
        },
    },
    texture_sampler_pairs = {
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "albedo_tex_albedo_smp" },
        { stage = gfx.ShaderStage.FRAGMENT, view_slot = 3, sampler_slot = 3, glsl_name = "specular_tex_specular_smp" },
    },
    attrs = {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
    },
}

-- Setup common resource management (on_reload, destroy, ensure_resources)
render_pass.setup(M, {
    shader_name = "light",
    pipeline_desc = function(shader_handle)
        return gfx.PipelineDesc({
            shader = shader_handle,
            layout = {
                attrs = {
                    { format = gfx.VertexFormat.FLOAT2 }, -- pos
                    { format = gfx.VertexFormat.FLOAT2 }, -- uv
                },
            },
            label = "light_pipeline",
        })
    end,
})

---Get pass descriptor for lighting (renders to swapchain)
---@param ctx rendering.Context
---@return any? desc Pass descriptor, nil to skip
function M.get_pass_desc(_ctx)
    if not M.ensure_resources() then
        return nil
    end

    return gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 } } },
        }),
        swapchain = glue.swapchain(),
    })
end

---Execute lighting pass, rendering to swapchain
---@param ctx rendering.Context
---@param frame_data {light_uniforms: string}
function M.execute(ctx, frame_data)
    gfx.apply_pipeline(M.resources.pipeline.handle)
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { ctx.quad_vbuf.handle },
        views = {
            ctx.outputs.gbuf_position.handle,
            ctx.outputs.gbuf_normal.handle,
            ctx.outputs.gbuf_albedo.handle,
            ctx.outputs.gbuf_specular.handle,
        },
        samplers = {
            ctx.gbuf_sampler.handle,
            ctx.gbuf_sampler.handle,
            ctx.gbuf_sampler.handle,
            ctx.gbuf_sampler.handle,
        },
    }))

    gfx.apply_uniforms(0, gfx.Range(frame_data.light_uniforms))
    gfx.draw(0, 6, 1)
end

return M
