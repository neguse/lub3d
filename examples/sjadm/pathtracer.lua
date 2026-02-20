-- sjadm path tracer
-- Fragment shader path tracing with ping-pong accumulation
-- Based on hakonotaiatari/pathtracer.lua (PR #35)

local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local glm = require("lib.glm")
local gpu = require("lib.gpu")
local rt_mod = require("lib.render_target")
local shader_mod = require("lib.shader")
local util = require("lib.util")
local log = require("lib.log")

local M = {}

-- Max boxes in scene (platforms + kills visible on screen)
local MAX_BOXES <const> = 80
local MAX_SHADOWS <const> = 16

-- Uniform block layout:
-- Header: 11 vec4 = 44 floats
-- Shadows: MAX_SHADOWS vec4 = 16 vec4 = 64 floats
-- Boxes: MAX_BOXES * 2 vec4 = 160 vec4 = 640 floats
local HEADER_SIZE <const> = 11 * 4 -- 44 floats
local SHADOW_STRIDE <const> = 4    -- 4 floats per shadow (x, y, hw, hh)
local SHADOW_SECTION <const> = MAX_SHADOWS * SHADOW_STRIDE -- 64 floats
local BOX_STRIDE <const> = 2 * 4   -- 8 floats per box
local UNIFORM_FLOATS <const> = HEADER_SIZE + SHADOW_SECTION + MAX_BOXES * BOX_STRIDE
local UNIFORM_SIZE <const> = UNIFORM_FLOATS * 4 -- bytes

-- Resources
---@type render_target.ColorTarget[]
local rt = {}
local read_idx, write_idx = 1, 2
local pt_shader = nil
local pt_pipeline = nil
local out_shader = nil
local out_pipeline = nil
local quad_vbuf = nil
---@type gpu.Sampler?
local tex_sampler = nil
local frame_count = 0
local accum_count = 0
local rt_width, rt_height = 0, 0
local prev_eye = nil
local prev_lookat = nil

-- Coordinate scale: game units → world units
local SCALE <const> = 1.0 / 1000.0

-- Tunable parameters (exposed for ImGui)
M.exposure = 1.5
M.gamma = 2.2
M.max_accum_moving = 4
M.max_accum_still = 32

-- ============================================================
-- Path tracing shader
-- ============================================================
local pt_shader_source = [[
@vs pt_vs
in vec2 pos;
out vec2 uv;
void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    uv = pos * 0.5 + 0.5;
}
@end

@fs pt_fs
in vec2 uv;
out vec4 frag_color;

layout(binding=0) uniform texture2D prev_frame_tex;
layout(binding=0) uniform sampler prev_frame_smp;

layout(binding=0) uniform fs_params {
    vec4 camera_origin;
    vec4 camera_forward;
    vec4 camera_right;
    vec4 camera_up;
    vec4 frame_params;      // x=frame, y=accum, z=time, w=fov_scale
    vec4 scene_info;        // x=num_boxes, y=num_kills_start, z=num_items, w=0
    vec4 player_pos;        // x=px, y=py, z=hw, w=hh
    vec4 player_ext;        // x=depth, y=alive, z=dash_time, w=dead_timer
    vec4 light_params;      // xyz=pos, w=radius
    vec4 light_color;       // xyz=color, w=intensity
    vec4 shadow_info;       // x=num_shadows, y=0, z=0, w=0
    vec4 shadow_data[]] .. tostring(MAX_SHADOWS) .. [[]; // xy=pos, zw=hw,hh (scaled)
    vec4 box_data[]] .. tostring(MAX_BOXES * 2) .. [[];
};

#define MAT_DIFF 0
#define MAT_GLOSSY 1
#define MAT_EMISSIVE 2

#define MAX_BOUNCES 4
#define EPS 0.01
#define INF 1e20
#define PI 3.14159265358979

// Box types
#define BOX_PLATFORM 0.0
#define BOX_KILL 1.0
#define BOX_ITEM 2.0
#define BOX_CHECKPOINT 3.0

// ---- RNG: PCG hash ----
uint pcg_hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float rand(inout uint seed) {
    seed = pcg_hash(seed);
    return float(seed) / 4294967296.0;
}

// ---- Sampling ----
vec3 cosine_weighted_hemisphere(vec3 n, inout uint seed) {
    float u1 = rand(seed);
    float u2 = rand(seed);
    float r = sqrt(u1);
    float theta = 2.0 * PI * u2;
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(max(0.0, 1.0 - u1));

    vec3 w = n;
    vec3 a = abs(w.x) > 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0);
    vec3 u = normalize(cross(a, w));
    vec3 v = cross(w, u);

    return normalize(u * x + v * y + w * z);
}

// ---- Intersection: Ray-AABB slab test ----
bool intersect_aabb(vec3 ro, vec3 rd, vec3 box_min, vec3 box_max,
                    out float t_hit, out vec3 normal) {
    vec3 inv_rd = 1.0 / rd;
    vec3 t0 = (box_min - ro) * inv_rd;
    vec3 t1 = (box_max - ro) * inv_rd;
    vec3 tmin = min(t0, t1);
    vec3 tmax = max(t0, t1);
    float t_enter = max(max(tmin.x, tmin.y), tmin.z);
    float t_exit = min(min(tmax.x, tmax.y), tmax.z);

    if (t_enter > t_exit || t_exit < 0.0) return false;

    t_hit = t_enter > 0.0 ? t_enter : t_exit;
    if (t_hit < 0.0) return false;

    if (t_enter > 0.0) {
        if (tmin.x > tmin.y && tmin.x > tmin.z)
            normal = vec3(rd.x > 0.0 ? -1.0 : 1.0, 0.0, 0.0);
        else if (tmin.y > tmin.z)
            normal = vec3(0.0, rd.y > 0.0 ? -1.0 : 1.0, 0.0);
        else
            normal = vec3(0.0, 0.0, rd.z > 0.0 ? -1.0 : 1.0);
    } else {
        if (tmax.x < tmax.y && tmax.x < tmax.z)
            normal = vec3(rd.x > 0.0 ? 1.0 : -1.0, 0.0, 0.0);
        else if (tmax.y < tmax.z)
            normal = vec3(0.0, rd.y > 0.0 ? 1.0 : -1.0, 0.0);
        else
            normal = vec3(0.0, 0.0, rd.z > 0.0 ? 1.0 : -1.0);
    }
    return true;
}

// ---- Intersection: Z-axis rotated box (side-scrolling) ----
bool intersect_rotated_box(vec3 ro, vec3 rd, vec3 center, vec3 half_ext,
                           float angle_z, out float t_hit, out vec3 normal) {
    // Transform ray into box local space (rotate around Z axis)
    float c = cos(-angle_z);
    float s = sin(-angle_z);

    vec3 local_ro = ro - center;
    local_ro = vec3(local_ro.x * c + local_ro.y * s,
                    -local_ro.x * s + local_ro.y * c,
                    local_ro.z);

    vec3 local_rd = vec3(rd.x * c + rd.y * s,
                         -rd.x * s + rd.y * c,
                         rd.z);

    vec3 box_min = -half_ext;
    vec3 box_max = half_ext;

    vec3 local_normal;
    if (!intersect_aabb(local_ro, local_rd, box_min, box_max, t_hit, local_normal))
        return false;

    // Transform normal back to world space
    float c2 = cos(angle_z);
    float s2 = sin(angle_z);
    normal = vec3(local_normal.x * c2 + local_normal.y * s2,
                  -local_normal.x * s2 + local_normal.y * c2,
                  local_normal.z);
    return true;
}

// ---- Intersection: Sphere ----
bool intersect_sphere(vec3 ro, vec3 rd, vec3 center, float radius,
                      out float t_hit, out vec3 normal) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return false;
    float sq = sqrt(disc);
    t_hit = -b - sq;
    if (t_hit < EPS) {
        t_hit = -b + sq;
        if (t_hit < EPS) return false;
    }
    vec3 p = ro + rd * t_hit;
    normal = normalize(p - center);
    return true;
}

