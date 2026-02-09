local b2d = require("b2d")
local gl = require("sokol.gl")
local audio = require("examples.sjadm.audio")

local player = {}
player.__index = player

local WIDTH = 25
local HEIGHT = 50
local KILL_Y = -3000
local DEAD_TIMER_MAX = 1.5

function player.new(world_id, input, camera, map, registry)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMICBODY
    body_def.position = { 0, 10 }
    body_def.fixedRotation = true
    local body_id = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.enableContactEvents = true
    shape_def.enableSensorEvents = true
    local box = b2d.make_box(WIDTH / 2, HEIGHT / 2)
    local shape_id = b2d.create_polygon_shape(body_id, shape_def, box)
    b2d.shape_enable_contact_events(shape_id, true)

    -- Set mass to match original (~2.77)
    local mass_data = b2d.body_get_mass_data(body_id)
    mass_data.mass = 2.77
    b2d.body_set_mass_data(body_id, mass_data)

    local pl = setmetatable({
        world_id = world_id,
        input = input,
        camera = camera,
        map = map,
        registry = registry,
        body_id = body_id,
        shape_id = shape_id,
        jumpMax = 0,
        dashMax = 0,
        jumpNum = 0,
        dashNum = 0,
        jumpRepair = 0,
        dashRepair = 0,
        dashTime = 0,
        gameTime = nil,
        goalTime = nil,
        dead = false,
        deadTimer = DEAD_TIMER_MAX,
        shadows = {},
        respawnPoint = nil,
        groundConsequent = 0,
        state = "ground",
        touchingWalls = 0, -- count of wall contacts this frame
        contactNormalX = 0,
        contactNormalY = 0,
    }, player)

    registry[tostring(shape_id)] = pl
    return pl
end

function player:getType()
    return "P"
end

function player:setRespawnPoint(x, y)
    self.respawnPoint = { x = x, y = y }
end

function player:kill()
    if self.dead then return end
    self.dead = true
    audio.play("death")
end

function player:respawn()
    local point = self.respawnPoint
    b2d.body_set_transform(self.body_id, { point.x, point.y }, { 1, 0 })
    self.camera:set(point.x, point.y)
    self.dead = false
    self.deadTimer = DEAD_TIMER_MAX
    self.touchingWalls = 0
    b2d.body_enable(self.body_id)
    b2d.body_set_linear_velocity(self.body_id, { 0, 0 })
    b2d.body_set_awake(self.body_id, true)
end

function player:getPosition()
    local pos = b2d.body_get_position(self.body_id)
    return pos[1], pos[2]
end

function player:dashing()
    return self.dashTime > 0
end

function player:getVelocity()
    local vel = b2d.body_get_linear_velocity(self.body_id)
    return vel[1], vel[2]
end

function player:jumpable()
    return self.jumpNum > 0 and not self.dead
end

function player:dashable()
    return self.dashNum > 0 and not (self.dashTime > 0) and not self.dead
end

function player:addShadow()
    local x, y = self:getPosition()
    table.insert(self.shadows, { x = x, y = y })
end

function player:consumeShadow()
    table.remove(self.shadows, 1)
end

-- Called by init.lua when contact events are detected
function player:onContact(other)
    if not other then
        -- wall contact
        audio.play("ground")
        return
    end
    local t = other.getType and other:getType()
    if not t then
        audio.play("ground")
        return
    end
    if t == "K" then
        self:kill()
        return
    end
    if t == "C" then
        local x, y = other:getPosition()
        self:setRespawnPoint(x, y)
        audio.play("checkpoint")
        return
    end
    if t == "G" then
        self.goalTime = self.gameTime
        self.gameTime = nil
        self.jumpNum = 0
        self.jumpMax = 0
        self.dashNum = 0
        self.dashMax = 0
        self.map:resetItems()
        audio.stop_bgm()
        audio.play("goal")
        self:setRespawnPoint(self.map:getStartPoint())
        return
    end
    if t == "S" then
        return
    end
    if t == "J" or t == "D" then
        if other:consume() then
            if t == "J" then
                self.jumpMax = self.jumpMax + 1
            elseif t == "D" then
                self.dashMax = self.dashMax + 1
            end
            audio.play("item")
        end
    end
end

function player:onEndContact(other)
    if not other then return end
    local t = other.getType and other:getType()
    if t == "S" then
        if self.gameTime == nil and not self.dead then
            self.gameTime = 0
            audio.play_bgm()
        end
    end
end

