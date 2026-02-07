--- UI rendering (ImGui-based)
local imgui = require("imgui")
local const = require("examples.rhythm.const")

-- ImGui constants
local WindowFlags_NoTitleBar = 1
local WindowFlags_NoResize = 2
local WindowFlags_NoMove = 4
local WindowFlags_NoScrollbar = 8
local WindowFlags_NoBackground = 128
local WindowFlags_NoBringToFrontOnFocus = 8192
local WindowFlags_NoInputs = 262144 + 524288 -- NoMouseInputs + NoNav
local Cond_Always = 1
local Col_Text = 0

local hud_flags = WindowFlags_NoTitleBar + WindowFlags_NoResize + WindowFlags_NoMove
    + WindowFlags_NoScrollbar + WindowFlags_NoInputs + WindowFlags_NoBringToFrontOnFocus
    + WindowFlags_NoBackground

local shadow_color = {0.0, 0.0, 0.0, 1.0}
local shadow_offsets = {{1,0},{-1,0},{0,1},{0,-1}}

--- Draw text with outline (shadow in 4 directions)
---@param text string
---@param color number[]
local function outlined_text(text, color)
    local pos = imgui.GetCursorPos()
    -- Shadow
    imgui.PushStyleColor_X_Vec4(Col_Text, shadow_color)
    for _, off in ipairs(shadow_offsets) do
        imgui.SetCursorPos({pos[1] + off[1], pos[2] + off[2]})
        imgui.TextUnformatted(text)
    end
    imgui.PopStyleColor(1)
    -- Foreground
    imgui.SetCursorPos(pos)
    imgui.PushStyleColor_X_Vec4(Col_Text, color)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor(1)
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

    imgui.SetNextWindowPos({const.SCREEN_WIDTH * 0.5, const.SCREEN_HEIGHT * 0.4}, Cond_Always, {0.5, 0.5})
    imgui.Begin("##hud_combo", nil, hud_flags)
    outlined_text(string.format("COMBO: %d", combo), {1.0, 1.0, 0.0, 1.0})
    imgui.End()
end

--- Draw song info
---@param title string
---@param artist string
---@param bpm number
function UIRenderer:draw_song_info(title, artist, bpm)
    imgui.SetNextWindowPos({10, 10}, Cond_Always)
    imgui.Begin("##hud_song", nil, hud_flags)
    outlined_text(title, {0.78, 0.78, 0.78, 1.0})
    outlined_text(artist, {0.59, 0.59, 0.59, 1.0})
    outlined_text(string.format("BPM: %.1f", bpm), {0.39, 0.39, 0.39, 1.0})
    imgui.End()
end

--- Draw state indicator
---@param state string
function UIRenderer:draw_state(state)
    imgui.SetNextWindowPos({10, const.SCREEN_HEIGHT - 40}, Cond_Always)
    imgui.Begin("##hud_state", nil, hud_flags)

    if state == "loading" then
        outlined_text("LOADING...", {1.0, 1.0, 0.0, 1.0})
    elseif state == "finished" then
        outlined_text("COMPLETE!", {0.0, 1.0, 0.0, 1.0})
    elseif state == "paused" then
        outlined_text("PAUSED", {1.0, 0.5, 0.0, 1.0})
    end

    imgui.End()
end

--- Draw timing debug info
---@param current_beat number
---@param current_time_us integer
---@param bpm number
---@param hispeed number|nil
function UIRenderer:draw_debug(current_beat, current_time_us, bpm, hispeed)
    imgui.SetNextWindowPos({const.SCREEN_WIDTH - 200, 10}, Cond_Always)
    imgui.Begin("##hud_debug", nil, hud_flags)

    outlined_text(string.format("Beat: %.2f", current_beat), {0.39, 0.39, 0.39, 1.0})
    outlined_text(string.format("Time: %.2fs", current_time_us / 1000000), {0.39, 0.39, 0.39, 1.0})
    outlined_text(string.format("BPM: %.1f", bpm), {0.39, 0.39, 0.39, 1.0})

    if hispeed then
        outlined_text(string.format("HS: %.2f (1/2)", hispeed), {0.0, 1.0, 1.0, 1.0})
    end

    imgui.End()
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
    sgl.BeginQuads()
    sgl.C3f(0.2, 0.2, 0.2)
    sgl.V2f(x, y)
    sgl.V2f(x + width, y)
    sgl.V2f(x + width, y + height)
    sgl.V2f(x, y + height)
    sgl.End()

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

    sgl.BeginQuads()
    sgl.C3f(r, g, b)
    sgl.V2f(x, fill_y)
    sgl.V2f(x + width, fill_y)
    sgl.V2f(x + width, y + height)
    sgl.V2f(x, y + height)
    sgl.End()

    -- Clear threshold line (80% for GROOVE)
    if gauge_type == "groove" then
        local threshold_y = y + height * 0.2 -- 80% from bottom = 20% from top
        sgl.BeginLines()
        sgl.C3f(1.0, 1.0, 1.0)
        sgl.V2f(x, threshold_y)
        sgl.V2f(x + width, threshold_y)
        sgl.End()
    end

    -- Border
    sgl.BeginLineStrip()
    sgl.C3f(0.5, 0.5, 0.5)
    sgl.V2f(x, y)
    sgl.V2f(x + width, y)
    sgl.V2f(x + width, y + height)
    sgl.V2f(x, y + height)
    sgl.V2f(x, y)
    sgl.End()
end

--- Draw score and stats
---@param ex_score integer
---@param max_ex_score integer
---@param stats JudgeStats
function UIRenderer:draw_score(ex_score, max_ex_score, stats)
    imgui.SetNextWindowPos({10, 100}, Cond_Always)
    imgui.Begin("##hud_score", nil, hud_flags)

    -- EX Score
    outlined_text(string.format("EX: %d / %d", ex_score, max_ex_score), {1.0, 1.0, 1.0, 1.0})

    -- Score rate
    local rate = 0
    if max_ex_score > 0 then
        rate = (ex_score / max_ex_score) * 100
    end
    outlined_text(string.format("%.2f%%", rate), {0.78, 0.78, 0.78, 1.0})

    imgui.Spacing()

    -- Judgment counts
    outlined_text(string.format("PG:%d G:%d", stats.pgreat, stats.great), {1.0, 1.0, 0.39, 1.0})
    outlined_text(string.format("GD:%d BD:%d", stats.good, stats.bad), {0.39, 1.0, 0.39, 1.0})
    outlined_text(string.format("PR:%d MS:%d", stats.empty_poor, stats.miss), {1.0, 0.39, 0.39, 1.0})

    imgui.Spacing()

    -- FAST/SLOW
    outlined_text(string.format("FAST:%d  SLOW:%d", stats.fast, stats.slow), {0.39, 0.78, 1.0, 1.0})

    imgui.End()
end

return UIRenderer
