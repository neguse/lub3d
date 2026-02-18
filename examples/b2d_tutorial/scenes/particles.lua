-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)

local app = require("sokol.app")
local b2d = require("b2d")
local imgui = require("imgui")
local draw = require("examples.b2d_tutorial.draw")
local terrain_data = require("examples.b2d_tutorial.scenes.terrain_data")

local scene = {}
scene.name = "Particles"
scene.description = "Physics-driven particles from a car on terrain.\nA/D=drive, S=brake, F=follow cam, 4=4WD.\nSparks on concrete, smoke on rubber+concrete,\ndirt particles on dirt terrain."

-- Material types
local MAT_CONCRETE <const> = 1
local MAT_DIRT <const> = 2
local MAT_STEEL <const> = 3
local MAT_RUBBER <const> = 4

-- Particle types
local PT_SMOKE <const> = 1
local PT_SPARK <const> = 2
local PT_DIRT <const> = 3

-- Collision categories
local CAT_WORLD <const> = 0x0001
local CAT_PARTICLE <const> = 0x0002
local CAT_CAR <const> = 0x0004

-- State
local world_ref
local body_entries = {}
local terrain_bodies = {} -- { body_id } for custom per-shape rendering
local shape_material = {} -- tostring(shape_id) -> MAT_*
local shape_color = {} -- tostring(shape_id) -> { r, g, b }
local active_contacts = {} -- pair_key -> { shape_a, shape_b, pair_type }

-- Car
local car_id
local front_wheel_id, rear_wheel_id
local front_joint_id, rear_joint_id
local four_wd = false
local follow_car = true
local camera_ref

-- Particles: circular buffer
local MAX_PARTICLES <const> = 100
local particles = {} -- [1..MAX_PARTICLES] slots: { body_id, life, particle_type } or nil
local next_index = 1

-- Particle life decay rates
local LIFE_SMOKE <const> = -0.01
local LIFE_SPARK <const> = -0.015
local LIFE_DIRT <const> = -0.005

-- Key state
local key_a = false
local key_d = false
local key_s = false

local MOTOR_SPEED <const> = 27.93 -- ~1600 deg/s in rad/s

local function shape_key(shape_id)
    return tostring(shape_id)
end

local function pair_key(sa, sb)
    local ka, kb = shape_key(sa), shape_key(sb)
    if ka > kb then ka, kb = kb, ka end
    return ka .. ":" .. kb
end

local function classify_pair(mat_a, mat_b)
    -- Ensure one is car part, one is terrain
    local car_mat, terrain_mat
    if mat_a == MAT_STEEL or mat_a == MAT_RUBBER then
        car_mat, terrain_mat = mat_a, mat_b
    elseif mat_b == MAT_STEEL or mat_b == MAT_RUBBER then
        car_mat, terrain_mat = mat_b, mat_a
    else
        return nil
    end
    if terrain_mat == MAT_CONCRETE then
        if car_mat == MAT_STEEL then return PT_SPARK end
        if car_mat == MAT_RUBBER then return PT_SMOKE end
    elseif terrain_mat == MAT_DIRT then
        return PT_DIRT
    end
    return nil
end

local WHEEL_RADIUS <const> = 0.4

local function ground_height_at(x)
    local filter = b2d.default_query_filter()
    filter.mask_bits = CAT_WORLD
    local result = b2d.world_cast_ray_closest(world_ref,
        { x, 1000 }, { 0, -2000 }, filter)
    if result and result.hit then
        return result.point[2]
    end
    return 0
end

