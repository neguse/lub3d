--- UI rendering (ImGui-based)
local imgui = require("imgui")
local const = require("examples.rhythm.const")

-- ImGui constants
local WINDOW_FLAGS_NO_TITLE_BAR <const> = 1
local WINDOW_FLAGS_NO_RESIZE <const> = 2
local WINDOW_FLAGS_NO_MOVE <const> = 4
local WINDOW_FLAGS_NO_SCROLLBAR <const> = 8
local WINDOW_FLAGS_NO_BACKGROUND <const> = 128
local WINDOW_FLAGS_NO_BRING_TO_FRONT_ON_FOCUS <const> = 8192
local WINDOW_FLAGS_NO_INPUTS <const> = 262144 + 524288 -- NoMouseInputs + NoNav
local COND_ALWAYS <const> = 1
local COL_TEXT <const> = 0

local hud_flags = WINDOW_FLAGS_NO_TITLE_BAR + WINDOW_FLAGS_NO_RESIZE + WINDOW_FLAGS_NO_MOVE
    + WINDOW_FLAGS_NO_SCROLLBAR + WINDOW_FLAGS_NO_INPUTS + WINDOW_FLAGS_NO_BRING_TO_FRONT_ON_FOCUS
    + WINDOW_FLAGS_NO_BACKGROUND

local shadow_color = { 0.0, 0.0, 0.0, 1.0 }
local shadow_offsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- Draw text with outline (shadow in 4 directions)
---@param text string
---@param color number[]
local function outlined_text(text, color)
    local pos = imgui.get_cursor_pos()
    -- Shadow
    imgui.push_style_color_x_vec4(COL_TEXT, shadow_color)
    for _, off in ipairs(shadow_offsets) do
        imgui.set_cursor_pos({ pos[1] + off[1], pos[2] + off[2] })
        imgui.text_unformatted(text)
    end
    imgui.pop_style_color(1)
    -- Foreground
    imgui.set_cursor_pos(pos)
    imgui.push_style_color_x_vec4(COL_TEXT, color)
    imgui.text_unformatted(text)
    imgui.pop_style_color(1)
end

---@class UIRenderer
local UIRenderer = {}
UIRenderer.__index = UIRenderer

--- Create a new UIRenderer
---@return UIRenderer
function UIRenderer.new()
    local self = setmetatable({}, UIRenderer)
    return self
end

--- Draw combo counter
---@param combo integer
function UIRenderer:draw_combo(combo)
    if combo <= 0 then
        return
    end

    imgui.set_next_window_pos({ const.SCREEN_WIDTH * 0.5, const.SCREEN_HEIGHT * 0.4 }, COND_ALWAYS, { 0.5, 0.5 })
    imgui.begin_window("##hud_combo", nil, hud_flags)
    outlined_text(string.format("COMBO: %d", combo), { 1.0, 1.0, 0.0, 1.0 })
    imgui.end_window()
end

--- Draw song info
---@param title string
---@param artist string
---@param bpm number
function UIRenderer:draw_song_info(title, artist, bpm)
    imgui.set_next_window_pos({ 10, 10 }, COND_ALWAYS)
    imgui.begin_window("##hud_song", nil, hud_flags)
    outlined_text(title, { 0.78, 0.78, 0.78, 1.0 })
    outlined_text(artist, { 0.59, 0.59, 0.59, 1.0 })
    outlined_text(string.format("BPM: %.1f", bpm), { 0.39, 0.39, 0.39, 1.0 })
    imgui.end_window()
end

--- Draw state indicator
---@param state string
function UIRenderer:draw_state(state)
    imgui.set_next_window_pos({ 10, const.SCREEN_HEIGHT - 40 }, COND_ALWAYS)
    imgui.begin_window("##hud_state", nil, hud_flags)

    if state == "loading" then
        outlined_text("LOADING...", { 1.0, 1.0, 0.0, 1.0 })
    elseif state == "finished" then
        outlined_text("COMPLETE!", { 0.0, 1.0, 0.0, 1.0 })
    elseif state == "paused" then
        outlined_text("PAUSED", { 1.0, 0.5, 0.0, 1.0 })
    end

    imgui.end_window()
end

