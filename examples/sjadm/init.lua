-- Super Jump And Dash Man - lub3d port
-- Original: https://github.com/neguse/SuperJumpAndDashMan (LOVE 2D, #lovejam2019)

local gfx = require("sokol.gfx")
local app = require("sokol.app")
local gl = require("sokol.gl")
local glue = require("sokol.glue")
local sdtx = require("sokol.debugtext")
local b2d = require("b2d")
local log = require("lib.log")

local input = require("examples.sjadm.input")
local Camera = require("examples.sjadm.camera")
local audio = require("examples.sjadm.audio")
local map_mod = require("examples.sjadm.map")
local player_mod = require("examples.sjadm.player")

local M = {}
M.width = 800
M.height = 600
M.window_title = "Super Jump And Dash Man"

local world_id
local cam
local map
local pl
local registry = {} -- shape_id string -> entity

local function time_string(sec)
    return string.format("%4d:%02d.%02d", math.floor(sec / 60), math.floor(sec % 60), math.floor(sec * 100) % 100)
end

local function process_contact_events()
    local events = b2d.world_get_contact_events(world_id)
    if not events then return end

    -- begin contacts
    for _, c in ipairs(events.begin_events) do
        local e1 = registry[tostring(c.shape_id_a)]
        local e2 = registry[tostring(c.shape_id_b)]
        -- Dispatch: if one is player, call onContact with the other
        if e1 and e1.get_type and e1:get_type() == "P" then
            e1:on_contact(e2)
        elseif e2 and e2.get_type and e2:get_type() == "P" then
            e2:on_contact(e1)
        end
        -- Track wall contacts (entity is nil for plain walls)
        if e1 and e1.get_type and e1:get_type() == "P" and not e2 then
            e1.touching_walls = e1.touching_walls + 1
        elseif e2 and e2.get_type and e2:get_type() == "P" and not e1 then
            e2.touching_walls = e2.touching_walls + 1
        end
    end

    -- end contacts
    for _, c in ipairs(events.end_events) do
        local e1 = registry[tostring(c.shape_id_a)]
        local e2 = registry[tostring(c.shape_id_b)]
        if e1 and e1.get_type and e1:get_type() == "P" then
            if e2 and e2.get_type then
                e1:on_end_contact(e2)
            end
            if not e2 then
                e1.touching_walls = math.max(0, e1.touching_walls - 1)
            end
        elseif e2 and e2.get_type and e2:get_type() == "P" then
            if e1 and e1.get_type then
                e2:on_end_contact(e1)
            end
            if not e1 then
                e2.touching_walls = math.max(0, e2.touching_walls - 1)
            end
        end
    end

    -- hit events (have normal info for wall-jump direction)
    for _, c in ipairs(events.hit_events) do
        local e1 = registry[tostring(c.shape_id_a)]
        local e2 = registry[tostring(c.shape_id_b)]
        if e1 and e1.get_type and e1:get_type() == "P" and not e2 then
            e1.contact_normal_x = e1.contact_normal_x + (c.normal[1] or 0)
            e1.contact_normal_y = e1.contact_normal_y + (c.normal[2] or 0)
        elseif e2 and e2.get_type and e2:get_type() == "P" and not e1 then
            -- normal points from A to B, negate for B side
            e2.contact_normal_x = e2.contact_normal_x - (c.normal[1] or 0)
            e2.contact_normal_y = e2.contact_normal_y - (c.normal[2] or 0)
        end
    end
end

