-- hakonotaiatari - main entry point
-- A 2D action game ported from C++ to lub3d
-- https://github.com/neguse/hakonotaiatari

local gfx = require("sokol.gfx")
local app = require("sokol.app")
local gl = require("sokol.gl")
local glue = require("sokol.glue")
local log = require("lib.log")

-- Game modules
local const = require("examples.hakonotaiatari.const")
local renderer = require("examples.hakonotaiatari.renderer")
local pathtracer = require("examples.hakonotaiatari.pathtracer")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local Camera = require("examples.hakonotaiatari.camera")
local field = require("examples.hakonotaiatari.field")
local particle = require("examples.hakonotaiatari.particle")
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
    gfx.setup(gfx.Desc({
        environment = glue.environment(),
    }))

    -- Initialize sokol.gl
    gl.setup(gl.Desc({
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
    local frame_dt = app.frame_duration()
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

    -- Setup projection and view matrices (original game is 1:1 aspect ratio)
    local aspect = 1.0 -- Force square aspect ratio like original 240x240
    local eye = camera:get_eye()
    local lookat = camera:get_lookat()

    if renderer.get_mode() == renderer.MODE_PATHTRACED then
        -- Path tracing mode: collect scene and render via pathtracer
        local cubes = {}
        if current_state == const.GAME_STATE_GAME then
            local p = game.get_player()
            if p and not p:is_dead() then
                local is_dashing = (p.stat == const.P_ST_DASH)
                local p_emission = is_dashing and 4.0 or 1.0
                local p_color = is_dashing and const.P_COL_DASH_PT or p.color
                table.insert(cubes, {
                    pos = p.pos, length = p.length, angle = p.angle,
                    color = p_color, material = 1, emission = p_emission,
                })
            end
            for _, e in ipairs(game.get_enemies()) do
                if not e:is_dead() then
                    local is_dashing = (e.stat == const.E_ST_DASH)
                    local is_boss = (e.type == const.C_TYPE_DASH_ENEMY)
                    local e_emission = 0
                    if is_dashing then
                        e_emission = 4.0
                    elseif is_boss then
                        e_emission = 0.8
                    end
                    table.insert(cubes, {
                        pos = e.pos, length = e.length, angle = e.angle,
                        color = e.color, material = 1, emission = e_emission,
                    })
                end
            end
        end

        -- Render path traced image + open swapchain pass for UI overlay
        pathtracer.render(cubes, camera, renderer.get_gakugaku(), current_state)

        -- 3D overlay: particles (PT has its own ground plane, no field grid needed)
        renderer.set_camera_lookat(eye, lookat, aspect)
        local vx, vy, vw, vh = renderer.get_viewport()
        gfx.apply_viewport(vx, vy, vw, vh, true)
        gfx.apply_scissor_rect(0, 0, math.floor(app.widthf()), math.floor(app.heightf()), true)

        -- Rasterize cube depth for particle occlusion
        if current_state == const.GAME_STATE_GAME and #cubes > 0 then
            local proj = camera:get_proj(aspect)
            local view = camera:get_view()
            renderer.draw_cubes_depth_only(cubes, proj, view)
        end

        if current_state == const.GAME_STATE_GAME then
            particle.render()
        end

        -- Setup UI projection for overlay on top of path traced image
        renderer.setup_ui_projection()
    else
        -- Wireframe / Shaded mode (unchanged)
        renderer.begin_frame()

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

        -- Setup orthographic projection for UI
        renderer.setup_ui_projection()
    end

    -- Render UI based on state (drawn on top of all modes)
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
            app.quit()
        elseif ev.key_code == app.Keycode.TAB then
            local mode = renderer.toggle_mode()
            local names = { [1] = "WIREFRAME", [2] = "SHADED", [3] = "PATHTRACED" }
            log.info("Render mode: " .. (names[mode] or "UNKNOWN"))
        end
    end
end

function M:cleanup()
    audio.cleanup()
    renderer.cleanup() -- gl.shutdown() is called inside
    gfx.shutdown()
    log.info("hakonotaiatari cleanup complete")
end

return M
