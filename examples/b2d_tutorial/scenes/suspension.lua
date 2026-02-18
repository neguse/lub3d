-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")

local scene = {}
scene.name = "Hovercar Suspension"
scene.description = "Left/Right arrows to move, W to fly.\nRaycast spring suspension keeps car hovering.\nAdjust spring constant and target height."

local world_ref
local car_id
local terrain_bodies = {}
local body_entries = {}
local camera_ref
local follow_car = true

local spring_constant = 50.0
local target_height = 3.0
local damping_factor = 0.25
local max_ray = 5.0
local lateral_force = 50.0
local max_lateral_vel = 10.0
local fly_force = 100.0
local max_vertical_vel = 10.0
local dir_x = 0
local dir_fly = false

-- Ray anchor point in car local space (center bottom)
local ray_anchors = {
    { 0, -0.5 },
}

local ray_debug = {} -- { origin, hit_point } for debug rendering

local function generate_terrain(world_id)
    local body_def = b2d.default_body_def()
    body_def.position = { 0, 0 }
    local terrain = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    local mat = b2d.default_surface_material()
    mat.friction = 0.8
    shape_def.material = mat

    local segments = 120
    local seg_width = 0.8
    local start_x = -segments * seg_width / 2

    -- Pre-generate random heights (C++: rnd_1()*2, range [0,2])
    local heights = {}
    for i = 0, segments do
        heights[i] = math.random() * 2
    end

    for i = 0, segments - 1 do
        local x1 = start_x + i * seg_width
        local x2 = start_x + (i + 1) * seg_width

        b2d.create_segment_shape(terrain, shape_def,
            b2d.Segment({ point1 = { x1, heights[i] }, point2 = { x2, heights[i + 1] } }))
    end

    table.insert(terrain_bodies, terrain)
    return terrain
end

local function create_little_boxes(world_id)
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 15 }
    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    local mat = b2d.default_surface_material()
    mat.friction = 0.8
    shape_def.material = mat
    for i = 1, 10 do
        local body = b2d.create_body(world_id, body_def)
        b2d.create_polygon_shape(body, shape_def, b2d.make_box(0.5, 0.5))
        table.insert(body_entries, { body_id = body, color = { 0.8, 0.6, 0.3 } })
    end
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    terrain_bodies = {}
    body_entries = {}
    dir_x = 0
    dir_fly = false
    ray_debug = {}
    follow_car = true

    -- Generate terrain
    generate_terrain(world_id)

    -- Car body
    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { 0, 10 }
    body_def.fixed_rotation = true
    car_id = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    local mat = b2d.default_surface_material()
    mat.friction = 0.8
    shape_def.material = mat
    b2d.create_polygon_shape(car_id, shape_def, b2d.make_box(2, 0.5))

    table.insert(body_entries, { body_id = car_id, color = { 0.2, 0.6, 0.9 } })

    -- Little boxes on terrain
    create_little_boxes(world_id)

    -- Initial camera position on car
    if camera_ref then
        local pos = b2d.body_get_position(car_id)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:update(dt)
    ray_debug = {}

    local mass = b2d.body_get_mass(car_id)
    local gravity = b2d.world_get_gravity(world_ref)
    local vel = b2d.body_get_linear_velocity(car_id)
    local filter = b2d.default_query_filter()

    for _, anchor in ipairs(ray_anchors) do
        local ray_origin = b2d.body_get_world_point(car_id, anchor)
        local ray_dir = { 0, -max_ray }

        local result = b2d.world_cast_ray_closest(world_ref, ray_origin, ray_dir, filter)
        if result and result.hit then
            local dist = result.fraction * max_ray
            local hit_y = ray_origin[2] - dist

            if dist < target_height then
                -- Look-ahead damping (vel[2] > 0 = moving up → increase dist → reduce force)
                local adjusted = dist + damping_factor * vel[2]

                -- Spring force applied to center of mass
                b2d.body_apply_force_to_center(car_id, { 0, spring_constant * (target_height - adjusted) }, true)

                -- Cancel gravity
                b2d.body_apply_force_to_center(car_id, { 0, -mass * gravity[2] }, true)
            end

            table.insert(ray_debug, {
                origin = { ray_origin[1], ray_origin[2] },
                hit = { ray_origin[1], hit_y },
            })
        else
            table.insert(ray_debug, {
                origin = { ray_origin[1], ray_origin[2] },
                hit = nil,
            })
        end
    end

    -- Fly control
    if dir_fly and vel[2] < max_vertical_vel then
        b2d.body_apply_force_to_center(car_id, { 0, fly_force }, true)
    end

    -- Lateral control
    if dir_x ~= 0 then
        if (dir_x < 0 and vel[1] > -max_lateral_vel) or
            (dir_x > 0 and vel[1] < max_lateral_vel) then
            b2d.body_apply_force_to_center(car_id, { dir_x * lateral_force, 0 }, true)
        end
    end

    -- Follow camera
    if follow_car and camera_ref and b2d.body_is_valid(car_id) then
        local pos = b2d.body_get_position(car_id)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:get_bodies()
    return body_entries
