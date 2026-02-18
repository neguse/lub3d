-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local gl = require("sokol.gl")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Projected Trajectory"
scene.description = "Rotating launcher with trajectory prediction.\nQ/W: Fire/Reset player  A/S: Speed +/-\nD/F: Fire/Reset computer  M: Move target"

-- Collision categories
local CAT_DEFAULT <const> = 0x0001
local CAT_PLAYER_PROJ <const> = 0x0002
local CAT_COMPUTER_PROJ <const> = 0x0004

local BALL_SIZE <const> = 0.25
local DT <const> = 1.0 / 60.0

-- State
local world_ref
local camera_ref
local ground_ref

local launcher_id
local revolute_joint_id
local little_box
local little_box2
local target_id

local launch_speed = 10.0
local firing = false
local firing2 = false

local mouse_x, mouse_y = 11, 22

-- basic trajectory 'point at timestep n' formula
local function get_trajectory_point(pos, vel, n)
    local gravity = b2d.world_get_gravity(world_ref)
    local step_vel_x = DT * vel[1]
    local step_vel_y = DT * vel[2]
    local step_grav_x = DT * DT * gravity[1]
    local step_grav_y = DT * DT * gravity[2]
    local factor = 0.5 * (n * n + n)
    return {
        pos[1] + n * step_vel_x + factor * step_grav_x,
        pos[2] + n * step_vel_y + factor * step_grav_y,
    }
end

-- find out how many timesteps it will take for projectile to reach maximum height
local function get_timesteps_to_top(vel)
    local gravity = b2d.world_get_gravity(world_ref)
    local step_vel_y = DT * vel[2]
    local step_grav_y = DT * DT * gravity[2]
    return -step_vel_y / step_grav_y - 1
end

-- find out the maximum height for this parabola
local function get_max_height(pos, vel)
    if vel[2] < 0 then
        return pos[2]
    end
    local gravity = b2d.world_get_gravity(world_ref)
    local step_vel_y = DT * vel[2]
    local step_grav_y = DT * DT * gravity[2]
    local n = -step_vel_y / step_grav_y - 1
    return pos[2] + n * step_vel_y + 0.5 * (n * n + n) * step_grav_y
end

-- find the initial velocity necessary to reach a specified maximum height
local function calculate_vertical_velocity_for_height(desired_h)
    if desired_h <= 0 then return 0 end
    local gravity = b2d.world_get_gravity(world_ref)
    local step_grav_y = DT * DT * gravity[2]
    -- quadratic equation setup (original formula)
    local a = 0.5 / step_grav_y
    local b = 0.5
    local c = desired_h
    local disc = b * b - 4 * a * c
    local sqrt_disc = math.sqrt(disc)
    local q1 = (-b - sqrt_disc) / (2 * a)
    local q2 = (-b + sqrt_disc) / (2 * a)
    local v = q1
    if v < 0 then v = q2 end
    return v * 60.0
end

-- returns the current top edge of the target tee
local function get_computer_target_position()
    local pos = b2d.body_get_position(target_id)
    return { pos[1], pos[2] + BALL_SIZE + 0.01 }
end

