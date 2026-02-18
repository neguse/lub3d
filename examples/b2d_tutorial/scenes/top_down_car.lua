-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")
local track_data = require("examples.b2d_tutorial.scenes.racetrack_data")

local scene = {}
scene.name = "Top-Down Car"
scene.description = "WASD or Arrow keys to drive.\nUp=forward, Down=reverse, Left/Right=steer.\nZero gravity, tire friction model.\nRace track with barrels and water zones."

local world_ref
local chassis_id
local tires = {} -- { body_id, joint_id, is_front, max_forward_speed, ..., current_traction, current_drag, contacted_areas }
local body_entries = {}
local camera_ref
local follow_car = true

local dir_up = false
local dir_down = false
local dir_left = false
local dir_right = false

-- Original iforce2d race track constants
local lock_angle = math.rad(35)
local turn_speed_per_sec = math.rad(320)

-- Filter: car-scene objects only collide with each other, not the default ground
local car_filter = b2d.Filter({ category_bits = 0x0002, mask_bits = 0x0002 })

-- Ground area sensor data
local ground_areas = {} -- tostring(shape_id) -> { friction_modifier, drag_modifier }
local tire_shapes = {} -- tostring(shape_id) -> tire_index

-- Track rendering state
local chain_ids = {}
local track_body_id
local water_zone_verts = {} -- for debug rendering

local function shape_key(shape_id)
    return tostring(shape_id)
end

local function dot2(a, b)
    return a[1] * b[1] + a[2] * b[2]
end

local function len2(a)
    return math.sqrt(a[1] * a[1] + a[2] * a[2])
end

local function signed_area(verts)
    local a = 0
    local n = #verts
    for i = 1, n do
        local j = (i % n) + 1
        a = a + verts[i][1] * verts[j][2] - verts[j][1] * verts[i][2]
    end
    return a * 0.5
end

local function get_lateral_velocity(body)
    local right = b2d.body_get_world_vector(body, { 1, 0 })
    local vel = b2d.body_get_linear_velocity(body)
    local d = dot2(vel, right)
    return { d * right[1], d * right[2] }
end

local function update_tire_traction(tire)
    if not next(tire.contacted_areas) then
        tire.current_traction = 1.0
        tire.current_drag = 1.0
    else
        tire.current_traction = 0
        tire.current_drag = 1.0
        for _, area in pairs(tire.contacted_areas) do
            if area.friction_modifier > tire.current_traction then
                tire.current_traction = area.friction_modifier
            end
            if area.drag_modifier > tire.current_drag then
                tire.current_drag = area.drag_modifier
            end
        end
    end
end

-- Tire: iforce2d TDTireR class (race track version)
local function create_tire(world_id, max_fwd, max_bwd, max_drive, max_lateral)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 0 } -- will be placed by joint
    body_def.enable_sleep = false
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
        current_drag = 1.0,
        contacted_areas = {},
    }

    -- Register tire shape for sensor event lookup
    tire_shapes[shape_key(sid)] = #tires + 1

    return tire
end

-- Race track version: no lateral impulse, drag modifier on forward drag
local function update_tire_friction(tire, dt)
    local body = tire.body_id
    local vel = b2d.body_get_linear_velocity(body)
    local traction = tire.current_traction
    local dt_scale = dt * 60.0 -- 1.0 at 60Hz

    -- Angular velocity damping (scaled by traction and dt)
    local ang_vel = b2d.body_get_angular_velocity(body)
    local mass_data = b2d.body_get_mass_data(body)
    local inertia = mass_data.rotational_inertia or 1.0
    b2d.body_apply_angular_impulse(body, traction * -0.1 * dt_scale * inertia * ang_vel, true)

    -- Forward drag (scaled by traction and drag modifier)
    local forward = b2d.body_get_world_vector(body, { 0, 1 })
    local fwd_speed = dot2(vel, forward)
    local drag = -0.25 * fwd_speed * tire.current_drag
    b2d.body_apply_force_to_center(body,
        { traction * drag * forward[1], traction * drag * forward[2] }, true)
