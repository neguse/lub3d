-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Buoyancy Boat"
scene.description = "Boat with engine drive and buoyancy.\nA = drive forward.\nChain + buoy trail behind.\nWorld wraps at x > 450."

local world_ref
local camera_ref
local body_entries = {}
local all_dynamic_bodies = {} -- for world wrap

local water_sensor_id
local submerged_bodies = {} -- body_id -> true

local water_y = 10.0
local fluid_density = 2.0

local drag_mod = 0.25
local lift_mod = 0.25
local max_drag = 2000
local max_lift = 500

local CIRCLE_VERTS <const> = 16
local MAX_BUBBLES <const> = 32

local boat_body
local boat_drive = false

local bubble_bodies = {} -- ring buffer
local steps_since_last_bubble = 0
local next_bubble_index = 1

local ground_points = {} -- 100 points for visual bumps

local debug_clipped_polygons = {}

---------------------------------------------------------------------
-- Sutherland-Hodgman polygon clipping helpers
---------------------------------------------------------------------

local function find_intersection_h(p1, p2, clip_y)
    local dx = p2[1] - p1[1]
    local dy = p2[2] - p1[2]
    if math.abs(dy) < 1e-10 then return { p1[1], clip_y } end
    local t = (clip_y - p1[2]) / dy
    return { p1[1] + t * dx, clip_y }
end