-- calculate how the computer should launch the ball with the current target location
local function get_computer_launch_velocity()
    local target_loc = get_computer_target_position()
    local vertical_velocity = calculate_vertical_velocity_for_height(target_loc[2] - 5)
    local starting_velocity = { 0, vertical_velocity }
    local timesteps_to_top = get_timesteps_to_top(starting_velocity)
    local target_edge_pos = b2d.body_get_position(target_id)[1]
    if target_edge_pos > 15 then
        target_edge_pos = target_edge_pos - BALL_SIZE
    else
        target_edge_pos = target_edge_pos + BALL_SIZE
    end
    local distance_to_target_edge = target_edge_pos - 15
    local horizontal_velocity = distance_to_target_edge / timesteps_to_top * 60.0
    return { horizontal_velocity, vertical_velocity }
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    ground_ref = ground_id
    firing = false
    firing2 = false
    launch_speed = 10.0
    mouse_x, mouse_y = 11, 22

    -- Set camera for the playfield (-20,0)-(20,40)
    if camera_ref then
        camera_ref.x = 0
        camera_ref.y = 20
        camera_ref.zoom = 22
    end

    -- Remove default ground shapes
    local ground_shapes = b2d.body_get_shapes(ground_id)
    for _, s in ipairs(ground_shapes) do
        b2d.destroy_shape(s, true)
    end

    -- Create walls/floor/ceiling on ground body
    -- ground body is at (0, -1), so local_center = world_center + (0, 1)
    local rot0 = b2d.make_rot(0)
    local shape_def = b2d.default_shape_def()

    -- Floor: world (0, 0) -> local (0, 1)
    b2d.create_polygon_shape(ground_id, shape_def, b2d.make_offset_box(20, 1, { 0, 1 }, rot0))
    -- Ceiling: world (0, 40) -> local (0, 41)
    b2d.create_polygon_shape(ground_id, shape_def, b2d.make_offset_box(20, 1, { 0, 41 }, rot0))
    -- Left wall: world (-20, 20) -> local (-20, 21)
    b2d.create_polygon_shape(ground_id, shape_def, b2d.make_offset_box(1, 20, { -20, 21 }, rot0))
    -- Right wall: world (20, 20) -> local (20, 21)
    b2d.create_polygon_shape(ground_id, shape_def, b2d.make_offset_box(1, 20, { 20, 21 }, rot0))

    -- Shelves with friction=0.95
    local shelf_def = b2d.default_shape_def()
    local shelf_mat = b2d.default_surface_material()
    shelf_mat.friction = 0.95
    shelf_def.material = shelf_mat
    -- Shelf 1: world (3, 35) -> local (3, 36)
    b2d.create_polygon_shape(ground_id, shelf_def, b2d.make_offset_box(1.5, 0.25, { 3, 36 }, rot0))
    -- Shelf 2: world (13, 30) -> local (13, 31)
    b2d.create_polygon_shape(ground_id, shelf_def, b2d.make_offset_box(1.5, 0.25, { 13, 31 }, rot0))

    -- Target (kinematic, diamond shape)
    local target_def = b2d.default_body_def()
    target_def.type = b2d.BodyType.KINEMATIC_BODY
    target_def.position = { 11, 22 }
    target_id = b2d.create_body(world_id, target_def)
    local w = BALL_SIZE
    local target_shape_def = b2d.default_shape_def()
    target_shape_def.material = shelf_mat
    -- Triangle 1: (0, -2w), (w, 0), (0, -w)
    local tri1_verts = { { 0, -2 * w }, { w, 0 }, { 0, -w } }
    local hull1 = b2d.compute_hull(tri1_verts, 3)
    local tri1_poly = b2d.make_polygon(hull1, 0)
    b2d.create_polygon_shape(target_id, target_shape_def, tri1_poly)
    -- Triangle 2: (0, -2w), (0, -w), (-w, 0)
    local tri2_verts = { { 0, -2 * w }, { 0, -w }, { -w, 0 } }
    local hull2 = b2d.compute_hull(tri2_verts, 3)
    local tri2_poly = b2d.make_polygon(hull2, 0)
    b2d.create_polygon_shape(target_id, target_shape_def, tri2_poly)

    -- Launcher (dynamic circle, revolute joint to ground)
    local launcher_def = b2d.default_body_def()
    launcher_def.type = b2d.BodyType.DYNAMIC_BODY
    launcher_def.position = { -15, 5 }
    launcher_id = b2d.create_body(world_id, launcher_def)
    local launcher_shape_def = b2d.default_shape_def()
    launcher_shape_def.density = 1.0
    launcher_shape_def.material = shelf_mat
    b2d.create_circle_shape(launcher_id, launcher_shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = 2 }))

    -- Revolute joint: ground <-> launcher
    local rj_def = b2d.default_revolute_joint_def()
    rj_def.body_id_a = ground_id
    rj_def.body_id_b = launcher_id
    -- ground body at (0,-1), launcher world pivot at (-15,5) -> ground local (-15,6)
    rj_def.local_anchor_a = { -15, 6 }
    rj_def.local_anchor_b = { 0, 0 }
    rj_def.enable_motor = true
    rj_def.motor_speed = 0
    rj_def.max_motor_torque = 250
    revolute_joint_id = b2d.create_revolute_joint(world_id, rj_def)

    -- Player projectile (littleBox)
    local box_def = b2d.default_body_def()
    box_def.type = b2d.BodyType.DYNAMIC_BODY
    box_def.position = { 0, -5 }
    little_box = b2d.create_body(world_id, box_def)
    local box_shape_def = b2d.default_shape_def()
    box_shape_def.density = 1.0
    box_shape_def.material = shelf_mat
    box_shape_def.filter = b2d.Filter({ category_bits = CAT_PLAYER_PROJ, mask_bits = 0xFFFF })
    b2d.create_polygon_shape(little_box, box_shape_def, b2d.make_box(0.5, 0.5))
    b2d.body_set_gravity_scale(little_box, 0)

    -- Computer projectile (littleBox2)
    local box2_def = b2d.default_body_def()
    box2_def.type = b2d.BodyType.DYNAMIC_BODY
    box2_def.position = { 0, -5 }
    little_box2 = b2d.create_body(world_id, box2_def)
    local box2_shape_def = b2d.default_shape_def()
    box2_shape_def.density = 1.0
    box2_shape_def.material = shelf_mat
    box2_shape_def.filter = b2d.Filter({ category_bits = CAT_COMPUTER_PROJ, mask_bits = 0xFFFF })
    b2d.create_circle_shape(little_box2, box2_shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = BALL_SIZE }))
    b2d.body_set_gravity_scale(little_box2, 0)