// ---- Intersection: Ground plane (y = floor_y) ----
bool intersect_ground(vec3 ro, vec3 rd, float floor_y,
                      out float t_hit, out vec3 normal) {
    if (abs(rd.y) < 1e-6) return false;
    t_hit = (floor_y - ro.y) / rd.y;
    if (t_hit < 0.0) return false;
    normal = vec3(0.0, 1.0, 0.0);
    return true;
}

// ---- Scene data structures ----
struct HitInfo {
    float t;
    vec3 normal;
    vec3 albedo;
    int material;
    vec3 emission;
    float roughness;
};

// ---- Scene intersection ----
bool trace_scene(vec3 ro, vec3 rd, out HitInfo hit) {
    hit.t = INF;
    hit.emission = vec3(0.0);
    bool found = false;

    int num_boxes = int(scene_info.x);
    int num_kills_start = int(scene_info.y);
    int num_items = int(scene_info.z);

    // Ground plane at y = -10 (far below)
    float t_ground;
    vec3 n_ground;
    if (intersect_ground(ro, rd, -10.0, t_ground, n_ground) && t_ground < hit.t) {
        hit.t = t_ground;
        hit.normal = n_ground;
        hit.albedo = vec3(0.03, 0.03, 0.06);
        hit.material = MAT_DIFF;
        hit.roughness = 1.0;
        found = true;
    }

    // Background wall at z = -2 (behind the scene)
    {
        float t_bg = (-2.0 - ro.z) / rd.z;
        if (t_bg > EPS && t_bg < hit.t) {
            hit.t = t_bg;
            hit.normal = vec3(0.0, 0.0, 1.0);
            hit.albedo = vec3(0.9, 0.9, 0.92);
            hit.material = MAT_DIFF;
            hit.roughness = 1.0;
            hit.emission = vec3(0.0);
            found = true;
        }
    }

    // Platforms and kill zones (box_data)
    for (int i = 0; i < num_boxes && i < ]] .. tostring(MAX_BOXES) .. [[; i++) {
        vec4 b0 = box_data[i * 2 + 0]; // cx, cy, hw, hh
        vec4 b1 = box_data[i * 2 + 1]; // angle, depth, type, 0

        vec3 center = vec3(b0.x, b0.y, 0.0);
        float hw = b0.z;
        float hh = b0.w;
        float depth = b1.y;
        float angle = b1.x;
        float box_type = b1.z;
        vec3 half_ext = vec3(hw, hh, depth);

        float t_box;
        vec3 n_box;
        if (intersect_rotated_box(ro, rd, center, half_ext, angle, t_box, n_box)
            && t_box > EPS && t_box < hit.t) {
            hit.t = t_box;
            hit.normal = n_box;
            hit.roughness = 0.3;

            if (box_type == BOX_KILL) {
                // Kill zone: red emissive
                hit.albedo = vec3(0.9, 0.15, 0.1);
                hit.material = MAT_EMISSIVE;
                hit.emission = vec3(1.5, 0.2, 0.1);
            } else if (box_type == BOX_ITEM) {
                // Items: golden glow
                hit.albedo = vec3(1.0, 0.85, 0.3);
                hit.material = MAT_EMISSIVE;
                hit.emission = vec3(1.0, 0.8, 0.2) * 2.0;
            } else if (box_type == BOX_CHECKPOINT) {
                float is_active = b1.w;
                if (is_active > 0.5) {
                    // Active checkpoint: bright cyan glow
                    hit.albedo = vec3(0.4, 1.0, 1.0);
                    hit.material = MAT_EMISSIVE;
                    hit.emission = vec3(1.5, 4.0, 5.0);
                } else {
                    // Inactive checkpoint: dim
                    hit.albedo = vec3(0.2, 0.4, 0.5);
                    hit.material = MAT_DIFF;
                    hit.emission = vec3(0.0);
                }
            } else {
                // Platform: white/grey
                hit.albedo = vec3(0.8, 0.8, 0.85);
                hit.material = MAT_DIFF;
            }
            found = true;
        }
    }

    // Player box
    float p_dash = player_ext.z;   // dash_time (0.5 → 0)
    float p_dead = player_ext.w;   // dead_timer (1.5 → 0)

    if (player_ext.y > 0.5) {
        // Alive: normal or dashing
        vec3 p_center = vec3(player_pos.x, player_pos.y, 0.0);
        vec3 p_half = vec3(player_pos.z, player_pos.w, player_ext.x);

        // Dash: stretch horizontally
        if (p_dash > 0.0) {
            float stretch = 1.0 + p_dash * 3.0;
            p_half.x *= stretch;
        }

        float t_p;
        vec3 n_p;
        if (intersect_rotated_box(ro, rd, p_center, p_half, 0.0, t_p, n_p)
            && t_p > EPS && t_p < hit.t) {
            hit.t = t_p;
            hit.normal = n_p;
            if (p_dash > 0.0) {
                // Dashing: bright blue-white burst
                float intensity = p_dash * 2.0;
                hit.albedo = vec3(0.7, 0.85, 1.0);
                hit.material = MAT_EMISSIVE;
                hit.emission = vec3(3.0, 5.0, 8.0) * intensity;
            } else {
                hit.albedo = vec3(0.9, 0.95, 1.0);
                hit.material = MAT_GLOSSY;
                hit.emission = vec3(2.0, 2.5, 3.5);
                hit.roughness = 0.15;
            }
            found = true;
        }
    } else if (p_dead > 0.0) {
        // Dead: expanding glowing sphere
        vec3 p_center = vec3(player_pos.x, player_pos.y, 0.0);
        float expand = (1.5 - p_dead) / 1.5;  // 0 → 1
        float radius = mix(0.005, 0.08, expand);
        float t_s = INF;
        vec3 oc = ro - p_center;
        float b = dot(oc, rd);
        float c = dot(oc, oc) - radius * radius;
        float disc = b * b - c;
        if (disc > 0.0) {
            t_s = -b - sqrt(disc);
            if (t_s > EPS && t_s < hit.t) {
                hit.t = t_s;
                hit.normal = normalize(ro + rd * t_s - p_center);
                float fade = p_dead / 1.5;  // 1 → 0
                hit.albedo = vec3(1.0, 0.3, 0.1);
                hit.material = MAT_EMISSIVE;
                hit.emission = vec3(8.0, 2.0, 0.5) * fade;
                found = true;
            }
        }
    }

    // Shadow trail (afterimages)
    int num_shadows = int(shadow_info.x);
    for (int si = 0; si < num_shadows && si < ]] .. tostring(MAX_SHADOWS) .. [[; si++) {
        vec4 sd = shadow_data[si];
        vec3 s_center = vec3(sd.x, sd.y, 0.0);
        vec3 s_half = vec3(sd.z, sd.w, sd.z * 0.5);
        float t_s;
        vec3 n_s;
        if (intersect_rotated_box(ro, rd, s_center, s_half, 0.0, t_s, n_s)
            && t_s > EPS && t_s < hit.t) {
            hit.t = t_s;
            hit.normal = n_s;
            float fade = 1.0 - float(si) / float(max(num_shadows, 1));
            hit.albedo = vec3(0.5, 0.7, 1.0);
            hit.material = MAT_EMISSIVE;
            hit.emission = vec3(1.0, 2.0, 4.0) * fade * fade;
            found = true;
        }
    }

    return found;
}

