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
local mapMod = require("examples.sjadm.map")
local playerMod = require("examples.sjadm.player")

local M = {}
M.width = 800
M.height = 600
M.window_title = "Super Jump And Dash Man"

local world_id
local cam
local map
local pl
local registry = {} -- shape_id string -> entity

local function timeString(sec)
    return string.format("%4d:%02d.%02d", math.floor(sec / 60), math.floor(sec % 60), math.floor(sec * 100) % 100)
end

local function process_contact_events()
    local events = b2d.world_get_contact_events(world_id)
    if not events then return end

    -- begin contacts
    for _, c in ipairs(events.begin) do
        local e1 = registry[tostring(c.shapeIdA)]
        local e2 = registry[tostring(c.shapeIdB)]
        -- Dispatch: if one is player, call onContact with the other
        if e1 and e1.getType and e1:getType() == "P" then
            e1:onContact(e2)
        elseif e2 and e2.getType and e2:getType() == "P" then
            e2:onContact(e1)
        end
        -- Track wall contacts (entity is nil for plain walls)
        if e1 and e1.getType and e1:getType() == "P" and not e2 then
            e1.touchingWalls = e1.touchingWalls + 1
        elseif e2 and e2.getType and e2:getType() == "P" and not e1 then
            e2.touchingWalls = e2.touchingWalls + 1
        end
    end

    -- end contacts
    for _, c in ipairs(events.end_) do
        local e1 = registry[tostring(c.shapeIdA)]
        local e2 = registry[tostring(c.shapeIdB)]
        if e1 and e1.getType and e1:getType() == "P" then
            if e2 and e2.getType then
                e1:onEndContact(e2)
            end
            if not e2 then
                e1.touchingWalls = math.max(0, e1.touchingWalls - 1)
            end
        elseif e2 and e2.getType and e2:getType() == "P" then
            if e1 and e1.getType then
                e2:onEndContact(e1)
            end
            if not e1 then
                e2.touchingWalls = math.max(0, e2.touchingWalls - 1)
            end
        end
    end

    -- hit events (have normal info for wall-jump direction)
    for _, c in ipairs(events.hit) do
        local e1 = registry[tostring(c.shapeIdA)]
        local e2 = registry[tostring(c.shapeIdB)]
        if e1 and e1.getType and e1:getType() == "P" and not e2 then
            e1.contactNormalX = e1.contactNormalX + (c.normal[1] or 0)
            e1.contactNormalY = e1.contactNormalY + (c.normal[2] or 0)
        elseif e2 and e2.getType and e2:getType() == "P" and not e1 then
            -- normal points from A to B, negate for B side
            e2.contactNormalX = e2.contactNormalX - (c.normal[1] or 0)
            e2.contactNormalY = e2.contactNormalY - (c.normal[2] or 0)
        end
    end
end

local function process_sensor_events()
    local events = b2d.world_get_sensor_events(world_id)
    if not events then return end

    for _, ev in ipairs(events.begin) do
        local sensor = registry[tostring(ev.sensorShapeId)]
        local visitor = registry[tostring(ev.visitorShapeId)]
        if visitor and visitor.getType and visitor:getType() == "P" then
            visitor:onContact(sensor)
        elseif sensor and sensor.getType and sensor:getType() == "P" then
            sensor:onContact(visitor)
        end
    end

    for _, ev in ipairs(events.end_) do
        local sensor = registry[tostring(ev.sensorShapeId)]
        local visitor = registry[tostring(ev.visitorShapeId)]
        if visitor and visitor.getType and visitor:getType() == "P" then
            if sensor and sensor.getType then
                visitor:onEndContact(sensor)
            end
        elseif sensor and sensor.getType and sensor:getType() == "P" then
            if visitor and visitor.getType then
                sensor:onEndContact(visitor)
            end
        end
    end
end

function M:init()
    log.info("sjadm starting...")

    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    gl.Setup(gl.Desc({
        max_vertices = 65536,
        max_commands = 16384,
    }))

    sdtx.Setup(sdtx.Desc({ fonts = { sdtx.FontC64() } }))

    -- Create Box2D world
    local world_def = b2d.default_world_def()
    world_def.gravity = { 0, -1000 }
    world_def.maximumLinearSpeed = 2000
    world_id = b2d.create_world(world_def)

    -- Initialize subsystems
    input.init()
    cam = Camera.new()
    audio.init()
    map = mapMod.new(world_id, registry)
    pl = playerMod.new(world_id, input, cam, map, registry)

    -- Set start point and spawn
    pl:setRespawnPoint(map:getStartPoint())
    pl:respawn()

    log.info("sjadm initialized")
end

function M:frame()
    local dt = app.FrameDuration()
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
    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.05, g = 0.05, b = 0.1, a = 1.0 },
            } },
        }),
        swapchain = glue.Swapchain(),
    }))

    local w = app.Widthf()
    local h = app.Heightf()

    gl.Defaults()
    gl.MatrixModeProjection()
    gl.Ortho(0, w, h, 0, -1, 1)
    gl.MatrixModeModelview()

    -- Camera transform
    cam:push()

    -- Render world
    pl:render()
    map:render()

    cam:pop()

    -- UI overlay (screen space)
    local canvas_w = w / 2
    local canvas_h = h / 2
    sdtx.Canvas(canvas_w, canvas_h)
    sdtx.Origin(1, 1)
    sdtx.Color3f(1, 1, 1)

    if pl.gameTime then
        sdtx.Puts("time:" .. timeString(pl.gameTime) .. "\n")
    end
    if pl.goalTime then
        sdtx.Puts("goal:" .. timeString(pl.goalTime) .. "\n")
    end
    if pl.jumpMax > 0 then
        sdtx.Puts(string.format("jump: %d\n", pl.jumpNum))
    end
    if pl.dashMax > 0 then
        sdtx.Puts(string.format("dash: %d\n", pl.dashNum))
    end

    -- FPS (top right)
    local fps = math.floor(1.0 / (dt > 0 and dt or 1))
    sdtx.Origin(canvas_w / 8 - 10, 1)
    sdtx.Color3f(1, 1, 0)
    sdtx.Puts(string.format("FPS:%3d", fps))

    gl.Draw()
    sdtx.Draw()
    gfx.EndPass()
    gfx.Commit()

    input.end_frame()
end

function M:event(ev)
    input.handle_event(ev)

    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.Quit()
        end
    end
end

function M:cleanup()
    audio.cleanup()
    b2d.destroy_world(world_id)
    gl.Shutdown()
    gfx.Shutdown()
    log.info("sjadm cleanup complete")
end

return M