end

function scene:update(dt)
    -- Player projectile follows launcher tip when not firing
    if not firing then
        local start_pos = b2d.body_get_world_point(launcher_id, { 3, 0 })
        local rot = b2d.body_get_rotation(launcher_id)
        b2d.body_set_transform(little_box, start_pos, rot)
    end
end

function scene:get_bodies()
    local entries = {}
    table.insert(entries, { body_id = launcher_id, color = { 0.6, 0.6, 0.8 } })
    table.insert(entries, { body_id = little_box, color = { 0.2, 0.9, 0.2 } })
    table.insert(entries, { body_id = little_box2, color = { 0.9, 0.5, 0.2 } })
    table.insert(entries, { body_id = target_id, color = { 0.9, 0.2, 0.2 } })
    return entries
end

function scene:render_extra()
    local start_pos = b2d.body_get_world_point(launcher_id, { 3, 0 })
    local start_vel = b2d.body_get_world_vector(launcher_id, { launch_speed, 0 })

    -- Raycast filter: skip player projectile
    local ray_filter = b2d.default_query_filter()
    ray_filter.mask_bits = 0xFFF9 -- ~(CAT_PLAYER_PROJ | CAT_COMPUTER_PROJ)

    -- 1. Yellow trajectory line (GL_LINES pairs = dashed line)
    local hit_point = nil
    gl.begin_lines()
    gl.c3f(1, 1, 0)
    local last_tp = { start_pos[1], start_pos[2] }
    for n = 0, 299 do
        local tp = get_trajectory_point(start_pos, start_vel, n)
        if n > 0 then
            local result = b2d.world_cast_ray_closest(world_ref, last_tp,
                { tp[1] - last_tp[1], tp[2] - last_tp[2] }, ray_filter)
            if result and result.hit then
                hit_point = result.point
                gl.v2f(result.point[1], result.point[2])
                break
            end
        end
        gl.v2f(tp[1], tp[2])
        last_tp = tp
    end
    gl["end"]()

    -- 2. Cyan dot at raycast hit point
    if hit_point then
        draw.point(hit_point[1], hit_point[2], 0.3, 0, 1, 1)
    end

    -- 3. Green dot at littleBox position (always shown)
    local little_box_pos = b2d.body_get_position(little_box)
    draw.point(little_box_pos[1], little_box_pos[2], 0.3, 0, 1, 0)

    -- 4. White semi-transparent max height line
    local max_h = get_max_height(start_pos, start_vel)
    gl.begin_lines()
    gl.c4f(1, 1, 1, 0.5)
    gl.v2f(-20, max_h)
    gl.v2f(20, max_h)
    gl["end"]()

    -- 5. Computer launch velocity vector (red->green gradient, 0.1 scale)
    local comp_vel = get_computer_launch_velocity()
    local comp_start_x, comp_start_y = 15, 5
    local end_x = comp_start_x + 0.1 * comp_vel[1]
    local end_y = comp_start_y + 0.1 * comp_vel[2]
    gl.begin_lines()
    gl.c3f(1, 0, 0)
    gl.v2f(comp_start_x, comp_start_y)
    gl.c3f(0, 1, 0)
    gl.v2f(end_x, end_y)
    gl["end"]()

    -- 6. Computer projectile stays at spawn when not firing (after drawing, like original)
    if not firing2 then
        b2d.body_set_transform(little_box2, { 15, 5 }, b2d.make_rot(0))
    end
