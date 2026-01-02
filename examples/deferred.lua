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

-- Light (matches original sunlightColor1 and ambientLight)
local light_pos = glm.vec3(10, -10, 20)
local light_color = glm.vec3(0.765, 0.573, 0.400)
local ambient_color = glm.vec3(0.388, 0.356, 0.447)

-- Fog parameters
local fog_enabled = true
local fog_near = 20.0
local fog_far = 150.0
local fog_sun_position = 0.5  -- 0-1, affects color brightness
local fog_bg_color0 = { 0.7, 0.8, 0.9 }  -- Horizon color
local fog_bg_color1 = { 0.3, 0.4, 0.6 }  -- Zenith color

-- Lighting effect parameters
local fresnel_enabled = true
local fresnel_power = 5.0
local rim_light_enabled = true
local cel_shading_enabled = true

-- Blur parameters
local blur_enabled = false
local blur_size = 2
local blur_separation = 1.0

-- Bloom parameters
local bloom_enabled = true
local bloom_size = 3
local bloom_separation = 4.0
local bloom_threshold = 0.6
local bloom_amount = 0.6

-- SSAO parameters
local ssao_enabled = true
local ssao_radius = 0.6
local ssao_bias = 0.005
local ssao_intensity = 1.1

-- Motion blur parameters
local motion_blur_enabled = false
local motion_blur_size = 2
local motion_blur_separation = 1.0

-- Chromatic aberration parameters
local chromatic_enabled = true
local chromatic_red_offset = 0.009
local chromatic_green_offset = 0.006
local chromatic_blue_offset = -0.006

-- Screen Space Reflection parameters
local ssr_enabled = true
local ssr_max_distance = 8.0
local ssr_resolution = 0.3
local ssr_steps = 5
local ssr_thickness = 0.5
local ssr_debug = 0  -- 0=off, 1=mask, 2=water pos.w, 3=ray dir

-- Screen Space Refraction parameters
local refraction_enabled = true
local refraction_ior = 1.33  -- Water: ~1.33, Glass: ~1.5
local refraction_max_distance = 5.0
local refraction_resolution = 0.3
local refraction_steps = 5
local refraction_thickness = 0.5
-- Tint color (original: vec4(0.392, 0.537, 0.561, 0.8))
local refraction_tint_r = 0.392
local refraction_tint_g = 0.537
local refraction_tint_b = 0.561
local refraction_tint_a = 0.8  -- Tint intensity
local refraction_depth_max = 2.0
local refraction_debug = false  -- Show visibility debug

-- Debug buffer display
-- 0=Final, 1=Position, 2=Normal, 3=Albedo, 4=SSAO
-- 5=WaterPosition, 6=WaterNormal, 7=SSR_UV, 8=Reflection, 9=RefractionUV, 10=Refraction
local debug_buffer = 0
local debug_buffer_names = {
    "Final", "Position", "Normal", "Albedo", "SSAO",
    "Water Position", "Water Normal", "SSR UV", "Reflection", "Refraction UV", "Refraction"
}

-- Graphics resources
local geom_shader = nil
local water_geom_shader = nil  -- Water G-buffer with mask outputs
---@type gfx.Pipeline
local geom_pipeline = nil
---@type gfx.Pipeline
local water_geom_pipeline = nil  -- No culling for water, 5 color outputs
local light_shader = nil
---@type gfx.Pipeline
local light_pipeline = nil
local meshes = {}        -- Opaque meshes
local water_meshes = {}  -- Water/refractive meshes
local textures_cache = {}
local default_mask = nil

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

-- Water G-Buffer resources (second pass for refractive surfaces)
local water_position_img = nil
local water_normal_img = nil
local water_albedo_img = nil
local water_depth_img = nil
local water_position_attach = nil
local water_normal_attach = nil
local water_albedo_attach = nil
local water_reflection_mask_img = nil
local water_reflection_mask_attach = nil
local water_reflection_mask_tex = nil
local water_refraction_mask_img = nil
local water_refraction_mask_attach = nil
local water_refraction_mask_tex = nil
local water_depth_attach = nil
local water_position_tex = nil
local water_normal_tex = nil
local water_albedo_tex = nil

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

-- SSAO resources
local ssao_img = nil
local ssao_attach = nil
local ssao_tex = nil
local ssao_shader = nil
---@type gfx.Pipeline
local ssao_pipeline = nil

-- Motion blur resources
local motion_img = nil
local motion_attach = nil
local motion_tex = nil
local motion_shader = nil
---@type gfx.Pipeline
local motion_pipeline = nil

-- SSR resources
local ssr_uv_img = nil
local ssr_uv_attach = nil
local ssr_uv_tex = nil
local ssr_uv_shader = nil
---@type gfx.Pipeline
local ssr_uv_pipeline = nil

-- Reflection color resources
local reflection_img = nil
local reflection_attach = nil
local reflection_tex = nil
local reflection_shader = nil
---@type gfx.Pipeline
local reflection_pipeline = nil

-- Refraction UV resources
local refraction_uv_img = nil
local refraction_uv_attach = nil
local refraction_uv_tex = nil
local refraction_uv_shader = nil
---@type gfx.Pipeline
local refraction_uv_pipeline = nil

-- Refraction color resources
local refraction_img = nil
local refraction_attach = nil
local refraction_tex = nil
local refraction_shader = nil
---@type gfx.Pipeline
local refraction_pipeline = nil

-- Debug display
local debug_shader = nil
---@type gfx.Pipeline
local debug_pipeline = nil

-- Previous frame view matrix for motion blur
local prev_view = nil

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

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;

void main() {
    // Sample textures
    vec4 albedo = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    vec3 normal_map = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb;

    // Unpack and transform normal (in view space)
    vec3 n_tangent = normalize(normal_map * 2.0 - 1.0);
    mat3 tbn = mat3(v_view_tangent, v_view_bitangent, v_view_normal);
    vec3 n = normalize(tbn * n_tangent);

    // Output to G-Buffer (view space)
    out_position = vec4(v_view_pos, 1.0);
    out_normal = vec4(n * 0.5 + 0.5, 1.0);  // Pack to [0,1]
    out_albedo = albedo;
}
@end

@program geom geom_vs geom_fs
]]

