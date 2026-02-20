-- hakonotaiatari path tracer
-- Fragment shader path tracing with ping-pong accumulation
-- Inspired by THREE.js-PathTracing-Renderer

local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local glm = require("lib.glm")
local gpu = require("lib.gpu")
local rt_mod = require("lib.render_target")
local shader_mod = require("lib.shader")
local util = require("lib.util")
local log = require("lib.log")
local const = require("examples.hakonotaiatari.const")

local M = {}

-- Max cubes in scene (player + enemies + spare)
local MAX_CUBES <const> = 24

-- Uniform block size: header (13 vec4 = 208B) + cubes (MAX_CUBES * 3 vec4 = 1152B)
local HEADER_SIZE <const> = 13 * 4 -- 13 vec4 = 52 floats
local CUBE_STRIDE <const> = 3 * 4  -- 3 vec4 = 12 floats per cube
local UNIFORM_FLOATS <const> = HEADER_SIZE + MAX_CUBES * CUBE_STRIDE
local UNIFORM_SIZE <const> = UNIFORM_FLOATS * 4 -- bytes

-- Resources
---@type render_target.ColorTarget[]
local rt = {} ---@diagnostic disable-line: missing-fields  -- ping-pong RGBA32F render targets
local read_idx, write_idx = 1, 2
local pt_shader = nil             -- path trace shader
local pt_pipeline = nil           -- path trace pipeline
local out_shader = nil            -- output (tonemap) shader
local out_pipeline = nil          -- output pipeline
local quad_vbuf = nil             -- fullscreen quad vertex buffer
---@type gpu.Sampler?
local tex_sampler = nil           -- texture sampler
local frame_count = 0
local accum_count = 0
local rt_width, rt_height = 0, 0
local prev_eye = nil
local prev_lookat = nil

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
    vec4 field_params;      // x=half_size, y=gakugaku, z=0, w=0
    vec4 sky_color;
    vec4 light_params;      // xyz=pos, w=radius
    vec4 light_color;       // xyz=color, w=intensity
    vec4 light2_params;     // xyz=pos, w=radius
    vec4 light3_params;     // xyz=pos, w=radius (dynamic light)
    vec4 light3_color;      // xyz=color, w=intensity (dynamic light)
    vec4 num_cubes;         // x=count, y=0, z=0, w=0
    vec4 cube_data[]] .. tostring(MAX_CUBES * 3) .. [[];
};

#define MAT_DIFF 0
#define MAT_GLOSSY 1
#define MAT_EMISSIVE 2

#define MAX_BOUNCES 4
#define EPS 0.01
#define INF 1e20
#define PI 3.14159265358979

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

    // Build orthonormal basis
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

    // Determine which face was hit
    if (t_enter > 0.0) {
        // Hit from outside
        if (tmin.x > tmin.y && tmin.x > tmin.z)
            normal = vec3(rd.x > 0.0 ? -1.0 : 1.0, 0.0, 0.0);
        else if (tmin.y > tmin.z)
            normal = vec3(0.0, rd.y > 0.0 ? -1.0 : 1.0, 0.0);
        else
            normal = vec3(0.0, 0.0, rd.z > 0.0 ? -1.0 : 1.0);
    } else {
        // Hit from inside
        if (tmax.x < tmax.y && tmax.x < tmax.z)
            normal = vec3(rd.x > 0.0 ? 1.0 : -1.0, 0.0, 0.0);
        else if (tmax.y < tmax.z)
            normal = vec3(0.0, rd.y > 0.0 ? 1.0 : -1.0, 0.0);
        else
            normal = vec3(0.0, 0.0, rd.z > 0.0 ? 1.0 : -1.0);
    }
    return true;
}

