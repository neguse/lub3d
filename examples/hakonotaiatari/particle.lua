-- hakonotaiatari particle system

local glm = require("lib.glm")
local gl = require("sokol.gl")
local const = require("examples.hakonotaiatari.const")

local M = {}

-- Particle pool
local particles = {}
local MAX_PARTICLES = 2000

-- Particle structure
local function new_particle()
    return {
        pos = glm.vec3(0, 0, 0),
        velo = glm.vec3(0, 0, 0),
        acc = glm.vec3(0, 0, 0),
        color = 0xffffffff,
        tick = 0,
        max_tick = 60,
        size = 2,
        alive = false,
    }
end

-- Initialize particle pool
function M.init()
    particles = {}
    for i = 1, MAX_PARTICLES do
        particles[i] = new_particle()
    end
end

-- Get a free particle from pool
local function get_particle()
    for i = 1, MAX_PARTICLES do
        if not particles[i].alive then
            return particles[i]
        end
    end
    return nil
end

-- Emit particles in a cone pattern
-- amount: number of particles
-- center: vec3 position
-- y_angle_center, y_angle_range: horizontal direction
-- xz_angle_center, xz_angle_range: vertical direction
-- velo_center, velo_range: speed
-- tick_center, tick_range: lifetime
-- acc_center, acc_range: acceleration (vec3)
-- color: ARGB color
function M.emit_cone(amount, center, y_angle_center, y_angle_range,
                     xz_angle_center, xz_angle_range,
                     velo_center, velo_range,
                     tick_center, tick_range,
                     acc_center, acc_range, color)
    for i = 1, amount do
        local p = get_particle()
        if not p then break end

        local y_angle = y_angle_center + (math.random() * 2 - 1) * y_angle_range
        local xz_angle = xz_angle_center + (math.random() * 2 - 1) * xz_angle_range
        local velo_len = velo_center + (math.random() * 2 - 1) * velo_range

        local velo_xz = math.cos(xz_angle) * velo_len
        local velo_y = math.sin(xz_angle) * velo_len

        p.pos = glm.vec3(center.x, center.y, center.z)
        p.velo = glm.vec3(
            math.cos(y_angle) * velo_xz,
            velo_y,
            math.sin(y_angle) * velo_xz
        )
        p.acc = acc_center + glm.vec3(
            (math.random() * 2 - 1) * acc_range.x,
            (math.random() * 2 - 1) * acc_range.y,
            (math.random() * 2 - 1) * acc_range.z
        )
        p.color = color
        p.tick = 0
        p.max_tick = tick_center + math.floor((math.random() * 2 - 1) * tick_range)
        p.size = 2
        p.alive = true
    end
end

-- Update all particles
function M.update(dt)
    for i = 1, MAX_PARTICLES do
        local p = particles[i]
        if p.alive then
            p.tick = p.tick + 1
            p.velo = p.velo + p.acc * dt
            p.pos = p.pos + p.velo * dt

            if p.tick >= p.max_tick then
                p.alive = false
            end
        end
    end
end

-- Render all particles as small crosses
function M.render()
    local SIZE = 2.0
    gl.begin_lines()
    for i = 1, MAX_PARTICLES do
        local p = particles[i]
        if p.alive then
            local r, g, b = const.argb_to_rgb(p.color)
            -- Fade out near end of life
            local alpha = 1.0 - (p.tick / p.max_tick)
            local cr, cg, cb = r * alpha, g * alpha, b * alpha
            local x, y, z = p.pos.x, p.pos.y, p.pos.z
            -- Draw cross
            gl.v3f_c3f(x - SIZE, y, z, cr, cg, cb)
            gl.v3f_c3f(x + SIZE, y, z, cr, cg, cb)
            gl.v3f_c3f(x, y - SIZE, z, cr, cg, cb)
            gl.v3f_c3f(x, y + SIZE, z, cr, cg, cb)
            gl.v3f_c3f(x, y, z - SIZE, cr, cg, cb)
            gl.v3f_c3f(x, y, z + SIZE, cr, cg, cb)
        end
    end
    gl["end"]()
end

-- Clear all particles
function M.clear()
    for i = 1, MAX_PARTICLES do
        particles[i].alive = false
    end
end

return M
