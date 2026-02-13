-- hakonotaiatari cube base class
-- Physics and collision detection for cubes

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local renderer = require("examples.hakonotaiatari.renderer")

---@class Cube
---@field type integer
---@field pos vec2
---@field velo number
---@field angle number
---@field color integer
---@field length number
---@field force vec2
---@field stat integer
---@field life integer
---@field coll_enable boolean
---@field combo integer
local Cube = {}
Cube.__index = Cube

-- Helper: polar to cartesian (radius, angle) -> (x, y)
local function pcs(radius, angle)
    return glm.Vec2(math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Create new cube
function Cube.new()
    local self = setmetatable({}, Cube)
    self.type = 0
    self.pos = glm.Vec2(0, 0)
    self.velo = 0
    self.angle = 0
    self.color = 0xffffffff
    self.length = 10
    self.force = glm.Vec2(0, 0)
    self.stat = 0
    self.life = 0
    self.coll_enable = false
    self.combo = 0
    return self
end

-- Initialize cube
function Cube:init(cube_type, pos, velo, angle, color, length, combo)
    self.type = cube_type or 0
    self.pos = pos or glm.Vec2(0, 0)
    self.velo = velo or 0
    self.angle = angle or 0
    self.color = color or 0xffffffff
    self.length = length or 10
    self.combo = combo or 0
    self.force = glm.Vec2(0, 0)
end

-- Update cube position
function Cube:update(dt)
    -- Move in direction of angle at current velocity
    local movement = pcs(self.velo * dt, self.angle)
    self.pos = self.pos + movement

    -- Apply accumulated force
    self.pos = self.pos + self.force
    self.force = glm.Vec2(0, 0)
end

-- Handle collision with another cube
function Cube:collide(other_cube)
    local d = other_cube.pos - self.pos
    local l = (self.length + other_cube.length) * const.SQRT2
    local dl = glm.Length(d)

    if dl > 0.001 then
        -- Push force proportional to overlap
        self.force = self.force - d * 0.5 * ((l - dl) / l)
    end
end

-- Check if cube is out of field
function Cube:is_out_of_area()
    return (self.pos.x - self.length) < -const.FIELD_Lf
        or (self.pos.x + self.length) > const.FIELD_Lf
        or (self.pos.y - self.length) < -const.FIELD_Lf
        or (self.pos.y + self.length) > const.FIELD_Lf
end

-- Clamp position to field boundaries
function Cube:clamp_position()
    self.pos.x = glm.Clamp(self.pos.x, -const.FIELD_Lf + self.length, const.FIELD_Lf - self.length)
    self.pos.y = glm.Clamp(self.pos.y, -const.FIELD_Lf + self.length, const.FIELD_Lf - self.length)
end

-- Render cube
function Cube:render(proj, view)
    local r, g, b = const.argb_to_rgb(self.color)
    -- pos.x, pos.y are on XZ plane, Y is up
    -- Original uses uniform scale of length on vertices that go from -1 to 1 (size 2)
    -- So total size is length * 2 on all axes
    local pos3d = glm.Vec3(self.pos.x, self.length, self.pos.y)
    local size = glm.Vec3(self.length * 2, self.length * 2, self.length * 2)
    renderer.draw_cube(pos3d, size, -self.angle, r, g, b, proj, view)
end

-- Get collision state (to be overridden)
function Cube:coll_stat()
    return const.C_COL_ST_NONE
end

-- Check if this is a player
function Cube:is_player()
    return self.type == const.C_TYPE_PLAYER
end

-- Check if this is an enemy
function Cube:is_enemy()
    return (self.type & const.C_TYPE_ENEMY_MASK) ~= 0
end

-- Static: check collision between two rotating squares
-- c1, c2: vec2 centers
-- l1, l2: half-lengths (will be multiplied by sqrt(2))
-- a1, a2: rotation angles
function Cube.is_collide_square(c1, l1, a1, c2, l2, a2)
    -- Multiply by sqrt(2) to get center-to-vertex distance
    l1 = l1 * const.SQRT2
    l2 = l2 * const.SQRT2

    -- Quick rejection: circle test
    if glm.Length(c2 - c1) > (l1 + l2) then
        return false
    end

    -- Calculate 4 vertices of each square
    local p1 = {}
    for i = 0, 3 do
        local a = a1 + const.PI * (0.25 + 0.5 * i)
        p1[i + 1] = c1 + pcs(l1, a)
    end

    local p2 = {}
    for i = 0, 3 do
        local a = a2 + const.PI * (0.25 + 0.5 * i)
        p2[i + 1] = c2 + pcs(l2, a)
    end

    -- Check if any vertex of p2 is inside p1
    for i2 = 1, 4 do
        local all_inner = true
        for i1_1 = 1, 4 do
            local i1_2 = (i1_1 % 4) + 1
            local v1 = p1[i1_2] - p1[i1_1]
            local v2 = p2[i2] - p1[i1_1]
            local cross = v1.x * v2.y - v1.y * v2.x
            if cross < 0 then
                all_inner = false
                break
            end
        end
        if all_inner then
            return true
        end
    end

    -- Check if any vertex of p1 is inside p2
    for i1 = 1, 4 do
        local all_inner = true
        for i2_1 = 1, 4 do
            local i2_2 = (i2_1 % 4) + 1
            local v1 = p2[i2_2] - p2[i2_1]
            local v2 = p1[i1] - p2[i2_1]
            local cross = v1.x * v2.y - v1.y * v2.x
            if cross < 0 then
                all_inner = false
                break
            end
        end
        if all_inner then
            return true
        end
    end

    return false
end

-- Static: check collision between two cubes
function Cube.is_cube_collide(cube1, cube2)
    return Cube.is_collide_square(
        cube1.pos, cube1.length, cube1.angle,
        cube2.pos, cube2.length, cube2.angle
    )
end

return Cube