local function spawn_particle(ptype, wx, wy, vel_a, vel_b, intensity)
    -- Recycle old particle at next_index
    local old = particles[next_index]
    if old and old.body_id and b2d.body_is_valid(old.body_id) then
        b2d.destroy_body(old.body_id)
    end

    local life = math.min(math.max(intensity * 0.3, 0), 1)

    local body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMIC_BODY
    body_def.position = { wx, wy }
    body_def.fixed_rotation = true

    local vx, vy = 0, 0
    local sum_vx = vel_a[1] + vel_b[1]
    local sum_vy = vel_a[2] + vel_b[2]

    if ptype == PT_SMOKE then
        body_def.gravity_scale = 0
        body_def.linear_damping = 4
        vx = sum_vx * 0.1 + (math.random() * 4 - 2)
        vy = sum_vy * 0.1 + (math.random() * 4 - 2)
    elseif ptype == PT_SPARK then
        body_def.gravity_scale = 0.5
        body_def.linear_damping = 1
        vx = (math.random() * 6 - 3)
        vy = (math.random() * 6 - 3)
    elseif ptype == PT_DIRT then
        body_def.gravity_scale = 1
        body_def.linear_damping = 0.1
        vx = sum_vx * 0.3 + (math.random() * 4 - 2)
        vy = sum_vy * 0.3 + (math.random() * 4 - 2)
    end

    local body = b2d.create_body(world_ref, body_def)
    b2d.body_set_linear_velocity(body, { vx, vy })

    local shape_def = b2d.default_shape_def()
    shape_def.density = 0.1
    shape_def.filter = b2d.Filter({ category_bits = CAT_PARTICLE, mask_bits = CAT_WORLD })
    local smat = b2d.default_surface_material()
    if ptype == PT_SMOKE then
        smat.restitution = 0.1
    elseif ptype == PT_SPARK then
        smat.restitution = 0.8
    elseif ptype == PT_DIRT then
        smat.restitution = 0.2
    end
    shape_def.material = smat
    b2d.create_circle_shape(body, shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = 0.02 }))

    particles[next_index] = {
        body_id = body,
        life = life,
        particle_type = ptype,
    }
    next_index = next_index % MAX_PARTICLES + 1
end

local function register_shape_material(shape_id, mat)
    shape_material[shape_key(shape_id)] = mat
end

local function get_shape_material(shape_id)
    return shape_material[shape_key(shape_id)]
end

function scene:set_camera(cam)
    camera_ref = cam
end

