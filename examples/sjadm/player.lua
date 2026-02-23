local b2d = require("b2d")
local gl = require("sokol.gl")
local audio = require("examples.sjadm.audio")

local player = {}
player.__index = player

local WIDTH <const> = 25
local HEIGHT <const> = 50
local KILL_Y <const> = -3000
local DEAD_TIMER_MAX <const> = 1.5

function player.new(world_id, input, camera, map, registry)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 10 }
    body_def.fixed_rotation = true
    local body_id = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.enable_contact_events = true
    shape_def.enable_sensor_events = true
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
        jump_max = 0,
        dash_max = 0,
        jump_num = 0,
        dash_num = 0,
        jump_repair = 0,
        dash_repair = 0,
        dash_time = 0,
        game_time = nil,
        goal_time = nil,
        dead = false,
        dead_timer = DEAD_TIMER_MAX,
        shadows = {},
        respawn_point = nil,
        ground_consequent = 0,
        state = "ground",
        touching_walls = 0, -- count of wall contacts this frame
        contact_normal_x = 0,
        contact_normal_y = 0,
    }, player)

    registry[tostring(shape_id)] = pl
    return pl
end

function player:get_type()
    return "P"
end

function player:set_respawn_point(x, y)
    self.respawn_point = { x = x, y = y }
end

function player:kill()
    if self.dead then return end
    self.dead = true
    audio.play("death")
end

function player:respawn()
    local point = self.respawn_point
    b2d.body_set_transform(self.body_id, { point.x, point.y }, { 1, 0 })
    self.camera:set(point.x, point.y)
    self.dead = false
    self.dead_timer = DEAD_TIMER_MAX
    self.touching_walls = 0
    b2d.body_enable(self.body_id)
    b2d.body_set_linear_velocity(self.body_id, { 0, 0 })
    b2d.body_set_awake(self.body_id, true)
end

function player:get_position()
    local pos = b2d.body_get_position(self.body_id)
    return pos[1], pos[2]
end

function player:dashing()
    return self.dash_time > 0
end

function player:get_velocity()
    local vel = b2d.body_get_linear_velocity(self.body_id)
    return vel[1], vel[2]
end

function player:jumpable()
    return self.jump_num > 0 and not self.dead
end

function player:dashable()
    return self.dash_num > 0 and not (self.dash_time > 0) and not self.dead
end

function player:add_shadow()
    local x, y = self:get_position()
    table.insert(self.shadows, { x = x, y = y })
end

function player:consume_shadow()
    table.remove(self.shadows, 1)
end

-- Called by init.lua when contact events are detected
function player:on_contact(other)
    if not other then
        -- wall contact
        audio.play("ground")
        return
    end
    local t = other.get_type and other:get_type()
    if not t then
        audio.play("ground")
        return
    end
    if t == "K" then
        self:kill()
        return
    end
    if t == "C" then
        local x, y = other:get_position()
        self:set_respawn_point(x, y)
        audio.play("checkpoint")
        return
    end
    if t == "G" then
        self.goal_time = self.game_time
        self.game_time = nil
        self.jump_num = 0
        self.jump_max = 0
        self.dash_num = 0
        self.dash_max = 0
        self.map:reset_items()
        audio.stop_bgm()
        audio.play("goal")
        self:set_respawn_point(self.map:get_start_point())
        return
    end
    if t == "S" then
        return
    end
    if t == "J" or t == "D" then
        if other:consume() then
            if t == "J" then
                self.jump_max = self.jump_max + 1
            elseif t == "D" then
                self.dash_max = self.dash_max + 1
            end
            audio.play("item")
        end
    end
end

function player:on_end_contact(other)
    if not other then return end
    local t = other.get_type and other:get_type()
    if t == "S" then
        if self.game_time == nil and not self.dead then
            self.game_time = 0
            audio.play_bgm()
        end
    end
end