local function process_sensor_events()
    local events = b2d.world_get_sensor_events(world_id)
    if not events then return end

    for _, ev in ipairs(events.begin_events) do
        local sensor = registry[tostring(ev.sensor_shape_id)]
        local visitor = registry[tostring(ev.visitor_shape_id)]
        if visitor and visitor.get_type and visitor:get_type() == "P" then
            visitor:on_contact(sensor)
        elseif sensor and sensor.get_type and sensor:get_type() == "P" then
            sensor:on_contact(visitor)
        end
    end

    for _, ev in ipairs(events.end_events) do
        local sensor = registry[tostring(ev.sensor_shape_id)]
        local visitor = registry[tostring(ev.visitor_shape_id)]
        if visitor and visitor.get_type and visitor:get_type() == "P" then
            if sensor and sensor.get_type then
                visitor:on_end_contact(sensor)
            end
        elseif sensor and sensor.get_type and sensor:get_type() == "P" then
            if visitor and visitor.get_type then
                sensor:on_end_contact(visitor)
            end
        end
    end
end

function M:init()
    log.info("sjadm starting...")

    gfx.setup(gfx.Desc({
        environment = glue.environment(),
    }))

    gl.setup(gl.Desc({
        max_vertices = 65536,
        max_commands = 16384,
    }))

    sdtx.setup(sdtx.Desc({ fonts = { sdtx.font_c64() } }))

    -- Create Box2D world
    local world_def = b2d.default_world_def()
    world_def.gravity = { 0, -1000 }
    world_def.maximum_linear_speed = 2000
    world_id = b2d.create_world(world_def)

    -- Initialize subsystems
    input.init()
    cam = Camera.new()
    audio.init()
    map = map_mod.new(world_id, registry)
    pl = player_mod.new(world_id, input, cam, map, registry)

    -- Set start point and spawn
    pl:set_respawn_point(map:get_start_point())
    pl:respawn()

    log.info("sjadm initialized")
end

function M:frame()
    local dt = app.frame_duration()
    if dt <= 0 then dt = 1.0 / 60.0 end
    if dt > 0.1 then dt = 0.1 end

    -- Variable timestep (matches original LOVE 2D behaviour)
    b2d.world_step(world_id, dt, 4)

    -- Process events
    process_contact_events()
    process_sensor_events()

    -- Update game
    input.update()
    map:update()
    pl:update(dt)
    cam:update(dt)

    -- Render
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.05, g = 0.05, b = 0.1, a = 1.0 },
            } },
        }),
        swapchain = glue.swapchain(),
    }))

    local w = app.widthf()
    local h = app.heightf()

    gl.defaults()
    gl.matrix_mode_projection()
    gl.ortho(0, w, h, 0, -1, 1)
    gl.matrix_mode_modelview()

    -- Camera transform
    cam:push()

    -- Render world
    pl:render()
    map:render()

    cam:pop()

    -- UI overlay (screen space)
    local canvas_w = w / 2
    local canvas_h = h / 2
    sdtx.canvas(canvas_w, canvas_h)
    sdtx.origin(1, 1)
    sdtx.color3f(1, 1, 1)

    if pl.game_time then
        sdtx.puts("time:" .. time_string(pl.game_time) .. "\n")
    end
    if pl.goal_time then
        sdtx.puts("goal:" .. time_string(pl.goal_time) .. "\n")
    end
    if pl.jump_max > 0 then
        sdtx.puts(string.format("jump: %d\n", pl.jump_num))
    end
    if pl.dash_max > 0 then
        sdtx.puts(string.format("dash: %d\n", pl.dash_num))
    end

    -- FPS (top right)
    local fps = math.floor(1.0 / (dt > 0 and dt or 1))
    sdtx.origin(canvas_w / 8 - 10, 1)
    sdtx.color3f(1, 1, 0)
    sdtx.puts(string.format("FPS:%3d", fps))

    gl.draw()
    sdtx.draw()
    gfx.end_pass()
    gfx.commit()

    input.end_frame()
end

function M:event(ev)
    input.handle_event(ev)

    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.quit()
        end
    end
end

function M:cleanup()
    audio.cleanup()
    b2d.destroy_world(world_id)
    gl.shutdown()
    gfx.shutdown()
    log.info("sjadm cleanup complete")
end

return M
