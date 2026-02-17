-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Buoyancy"
scene.description = "Water surface with buoyancy simulation.\nSutherland-Hodgman polygon clipping.\nDrop objects with different densities."

local world_ref
local camera_ref
local body_entries = {}
local water_sensor_id
local submerged_bodies = {} -- set: body_id -> true

local water_y = 4.0
local water_half_w = 15.0
local water_half_h = 4.0
local fluid_density = 2.0

-- Drag/lift parameters (original iforce2d)
local drag_mod = 0.25
local lift_mod = 0.25
local max_drag = 2000
local max_lift = 500

local debug_clipped_polygons = {}

local CIRCLE_VERTS <const> = 16

---------------------------------------------------------------------
-- Sutherland-Hodgman polygon clipping helpers
---------------------------------------------------------------------

-- Find intersection of segment (p1→p2) with horizontal line y=clip_y
local function find_intersection_h(p1, p2, clip_y)
    local dx = p2[1] - p1[1]
    local dy = p2[2] - p1[2]
    if math.abs(dy) < 1e-10 then return { p1[1], clip_y } end
    local t = (clip_y - p1[2]) / dy
    return { p1[1] + t * dx, clip_y }
end

-- Clip polygon by horizontal line y=clip_y, keeping vertices with y <= clip_y (below water)
local function clip_polygon_below(verts, clip_y)
    if #verts < 2 then return verts end
    local out = {}
    local prev = verts[#verts]
    local prev_inside = (prev[2] <= clip_y)

    for _, cur in ipairs(verts) do
        local cur_inside = (cur[2] <= clip_y)
        if cur_inside then
            if not prev_inside then
                -- Entering: add intersection
                table.insert(out, find_intersection_h(prev, cur, clip_y))
            end
            table.insert(out, cur)
        elseif prev_inside then
            -- Leaving: add intersection
            table.insert(out, find_intersection_h(prev, cur, clip_y))
        end
        prev = cur
        prev_inside = cur_inside
    end
    return out
end

-- Compute centroid and area of a polygon (signed area, CCW positive)
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

-- Get shape vertices in world space
-- For circles, approximate as N-gon
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
        local cx = pos[1] + circle.center[1] * cos_a - circle.center[2] * sin_a
        local cy = pos[2] + circle.center[1] * sin_a + circle.center[2] * cos_a
        local r = circle.radius
        for i = 0, CIRCLE_VERTS - 1 do
            local a = (i / CIRCLE_VERTS) * math.pi * 2
            table.insert(verts, { cx + math.cos(a) * r, cy + math.sin(a) * r })
        end
    end

    return verts
end

---------------------------------------------------------------------

local function add_object(world_id, obj_type, x, y)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { x, y }
    local body = b2d.create_body(world_id, body_def)
    local shape_def = b2d.default_shape_def()
    shape_def.enable_sensor_events = true

    local color
    if obj_type == "ball" then
        shape_def.density = 0.3
        local mat = b2d.default_surface_material()
        mat.restitution = 0.6
        shape_def.material = mat
        b2d.create_circle_shape(body, shape_def,
            b2d.Circle({ center = { 0, 0 }, radius = 1.0 }))
        color = { 0.9, 0.3, 0.3 }
    elseif obj_type == "crate" then
        shape_def.density = 1.5
        b2d.create_polygon_shape(body, shape_def, b2d.make_box(0.6, 0.6))
        color = { 0.8, 0.6, 0.2 }
    elseif obj_type == "iron" then
        shape_def.density = 7.0
        b2d.create_circle_shape(body, shape_def,
            b2d.Circle({ center = { 0, 0 }, radius = 0.4 }))
        color = { 0.5, 0.5, 0.6 }
    end

    table.insert(body_entries, { body_id = body, color = color })
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    body_entries = {}
    submerged_bodies = {}

    -- Water sensor (static body with sensor shape)
    local body_def = b2d.default_body_def()
    body_def.position = { 0, water_y - water_half_h }
    local water_body = b2d.create_body(world_id, body_def)
    local shape_def = b2d.default_shape_def()
    shape_def.is_sensor = true
    shape_def.enable_sensor_events = true
    water_sensor_id = b2d.create_polygon_shape(water_body, shape_def,
        b2d.make_box(water_half_w, water_half_h))

    -- Side walls
    body_def = b2d.default_body_def()
    body_def.position = { -water_half_w, 5 }
    local lwall = b2d.create_body(world_id, body_def)
    shape_def = b2d.default_shape_def()
    shape_def.enable_sensor_events = true
    b2d.create_polygon_shape(lwall, shape_def, b2d.make_box(0.5, 10))
    table.insert(body_entries, { body_id = lwall, color = { 0.4, 0.4, 0.4 } })

    body_def = b2d.default_body_def()
    body_def.position = { water_half_w, 5 }
    local rwall = b2d.create_body(world_id, body_def)
    shape_def = b2d.default_shape_def()
    shape_def.enable_sensor_events = true
    b2d.create_polygon_shape(rwall, shape_def, b2d.make_box(0.5, 10))
    table.insert(body_entries, { body_id = rwall, color = { 0.4, 0.4, 0.4 } })

    -- Initial objects
    add_object(world_id, "ball", -3, 10)
    add_object(world_id, "crate", 0, 10)
    add_object(world_id, "iron", 3, 10)
end

function scene:update(dt)
    debug_clipped_polygons = {}

    -- Track sensor events for submerged bodies
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
        local mass = b2d.body_get_mass(body_id)

        local shapes = b2d.body_get_shapes(body_id)
        for _, shape_id in ipairs(shapes) do
            -- Get world vertices of the shape
            local world_verts = get_shape_world_vertices(shape_id, body_id)
            if #world_verts < 3 then goto continue_shape end

            -- Clip polygon below water surface
            local clipped = clip_polygon_below(world_verts, water_y)
            if #clipped < 3 then goto continue_shape end

            -- Compute area and centroid of submerged portion
            local cx, cy, area = compute_centroid_and_area(clipped)
            if area < 1e-6 then goto continue_shape end

            -- Buoyancy force at intersection centroid
            local buoyancy = fluid_density * area * 10 -- gravity = 10
            b2d.body_apply_force(body_id, { 0, buoyancy }, { cx, cy }, true)

            table.insert(debug_clipped_polygons, clipped)

            -- Per-edge drag and lift (faithful port of iforce2d)
            for i = 1, #clipped do
                local j = (i % #clipped) + 1
                local x1, y1 = clipped[i][1], clipped[i][2]
                local x2, y2 = clipped[j][1], clipped[j][2]
                local mid_x = (x1 + x2) * 0.5
                local mid_y = (y1 + y2) * 0.5

                -- Velocity at edge midpoint, separated into direction and speed
                local pos_body = b2d.body_get_position(body_id)
                local r_x = mid_x - pos_body[1]
                local r_y = mid_y - pos_body[2]
                local vel_x = vel[1] + (-ang_vel * r_y)
                local vel_y = vel[2] + (ang_vel * r_x)
                local spd = math.sqrt(vel_x * vel_x + vel_y * vel_y)
                if spd < 1e-6 then goto continue_edge end
                local dx, dy = vel_x / spd, vel_y / spd

                -- Edge direction + outward normal
                local ex, ey = x2 - x1, y2 - y1
                local elen = math.sqrt(ex * ex + ey * ey)
                if elen < 1e-6 then goto continue_edge end
                local enx, eny = ex / elen, ey / elen
                local nx, ny = eny, -enx -- b2Cross(-1, edge)

                -- Leading edge check: dragDot < 0 means trailing edge → skip
                local drag_dot = nx * dx + ny * dy
                if drag_dot < 0 then goto continue_edge end

                -- Drag: magnitude = dragDot * mod * len * density * speed²
                -- Direction: opposite to velocity (-velDir)
                local dm = drag_dot * drag_mod * elen * fluid_density * spd * spd
                dm = math.min(dm, max_drag)

                -- Lift: magnitude = dragDot * liftDot * mod * len * density * speed²
                -- Direction: b2Cross(1, velDir) = (-dy, dx)
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
    -- Draw water surface (semi-transparent blue)
    draw.filled_polygon({
        { -water_half_w, water_y - water_half_h * 2 },
        { water_half_w, water_y - water_half_h * 2 },
        { water_half_w, water_y },
        { -water_half_w, water_y },
    }, 0.1, 0.2, 0.6)

    -- Debug: clipped polygon outlines (cyan)
    for _, poly in ipairs(debug_clipped_polygons) do
        draw.polygon_outline(poly, 0.0, 1.0, 1.0)
    end
end

function scene:render_ui()
    local changed, val

    changed, val = imgui.slider_float("Fluid Density", fluid_density, 0.5, 10)
    if changed then fluid_density = val end

    changed, val = imgui.slider_float("Drag Mod", drag_mod, 0, 2)
    if changed then drag_mod = val end

    changed, val = imgui.slider_float("Lift Mod", lift_mod, 0, 2)
    if changed then lift_mod = val end

    imgui.separator()
    if imgui.button("Add Ball") then
        add_object(world_ref, "ball", (math.random() - 0.5) * 10, 12)
    end
    imgui.same_line()
    if imgui.button("Add Crate") then
        add_object(world_ref, "crate", (math.random() - 0.5) * 10, 12)
    end
    imgui.same_line()
    if imgui.button("Add Iron") then
        add_object(world_ref, "iron", (math.random() - 0.5) * 10, 12)
    end

    imgui.text_unformatted("Bodies: " .. #body_entries)
end

function scene:event(ev) end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:cleanup() end

return scene