// ---- Area light sampling (NEE) ----
vec3 sample_area_light(vec3 p, vec3 n, vec4 lp, vec4 lc, inout uint seed) {
    vec3 light_center = lp.xyz;
    float light_radius = lp.w;
    if (light_radius < 0.01) return vec3(0.0);

    float u1 = rand(seed);
    float u2 = rand(seed);
    float z = 1.0 - 2.0 * u1;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = 2.0 * PI * u2;
    vec3 sample_pos = light_center + light_radius * vec3(r * cos(phi), z, r * sin(phi));

    vec3 to_light = sample_pos - p;
    float dist2 = dot(to_light, to_light);
    float dist = sqrt(dist2);
    vec3 light_dir = to_light / dist;

    float cos_theta = dot(n, light_dir);
    if (cos_theta <= 0.0) return vec3(0.0);

    HitInfo shadow_hit;
    if (trace_scene(p + n * EPS, light_dir, shadow_hit) && shadow_hit.t < dist - EPS) {
        return vec3(0.0);
    }

    float sphere_area = 4.0 * PI * light_radius * light_radius;
    return lc.rgb * lc.w * cos_theta * sphere_area / (dist2 * 4.0 * PI);
}

// ---- Path tracing ----
vec3 calculate_radiance(vec3 ro, vec3 rd, inout uint seed) {
    vec3 radiance = vec3(0.0);
    vec3 throughput = vec3(1.0);

    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
        HitInfo hit;
        if (!trace_scene(ro, rd, hit)) {
            // Sky: dark blue gradient
            float sky_t = 0.5 * (rd.y + 1.0);
            vec3 sky = mix(vec3(0.01, 0.01, 0.04), vec3(0.05, 0.08, 0.2), clamp(sky_t, 0.0, 1.0));
            radiance += throughput * sky;
            break;
        }

        vec3 p = ro + rd * hit.t;
        vec3 n = hit.normal;

        // Emissive contribution
        radiance += throughput * hit.emission;

        if (hit.material == MAT_EMISSIVE) {
            break; // No further bounces from emissive surfaces
        }

        if (hit.material == MAT_DIFF) {
            vec3 direct = sample_area_light(p, n, light_params, light_color, seed);
            radiance += throughput * hit.albedo * direct;

            throughput *= hit.albedo;
            rd = cosine_weighted_hemisphere(n, seed);
            ro = p + n * EPS;
        }
        else if (hit.material == MAT_GLOSSY) {
            vec3 direct = sample_area_light(p, n, light_params, light_color, seed);
            radiance += throughput * hit.albedo * direct * hit.roughness;

            vec3 reflected = reflect(rd, n);
            vec3 diffuse_dir = cosine_weighted_hemisphere(n, seed);
            rd = normalize(mix(reflected, diffuse_dir, hit.roughness));
            ro = p + n * EPS;
            throughput *= hit.albedo;
        }

        // Russian roulette after bounce 2
        if (bounce > 1) {
            float p_survive = max(max(throughput.x, throughput.y), throughput.z);
            p_survive = clamp(p_survive, 0.05, 0.95);
            if (rand(seed) > p_survive) break;
            throughput /= p_survive;
        }
    }

    return max(radiance, vec3(0.0));
}