-- Water G-Buffer Shader: outputs 5 targets (position, normal, albedo, reflection mask, refraction mask)
-- Based on lettier/3d-game-shaders-for-beginners geometry-buffer-1.frag
local water_geom_shader_source = [[
@vs water_geom_vs
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

@fs water_geom_fs
in vec3 v_view_pos;
in vec3 v_view_normal;
in vec3 v_view_tangent;
in vec3 v_view_bitangent;
in vec2 v_uv;

layout(location=0) out vec4 out_position;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_albedo;
layout(location=3) out vec4 out_reflection_mask;
layout(location=4) out vec4 out_refraction_mask;

layout(binding=0) uniform texture2D diffuse_tex;
layout(binding=0) uniform sampler diffuse_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;
layout(binding=2) uniform texture2D reflection_mask_tex;
layout(binding=2) uniform sampler reflection_mask_smp;
layout(binding=3) uniform texture2D refraction_mask_tex;
layout(binding=3) uniform sampler refraction_mask_smp;

void main() {
    // Sample textures
    vec4 albedo = texture(sampler2D(diffuse_tex, diffuse_smp), v_uv);
    vec3 normal_map = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb;
    vec4 reflection_mask = texture(sampler2D(reflection_mask_tex, reflection_mask_smp), v_uv);
    vec4 refraction_mask = texture(sampler2D(refraction_mask_tex, refraction_mask_smp), v_uv);

    // Unpack and transform normal (in view space)
    vec3 n_tangent = normalize(normal_map * 2.0 - 1.0);
    mat3 tbn = mat3(v_view_tangent, v_view_bitangent, v_view_normal);
    vec3 n = normalize(tbn * n_tangent);

    // Output to G-Buffer (view space)
    out_position = vec4(v_view_pos, 1.0);
    out_normal = vec4(n * 0.5 + 0.5, 1.0);  // Pack to [0,1]
    out_albedo = albedo;
    out_reflection_mask = reflection_mask;
    out_refraction_mask = refraction_mask;
}
@end

@program water_geom water_geom_vs water_geom_fs
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
layout(binding=3) uniform texture2D ssao_tex;
layout(binding=3) uniform sampler ssao_smp;

layout(binding=0) uniform fs_params {
    vec4 light_pos_view;     // Light position in view space
    vec4 light_color;
    vec4 ambient_color;
    vec4 backgroundColor0;   // Fog gradient color 0 (horizon)
    vec4 backgroundColor1;   // Fog gradient color 1 (zenith)
    vec4 fog_params;         // x = near, y = far, z = enabled, w = sunPosition
    vec4 fresnel_params;     // x = enabled, y = power
    vec4 rim_params;         // x = enabled, y = power
    vec4 cel_params;         // x = enabled
};

const float PI = 3.14159265359;
const float GAMMA = 2.2;

void main() {
    vec2 texSize = vec2(textureSize(sampler2D(position_tex, position_smp), 0));
    vec2 texCoord = gl_FragCoord.xy / texSize;

    // Sample G-Buffer (view space)
    vec4 position = texture(sampler2D(position_tex, position_smp), v_uv);
    vec3 view_pos = position.rgb;
    vec3 view_normal = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb * 2.0 - 1.0;
    vec4 albedo = texture(sampler2D(albedo_tex, albedo_smp), v_uv);

    // Calculate fog color (gradient sky with noise)
    float random = fract(10000.0 * sin((gl_FragCoord.x * 104729.0 + gl_FragCoord.y * 7639.0) * PI));

    vec3 bgColor0 = pow(backgroundColor0.rgb, vec3(GAMMA));
    vec3 bgColor1 = pow(backgroundColor1.rgb, vec3(GAMMA));

    float sunPos = max(0.2, -1.0 * sin(fog_params.w * PI));
    vec3 fog_color = mix(bgColor0, bgColor1, 1.0 - clamp(random * 0.1 + texCoord.y, 0.0, 1.0));
    fog_color *= sunPos;
    fog_color.b = mix(fog_color.b + 0.05, fog_color.b, sunPos);

    // Skip if no geometry - show sky
    if (position.a < 0.01) {
        frag_color = vec4(fog_color, 1.0);
        return;
    }

    // All calculations in view space (camera at origin)
    vec3 light_dir = normalize(light_pos_view.xyz - view_pos);
    vec3 view_dir = normalize(-view_pos);
    vec3 n = normalize(view_normal);

    // Sample SSAO
    float ssao = texture(sampler2D(ssao_tex, ssao_smp), v_uv).r;

    // Ambient (modulated by SSAO)
    vec3 ambient = ambient_color.rgb * albedo.rgb * ssao;

    // Diffuse intensity
    float diffuseIntensity = max(dot(n, light_dir), 0.0);

    // Apply cel shading to diffuse (before specular calculation)
    if (cel_params.x > 0.5) {
        diffuseIntensity = smoothstep(0.1, 0.2, diffuseIntensity);
    }

    // Specular (Blinn-Phong)
    vec3 halfway = normalize(light_dir + view_dir);
    float specularIntensity = pow(max(dot(n, halfway), 0.0), 32.0);

    // Apply cel shading to specular
    if (cel_params.x > 0.5) {
        specularIntensity = smoothstep(0.9, 1.0, specularIntensity);
    }

    // Fresnel factor - modulates material specular color
    // Original: mix(materialSpecularColor, white, fresnelFactor)
    vec3 materialSpecularColor = vec3(0.3);
    if (fresnel_params.x > 0.5) {
        float fresnelFactor = 1.0 - max(dot(halfway, view_dir), 0.0);
        fresnelFactor = pow(fresnelFactor, fresnel_params.y);
        materialSpecularColor = mix(materialSpecularColor, vec3(1.0), clamp(fresnelFactor, 0.0, 1.0));
    }

    // Rim lighting - illuminates silhouette edges
    vec3 rimLight = vec3(0.0);
    if (rim_params.x > 0.5) {
        float rimIntensity = 1.0 - max(dot(view_dir, n), 0.0);
        if (cel_params.x > 0.5) {
            rimIntensity = smoothstep(0.3, 0.4, rimIntensity);
        } else {
            rimIntensity = pow(rimIntensity, 2.0) * 1.2;
        }
        rimLight = rimIntensity * diffuseIntensity * light_color.rgb * albedo.rgb;
    }

    vec3 diffuse = light_color.rgb * diffuseIntensity * albedo.rgb;
    vec3 specular = light_color.rgb * specularIntensity * materialSpecularColor;

    vec3 result = ambient + diffuse + specular + rimLight;

    // Apply fog (distance from camera in view space, using z-depth)
    if (fog_params.z > 0.5) {
        float dist = abs(view_pos.z);  // Use z-depth for fog
        float fog_intensity = clamp((dist - fog_params.x) / (fog_params.y - fog_params.x), 0.0, 0.97);
        result = mix(result, fog_color, fog_intensity);
    }

    frag_color = vec4(result, 1.0);
}
@end

@program light light_vs light_fs
]]

-- Post-processing Shader (Blur + Bloom)
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
layout(binding=1) uniform texture2D reflection_tex;
layout(binding=1) uniform sampler reflection_smp;
layout(binding=2) uniform texture2D refraction_tex;
layout(binding=2) uniform sampler refraction_smp;

layout(binding=0) uniform fs_params {
    vec4 blur_params;      // x = size, y = separation, z = enabled
    vec4 bloom_params;     // x = size, y = separation, z = threshold, w = amount
    vec4 bloom_enabled;    // x = enabled
    vec4 chromatic_params; // x = enabled, y = red offset, z = green offset, w = blue offset
};

void main() {
    vec2 tex_size = vec2(textureSize(sampler2D(color_tex, color_smp), 0));
    vec2 texCoord = v_uv;

    // Chromatic aberration - sample RGB with different offsets
    vec4 original;
    if (chromatic_params.x > 0.5) {
        vec2 direction = texCoord - vec2(0.5);  // Radiate from center
        float redOffset = chromatic_params.y;
        float greenOffset = chromatic_params.z;
        float blueOffset = chromatic_params.w;

        original.r = texture(sampler2D(color_tex, color_smp), texCoord + direction * redOffset).r;
        original.g = texture(sampler2D(color_tex, color_smp), texCoord + direction * greenOffset).g;
        original.b = texture(sampler2D(color_tex, color_smp), texCoord + direction * blueOffset).b;
        original.a = texture(sampler2D(color_tex, color_smp), texCoord).a;
    } else {
        original = texture(sampler2D(color_tex, color_smp), texCoord);
    }

    // Blur pass
    vec4 blurred = original;
    int blur_size = int(blur_params.x);
    float blur_separation = blur_params.y;

    if (blur_params.z > 0.5 && blur_size > 0) {
        blur_separation = max(blur_separation, 1.0);
        blurred = vec4(0.0);
        float count = 0.0;

        for (int i = -blur_size; i <= blur_size; ++i) {
            for (int j = -blur_size; j <= blur_size; ++j) {
                vec2 offset = vec2(float(i), float(j)) * blur_separation / tex_size;
                blurred += texture(sampler2D(color_tex, color_smp), texCoord + offset);
                count += 1.0;
            }
        }
        blurred /= count;
    }

    // Bloom pass
    vec4 bloom = vec4(0.0);
    if (bloom_enabled.x > 0.5) {
        int bloom_size = int(bloom_params.x);
        float bloom_separation = max(bloom_params.y, 1.0);
        float threshold = bloom_params.z;
        float amount = bloom_params.w;

        float count = 0.0;
        for (int i = -bloom_size; i <= bloom_size; ++i) {
            for (int j = -bloom_size; j <= bloom_size; ++j) {
                vec2 offset = vec2(float(i), float(j)) * bloom_separation / tex_size;
                vec4 sample_color = texture(sampler2D(color_tex, color_smp), texCoord + offset);

                // Check if bright enough
                float brightness = max(sample_color.r, max(sample_color.g, sample_color.b));
                if (brightness >= threshold) {
                    bloom += sample_color;
                }
                count += 1.0;
            }
        }
        bloom = (bloom / count) * amount;
    }

    vec4 result = blurred + bloom;

    // Blend reflection (SSR)
    vec4 reflection = texture(sampler2D(reflection_tex, reflection_smp), texCoord);
    result.rgb = mix(result.rgb, reflection.rgb, clamp(reflection.a, 0.0, 1.0));

    // Blend refraction (water surfaces)
    // Refraction replaces the background where water is present
    vec4 refraction = texture(sampler2D(refraction_tex, refraction_smp), texCoord);
    result.rgb = mix(result.rgb, refraction.rgb, clamp(refraction.a, 0.0, 1.0));

    frag_color = result;
}
@end

@program blur blur_vs blur_fs
]]

-- Debug Buffer Display Shader
local debug_shader_source = [[
@vs debug_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs debug_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D debug_tex;
layout(binding=0) uniform sampler debug_smp;

layout(binding=0) uniform fs_params {
    vec4 params;  // x = mode (0=color, 1=position, 2=normal, 3=uv)
};

void main() {
    vec4 value = texture(sampler2D(debug_tex, debug_smp), v_uv);
    int mode = int(params.x);

    if (mode == 1) {
        // Position: normalize to visible range
        frag_color = vec4(value.xyz * 0.1 + 0.5, 1.0);
    } else if (mode == 2) {
        // Normal: already in 0-1 range (packed) or convert from -1,1
        frag_color = vec4(value.xyz, 1.0);
    } else if (mode == 3) {
        // UV: show xy as RG, visibility as B
        frag_color = vec4(value.xy, value.b, 1.0);
    } else {
        // Default: show as-is
        frag_color = vec4(value.rgb, 1.0);
    }
}
@end

@program debug debug_vs debug_fs
]]