--- Draw timing debug info
---@param current_beat number
---@param current_time_us integer
---@param bpm number
---@param hispeed number|nil
function UIRenderer:draw_debug(current_beat, current_time_us, bpm, hispeed)
    imgui.set_next_window_pos({ const.SCREEN_WIDTH - 200, 10 }, COND_ALWAYS)
    imgui.begin_window("##hud_debug", nil, hud_flags)

    outlined_text(string.format("Beat: %.2f", current_beat), { 0.39, 0.39, 0.39, 1.0 })
    outlined_text(string.format("Time: %.2fs", current_time_us / 1000000), { 0.39, 0.39, 0.39, 1.0 })
    outlined_text(string.format("BPM: %.1f", bpm), { 0.39, 0.39, 0.39, 1.0 })

    if hispeed then
        outlined_text(string.format("HS: %.2f (1/2)", hispeed), { 0.0, 1.0, 1.0, 1.0 })
    end

    imgui.end_window()
end

--- Draw gauge bar
---@param gauge_value number 0-100
---@param gauge_type string "groove"|"hard"|"exhard"
---@param sgl any sokol.gl module
function UIRenderer:draw_gauge(gauge_value, gauge_type, sgl)
    if not sgl then return end

    local x = const.GAUGE_X
    local y = const.GAUGE_Y
    local width = const.GAUGE_WIDTH
    local height = const.GAUGE_HEIGHT

    -- Background
    sgl.begin_quads()
    sgl.c3f(0.2, 0.2, 0.2)
    sgl.v2f(x, y)
    sgl.v2f(x + width, y)
    sgl.v2f(x + width, y + height)
    sgl.v2f(x, y + height)
    sgl["end"]()

    -- Gauge fill (from bottom to top)
    local fill_height = height * (gauge_value / 100)
    local fill_y = y + height - fill_height

    -- Color based on gauge type and value
    local r, g, b
    if gauge_type == "hard" or gauge_type == "exhard" then
        r, g, b = 1.0, 0.3, 0.3 -- red
    else
        -- GROOVE: red -> yellow -> green
        if gauge_value < 80 then
            local t = gauge_value / 80
            r, g, b = 1.0, t, 0.0
        else
            local t = (gauge_value - 80) / 20
            r, g, b = 1.0 - t, 1.0, 0.0
        end
    end

    sgl.begin_quads()
    sgl.c3f(r, g, b)
    sgl.v2f(x, fill_y)
    sgl.v2f(x + width, fill_y)
    sgl.v2f(x + width, y + height)
    sgl.v2f(x, y + height)
    sgl["end"]()

    -- Clear threshold line (80% for GROOVE)
    if gauge_type == "groove" then
        local threshold_y = y + height * 0.2 -- 80% from bottom = 20% from top
        sgl.begin_lines()
        sgl.c3f(1.0, 1.0, 1.0)
        sgl.v2f(x, threshold_y)
        sgl.v2f(x + width, threshold_y)
        sgl["end"]()
    end

    -- Border
    sgl.begin_line_strip()
    sgl.c3f(0.5, 0.5, 0.5)
    sgl.v2f(x, y)
    sgl.v2f(x + width, y)
    sgl.v2f(x + width, y + height)
    sgl.v2f(x, y + height)
    sgl.v2f(x, y)
    sgl["end"]()
end

--- Draw score and stats
---@param ex_score integer
---@param max_ex_score integer
---@param stats JudgeStats
function UIRenderer:draw_score(ex_score, max_ex_score, stats)
    imgui.set_next_window_pos({ 10, 100 }, COND_ALWAYS)
    imgui.begin_window("##hud_score", nil, hud_flags)

    -- EX Score
    outlined_text(string.format("EX: %d / %d", ex_score, max_ex_score), { 1.0, 1.0, 1.0, 1.0 })

    -- Score rate
    local rate = 0
    if max_ex_score > 0 then
        rate = (ex_score / max_ex_score) * 100
    end
    outlined_text(string.format("%.2f%%", rate), { 0.78, 0.78, 0.78, 1.0 })

    imgui.spacing()

    -- Judgment counts
    outlined_text(string.format("PG:%d G:%d", stats.pgreat, stats.great), { 1.0, 1.0, 0.39, 1.0 })
    outlined_text(string.format("GD:%d BD:%d", stats.good, stats.bad), { 0.39, 1.0, 0.39, 1.0 })
    outlined_text(string.format("PR:%d MS:%d", stats.empty_poor, stats.miss), { 1.0, 0.39, 0.39, 1.0 })

    imgui.spacing()

    -- FAST/SLOW
    outlined_text(string.format("FAST:%d  SLOW:%d", stats.fast, stats.slow), { 0.39, 0.78, 1.0, 1.0 })

    imgui.end_window()
end

return UIRenderer