end

local function update_tire_drive(tire, dt)
    local body = tire.body_id
    local forward = b2d.body_get_world_vector(body, { 0, 1 })
    local vel = b2d.body_get_linear_velocity(body)
    local current_speed = dot2(vel, forward)
    local traction = tire.current_traction

    -- Step 1: desired_speed and force from input
    local desired_speed = 0
    if dir_up then desired_speed = tire.max_forward_speed
    elseif dir_down then desired_speed = tire.max_backward_speed end

    local force = 0
    if dir_up or dir_down then
        if desired_speed > current_speed then
            force = tire.max_drive_force
        elseif desired_speed < current_speed then
            force = -tire.max_drive_force * 0.5
        end
    end

    -- Step 2: drive impulse (force -> impulse, dt-scaled)
    local speed_factor = current_speed / 120.0
    local di_x = (force * dt) * forward[1]
    local di_y = (force * dt) * forward[2]
    local di_len = math.sqrt(di_x * di_x + di_y * di_y)
    if di_len > tire.max_lateral_impulse then
        local s = tire.max_lateral_impulse / di_len
        di_x, di_y = di_x * s, di_y * s
    end

    -- Step 3: lateral friction impulse (speed-dependent grip)
    local lat_vel = get_lateral_velocity(body)
    local mass = b2d.body_get_mass(body)
    local lfi_x = -mass * lat_vel[1]
    local lfi_y = -mass * lat_vel[2]

    local lat_available = tire.max_lateral_impulse * 2.0 * speed_factor
    if lat_available < 0.5 * tire.max_lateral_impulse then
        lat_available = 0.5 * tire.max_lateral_impulse
    end
    local lfi_len = math.sqrt(lfi_x * lfi_x + lfi_y * lfi_y)
    if lfi_len > lat_available then
        local s = lat_available / lfi_len
        lfi_x, lfi_y = lfi_x * s, lfi_y * s
    end

    -- Step 4: combine, cap, apply
    local ix = di_x + lfi_x
    local iy = di_y + lfi_y
    local i_len = math.sqrt(ix * ix + iy * iy)
    if i_len > tire.max_lateral_impulse then
        local s = tire.max_lateral_impulse / i_len
        ix, iy = ix * s, iy * s
    end

    b2d.body_apply_linear_impulse_to_center(body,
        { traction * ix, traction * iy }, true)
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
    chain_ids = {}
    track_body_id = nil
    water_zone_verts = {}
    dir_up = false
    dir_down = false
    dir_left = false
    dir_right = false
    follow_car = true

    -- Zero gravity
    b2d.world_set_gravity(world_id, { 0, 0 })

    -- Track body (static, at origin since data is pre-transformed to world coords)
    local track_def = b2d.default_body_def()
    track_def.position = { 0, 0 }
    track_body_id = b2d.create_body(world_id, track_def)

    -- Track walls (chain shapes)
    -- Box2D v3 chains are one-sided: CCW winding = normal points outward.
    -- Outer wall needs CW (normal inward) to block car from leaving.
    -- Inner walls need CCW (normal outward) to block car from entering.
    local max_wall_area = 0
    local outer_wall_idx = 1
    for i, wall_verts in ipairs(track_data.walls) do
        local area = math.abs(signed_area(wall_verts))
        if area > max_wall_area then
            max_wall_area = area
            outer_wall_idx = i
        end
    end

    for i, wall_verts in ipairs(track_data.walls) do
        local verts = wall_verts
        local area = signed_area(verts)
        if i == outer_wall_idx then
            -- Outer wall: ensure CW (area > 0 means CCW, reverse it)
            if area > 0 then
                local rev = {}
                for j = #verts, 1, -1 do rev[#rev + 1] = verts[j] end
                verts = rev
            end
        else
            -- Inner wall: ensure CCW (area < 0 means CW, reverse it)
            if area < 0 then
                local rev = {}
                for j = #verts, 1, -1 do rev[#rev + 1] = verts[j] end
                verts = rev
            end
        end
        local chain_def = b2d.default_chain_def()
        chain_def.points = verts
        chain_def.is_loop = true
        chain_def.filter = car_filter
        local chain_id = b2d.create_chain(track_body_id, chain_def)
        b2d.chain_set_friction(chain_id, 0.1)
        b2d.chain_set_restitution(chain_id, 0.1)
        table.insert(chain_ids, chain_id)
    end

    -- Water zones (sensor polygons on ground body for traction detection)
    for _, zone_verts in ipairs(track_data.water_zones) do
        local zone_shape_def = b2d.default_shape_def()
        zone_shape_def.is_sensor = true
        zone_shape_def.enable_sensor_events = true
        local hull = b2d.compute_hull(zone_verts, #zone_verts)
        local zone_sid = b2d.create_polygon_shape(ground_id, zone_shape_def,
            b2d.make_polygon(hull, 0))
        ground_areas[shape_key(zone_sid)] = { friction_modifier = 1.0, drag_modifier = 30.0 }
        table.insert(water_zone_verts, zone_verts)
    end

    -- Barrels (dynamic circles)
    local barrel_shape_def = b2d.default_shape_def()
    barrel_shape_def.density = 5.0
    barrel_shape_def.filter = car_filter
    local barrel_mat = b2d.default_surface_material()
    barrel_mat.friction = 0.8
    barrel_shape_def.material = barrel_mat
    for _, pos in ipairs(track_data.barrels) do
        local barrel_def = b2d.default_body_def()
        barrel_def.type = b2d.BodyType.DYNAMIC_BODY
        barrel_def.position = pos
        barrel_def.linear_damping = 10.0
        barrel_def.angular_damping = 10.0
        local barrel = b2d.create_body(world_id, barrel_def)
        b2d.create_circle_shape(barrel, barrel_shape_def,
            b2d.Circle({ center = { 0, 0 }, radius = 2.0 }))
        table.insert(body_entries, { body_id = barrel, color = { 0.6, 0.4, 0.2 } })
    end

    -- Chassis: original iforce2d 8-vertex car polygon
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 0 }
    body_def.angular_damping = 5.0
    body_def.enable_sleep = false
    chassis_id = b2d.create_body(world_id, body_def)

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

    -- Race track tire parameters (iforce2d_TopdownCarRaceTrack.h):
    -- Back:  maxForward=300, maxBackward=-40, maxDrive=950, maxLateral=9
    -- Front: maxForward=300, maxBackward=-40, maxDrive=400, maxLateral=9

    -- Back left tire
    local bl = create_tire(world_id, 300, -40, 950, 9)
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
    local br = create_tire(world_id, 300, -40, 950, 9)
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
    local fl = create_tire(world_id, 300, -40, 400, 9)
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
    local fr = create_tire(world_id, 300, -40, 400, 9)
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
        camera_ref.zoom = 80
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

        update_tire_friction(tire, dt)
        update_tire_drive(tire, dt)
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
    -- Draw track walls (chain segments)
    for _, chain_id in ipairs(chain_ids) do
        if b2d.chain_is_valid(chain_id) then
            local segments = b2d.chain_get_segments(chain_id)
            for _, seg_shape in ipairs(segments) do
                local seg = b2d.shape_get_chain_segment(seg_shape)
                draw.line(seg.segment.point1[1], seg.segment.point1[2],
                    seg.segment.point2[1], seg.segment.point2[2],
                    0.5, 0.5, 0.5)
            end
        end
    end

    -- Draw water zones (blue outlines)
    for _, verts in ipairs(water_zone_verts) do
        draw.polygon_outline(verts, 0.2, 0.4, 0.8)
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
        imgui.text_unformatted(string.format("Tire %s traction: %.2f drag: %.1f",
            names[i] or i, tire.current_traction, tire.current_drag))
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
