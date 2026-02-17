-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Sticky Projectiles"
scene.description = "Left-drag launcher to aim, Q to fire.\nA/S to change speed.\nArrows stick on contact via weld joint."

local world_ref
local body_entries = {}
local arrows = {} -- { body_id, flying, joint_id }
local drag_constant = 0.1
local step_count = 0
local camera_ref
local camera_initialized = false

-- Target hardness: approach_speed must exceed this to stick
local HARDNESS_STRAW <const> = 1
local HARDNESS_WOOD <const> = 5
local HARDNESS_STEEL <const> = 100
local target_hardness = {} -- body_id -> hardness value

-- Launcher state
local launcher_body
local loaded_arrow
local launch_speed = 50
local kinematic_body

-- Diamond arrow shape vertices (original iforce2d)
local arrow_verts = {
    { -1.4, 0 },
    { 0, -0.1 },
    { 0.6, 0 },
    { 0, 0.1 },
}

local function load_one_arrow(world_id)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 5 }
    body_def.angular_damping = 3.0
    body_def.gravity_scale = 0 -- until fired

    local body = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.enable_contact_events = true
    shape_def.enable_hit_events = true
    local hull = b2d.compute_hull(arrow_verts, #arrow_verts)
    b2d.create_polygon_shape(body, shape_def, b2d.make_polygon(hull, 0))

    loaded_arrow = body
    table.insert(body_entries, { body_id = body, color = { 0.9, 0.8, 0.2 } })
end

local function fire_arrow()
    if not loaded_arrow or not b2d.body_is_valid(loaded_arrow) then return end

    b2d.body_set_awake(loaded_arrow, true)
    b2d.body_set_gravity_scale(loaded_arrow, 1)
    b2d.body_set_angular_velocity(loaded_arrow, 0)

    -- Position at launcher tip
    local tip = b2d.body_get_world_point(launcher_body, { 3, 0 })
    local rot = b2d.body_get_rotation(launcher_body)
    b2d.body_set_transform(loaded_arrow, tip, rot)

    -- Launch in launcher's direction
    local vel = b2d.body_get_world_vector(launcher_body, { launch_speed, 0 })
    b2d.body_set_linear_velocity(loaded_arrow, vel)

    table.insert(arrows, { body_id = loaded_arrow, flying = true, joint_id = nil })
    loaded_arrow = nil
    load_one_arrow(world_ref)
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    body_entries = {}
    arrows = {}
    target_hardness = {}
    step_count = 0
    camera_initialized = false
    loaded_arrow = nil
    launch_speed = 50

    -- Joint anchor body at origin (equivalent to m_groundBody in original)
    local anchor_def = b2d.default_body_def()
    anchor_def.position = { 0, 0 }
    local joint_anchor = b2d.create_body(world_id, anchor_def)

    -- Wall shape def (shared)
    local wall_shape = b2d.default_shape_def()
    wall_shape.enable_contact_events = true
    wall_shape.enable_hit_events = true

    -- Ground: box(50, 1) at y=0, wood
    local gw_def = b2d.default_body_def()
    gw_def.position = { 0, 0 }
    local ground_wall = b2d.create_body(world_id, gw_def)
    b2d.create_polygon_shape(ground_wall, wall_shape, b2d.make_box(50, 1))
    target_hardness[ground_wall] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = ground_wall, color = { 0.4, 0.4, 0.4 } })

    -- Framework ground also gets hardness
    target_hardness[ground_id] = HARDNESS_WOOD

    -- Ceiling: box(50, 1) at y=100, wood
    local ceil_def = b2d.default_body_def()
    ceil_def.position = { 0, 100 }
    local ceiling = b2d.create_body(world_id, ceil_def)
    b2d.create_polygon_shape(ceiling, wall_shape, b2d.make_box(50, 1))
    target_hardness[ceiling] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = ceiling, color = { 0.4, 0.4, 0.4 } })

    -- Left wall: box(1, 50) at (-50, 50), steel
    local lw_def = b2d.default_body_def()
    lw_def.position = { -50, 50 }
    local left_wall = b2d.create_body(world_id, lw_def)
    b2d.create_polygon_shape(left_wall, wall_shape, b2d.make_box(1, 50))
    target_hardness[left_wall] = HARDNESS_STEEL
    table.insert(body_entries, { body_id = left_wall, color = { 0.5, 0.5, 0.6 } })

    -- Right wall: box(1, 50) at (50, 50), wood
    local rw_def = b2d.default_body_def()
    rw_def.position = { 50, 50 }
    local right_wall = b2d.create_body(world_id, rw_def)
    b2d.create_polygon_shape(right_wall, wall_shape, b2d.make_box(1, 50))
    target_hardness[right_wall] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = right_wall, color = { 0.4, 0.4, 0.4 } })

    -- Target shape def (shared, density=2)
    local target_shape = b2d.default_shape_def()
    target_shape.density = 2
    target_shape.enable_contact_events = true
    target_shape.enable_hit_events = true

    -- Straw target: static, (0, 5), angle -10°
    local straw_def = b2d.default_body_def()
    straw_def.position = { 0, 5 }
    straw_def.rotation = b2d.make_rot(-10 * math.pi / 180)
    local straw = b2d.create_body(world_id, straw_def)
    b2d.create_polygon_shape(straw, target_shape, b2d.make_box(0.5, 4))
    target_hardness[straw] = HARDNESS_STRAW
    table.insert(body_entries, { body_id = straw, color = { 0.8, 0.7, 0.3 } })

    -- Wood target 1: dynamic, (15, 20)
    local w1_def = b2d.default_body_def()
    w1_def.type = b2d.BodyType.DYNAMIC_BODY
    w1_def.position = { 15, 20 }
    local wood1 = b2d.create_body(world_id, w1_def)
    b2d.create_polygon_shape(wood1, target_shape, b2d.make_box(0.5, 4))
    target_hardness[wood1] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = wood1, color = { 0.6, 0.4, 0.2 } })

    -- Distance joint for wood1
    local dist_def = b2d.default_distance_joint_def()
    dist_def.body_id_a = joint_anchor
    dist_def.body_id_b = wood1
    dist_def.local_anchor_a = { 15, 25 }
    dist_def.local_anchor_b = { 0, 3.5 }
    b2d.create_distance_joint(world_id, dist_def)

    -- Wood target 2: dynamic, (25, 40)
    local w2_def = b2d.default_body_def()
    w2_def.type = b2d.BodyType.DYNAMIC_BODY
    w2_def.position = { 25, 40 }
    local wood2 = b2d.create_body(world_id, w2_def)
    b2d.create_polygon_shape(wood2, target_shape, b2d.make_box(0.5, 4))
    target_hardness[wood2] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = wood2, color = { 0.6, 0.4, 0.2 } })

    -- Distance joint for wood2
    dist_def = b2d.default_distance_joint_def()
    dist_def.body_id_a = joint_anchor
    dist_def.body_id_b = wood2
    dist_def.local_anchor_a = { 25, 45 }
    dist_def.local_anchor_b = { 0, 3.5 }
    b2d.create_distance_joint(world_id, dist_def)

    -- Kinematic target: (40, 50), wood
    local kin_def = b2d.default_body_def()
    kin_def.type = b2d.BodyType.KINEMATIC_BODY
    kin_def.position = { 40, 50 }
    kinematic_body = b2d.create_body(world_id, kin_def)
    b2d.create_polygon_shape(kinematic_body, target_shape, b2d.make_box(0.5, 4))
    target_hardness[kinematic_body] = HARDNESS_WOOD
    table.insert(body_entries, { body_id = kinematic_body, color = { 0.6, 0.4, 0.2 } })

    -- Apple: dynamic, (40, 54.75), circle r=0.75, density=10
    local apple_def = b2d.default_body_def()
    apple_def.type = b2d.BodyType.DYNAMIC_BODY
    apple_def.position = { 40, 54.75 }
    local apple = b2d.create_body(world_id, apple_def)
    local apple_shape = b2d.default_shape_def()
    apple_shape.density = 10
    apple_shape.enable_contact_events = true
    apple_shape.enable_hit_events = true
    b2d.create_circle_shape(apple, apple_shape,
        b2d.Circle({ center = { 0, 0 }, radius = 0.75 }))
    target_hardness[apple] = HARDNESS_STRAW
    table.insert(body_entries, { body_id = apple, color = { 0.9, 0.2, 0.2 } })

    -- Launcher: dynamic circle at (-35, 5)
    local launch_def = b2d.default_body_def()
    launch_def.type = b2d.BodyType.DYNAMIC_BODY
    launch_def.position = { -35, 5 }
    launcher_body = b2d.create_body(world_id, launch_def)
    local launch_shape = b2d.default_shape_def()
    launch_shape.density = 1
    b2d.create_circle_shape(launcher_body, launch_shape,
        b2d.Circle({ center = { 0, 0 }, radius = 2 }))
    table.insert(body_entries, { body_id = launcher_body, color = { 0.4, 0.6, 0.8 } })

    -- Revolute joint to pin launcher
    local rev_def = b2d.default_revolute_joint_def()
    rev_def.body_id_a = joint_anchor
    rev_def.body_id_b = launcher_body
    rev_def.local_anchor_a = { -35, 5 }
    rev_def.local_anchor_b = { 0, 0 }
    rev_def.enable_motor = true
    rev_def.max_motor_torque = 250
    rev_def.motor_speed = 0
    b2d.create_revolute_joint(world_id, rev_def)

    -- Load first arrow
    load_one_arrow(world_id)