function scene:setup(world_id, ground_id)
    world_ref = world_id
    body_entries = {}
    terrain_bodies = {}
    shape_material = {}
    shape_color = {}
    active_contacts = {}
    particles = {}
    next_index = 1
    key_a = false
    key_d = false
    key_s = false
    four_wd = false
    follow_car = true

    -- Remove default ground shapes
    local ground_shapes = b2d.body_get_shapes(ground_id)
    for _, s in ipairs(ground_shapes) do
        b2d.destroy_shape(s, true)
    end

    -- Create terrain from data
    for _, bdata in ipairs(terrain_data) do
        local body_def = b2d.default_body_def()
        body_def.position = { bdata.position[1], bdata.position[2] }
        local terrain_body = b2d.create_body(world_id, body_def)
        table.insert(terrain_bodies, terrain_body)

        for _, fix in ipairs(bdata.fixtures) do
            local shape_def = b2d.default_shape_def()
            shape_def.enable_contact_events = true
            shape_def.filter = b2d.Filter({ category_bits = CAT_WORLD, mask_bits = 0xFFFF })
            local mat = b2d.default_surface_material()
            mat.friction = fix.friction
            shape_def.material = mat

            local shape_id
            if fix.type == "circle" then
                shape_id = b2d.create_circle_shape(terrain_body, shape_def,
                    b2d.Circle({ center = { fix.center[1], fix.center[2] }, radius = fix.radius }))
            else
                local verts = fix.vertices
                local hull = b2d.compute_hull(verts, #verts)
                local polygon = b2d.make_polygon(hull, 0)
                shape_id = b2d.create_polygon_shape(terrain_body, shape_def, polygon)
            end

            -- Classify material: friction > 0.5 = concrete, else dirt
            local terrain_mat = fix.friction > 0.5 and MAT_CONCRETE or MAT_DIRT
            register_shape_material(shape_id, terrain_mat)

            if terrain_mat == MAT_CONCRETE then
                shape_color[shape_key(shape_id)] = { 0.9, 0.9, 0.9 }
            else
                shape_color[shape_key(shape_id)] = { 1.0, 0.6, 0.4 }
            end
        end
    end

    -- Car body (bodies[3] in original): position {-52.56, 0.89}
    local car_def = b2d.default_body_def()
    car_def.type = b2d.BodyType.DYNAMIC_BODY
    car_def.position = { -52.56, 0.89 }
    car_def.enable_sleep = false
    car_id = b2d.create_body(world_id, car_def)

    local car_shape_def = b2d.default_shape_def()
    car_shape_def.density = 1.0
    car_shape_def.enable_contact_events = true
    car_shape_def.filter = b2d.Filter({ category_bits = CAT_CAR, mask_bits = 0xFFFD })
    local car_mat = b2d.default_surface_material()
    car_mat.friction = 0.5
    car_shape_def.material = car_mat

    local car_verts = {
        { 1.5, -0.5 }, { 1.5, 0 }, { 0, 0.9 },
        { -1.15, 0.9 }, { -1.5, 0.2 }, { -1.5, -0.5 },
    }
    local car_hull = b2d.compute_hull(car_verts, #car_verts)
    local car_polygon = b2d.make_polygon(car_hull, 0)
    local car_shape_id = b2d.create_polygon_shape(car_id, car_shape_def, car_polygon)
    register_shape_material(car_shape_id, MAT_STEEL)
    table.insert(body_entries, { body_id = car_id, color = { 1.0, 0.0, 0.0 } })

    -- Front wheel (bodies[2] in original)
    local fw_def = b2d.default_body_def()
    fw_def.type = b2d.BodyType.DYNAMIC_BODY
    fw_def.position = { -51.58, 0.37 }
    fw_def.enable_sleep = false
    front_wheel_id = b2d.create_body(world_id, fw_def)

    local fw_shape_def = b2d.default_shape_def()
    fw_shape_def.density = 1.5
    fw_shape_def.enable_contact_events = true
    fw_shape_def.filter = b2d.Filter({ category_bits = CAT_CAR, mask_bits = 0xFFFD })
    local fw_mat = b2d.default_surface_material()
    fw_mat.friction = 0.9
    fw_shape_def.material = fw_mat
    local fw_shape_id = b2d.create_circle_shape(front_wheel_id, fw_shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = 0.4 }))
    register_shape_material(fw_shape_id, MAT_RUBBER)
    table.insert(body_entries, { body_id = front_wheel_id, color = { 0.5, 0.5, 0.5 } })

    -- Rear wheel (bodies[4] in original)
    local rw_def = b2d.default_body_def()
    rw_def.type = b2d.BodyType.DYNAMIC_BODY
    rw_def.position = { -53.58, 0.37 }
    rw_def.enable_sleep = false
    rear_wheel_id = b2d.create_body(world_id, rw_def)

    local rw_shape_def = b2d.default_shape_def()
    rw_shape_def.density = 1.0
    rw_shape_def.enable_contact_events = true
    rw_shape_def.filter = b2d.Filter({ category_bits = CAT_CAR, mask_bits = 0xFFFD })
    local rw_mat = b2d.default_surface_material()
    rw_mat.friction = 0.9
    rw_shape_def.material = rw_mat
    local rw_shape_id = b2d.create_circle_shape(rear_wheel_id, rw_shape_def,
        b2d.Circle({ center = { 0, 0 }, radius = 0.4 }))
    register_shape_material(rw_shape_id, MAT_RUBBER)
    table.insert(body_entries, { body_id = rear_wheel_id, color = { 0.5, 0.5, 0.5 } })

    -- Front wheel joint
    local fj_def = b2d.default_wheel_joint_def()
    fj_def.body_id_a = car_id
    fj_def.body_id_b = front_wheel_id
    fj_def.local_anchor_a = { 1.0, -0.6 }
    fj_def.local_anchor_b = { 0, 0 }
    fj_def.local_axis_a = { 0, 1 }
    fj_def.enable_spring = true
    fj_def.hertz = 3.8
    fj_def.damping_ratio = 0.7
    fj_def.enable_motor = true
    fj_def.motor_speed = 0
    fj_def.max_motor_torque = 20
    front_joint_id = b2d.create_wheel_joint(world_id, fj_def)

    -- Rear wheel joint
    local rj_def = b2d.default_wheel_joint_def()
    rj_def.body_id_a = car_id
    rj_def.body_id_b = rear_wheel_id
    rj_def.local_anchor_a = { -1.0, -0.65 }
    rj_def.local_anchor_b = { 0, 0 }
    rj_def.local_axis_a = { 0, 1 }
    rj_def.enable_spring = true
    rj_def.hertz = 3.8
    rj_def.damping_ratio = 0.7
    rj_def.enable_motor = true
    rj_def.motor_speed = 0
    rj_def.max_motor_torque = 20
    rear_joint_id = b2d.create_wheel_joint(world_id, rj_def)

    -- Initial camera position on car
    if camera_ref then
        local pos = b2d.body_get_position(car_id)
        camera_ref.x = pos[1]
        camera_ref.y = pos[2]
    end
end