// ---- Intersection: Y-axis rotated box ----
bool intersect_rotated_box(vec3 ro, vec3 rd, vec3 center, float half_size,
                           float angle_y, out float t_hit, out vec3 normal) {
    // Transform ray into box local space (rotate around Y)
    float c = cos(-angle_y);
    float s = sin(-angle_y);

    vec3 local_ro = ro - center;
    local_ro = vec3(local_ro.x * c + local_ro.z * s, local_ro.y,
                    -local_ro.x * s + local_ro.z * c);

    vec3 local_rd = vec3(rd.x * c + rd.z * s, rd.y,
                         -rd.x * s + rd.z * c);

    vec3 box_min = vec3(-half_size);
    vec3 box_max = vec3(half_size);

    vec3 local_normal;
    if (!intersect_aabb(local_ro, local_rd, box_min, box_max, t_hit, local_normal))
        return false;

    // Transform normal back to world space
    float c2 = cos(angle_y);
    float s2 = sin(angle_y);
    normal = vec3(local_normal.x * c2 + local_normal.z * s2, local_normal.y,
                  -local_normal.x * s2 + local_normal.z * c2);
    return true;
}

// ---- Intersection: Ground plane (y=0) ----
bool intersect_plane(vec3 ro, vec3 rd, float field_half_size,
                     out float t_hit, out vec3 normal) {
    if (abs(rd.y) < 1e-6) return false;
    t_hit = -ro.y / rd.y;
    if (t_hit < 0.0) return false;
    vec3 p = ro + rd * t_hit;
    if (abs(p.x) > field_half_size || abs(p.z) > field_half_size) return false;
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
    float field_hs = field_params.x;

    // Ground plane
    float t_plane;
    vec3 n_plane;
    if (intersect_plane(ro, rd, field_hs, t_plane, n_plane) && t_plane < hit.t) {
        hit.t = t_plane;
        hit.normal = n_plane;
        vec3 p = ro + rd * t_plane;
        float grid = field_hs / 10.0;
        float checker = mod(floor(p.x / grid) + floor(p.z / grid), 2.0);
        hit.albedo = mix(vec3(0.25, 0.25, 0.28), vec3(0.45, 0.45, 0.50), checker);
        hit.material = MAT_DIFF;
        hit.roughness = 1.0;
        found = true;
    }

    // Cubes
    int count = int(num_cubes.x);
    for (int i = 0; i < count && i < ]] .. tostring(MAX_CUBES) .. [[; i++) {
        vec4 cs = cube_data[i * 3 + 0]; // center(xyz), half_size(w)
        vec4 cm = cube_data[i * 3 + 1]; // color(rgb), material(w)
        vec4 rot = cube_data[i * 3 + 2]; // angle_y(x), emission_strength(y)

        float t_box;
        vec3 n_box;
        if (intersect_rotated_box(ro, rd, cs.xyz, cs.w, rot.x, t_box, n_box)
            && t_box > EPS && t_box < hit.t) {
            hit.t = t_box;
            hit.normal = n_box;
            hit.albedo = cm.rgb;
            hit.material = int(cm.w);
            hit.roughness = 0.25;
            // emission controlled by rot.y (0=none, >0=glow strength)
            hit.emission = (rot.y > 0.0) ? cm.rgb * rot.y : vec3(0.0);
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

    // Random point on sphere
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

    // Shadow ray
    HitInfo shadow_hit;
    if (trace_scene(p + n * EPS, light_dir, shadow_hit) && shadow_hit.t < dist - EPS) {
        return vec3(0.0);
    }

    // Light contribution: color * intensity * (sphere_area / dist^2) * cos_theta / pdf
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
            // Sky gradient
            float sky_t = 0.5 * (rd.y + 1.0);
            vec3 sky = mix(vec3(0.02, 0.02, 0.06), sky_color.rgb, clamp(sky_t, 0.0, 1.0));
            radiance += throughput * sky;
            break;
        }

        vec3 p = ro + rd * hit.t;
        vec3 n = hit.normal;

        // Emissive contribution
        radiance += throughput * hit.emission;

        if (hit.material == MAT_DIFF) {
            // NEE: direct light sampling
            vec3 direct = sample_area_light(p, n, light_params, light_color, seed);
            direct += sample_area_light(p, n, light2_params, vec4(light_color.rgb * 0.3, light_color.w), seed);
            direct += sample_area_light(p, n, light3_params, light3_color, seed);
            radiance += throughput * hit.albedo * direct;

            // Indirect: cosine-weighted hemisphere
            throughput *= hit.albedo;
            rd = cosine_weighted_hemisphere(n, seed);
            ro = p + n * EPS;
        }
        else if (hit.material == MAT_GLOSSY) {
            // NEE for glossy
            vec3 direct = sample_area_light(p, n, light_params, light_color, seed);
            direct += sample_area_light(p, n, light2_params, vec4(light_color.rgb * 0.3, light_color.w), seed);
            direct += sample_area_light(p, n, light3_params, light3_color, seed);
            radiance += throughput * hit.albedo * direct * hit.roughness;

            // Glossy reflection: mix between mirror and diffuse
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
    float gaku = field_params.y;

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
    vec3 rd = normalize(camera_forward.xyz * fov_scale
                        + screen.x * camera_right.xyz
                        + screen.y * camera_up.xyz);

    // Gakugaku: perturb ray direction
    if (gaku > 0.0) {
        float perturb = rand(seed) * gaku * 0.003;
        rd = normalize(rd + vec3(rand(seed) - 0.5, rand(seed) - 0.5, rand(seed) - 0.5) * perturb);
    }

    // Path trace
    vec3 color = calculate_radiance(ro, rd, seed);

    // Accumulation blending
    vec3 prev = texture(sampler2D(prev_frame_tex, prev_frame_smp), vec2(uv.x, 1.0 - uv.y)).rgb;
    float blend = 1.0 / (accum + 1.0);
    vec3 accumulated = mix(prev, color, blend);

    frag_color = vec4(accumulated, 1.0);
}
@end

@program pathtracer pt_vs pt_fs
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
    vec4 params; // x=exposure, y=gamma, z=flip_y, w=0
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

@program pt_output out_vs out_fs
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
    -- Destroy existing
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
    log.info(string.format("PT render targets created: %dx%d", w, h))
end

function M.init()
    -- Compile shaders
    pt_shader = shader_mod.compile_full(pt_shader_source, "pathtracer", pt_shader_desc)
    if not pt_shader then
        log.error("Path trace shader compilation failed!")
        return false
    end

    out_shader = shader_mod.compile_full(out_shader_source, "pt_output", out_shader_desc)
    if not out_shader then
        log.error("Output shader compilation failed!")
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
        log.error("PT pipeline creation failed!")
        return false
    end

    out_pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = out_shader,
        layout = { attrs = { { format = gfx.VertexFormat.FLOAT2 } } },
        primitive_type = gfx.PrimitiveType.TRIANGLE_STRIP,
    }))
    if gfx.query_pipeline_state(out_pipeline) ~= gfx.ResourceState.VALID then
        log.error("Output pipeline creation failed!")
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

    log.info("Path tracer initialized")
    return true
