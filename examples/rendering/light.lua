-- examples/rendering/light.lua
-- Light module: p3d_LightSourceParameters equivalent (without shadow)
local glm = require("lib.glm")

--[[
p3d_LightSourceParameters structure (from base.frag):

uniform struct p3d_LightSourceParameters {
    vec4 color;
    vec4 ambient;
    vec4 diffuse;
    vec4 specular;
    vec4 position;
    vec3 spotDirection;
    float spotExponent;
    float spotCutoff;
    float spotCosCutoff;
    float constantAttenuation;
    float linearAttenuation;
    float quadraticAttenuation;
    vec3 attenuation;
    // sampler2DShadow shadowMap;  -- excluded
    // mat4 shadowViewMatrix;      -- excluded
} p3d_LightSource[NUMBER_OF_LIGHTS];

For sokol uniform block (std140 layout), we pack as:
    vec4 color;           // 16 bytes
    vec4 ambient;         // 16 bytes
    vec4 diffuse;         // 16 bytes
    vec4 specular;        // 16 bytes
    vec4 position;        // 16 bytes (w: 0=directional, 1=positional)
    vec4 spot_direction;  // 16 bytes (xyz=direction, w=exponent)
    vec4 spot_params;     // 16 bytes (x=cutoff, y=cosCutoff, zw=pad)
    vec4 attenuation;     // 16 bytes (x=constant, y=linear, z=quadratic, w=pad)
Total: 128 bytes per light
]]

---@class rendering.LightSourceParameters
---@field color vec4
---@field ambient vec4
---@field diffuse vec4
---@field specular vec4
---@field position vec4 xyz=position, w=0 for directional, w=1 for positional
---@field spot_direction vec4 xyz=direction, w=spotExponent
---@field spot_params vec4 x=spotCutoff (radians), y=spotCosCutoff, zw=unused
---@field attenuation vec4 x=constant, y=linear, z=quadratic, w=unused

---@class rendering.Light
local M = {}

M.NUMBER_OF_LIGHTS = 4

---p3d_LightModel.ambient
M.light_model_ambient = glm.vec4(0.388, 0.356, 0.447, 1.0)

---Light sources array
---@type rendering.LightSourceParameters[]
M.sources = {}

-- Animation state
M.sun_pitch = 270  -- degrees, 270 = midday, 90 = midnight
M.animation_speed = 10  -- degrees per second
M.animate_enabled = true

-- Color constants (from tutorial)
local sunlight_color0 = glm.vec4(0.612, 0.365, 0.306, 1)  -- sunrise/sunset
local sunlight_color1 = glm.vec4(0.765, 0.573, 0.400, 1)  -- midday
local moonlight_color0 = glm.vec4(0.247, 0.384, 0.404, 1)
local moonlight_color1 = glm.vec4(0.392, 0.537, 0.571, 1)
local window_light_color = glm.vec4(0.765, 0.573, 0.400, 1)

---Mix two colors
---@param a vec4
---@param b vec4
---@param t number 0-1
---@return vec4
local function mix_color(a, b, t)
    return glm.vec4(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
        a.w + (b.w - a.w) * t
    )
end

---Clamp value
local function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

---Create default light parameters (OpenGL defaults)
---@return rendering.LightSourceParameters
local function default_params()
    return {
        color = glm.vec4(0, 0, 0, 1),
        ambient = glm.vec4(0, 0, 0, 1),
        diffuse = glm.vec4(0, 0, 0, 1),
        specular = glm.vec4(0, 0, 0, 1),
        position = glm.vec4(0, 0, 1, 0),  -- default directional from +Z
        spot_direction = glm.vec4(0, 0, -1, 0),  -- exponent=0
        spot_params = glm.vec4(math.pi, -1, 0, 0),  -- cutoff=180deg (no spotlight), cosCutoff=-1
        attenuation = glm.vec4(1, 0, 0, 0),  -- constant=1, linear=0, quadratic=0
    }
end