void main() {
    float frame = frame_params.x;
    float accum = frame_params.y;
    float fov_scale = frame_params.w;

    // Per-pixel RNG seed
    uint seed = pcg_hash(uint(gl_FragCoord.x) * 1973u +
                         uint(gl_FragCoord.y) * 9277u +
                         uint(frame) * 26699u);

    // Jittered sub-pixel
    vec2 res = vec2(textureSize(sampler2D(prev_frame_tex, prev_frame_smp), 0));
    float jx = (rand(seed) - 0.5) / res.x;
    float jy = (rand(seed) - 0.5) / res.y;
    vec2 pixel = uv + vec2(jx, jy);

    // Camera ray
    vec2 screen = pixel * 2.0 - 1.0;
    vec3 ro = camera_origin.xyz;
    float aspect = res.x / res.y;
    vec3 rd = normalize(camera_forward.xyz * fov_scale
                        + screen.x * aspect * camera_right.xyz
                        + screen.y * camera_up.xyz);

    // Path trace
    vec3 color = calculate_radiance(ro, rd, seed);

    // Accumulation blending
    vec3 prev = texture(sampler2D(prev_frame_tex, prev_frame_smp), vec2(uv.x, 1.0 - uv.y)).rgb;
    float blend = 1.0 / (accum + 1.0);
    vec3 accumulated = mix(prev, color, blend);

    frag_color = vec4(accumulated, 1.0);
}
@end