end

function scene:render_extra()
    -- Draw terrain
    for _, terrain in ipairs(terrain_bodies) do
        local shapes = b2d.body_get_shapes(terrain)
        for _, s in ipairs(shapes) do
            local seg = b2d.shape_get_segment(s)
            draw.line(seg.point1[1], seg.point1[2], seg.point2[1], seg.point2[2],
                0.3, 0.6, 0.3)
        end
    end

    -- Draw suspension rays
    for _, rd in ipairs(ray_debug) do
        if rd.hit then
            draw.line(rd.origin[1], rd.origin[2], rd.hit[1], rd.hit[2], 1, 0.5, 0)
            draw.point(rd.hit[1], rd.hit[2], 0.15, 1, 0, 0)
        else
            draw.line(rd.origin[1], rd.origin[2],
                rd.origin[1], rd.origin[2] - max_ray, 0.3, 0.3, 0.3)
        end
    end
end

function scene:render_ui()
    local changed, val

    changed, val = imgui.slider_float("Spring Constant", spring_constant, 10, 200)
    if changed then spring_constant = val end

    changed, val = imgui.slider_float("Target Height", target_height, 1, 8)
    if changed then target_height = val end

    changed, val = imgui.slider_float("Damping", damping_factor, 0, 1)
    if changed then damping_factor = val end

    changed, val = imgui.slider_float("Lateral Force", lateral_force, 10, 200)
    if changed then lateral_force = val end

    changed, val = imgui.slider_float("Fly Force", fly_force, 10, 300)
    if changed then fly_force = val end

    imgui.separator()
    local vel = b2d.body_get_linear_velocity(car_id)
    imgui.text_unformatted(string.format("Vel: (%.1f, %.1f)", vel[1], vel[2]))

    imgui.separator()
    for i, rd in ipairs(ray_debug) do
        if rd.hit then
            local dist = rd.origin[2] - rd.hit[2]
            imgui.text_unformatted(string.format("Ray %d distance above ground: %.3f", i, dist))
        else
            imgui.text_unformatted(string.format("Ray %d (out of range)", i))
        end
    end

    imgui.separator()
    imgui.text_unformatted("Follow: " .. (follow_car and "ON" or "OFF"))
    imgui.text_unformatted("F: Toggle follow camera")
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.LEFT then
            dir_x = -1
        elseif ev.key_code == app.Keycode.RIGHT then
            dir_x = 1
        elseif ev.key_code == app.Keycode.W or ev.key_code == app.Keycode.UP then
            dir_fly = true
        elseif ev.key_code == app.Keycode.F then
            follow_car = not follow_car
        end
    elseif ev.type == app.EventType.KEY_UP then
        if ev.key_code == app.Keycode.LEFT or ev.key_code == app.Keycode.RIGHT then
            dir_x = 0
        elseif ev.key_code == app.Keycode.W or ev.key_code == app.Keycode.UP then
            dir_fly = false
        end
    end
end

function scene:cleanup() end

return scene
