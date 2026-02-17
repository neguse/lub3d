-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Top-Down Car"
scene.description = "WASD or Arrow keys to drive.\nUp=forward, Down=reverse, Left/Right=steer.\nZero gravity, tire friction model.\nTraction zones affect handling."

local world_ref
local chassis_id
local tires = {} -- { body_id, joint_id, is_front, max_forward_speed, ..., current_traction, contacted_areas }
local body_entries = {}
local camera_ref
local follow_car = true

local dir_up = false
local dir_down = false
local dir_left = false
local dir_right = false

-- Original iforce2d constants
local lock_angle = math.rad(35)
local turn_speed_per_sec = math.rad(160)

-- Filter: car-scene objects only collide with each other, not the default ground
local car_filter = b2d.Filter({ category_bits = 0x0002, mask_bits = 0x0002 })

-- Ground area sensor data
local ground_areas = {} -- tostring(shape_id) -> { friction_modifier }
local tire_shapes = {} -- tostring(shape_id) -> tire_index
local zone_bodies = {} -- { body_id, hw, hh, center, rotation } for visualization

local function shape_key(shape_id)
    return tostring(shape_id)
end

local function dot2(a, b)
    return a[1] * b[1] + a[2] * b[2]
end

local function len2(a)
    return math.sqrt(a[1] * a[1] + a[2] * a[2])
end

local function update_tire_traction(tire)
    if not next(tire.contacted_areas) then
        tire.current_traction = 1.0
    else
        tire.current_traction = 0
        for _, area in pairs(tire.contacted_areas) do
            if area.friction_modifier > tire.current_traction then
                tire.current_traction = area.friction_modifier
            end
        end
    end
end

-- Tire: original iforce2d TDTire class
local function create_tire(world_id, max_fwd, max_bwd, max_drive, max_lateral)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 0 } -- will be placed by joint
    local body = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.filter = car_filter
    shape_def.enable_sensor_events = true
    local sid = b2d.create_polygon_shape(body, shape_def, b2d.make_box(0.5, 1.25))

    table.insert(body_entries, { body_id = body, color = { 0.3, 0.3, 0.3 } })
    local tire = {
        body_id = body,
        joint_id = nil,
        is_front = false,
        max_forward_speed = max_fwd,
        max_backward_speed = max_bwd,
        max_drive_force = max_drive,
        max_lateral_impulse = max_lateral,
        current_traction = 1.0,
        contacted_areas = {},
    }

    -- Register tire shape for sensor event lookup
    tire_shapes[shape_key(sid)] = #tires + 1

    return tire
end

local function update_tire_friction(tire)
    local body = tire.body_id
    local vel = b2d.body_get_linear_velocity(body)
    local mass = b2d.body_get_mass(body)
    local traction = tire.current_traction

    -- Get tire's right vector (local +x in world)
    local right = b2d.body_get_world_vector(body, { 1, 0 })

    -- Lateral velocity
    local lat_speed = dot2(vel, right)
    local lat_vel = { lat_speed * right[1], lat_speed * right[2] }

    -- Lateral impulse to cancel sideways motion (scaled by traction)
    local impulse = { -mass * lat_vel[1], -mass * lat_vel[2] }
    local imp_len = len2(impulse)
    if imp_len > tire.max_lateral_impulse then
        impulse[1] = impulse[1] * tire.max_lateral_impulse / imp_len
        impulse[2] = impulse[2] * tire.max_lateral_impulse / imp_len
    end
    b2d.body_apply_linear_impulse_to_center(body,
        { traction * impulse[1], traction * impulse[2] }, true)

    -- Angular velocity damping (scaled by traction)
    local ang_vel = b2d.body_get_angular_velocity(body)
    local mass_data = b2d.body_get_mass_data(body)
    local inertia = mass_data.rotational_inertia or 1.0
    b2d.body_apply_angular_impulse(body, traction * -0.1 * inertia * ang_vel, true)

    -- Forward drag (scaled by traction)
    local forward = b2d.body_get_world_vector(body, { 0, 1 })
    local fwd_speed = dot2(vel, forward)
    local drag = -2 * fwd_speed
    b2d.body_apply_force_to_center(body,
        { traction * drag * forward[1], traction * drag * forward[2] }, true)
end