function scene:update(dt)
    -- Motor control
    if key_s then
        -- Brake
        b2d.wheel_joint_enable_motor(rear_joint_id, true)
        b2d.wheel_joint_set_motor_speed(rear_joint_id, 0)
        b2d.wheel_joint_enable_motor(front_joint_id, true)
        b2d.wheel_joint_set_motor_speed(front_joint_id, 0)
    elseif key_a then
        b2d.wheel_joint_enable_motor(rear_joint_id, true)
        b2d.wheel_joint_set_motor_speed(rear_joint_id, MOTOR_SPEED)
        if four_wd then
            b2d.wheel_joint_enable_motor(front_joint_id, true)
            b2d.wheel_joint_set_motor_speed(front_joint_id, MOTOR_SPEED)
        else
            b2d.wheel_joint_enable_motor(front_joint_id, false)
        end
    elseif key_d then
        b2d.wheel_joint_enable_motor(rear_joint_id, true)
        b2d.wheel_joint_set_motor_speed(rear_joint_id, -MOTOR_SPEED)
        if four_wd then
            b2d.wheel_joint_enable_motor(front_joint_id, true)
            b2d.wheel_joint_set_motor_speed(front_joint_id, -MOTOR_SPEED)
        else
            b2d.wheel_joint_enable_motor(front_joint_id, false)
        end
    else
        -- Free roll
        b2d.wheel_joint_enable_motor(rear_joint_id, false)
        b2d.wheel_joint_enable_motor(front_joint_id, false)
    end

    -- Process contact events
    local events = b2d.world_get_contact_events(world_ref)
    if events then
        if events.begin_events then
            for _, ev in ipairs(events.begin_events) do
                local ma = get_shape_material(ev.shape_id_a)
                local mb = get_shape_material(ev.shape_id_b)
                if ma and mb then
                    local pt = classify_pair(ma, mb)
                    if pt then
                        local pk = pair_key(ev.shape_id_a, ev.shape_id_b)
                        active_contacts[pk] = {
                            shape_a = ev.shape_id_a,
                            shape_b = ev.shape_id_b,
                            pair_type = pt,
                        }
                    end
                end
            end
        end
        if events.end_events then
            for _, ev in ipairs(events.end_events) do
                local pk = pair_key(ev.shape_id_a, ev.shape_id_b)
                active_contacts[pk] = nil
            end
        end
    end

    -- Spawn particles from active contacts
    for _, contact in pairs(active_contacts) do
        local sa, sb = contact.shape_a, contact.shape_b
        if not (b2d.shape_is_valid(sa) and b2d.shape_is_valid(sb)) then
            goto continue
        end

        local body_a = b2d.shape_get_body(sa)
        local body_b = b2d.shape_get_body(sb)
        local pos_a = b2d.body_get_position(body_a)
        local pos_b = b2d.body_get_position(body_b)

        local vel_a = b2d.body_get_world_point_velocity(body_a, pos_a)
        local vel_b = b2d.body_get_world_point_velocity(body_b, pos_b)

        local dvx = vel_a[1] - vel_b[1]
        local dvy = vel_a[2] - vel_b[2]
        local relative_speed = math.sqrt(dvx * dvx + dvy * dvy)

        -- Skip if car is barely moving
        if relative_speed < 1 then
            goto continue
        end

        local surf_a = b2d.shape_get_surface_material(sa)
        local surf_b = b2d.shape_get_surface_material(sb)
        local total_friction = surf_a.friction * surf_b.friction
        local intensity = relative_speed * total_friction

        if intensity > 1 then
            -- Use car part body position as contact point approximation
            local mat_a = get_shape_material(sa)
            local car_mat, car_body
            if mat_a == MAT_STEEL or mat_a == MAT_RUBBER then
                car_mat, car_body = mat_a, body_a
            else
                car_mat, car_body = get_shape_material(sb), body_b
            end
            local car_pos = b2d.body_get_position(car_body)
            local spawn_y = ground_height_at(car_pos[1]) + 0.05
            spawn_particle(contact.pair_type, car_pos[1], spawn_y, vel_a, vel_b, intensity)
        end

        ::continue::
    end

    -- Decay particle life
    for i = 1, MAX_PARTICLES do
        local p = particles[i]
        if p then
            local decay
            if p.particle_type == PT_SMOKE then decay = LIFE_SMOKE
            elseif p.particle_type == PT_SPARK then decay = LIFE_SPARK
            else decay = LIFE_DIRT
            end
            p.life = p.life + decay
            if p.life <= 0 then
                if b2d.body_is_valid(p.body_id) then
                    b2d.destroy_body(p.body_id)
                end
                particles[i] = nil
            end
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