end

function M.cleanup()
    for i = 1, 2 do
        ---@diagnostic disable-next-line: need-check-nil
        if rt[i] then rt[i]:destroy(); rt[i] = nil end
    end
    if tex_sampler then tex_sampler:destroy(); tex_sampler = nil end
    -- quad_vbuf, pipelines, shaders are raw sokol handles (GC'd or leaked - acceptable)
end

-- ============================================================
-- Scene data packing
-- ============================================================

--- Pack scene data into uniform float array
---@param cubes table[] Array of {pos=vec2, length=number, angle=number, color=integer, stat=integer}
---@param camera_eye vec3
---@param camera_lookat vec3
---@param gakugaku_val number
---@param game_state integer
---@return string packed Packed uniform data
function M.pack_scene(cubes, camera_eye, camera_lookat, gakugaku_val, game_state)
    local data = {}
    for i = 1, UNIFORM_FLOATS do data[i] = 0 end

    -- Camera vectors
    local forward = glm.normalize(camera_lookat - camera_eye)
    local right = glm.normalize(glm.cross(forward, glm.vec3(0, 1, 0)))
    local up = glm.cross(right, forward)

    -- FOV scale: tan(fov/2) for 45 degree FOV
    local fov_scale = 1.0 / math.tan(math.rad(45) * 0.5)

    -- camera_origin (vec4)
    data[1], data[2], data[3], data[4] = camera_eye.x, camera_eye.y, camera_eye.z, 0
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
    -- field_params (vec4)
    data[21] = const.FIELD_LF
    data[22] = gakugaku_val
    data[23] = 0
    data[24] = 0
    -- sky_color (vec4)
    data[25] = 0.12
    data[26] = 0.15
    data[27] = 0.35
    data[28] = 1.0
    -- light_params (vec4): main area light above field
    data[29] = 0
    data[30] = 800
    data[31] = 200
    data[32] = 150  -- radius
    -- light_color (vec4)
    data[33] = 1.0
    data[34] = 0.95
    data[35] = 0.85
    data[36] = 3.0  -- intensity
    -- light2_params (vec4): fill light from side
    data[37] = -500
    data[38] = 400
    data[39] = -300
    data[40] = 100  -- radius
    -- light3_params (vec4): dynamic player-following light
    data[41] = 0
    data[42] = 0
    data[43] = 0
    data[44] = 0    -- radius=0 means OFF by default
    -- light3_color (vec4)
    data[45] = 0
    data[46] = 0
    data[47] = 0
    data[48] = 0
    -- Activate light3 during GAME state: warm spotlight above player
    if game_state == const.GAME_STATE_GAME and #cubes > 0 then
        local p = cubes[1]  -- player is always first cube
        data[41] = p.pos.x
        data[42] = 200      -- height
        data[43] = p.pos.y  -- Z in 3D
        data[44] = 80       -- radius
        data[45] = 1.0      -- warm color R
        data[46] = 0.8      -- G
        data[47] = 0.5      -- B
        data[48] = 2.0      -- intensity
    end
    -- num_cubes (vec4)
    local num = math.min(#cubes, MAX_CUBES)
    data[49] = num
    data[50] = 0
    data[51] = 0
    data[52] = 0

    -- Cube data
    local base = HEADER_SIZE
    for i = 1, num do
        local cube = cubes[i]
        local idx = base + (i - 1) * CUBE_STRIDE

        -- center_and_half_size: pos.x, length(=y center), pos.y(=z), half_size
        data[idx + 1] = cube.pos.x
        data[idx + 2] = cube.length     -- Y center (cube sits on ground)
        data[idx + 3] = cube.pos.y      -- Z in 3D
        data[idx + 4] = cube.length     -- half size

        -- color_and_material
        local r, g, b = const.argb_to_rgb(cube.color)
        data[idx + 5] = r
        data[idx + 6] = g
        data[idx + 7] = b
        data[idx + 8] = cube.material or 1 -- MAT_GLOSSY default

        -- rotation: x=angle_y, y=emission_strength
        data[idx + 9] = -cube.angle     -- negate to match renderer.lua convention
        data[idx + 10] = cube.emission or 0  -- emission_strength
        data[idx + 11] = 0
        data[idx + 12] = 0
    end

    return util.pack_floats(data)
end

-- ============================================================
-- Rendering
-- ============================================================

--- Render path traced frame
---@param cubes table[] Scene cubes
---@param camera table Camera object
---@param gakugaku_val number
---@param game_state integer
function M.render(cubes, camera, gakugaku_val, game_state)
    if not pt_pipeline or not out_pipeline or not rt[1] or not tex_sampler then return end

    -- Check resize
    local w = math.max(app.width(), 1)
    local h = math.max(app.height(), 1)
    if w ~= rt_width or h ~= rt_height then
        create_render_targets(w, h)
    end

    -- Camera motion detection → reset accumulation
    local eye = camera:get_eye()
    local lookat = camera:get_lookat()
    local should_reset = false

    if prev_eye then
        local eye_dist = glm.length(eye - prev_eye)
        local lookat_dist = glm.length(lookat - prev_lookat)
        if eye_dist > 0.1 or lookat_dist > 0.1 then
            should_reset = true
        end
    else
        should_reset = true
    end
    prev_eye = eye
    prev_lookat = lookat

    -- Dynamic scene: cap accumulation
    local max_accum = (game_state == const.GAME_STATE_GAME) and 8 or 64
    if should_reset or accum_count >= max_accum then
        accum_count = 0
    end

    -- Pack scene uniforms
    local scene_data = M.pack_scene(cubes, eye, lookat, gakugaku_val, game_state)

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
    -- NOTE: We do NOT end this pass here - init.lua will draw UI on top then end it
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
        1.5, 2.2, 0, 0,    -- exposure, gamma, pad, pad
        0, 0, 0, 0,        -- pad
    })))
    gfx.draw(0, 4, 1)
    -- Pass left OPEN for UI overlay

    accum_count = accum_count + 1
    frame_count = frame_count + 1
end

return M