---Create a DirectionalLight (like Panda3D DirectionalLight)
---@param color vec4|vec3 Light color
---@param direction? vec3 Light direction (default: from node transform)
---@return rendering.LightSourceParameters
function M.directional_light(color, direction)
    local c = glm.vec4(color.x, color.y, color.z, color.w or 1)
    local dir = direction and direction:normalize() or glm.vec3(0, 0, -1)

    local params = default_params()
    params.color = c
    -- DirectionalLight: diffuse/specular = color, ambient = black
    params.diffuse = glm.vec4(c.x, c.y, c.z, c.w)
    params.specular = glm.vec4(c.x, c.y, c.z, c.w)
    -- position.w = 0 means directional, xyz is direction (negated for "from" direction)
    params.position = glm.vec4(-dir.x, -dir.y, -dir.z, 0)
    return params
end

---Create a PointLight (like Panda3D PointLight)
---@param color vec4|vec3 Light color
---@param position vec3 World position
---@param attenuation? vec3 (constant, linear, quadratic), default (1,0,0)
---@return rendering.LightSourceParameters
function M.point_light(color, position, attenuation)
    local c = glm.vec4(color.x, color.y, color.z, color.w or 1)
    local atten = attenuation or glm.vec3(1, 0, 0)

    local params = default_params()
    params.color = c
    params.diffuse = glm.vec4(c.x, c.y, c.z, c.w)
    params.specular = glm.vec4(c.x, c.y, c.z, c.w)
    -- position.w = 1 means positional
    params.position = glm.vec4(position.x, position.y, position.z, 1)
    params.attenuation = glm.vec4(atten.x, atten.y, atten.z, 0)
    return params
end

---Create a Spotlight (like Panda3D Spotlight)
---@param color vec4|vec3 Light color
---@param position vec3 World position
---@param direction vec3 Spot direction
---@param exponent number Spot exponent (falloff)
---@param cutoff number Cutoff angle in radians (not degrees!)
---@param attenuation? vec3 (constant, linear, quadratic), default (1,0,0)
---@return rendering.LightSourceParameters
function M.spotlight(color, position, direction, exponent, cutoff, attenuation)
    local c = glm.vec4(color.x, color.y, color.z, color.w or 1)
    local dir = direction:normalize()
    local atten = attenuation or glm.vec3(1, 0, 0)

    local params = default_params()
    params.color = c
    params.diffuse = glm.vec4(c.x, c.y, c.z, c.w)
    params.specular = glm.vec4(c.x, c.y, c.z, c.w)
    -- position.w = 1 means positional
    params.position = glm.vec4(position.x, position.y, position.z, 1)
    params.spot_direction = glm.vec4(dir.x, dir.y, dir.z, exponent)
    params.spot_params = glm.vec4(cutoff, math.cos(cutoff), 0, 0)
    params.attenuation = glm.vec4(atten.x, atten.y, atten.z, 0)
    return params
end

---Transform light to view space
---@param light rendering.LightSourceParameters
---@param view_matrix mat4
---@return rendering.LightSourceParameters
local function to_view_space(light, view_matrix)
    local is_directional = light.position.w == 0

    local vs = {}
    vs.color = light.color
    vs.ambient = light.ambient
    vs.diffuse = light.diffuse
    vs.specular = light.specular

    if is_directional then
        -- Transform direction (w=0)
        local dir = view_matrix * glm.vec4(light.position.x, light.position.y, light.position.z, 0)
        vs.position = glm.vec4(dir.x, dir.y, dir.z, 0)
    else
        -- Transform position (w=1)
        local pos = view_matrix * glm.vec4(light.position.x, light.position.y, light.position.z, 1)
        vs.position = glm.vec4(pos.x, pos.y, pos.z, 1)
    end

    -- Transform spot direction if spotlight
    if light.spot_params.x < math.pi then
        local dir = view_matrix * glm.vec4(light.spot_direction.x, light.spot_direction.y, light.spot_direction.z, 0)
        vs.spot_direction = glm.vec4(dir.x, dir.y, dir.z, light.spot_direction.w)
    else
        vs.spot_direction = light.spot_direction
    end

    vs.spot_params = light.spot_params
    vs.attenuation = light.attenuation

    return vs
end