local function clip_polygon_below(verts, clip_y)
    if #verts < 2 then return verts end
    local out = {}
    local prev = verts[#verts]
    local prev_inside = (prev[2] <= clip_y)

    for _, cur in ipairs(verts) do
        local cur_inside = (cur[2] <= clip_y)
        if cur_inside then
            if not prev_inside then
                table.insert(out, find_intersection_h(prev, cur, clip_y))
            end
            table.insert(out, cur)
        elseif prev_inside then
            table.insert(out, find_intersection_h(prev, cur, clip_y))
        end
        prev = cur
        prev_inside = cur_inside
    end
    return out
end

local function compute_centroid_and_area(verts)
    local n = #verts
    if n < 3 then return 0, 0, 0 end

    local area = 0
    local cx, cy = 0, 0

    for i = 1, n do
        local j = (i % n) + 1
        local cross = verts[i][1] * verts[j][2] - verts[j][1] * verts[i][2]
        area = area + cross
        cx = cx + (verts[i][1] + verts[j][1]) * cross
        cy = cy + (verts[i][2] + verts[j][2]) * cross
    end

    area = area * 0.5
    if math.abs(area) < 1e-10 then return 0, 0, 0 end

    cx = cx / (6 * area)
    cy = cy / (6 * area)
    return cx, cy, math.abs(area)
end

local function get_shape_world_vertices(shape_id, body_id)
    local pos = b2d.body_get_position(body_id)
    local rot = b2d.body_get_rotation(body_id)
    local cos_a, sin_a = rot[1], rot[2]

    local st = b2d.shape_get_type(shape_id)
    local verts = {}

    if st == b2d.ShapeType.POLYGON_SHAPE then
        local poly = b2d.shape_get_polygon(shape_id)
        for i = 1, poly.count do
            local lx, ly = poly.vertices[i][1], poly.vertices[i][2]
            local wx = pos[1] + lx * cos_a - ly * sin_a
            local wy = pos[2] + lx * sin_a + ly * cos_a
            table.insert(verts, { wx, wy })
        end
    elseif st == b2d.ShapeType.CIRCLE_SHAPE then
        local circle = b2d.shape_get_circle(shape_id)
        local ccx = pos[1] + circle.center[1] * cos_a - circle.center[2] * sin_a
        local ccy = pos[2] + circle.center[1] * sin_a + circle.center[2] * cos_a
        local r = circle.radius
        for i = 0, CIRCLE_VERTS - 1 do
            local a = (i / CIRCLE_VERTS) * math.pi * 2
            table.insert(verts, { ccx + math.cos(a) * r, ccy + math.sin(a) * r })
        end
    end

    return verts
end

---------------------------------------------------------------------
-- Helper: create polygon from vertices
---------------------------------------------------------------------

local function make_poly_from_verts(verts)
    local hull = b2d.compute_hull(verts, #verts)
    return b2d.make_polygon(hull, 0)
end

---------------------------------------------------------------------
-- World construction (from buoyancy2.cpp)
---------------------------------------------------------------------

local function create_boat_world(world_id)
    local bodies = {}

    -- body[0]: static anchor
    local bd = b2d.default_body_def()
    bd.position = { 1.4514, 16.7282 }
    bodies[0] = b2d.create_body(world_id, bd)

    -- body[1]: dynamic chain segment 1
    bd = b2d.default_body_def()
    bd.type = b2d.BodyType.DYNAMIC_BODY
    bd.position = { -6.4308, 15.6827 }
    bodies[1] = b2d.create_body(world_id, bd)
    local sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    b2d.create_polygon_shape(bodies[1], sd, b2d.make_box(0.0176, 0.5531))
    table.insert(body_entries, { body_id = bodies[1], color = { 0.6, 0.6, 0.6 } })
    table.insert(all_dynamic_bodies, bodies[1])

    -- body[2]: dynamic chain segment 2
    bd = b2d.default_body_def()
    bd.type = b2d.BodyType.DYNAMIC_BODY
    bd.position = { -6.4310, 14.6476 }
    bodies[2] = b2d.create_body(world_id, bd)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    b2d.create_polygon_shape(bodies[2], sd, b2d.make_box(0.0320, 0.5531))
    table.insert(body_entries, { body_id = bodies[2], color = { 0.6, 0.6, 0.6 } })
    table.insert(all_dynamic_bodies, bodies[2])

    -- body[3]: dynamic chain segment 3
    bd = b2d.default_body_def()
    bd.type = b2d.BodyType.DYNAMIC_BODY
    bd.position = { -6.4310, 13.6946 }
    bodies[3] = b2d.create_body(world_id, bd)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    b2d.create_polygon_shape(bodies[3], sd, b2d.make_box(0.0480, 0.4919))
    table.insert(body_entries, { body_id = bodies[3], color = { 0.6, 0.6, 0.6 } })
    table.insert(all_dynamic_bodies, bodies[3])

    -- body[4]: static empty
    bd = b2d.default_body_def()
    bd.position = { 248.5095, 0 }
    bodies[4] = b2d.create_body(world_id, bd)

    -- body[5]: dynamic buoy
    bd = b2d.default_body_def()
    bd.type = b2d.BodyType.DYNAMIC_BODY
    bd.position = { -2.2504, 14.0400 }
    bodies[5] = b2d.create_body(world_id, bd)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 65535 })
    sd.enable_sensor_events = true
    b2d.create_circle_shape(bodies[5], sd,
        b2d.Circle({ center = { 0, 0 }, radius = 0.5 }))
    table.insert(body_entries, { body_id = bodies[5], color = { 0.9, 0.2, 0.2 } })
    table.insert(all_dynamic_bodies, bodies[5])

    -- body[6]: static water sensor
    -- World extents: x=-600..600, y=-243..10
    bd = b2d.default_body_def()
    bd.position = { 237.3832, 1.7508 }
    bodies[6] = b2d.create_body(world_id, bd)
    sd = b2d.default_shape_def()
    sd.density = 2.0
    sd.is_sensor = true
    sd.enable_sensor_events = true
    sd.filter = b2d.Filter({ category_bits = 2, mask_bits = 65535 })
    local water_verts = {
        { 362.6168, -244.6432 },
        { 362.6168, 8.2492 },
        { -837.3832, 8.2492 },
        { -837.3832, -244.6432 },
    }
    water_sensor_id = b2d.create_polygon_shape(bodies[6], sd,
        make_poly_from_verts(water_verts))

    -- body[7]: dynamic boat (5 fixtures)
    bd = b2d.default_body_def()
    bd.type = b2d.BodyType.DYNAMIC_BODY
    bd.position = { -7.3804, 10.7985 }
    bodies[7] = b2d.create_body(world_id, bd)
    boat_body = bodies[7]
    table.insert(all_dynamic_bodies, bodies[7])

    -- fixture 1: chimney (density=0.01, maskBits=0)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    local chimney_verts = {
        { 1.0135, 1.9346 }, { 1.0135, 2.4708 },
        { 0.8868, 2.4708 }, { 0.8868, 1.9346 },
    }
    b2d.create_polygon_shape(bodies[7], sd, make_poly_from_verts(chimney_verts))

    -- fixture 2: hull (6 vertices, density=0.85, maskBits=65534)
    sd = b2d.default_shape_def()
    sd.density = 0.85
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 65534 })
    sd.enable_sensor_events = true
    local hull_verts = {
        { 15.2818, 1.9913 }, { 0.1106, 1.9263 },
        { -0.7964, -0.0536 }, { 5.3200, -0.2321 },
        { 11.7724, 0.0214 }, { 14.1520, 0.7624 },
    }
    b2d.create_polygon_shape(bodies[7], sd, make_poly_from_verts(hull_verts))

    -- fixture 3: engine (circle, density=30, maskBits=0)
    sd = b2d.default_shape_def()
    sd.density = 30.0
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    b2d.create_circle_shape(bodies[7], sd,
        b2d.Circle({ center = { 0, 0 }, radius = 0.2314 }))

    -- fixture 4: superstructure (density=0.01, maskBits=0)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 0 })
    sd.enable_sensor_events = true
    local super_verts = {
        { 10.6093, 1.9688 }, { 8.3806, 3.3670 },
        { 6.1438, 3.3670 }, { 5.6707, 1.9510 },
    }
    b2d.create_polygon_shape(bodies[7], sd, make_poly_from_verts(super_verts))

    -- fixture 5: inner sensor (density=0.01, maskBits=65535)
    sd = b2d.default_shape_def()
    sd.density = 0.01
    sd.filter = b2d.Filter({ category_bits = 1, mask_bits = 65535 })
    sd.enable_sensor_events = true
    local inner_verts = {
        { 5.4269, 2.6673 }, { 4.7763, 2.6673 },
        { 4.6792, 1.9526 }, { 5.3464, 1.9526 },
    }
    b2d.create_polygon_shape(bodies[7], sd, make_poly_from_verts(inner_verts))

    table.insert(body_entries, { body_id = bodies[7], color = { 0.4, 0.6, 0.9 } })

    -----------------------------------------------------------------
    -- Joints
    -----------------------------------------------------------------

    -- joint[0]: distance boat->body3 (freq=4, damp=0.5)
    local dj = b2d.default_distance_joint_def()
    dj.body_id_a = bodies[7]
    dj.body_id_b = bodies[3]
    dj.local_anchor_a = { -0.008294, 2.9030 }
    dj.local_anchor_b = { 0, 0 }
    dj.length = 0.9604
    dj.enable_spring = true
    dj.hertz = 4.0
    dj.damping_ratio = 0.5
    b2d.create_distance_joint(world_id, dj)

    -- joint[1]: revolute boat->body3 (limit +/-30deg)
    local rj = b2d.default_revolute_joint_def()
    rj.body_id_a = bodies[7]
    rj.body_id_b = bodies[3]
    rj.local_anchor_a = { 0.9498, 2.4375 }
    rj.local_anchor_b = { 0.000342, -0.4586 }
    rj.enable_limit = true
    rj.lower_angle = -0.5236
    rj.upper_angle = 0.5236
    b2d.create_revolute_joint(world_id, rj)

    -- joint[2]: distance body3->body2 (freq=8, damp=0.5)
    dj = b2d.default_distance_joint_def()
    dj.body_id_a = bodies[3]
    dj.body_id_b = bodies[2]
    dj.local_anchor_a = { -0.9551, 0.9494 }
    dj.local_anchor_b = { 0, 0 }
    dj.length = 0.9530
    dj.enable_spring = true
    dj.hertz = 8.0
    dj.damping_ratio = 0.5
    b2d.create_distance_joint(world_id, dj)

    -- joint[3]: distance body2->body1 (freq=4.5, damp=0.5)
    dj = b2d.default_distance_joint_def()
    dj.body_id_a = bodies[2]
    dj.body_id_b = bodies[1]
    dj.local_anchor_a = { -0.9494, 1.0294 }
    dj.local_anchor_b = { 0, 0 }
    dj.length = 0.9506
    dj.enable_spring = true
    dj.hertz = 4.5
    dj.damping_ratio = 0.5
    b2d.create_distance_joint(world_id, dj)

    -- joint[4]: revolute body2->body1 (limit +/-40deg)
    rj = b2d.default_revolute_joint_def()
    rj.body_id_a = bodies[2]
    rj.body_id_b = bodies[1]
    rj.local_anchor_a = { 0.0000749, 0.5175 }
    rj.local_anchor_b = { -0.0000753, -0.5175 }
    rj.enable_limit = true
    rj.lower_angle = -0.6981
    rj.upper_angle = 0.6981
    b2d.create_revolute_joint(world_id, rj)

    -- joint[5]: revolute body3->body2 (limit +/-30deg)
    rj = b2d.default_revolute_joint_def()
    rj.body_id_a = bodies[3]
    rj.body_id_b = bodies[2]
    rj.local_anchor_a = { 0, 0.4459 }
    rj.local_anchor_b = { 0, -0.5071 }
    rj.enable_limit = true
    rj.lower_angle = -0.5236
    rj.upper_angle = 0.5236
    b2d.create_revolute_joint(world_id, rj)

    -- joint[6]: distance boat->buoy (freq=1.5, damp=0.5)
    dj = b2d.default_distance_joint_def()
    dj.body_id_a = bodies[7]
    dj.body_id_b = bodies[5]
    dj.local_anchor_a = { 5.1247, 3.2374 }
    dj.local_anchor_b = { -0.6856, 0.00782 }
    dj.length = 0.6807
    dj.enable_spring = true
    dj.hertz = 1.5
    dj.damping_ratio = 0.5
    b2d.create_distance_joint(world_id, dj)

    -- joint[7]: revolute boat->buoy (limit -34.8..+21.7deg)
    rj = b2d.default_revolute_joint_def()
    rj.body_id_a = bodies[7]
    rj.body_id_b = bodies[5]
    rj.local_anchor_a = { 5.0928, 2.5847 }
    rj.local_anchor_b = { -0.0364, -0.6568 }
    rj.enable_limit = true
    rj.lower_angle = -0.6071
    rj.upper_angle = 0.3784
    b2d.create_revolute_joint(world_id, rj)