-- SSAO Shader
local ssao_shader_source = [[
@vs ssao_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs ssao_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D position_tex;
layout(binding=0) uniform sampler position_smp;
layout(binding=1) uniform texture2D normal_tex;
layout(binding=1) uniform sampler normal_smp;

layout(binding=0) uniform fs_params {
    mat4 lensProjection;
    vec4 params;  // x = radius, y = bias, z = magnitude, w = enabled
};

// Pre-generated hemisphere samples (similar to original)
const int NUM_SAMPLES = 8;
const vec3 samples[NUM_SAMPLES] = vec3[](
    vec3( 0.039,  0.071, 0.022),
    vec3(-0.066, -0.010, 0.038),
    vec3( 0.075, -0.032, 0.043),
    vec3(-0.038,  0.085, 0.065),
    vec3( 0.095,  0.052, 0.079),
    vec3(-0.072, -0.088, 0.091),
    vec3( 0.112, -0.067, 0.103),
    vec3(-0.098,  0.121, 0.117)
);

// Noise patterns (2x2)
const int NUM_NOISE = 4;
const vec3 noise[NUM_NOISE] = vec3[](
    vec3( 0.707,  0.707, 0.0),
    vec3(-0.707,  0.707, 0.0),
    vec3( 0.707, -0.707, 0.0),
    vec3(-0.707, -0.707, 0.0)
);

void main() {
    float radius    = params.x;
    float bias      = params.y;
    float magnitude = params.z;
    float contrast  = 1.1;

    frag_color = vec4(1.0);

    if (params.w < 0.5) { return; }

    vec2 texSize = vec2(textureSize(sampler2D(position_tex, position_smp), 0));

    vec4 position = texture(sampler2D(position_tex, position_smp), v_uv);
    if (position.a <= 0.0) { return; }

    vec3 normal = normalize(texture(sampler2D(normal_tex, normal_smp), v_uv).xyz * 2.0 - 1.0);

    // Get noise based on screen position
    int noiseX = int(gl_FragCoord.x - 0.5) % 2;
    int noiseY = int(gl_FragCoord.y - 0.5) % 2;
    vec3 random = noise[noiseX + noiseY * 2];

    // Build TBN matrix
    vec3 tangent  = normalize(random - normal * dot(random, normal));
    vec3 binormal = cross(normal, tangent);
    mat3 tbn      = mat3(tangent, binormal, normal);

    float occlusion = float(NUM_SAMPLES);

    for (int i = 0; i < NUM_SAMPLES; ++i) {
        vec3 samplePosition = tbn * samples[i];
        samplePosition = position.xyz + samplePosition * radius;

        vec4 offsetUV      = vec4(samplePosition, 1.0);
        offsetUV           = lensProjection * offsetUV;
        offsetUV.xyz      /= offsetUV.w;
        offsetUV.xy        = offsetUV.xy * 0.5 + 0.5;
        offsetUV.y         = 1.0 - offsetUV.y;  // Flip Y to match v_uv

        vec4 offsetPosition = texture(sampler2D(position_tex, position_smp), offsetUV.xy);

        // Compare depths (z-axis in our view space)
        float occluded = 0.0;
        if (samplePosition.z + bias <= offsetPosition.z) {
            occluded = 0.0;
        } else {
            occluded = 1.0;
        }

        float intensity = smoothstep(0.0, 1.0, radius / abs(position.z - offsetPosition.z));
        occluded  *= intensity;
        occlusion -= occluded;
    }

    occlusion /= float(NUM_SAMPLES);
    occlusion  = pow(occlusion, magnitude);
    occlusion  = contrast * (occlusion - 0.5) + 0.5;

    frag_color = vec4(vec3(occlusion), position.a);
}
@end

@program ssao ssao_vs ssao_fs
]]

-- Motion Blur Shader
local motion_blur_shader_source = [[
@vs motion_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs motion_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D position_tex;
layout(binding=0) uniform sampler position_smp;
layout(binding=1) uniform texture2D color_tex;
layout(binding=1) uniform sampler color_smp;

layout(binding=0) uniform fs_params {
    mat4 previousViewWorldMat;  // Previous frame view-to-world (inverse of prev view)
    mat4 worldViewMat;          // Current frame world-to-view (current view)
    mat4 lensProjection;        // Projection matrix
    vec4 params;                // x = size, y = separation, z = enabled
};

void main() {
    int size = int(params.x);
    float separation = params.y;

    frag_color = texture(sampler2D(color_tex, color_smp), v_uv);
    vec4 position1 = texture(sampler2D(position_tex, position_smp), v_uv);

    if (size <= 0 || separation <= 0.0 || params.z < 0.5 || position1.a <= 0.0) {
        return;
    }

    // Transform current view-space position through prev inverse and current view
    // This gives where this point would appear if camera hadn't moved
    vec4 position0 = worldViewMat * previousViewWorldMat * position1;

    // Project to screen space
    position0 = lensProjection * position0;
    position0.xyz /= position0.w;
    position0.xy = position0.xy * 0.5 + 0.5;

    position1 = lensProjection * position1;
    position1.xyz /= position1.w;
    position1.xy = position1.xy * 0.5 + 0.5;

    vec2 direction = position1.xy - position0.xy;

    if (length(direction) <= 0.0) {
        return;
    }

    direction.xy *= separation;

    vec2 forward = v_uv;
    vec2 backward = v_uv;
    float count = 1.0;

    // Fixed loop count for HLSL compatibility
    const int MAX_SAMPLES = 16;
    for (int i = 0; i < MAX_SAMPLES; ++i) {
        if (i >= size) break;

        forward += direction;
        backward -= direction;

        frag_color += texture(sampler2D(color_tex, color_smp), forward);
        frag_color += texture(sampler2D(color_tex, color_smp), backward);

        count += 2.0;
    }

    frag_color /= count;
}
@end

@program motion motion_vs motion_fs
]]

-- SSR UV Shader: Ray marching to find reflection UV
-- Based on lettier/3d-game-shaders-for-beginners screen-space-reflection.frag
-- Key differences from original:
--   1. Loop iterations limited to 64 (original uses dynamic delta which can be 256+)
--      - HLSL has strict loop unrolling requirements, large dynamic loops cause compilation timeout
--   2. No mask texture (original uses specular map to determine reflectivity)
--      - Current model lacks specular map, so all surfaces are reflective
--   3. Y-flip handling for render target coordinate system
--      - Our G-buffer uses flipped UVs, so we flip when sampling and outputting
local ssr_uv_shader_source = [[
@vs ssr_uv_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs ssr_uv_fs
in vec2 v_uv;

out vec4 frag_color;

// Water surface G-buffer (reflective surface) - ray starts here
layout(binding=0) uniform texture2D position_from_tex;
layout(binding=0) uniform sampler position_from_smp;
layout(binding=1) uniform texture2D normal_from_tex;
layout(binding=1) uniform sampler normal_from_smp;
// Reflection mask - controls amount/roughness of reflections
layout(binding=2) uniform texture2D mask_tex;
layout(binding=2) uniform sampler mask_smp;
// Opaque scene G-buffer - ray searches for hits here
layout(binding=3) uniform texture2D position_to_tex;
layout(binding=3) uniform sampler position_to_smp;

layout(binding=0) uniform fs_params {
    mat4 lensProjection;
    vec4 params;      // x = enabled, y = maxDistance, z = resolution, w = thickness
    vec4 params2;     // x = steps
};

void main() {
    float maxDistance = params.y;
    float resolution  = params.z;
    float thickness   = params.w;
    int   steps       = int(params2.x);

    vec2 texSize  = vec2(textureSize(sampler2D(position_from_tex, position_from_smp), 0));
    vec2 texCoord = v_uv;

    vec4 uv = vec4(0.0);

    vec4 positionFrom = texture(sampler2D(position_from_tex, position_from_smp), texCoord);
    vec4 mask         = texture(sampler2D(mask_tex, mask_smp), texCoord);

    // Skip if disabled or no water at this pixel
    float maskAmount = clamp(mask.r, 0.0, 1.0);
    if (positionFrom.w <= 0.0 || params.x < 0.5 || maskAmount <= 0.0) {
        frag_color = uv;
        return;
    }

    // Calculate reflection direction
    vec3 unitPositionFrom = normalize(positionFrom.xyz);
    vec3 normalFrom       = normalize(texture(sampler2D(normal_from_tex, normal_from_smp), texCoord).xyz * 2.0 - 1.0);
    vec3 pivot            = normalize(reflect(unitPositionFrom, normalFrom));

    vec4 positionTo = positionFrom;

    // Define ray in view space
    vec4 startView = vec4(positionFrom.xyz + (pivot *         0.0), 1.0);
    vec4 endView   = vec4(positionFrom.xyz + (pivot * maxDistance), 1.0);

    // Project to screen space
    vec4 startFrag      = startView;
         startFrag      = lensProjection * startFrag;
         startFrag.xyz /= startFrag.w;
         startFrag.xy   = startFrag.xy * 0.5 + 0.5;
         startFrag.y    = 1.0 - startFrag.y;          // Flip Y for render target coords
         startFrag.xy  *= texSize;

    vec4 endFrag      = endView;
         endFrag      = lensProjection * endFrag;
         endFrag.xyz /= endFrag.w;
         endFrag.xy   = endFrag.xy * 0.5 + 0.5;
         endFrag.y    = 1.0 - endFrag.y;
         endFrag.xy  *= texSize;

    vec2 frag  = startFrag.xy;
         uv.xy = frag / texSize;

    float deltaX    = endFrag.x - startFrag.x;
    float deltaY    = endFrag.y - startFrag.y;
    float useX      = abs(deltaX) >= abs(deltaY) ? 1.0 : 0.0;
    float delta     = mix(abs(deltaY), abs(deltaX), useX) * clamp(resolution, 0.0, 1.0);
    vec2  increment = vec2(deltaX, deltaY) / max(delta, 0.001);

    float search0 = 0.0;
    float search1 = 0.0;

    int hit0 = 0;
    int hit1 = 0;

    // GLM uses -Z for depth (negative Z is forward)
    float viewDistance = startView.z;
    float depth        = thickness;

    // Coarse search through OPAQUE scene G-buffer
    for (int i = 0; i < 64; ++i) {
        if (float(i) >= delta) break;

        frag      += increment;
        uv.xy      = frag / texSize;

        positionTo = texture(sampler2D(position_to_tex, position_to_smp), uv.xy);

        search1 = mix(
            (frag.y - startFrag.y) / deltaY,
            (frag.x - startFrag.x) / deltaX,
            useX
        );
        search1 = clamp(search1, 0.0, 1.0);

        viewDistance = (startView.z * endView.z) / mix(endView.z, startView.z, search1);
        depth        = positionTo.z - viewDistance;

        if (depth > 0.0 && depth < thickness) {
            hit0 = 1;
            break;
        } else {
            search0 = search1;
        }
    }

    search1 = search0 + ((search1 - search0) / 2.0);

    // Binary search refinement
    for (int i = 0; i < 8; ++i) {
        if (hit0 == 0) break;
        if (i >= steps) break;

        frag       = mix(startFrag.xy, endFrag.xy, search1);
        uv.xy      = frag / texSize;

        positionTo = texture(sampler2D(position_to_tex, position_to_smp), uv.xy);

        viewDistance = (startView.z * endView.z) / mix(endView.z, startView.z, search1);
        depth        = positionTo.z - viewDistance;

        if (depth > 0.0 && depth < thickness) {
            hit1 = 1;
            search1 = search0 + ((search1 - search0) / 2.0);
        } else {
            float temp = search1;
            search1 = search1 + ((search1 - search0) / 2.0);
            search0 = temp;
        }
    }

    // Calculate visibility
    float visibility =
        float(hit1)
      * positionTo.w
      * (1.0 - max(dot(-unitPositionFrom, pivot), 0.0))
      * (1.0 - clamp(depth / thickness, 0.0, 1.0))
      * (1.0 - clamp(length(positionTo - positionFrom) / maxDistance, 0.0, 1.0))
      * (uv.x < 0.0 || uv.x > 1.0 ? 0.0 : 1.0)
      * (uv.y < 0.0 || uv.y > 1.0 ? 0.0 : 1.0);

    visibility = clamp(visibility, 0.0, 1.0);

    uv.ba = vec2(visibility);

    frag_color = uv;
}
@end

@program ssr_uv ssr_uv_vs ssr_uv_fs
]]