function player:update(dt)
    if self.gameTime ~= nil then
        self.gameTime = self.gameTime + dt
    end

    local ix, iy = self.input.getAxis()

    -- Check ground state using contact count set by init.lua
    if self.touchingWalls > 0 then
        self.state = "ground"
        local vx, vy = self:getVelocity()
        if (vx * vx + vy * vy) > 15000 then
            if math.abs(vy) < 10.0 then
                audio.start_loop("walk")
            elseif vy < -100 then
                audio.start_loop("friction")
            end
        else
            audio.stop("walk")
            audio.stop("friction")
        end
    else
        self.state = "air"
        audio.stop("friction")
        audio.stop("walk")
    end

    -- repair abilities on ground
    if self.state == "ground" then
        if self.dashNum < self.dashMax then
            self.dashRepair = self.dashRepair - 1
            if self.dashRepair <= 0 then
                self.dashRepair = 2
                self.dashNum = self.dashMax
            end
        end
        if self.jumpNum < self.jumpMax then
            self.jumpRepair = self.jumpRepair - 1
            if self.jumpRepair <= 0 then
                self.jumpRepair = 2
                self.jumpNum = self.jumpMax
            end
        end
    end

    -- shadow trail
    self:addShadow()
    if self:dashing() then
        self.dashTime = self.dashTime - dt
    else
        if #self.shadows > 1 then
            self:consumeShadow()
            self:consumeShadow()
        end
    end

    -- horizontal movement
    local velocity = 250
    if self:dashing() then velocity = 700 end
    local vx, vy = self:getVelocity()
    local force = 10
    b2d.body_apply_force_to_center(self.body_id, { force * (ix * velocity - vx), 0 }, true)

    -- dash
    if self.input.getDash() and self:dashable() then
        local dash_force = 10
        local dash_velocity = 300
        local mass = b2d.body_get_mass(self.body_id)
        local fx = ix * dash_force * math.max(dash_velocity - math.abs(vx), 0)
        local fy = math.max(-vy * mass, 0)
        b2d.body_apply_linear_impulse_to_center(self.body_id, { fx, fy }, true)
        self.dashTime = 0.5
        self.dashNum = self.dashNum - 1
        audio.play("dash")
    end

    -- jump
    if self.input.getJump() and self:jumpable() then
        local nx, ny = self.contactNormalX, self.contactNormalY
        local a = -math.atan(nx, ny) + math.pi * 0.5
        local jumpUpVelo = 500
        local jumpNormalVelo = 200
        local nvx = math.cos(a) * jumpNormalVelo
        local nvy = jumpUpVelo + math.sin(a) * jumpNormalVelo
        local dvx, dvy = nvx - vx, nvy - vy
        local mass = b2d.body_get_mass(self.body_id)
        b2d.body_apply_linear_impulse_to_center(self.body_id, { dvx * mass, dvy * mass }, true)
        self.jumpNum = self.jumpNum - 1
        audio.play("jump")
    end

    -- kill Y
    local x, y = self:getPosition()
    if y < KILL_Y then
        self:kill()
    end

    -- dead state
    if self.dead then
        b2d.body_disable(self.body_id)
        self.deadTimer = self.deadTimer - dt
        if self.deadTimer < 0 then
            self:respawn()
        end
    end

    -- camera follow
    local vl = math.sqrt(vx * vx + vy * vy)
    local ts = 0.5 - 0.25 * math.min(vl * 0.002, 1)
    self.camera:target(x, y, ts)

    -- reset per-frame normal accumulator (walls count is managed by begin/end events)
    self.contactNormalX = 0
    self.contactNormalY = 0
end

function player:renderShadow()
    local hw, hh = WIDTH / 2, HEIGHT / 2
    for _, shadow in ipairs(self.shadows) do
        gl.BeginLines()
        gl.C3f(1, 1, 1)
        local x, y = shadow.x, shadow.y
        gl.V2f(x - hw, y - hh)
        gl.V2f(x + hw, y - hh)
        gl.V2f(x + hw, y - hh)
        gl.V2f(x + hw, y + hh)
        gl.V2f(x + hw, y + hh)
        gl.V2f(x - hw, y + hh)
        gl.V2f(x - hw, y + hh)
        gl.V2f(x - hw, y - hh)
        gl.End()
    end
end

function player:render()
    local x, y = self:getPosition()
    local hw, hh = WIDTH / 2, HEIGHT / 2
    -- player box (wireframe)
    gl.BeginLines()
    gl.C3f(1, 1, 1)
    gl.V2f(x - hw, y - hh)
    gl.V2f(x + hw, y - hh)
    gl.V2f(x + hw, y - hh)
    gl.V2f(x + hw, y + hh)
    gl.V2f(x + hw, y + hh)
    gl.V2f(x - hw, y + hh)
    gl.V2f(x - hw, y + hh)
    gl.V2f(x - hw, y - hh)
    gl.End()
    -- shadows
    self:renderShadow()
    -- jump indicator
    if self:jumpable() and (self.jumpNum < self.jumpMax) then
        local seg = 16
        gl.BeginLines()
        gl.C3f(1, 1, 1)
        for i = 0, seg - 1 do
            local a1 = (i / seg) * math.pi * 2
            local a2 = ((i + 1) / seg) * math.pi * 2
            gl.V2f(x + math.cos(a1) * 30, y - hh + math.sin(a1) * 10)
            gl.V2f(x + math.cos(a2) * 30, y - hh + math.sin(a2) * 10)
        end
        gl.End()
    end
end

return player