end

---------------------------------------------------------------------

function scene:setup(world_id, ground_id)
    world_ref = world_id
    body_entries = {}
    all_dynamic_bodies = {}
    submerged_bodies = {}
    boat_body = nil
    boat_drive = false
    bubble_bodies = {}
    steps_since_last_bubble = 0
    next_bubble_index = 1
    debug_clipped_polygons = {}

    create_boat_world(world_id)

    -- Generate ground bumps (100 random points)
    ground_points = {}
    for i = 0, 99 do
        ground_points[i + 1] = { i * 3, math.random() * 3 }
    end
end

function scene:update(dt)
    debug_clipped_polygons = {}

    -- Sensor events for buoyancy tracking
    local events = b2d.world_get_sensor_events(world_ref)
    if events then
        if events.begin_events then
            for _, ev in ipairs(events.begin_events) do
                if ev.sensor_shape_id == water_sensor_id then
                    local body = b2d.shape_get_body(ev.visitor_shape_id)
                    submerged_bodies[body] = true
                end
            end
        end
        if events.end_events then
            for _, ev in ipairs(events.end_events) do
                if ev.sensor_shape_id == water_sensor_id then
                    local body = b2d.shape_get_body(ev.visitor_shape_id)
                    submerged_bodies[body] = nil
                end
            end
        end
    end

    -- Boat drive + bubbles + camera + wrap
    if boat_body and b2d.body_is_valid(boat_body) then
        local pos = b2d.body_get_position(boat_body)

        -- Drive: if A key held and engine underwater
        if boat_drive and pos[2] < 10.1 then
            local force = b2d.body_get_world_vector(boat_body, { 400, -25 })
            b2d.body_apply_force(boat_body, force, pos, true)

            -- Bubbles
            if steps_since_last_bubble > 0 then
                local bubble_pos = pos -- engine is at local (0,0)
                local rnd = math.random()
                local bubble_dir = b2d.body_get_world_vector(
                    boat_body, { -50, -20 - rnd * 40 })

                local b = bubble_bodies[next_bubble_index]
                if not b then
                    local bbd = b2d.default_body_def()
                    bbd.type = b2d.BodyType.DYNAMIC_BODY
                    b = b2d.create_body(world_ref, bbd)
                    local bsd = b2d.default_shape_def()
                    bsd.density = 1.75
                    bsd.enable_sensor_events = true
                    b2d.create_polygon_shape(b, bsd, b2d.make_box(0.25, 0.25))
                    bubble_bodies[next_bubble_index] = b
                    table.insert(all_dynamic_bodies, b)
                    table.insert(body_entries,
                        { body_id = b, color = { 0.7, 0.8, 1.0 } })
                end
                b2d.body_set_transform(b, bubble_pos, b2d.make_rot(rnd))
                b2d.body_set_linear_velocity(b, bubble_dir)

                steps_since_last_bubble = 0
                next_bubble_index = next_bubble_index + 1
                if next_bubble_index > MAX_BUBBLES then
                    next_bubble_index = 1
                end
            end
        end
        steps_since_last_bubble = steps_since_last_bubble + 1

        -- Camera follow
        if camera_ref then
            local wc = b2d.body_get_world_center_of_mass(boat_body)
            local vel = b2d.body_get_linear_velocity(boat_body)
            local target_x = wc[1] + 0.25 * vel[1]
            local target_y = wc[2] + 0.25 * vel[2]
            camera_ref.x = 0.9 * camera_ref.x + 0.1 * target_x
            camera_ref.y = 0.9 * camera_ref.y + 0.1 * target_y
        end

        -- World wrap
        if pos[1] > 450 then
            for _, body_id in ipairs(all_dynamic_bodies) do
                if b2d.body_is_valid(body_id) then
                    local bp = b2d.body_get_position(body_id)
                    local br = b2d.body_get_rotation(body_id)
                    b2d.body_set_transform(body_id, { bp[1] - 900, bp[2] }, br)
                end
            end
            if camera_ref then
                camera_ref.x = camera_ref.x - 900
            end
        end
    end

    -- Apply buoyancy forces using polygon clipping
    for body_id, _ in pairs(submerged_bodies) do
        if not b2d.body_is_valid(body_id) then
            submerged_bodies[body_id] = nil
            goto continue
        end
        if b2d.body_get_type(body_id) ~= b2d.BodyType.DYNAMIC_BODY then
            goto continue
        end

        local vel = b2d.body_get_linear_velocity(body_id)
        local ang_vel = b2d.body_get_angular_velocity(body_id)

        local shapes = b2d.body_get_shapes(body_id)
        for _, shape_id in ipairs(shapes) do
            local world_verts = get_shape_world_vertices(shape_id, body_id)
            if #world_verts < 3 then goto continue_shape end

            local clipped = clip_polygon_below(world_verts, water_y)
            if #clipped < 3 then goto continue_shape end

            local cx, cy, area = compute_centroid_and_area(clipped)
            if area < 1e-6 then goto continue_shape end

            -- Buoyancy force
            local buoyancy = fluid_density * area * 10
            b2d.body_apply_force(body_id, { 0, buoyancy }, { cx, cy }, true)

            table.insert(debug_clipped_polygons, clipped)

            -- Per-edge drag and lift
            for i = 1, #clipped do
                local j = (i % #clipped) + 1
                local x1, y1 = clipped[i][1], clipped[i][2]
                local x2, y2 = clipped[j][1], clipped[j][2]
                local mid_x = (x1 + x2) * 0.5
                local mid_y = (y1 + y2) * 0.5

                local pos_body = b2d.body_get_position(body_id)
                local r_x = mid_x - pos_body[1]
                local r_y = mid_y - pos_body[2]
                local vel_x = vel[1] + (-ang_vel * r_y)
                local vel_y = vel[2] + (ang_vel * r_x)
                local spd = math.sqrt(vel_x * vel_x + vel_y * vel_y)
                if spd < 1e-6 then goto continue_edge end
                local dx, dy = vel_x / spd, vel_y / spd

                local ex, ey = x2 - x1, y2 - y1
                local elen = math.sqrt(ex * ex + ey * ey)
                if elen < 1e-6 then goto continue_edge end
                local enx, eny = ex / elen, ey / elen
                local nx, ny = eny, -enx

                local drag_dot = nx * dx + ny * dy
                if drag_dot < 0 then goto continue_edge end

                local dm = drag_dot * drag_mod * elen * fluid_density * spd * spd
                dm = math.min(dm, max_drag)

                local lift_dot = enx * dx + eny * dy
                local lm = drag_dot * lift_dot * lift_mod * elen * fluid_density * spd * spd
                lm = math.min(lm, max_lift)

                b2d.body_apply_force(body_id,
                    { dm * (-dx) + lm * (-dy), dm * (-dy) + lm * dx },
                    { mid_x, mid_y }, true)

                ::continue_edge::
            end

            ::continue_shape::
        end

        ::continue::
    end
end

function scene:get_bodies()
    return body_entries
end

function scene:render_extra()
    -- Draw water surface (camera-relative wide rectangle)
    local cam_x = camera_ref and camera_ref.x or 0
    local half_w = 200
    draw.filled_polygon({
        { cam_x - half_w, -243 },
        { cam_x + half_w, -243 },
        { cam_x + half_w, water_y },
        { cam_x - half_w, water_y },
    }, 0.1, 0.2, 0.6)

    -- Debug: clipped polygon outlines (cyan)
    for _, poly in ipairs(debug_clipped_polygons) do
        draw.polygon_outline(poly, 0.0, 1.0, 1.0)
    end

    -- Draw repeating ground bumps (4 tiles at k*300)
    for k = -2, 1 do
        local ox = k * 300
        for i = 1, 99 do
            draw.line(
                ground_points[i][1] + ox, ground_points[i][2],
                ground_points[i + 1][1] + ox, ground_points[i + 1][2],
                0.5, 0.9, 0.5)
        end
        -- Connect last point to first point of next tile
        draw.line(
            ground_points[100][1] + ox, ground_points[100][2],
            ground_points[1][1] + ox + 300, ground_points[1][2],
            0.5, 0.9, 0.5)
    end
end

function scene:render_ui()
    imgui.text_unformatted("Press A to drive the boat")
    imgui.separator()

    local changed, val

    changed, val = imgui.slider_float("Fluid Density", fluid_density, 0.5, 10)
    if changed then fluid_density = val end

    changed, val = imgui.slider_float("Drag Mod", drag_mod, 0, 2)
    if changed then drag_mod = val end

    changed, val = imgui.slider_float("Lift Mod", lift_mod, 0, 2)
    if changed then lift_mod = val end

    imgui.separator()
    imgui.text_unformatted("Bodies: " .. #body_entries)
    local submerged_count = 0
    for _ in pairs(submerged_bodies) do submerged_count = submerged_count + 1 end
    imgui.text_unformatted("Submerged: " .. submerged_count)
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.A then
            boat_drive = true
        end
    elseif ev.type == app.EventType.KEY_UP then
        if ev.key_code == app.Keycode.A then
            boat_drive = false
        end
    end
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:cleanup() end

return scene
