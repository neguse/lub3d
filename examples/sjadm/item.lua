local b2d = require("b2d")
local gl = require("sokol.gl")

local item = {}
item.__index = item

local RADIUS = 50
local SEGMENTS = 16

function item.new(world_id, x, y, type, registry)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { x, y }
    local body_id = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.enable_contact_events = true
    shape_def.density = 1.0
    local circle = b2d.circle({ center = { 0, 0 }, radius = RADIUS })
    local shape_id = b2d.create_circle_shape(body_id, shape_def, circle)

    local it = setmetatable({
        type = type, -- "J" or "D"
        body_id = body_id,
        shape_id = shape_id,
        consumed = false,
    }, item)

    if registry then
        registry[tostring(shape_id)] = it
    end

    return it
end

function item:get_type()
    return self.type
end

function item:is_consumed()
    return self.consumed
end

function item:consume()
    if self.consumed then return false end
    self.consumed = true
    return true
end

function item:destroy(registry)
    if registry then
        registry[tostring(self.shape_id)] = nil
    end
    b2d.destroy_body(self.body_id)
end

function item:render()
    if self.consumed then return end
    local pos = b2d.body_get_position(self.body_id)
    local x, y = pos[1], pos[2]
    gl.begin_lines()
    gl.c3f(1, 1, 1)
    for i = 0, SEGMENTS - 1 do
        local a1 = (i / SEGMENTS) * math.pi * 2
        local a2 = ((i + 1) / SEGMENTS) * math.pi * 2
        gl.v2f(x + math.cos(a1) * RADIUS, y + math.sin(a1) * RADIUS)
        gl.v2f(x + math.cos(a2) * RADIUS, y + math.sin(a2) * RADIUS)
    end
    gl["end"]()
end

return item