local function update_tire_drive(tire)
    local body = tire.body_id
    local forward = b2d.body_get_world_vector(body, { 0, 1 })
    local vel = b2d.body_get_linear_velocity(body)
    local current_speed = dot2(vel, forward)

    local desired_speed = 0
    if dir_up then
        desired_speed = tire.max_forward_speed
    elseif dir_down then
        desired_speed = tire.max_backward_speed
    else
        return
    end

    local force = 0
    if desired_speed > current_speed then
        force = tire.max_drive_force
    elseif desired_speed < current_speed then
        force = -tire.max_drive_force
    end

    -- Drive force scaled by traction
    local traction = tire.current_traction
    b2d.body_apply_force_to_center(body,
        { traction * force * forward[1], traction * force * forward[2] }, true)
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    body_entries = {}
    tires = {}
    ground_areas = {}
    tire_shapes = {}
    zone_bodies = {}
    dir_up = false
    dir_down = false
    dir_left = false
    dir_right = false
    follow_car = true

    -- Zero gravity
    b2d.world_set_gravity(world_id, { 0, 0 })

    -- Ground area sensors (on ground body)
    local zone_defs = {
        { hw = 9, hh = 7, center = { -10, 15 }, angle = math.rad(20), friction_modifier = 0.5 },
        { hw = 9, hh = 5, center = { 5, 20 }, angle = math.rad(-40), friction_modifier = 0.2 },
    }
    for _, zd in ipairs(zone_defs) do
        local zone_shape_def = b2d.default_shape_def()
        zone_shape_def.is_sensor = true
        zone_shape_def.enable_sensor_events = true
        local zone_polygon = b2d.make_offset_box(zd.hw, zd.hh, zd.center, b2d.make_rot(zd.angle))
        local zone_sid = b2d.create_polygon_shape(ground_id, zone_shape_def, zone_polygon)
        ground_areas[shape_key(zone_sid)] = { friction_modifier = zd.friction_modifier }
        table.insert(zone_bodies, {
            center = zd.center, hw = zd.hw, hh = zd.hh, angle = zd.angle,
            friction_modifier = zd.friction_modifier,
        })
    end

    -- Boundary walls (large arena for high-speed car)
    local arena = 150
    local walls = {
        { pos = { 0, -arena }, hw = arena, hh = 1 },
        { pos = { 0, arena }, hw = arena, hh = 1 },
        { pos = { -arena, 0 }, hw = 1, hh = arena },
        { pos = { arena, 0 }, hw = 1, hh = arena },
    }
    for _, w in ipairs(walls) do
        local body_def = b2d.default_body_def()
        body_def.position = w.pos
        local wall = b2d.create_body(world_id, body_def)
        local shape_def = b2d.default_shape_def()
        shape_def.filter = car_filter
        b2d.create_polygon_shape(wall, shape_def, b2d.make_box(w.hw, w.hh))
        table.insert(body_entries, { body_id = wall, color = { 0.4, 0.4, 0.4 } })
    end

    -- Obstacles
    local obstacles = {
        { pos = { -30, 40 }, hw = 3, hh = 3 },
        { pos = { 40, -20 }, hw = 4, hh = 2 },
        { pos = { -20, -50 }, hw = 2, hh = 5 },
        { pos = { 60, 50 }, hw = 2, hh = 8 },
        { pos = { -50, -30 }, hw = 5, hh = 2 },
    }
    for _, obs in ipairs(obstacles) do
        local body_def = b2d.default_body_def()
        body_def.position = obs.pos
        local ob = b2d.create_body(world_id, body_def)
        local shape_def = b2d.default_shape_def()
        shape_def.filter = car_filter
        b2d.create_polygon_shape(ob, shape_def, b2d.make_box(obs.hw, obs.hh))
        table.insert(body_entries, { body_id = ob, color = { 0.5, 0.5, 0.6 } })
    end

    -- Chassis: original iforce2d 8-vertex car polygon
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 0 }
    body_def.angular_damping = 3.0
    chassis_id = b2d.create_body(world_id, body_def)

    -- Original iforce2d 8-vertex car polygon
    local vertices = {
        { 1.5, 0 }, { 3, 2.5 }, { 2.8, 5.5 }, { 1, 10 },
        { -1, 10 }, { -2.8, 5.5 }, { -3, 2.5 }, { -1.5, 0 },
    }
    local hull = b2d.compute_hull(vertices, #vertices)
    local shape_def = b2d.default_shape_def()
    shape_def.density = 0.1
    shape_def.filter = car_filter
    b2d.create_polygon_shape(chassis_id, shape_def, b2d.make_polygon(hull, 0))
    table.insert(body_entries, { body_id = chassis_id, color = { 0.2, 0.5, 0.9 } })

    -- Original iforce2d tire parameters:
    -- Back:  maxForward=250, maxBackward=-40, maxDrive=300, maxLateral=8.5
    -- Front: maxForward=250, maxBackward=-40, maxDrive=500, maxLateral=7.5

    -- Back left tire
    local bl = create_tire(world_id, 250, -40, 300, 8.5)
    local jdef = b2d.default_revolute_joint_def()
    jdef.body_id_a = chassis_id
    jdef.body_id_b = bl.body_id
    jdef.local_anchor_a = { -3, 0.75 }
    jdef.local_anchor_b = { 0, 0 }
    jdef.enable_limit = true
    jdef.lower_angle = 0
    jdef.upper_angle = 0
    bl.joint_id = b2d.create_revolute_joint(world_id, jdef)
    bl.is_front = false
    table.insert(tires, bl)

    -- Back right tire
    local br = create_tire(world_id, 250, -40, 300, 8.5)
    jdef = b2d.default_revolute_joint_def()
    jdef.body_id_a = chassis_id
    jdef.body_id_b = br.body_id
    jdef.local_anchor_a = { 3, 0.75 }
    jdef.local_anchor_b = { 0, 0 }
    jdef.enable_limit = true
    jdef.lower_angle = 0
    jdef.upper_angle = 0
    br.joint_id = b2d.create_revolute_joint(world_id, jdef)
    br.is_front = false
    table.insert(tires, br)

    -- Front left tire
    local fl = create_tire(world_id, 250, -40, 500, 7.5)
    jdef = b2d.default_revolute_joint_def()
    jdef.body_id_a = chassis_id
    jdef.body_id_b = fl.body_id
    jdef.local_anchor_a = { -3, 8.5 }
    jdef.local_anchor_b = { 0, 0 }
    jdef.enable_limit = true
    jdef.lower_angle = 0
    jdef.upper_angle = 0
    fl.joint_id = b2d.create_revolute_joint(world_id, jdef)
    fl.is_front = true
    table.insert(tires, fl)

    -- Front right tire
    local fr = create_tire(world_id, 250, -40, 500, 7.5)
    jdef = b2d.default_revolute_joint_def()
    jdef.body_id_a = chassis_id
    jdef.body_id_b = fr.body_id
    jdef.local_anchor_a = { 3, 8.5 }
    jdef.local_anchor_b = { 0, 0 }
    jdef.enable_limit = true
    jdef.lower_angle = 0
    jdef.upper_angle = 0
    fr.joint_id = b2d.create_revolute_joint(world_id, jdef)
    fr.is_front = true
    table.insert(tires, fr)

    -- Initial camera position
    if camera_ref then
        camera_ref.x = 0
        camera_ref.y = 0
    end
end

function scene:update(dt)
    -- Process sensor events for traction zones
    local sensor_events = b2d.world_get_sensor_events(world_ref)
    if sensor_events then
        if sensor_events.begin_events then
            for _, ev in ipairs(sensor_events.begin_events) do
                local area = ground_areas[shape_key(ev.sensor_shape_id)]
                local tire_idx = tire_shapes[shape_key(ev.visitor_shape_id)]
                if area and tire_idx then
                    local tire = tires[tire_idx]
                    tire.contacted_areas[shape_key(ev.sensor_shape_id)] = area
                    update_tire_traction(tire)
                end
            end
        end
        if sensor_events.end_events then
            for _, ev in ipairs(sensor_events.end_events) do
                local tire_idx = tire_shapes[shape_key(ev.visitor_shape_id)]
                if tire_idx then
                    local tire = tires[tire_idx]
                    tire.contacted_areas[shape_key(ev.sensor_shape_id)] = nil
                    update_tire_traction(tire)
                end
            end
        end
    end

    -- Update steering
    local turn_per_step = turn_speed_per_sec * dt
    for _, tire in ipairs(tires) do
        if tire.is_front then
            local desired_angle = 0
            if dir_left then
                desired_angle = lock_angle
            elseif dir_right then
                desired_angle = -lock_angle
            end

            local current_angle = b2d.revolute_joint_get_angle(tire.joint_id)
            local angle_diff = desired_angle - current_angle
            angle_diff = math.max(-turn_per_step, math.min(turn_per_step, angle_diff))
            local new_angle = current_angle + angle_diff
            b2d.revolute_joint_set_limits(tire.joint_id, new_angle, new_angle)
        end

        update_tire_friction(tire)
        update_tire_drive(tire)
    end

    -- Follow camera
    if follow_car and camera_ref and b2d.body_is_valid(chassis_id) then
        local pos = b2d.body_get_position(chassis_id)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:get_bodies()
    return body_entries
end

function scene:render_extra()
    -- Draw traction zone outlines
    for _, zd in ipairs(zone_bodies) do
        local cx, cy = zd.center[1], zd.center[2]
        local hw, hh = zd.hw, zd.hh
        local cos_a = math.cos(zd.angle)
        local sin_a = math.sin(zd.angle)
        local corners = {
            { cx + (-hw * cos_a - (-hh) * sin_a), cy + (-hw * sin_a + (-hh) * cos_a) },
            { cx + (hw * cos_a - (-hh) * sin_a), cy + (hw * sin_a + (-hh) * cos_a) },
            { cx + (hw * cos_a - hh * sin_a), cy + (hw * sin_a + hh * cos_a) },
            { cx + (-hw * cos_a - hh * sin_a), cy + (-hw * sin_a + hh * cos_a) },
        }
        local r, g, b_c = 0.8, 0.4, 0.1
        if zd.friction_modifier < 0.3 then
            r, g, b_c = 0.2, 0.4, 0.8
        end
        draw.polygon_outline(corners, r, g, b_c)
    end

    -- Draw direction indicator on chassis
    local pos = b2d.body_get_position(chassis_id)
    local forward = b2d.body_get_world_vector(chassis_id, { 0, 1 })
    draw.line(pos[1], pos[2],
        pos[1] + forward[1] * 5, pos[2] + forward[2] * 5,
        0, 1, 0)
end

function scene:render_ui()
    local vel = b2d.body_get_linear_velocity(chassis_id)
    local speed = len2(vel)
    imgui.text_unformatted(string.format("Speed: %.1f m/s", speed))

    imgui.separator()
    imgui.text_unformatted("Controls: WASD / Arrow keys")
    imgui.text_unformatted("UP=forward, DOWN=reverse")
    imgui.text_unformatted("LEFT/RIGHT=steer, F=follow cam")

    imgui.separator()
    imgui.text_unformatted("Follow: " .. (follow_car and "ON" or "OFF"))

    imgui.separator()
    local names = { "BL", "BR", "FL", "FR" }
    for i, tire in ipairs(tires) do
        imgui.text_unformatted(string.format("Tire %s traction: %.2f", names[i] or i, tire.current_traction))
    end
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.UP or ev.key_code == app.Keycode.W then
            dir_up = true
        elseif ev.key_code == app.Keycode.DOWN or ev.key_code == app.Keycode.S then
            dir_down = true
        elseif ev.key_code == app.Keycode.LEFT or ev.key_code == app.Keycode.A then
            dir_left = true
        elseif ev.key_code == app.Keycode.RIGHT or ev.key_code == app.Keycode.D then
            dir_right = true
        elseif ev.key_code == app.Keycode.F then
            follow_car = not follow_car
        end
    elseif ev.type == app.EventType.KEY_UP then
        if ev.key_code == app.Keycode.UP or ev.key_code == app.Keycode.W then
            dir_up = false
        elseif ev.key_code == app.Keycode.DOWN or ev.key_code == app.Keycode.S then
            dir_down = false
        elseif ev.key_code == app.Keycode.LEFT or ev.key_code == app.Keycode.A then
            dir_left = false
        elseif ev.key_code == app.Keycode.RIGHT or ev.key_code == app.Keycode.D then
            dir_right = false
        end
    end
end

function scene:cleanup() end

return scene