@program sjadm_pathtracer pt_vs pt_fs
]]

-- ============================================================
-- Output (tonemap) shader
-- ============================================================
local out_shader_source = [[
@vs out_vs
in vec2 pos;
out vec2 uv;
void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    uv = pos * 0.5 + 0.5;
}
@end

@fs out_fs
in vec2 uv;
out vec4 frag_color;

layout(binding=0) uniform texture2D accum_tex;
layout(binding=0) uniform sampler accum_smp;

layout(binding=0) uniform fs_params {
    vec4 params;  // x=exposure, y=gamma, z=0, w=0
    vec4 params2; // pad
};

void main() {
    vec2 sample_uv = vec2(uv.x, 1.0 - uv.y);
    vec3 color = texture(sampler2D(accum_tex, accum_smp), sample_uv).rgb;

    // Reinhard tone mapping
    color *= params.x;
    color = color / (color + vec3(1.0));

    // Gamma correction
    color = pow(color, vec3(1.0 / params.y));

    frag_color = vec4(color, 1.0);
}
@end

@program sjadm_output out_vs out_fs
]]

-- ============================================================
-- Shader descriptors
-- ============================================================
local pt_shader_desc = {
    uniform_blocks = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            size = UNIFORM_SIZE,
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
    },
    samplers = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 0,
            wgsl_group1_binding_n = 32,
        },
    },
    texture_sampler_pairs = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            view_slot = 0,
            sampler_slot = 0,
            glsl_name = "prev_frame_tex_prev_frame_smp",
        },
    },
    attrs = {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
    },
}

