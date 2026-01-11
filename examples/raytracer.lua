-- Raytracer example: GPU raytracing in fragment shader
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local stm = require("sokol.time")
local sdtx = require("sokol.debugtext")
local log = require("lib.log")
local shaderMod = require("lib.shader")
local util = require("lib.util")

---@type gfx.Shader?
local shader = nil
---@type gfx.Pipeline?
local pipeline = nil
---@type gfx.Buffer?
local vbuf = nil
local t = 0
local last_time = 0
local frame_count = 0
local fps = 0

-- Raytracing shader - renders spheres with reflections
local shader_source = [[
@vs vs
in vec2 pos;
out vec2 uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    uv = pos;
}
@end

@fs fs
in vec2 uv;
out vec4 frag_color;

layout(binding=0) uniform fs_params {
    float time;
    float aspect;
    float _pad0;
    float _pad1;
};

#define MAX_STEPS 100
#define MAX_DIST 100.0
#define SURF_DIST 0.001
#define MAX_BOUNCES 3

struct Material {
    vec3 color;
    float reflectivity;
};

// Signed distance functions
float sdSphere(vec3 p, vec3 center, float radius) {
    return length(p - center) - radius;
}

float sdPlane(vec3 p, float y) {
    return p.y - y;
}

float sdBox(vec3 p, vec3 center, vec3 size) {
    vec3 d = abs(p - center) - size;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Scene SDF with material output
float sceneSDF(vec3 p, out Material mat) {
    float d = MAX_DIST;

    // Ground plane
    float plane = sdPlane(p, -1.0);
    if (plane < d) {
        d = plane;
        float checker = mod(floor(p.x) + floor(p.z), 2.0);
        mat.color = mix(vec3(0.2), vec3(0.8), checker);
        mat.reflectivity = 0.3;
    }

    // Animated spheres
    float t = time * 0.5;

    // Center sphere (metallic)
    vec3 c1 = vec3(0.0, sin(t) * 0.3, 0.0);
    float s1 = sdSphere(p, c1, 0.8);
    if (s1 < d) {
        d = s1;
        mat.color = vec3(0.9, 0.9, 1.0);
        mat.reflectivity = 0.9;
    }

    // Orbiting spheres
    for (int i = 0; i < 5; i++) {
        float angle = t + float(i) * 1.2566;
        float radius = 2.0 + sin(t * 0.7 + float(i)) * 0.3;
        vec3 center = vec3(cos(angle) * radius, sin(t * 2.0 + float(i)) * 0.5, sin(angle) * radius);
        float sphere = sdSphere(p, center, 0.3 + sin(t + float(i)) * 0.1);
        if (sphere < d) {
            d = sphere;
            mat.color = vec3(
                sin(float(i) * 1.1) * 0.5 + 0.5,
                sin(float(i) * 1.7 + 2.0) * 0.5 + 0.5,
                sin(float(i) * 2.3 + 4.0) * 0.5 + 0.5
            );
            mat.reflectivity = 0.5;
        }
    }

    // Rotating box
    vec3 boxCenter = vec3(sin(t * 0.3) * 3.0, 0.0, cos(t * 0.3) * 3.0);
    float box = sdBox(p, boxCenter, vec3(0.4));
    if (box < d) {
        d = box;
        mat.color = vec3(1.0, 0.3, 0.1);
        mat.reflectivity = 0.2;
    }

    return d;
}

// Calculate normal
vec3 calcNormal(vec3 p) {
    Material m;
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        sceneSDF(p + e.xyy, m) - sceneSDF(p - e.xyy, m),
        sceneSDF(p + e.yxy, m) - sceneSDF(p - e.yxy, m),
        sceneSDF(p + e.yyx, m) - sceneSDF(p - e.yyx, m)
    ));
}

// Raymarching
float rayMarch(vec3 ro, vec3 rd, out Material mat) {
    float d = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * d;
        float ds = sceneSDF(p, mat);
        d += ds;
        if (ds < SURF_DIST || d > MAX_DIST) break;
    }
    return d;
}