function player:update(dt)
    if self.game_time ~= nil then
        self.game_time = self.game_time + dt
    end

    local ix, _iy = self.input.get_axis()

    -- Check ground state using contact count set by init.lua
    if self.touching_walls > 0 then
        self.state = "ground"
        local vx, vy = self:get_velocity()
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
        if self.dash_num < self.dash_max then
            self.dash_repair = self.dash_repair - 1
            if self.dash_repair <= 0 then
                self.dash_repair = 2
                self.dash_num = self.dash_max
            end
        end
        if self.jump_num < self.jump_max then
            self.jump_repair = self.jump_repair - 1
            if self.jump_repair <= 0 then
                self.jump_repair = 2
                self.jump_num = self.jump_max
            end
        end
    end

    -- shadow trail
    self:add_shadow()
    if self:dashing() then
        self.dash_time = self.dash_time - dt
    else
        if #self.shadows > 1 then
            self:consume_shadow()
            self:consume_shadow()
        end
    end

    -- horizontal movement
    local velocity = 250
    if self:dashing() then velocity = 700 end
    local vx, vy = self:get_velocity()
    local force = 10
    b2d.body_apply_force_to_center(self.body_id, { force * (ix * velocity - vx), 0 }, true)

    -- dash
    if self.input.get_dash() and self:dashable() then
        local dash_force = 10
        local dash_velocity = 300
        local mass = b2d.body_get_mass(self.body_id)
        local fx = ix * dash_force * math.max(dash_velocity - math.abs(vx), 0)
        local fy = math.max(-vy * mass, 0)
        b2d.body_apply_linear_impulse_to_center(self.body_id, { fx, fy }, true)
        self.dash_time = 0.5
        self.dash_num = self.dash_num - 1
        audio.play("dash")
    end

    -- jump
    if self.input.get_jump() and self:jumpable() then
        local nx, ny = self.contact_normal_x, self.contact_normal_y
        local a = -math.atan(nx, ny) + math.pi * 0.5
        local jump_up_velo = 500
        local jump_normal_velo = 200
        local nvx = math.cos(a) * jump_normal_velo
        local nvy = jump_up_velo + math.sin(a) * jump_normal_velo
        local dvx, dvy = nvx - vx, nvy - vy
        local mass = b2d.body_get_mass(self.body_id)
        b2d.body_apply_linear_impulse_to_center(self.body_id, { dvx * mass, dvy * mass }, true)
        self.jump_num = self.jump_num - 1
        audio.play("jump")
    end

    -- kill Y
    local x, y = self:get_position()
    if y < KILL_Y then
        self:kill()
    end

    -- dead state
    if self.dead then
        b2d.body_disable(self.body_id)
        self.dead_timer = self.dead_timer - dt
        if self.dead_timer < 0 then
            self:respawn()
        end
    end

    -- camera follow
    local vl = math.sqrt(vx * vx + vy * vy)
    local ts = 0.5 - 0.25 * math.min(vl * 0.002, 1)
    self.camera:target(x, y, ts)

    -- reset per-frame normal accumulator (walls count is managed by begin/end events)
    self.contact_normal_x = 0
    self.contact_normal_y = 0
end

function player:render_shadow()
    local hw, hh = WIDTH / 2, HEIGHT / 2
    for _, shadow in ipairs(self.shadows) do
        gl.begin_lines()
        gl.c3f(1, 1, 1)
        local x, y = shadow.x, shadow.y
        gl.v2f(x - hw, y - hh)
        gl.v2f(x + hw, y - hh)
        gl.v2f(x + hw, y - hh)
        gl.v2f(x + hw, y + hh)
        gl.v2f(x + hw, y + hh)
        gl.v2f(x - hw, y + hh)
        gl.v2f(x - hw, y + hh)
        gl.v2f(x - hw, y - hh)
        gl["end"]()
    end
end

function player:render()
    local x, y = self:get_position()
    local hw, hh = WIDTH / 2, HEIGHT / 2
    -- player box (wireframe)
    gl.begin_lines()
    gl.c3f(1, 1, 1)
    gl.v2f(x - hw, y - hh)
    gl.v2f(x + hw, y - hh)
    gl.v2f(x + hw, y - hh)
    gl.v2f(x + hw, y + hh)
    gl.v2f(x + hw, y + hh)
    gl.v2f(x - hw, y + hh)
    gl.v2f(x - hw, y + hh)
    gl.v2f(x - hw, y - hh)
    gl["end"]()
    -- shadows
    self:render_shadow()
    -- jump indicator
    if self:jumpable() and (self.jump_num < self.jump_max) then
        local seg = 16
        gl.begin_lines()
        gl.c3f(1, 1, 1)
        for i = 0, seg - 1 do
            local a1 = (i / seg) * math.pi * 2
            local a2 = ((i + 1) / seg) * math.pi * 2
            gl.v2f(x + math.cos(a1) * 30, y - hh + math.sin(a1) * 10)
            gl.v2f(x + math.cos(a2) * 30, y - hh + math.sin(a2) * 10)
        end
        gl["end"]()
    end
end

return player