local out_shader_desc = {
    uniform_blocks = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            size = 32, -- 2 vec4
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
    },
    samplers = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            sampler_type = gfx.SamplerType.FILTERING,
            hlsl_register_s_n = 0,
            wgsl_group1_binding_n = 32,
        },
    },
    texture_sampler_pairs = {
        {
            stage = gfx.ShaderStage.FRAGMENT,
            view_slot = 0,
            sampler_slot = 0,
            glsl_name = "accum_tex_accum_smp",
        },
    },
    attrs = {
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
    },
}

-- ============================================================
-- Resource management
-- ============================================================

local function create_render_targets(w, h)
    for i = 1, 2 do
        ---@diagnostic disable-next-line: need-check-nil
        if rt[i] then rt[i]:destroy() end
    end
    rt[1] = rt_mod.color(w, h, gfx.PixelFormat.RGBA32F)
    rt[2] = rt_mod.color(w, h, gfx.PixelFormat.RGBA32F)
    rt_width = w
    rt_height = h
    read_idx = 1
    write_idx = 2
    accum_count = 0
    log.info(string.format("sjadm PT render targets: %dx%d", w, h))
end

function M.init()
    pt_shader = shader_mod.compile_full(pt_shader_source, "sjadm_pathtracer", pt_shader_desc)
    if not pt_shader then
        log.error("sjadm PT shader compilation failed!")
        return false
    end

    out_shader = shader_mod.compile_full(out_shader_source, "sjadm_output", out_shader_desc)
    if not out_shader then
        log.error("sjadm output shader compilation failed!")
        return false
    end

    -- Pipelines
    pt_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = pt_shader,
        layout = { attrs = { { format = gfx.VertexFormat.FLOAT2 } } },
        primitive_type = gfx.PrimitiveType.TRIANGLE_STRIP,
        color_count = 1,
        colors = { { pixel_format = gfx.PixelFormat.RGBA32F } },
        depth = { pixel_format = gfx.PixelFormat.NONE },
    }))
    if gfx.query_pipeline_state(pt_pipeline) ~= gfx.ResourceState.VALID then
        log.error("sjadm PT pipeline creation failed!")
        return false
    end

    out_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = out_shader,
        layout = { attrs = { { format = gfx.VertexFormat.FLOAT2 } } },
        primitive_type = gfx.PrimitiveType.TRIANGLE_STRIP,
    }))
    if gfx.query_pipeline_state(out_pipeline) ~= gfx.ResourceState.VALID then
        log.error("sjadm output pipeline creation failed!")
        return false
    end

    -- Fullscreen quad
    quad_vbuf = gfx.make_buffer(gfx.BufferDesc({
        data = gfx.Range(util.pack_floats({ -1, -1, 1, -1, -1, 1, 1, 1 })),
        usage = { vertex_buffer = true, immutable = true },
    }))

    -- Sampler
    tex_sampler = gpu.sampler(gfx.SamplerDesc({
        min_filter = gfx.Filter.LINEAR,
        mag_filter = gfx.Filter.LINEAR,
        wrap_u = gfx.Wrap.CLAMP_TO_EDGE,
        wrap_v = gfx.Wrap.CLAMP_TO_EDGE,
    }))

    -- Create initial render targets
    local w = math.max(app.width(), 1)
    local h = math.max(app.height(), 1)
    create_render_targets(w, h)

    log.info("sjadm path tracer initialized")
    return true
end

function M.cleanup()
    for i = 1, 2 do
        ---@diagnostic disable-next-line: need-check-nil
        if rt[i] then rt[i]:destroy(); rt[i] = nil end
    end
    if tex_sampler then tex_sampler:destroy(); tex_sampler = nil end
end

-- ============================================================
-- Scene data packing
-- ============================================================