-- Reflection Color Shader: Sample color at SSR UVs with hole filling
-- Based on lettier/3d-game-shaders-for-beginners reflection-color.frag
-- Two-pass approach:
--   1. SSR UV pass outputs UV coordinates where reflection should sample from
--   2. This pass samples the lit scene at those UVs to get actual reflection color
-- Hole filling: Ray marching can miss pixels, leaving holes in the UV map.
-- We blur-sample neighboring pixels to fill these holes for smoother reflections.
local reflection_shader_source = [[
@vs reflection_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs reflection_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D uv_tex;
layout(binding=0) uniform sampler uv_smp;
layout(binding=1) uniform texture2D color_tex;
layout(binding=1) uniform sampler color_smp;
layout(binding=2) uniform texture2D mask_tex;
layout(binding=2) uniform sampler mask_smp;

void main() {
    int   size       = 6;
    float separation = 2.0;

    vec2 texSize  = vec2(textureSize(sampler2D(uv_tex, uv_smp), 0));
    vec2 texCoord = v_uv;

    vec4 uv = texture(sampler2D(uv_tex, uv_smp), texCoord);
    vec4 mask = texture(sampler2D(mask_tex, mask_smp), texCoord);
    float amount = clamp(mask.r, 0.0, 1.0);
    float roughness = clamp(mask.g, 0.0, 1.0);

    // Removes holes in the UV map (blur-based hole fill)
    if (uv.b <= 0.0) {
        uv = vec4(0.0);
        float count = 0.0;

        for (int i = -size; i <= size; ++i) {
            for (int j = -size; j <= size; ++j) {
                vec2 offset = vec2(float(i), float(j)) * separation / texSize;
                uv += texture(sampler2D(uv_tex, uv_smp), texCoord + offset);
                count += 1.0;
            }
        }

        uv.xyz /= count;
    }

    if (uv.b <= 0.0 || amount <= 0.0) {
        frag_color = vec4(0.0);
        return;
    }

    vec4  color = texture(sampler2D(color_tex, color_smp), uv.xy);
    vec4  blurredColor = color;

    // Roughness-driven blur (approximate the separate blur pass from the original)
    if (roughness > 0.01) {
        int   size       = int(mix(1.0, 4.0, roughness));
        float separation = mix(1.0, 3.0, roughness);
        float count      = 0.0;
        blurredColor     = vec4(0.0);

        for (int i = -size; i <= size; ++i) {
            for (int j = -size; j <= size; ++j) {
                vec2 offset = vec2(float(i), float(j)) * separation / texSize;
                blurredColor += texture(sampler2D(color_tex, color_smp), uv.xy + offset);
                count += 1.0;
            }
        }
        blurredColor /= count;
    }

    float alpha = clamp(uv.b, 0.0, 1.0) * amount;
    vec3 combined = mix(color.rgb, blurredColor.rgb, roughness);
    frag_color = vec4(combined, alpha);
}
@end

@program reflection reflection_vs reflection_fs
]]

-- Refraction UV Shader: Ray marching with refract() instead of reflect()
-- Based on lettier/3d-game-shaders-for-beginners screen-space-refraction.frag
-- Key differences from SSR:
--   1. Uses refract() with index of refraction (IOR) instead of reflect()
--   2. Requires two G-buffers: water surface (positionFrom) and background (positionTo)
--   3. Outputs UV that blends with original when no hit (vs SSR which outputs 0 alpha)
local refraction_uv_shader_source = [[
@vs refraction_uv_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs refraction_uv_fs
in vec2 v_uv;

out vec4 frag_color;

// Water surface G-buffer (refractive surface)
layout(binding=0) uniform texture2D position_from_tex;
layout(binding=0) uniform sampler position_from_smp;
layout(binding=1) uniform texture2D normal_from_tex;
layout(binding=1) uniform sampler normal_from_smp;
// Background G-buffer (what's behind water)
layout(binding=2) uniform texture2D position_to_tex;
layout(binding=2) uniform sampler position_to_smp;

layout(binding=0) uniform fs_params {
    mat4 lensProjection;
    vec4 params;      // x = enabled, y = maxDistance, z = resolution, w = thickness
    vec4 params2;     // x = steps, y = ior (index of refraction)
};

void main() {
    float maxDistance = params.y;
    float resolution  = params.z;
    float thickness   = params.w;
    int   steps       = int(params2.x);
    float ior         = params2.y;  // e.g., 1.0/1.33 for water

    vec2 texSize  = vec2(textureSize(sampler2D(position_from_tex, position_from_smp), 0));
    vec2 texCoord = v_uv;

    // Default: pass through original UV (no refraction)
    vec4 uv = vec4(texCoord.xy, 1.0, 1.0);

    vec4 positionFrom = texture(sampler2D(position_from_tex, position_from_smp), texCoord);

    // Skip if disabled or no water surface at this pixel
    if (positionFrom.w <= 0.0 || params.x < 0.5) {
        frag_color = uv;
        return;
    }

    // Calculate refraction direction
    vec3 unitPositionFrom = normalize(positionFrom.xyz);
    vec3 normalFrom       = normalize(texture(sampler2D(normal_from_tex, normal_from_smp), texCoord).xyz * 2.0 - 1.0);
    vec3 pivot            = normalize(refract(unitPositionFrom, normalFrom, ior));

    // If total internal reflection, no refraction
    if (length(pivot) < 0.01) {
        frag_color = uv;
        return;
    }

    vec4 positionTo = positionFrom;

    // Define ray in view space
    vec4 startView = vec4(positionFrom.xyz + (pivot *         0.0), 1.0);
    vec4 endView   = vec4(positionFrom.xyz + (pivot * maxDistance), 1.0);

    // Project to screen space
    vec4 startFrag      = startView;
         startFrag      = lensProjection * startFrag;
         startFrag.xyz /= startFrag.w;
         startFrag.xy   = startFrag.xy * 0.5 + 0.5;
         startFrag.y    = 1.0 - startFrag.y;          // Flip Y for render target coords
         startFrag.xy  *= texSize;

    vec4 endFrag      = endView;
         endFrag      = lensProjection * endFrag;
         endFrag.xyz /= endFrag.w;
         endFrag.xy   = endFrag.xy * 0.5 + 0.5;
         endFrag.y    = 1.0 - endFrag.y;
         endFrag.xy  *= texSize;

    vec2 frag  = startFrag.xy;
         uv.xy = frag / texSize;

    float deltaX    = endFrag.x - startFrag.x;
    float deltaY    = endFrag.y - startFrag.y;
    float useX      = abs(deltaX) >= abs(deltaY) ? 1.0 : 0.0;
    float delta     = mix(abs(deltaY), abs(deltaX), useX) * clamp(resolution, 0.0, 1.0);
    vec2  increment = vec2(deltaX, deltaY) / max(delta, 0.001);

    float search0 = 0.0;
    float search1 = 0.0;

    int hit0 = 0;
    int hit1 = 0;

    // Note: Original Panda3D uses Y as depth, but GLM uses Z (negative Z is forward)
    float viewDistance = startView.z;
    float depth        = thickness;

    // Coarse search (fixed iterations for HLSL loop unrolling)
    for (int i = 0; i < 64; ++i) {
        if (float(i) >= delta) break;

        frag      += increment;
        uv.xy      = frag / texSize;

        positionTo = texture(sampler2D(position_to_tex, position_to_smp), uv.xy);

        search1 = mix(
            (frag.y - startFrag.y) / deltaY,
            (frag.x - startFrag.x) / deltaX,
            useX
        );
        search1 = clamp(search1, 0.0, 1.0);

        viewDistance = (startView.z * endView.z) / mix(endView.z, startView.z, search1);
        // GLM: negative Z is forward, so swap subtraction order for correct sign
        depth        = positionTo.z - viewDistance;

        if (depth > 0.0 && depth < thickness) {
            hit0 = 1;
            break;
        } else {
            search0 = search1;
        }
    }

    search1 = search0 + ((search1 - search0) / 2.0);

    // Binary search refinement
    for (int i = 0; i < 8; ++i) {
        if (hit0 == 0) break;
        if (i >= steps) break;

        frag       = mix(startFrag.xy, endFrag.xy, search1);
        uv.xy      = frag / texSize;

        positionTo = texture(sampler2D(position_to_tex, position_to_smp), uv.xy);

        viewDistance = (startView.z * endView.z) / mix(endView.z, startView.z, search1);
        depth        = positionTo.z - viewDistance;

        if (depth > 0.0 && depth < thickness) {
            hit1 = 1;
            search1 = search0 + ((search1 - search0) / 2.0);
        } else {
            float temp = search1;
            search1 = search1 + ((search1 - search0) / 2.0);
            search0 = temp;
        }
    }

    // Calculate visibility
    float visibility =
        float(hit1)
      * positionTo.w
      * (1.0 - max(dot(-unitPositionFrom, pivot), 0.0))
      * (uv.x < 0.0 || uv.x > 1.0 ? 0.0 : 1.0)
      * (uv.y < 0.0 || uv.y > 1.0 ? 0.0 : 1.0);

    visibility = clamp(visibility, 0.0, 1.0);

    // Blend refracted UV with original based on visibility
    // UVs are already in render target coordinate system (projection was Y-flipped)
    vec2 finalUV = mix(texCoord, uv.xy, visibility);
    frag_color = vec4(finalUV, visibility, 1.0);
}
@end

@program refraction_uv refraction_uv_vs refraction_uv_fs
]]

