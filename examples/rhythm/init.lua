--- mane3d-rhythm: Minimal BMS Player
--- Entry point for the rhythm game with song selection

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local sgl = require("sokol.gl")
local sdtx = require("sokol.debugtext")
local slog = require("sokol.log")
local stm = require("sokol.time")
local imgui = require("imgui")

local const = require("examples.rhythm.const")
local converter = require("examples.rhythm.bms.converter")
local Conductor = require("examples.rhythm.core.conductor")
local InputHandler = require("examples.rhythm.input.handler")
local GameState = require("examples.rhythm.game.state")
local Playfield = require("examples.rhythm.game.playfield")
local LaneRenderer = require("examples.rhythm.render.lane")
local NoteRenderer = require("examples.rhythm.render.note")
local UIRenderer = require("examples.rhythm.render.ui")
local EffectRenderer = require("examples.rhythm.render.effect")
local ResultRenderer = require("examples.rhythm.render.result")
local AudioManager = require("examples.rhythm.audio.manager")
local SongScanner = require("examples.rhythm.song.scanner")
local SelectScreen = require("examples.rhythm.ui.select")

-- Application state
local app_state = "select"  -- "select" | "playing" | "finished"

-- Song scanner and select screen
local song_scanner
local select_screen

-- Game components (initialized when playing)
local state
local conductor
local input_handler
local playfield
local lane_renderer
local note_renderer
local ui_renderer
local effect_renderer
local result_renderer
local audio_manager
local chart
local start_time_us
local scroll_speed = const.DEFAULT_SCROLL_SPEED
local result_data = nil

-- BMS base path and cache
local BMS_BASE_PATH = "D:/BMS"
local BMS_CACHE_PATH = "bms_cache.lua"

