-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local DEGTORAD = math.pi / 180

local scene = {}
scene.name = "One-Way Walls"
scene.description = "A/D=move, W=jump.\nPlatforms allow passage from below.\nUses PreSolve callback to disable contacts\nbased on relative velocity at contact points."

local world_ref
local ground_ref
local step_count = 0
local camera_ref

-- Platform shape ids -> used to identify platforms in PreSolve
local platform_shapes = {}
-- Platform shrink factor per shape: tostring(shape_id) -> shrink_by
local platform_shrink = {}
-- Foot sensor shape id
local foot_shape_id

-- Kinematic platform bodies
local kinematic_body_1
local kinematic_body_2

-- Rotating floor
local rotating_floor
local rotating_floor_timer = 0
local rotating_floor_turn_count = 0

-- Player
local player_body
local player_foot_body
local num_foot_contacts = 0
local jump_timeout = 0
local key_left = false
local key_right = false
local key_jump = false

-- Body ids for rendering
local body_entries = {}

-- Base platform vertices (shrinkBy=1)
local base_platform_verts = {
    { 0, -0.75 },
    { 2.5, -0.5 },
    { 2.5, 0.5 },
    { -2.5, 0.5 },
    { -2.5, -0.5 },
}

local function shape_key(shape_id)
    return tostring(shape_id)
end