-- Refraction Color Shader: Sample background at refracted UVs
-- Simpler than reflection - just sample at the UV, no hole filling needed
-- Also applies water tint based on depth
local refraction_shader_source = [[
@vs refraction_vs
in vec2 pos;
in vec2 uv;

out vec2 v_uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    v_uv = vec2(uv.x, 1.0 - uv.y);
}
@end

@fs refraction_fs
in vec2 v_uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D uv_tex;
layout(binding=0) uniform sampler uv_smp;
layout(binding=1) uniform texture2D color_tex;
layout(binding=1) uniform sampler color_smp;
layout(binding=2) uniform texture2D water_position_tex;
layout(binding=2) uniform sampler water_position_smp;
layout(binding=3) uniform texture2D opaque_position_tex;
layout(binding=3) uniform sampler opaque_position_smp;
layout(binding=4) uniform texture2D mask_tex;
layout(binding=4) uniform sampler mask_smp;

layout(binding=0) uniform fs_params {
    vec4 tint_color;   // rgb = tint, a = intensity
    vec4 params;       // x = depthMax, y = debug mode
};

void main() {
    vec2 texCoord = v_uv;
    float depthMax = params.x;
    bool debugMode = params.y > 0.5;

    // Always start with background color so non-water pixels still carry color (important for reflection sampling).
    vec4 backgroundColor = texture(sampler2D(color_tex, color_smp), texCoord);

    // Check if this pixel has water
    vec4 waterPos = texture(sampler2D(water_position_tex, water_position_smp), texCoord);
    if (waterPos.w <= 0.0) {
        frag_color = vec4(backgroundColor.rgb, 0.0);  // No water, keep color but no alpha
        return;
    }

    vec4 mask = texture(sampler2D(mask_tex, mask_smp), texCoord);
    float amount = clamp(mask.r, 0.0, 1.0);
    if (amount <= 0.0) {
        frag_color = vec4(backgroundColor.rgb, 0.0);
        return;
    }

    // Get refracted UV and visibility
    vec4 uvData = texture(sampler2D(uv_tex, uv_smp), texCoord);
    float visibility = uvData.b;  // SSR UV pass stores visibility in b channel

    // If no valid refraction, fall back to background
    if (visibility <= 0.0) {
        frag_color = vec4(backgroundColor.rgb, 0.0);
        return;
    }

    // Sample background color at refracted position
    vec4 opaquePos = texture(sampler2D(opaque_position_tex, opaque_position_smp), uvData.xy);
    backgroundColor = texture(sampler2D(color_tex, color_smp), uvData.xy);

    // Calculate 3D depth (distance between water surface and refracted point)
    float depth = length(opaquePos.xyz - waterPos.xyz);
    float mixture = clamp(depth / depthMax, 0.0, 1.0);

    // Two-stage tinting (original algorithm)
    vec3 shallowColor = backgroundColor.rgb;
    vec3 deepColor = mix(shallowColor, tint_color.rgb, tint_color.a);
    vec3 foregroundColor = mix(shallowColor, deepColor, mixture);

    // Debug: show visibility
    if (debugMode) {
        frag_color = vec4(visibility, visibility, visibility, 1.0);
        return;
    }

    // Mix with visibility
    float alpha = visibility * amount;
    frag_color = vec4(foregroundColor, alpha);
}
@end

@program refraction refraction_vs refraction_fs
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

    -- Water G-Buffer (for refractive surfaces - rendered in second pass)
    water_position_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA16F,
    }))
    water_position_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = water_position_img },
    }))
    water_position_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = water_position_img },
    }))

    water_normal_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    water_normal_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = water_normal_img },
    }))
    water_normal_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = water_normal_img },
    }))

    water_albedo_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    water_albedo_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = water_albedo_img },
    }))
    water_albedo_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = water_albedo_img },
    }))

    -- Reflection mask (from water's slot 3 texture)
    water_reflection_mask_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    water_reflection_mask_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = water_reflection_mask_img },
    }))
    water_reflection_mask_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = water_reflection_mask_img },
    }))

    -- Refraction mask (from water's slot 4 texture)
    water_refraction_mask_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    water_refraction_mask_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = water_refraction_mask_img },
    }))
    water_refraction_mask_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = water_refraction_mask_img },
    }))

    water_depth_img = gfx.make_image(gfx.ImageDesc({
        usage = { depth_stencil_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.DEPTH,
    }))
    water_depth_attach = gfx.make_view(gfx.ViewDesc({
        depth_stencil_attachment = { image = water_depth_img },
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

    -- SSAO render target
    ssao_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.R8,  -- single channel occlusion
    }))
    ssao_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = ssao_img },
    }))
    ssao_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = ssao_img },
    }))

    -- Motion blur render target
    motion_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    motion_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = motion_img },
    }))
    motion_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = motion_img },
    }))

    -- SSR UV render target (RGBA16F for UV coords + visibility)
    ssr_uv_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA16F,
    }))
    ssr_uv_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = ssr_uv_img },
    }))
    ssr_uv_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = ssr_uv_img },
    }))

    -- Reflection color render target
    reflection_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    reflection_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = reflection_img },
    }))
    reflection_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = reflection_img },
    }))

    -- Refraction UV render target
    refraction_uv_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA16F,
    }))
    refraction_uv_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = refraction_uv_img },
    }))
    refraction_uv_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = refraction_uv_img },
    }))

    -- Refraction color render target
    refraction_img = gfx.make_image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
    }))
    refraction_attach = gfx.make_view(gfx.ViewDesc({
        color_attachment = { image = refraction_img },
    }))
    refraction_tex = gfx.make_view(gfx.ViewDesc({
        texture = { image = refraction_img },
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
                size = 192,  -- 3 mat4
                glsl_uniforms = {
                    { glsl_name = "mvp", type = gfx.UniformType.MAT4 },
                    { glsl_name = "model", type = gfx.UniformType.MAT4 },
                    { glsl_name = "view", type = gfx.UniformType.MAT4 },
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

    -- Water geometry shader (5 outputs: position, normal, albedo, reflection mask, refraction mask)
    local water_geom_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 192,  -- 3 mat4 = 192 bytes
                hlsl_register_b_n = 0,
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 2 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 3 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 2 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 3 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "diffuse_tex_diffuse_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "reflection_mask_tex_reflection_mask_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 3, sampler_slot = 3, glsl_name = "refraction_mask_tex_refraction_mask_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 2 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 3 },
        },
    }
    water_geom_shader = util.compile_shader_full(water_geom_shader_source, "water_geom", water_geom_desc)
    if not water_geom_shader then
        util.error("Failed to compile water geometry shader")
        return
    end

    -- Water geometry pipeline (no culling, 5 color outputs for masks)
    water_geom_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = water_geom_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 },  -- pos
                { format = gfx.VertexFormat.FLOAT3 },  -- normal
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
                { format = gfx.VertexFormat.FLOAT3 },  -- tangent
            },
        },
        index_type = gfx.IndexType.UINT32,
        cull_mode = gfx.CullMode.NONE,  -- No culling for water
        depth = {
            write_enabled = true,
            compare = gfx.CompareFunc.LESS_EQUAL,
            pixel_format = gfx.PixelFormat.DEPTH,
        },
        color_count = 5,
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA16F },  -- position
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- normal
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- albedo
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- reflection mask
            { pixel_format = gfx.PixelFormat.RGBA8 },    -- refraction mask
        },
    }))

    -- Lighting pass shader
    local light_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 144,  -- 9 vec4
                glsl_uniforms = {
                    { glsl_name = "light_pos_view", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "light_color", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "ambient_color", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "backgroundColor0", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "backgroundColor1", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "fog_params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "fresnel_params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "rim_params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "cel_params", type = gfx.UniformType.FLOAT4 },
                },
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 2 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 3 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 2 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 3 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "albedo_tex_albedo_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 3, sampler_slot = 3, glsl_name = "ssao_tex_ssao_smp" },
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

    -- Blur shader (includes bloom + chromatic aberration + SSR blend + refraction blend)
    local blur_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 64,  -- 4 vec4
                glsl_uniforms = {
                    { glsl_name = "blur_params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "bloom_params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "bloom_enabled", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "chromatic_params", type = gfx.UniformType.FLOAT4 },
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "color_tex_color_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "reflection_tex_reflection_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "refraction_tex_refraction_smp" },
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

    -- SSAO shader
    local ssao_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 80,  -- 1 mat4 (64) + 1 vec4 (16)
                glsl_uniforms = {
                    { glsl_name = "lensProjection", type = gfx.UniformType.MAT4 },
                    { glsl_name = "params", type = gfx.UniformType.FLOAT4 },
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    ssao_shader = util.compile_shader_full(ssao_shader_source, "ssao", ssao_desc)
    if not ssao_shader then
        util.error("Failed to compile SSAO shader")
        return
    end

    -- SSAO pipeline
    ssao_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = ssao_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- pos
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
            },
        },
        colors = {
            { pixel_format = gfx.PixelFormat.R8 },
        },
        depth = {
            pixel_format = gfx.PixelFormat.NONE,
        },
    }))

    -- Motion blur shader
    local motion_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 208,  -- 3 mat4 (192) + 1 vec4 (16)
                glsl_uniforms = {
                    { glsl_name = "previousViewWorldMat", type = gfx.UniformType.MAT4 },
                    { glsl_name = "worldViewMat", type = gfx.UniformType.MAT4 },
                    { glsl_name = "lensProjection", type = gfx.UniformType.MAT4 },
                    { glsl_name = "params", type = gfx.UniformType.FLOAT4 },
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "color_tex_color_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    motion_shader = util.compile_shader_full(motion_blur_shader_source, "motion", motion_desc)
    if not motion_shader then
        util.error("Failed to compile motion blur shader")
        return
    end

    -- Motion blur pipeline
    motion_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = motion_shader,
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

    -- SSR UV shader
    local ssr_uv_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 96,  -- 1 mat4 (64) + 2 vec4 (32)
                glsl_uniforms = {
                    { glsl_name = "lensProjection", type = gfx.UniformType.MAT4 },
                    { glsl_name = "params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "params2", type = gfx.UniformType.FLOAT4 },
                },
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 2 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 3 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 2 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 3 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_tex_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_tex_normal_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "mask_tex_mask_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 3, sampler_slot = 3, glsl_name = "position_to_tex_position_to_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    ssr_uv_shader = util.compile_shader_full(ssr_uv_shader_source, "ssr_uv", ssr_uv_desc)
    if not ssr_uv_shader then
        util.error("Failed to compile SSR UV shader")
        return
    end

    -- SSR UV pipeline
    ssr_uv_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = ssr_uv_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- pos
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
            },
        },
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA16F },
        },
        depth = {
            pixel_format = gfx.PixelFormat.NONE,
        },
    }))

    -- Reflection color shader
    local reflection_desc = {
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "uv_tex_uv_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "color_tex_color_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "mask_tex_mask_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    reflection_shader = util.compile_shader_full(reflection_shader_source, "reflection", reflection_desc)
    if not reflection_shader then
        util.error("Failed to compile reflection shader")
        return
    end

    -- Reflection color pipeline
    reflection_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = reflection_shader,
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

    -- Refraction UV shader
    local refraction_uv_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 96,  -- 1 mat4 (64) + 2 vec4 (32)
                glsl_uniforms = {
                    { glsl_name = "lensProjection", type = gfx.UniformType.MAT4 },
                    { glsl_name = "params", type = gfx.UniformType.FLOAT4 },
                    { glsl_name = "params2", type = gfx.UniformType.FLOAT4 },
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "position_from_tex_position_from_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "normal_from_tex_normal_from_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "position_to_tex_position_to_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    refraction_uv_shader = util.compile_shader_full(refraction_uv_shader_source, "refraction_uv", refraction_uv_desc)
    if not refraction_uv_shader then
        util.error("Failed to compile refraction UV shader")
        return
    end

    -- Refraction UV pipeline
    refraction_uv_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = refraction_uv_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },  -- pos
                { format = gfx.VertexFormat.FLOAT2 },  -- uv
            },
        },
        colors = {
            { pixel_format = gfx.PixelFormat.RGBA16F },
        },
        depth = {
            pixel_format = gfx.PixelFormat.NONE,
        },
    }))

    -- Refraction color shader
    local refraction_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 32,  -- 2 vec4 = 32 bytes
                hlsl_register_b_n = 0,
            },
        },
        views = {
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 0 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 1 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 2 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 3 } },
            { texture = { stage = gfx.ShaderStage.FRAGMENT, image_type = gfx.ImageType["2D"], sample_type = gfx.ImageSampleType.FLOAT, hlsl_register_t_n = 4 } },
        },
        samplers = {
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 0 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 1 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 2 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 3 },
            { stage = gfx.ShaderStage.FRAGMENT, sampler_type = gfx.SamplerType.FILTERING, hlsl_register_s_n = 4 },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "uv_tex_uv_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 1, sampler_slot = 1, glsl_name = "color_tex_color_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 2, sampler_slot = 2, glsl_name = "water_position_tex_water_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 3, sampler_slot = 3, glsl_name = "opaque_position_tex_opaque_position_smp" },
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 4, sampler_slot = 4, glsl_name = "mask_tex_mask_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    refraction_shader = util.compile_shader_full(refraction_shader_source, "refraction", refraction_desc)
    if not refraction_shader then
        util.error("Failed to compile refraction shader")
        return
    end

    -- Refraction color pipeline
    refraction_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = refraction_shader,
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

    -- Debug display shader
    local debug_desc = {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                size = 16,
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
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "debug_tex_debug_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        },
    }
    debug_shader = util.compile_shader_full(debug_shader_source, "debug", debug_desc)
    if not debug_shader then
        util.error("Failed to compile debug shader")
        return
    end

    debug_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = debug_shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },
                { format = gfx.VertexFormat.FLOAT2 },
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

        -- Create default white mask texture (used when mask textures are missing)
        if not default_mask then
            local white = string.pack("BBBB", 255, 255, 255, 255)
            local white_img = gfx.make_image(gfx.ImageDesc({
                width = 1,
                height = 1,
                pixel_format = gfx.PixelFormat.RGBA8,
                data = { mip_levels = { white } },
            }))
            local white_view = gfx.make_view(gfx.ViewDesc({
                texture = { image = white_img },
            }))
            local white_smp = gfx.make_sampler(gfx.SamplerDesc({}))
            default_mask = { view = white_view, smp = white_smp }
        end

        if diffuse_view then
            local mesh_entry = {
                vbuf = vbuf,
                ibuf = ibuf,
                index_count = #indices,
                diffuse_view = diffuse_view,
                diffuse_smp = diffuse_smp,
                normal_view = normal_view,
                normal_smp = normal_smp,
            }

            -- Separate water meshes for refraction (mat_name is the material name)
            if mat_name == "water" then
                -- Load reflection mask (slot 3) and refraction mask (slot 4) for water
                if mesh_data.textures[4] then  -- slot 3 = reflection mask
                    local mask_info = model.textures[mesh_data.textures[4]]
                    if mask_info and mask_info.path then
                        local path = "textures/" .. mask_info.path
                        if not textures_cache[path] then
                            local view, smp = util.load_texture(path)
                            if view then
                                textures_cache[path] = { view = view, smp = smp }
                                util.info("Loaded reflection mask: " .. path)
                            end
                        end
                        if textures_cache[path] then
                            mesh_entry.reflection_mask_view = textures_cache[path].view
                            mesh_entry.reflection_mask_smp = textures_cache[path].smp
                        end
                    end
                end
                if not mesh_entry.reflection_mask_view then
                    mesh_entry.reflection_mask_view = default_mask.view
                    mesh_entry.reflection_mask_smp = default_mask.smp
                end
                if mesh_data.textures[5] then  -- slot 4 = refraction mask
                    local mask_info = model.textures[mesh_data.textures[5]]
                    if mask_info and mask_info.path then
                        local path = "textures/" .. mask_info.path
                        if not textures_cache[path] then
                            local view, smp = util.load_texture(path)
                            if view then
                                textures_cache[path] = { view = view, smp = smp }
                                util.info("Loaded refraction mask: " .. path)
                            end
                        end
                        if textures_cache[path] then
                            mesh_entry.refraction_mask_view = textures_cache[path].view
                            mesh_entry.refraction_mask_smp = textures_cache[path].smp
                        end
                    end
                end
                if not mesh_entry.refraction_mask_view then
                    mesh_entry.refraction_mask_view = default_mask.view
                    mesh_entry.refraction_mask_smp = default_mask.smp
                end
                table.insert(water_meshes, mesh_entry)
                util.info("Added water mesh: " .. mat_name)
            else
                table.insert(meshes, mesh_entry)
            end
        end
    end

    util.info("Loaded " .. #meshes .. " opaque meshes, " .. #water_meshes .. " water meshes")
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

    -- Uniform data: mvp + model + view
    local uniform_data = mvp:pack() .. model_mat:pack() .. view:pack()

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

    -- === WATER GEOMETRY PASS (for refraction) ===
    -- Use opaque depth buffer with LOAD to respect opaque geometry occlusion
    -- Outputs: position, normal, albedo, reflection mask, refraction mask
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0.5, g = 0.5, b = 0.5, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },  -- reflection mask
                { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 0 } },  -- refraction mask
            },
            depth = { load_action = gfx.LoadAction.LOAD },  -- Keep opaque depth
        }),
        attachments = {
            colors = {
                water_position_attach,
                water_normal_attach,
                water_albedo_attach,
                water_reflection_mask_attach,
                water_refraction_mask_attach,
            },
            depth_stencil = gbuf_depth_attach,  -- Share depth with opaque pass
        },
    }))

    gfx.apply_pipeline(water_geom_pipeline)

    for _, mesh in ipairs(water_meshes) do
        -- Use mask textures if available, otherwise use diffuse as fallback (white = full mask)
        local refl_view = mesh.reflection_mask_view or default_mask.view
        local refl_smp = mesh.reflection_mask_smp or default_mask.smp
        local refr_view = mesh.refraction_mask_view or default_mask.view
        local refr_smp = mesh.refraction_mask_smp or default_mask.smp

        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { mesh.vbuf },
            index_buffer = mesh.ibuf,
            views = { mesh.diffuse_view, mesh.normal_view, refl_view, refr_view },
            samplers = { mesh.diffuse_smp, mesh.normal_smp, refl_smp, refr_smp },
        }))
        gfx.apply_uniforms(0, gfx.Range(uniform_data))
        gfx.draw(0, mesh.index_count, 1)
    end

    gfx.end_pass()

    -- === SSAO PASS ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
            }},
        }),
        attachments = {
            colors = { ssao_attach },
        },
    }))

    gfx.apply_pipeline(ssao_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { gbuf_position_tex, gbuf_normal_tex },
        samplers = { gbuf_sampler, gbuf_sampler },
    }))

    -- SSAO uniforms: projection matrix, params
    local ssao_uniforms = proj:pack() .. string.pack("ffff",
        ssao_radius, ssao_bias, ssao_intensity, ssao_enabled and 1.0 or 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(ssao_uniforms))
    gfx.draw(0, 6, 1)

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
        views = { gbuf_position_tex, gbuf_normal_tex, gbuf_albedo_tex, ssao_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    -- Transform light position to view space
    local light_view = view * glm.vec4(light_pos.x, light_pos.y, light_pos.z, 1.0)

    -- Lighting uniforms (including fog, fresnel, rim, cel)
    local light_uniforms = string.pack("ffff ffff ffff ffff ffff ffff ffff ffff ffff",
        light_view.x, light_view.y, light_view.z, 1.0,
        light_color.x, light_color.y, light_color.z, 1.0,
        ambient_color.x, ambient_color.y, ambient_color.z, 1.0,
        fog_bg_color0[1], fog_bg_color0[2], fog_bg_color0[3], 1.0,
        fog_bg_color1[1], fog_bg_color1[2], fog_bg_color1[3], 1.0,
        fog_near, fog_far, fog_enabled and 1.0 or 0.0, fog_sun_position,
        fresnel_enabled and 1.0 or 0.0, fresnel_power, 0.0, 0.0,
        rim_light_enabled and 1.0 or 0.0, 0.0, 0.0, 0.0,
        cel_shading_enabled and 1.0 or 0.0, 0.0, 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(light_uniforms))
    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === SSR UV PASS ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 },
            }},
        }),
        attachments = {
            colors = { ssr_uv_attach },
        },
    }))

    gfx.apply_pipeline(ssr_uv_pipeline)

    -- SSR: Ray starts from water surface, searches through opaque scene
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { water_position_tex, water_normal_tex, water_reflection_mask_tex, gbuf_position_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    -- SSR UV uniforms: projection matrix, params
    local ssr_uv_uniforms = proj:pack() .. string.pack("ffff ffff",
        ssr_enabled and 1.0 or 0.0, ssr_max_distance, ssr_resolution, ssr_thickness,
        ssr_steps, ssr_debug, 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(ssr_uv_uniforms))
    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === REFRACTION UV PASS ===
    -- Similar to SSR UV, but uses refract() instead of reflect()
    -- Reads water G-buffer (refractive surface) and opaque G-buffer (what's behind)
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 },
            }},
        }),
        attachments = {
            colors = { refraction_uv_attach },
        },
    }))

    gfx.apply_pipeline(refraction_uv_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { water_position_tex, water_normal_tex, gbuf_position_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    -- Refraction UV uniforms: projection matrix, params (enabled, maxDistance, resolution, thickness, steps, ior)
    local refraction_uv_uniforms = proj:pack() .. string.pack("ffff ffff",
        refraction_enabled and 1.0 or 0.0, refraction_max_distance, refraction_resolution, refraction_thickness,
        refraction_steps, 1.0 / refraction_ior, 0.0, 0.0  -- ior is inverted (air->water = 1/1.33)
    )
    gfx.apply_uniforms(0, gfx.Range(refraction_uv_uniforms))
    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === REFRACTION COLOR PASS ===
    -- Samples scene at refracted UVs, applies water tint based on depth
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 },
            }},
        }),
        attachments = {
            colors = { refraction_attach },
        },
    }))

    gfx.apply_pipeline(refraction_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { refraction_uv_tex, scene_tex, water_position_tex, gbuf_position_tex, water_refraction_mask_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    -- Refraction color uniforms: tint_color (rgba), params (depthMax, debugMode)
    local refraction_color_uniforms = string.pack("ffff ffff",
        refraction_tint_r, refraction_tint_g, refraction_tint_b, refraction_tint_a,
        refraction_depth_max, refraction_debug and 1.0 or 0.0, 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(refraction_color_uniforms))

    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === REFLECTION COLOR PASS ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 },
            }},
        }),
        attachments = {
            colors = { reflection_attach },
        },
    }))

    gfx.apply_pipeline(reflection_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { ssr_uv_tex, refraction_tex, water_reflection_mask_tex },
        samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler },
    }))

    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- === MOTION BLUR PASS ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            }},
        }),
        attachments = {
            colors = { motion_attach },
        },
    }))

    gfx.apply_pipeline(motion_pipeline)

    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { gbuf_position_tex, scene_tex },
        samplers = { gbuf_sampler, gbuf_sampler },
    }))

    -- Motion blur uniforms: previousViewWorldMat (inverse of prev view), worldViewMat (current view), lensProjection
    -- Use current view as prev on first frame
    local effective_prev_view = prev_view or view
    local previousViewWorldMat = effective_prev_view:inverse()
    local motion_uniforms = previousViewWorldMat:pack() .. view:pack() .. proj:pack() .. string.pack("ffff",
        motion_blur_size, motion_blur_separation, motion_blur_enabled and 1.0 or 0.0, 0.0
    )
    gfx.apply_uniforms(0, gfx.Range(motion_uniforms))
    gfx.draw(0, 6, 1)

    gfx.end_pass()

    -- Store current view for next frame (copy the matrix)
    prev_view = glm.mat4(
        view[1], view[2], view[3], view[4],
        view[5], view[6], view[7], view[8],
        view[9], view[10], view[11], view[12],
        view[13], view[14], view[15], view[16]
    )

    -- === FINAL PASS (to swapchain) ===
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            }},
        }),
        swapchain = glue.swapchain(),
    }))

    if debug_buffer > 0 then
        -- Debug buffer display
        -- 1=Position, 2=Normal, 3=Albedo, 4=SSAO
        -- 5=WaterPosition, 6=WaterNormal, 7=SSR_UV, 8=Reflection, 9=RefractionUV, 10=Refraction
        local debug_textures = {
            gbuf_position_tex,    -- 1
            gbuf_normal_tex,      -- 2
            gbuf_albedo_tex,      -- 3
            ssao_tex,             -- 4
            water_position_tex,   -- 5
            water_normal_tex,     -- 6
            ssr_uv_tex,           -- 7
            reflection_tex,       -- 8
            refraction_uv_tex,    -- 9
            refraction_tex,       -- 10
        }
        -- Display modes: 0=color, 1=position, 2=normal, 3=uv
        local debug_modes = { 1, 2, 0, 0, 1, 2, 3, 0, 3, 0 }

        local tex = debug_textures[debug_buffer]
        local mode = debug_modes[debug_buffer] or 0

        gfx.apply_pipeline(debug_pipeline)
        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { quad_vbuf },
            views = { tex },
            samplers = { gbuf_sampler },
        }))
        gfx.apply_uniforms(0, gfx.Range(string.pack("ffff", mode, 0, 0, 0)))
        gfx.draw(0, 6, 1)
    else
        -- Normal blur pass
        gfx.apply_pipeline(blur_pipeline)

        gfx.apply_bindings(gfx.Bindings({
            vertex_buffers = { quad_vbuf },
            views = { motion_tex, reflection_tex, refraction_tex },
            samplers = { gbuf_sampler, gbuf_sampler, gbuf_sampler },
        }))

        -- Post-processing uniforms (blur + bloom + chromatic aberration)
        local post_uniforms = string.pack("ffff ffff ffff ffff",
            blur_size, blur_separation, blur_enabled and 1.0 or 0.0, 0.0,
            bloom_size, bloom_separation, bloom_threshold, bloom_amount,
            bloom_enabled and 1.0 or 0.0, 0.0, 0.0, 0.0,
            chromatic_enabled and 1.0 or 0.0, chromatic_red_offset, chromatic_green_offset, chromatic_blue_offset
        )
        gfx.apply_uniforms(0, gfx.Range(post_uniforms))
        gfx.draw(0, 6, 1)
    end

    -- ImGui debug UI
    if imgui.Begin("Debug") then
        -- Debug buffer selector at top
        if imgui.CollapsingHeader("Debug Buffer", true) then
            debug_buffer = imgui.SliderInt("Buffer", debug_buffer, 0, #debug_buffer_names - 1)
            imgui.Text("Current: " .. debug_buffer_names[debug_buffer + 1])
        end

        imgui.Text("Deferred Rendering + Fog + Blur")
        imgui.Separator()

        if imgui.CollapsingHeader("Light") then
            local lx, ly, lz, changed = imgui.InputFloat3("Light Position", light_pos.x, light_pos.y, light_pos.z)
            if changed then
                light_pos = glm.vec3(lx, ly, lz)
            end

            local lr, lg, lb
            lr, lg, lb, changed = imgui.ColorEdit3("Light Color", light_color.x, light_color.y, light_color.z)
            if changed then
                light_color = glm.vec3(lr, lg, lb)
            end

            local ar, ag, ab
            ar, ag, ab, changed = imgui.ColorEdit3("Ambient Color", ambient_color.x, ambient_color.y, ambient_color.z)
            if changed then
                ambient_color = glm.vec3(ar, ag, ab)
            end
        end

        if imgui.CollapsingHeader("Fog") then
            fog_enabled = imgui.Checkbox("Fog Enabled", fog_enabled)

            local r, g, b, changed = imgui.ColorEdit3("Horizon Color", fog_bg_color0[1], fog_bg_color0[2], fog_bg_color0[3])
            if changed then
                fog_bg_color0 = { r, g, b }
            end

            r, g, b, changed = imgui.ColorEdit3("Zenith Color", fog_bg_color1[1], fog_bg_color1[2], fog_bg_color1[3])
            if changed then
                fog_bg_color1 = { r, g, b }
            end

            fog_sun_position = imgui.SliderFloat("Sun Position", fog_sun_position, 0.0, 1.0)
            fog_near = imgui.SliderFloat("Fog Near", fog_near, 0.0, 100.0)
            fog_far = imgui.SliderFloat("Fog Far", fog_far, 50.0, 300.0)
        end

        if imgui.CollapsingHeader("Blur") then
            blur_enabled = imgui.Checkbox("Blur Enabled", blur_enabled)
            blur_size = imgui.SliderInt("Blur Size", blur_size, 0, 8)
            blur_separation = imgui.SliderFloat("Blur Separation", blur_separation, 1.0, 5.0)
        end

        if imgui.CollapsingHeader("Bloom") then
            bloom_enabled = imgui.Checkbox("Bloom Enabled", bloom_enabled)
            bloom_size = imgui.SliderInt("Bloom Size", bloom_size, 1, 10)
            bloom_separation = imgui.SliderFloat("Bloom Separation", bloom_separation, 1.0, 5.0)
            bloom_threshold = imgui.SliderFloat("Threshold", bloom_threshold, 0.0, 1.0)
            bloom_amount = imgui.SliderFloat("Amount", bloom_amount, 0.0, 3.0)
        end

        if imgui.CollapsingHeader("SSAO") then
            ssao_enabled = imgui.Checkbox("SSAO Enabled", ssao_enabled)
            ssao_radius = imgui.SliderFloat("Radius", ssao_radius, 0.1, 2.0)
            ssao_bias = imgui.SliderFloat("Bias", ssao_bias, 0.0, 0.1)
            ssao_intensity = imgui.SliderFloat("Intensity", ssao_intensity, 0.5, 3.0)
        end

        if imgui.CollapsingHeader("Motion Blur") then
            motion_blur_enabled = imgui.Checkbox("Motion Blur Enabled", motion_blur_enabled)
            motion_blur_size = imgui.SliderInt("Samples", motion_blur_size, 1, 16)
            motion_blur_separation = imgui.SliderFloat("Separation", motion_blur_separation, 0.5, 3.0)
        end

        if imgui.CollapsingHeader("Chromatic Aberration") then
            chromatic_enabled = imgui.Checkbox("Enabled", chromatic_enabled)
            chromatic_red_offset = imgui.SliderFloat("Red Offset", chromatic_red_offset, -0.02, 0.02)
            chromatic_green_offset = imgui.SliderFloat("Green Offset", chromatic_green_offset, -0.02, 0.02)
            chromatic_blue_offset = imgui.SliderFloat("Blue Offset", chromatic_blue_offset, -0.02, 0.02)
        end

        if imgui.CollapsingHeader("Screen Space Reflection") then
            ssr_enabled = imgui.Checkbox("SSR Enabled", ssr_enabled)
            ssr_max_distance = imgui.SliderFloat("Max Distance", ssr_max_distance, 1.0, 20.0)
            ssr_resolution = imgui.SliderFloat("Resolution", ssr_resolution, 0.1, 1.0)
            ssr_steps = imgui.SliderInt("Refinement Steps", ssr_steps, 1, 16)
            ssr_thickness = imgui.SliderFloat("Thickness", ssr_thickness, 0.1, 2.0)
            ssr_debug = imgui.SliderInt("Debug (0=off,1=mask,2=water)", ssr_debug, 0, 3)
        end

        if imgui.CollapsingHeader("Screen Space Refraction") then
            refraction_enabled = imgui.Checkbox("Refraction Enabled", refraction_enabled)
            refraction_debug = imgui.Checkbox("Debug Visibility##refr", refraction_debug)
            refraction_ior = imgui.SliderFloat("IOR##refr", refraction_ior, 1.0, 2.0)
            refraction_max_distance = imgui.SliderFloat("Max Distance##refr", refraction_max_distance, 1.0, 20.0)
            refraction_resolution = imgui.SliderFloat("Resolution##refr", refraction_resolution, 0.1, 1.0)
            refraction_steps = imgui.SliderInt("Refinement Steps##refr", refraction_steps, 1, 16)
            refraction_thickness = imgui.SliderFloat("Thickness##refr", refraction_thickness, 0.1, 2.0)
            imgui.Separator()
            imgui.Text("Water Tint Color")
            local r, g, b, changed = imgui.ColorEdit3("Tint##refr", refraction_tint_r, refraction_tint_g, refraction_tint_b)
            if changed then refraction_tint_r, refraction_tint_g, refraction_tint_b = r, g, b end
            refraction_tint_a = imgui.SliderFloat("Tint Intensity##refr", refraction_tint_a, 0.0, 1.0)
            refraction_depth_max = imgui.SliderFloat("Depth Max##refr", refraction_depth_max, 0.5, 10.0)
            imgui.Text(string.format("Water meshes: %d", #water_meshes))
        end

        if imgui.CollapsingHeader("Lighting Effects") then
            fresnel_enabled = imgui.Checkbox("Fresnel Enabled", fresnel_enabled)
            fresnel_power = imgui.SliderFloat("Fresnel Power", fresnel_power, 1.0, 5.0)

            rim_light_enabled = imgui.Checkbox("Rim Light Enabled", rim_light_enabled)

            cel_shading_enabled = imgui.Checkbox("Cel Shading Enabled", cel_shading_enabled)
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