---Pack a single light to binary (128 bytes = 8 * vec4)
---@param light rendering.LightSourceParameters
---@return string
local function pack_light(light)
    return string.pack("ffffffff ffffffff ffffffff ffffffff",
        -- color (vec4)
        light.color.x, light.color.y, light.color.z, light.color.w,
        -- ambient (vec4)
        light.ambient.x, light.ambient.y, light.ambient.z, light.ambient.w,
        -- diffuse (vec4)
        light.diffuse.x, light.diffuse.y, light.diffuse.z, light.diffuse.w,
        -- specular (vec4)
        light.specular.x, light.specular.y, light.specular.z, light.specular.w,
        -- position (vec4)
        light.position.x, light.position.y, light.position.z, light.position.w,
        -- spot_direction (vec4) xyz=dir, w=exponent
        light.spot_direction.x, light.spot_direction.y, light.spot_direction.z, light.spot_direction.w,
        -- spot_params (vec4) x=cutoff, y=cosCutoff
        light.spot_params.x, light.spot_params.y, light.spot_params.z, light.spot_params.w,
        -- attenuation (vec4) x=constant, y=linear, z=quadratic
        light.attenuation.x, light.attenuation.y, light.attenuation.z, light.attenuation.w
    )
end

---Pack empty light (128 bytes of zeros, but with valid defaults)
---@return string
local function pack_empty_light()
    local empty = default_params()
    return pack_light(empty)
end

-- Gamma value
M.gamma = 2.2

-- Blinn-Phong toggle (true = Blinn-Phong, false = Phong)
M.blinn_phong_enabled = true

-- Fresnel effect toggle and max power
M.fresnel_enabled = true
M.max_fresnel_power = 5.0  -- specular_map.b * this value

-- Rim light toggle
M.rim_light_enabled = true

-- Debug mode (0=off, 1=fresnel, 2=normal, 3=specular)
M.debug_mode = 0

---Pack all uniforms for lighting shader
---Layout: Light[NUMBER_OF_LIGHTS] (512 bytes) + light_model_ambient (16 bytes) + params (16 bytes) + flags (16 bytes) + debug (16 bytes)
---Total: 576 bytes
---@param view_matrix mat4
---@return string
function M.pack_uniforms(view_matrix)
    local parts = {}

    -- Pack lights
    for i = 1, M.NUMBER_OF_LIGHTS do
        local light = M.sources[i]
        if light then
            local vs_light = to_view_space(light, view_matrix)
            parts[i] = pack_light(vs_light)
        else
            parts[i] = pack_empty_light()
        end
    end

    -- p3d_LightModel.ambient (vec4)
    parts[M.NUMBER_OF_LIGHTS + 1] = string.pack("ffff",
        M.light_model_ambient.x, M.light_model_ambient.y, M.light_model_ambient.z, M.light_model_ambient.w
    )

    -- num_lights (int), gamma, gamma_rec, pad
    parts[M.NUMBER_OF_LIGHTS + 2] = string.pack("ifff",
        #M.sources, M.gamma, 1.0 / M.gamma, 0
    )

    -- blinn_phong (int), fresnel (int), max_fresnel_power (float), rim_light (int)
    parts[M.NUMBER_OF_LIGHTS + 3] = string.pack("iifi",
        M.blinn_phong_enabled and 1 or 0,
        M.fresnel_enabled and 1 or 0,
        M.max_fresnel_power,
        M.rim_light_enabled and 1 or 0
    )

    -- debug_mode (int), pad, pad, pad
    parts[M.NUMBER_OF_LIGHTS + 4] = string.pack("iiii",
        M.debug_mode,
        0, 0, 0
    )

    return table.concat(parts)
end

---Get uniform size in bytes
---@return integer
function M.uniform_size()
    -- Light[4] * 128 + ambient(16) + params(16) + flags(16) + debug(16) = 576
    return M.NUMBER_OF_LIGHTS * 128 + 16 + 16 + 16 + 16
end

