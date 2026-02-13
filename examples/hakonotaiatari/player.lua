-- hakonotaiatari player
-- Player cube with dash mechanics

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local Cube = require("examples.hakonotaiatari.cube")
local input = require("examples.hakonotaiatari.input")

---@class Player : Cube
---@field tick integer
---@field dash_len number
---@field dash_f number
---@field power number
local Player = setmetatable({}, { __index = Cube })
Player.__index = Player

-- Helper: polar to cartesian
local function pcs(radius, angle)
    return glm.Vec2(math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Create new player
function Player.new()
    local self = setmetatable(Cube.new(), Player)
    self.tick = 0
    self.dash_len = 0
    self.dash_f = 0
    self.power = 0
    return self
end

-- Initialize player
function Player:init()
    Cube.init(self, const.C_TYPE_PLAYER, glm.Vec2(0, 0), 0, 0, const.P_COL_NORMAL, const.P_LEN, 0)
    self.stat = const.P_ST_MUTEKI
    self.tick = 0
    self.power = 0
    self.life = const.P_LIFE_INIT
    self.coll_enable = false
end

-- Calculate dash duration based on power
function Player:calc_dash_f()
    if self.power < const.P_DASH_MIN_POW then
        return 0
    else
        return const.P_POW_GETA + const.P_POW_COEFF * (self.power - const.P_DASH_MIN_POW)
    end
end

-- Add power (clamped to 0..P_POW_MAX)
function Player:add_power(d)
    self.power = glm.Clamp(self.power + d, 0, const.P_POW_MAX)
end

-- Update player
-- target_pos: vec2 - mouse target position on XZ plane
-- camera: Camera object to update
-- audio: audio module for sound effects
function Player:update(dt, target_pos, camera, audio)
    self.tick = self.tick + 1
    local dv = target_pos - self.pos
    local dva = math.atan(dv.y, dv.x)
    local dvl = glm.Length(dv)
    local prev_stat = self.stat

    if self.stat == const.P_ST_MUTEKI then
        if self.tick > const.P_MUTEKI_F then
            self.stat = const.P_ST_NORMAL
            self.coll_enable = true
        end
        -- Intentional fall-through to NORMAL for movement
        self.length = self.length + (const.P_LEN - self.length) * 0.01
        self.angle = dva
        self.velo = math.min(dvl * const.P_VR, const.P_VL)
        self:add_power(1)

        if self.power == const.P_DASH_MIN_POW + 1 then
            if audio then audio.play(const.WAVE_POWERFULL_INDEX) end
        end

        if const.P_DASH_MIN_POW < self.power and input.is_button_down() then
            self.stat = const.P_ST_DASH
            self.velo = const.P_DASH_V
            self.color = const.P_COL_DASH
            self.coll_enable = true
            self.dash_len = self.length + const.P_DASH_LEN
            self.dash_f = self:calc_dash_f()
            self:add_power(-const.P_DASH_USE_POW)
            if audio then audio.play(const.WAVE_SUBERI_INDEX) end
        end
    elseif self.stat == const.P_ST_NORMAL then
        self.length = self.length + (const.P_LEN - self.length) * 0.01
        self.angle = dva
        self.velo = math.min(dvl * const.P_VR, const.P_VL)
        self:add_power(1)

        if self.power == const.P_DASH_MIN_POW + 1 then
            if audio then audio.play(const.WAVE_POWERFULL_INDEX) end
        end

        if const.P_DASH_MIN_POW < self.power and input.is_button_down() then
            self.stat = const.P_ST_DASH
            self.velo = const.P_DASH_V
            self.color = const.P_COL_DASH
            self.coll_enable = true
            self.dash_len = self.length + const.P_DASH_LEN
            self.dash_f = self:calc_dash_f()
            self:add_power(-const.P_DASH_USE_POW)
            if audio then audio.play(const.WAVE_SUBERI_INDEX) end
        end
    elseif self.stat == const.P_ST_DASH then
        self.length = self.length + (self.dash_len - self.length) * 0.1
        self.velo = const.P_DASH_V

        if self.tick > self.dash_f then
            self.stat = const.P_ST_NORMAL
            self.color = const.P_COL_NORMAL
            self.coll_enable = true
            if self:calc_dash_f() > 0 then
                if audio then audio.play(const.WAVE_POWERFULL_INDEX) end
            end
        end
        -- TODO: emit dash particles
    elseif self.stat == const.P_ST_FUTTOBI or self.stat == const.P_ST_FUTTOBI_NOMUTEKI then
        self.velo = const.P_FUTTOBI_V

        if self.tick > const.P_FUTTOBI_F then
            if self.life > 0 then
                if self.stat == const.P_ST_FUTTOBI then
                    self.stat = const.P_ST_MUTEKI
                    self.tick = 0
                    self.coll_enable = false
                else
                    -- P_ST_FUTTOBI_NOMUTEKI
                    self.stat = const.P_ST_MUTEKI
                    self.tick = const.P_MUTEKI_F - const.P_NOMUTEKI_F
                    self.coll_enable = false
                end
                self.color = const.P_COL_NORMAL
            else
                if audio then audio.play(const.WAVE_FALL_INDEX) end
                self.stat = const.P_ST_FADEOUT
                if camera then camera:set_enable_rotate(true) end
                self.coll_enable = false
            end
        end
    elseif self.stat == const.P_ST_FADEOUT or self.stat == const.P_ST_DEAD then
        self.length = self.length + (-self.length * 0.03)
        if self.tick > const.P_FADEOUT_F and self.stat == const.P_ST_FADEOUT then
            self.stat = const.P_ST_DEAD
        end
    end

    -- Update camera based on state
    if camera then
        if self.stat == const.P_ST_DASH then
            camera:set_behind(const.CAM_BEHIND_HIGH_DASH, const.CAM_BEHIND_BACK_DASH)
        elseif self.stat == const.P_ST_DEAD then
            camera:set_behind(const.CAM_BEHIND_HIGH_DEAD, const.CAM_BEHIND_BACK_DEAD)
        else
            camera:set_behind(const.CAM_BEHIND_HIGH, const.CAM_BEHIND_BACK)
        end
    end

    -- Reset tick on state change (except MUTEKI)
    if prev_stat ~= self.stat and self.stat ~= const.P_ST_MUTEKI then
        self.tick = 0
    end

    -- Base cube update
    Cube.update(self, dt)

    -- Update camera lookat
    if camera then
        if self.stat ~= const.P_ST_DEAD then
            local la = self.pos + pcs(dvl * 0.05, dva)
            camera:set_lookat(glm.Vec3(
                glm.Clamp(la.x, -const.FIELD_Lf, const.FIELD_Lf),
                0,
                glm.Clamp(la.y, -const.FIELD_Lf, const.FIELD_Lf)
            ))
        else
            camera:set_lookat(glm.Vec3(self.pos.x, 0, self.pos.y))
        end
    end
end

-- Render player
function Player:render(proj, view)
    -- Blink during MUTEKI
    if self.stat == const.P_ST_MUTEKI and math.floor(self.tick / 4) % 4 == 0 then
        return
    end

    Cube.render(self, proj, view)

    -- Draw dash guide line
    if self.stat == const.P_ST_MUTEKI or self.stat == const.P_ST_NORMAL or self.stat == const.P_ST_DASH then
        local can_dash = self:calc_dash_f() > 0
        local color = can_dash and const.P_COL_DASH_GUIDE or const.P_COL_DASH_GUIDE_DISABLE
        local frame
        if self.stat == const.P_ST_DASH then
            frame = self.dash_f - self.tick
        else
            frame = math.max(self:calc_dash_f(), const.P_POW_GETA)
        end
        local guide_length = frame * const.P_DASH_V * const.DELTA_T

        local p1 = glm.Vec3(self.pos.x, 1, self.pos.y)
        local ps = pcs(guide_length, self.angle)
        local p2 = p1 + glm.Vec3(ps.x, 0, ps.y)

        local r, g, b = const.argb_to_rgb(color)
        local renderer = require("examples.hakonotaiatari.renderer")
        renderer.draw_line(p1, p2, r, g, b)
    end
end

-- Handle collision with another cube
function Player:on_collide(other_cube, audio)
    local dv = self.pos - other_cube.pos

    local my_coll_stat = self:coll_stat()
    local other_coll_stat = other_cube:coll_stat()

    if my_coll_stat == const.C_COL_ST_NORMAL then
        if other_coll_stat == const.C_COL_ST_NORMAL or other_coll_stat == const.C_COL_ST_DASH then
            if audio then audio.play(const.WAVE_HIT1_INDEX) end
            -- TODO: emit hit particles

            self.angle = math.atan(dv.y, dv.x)
            self.life = self.life - 1
            self.stat = const.P_ST_FUTTOBI
            self.color = const.P_COL_FUTTOBI
            self.tick = 0
            self.coll_enable = true
            self:add_power(const.P_POW_HIT_BONUS)
        end
    elseif my_coll_stat == const.C_COL_ST_DASH then
        if other_coll_stat == const.C_COL_ST_DASH then
            -- Mutual dash collision
            Cube.collide(self, other_cube)
            self.angle = math.atan(dv.y, dv.x)
            self.stat = const.P_ST_FUTTOBI_NOMUTEKI
            if audio then audio.play(const.WAVE_NAGU_INDEX) end
        end
    end
end

-- Get collision state
function Player:coll_stat()
    if self.stat == const.P_ST_MUTEKI then
        return const.C_COL_ST_NONE
    elseif self.stat == const.P_ST_NORMAL then
        return const.C_COL_ST_NORMAL
    elseif self.stat == const.P_ST_DASH then
        return const.C_COL_ST_DASH
    elseif self.stat == const.P_ST_FUTTOBI then
        return const.C_COL_ST_FUTTOBI
    elseif self.stat == const.P_ST_FUTTOBI_NOMUTEKI then
        return const.C_COL_ST_FUTTOBI
    elseif self.stat == const.P_ST_FADEOUT then
        return const.C_COL_ST_NONE
    elseif self.stat == const.P_ST_DEAD then
        return const.C_COL_ST_NONE
    end
    return const.C_COL_ST_NONE
end

-- Check if player is dead
function Player:is_dead()
    return self.stat == const.P_ST_DEAD
end

return Player
