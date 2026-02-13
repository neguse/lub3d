local b2d = require("b2d")
local gl = require("sokol.gl")

local checkpoint = {}
checkpoint.__index = checkpoint

local RADIUS = 150
local SEGMENTS = 24

function checkpoint.new(world_id, x, y, registry)
    local body_def = b2d.DefaultBodyDef()
    body_def.position = { x, y }
    local body_id = b2d.CreateBody(world_id, body_def)

    local shape_def = b2d.DefaultShapeDef()
    shape_def.isSensor = true
    shape_def.enableSensorEvents = true
    local circle = b2d.Circle({ center = { 0, 0 }, radius = RADIUS })
    local shape_id = b2d.CreateCircleShape(body_id, shape_def, circle)

    local cp = setmetatable({
        body_id = body_id,
        shape_id = shape_id,
        x = x,
        y = y,
    }, checkpoint)

    if registry then
        registry[tostring(shape_id)] = cp
    end

    return cp
end

function checkpoint:getType()
    return "C"
end

function checkpoint:getPosition()
    return self.x, self.y
end

function checkpoint:render()
    gl.BeginLines()
    gl.C3f(1, 1, 1)
    for i = 0, SEGMENTS - 1 do
        local a1 = (i / SEGMENTS) * math.pi * 2
        local a2 = ((i + 1) / SEGMENTS) * math.pi * 2
        gl.V2f(self.x + math.cos(a1) * RADIUS, self.y + math.sin(a1) * RADIUS)
        gl.V2f(self.x + math.cos(a2) * RADIUS, self.y + math.sin(a2) * RADIUS)
    end
    gl.End()
end

return checkpoint