local function make_platform_polygon(shrink_by)
    local scale = 1 / shrink_by
    local verts = {}
    for i, v in ipairs(base_platform_verts) do
        verts[i] = { v[1] * scale, v[2] * scale }
    end
    local hull = b2d.compute_hull(verts, #verts)
    return b2d.make_polygon(hull, 0)
end

local function is_platform_shape(shape_id)
    return platform_shrink[shape_key(shape_id)] ~= nil
end

local function is_foot_shape(shape_id)
    return foot_shape_id and shape_id == foot_shape_id
end

local function setup_one_way_wall(world_id, ground_id, body_type, pos, angle, shrink_by, color)
    shrink_by = shrink_by or 1
    color = color or { 0.5, 0.7, 0.5 }

    local platform_polygon = make_platform_polygon(shrink_by)

    local body_def = b2d.default_body_def()
    body_def.type = body_type
    body_def.position = pos
    body_def.rotation = b2d.make_rot(angle)
    local body = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.enable_pre_solve_events = true
    local mat = b2d.default_surface_material()
    mat.friction = 0.8
    shape_def.material = mat
    local sid = b2d.create_polygon_shape(body, shape_def, platform_polygon)

    table.insert(platform_shapes, sid)
    platform_shrink[shape_key(sid)] = shrink_by
    table.insert(body_entries, { body_id = body, color = color })

    return body
end

local function calculate_vertical_velocity_for_height(desired_height)
    if desired_height <= 0 then return 0 end

    local gravity = b2d.world_get_gravity(world_ref)
    local t = 1 / 60.0
    local step_gravity_y = t * t * gravity[2]

    local a = 0.5 / step_gravity_y
    local b_coeff = 0.5
    local c = desired_height

    local disc = b_coeff * b_coeff - 4 * a * c
    if disc < 0 then return 0 end

    local sol1 = (-b_coeff - math.sqrt(disc)) / (2 * a)
    local sol2 = (-b_coeff + math.sqrt(disc)) / (2 * a)

    local v = sol1
    if v < 0 then v = sol2 end

    return v * 60.0
end

local function update_kinematic_platforms()
    step_count = step_count + 1
    local theta = 0.025 * step_count

    -- Kinematic platform 1: circular orbit around (15, 15)
    local target1 = { 15 + 2 * math.sin(theta), 15 + 2.55 * math.cos(theta) }
    local pos1 = b2d.body_get_position(kinematic_body_1)
    b2d.body_set_linear_velocity(kinematic_body_1,
        { 60 * (target1[1] - pos1[1]), 60 * (target1[2] - pos1[2]) })

    -- Kinematic platform 2: vertical oscillation around y=20
    local target2 = { 15, 20 - 2.55 * math.cos(theta) }
    local pos2 = b2d.body_get_position(kinematic_body_2)
    b2d.body_set_linear_velocity(kinematic_body_2,
        { 60 * (target2[1] - pos2[1]), 60 * (target2[2] - pos2[2]) })
end

local function update_rotating_floor()
    rotating_floor_timer = rotating_floor_timer - 1
    if rotating_floor_timer < 0 then
        b2d.body_set_angular_velocity(rotating_floor, 0)
        rotating_floor_timer = 180 -- 3 second timeout
        rotating_floor_turn_count = rotating_floor_turn_count + 1
    elseif rotating_floor_timer < 70 then
        local target_angle = rotating_floor_turn_count * math.rad(180)
        local rot = b2d.body_get_rotation(rotating_floor)
        local current_angle = b2d.rot_get_angle(rot)
        local angle_diff = target_angle - current_angle
        if angle_diff < math.rad(2) then
            local pos = b2d.body_get_position(rotating_floor)
            b2d.body_set_transform(rotating_floor, pos, b2d.make_rot(target_angle))
            b2d.body_set_angular_velocity(rotating_floor, 0)
        else
            b2d.body_set_angular_velocity(rotating_floor, math.rad(180))
        end
    end
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    ground_ref = ground_id
    step_count = 0
    platform_shapes = {}
    platform_shrink = {}
    body_entries = {}
    foot_shape_id = nil
    num_foot_contacts = 0
    jump_timeout = 0
    key_left = false
    key_right = false
    key_jump = false
    rotating_floor_timer = 0
    rotating_floor_turn_count = 0

    -- Remove default ground shapes and re-create boundary fence with friction
    local ground_shapes = b2d.body_get_shapes(ground_id)
    for _, s in ipairs(ground_shapes) do
        b2d.destroy_shape(s, true)
    end

    local shape_def = b2d.default_shape_def()
    local mat = b2d.default_surface_material()
    mat.friction = 0.8
    shape_def.material = mat
    local rot0 = b2d.make_rot(0)

    -- ground
    b2d.create_polygon_shape(ground_id, shape_def,
        b2d.make_offset_box(20, 1, { 0, -1 }, rot0))
    -- ceiling
    b2d.create_polygon_shape(ground_id, shape_def,
        b2d.make_offset_box(20, 1, { 0, 40 }, rot0))
    -- left wall
    b2d.create_polygon_shape(ground_id, shape_def,
        b2d.make_offset_box(1, 20, { -20, 20 }, rot0))
    -- right wall
    b2d.create_polygon_shape(ground_id, shape_def,
        b2d.make_offset_box(1, 20, { 20, 20 }, rot0))

    -- Static platforms to make a little maze (from C++ lines 113-131)
    local static_color = { 0.5, 0.7, 0.5 }
    local st = b2d.BodyType.STATIC_BODY
    setup_one_way_wall(world_id, ground_id, st, { 15, 12.55 }, 0 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -15, 2.5 }, 270 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -15, 7.5 }, 90 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -5, 7.5 }, 90 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 10, 7.5 }, 90 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -10, 2.5 }, 90 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 15, 2.5 }, -25 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 15, 7.5 }, 25 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 1, 2.5 }, 90 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -12.5, 5 }, 0 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -7.5, 5 }, 180 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -2.5, 5 }, 0 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 2.5, 5 }, 0 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -12.5, 10 }, 180 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -7.5, 10 }, 180 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -2.5, 10 }, 180 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 2.5, 10 }, 180 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { 7.5, 10 }, 180 * DEGTORAD, 1, static_color)

    -- Extra static platforms above
    setup_one_way_wall(world_id, ground_id, st, { 6.5, 27 }, 0 * DEGTORAD, 1, static_color)
    setup_one_way_wall(world_id, ground_id, st, { -16.5, 27 }, 0 * DEGTORAD, 1, static_color)

    -- Cart on prismatic joint
    local cart_color = { 0.7, 0.5, 0.5 }
    local cart_body = setup_one_way_wall(world_id, ground_id, b2d.BodyType.DYNAMIC_BODY,
        { 1.49, 27 }, 0 * DEGTORAD, 1, cart_color)
    local cart_edge1 = setup_one_way_wall(world_id, ground_id, b2d.BodyType.DYNAMIC_BODY,
        { 1.49 + 2.375, 27.5 + (2.5 / 4.0) }, 90 * DEGTORAD, 4, cart_color)
    local cart_edge2 = setup_one_way_wall(world_id, ground_id, b2d.BodyType.DYNAMIC_BODY,
        { 1.49 - 2.375, 27.5 + (2.5 / 4.0) }, 270 * DEGTORAD, 4, cart_color)

    -- Weld cart edges to cart body
    local weld_def = b2d.default_weld_joint_def()
    weld_def.body_id_a = cart_body
    weld_def.body_id_b = cart_edge1
    local edge1_pos = b2d.body_get_position(cart_edge1)
    weld_def.local_anchor_a = b2d.body_get_local_point(cart_body, edge1_pos)
    weld_def.local_anchor_b = { 0, 0 }
    b2d.create_weld_joint(world_id, weld_def)

    weld_def = b2d.default_weld_joint_def()
    weld_def.body_id_a = cart_body
    weld_def.body_id_b = cart_edge2
    local edge2_pos = b2d.body_get_position(cart_edge2)
    weld_def.local_anchor_a = b2d.body_get_local_point(cart_body, edge2_pos)
    weld_def.local_anchor_b = { 0, 0 }
    b2d.create_weld_joint(world_id, weld_def)

    -- Prismatic joint for cart
    local pris_def = b2d.default_prismatic_joint_def()
    pris_def.body_id_a = ground_id
    pris_def.body_id_b = cart_body
    pris_def.local_anchor_a = { 1.49, 27 }
    pris_def.local_anchor_b = { 0, 0 }
    pris_def.local_axis_a = { -1, 0 }
    pris_def.enable_limit = true
    pris_def.lower_translation = 0
    pris_def.upper_translation = 11.5 + 1.5 - 0.02
    pris_def.collide_connected = true
    b2d.create_prismatic_joint(world_id, pris_def)

    -- Kinematic moving platforms
    local kin_color = { 0.5, 0.5, 0.8 }
    kinematic_body_1 = setup_one_way_wall(world_id, ground_id,
        b2d.BodyType.KINEMATIC_BODY, { 15, 15 }, 0, 1, kin_color)
    kinematic_body_2 = setup_one_way_wall(world_id, ground_id,
        b2d.BodyType.KINEMATIC_BODY, { 15, 20 }, 0, 1, kin_color)

    -- Rotating floor section
    local rot_color = { 0.5, 0.8, 0.5 }
    rotating_floor = setup_one_way_wall(world_id, ground_id,
        b2d.BodyType.KINEMATIC_BODY, { 7.5, 5 }, 0, 1, rot_color)

    -- Swinging wall (dynamic with revolute joint)
    local swing_color = { 0.8, 0.5, 0.5 }
    local swing_door = setup_one_way_wall(world_id, ground_id,
        b2d.BodyType.DYNAMIC_BODY, { -5, 2.5 }, 90 * DEGTORAD, 1, swing_color)
    local rev_def = b2d.default_revolute_joint_def()
    rev_def.body_id_a = ground_id
    rev_def.body_id_b = swing_door
    rev_def.local_anchor_a = { -5, 5 }
    rev_def.local_anchor_b = { 2.5, 0 }
    b2d.create_revolute_joint(world_id, rev_def)

    -- Swing bridge (10-piece chain)
    local bridge_color = { 0.6, 0.6, 0.5 }
    local last_chain_piece = nil
    for i = 0, 9 do
        local chain_piece = setup_one_way_wall(world_id, ground_id,
            b2d.BodyType.DYNAMIC_BODY, { 9.5 + i, 27.5 }, 0, 5, bridge_color)
        if last_chain_piece then
            local jdef = b2d.default_revolute_joint_def()
            jdef.body_id_a = last_chain_piece
            jdef.body_id_b = chain_piece
            jdef.local_anchor_a = { 0.5, 0 }
            jdef.local_anchor_b = { -0.5, 0 }
            b2d.create_revolute_joint(world_id, jdef)
        else
            local jdef = b2d.default_revolute_joint_def()
            jdef.body_id_a = ground_id
            jdef.body_id_b = chain_piece
            jdef.local_anchor_a = { 9, 27.375 }
            jdef.local_anchor_b = { -0.5, 0 }
            b2d.create_revolute_joint(world_id, jdef)
        end
        last_chain_piece = chain_piece
    end
    -- Anchor end of bridge to ground
    local end_jdef = b2d.default_revolute_joint_def()
    end_jdef.body_id_a = ground_id
    end_jdef.body_id_b = last_chain_piece
    end_jdef.local_anchor_a = { 19, 27.5 }
    end_jdef.local_anchor_b = { 0.5, 0 }
    b2d.create_revolute_joint(world_id, end_jdef)

    -- Player character
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.fixed_rotation = true
    body_def.position = { -17.5, 1.25 }
    player_body = b2d.create_body(world_id, body_def)

    shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    b2d.create_polygon_shape(player_body, shape_def, b2d.make_box(0.5, 0.75))
    table.insert(body_entries, { body_id = player_body, color = { 0.9, 0.3, 0.3 } })

    -- Foot sensor (circle)
    body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.fixed_rotation = true
    body_def.position = { -17.5, 0.5 }
    player_foot_body = b2d.create_body(world_id, body_def)

    shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    shape_def.enable_contact_events = true
    foot_shape_id = b2d.create_circle_shape(player_foot_body, shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = 0.5 }))
    table.insert(body_entries, { body_id = player_foot_body, color = { 0.9, 0.5, 0.5 } })

    -- Revolute joint connecting player body to foot
    local player_jdef = b2d.default_revolute_joint_def()
    player_jdef.body_id_a = player_body
    player_jdef.body_id_b = player_foot_body
    player_jdef.local_anchor_a = { 0, -0.75 }
    player_jdef.local_anchor_b = { 0, 0 }
    b2d.create_revolute_joint(world_id, player_jdef)

    -- PreSolve callback with shrinkBy support
    b2d.world_set_pre_solve_callback(world_id, function(shape_a, shape_b, manifold)
        local a_is = is_platform_shape(shape_a)
        local b_is = is_platform_shape(shape_b)

        -- If both are platforms, disable contact (avoids problems with swinging wall)
        if a_is and b_is then return false end

        local platform_shape, other_shape
        if a_is then
            platform_shape, other_shape = shape_a, shape_b
        elseif b_is then
            platform_shape, other_shape = shape_b, shape_a
        else
            -- Neither is a platform - check for foot contact tracking
            return true
        end

        local shrink = platform_shrink[shape_key(platform_shape)] or 1
        local platform_body = b2d.shape_get_body(platform_shape)
        local other_body = b2d.shape_get_body(other_shape)
        local count = b2d.manifold_point_count(manifold)

        local solid = false
        for i = 1, count do
            local pt = b2d.manifold_point(manifold, i)
            local vel_platform = b2d.body_get_world_point_velocity(platform_body, pt)
            local vel_other = b2d.body_get_world_point_velocity(other_body, pt)
            local rel_vel = b2d.body_get_local_vector(platform_body,
                { vel_other[1] - vel_platform[1], vel_other[2] - vel_platform[2] })

            if rel_vel[2] < -1 then
                solid = true
                break
            end
            if rel_vel[2] < 1 then
                local rel_point = b2d.body_get_local_point(platform_body, pt)
                local platform_face_y = 0.5 / shrink
                if rel_point[2] > platform_face_y - 0.05 then
                    solid = true
                    break
                end
            end
        end

        return solid
    end)

    -- Set initial velocity so first world_step sees correct kinematic motion
    update_kinematic_platforms()

    -- Initial camera position on player
    if camera_ref then
        local pos = b2d.body_get_position(player_body)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:update(dt)
    update_kinematic_platforms()
    update_rotating_floor()

    -- Track foot contacts via contact events
    local events = b2d.world_get_contact_events(world_ref)
    if events then
        if events.begin_events then
            for _, ev in ipairs(events.begin_events) do
                if is_foot_shape(ev.shape_id_a) or is_foot_shape(ev.shape_id_b) then
                    num_foot_contacts = num_foot_contacts + 1
                end
            end
        end
        if events.end_events then
            for _, ev in ipairs(events.end_events) do
                if is_foot_shape(ev.shape_id_a) or is_foot_shape(ev.shape_id_b) then
                    num_foot_contacts = num_foot_contacts - 1
                    if num_foot_contacts < 0 then num_foot_contacts = 0 end
                end
            end
        end
    end

    -- Player sideways movement
    local vel = b2d.body_get_linear_velocity(player_body)
    local desired_vel = 0
    if key_left then
        desired_vel = math.max(vel[1] - 0.5, -5.0)
    elseif key_right then
        desired_vel = math.min(vel[1] + 0.5, 5.0)
    end
    local vel_change = desired_vel - vel[1]
    local mass = b2d.body_get_mass(player_body)
    local impulse = mass * vel_change
    if num_foot_contacts < 1 then
        impulse = impulse * 0.1
    end
    local com = b2d.body_get_world_center_of_mass(player_body)
    b2d.body_apply_linear_impulse(player_body, { impulse, 0 }, com, true)

    -- Player jump
    jump_timeout = jump_timeout - 1
    if jump_timeout < 0 and num_foot_contacts > 0 and key_jump then
        jump_timeout = 15
        local jump_vel = calculate_vertical_velocity_for_height(6)
        b2d.body_set_linear_velocity(player_body, { vel[1], jump_vel })
        b2d.body_set_linear_velocity(player_foot_body, { vel[1], jump_vel })
    end

    -- Camera follow player
    if camera_ref and b2d.body_is_valid(player_body) then
        local pos = b2d.body_get_position(player_body)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:get_bodies()
    return body_entries
end

function scene:render_extra()
end

function scene:render_ui()
    imgui.text_unformatted("A/D: Move  W: Jump")
    imgui.separator()
    imgui.text_unformatted(string.format("Step: %d", step_count))
    imgui.text_unformatted(string.format("Platforms: %d", #platform_shapes))
    imgui.text_unformatted(string.format("Foot contacts: %d", num_foot_contacts))
    if b2d.body_is_valid(player_body) then
        local vel = b2d.body_get_linear_velocity(player_body)
        imgui.text_unformatted(string.format("Vel: (%.1f, %.1f)", vel[1], vel[2]))
    end
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.A then
            key_left = true
        elseif ev.key_code == app.Keycode.D then
            key_right = true
        elseif ev.key_code == app.Keycode.W then
            key_jump = true
        end
    elseif ev.type == app.EventType.KEY_UP then
        if ev.key_code == app.Keycode.A then
            key_left = false
        elseif ev.key_code == app.Keycode.D then
            key_right = false
        elseif ev.key_code == app.Keycode.W then
            key_jump = false
        end
    end
end

function scene:cleanup()
    if world_ref then
        b2d.world_set_pre_solve_callback(world_ref, nil)
    end
end

return scene