// Soft shadows
float softShadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t = mint;
    Material m;
    for (int i = 0; i < 32; i++) {
        float h = sceneSDF(ro + rd * t, m);
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.1);
        if (h < 0.001 || t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

// Main lighting
vec3 shade(vec3 p, vec3 rd, Material mat) {
    vec3 n = calcNormal(p);

    // Multiple lights
    vec3 lightPos1 = vec3(5.0, 5.0, -5.0);
    vec3 lightPos2 = vec3(-5.0, 3.0, 5.0);
    vec3 lightCol1 = vec3(1.0, 0.9, 0.8);
    vec3 lightCol2 = vec3(0.3, 0.4, 0.8);

    vec3 l1 = normalize(lightPos1 - p);
    vec3 l2 = normalize(lightPos2 - p);

    // Diffuse
    float diff1 = max(dot(n, l1), 0.0);
    float diff2 = max(dot(n, l2), 0.0);

    // Specular
    vec3 v = -rd;
    vec3 h1 = normalize(l1 + v);
    vec3 h2 = normalize(l2 + v);
    float spec1 = pow(max(dot(n, h1), 0.0), 32.0);
    float spec2 = pow(max(dot(n, h2), 0.0), 32.0);

    // Shadows
    float shadow1 = softShadow(p + n * 0.01, l1, 0.1, 10.0, 16.0);
    float shadow2 = softShadow(p + n * 0.01, l2, 0.1, 10.0, 16.0);

    // Ambient
    vec3 ambient = vec3(0.1, 0.1, 0.15);

    vec3 color = mat.color * ambient;
    color += mat.color * lightCol1 * diff1 * shadow1;
    color += mat.color * lightCol2 * diff2 * shadow2;
    color += lightCol1 * spec1 * shadow1 * mat.reflectivity;
    color += lightCol2 * spec2 * shadow2 * mat.reflectivity;

    return color;
}

void main() {
    vec2 p = uv;
    p.x *= aspect;

    // Camera
    float camDist = 6.0;
    float camAngle = time * 0.2;
    vec3 ro = vec3(sin(camAngle) * camDist, 2.0 + sin(time * 0.3), cos(camAngle) * camDist);
    vec3 look_at = vec3(0.0, 0.0, 0.0);

    vec3 forward = normalize(look_at - ro);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);

    vec3 rd = normalize(forward + p.x * right + p.y * up);

    vec3 color = vec3(0.0);
    vec3 throughput = vec3(1.0);

    // Raytracing with reflections
    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {
        Material mat;
        float d = rayMarch(ro, rd, mat);

        if (d < MAX_DIST) {
            vec3 hitPos = ro + rd * d;
            vec3 n = calcNormal(hitPos);

            // Add direct lighting
            color += throughput * shade(hitPos, rd, mat) * (1.0 - mat.reflectivity);

            // Reflection
            if (mat.reflectivity > 0.01) {
                throughput *= mat.reflectivity * mat.color;
                ro = hitPos + n * 0.01;
                rd = reflect(rd, n);
            } else {
                break;
            }
        } else {
            // Sky gradient
            float t = 0.5 * (rd.y + 1.0);
            vec3 sky = mix(vec3(0.5, 0.7, 1.0), vec3(0.1, 0.2, 0.4), t);
            color += throughput * sky;
            break;
        }
    }

    // Tone mapping and gamma
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));

    frag_color = vec4(color, 1.0);
}
@end

@program raytracer vs fs
]]

function init()
    log.log("Raytracer init starting...")

    stm.setup()
    sdtx.setup(sdtx.Desc({ fonts = { sdtx.font_c64() } }))
    last_time = stm.now()

    shader = shaderMod.compile(shader_source, "raytracer", {
        { size = 16, stage = gfx.ShaderStage.FRAGMENT }
    })
    if not shader then
        log.log("Shader compilation failed!")
        return
    end
    log.log("Shader compiled OK")

    pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 },
            }
        },
        primitive_type = gfx.PrimitiveType.TRIANGLE_STRIP,
    }))

    if gfx.query_pipeline_state(pipeline) ~= gfx.ResourceState.VALID then
        log.log("Pipeline creation failed!")
        return
    end

    -- Fullscreen quad
    vbuf = gfx.make_buffer(gfx.BufferDesc({
        data = util.pack_floats({ -1, -1, 1, -1, -1, 1, 1, 1 }),
        usage = { vertex_buffer = true, immutable = true }
    }))
end

function frame()
    t = t + 1.0 / 60.0
    if not pipeline or not vbuf then return end

    -- Calculate FPS
    frame_count = frame_count + 1
    local now = stm.now()
    local elapsed = stm.ms(stm.diff(now, last_time))
    if elapsed >= 1000 then
        fps = frame_count * 1000 / elapsed
        frame_count = 0
        last_time = now
    end

    local w = 800
    local h = 600

    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{ load_action = gfx.LoadAction.CLEAR, clear_value = { r = 0, g = 0, b = 0, a = 1 } }}
        }),
        swapchain = glue.swapchain()
    }))

    gfx.apply_pipeline(pipeline)
    gfx.apply_bindings(gfx.Bindings({ vertex_buffers = { vbuf } }))

    -- Pass uniforms (time, aspect ratio)
    gfx.apply_uniforms(0, gfx.Range(util.pack_floats({ t, w / h, 0, 0 })))

    gfx.draw(0, 4, 1)

    -- Draw FPS
    sdtx.origin(0.5, 0.5)
    sdtx.color3f(1, 1, 0)
    sdtx.puts(string.format("FPS: %.1f", fps))
    sdtx.draw()

    gfx.end_pass()
    gfx.commit()
end

function cleanup()
end

function event(ev)
    if ev.type == app.EventType.KEY_DOWN and ev.key_code == app.Keycode.Q then
        app.quit()
    end
end