end

function scene:update(dt)
    -- Set camera on first frame (after framework's camera.reset())
    if not camera_initialized and camera_ref then
        camera_ref.x = 0
        camera_ref.y = 50
        camera_ref.zoom = 60
        camera_initialized = true
    end

    step_count = step_count + 1

    -- Position loaded arrow at launcher tip
    if loaded_arrow and b2d.body_is_valid(loaded_arrow) then
        local tip = b2d.body_get_world_point(launcher_body, { 3.5, 0 })
        local rot = b2d.body_get_rotation(launcher_body)
        b2d.body_set_transform(loaded_arrow, tip, rot)
    end

    -- Apply aerodynamic drag to flying arrows
    for _, arrow in ipairs(arrows) do
        if arrow.flying and b2d.body_is_valid(arrow.body_id) then
            local vel = b2d.body_get_linear_velocity(arrow.body_id)
            local speed = math.sqrt(vel[1] * vel[1] + vel[2] * vel[2])
            if speed > 0.1 then
                local mass = b2d.body_get_mass(arrow.body_id)
                local fd_x, fd_y = vel[1] / speed, vel[2] / speed
                local pointing = b2d.body_get_world_vector(arrow.body_id, { 1, 0 })
                local dot = fd_x * pointing[1] + fd_y * pointing[2]
                local drag_mag = (1 - math.abs(dot)) * speed * speed * drag_constant * mass
                local tail = b2d.body_get_world_point(arrow.body_id, { -1.4, 0 })
                b2d.body_apply_force(arrow.body_id,
                    { -drag_mag * fd_x, -drag_mag * fd_y },
                    tail, true)
            end
        end
    end

    -- Move kinematic target (sine wave, matching original)
    if kinematic_body and b2d.body_is_valid(kinematic_body) then
        local pos = b2d.body_get_position(kinematic_body)
        local new_y = 50 + math.sin(step_count * 0.01) * 25
        b2d.body_set_linear_velocity(kinematic_body, { 40 - pos[1], new_y - pos[2] })
    end

    -- Check hit events for sticking
    local events = b2d.world_get_contact_events(world_ref)
    if events and events.hit_events then
        for _, ev in ipairs(events.hit_events) do
            local body_a = b2d.shape_get_body(ev.shape_id_a)
            local body_b = b2d.shape_get_body(ev.shape_id_b)
            local hardness_a = target_hardness[body_a]
            local hardness_b = target_hardness[body_b]

            -- Skip circle-target contacts (apple/launcher exclusion)
            local type_a = b2d.shape_get_type(ev.shape_id_a)
            local type_b = b2d.shape_get_type(ev.shape_id_b)
            if (hardness_b and type_a == b2d.ShapeType.CIRCLE_SHAPE) or
                (hardness_a and type_b == b2d.ShapeType.CIRCLE_SHAPE) then
                goto continue_hit
            end

            local target_body, arrow_body
            local approach = ev.approach_speed or 0

            if hardness_a and approach > hardness_a then
                target_body = body_a
                arrow_body = body_b
            elseif hardness_b and approach > hardness_b then
                target_body = body_b
                arrow_body = body_a
            end

            if target_body and arrow_body then
                -- Create weld joint at arrow tip
                local weld_def = b2d.default_weld_joint_def()
                weld_def.body_id_a = target_body
                weld_def.body_id_b = arrow_body
                local tip_world = b2d.body_get_world_point(arrow_body, { 0.6, 0 })
                weld_def.local_anchor_a = b2d.body_get_local_point(target_body, tip_world)
                weld_def.local_anchor_b = { 0.6, 0 }
                local rot_a = b2d.body_get_rotation(target_body)
                local rot_b = b2d.body_get_rotation(arrow_body)
                local angle_a = b2d.rot_get_angle(rot_a)
                local angle_b = b2d.rot_get_angle(rot_b)
                weld_def.reference_angle = angle_b - angle_a
                local joint = b2d.create_weld_joint(world_ref, weld_def)

                -- Mark arrow as stuck
                for _, arrow in ipairs(arrows) do
                    if arrow.body_id == arrow_body then
                        arrow.flying = false
                        arrow.joint_id = joint
                        break
                    end
                end
            end
            ::continue_hit::
        end
    end
end

function scene:get_bodies()
    return body_entries
end

function scene:render_extra() end

function scene:render_ui()
    imgui.text_unformatted(string.format("Launch speed: %.1f", launch_speed))
    imgui.text_unformatted(string.format("Arrows: %d", #arrows))
    imgui.separator()
    imgui.text_unformatted("Q: fire  A/S: change speed")
    imgui.text_unformatted("Hardness: straw=1, wood=5, steel=100")
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.Q or ev.key_code == app.Keycode.F then
            fire_arrow()
        elseif ev.key_code == app.Keycode.A then
            launch_speed = launch_speed * 1.02
        elseif ev.key_code == app.Keycode.S then
            launch_speed = launch_speed * 0.98
        end
    end
end

function scene:cleanup() end

return scene
