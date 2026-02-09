local app = require("sokol.app")
local gl = require("sokol.gl")

local camera = {}
camera.__index = camera

function camera.new()
    return setmetatable({
        x = 0,
        y = 0,
        tx = 0,
        ty = 0,
        ts = 0.2,
        s = 0.2,
    }, camera)
end

function camera:push()
    gl.PushMatrix()
    local w = app.Widthf()
    local h = app.Heightf()
    -- screen center
    gl.Translate(w / 2, h / 2, 0)
    -- camera zoom
    gl.Scale(self.s, self.s, 1)
    -- camera pan (y inverted for screen coords)
    gl.Translate(-self.x, self.y, 0)
    -- flip Y so physics Y-up becomes screen Y-down
    gl.Scale(1, -1, 1)
end

function camera:pop()
    gl.PopMatrix()
end

function camera:update(dt)
    if math.abs(self.tx - self.x) > 300 then
        self.x = self.x + (self.tx - self.x) * dt
    end
    if math.abs(self.ty - self.y) > 200 then
        self.y = self.y + (self.ty - self.y) * dt * 5
    end
    self.s = self.s + (self.ts - self.s) * dt
end

function camera:set(x, y)
    self.x = x
    self.tx = x
    self.y = y
    self.ty = y
end

function camera:target(x, y, s)
    self.tx, self.ty, self.ts = x, y, s
end

return camera