local function transform_point(lx, ly, pos, cos_a, sin_a)
    return pos[1] + lx * cos_a - ly * sin_a,
        pos[2] + lx * sin_a + ly * cos_a
end

local function draw_terrain()
    for _, body_id in ipairs(terrain_bodies) do
        if not b2d.body_is_valid(body_id) then goto next_body end
        local pos = b2d.body_get_position(body_id)
        local rot = b2d.body_get_rotation(body_id)
        local cos_a, sin_a = rot[1], rot[2]
        local shapes = b2d.body_get_shapes(body_id)
        for _, sid in ipairs(shapes) do
            local color = shape_color[shape_key(sid)] or { 0.5, 0.5, 0.5 }
            local r, g, b_c = color[1], color[2], color[3]
            local st = b2d.shape_get_type(sid)
            if st == b2d.ShapeType.POLYGON_SHAPE then
                local poly = b2d.shape_get_polygon(sid)
                local tverts = {}
                for i = 1, poly.count do
                    local lx, ly = poly.vertices[i][1], poly.vertices[i][2]
                    local wx, wy = transform_point(lx, ly, pos, cos_a, sin_a)
                    tverts[i] = { wx, wy }
                end
                draw.filled_polygon(tverts, r * 0.6, g * 0.6, b_c * 0.6)
                draw.polygon_outline(tverts, r, g, b_c)
            elseif st == b2d.ShapeType.CIRCLE_SHAPE then
                local circle = b2d.shape_get_circle(sid)
                local cx, cy = transform_point(
                    circle.center[1], circle.center[2], pos, cos_a, sin_a)
                draw.circle_outline(cx, cy, circle.radius, 0, r, g, b_c)
            end
        end
        ::next_body::
    end
end

function scene:render_extra()
    -- Draw terrain with per-shape colors
    draw_terrain()

    -- Draw particles
    for i = 1, MAX_PARTICLES do
        local p = particles[i]
        if p and b2d.body_is_valid(p.body_id) then
            local pos = b2d.body_get_position(p.body_id)
            local alpha = math.max(0, math.min(1, p.life))
            local r, g, b_c
            if p.particle_type == PT_SMOKE then
                r, g, b_c = 0.5, 0.5, 0.5
            elseif p.particle_type == PT_SPARK then
                r, g, b_c = 0.9, 1.0, 0.1
            else -- PT_DIRT
                r, g, b_c = 1.0, 0.6, 0.4
            end
            draw.point(pos[1], pos[2], 0.08,
                r * alpha, g * alpha, b_c * alpha)
        end
    end
end

function scene:render_ui()
    imgui.text_unformatted("A/D: Drive  S: Brake")
    imgui.text_unformatted("F: Follow Camera  4: 4WD Toggle")
    imgui.separator()
    imgui.text_unformatted("4WD: " .. (four_wd and "ON" or "OFF"))
    imgui.text_unformatted("Follow: " .. (follow_car and "ON" or "OFF"))

    -- Count active particles
    local count = 0
    for i = 1, MAX_PARTICLES do
        if particles[i] then count = count + 1 end
    end
    imgui.text_unformatted("Particles: " .. count .. "/" .. MAX_PARTICLES)

    if b2d.body_is_valid(car_id) then
        local vel = b2d.body_get_linear_velocity(car_id)
        local speed = math.sqrt(vel[1] * vel[1] + vel[2] * vel[2])
        imgui.text_unformatted(string.format("Speed: %.1f", speed))
    end
end

function scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.A then
            key_a = true
        elseif ev.key_code == app.Keycode.D then
            key_d = true
        elseif ev.key_code == app.Keycode.S then
            key_s = true
        elseif ev.key_code == app.Keycode["4"] then
            four_wd = not four_wd
        elseif ev.key_code == app.Keycode.F then
            follow_car = not follow_car
        end
    elseif ev.type == app.EventType.KEY_UP then
        if ev.key_code == app.Keycode.A then
            key_a = false
        elseif ev.key_code == app.Keycode.D then
            key_d = false
        elseif ev.key_code == app.Keycode.S then
            key_s = false
        end
    end
end

function scene:cleanup()
    -- Destroy remaining particles
    for i = 1, MAX_PARTICLES do
        local p = particles[i]
        if p and b2d.body_is_valid(p.body_id) then
            b2d.destroy_body(p.body_id)
        end
    end
    particles = {}
end

return scene
