-- hakonotaiatari - main entry point
-- A 2D action game ported from C++ to lub3d
-- https://github.com/neguse/hakonotaiatari

local gfx = require("sokol.gfx")
local app = require("sokol.app")
local gl = require("sokol.gl")
local glue = require("sokol.glue")
local log = require("lib.log")
local glm = require("lib.glm")

-- Game modules
local const = require("examples.hakonotaiatari.const")
local renderer = require("examples.hakonotaiatari.renderer")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local Camera = require("examples.hakonotaiatari.camera")
local field = require("examples.hakonotaiatari.field")
local audio = require("examples.hakonotaiatari.audio")

-- State modules
local title = require("examples.hakonotaiatari.title")
local tutorial = require("examples.hakonotaiatari.tutorial")
local game = require("examples.hakonotaiatari.game")
local record = require("examples.hakonotaiatari.record")

-- Game state
local current_state = const.GAME_STATE_TITLE
---@type Camera
local camera
local last_score = 0
local time_accumulator = 0 -- For fixed timestep

local M = {}
M.width = 800
M.height = 800
M.window_title = "hakonotaiatari"
M.high_dpi = true

function M:init()
    log.info("hakonotaiatari starting...")

    -- Initialize sokol.gfx (required for Lua entry point)
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    -- Initialize sokol.gl
    gl.Setup(gl.Desc({
        max_vertices = 65536,
        max_commands = 16384,
    }))

    -- Initialize renderer
    renderer.init()

    -- Initialize font
    font.init()

    -- Initialize camera
    camera = Camera.new()
    camera:init()

    -- Initialize audio
    audio.init()

    -- Initialize input
    input.init()

    -- Initialize field
    field.init()

    -- Start with title screen
    title.init(camera, audio)

    log.info("hakonotaiatari initialized")
end

function M:frame()
    local frame_dt = app.FrameDuration()
    local fixed_dt = const.DELTA_T -- 1/60 sec

    -- Update input (every frame)
    input.update()

    -- Update audio (every frame)
    audio.update()

    -- Update gakugaku time (every frame)
    renderer.update_gakugaku_time(frame_dt)

    -- Fixed timestep for game logic (60 FPS)
    time_accumulator = time_accumulator + frame_dt
    while time_accumulator >= fixed_dt do
        time_accumulator = time_accumulator - fixed_dt

        -- Update current state at fixed 60 FPS
        if current_state == const.GAME_STATE_TITLE then
            title.update(fixed_dt, camera)
        elseif current_state == const.GAME_STATE_TUTORIAL then
            tutorial.update(fixed_dt, camera)
        elseif current_state == const.GAME_STATE_GAME then
            game.update(fixed_dt, camera, audio)
        elseif current_state == const.GAME_STATE_RECORD then
            record.update(fixed_dt, camera)
        end
    end

    -- Check state transitions
    local next_state, extra = nil, nil
    if current_state == const.GAME_STATE_TITLE then
        next_state = title.next_state()
    elseif current_state == const.GAME_STATE_TUTORIAL then
        next_state = tutorial.next_state()
    elseif current_state == const.GAME_STATE_GAME then
        next_state, extra = game.next_state()
        if next_state and extra then
            last_score = extra
        end
    elseif current_state == const.GAME_STATE_RECORD then
        next_state = record.next_state()
    end

    -- Handle state transition
    if next_state then
        -- Cleanup current state
        if current_state == const.GAME_STATE_TITLE then
            title.cleanup(audio)
        elseif current_state == const.GAME_STATE_TUTORIAL then
            tutorial.cleanup(audio)
        elseif current_state == const.GAME_STATE_GAME then
            game.cleanup(audio)
        elseif current_state == const.GAME_STATE_RECORD then
            record.cleanup(audio)
        end

        -- Switch state
        current_state = next_state

        -- Initialize new state
        if current_state == const.GAME_STATE_TITLE then
            title.init(camera, audio)
        elseif current_state == const.GAME_STATE_TUTORIAL then
            tutorial.init(camera, audio)
        elseif current_state == const.GAME_STATE_GAME then
            game.init(camera, audio)
        elseif current_state == const.GAME_STATE_RECORD then
            record.init(last_score, camera, audio)
        end
    end

    -- Begin render pass (use renderer to handle both wireframe and shaded modes)
    renderer.begin_frame()

    -- Setup projection and view matrices (original game is 1:1 aspect ratio)
    local aspect = 1.0 -- Force square aspect ratio like original 240x240
    local eye = camera:get_eye()
    local lookat = camera:get_lookat()

    -- For render functions that need mat4
    local proj = camera:get_proj(aspect)
    local view = camera:get_view()

    -- Setup camera for current render mode
    renderer.set_camera_lookat(eye, lookat, aspect)

    -- Render field
    field.render()

    -- Render 3D content based on state
    if current_state == const.GAME_STATE_GAME then
        game.render(proj, view)
    end

    -- Setup orthographic projection for UI (includes loading wireframe pipeline)
    -- Note: gl.Draw() is called once at the end to render both 3D and UI
    renderer.setup_ui_projection()

    -- Render UI based on state
    if current_state == const.GAME_STATE_TITLE then
        title.render()
    elseif current_state == const.GAME_STATE_TUTORIAL then
        tutorial.render()
    elseif current_state == const.GAME_STATE_GAME then
        game.render_ui()
    elseif current_state == const.GAME_STATE_RECORD then
        record.render()
    end

    -- Flush all rendering (3D + UI)
    renderer.end_frame()

    -- Reset button pressed state
    input.end_frame()
end

function M:event(ev)
    -- Pass to input handler
    input.handle_event(ev)

    -- Handle global keys
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.Q then
            app.Quit()
        elseif ev.key_code == app.Keycode.TAB then
            renderer.toggle_mode()
            log.info("Render mode: " .. (renderer.get_mode() == renderer.MODE_WIREFRAME and "WIREFRAME" or "SHADED"))
        end
    end
end

function M:cleanup()
    audio.cleanup()
    renderer.cleanup() -- gl.Shutdown() is called inside
    gfx.Shutdown()
    log.info("hakonotaiatari cleanup complete")
end

return M