---Calculate sun direction from pitch angle (like tutorial's pivot rotation)
---@param pitch number Pitch angle in degrees
---@return vec3 direction Direction vector (normalized)
local function sun_direction_from_pitch(pitch)
    local rad = math.rad(pitch)
    -- Pivot at (0, 0.5, 15), light at (0, -17.5, 0) relative
    -- HPR (135, pitch, 0) rotation
    -- Simplified: rotating around X axis mostly
    local y = -math.cos(rad)
    local z = math.sin(rad)
    -- Add some horizontal component based on HPR heading 135
    local h_rad = math.rad(135)
    local x = -math.sin(h_rad) * math.cos(rad) * 0.5
    return glm.vec3(x, y, z):normalize()
end

---Setup lights similar to generateLights() in tutorial
function M.setup_default()
    M.sources = {}
    M.sun_pitch = 270  -- midday

    -- Global ambient (from tutorial)
    M.light_model_ambient = glm.vec4(0.388, 0.356, 0.447, 1.0)

    -- Sunlight (DirectionalLight) - will be updated by animate()
    table.insert(M.sources, M.directional_light(sunlight_color1, glm.vec3(1, -1, 1)))

    -- Moonlight (DirectionalLight) - 180 degrees offset from sun
    table.insert(M.sources, M.directional_light(moonlight_color1, glm.vec3(-1, 1, -1)))

    -- Window spotlight (from generateWindowLight)
    -- set_exponent(5), set_attenuation(1, 0.008, 0), fov=140
    local cutoff = math.rad(70)  -- fov/2 = 140/2 = 70
    table.insert(M.sources, M.spotlight(
        window_light_color,
        glm.vec3(1.5, 2.49, 7.9),  -- position
        glm.vec3(0, -1, 0),        -- direction (hpr=180,0,0 → -Y)
        5,                          -- exponent
        cutoff,
        glm.vec3(1, 0.008, 0)      -- attenuation
    ))

    -- Run initial animation to set correct colors
    M.animate(0)
end

---Animate lights (like animateLights in tutorial)
---@param dt number Delta time in seconds
function M.animate(dt)
    if not M.animate_enabled and dt > 0 then
        return
    end

    -- Update sun pitch
    M.sun_pitch = M.sun_pitch + M.animation_speed * dt
    if M.sun_pitch > 360 then M.sun_pitch = M.sun_pitch - 360 end
    if M.sun_pitch < 0 then M.sun_pitch = M.sun_pitch + 360 end

    local p = M.sun_pitch
    local p_rad = math.rad(p)

    -- Calculate mix factor (from tutorial line 2219)
    -- mixFactor = 1.0 - (sin(p) / 2.0 + 0.5)
    local mix_factor = 1.0 - (math.sin(p_rad) / 2.0 + 0.5)

    -- Calculate light colors (from tutorial lines 2221-2223)
    local sunlight_color = mix_color(sunlight_color0, sunlight_color1, mix_factor)
    local moonlight_color = mix_color(moonlight_color1, sunlight_color0, mix_factor)
    local light_color = mix_color(moonlight_color, sunlight_color, mix_factor)

    -- Calculate intensity magnitudes (from tutorial lines 2225-2226)
    local day_magnitude = clamp(-math.sin(p_rad), 0.0, 1.0)
    local night_magnitude = clamp(math.sin(p_rad), 0.0, 1.0)

    -- Update sun direction and color
    local sun_dir = sun_direction_from_pitch(p)
    local sun = M.sources[1]
    if sun then
        sun.position = glm.vec4(-sun_dir.x, -sun_dir.y, -sun_dir.z, 0)
        local c = glm.vec4(
            light_color.x * day_magnitude,
            light_color.y * day_magnitude,
            light_color.z * day_magnitude,
            1.0
        )
        sun.color = c
        sun.diffuse = c
        sun.specular = c
    end

    -- Update moon direction and color (180 degrees offset)
    local moon_dir = sun_direction_from_pitch(p - 180)
    local moon = M.sources[2]
    if moon then
        moon.position = glm.vec4(-moon_dir.x, -moon_dir.y, -moon_dir.z, 0)
        local c = glm.vec4(
            light_color.x * night_magnitude,
            light_color.y * night_magnitude,
            light_color.z * night_magnitude,
            1.0
        )
        moon.color = c
        moon.diffuse = c
        moon.specular = c
    end

    -- Update window light (brighter at night)
    local window_magnitude = night_magnitude ^ 0.4
    local window = M.sources[3]
    if window then
        local c = glm.vec4(
            window_light_color.x * window_magnitude,
            window_light_color.y * window_magnitude,
            window_light_color.z * window_magnitude,
            1.0
        )
        window.color = c
        window.diffuse = c
        window.specular = c
    end
end

---Set time of day
---@param time string "midday" | "midnight" | number (degrees)
function M.set_time(time)
    if time == "midday" then
        M.sun_pitch = 270
    elseif time == "midnight" then
        M.sun_pitch = 90
    elseif type(time) == "number" then
        M.sun_pitch = time
    end
    M.animate(0)
end

-- Initialize
M.setup_default()

return M