end

function scene:render_ui()
    imgui.text_unformatted("Rotate the circle on the left to change launch direction")
    imgui.text_unformatted("Use a/s to change the launch speed")
    imgui.text_unformatted("Use q/w to launch and reset the projectile")
    imgui.text_unformatted("")
    imgui.text_unformatted("Use d/f to launch and reset the computer controlled projectile")
    imgui.text_unformatted("Hold down m and use the left mouse button to move the computer's target")
end

function scene:event(ev)
    if ev.type == app.EventType.MOUSE_MOVE then
        if camera_ref then
            mouse_x, mouse_y = camera_ref.screen_to_world(ev.mouse_x, ev.mouse_y)
        end
    end

    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.Q then
            -- Fire player projectile (no guard - allows re-fire)
            b2d.body_set_awake(little_box, true)
            b2d.body_set_gravity_scale(little_box, 1)
            b2d.body_set_angular_velocity(little_box, 0)
            local pos = b2d.body_get_world_point(launcher_id, { 3, 0 })
            local rot = b2d.body_get_rotation(launcher_id)
            b2d.body_set_transform(little_box, pos, rot)
            local vel = b2d.body_get_world_vector(launcher_id, { launch_speed, 0 })
            b2d.body_set_linear_velocity(little_box, vel)
            firing = true
        elseif ev.key_code == app.Keycode.W then
            -- Reset player projectile
            b2d.body_set_gravity_scale(little_box, 0)
            b2d.body_set_angular_velocity(little_box, 0)
            firing = false
        elseif ev.key_code == app.Keycode.A then
            launch_speed = launch_speed * 1.02
        elseif ev.key_code == app.Keycode.S then
            launch_speed = launch_speed * 0.98
        elseif ev.key_code == app.Keycode.D then
            -- Fire computer projectile (no guard - allows re-fire)
            b2d.body_set_awake(little_box2, true)
            b2d.body_set_gravity_scale(little_box2, 1)
            b2d.body_set_angular_velocity(little_box2, 0)
            local vel = get_computer_launch_velocity()
            b2d.body_set_transform(little_box2, { 15, 5 }, b2d.make_rot(0))
            b2d.body_set_linear_velocity(little_box2, vel)
            firing2 = true
        elseif ev.key_code == app.Keycode.F then
            -- Reset computer projectile
            b2d.body_set_gravity_scale(little_box2, 0)
            b2d.body_set_angular_velocity(little_box2, 0)
            firing2 = false
        elseif ev.key_code == app.Keycode.M then
            -- Move target to mouse position
            b2d.body_set_transform(target_id, { mouse_x, mouse_y }, b2d.make_rot(0))
        end
    end
end

function scene:cleanup() end

return scene