--- Pack scene data into uniform float array
---@param boxes table[] Array of {cx, cy, hw, hh, angle, type}
---@param player_info table {x, y, hw, hh, alive}
---@param camera_eye table {x,y,z}
---@param camera_lookat table {x,y,z}
---@param items table[] Array of {x, y, radius}
---@param checkpoints table[] Array of {x, y, radius}
---@return string packed Packed uniform data
function M.pack_scene(boxes, player_info, camera_eye, camera_lookat, items, checkpoints)
    local data = {}
    for i = 1, UNIFORM_FLOATS do data[i] = 0 end

    -- Camera vectors
    local eye = glm.vec3(camera_eye.x, camera_eye.y, camera_eye.z)
    local target = glm.vec3(camera_lookat.x, camera_lookat.y, camera_lookat.z)
    local forward = glm.normalize(target - eye)
    local right = glm.normalize(glm.cross(forward, glm.vec3(0, 1, 0)))
    local up = glm.cross(right, forward)

    local fov_scale = 1.0 / math.tan(math.rad(45) * 0.5)

    -- camera_origin (vec4)
    data[1], data[2], data[3], data[4] = eye.x, eye.y, eye.z, 0
    -- camera_forward (vec4)
    data[5], data[6], data[7], data[8] = forward.x, forward.y, forward.z, 0
    -- camera_right (vec4)
    data[9], data[10], data[11], data[12] = right.x, right.y, right.z, 0
    -- camera_up (vec4)
    data[13], data[14], data[15], data[16] = up.x, up.y, up.z, 0
    -- frame_params (vec4)
    data[17] = frame_count
    data[18] = accum_count
    data[19] = frame_count / 60.0
    data[20] = fov_scale

    -- Count kill zones: items/checkpoints added after real boxes
    local num_platform_and_kill = #boxes
    local num_items_spheres = #items
    local num_checkpoints_spheres = #checkpoints
    local total_boxes = num_platform_and_kill + num_items_spheres + num_checkpoints_spheres
    total_boxes = math.min(total_boxes, MAX_BOXES)

    -- scene_info (vec4)
    data[21] = total_boxes
    data[22] = 0  -- num_kills_start (not used separately)
    data[23] = num_items_spheres
    data[24] = 0

    -- player (vec4)
    data[25] = player_info.x * SCALE
    data[26] = player_info.y * SCALE
    data[27] = player_info.hw * SCALE
    data[28] = player_info.hh * SCALE
    -- player_ext (vec4)
    local p_depth = math.min(player_info.hw, player_info.hh) * 0.3 * SCALE
    data[29] = p_depth
    data[30] = player_info.alive and 1.0 or 0.0
    data[31] = player_info.dash_time or 0
    data[32] = player_info.dead_timer or 0

    -- light_params (vec4): area light above scene, following camera
    data[33] = camera_eye.x
    data[34] = camera_eye.y + 4.0
    data[35] = camera_eye.z + 2.0
    data[36] = 1.5  -- radius
    -- light_color (vec4)
    data[37] = 1.0
    data[38] = 0.95
    data[39] = 0.85
    data[40] = 4.0  -- intensity

    -- shadow_info (vec4)
    local shadows = player_info.shadows or {}
    local num_shadows = math.min(math.max(#shadows - 1, 0), MAX_SHADOWS)
    data[41] = num_shadows
    data[42] = 0
    data[43] = 0
    data[44] = 0

    -- shadow_data (MAX_SHADOWS vec4) — newest first, skip last (= current pos)
    local shadow_base = HEADER_SIZE  -- 44
    local total_shadows = #shadows
    for i = 1, num_shadows do
        local s = shadows[total_shadows - i]  -- skip current pos, newest first
        if s then
            local idx = shadow_base + (i - 1) * SHADOW_STRIDE
            data[idx + 1] = s.x * SCALE
            data[idx + 2] = s.y * SCALE
            data[idx + 3] = (player_info.hw or 12.5) * SCALE
            data[idx + 4] = (player_info.hh or 25) * SCALE
        end
    end

    -- Box data
    local base = HEADER_SIZE + SHADOW_SECTION
    local bi = 0

    -- Platform/kill boxes
    for i = 1, num_platform_and_kill do
        if bi >= MAX_BOXES then break end
        local box = boxes[i]
        local idx = base + bi * BOX_STRIDE
        data[idx + 1] = box.cx * SCALE
        data[idx + 2] = box.cy * SCALE
        data[idx + 3] = box.hw * SCALE
        data[idx + 4] = box.hh * SCALE
        data[idx + 5] = box.angle
        local depth = math.min(box.hw, box.hh) * 0.3 * SCALE
        data[idx + 6] = depth
        data[idx + 7] = box.type  -- 0=platform, 1=kill
        data[idx + 8] = 0
        bi = bi + 1
    end

    -- Items as small boxes (type=2)
    for i = 1, num_items_spheres do
        if bi >= MAX_BOXES then break end
        local it = items[i]
        local idx = base + bi * BOX_STRIDE
        local r = it.radius * SCALE
        data[idx + 1] = it.x * SCALE
        data[idx + 2] = it.y * SCALE
        data[idx + 3] = r
        data[idx + 4] = r
        data[idx + 5] = 0  -- no rotation
        data[idx + 6] = r  -- depth = radius
        data[idx + 7] = 2  -- BOX_ITEM
        data[idx + 8] = 0
        bi = bi + 1
    end

    -- Checkpoints as boxes (type=3)
    for i = 1, num_checkpoints_spheres do
        if bi >= MAX_BOXES then break end
        local cp = checkpoints[i]
        local idx = base + bi * BOX_STRIDE
        local r = cp.radius * SCALE * 0.3  -- visual size smaller than physics
        data[idx + 1] = cp.x * SCALE
        data[idx + 2] = cp.y * SCALE
        data[idx + 3] = r
        data[idx + 4] = r
        data[idx + 5] = 0
        data[idx + 6] = r
        data[idx + 7] = 3  -- BOX_CHECKPOINT
        data[idx + 8] = cp.active and 1.0 or 0.0
        bi = bi + 1
    end

    return util.pack_floats(data)
end

-- ============================================================
-- Rendering
-- ============================================================

--- Render path traced frame
--- Returns true if the swapchain pass is open (caller must end it)
---@param boxes table[]
---@param player_info table
---@param camera_params table {eye={x,y,z}, target={x,y,z}}
---@param items table[]
---@param checkpoints table[]
---@return boolean pass_open
function M.render(boxes, player_info, camera_params, items, checkpoints)
    if not pt_pipeline or not out_pipeline or not rt[1] or not tex_sampler then return false end

    -- Check resize
    local w = math.max(app.width(), 1)
    local h = math.max(app.height(), 1)
    if w ~= rt_width or h ~= rt_height then
        create_render_targets(w, h)
    end

    -- Camera motion detection
    local eye = glm.vec3(camera_params.eye.x, camera_params.eye.y, camera_params.eye.z)
    local lookat = glm.vec3(camera_params.target.x, camera_params.target.y, camera_params.target.z)
    local camera_moving = false

    if prev_eye then
        local eye_dist = glm.length(eye - prev_eye)
        local lookat_dist = glm.length(lookat - prev_lookat)
        if eye_dist > 0.001 or lookat_dist > 0.001 then
            camera_moving = true
        end
    end
    prev_eye = eye
    prev_lookat = lookat

    -- Cap accumulation: short when moving (keeps responsiveness),
    -- longer when still (reduces noise)
    local max_accum = camera_moving and M.max_accum_moving or M.max_accum_still
    if accum_count >= max_accum then
        accum_count = 0
    end

    -- Pack scene uniforms
    local scene_data = M.pack_scene(boxes, player_info, camera_params.eye, camera_params.target, items, checkpoints)

    -- Pass 1: Path trace → rt[write_idx]
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.LOAD } },
        }),
        attachments = {
            colors = { rt[write_idx].attach.handle },
        },
    }))

    gfx.apply_pipeline(pt_pipeline)
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { rt[read_idx].tex.handle },
        samplers = { tex_sampler.handle },
    }))
    gfx.apply_uniforms(0, gfx.Range(scene_data))
    gfx.draw(0, 4, 1)
    gfx.end_pass()

    -- Swap
    read_idx, write_idx = write_idx, read_idx

    -- Pass 2: Output (tonemap) → swapchain
    -- Pass left OPEN for HUD overlay
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 1 } } },
        }),
        swapchain = glue.swapchain(),
    }))

    gfx.apply_pipeline(out_pipeline)
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { quad_vbuf },
        views = { rt[read_idx].tex.handle },
        samplers = { tex_sampler.handle },
    }))
    gfx.apply_uniforms(0, gfx.Range(util.pack_floats({
        M.exposure, M.gamma, 0, 0,
        0, 0, 0, 0,
    })))
    gfx.draw(0, 4, 1)
    -- Pass left OPEN for sdtx overlay

    accum_count = accum_count + 1
    frame_count = frame_count + 1
    return true
end

return M
