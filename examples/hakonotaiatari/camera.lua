-- hakonotaiatari camera
-- Third-person camera that follows the player

local app = require("sokol.app")
local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")

---@class Camera
---@field eye vec3
---@field lookat vec3
---@field behind_high number
---@field behind_back number
---@field rot number
---@field does_rotate boolean
local Camera = {}
Camera.__index = Camera

-- Helper: angle subtraction with normalization to [-PI, PI]
local function sub_rad(a, b)
    local f = a - b
    while f >= const.PI do f = f - const.PI * 2 end
    while f < -const.PI do f = f + const.PI * 2 end
    return f
end

-- Create new camera
function Camera.new()
    local self = setmetatable({}, Camera)
    self.eye = glm.vec3(0, const.CAM_BEHIND_HIGH, -const.CAM_BEHIND_BACK)
    self.lookat = glm.vec3(0, 0, 0)
    self.behind_high = const.CAM_BEHIND_HIGH
    self.behind_back = const.CAM_BEHIND_BACK
    self.rot = 0
    self.does_rotate = false
    return self
end

-- Initialize camera
function Camera:init()
    self.eye = glm.vec3(0, const.CAM_BEHIND_HIGH, -const.CAM_BEHIND_BACK)
    self.lookat = glm.vec3(0, 0, 0)
    self.behind_high = const.CAM_BEHIND_HIGH
    self.behind_back = const.CAM_BEHIND_BACK
    self.rot = 0
    self.does_rotate = false
end

-- Enable/disable rotation (used for game over)
function Camera:set_enable_rotate(on)
    self.does_rotate = on
    self.rot = const.PI * 1.5
end

-- Update camera position
function Camera:update()
    if self.does_rotate then
        -- Rotate around lookat point
        self.rot = sub_rad(self.rot, -const.CAM_ROT_SPEED)
        local diff = glm.vec3(
            math.cos(self.rot) * self.behind_back,
            self.behind_high,
            math.sin(self.rot) * self.behind_back
        )
        local target = self.lookat + diff
        self.eye = self.eye + (target - self.eye) * const.CAM_BEHIND_COEFF
    else
        -- Static behind-view
        local target = self.lookat + glm.vec3(0, self.behind_high, -self.behind_back)
        self.eye = self.eye + (target - self.eye) * const.CAM_BEHIND_COEFF
    end
end

-- Set lookat target
function Camera:set_lookat(lookat)
    self.lookat = lookat
end

-- Get lookat target
function Camera:get_lookat()
    return self.lookat
end

-- Set eye position
function Camera:set_eye(eye)
    self.eye = eye
end

-- Get eye position
function Camera:get_eye()
    return self.eye
end

-- Set camera distance parameters
function Camera:set_behind(high, back)
    self.behind_high = high
    self.behind_back = back
end

-- Get view matrix
function Camera:view()
    return glm.lookat(
        self.eye,
        self.lookat,
        glm.vec3(0, 1, 0)
    )
end

-- Get projection matrix
function Camera:projection(fov)
    fov = fov or 45
    local w = app.widthf()
    local h = app.heightf()
    local aspect = w / h
    return glm.perspective(glm.radians(fov), aspect, 1.0, 5000.0)
end

-- Alias methods for consistency
function Camera:get_view()
    return self:view()
end

function Camera:get_proj(aspect)
    if aspect then
        return glm.perspective(glm.radians(45), aspect, 1.0, 5000.0)
    end
    return self:projection()
end

return Camera