--- Initialize game components for playing a song
---@param bms_path string Path to BMS file
local function init_game(bms_path)
    -- Load BMS file
    local load_err
    chart, load_err = converter.load(bms_path)
    if not chart then
        print("[rhythm] Failed to load BMS: " .. (load_err or "unknown"))
        app_state = "select"
        return false
    end

    print(string.format("[rhythm] Loaded: %s by %s (BPM: %.1f)",
        chart.meta.title, chart.meta.artist, chart.meta.bpm))
    print(string.format("[rhythm] Notes: %d, BGM events: %d",
        #chart.notes, #chart.bgm))

    -- Preload audio (with base directory)
    -- Handle both / and \ path separators
    local base_dir = bms_path:match("(.*[/\\])")
    if base_dir then
        base_dir = base_dir:sub(1, -2)  -- Remove trailing separator
        audio_manager:preload_chart(chart.wavs, base_dir)
    end

    -- Initialize game components
    input_handler = InputHandler.new()
    state = GameState.new()
    lane_renderer = LaneRenderer.new(sgl)
    note_renderer = NoteRenderer.new(sgl, lane_renderer)
    ui_renderer = UIRenderer.new(sdtx)
    effect_renderer = EffectRenderer.new(sdtx, sgl)

    conductor = Conductor.new(chart.timing_map, const.LEAD_TIME_US)
    state:load_chart(chart, conductor)
    playfield = Playfield.new(state, input_handler)
    playfield:init_with_chart(chart)

    -- Set up callbacks
    playfield.on_note_hit = function(note, judgment)
        audio_manager:play(note.wav_id)
    end
    playfield.on_note_miss = function(note)
        -- Could play a miss sound
    end
    playfield.on_judgment = function(result)
        local current_time_us = math.floor(stm.us(stm.now()))
        effect_renderer:add_judgment(
            result.judgment,
            result.timing,
            current_time_us,
            result.note and result.note.lane or nil
        )
    end

    -- Start with lead time
    start_time_us = math.floor(stm.us(stm.now()))
    conductor:start(start_time_us, -const.LEAD_TIME_US)
    state:start()

    result_data = nil
    app_state = "playing"
    return true
end

--- Prepare result data when game finishes
local function prepare_result()
    if not chart or not playfield then return end

    local stats = playfield:get_stats()
    local scoring = playfield.scoring
    local gauge = playfield.gauge

    result_data = {
        title = chart.meta.title or "Unknown",
        artist = chart.meta.artist or "Unknown",
        ex_score = scoring.ex_score,
        max_ex_score = scoring:get_max_ex_score(),
        dj_level = scoring:get_dj_level(),
        cleared = playfield:is_cleared(),
        gauge_type = gauge.gauge_type,
        final_gauge = gauge.value,
        stats = stats,
        max_combo = scoring.max_combo,
        total_notes = #chart.notes,
    }
end

--- Cleanup game resources
local function cleanup_game()
    if audio_manager then
        audio_manager:stop_all()
    end
    chart = nil
    conductor = nil
    playfield = nil
    state = nil
end

--- Return to select screen
local function return_to_select()
    cleanup_game()
    app_state = "select"
    result_data = nil
end

local function init()
    -- Initialize time
    stm.setup()

    -- Initialize graphics
    gfx.setup(gfx.Desc({
        environment = glue.environment(),
        logger = { func = slog.func },
    }))

    -- Initialize sokol-gl
    sgl.setup(sgl.Desc({
        logger = { func = slog.func },
    }))

    -- Initialize debug text
    sdtx.setup(sdtx.Desc({
        fonts = { sdtx.font_kc854() },
        logger = { func = slog.func },
    }))

    -- Initialize ImGui with Japanese font
    imgui.setup({
        japanese_font = "deps/fonts/NotoSansJP-Regular.ttf",
        font_size = 18.0,
    })

    -- Initialize audio
    audio_manager = AudioManager.new()
    local ok, err = audio_manager:init()
    if not ok then
        print("[rhythm] Audio init failed: " .. (err or "unknown"))
    end

    -- Initialize result renderer (shared)
    result_renderer = ResultRenderer.new(sdtx, sgl)

    -- Initialize song scanner and select screen
    select_screen = SelectScreen.new()
    song_scanner = SongScanner.new(BMS_BASE_PATH)

    -- Try to load from cache first
    if SongScanner.cache_exists(BMS_CACHE_PATH) then
        print("[rhythm] Loading song list from cache...")
        local ok, err = song_scanner:load_cache(BMS_CACHE_PATH)
        if ok then
            print(string.format("[rhythm] Loaded %d songs from cache", song_scanner:count()))
        else
            print("[rhythm] Cache load failed: " .. (err or "unknown"))
        end
    end

    -- If no songs loaded, scan and save cache
    if song_scanner:count() == 0 then
        print("[rhythm] Scanning for BMS files in " .. BMS_BASE_PATH .. "...")
        local count = song_scanner:scan(function(current, path)
            if current % 100 == 0 then
                print(string.format("[rhythm] Scanning... %d files", current))
            end
        end)
        print(string.format("[rhythm] Found %d songs", count))

        -- Save cache
        local ok, err = song_scanner:save_cache(BMS_CACHE_PATH)
        if ok then
            print("[rhythm] Saved song cache to " .. BMS_CACHE_PATH)
        else
            print("[rhythm] Failed to save cache: " .. (err or "unknown"))
        end
    end

    select_screen:set_songs(song_scanner:get_songs())

    -- Set up song selection callback
    select_screen.on_select = function(song)
        print("[rhythm] Selected: " .. song.title)
        init_game(song.path)
    end

    app_state = "select"
end

local function frame()
    local current_time_us = math.floor(stm.us(stm.now()))

    -- Begin rendering
    local pass_action = gfx.PassAction({
        colors = {
            [0] = { load_action = gfx.LoadAction.CLEAR, clear_value = { 0.1, 0.1, 0.15, 1.0 } },
        },
    })
    gfx.begin_pass(gfx.Pass({ action = pass_action, swapchain = glue.swapchain() }))

    if app_state == "select" then
        -- Draw select screen with ImGui
        imgui.new_frame()
        select_screen:draw()
        imgui.render()

    elseif app_state == "playing" then
        -- Update conductor
        if conductor and state:is(GameState.PLAYING) then
            conductor:update(current_time_us)

            -- Update playfield
            if playfield then
                playfield:update(conductor:get_chart_time_us(), conductor:get_current_beat())

                -- Play BGM events
                local bgm_events = playfield:get_bgm_to_play(conductor:get_chart_time_us())
                for _, bgm in ipairs(bgm_events) do
                    audio_manager:play(bgm.wav_id)
                end

                -- Check for HARD gauge failure
                if playfield:is_failed() then
                    state:finish()
                    prepare_result()
                    app_state = "finished"
                end
            end

            -- Check for completion
            if state:is_chart_complete() and conductor:get_current_beat() > 0 then
                -- Wait a bit after last note before finishing
                local last_note_beat = 0
                if chart and #chart.notes > 0 then
                    last_note_beat = chart.notes[#chart.notes].beat
                end
                if conductor:get_current_beat() > last_note_beat + 4 then
                    state:finish()
                    prepare_result()
                    app_state = "finished"
                end
            end
        end

        -- Update effects
        if effect_renderer then
            effect_renderer:update(current_time_us)
        end

        -- Setup sokol-gl
        sgl.defaults()
        sgl.matrix_mode_projection()
        sgl.ortho(0, const.SCREEN_WIDTH, const.SCREEN_HEIGHT, 0, -1, 1)
        sgl.matrix_mode_modelview()

        -- Draw lanes
        if lane_renderer and input_handler then
            lane_renderer:draw_lanes(input_handler:get_states())
            lane_renderer:draw_judgment_line()
        end

        -- Draw notes
        if chart and conductor and note_renderer then
            local visible_notes = state:get_visible_notes(
                conductor:get_current_beat(),
                const.VISIBLE_BEATS_ABOVE
            )
            note_renderer:draw_notes(visible_notes, conductor:get_current_beat(), scroll_speed)
        end

        -- Draw gauge
        if playfield and ui_renderer then
            ui_renderer:draw_gauge(playfield.gauge.value, playfield.gauge.gauge_type, sgl)
        end

        -- Draw sokol-gl
        sgl.draw()

        -- Draw UI
        if chart and ui_renderer then
            ui_renderer:draw_song_info(chart.meta.title, chart.meta.artist, chart.meta.bpm)
        end
        if state and ui_renderer then
            ui_renderer:draw_combo(state.combo)
            ui_renderer:draw_state(state.current)
        end

        -- Draw score and stats
        if playfield and ui_renderer then
            local scoring = playfield.scoring
            local stats = playfield:get_stats()
            ui_renderer:draw_score(scoring.ex_score, scoring:get_max_ex_score(), stats)
        end

        if conductor and ui_renderer then
            ui_renderer:draw_debug(
                conductor:get_current_beat(),
                conductor:get_chart_time_us(),
                conductor:get_current_bpm(),
                scroll_speed
            )
        end

        -- Draw judgment effects
        if effect_renderer then
            effect_renderer:draw(current_time_us)
        end

        -- Draw debug text
        sdtx.draw()

    elseif app_state == "finished" then
        -- Setup sokol-gl for result screen
        sgl.defaults()
        sgl.matrix_mode_projection()
        sgl.ortho(0, const.SCREEN_WIDTH, const.SCREEN_HEIGHT, 0, -1, 1)
        sgl.matrix_mode_modelview()

        -- Draw result screen
        if result_data and result_renderer then
            result_renderer:draw(result_data)
        end

        -- Draw debug text
        sdtx.draw()
    end

    gfx.end_pass()
    gfx.commit()
end

local function event(ev)
    local current_time_us = math.floor(stm.us(stm.now()))

    -- Let ImGui handle events first in select mode
    if app_state == "select" then
        imgui.handle_event(ev)

        if ev.type == app.EventType.KEY_DOWN then
            -- ESC to quit
            if ev.key_code == app.Keycode.ESCAPE then
                app.request_quit()
                return
            end

            -- Always handle navigation keys
            select_screen:handle_key(ev.key_code)
        end
        return
    end

    if app_state == "playing" then
        if ev.type == app.EventType.KEY_DOWN then
            if input_handler and conductor then
                -- Convert real time to chart time for judgment
                local chart_time_us = current_time_us - conductor.start_real_time_us
                input_handler:on_key(ev.key_code, true, chart_time_us)
            end

            -- ESC to return to select
            if ev.key_code == app.Keycode.ESCAPE then
                return_to_select()
            end

            -- Hi-Speed adjustment (1: down, 2: up)
            if ev.key_code == app.Keycode["1"] then
                scroll_speed = math.max(const.HISPEED_MIN, scroll_speed - const.HISPEED_STEP)
            elseif ev.key_code == app.Keycode["2"] then
                scroll_speed = math.min(const.HISPEED_MAX, scroll_speed + const.HISPEED_STEP)
            end
        elseif ev.type == app.EventType.KEY_UP then
            if input_handler and conductor then
                local chart_time_us = current_time_us - conductor.start_real_time_us
                input_handler:on_key(ev.key_code, false, chart_time_us)
            end
        end
        return
    end

    if app_state == "finished" then
        if ev.type == app.EventType.KEY_DOWN then
            if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.ENTER then
                return_to_select()
            end
        end
        return
    end
end

local function cleanup()
    cleanup_game()
    if audio_manager then
        audio_manager:shutdown()
    end
    imgui.shutdown()
    sdtx.shutdown()
    sgl.shutdown()
    gfx.shutdown()
end

-- Run the app
app.run(app.Desc({
    init_cb = init,
    frame_cb = frame,
    event_cb = event,
    cleanup_cb = cleanup,
    width = const.SCREEN_WIDTH,
    height = const.SCREEN_HEIGHT,
    window_title = "mane3d-rhythm",
    logger = { func = slog.func },
}))
