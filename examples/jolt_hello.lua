-- jolt_hello.lua - Jolt Physics falling boxes demo
-- 3D wireframe rendering with sokol.gl, mouse click to spawn boxes

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")
local jolt = require("jolt")

local M = {}
M.width = 800
M.height = 600
M.window_title = "Jolt Physics"

local world
local bodies = {} -- {id=, hx=, hy=, hz=, is_sphere=, radius=}
local depth_pip

-- Camera
local cam_dist = 30
local cam_yaw = 0.5
local cam_pitch = 0.4

local function draw_wire_box(hx, hy, hz)
    -- 12 edges of a box centered at origin with half-extents hx,hy,hz
    local v = {
        { -hx, -hy, -hz }, { hx, -hy, -hz }, { hx, hy, -hz }, { -hx, hy, -hz },
        { -hx, -hy, hz }, { hx, -hy, hz }, { hx, hy, hz }, { -hx, hy, hz },
    }
    local edges = {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }
    gl.begin_lines()
    for _, e in ipairs(edges) do
        gl.v3f(v[e[1]][1], v[e[1]][2], v[e[1]][3])
        gl.v3f(v[e[2]][1], v[e[2]][2], v[e[2]][3])
    end
    gl["end"]()
end

local function draw_wire_sphere_approx(r, segs)
    segs = segs or 16
    -- Draw 3 circles (XY, XZ, YZ planes)
    for _, plane in ipairs({ { 1, 2, 3 }, { 1, 3, 2 }, { 2, 3, 1 } }) do
        gl.begin_line_strip()
        for i = 0, segs do
            local a = (i / segs) * math.pi * 2
            local p = { 0, 0, 0 }
            p[plane[1]] = math.cos(a) * r
            p[plane[2]] = math.sin(a) * r
            gl.v3f(p[1], p[2], p[3])
        end
        gl["end"]()
    end
end

local function quat_to_axis_angle(qx, qy, qz, qw)
    -- Convert quaternion to axis-angle (for gl.rotate)
    local len = math.sqrt(qx * qx + qy * qy + qz * qz)
    if len < 1e-6 then
        return 0, 0, 1, 0 -- no rotation
    end
    local angle = 2 * math.atan(len, qw)
    return angle, qx / len, qy / len, qz / len
end

function M:init()
    gfx.setup(gfx.Desc({ environment = glue.environment() }))
    gl.setup(gl.Desc({ max_vertices = 65536 }))

    -- Pipeline with depth test
    depth_pip = gl.make_pipeline(gfx.PipelineDesc({
        depth = {
            compare = gfx.CompareFunc.LESS_EQUAL,
            write_enabled = true,
        },
    }))

    -- Create physics world
    world = jolt.init()
    world:set_gravity(0, -10, 0)

    -- Ground (static box)
    local ground = world:create_box(50, 0.5, 50, 0, -0.5, 0, jolt.STATIC)
    bodies[#bodies + 1] = { id = ground, hx = 50, hy = 0.5, hz = 50 }

    -- Initial falling boxes
    for i = 1, 5 do
        local id = world:create_box(0.5, 0.5, 0.5, (i - 3) * 1.5, 5 + i * 2, 0, jolt.DYNAMIC)
        bodies[#bodies + 1] = { id = id, hx = 0.5, hy = 0.5, hz = 0.5 }
    end

    world:optimize()
end

function M:frame()
    -- Step physics
    world:update(1.0 / 60.0)

    -- Begin render
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = 0.1, g = 0.1, b = 0.15, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.swapchain(),
    }))

    gl.defaults()
    gl.load_pipeline(depth_pip)

    -- Projection
    gl.matrix_mode_projection()
    local aspect = M.width / M.height
    gl.perspective(math.rad(60.0), aspect, 0.1, 200.0)

    -- Camera (orbit)
    gl.matrix_mode_modelview()
    local eye_x = cam_dist * math.cos(cam_pitch) * math.sin(cam_yaw)
    local eye_y = cam_dist * math.sin(cam_pitch)
    local eye_z = cam_dist * math.cos(cam_pitch) * math.cos(cam_yaw)
    gl.lookat(eye_x, eye_y + 5, eye_z, 0, 3, 0, 0, 1, 0)

    -- Draw bodies
    for _, b in ipairs(bodies) do
        local px, py, pz = world:get_position(b.id)
        local qx, qy, qz, qw = world:get_rotation(b.id)

        gl.push_matrix()
        gl.translate(px, py, pz)
        local angle, ax, ay, az = quat_to_axis_angle(qx, qy, qz, qw)
        gl.rotate(angle, ax, ay, az)

        local active = world:is_active(b.id)
        if active then
            gl.c3f(0.9, 0.6, 0.2)
        else
            gl.c3f(0.4, 0.5, 0.4)
        end

        if b.is_sphere then
            draw_wire_sphere_approx(b.radius)
        else
            draw_wire_box(b.hx, b.hy, b.hz)
        end

        gl.pop_matrix()
    end

    -- Draw ground grid
    gl.c3f(0.3, 0.3, 0.3)
    gl.begin_lines()
    for i = -10, 10 do
        gl.v3f(i, 0, -10); gl.v3f(i, 0, 10)
        gl.v3f(-10, 0, i); gl.v3f(10, 0, i)
    end
    gl["end"]()

    gl.draw()
    gfx.end_pass()
    gfx.commit()
end

function M:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.quit()
        elseif ev.key_code == app.Keycode.SPACE then
            -- Spawn box above center
            local x = (math.random() - 0.5) * 4
            local z = (math.random() - 0.5) * 4
            local id = world:create_box(0.5, 0.5, 0.5, x, 15, z, jolt.DYNAMIC)
            bodies[#bodies + 1] = { id = id, hx = 0.5, hy = 0.5, hz = 0.5 }
        elseif ev.key_code == app.Keycode.B then
            -- Spawn sphere
            local x = (math.random() - 0.5) * 4
            local z = (math.random() - 0.5) * 4
            local id = world:create_sphere(0.5, x, 15, z, jolt.DYNAMIC)
            bodies[#bodies + 1] = { id = id, is_sphere = true, radius = 0.5 }
        end
    elseif ev.type == app.EventType.MOUSE_DOWN then
        -- Spawn box at click
        local x = (math.random() - 0.5) * 6
        local z = (math.random() - 0.5) * 6
        local id = world:create_box(0.5, 0.5, 0.5, x, 15, z, jolt.DYNAMIC)
        bodies[#bodies + 1] = { id = id, hx = 0.5, hy = 0.5, hz = 0.5 }
    elseif ev.type == app.EventType.MOUSE_MOVE then
        if ev.mouse_button == app.Mousebutton.RIGHT or ev.modifiers_shift then
            cam_yaw = cam_yaw + ev.mouse_dx * 0.005
            cam_pitch = cam_pitch + ev.mouse_dy * 0.005
            cam_pitch = math.max(-1.2, math.min(1.2, cam_pitch))
        end
    elseif ev.type == app.EventType.MOUSE_SCROLL then
        cam_dist = cam_dist - ev.scroll_y * 2
        cam_dist = math.max(5, math.min(100, cam_dist))
    end
end

function M:cleanup()
    if world then
        world:destroy()
        world = nil
    end
    if depth_pip then
        gl.destroy_pipeline(depth_pip)
        depth_pip = nil
    end
    gl.shutdown()
    gfx.shutdown()
end

return M
