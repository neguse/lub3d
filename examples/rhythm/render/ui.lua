--- UI rendering
local const = require("examples.rhythm.const")

---@class UIRenderer
---@field sdtx any sokol.debugtext module
local UIRenderer = {}
UIRenderer.__index = UIRenderer

--- Create a new UIRenderer
---@param sdtx any sokol.debugtext module
---@return UIRenderer
function UIRenderer.new(sdtx)
    local self = setmetatable({}, UIRenderer)
    self.sdtx = sdtx
    return self
end

--- Draw combo counter
---@param combo integer
function UIRenderer:draw_combo(combo)
    if combo <= 0 then
        return
    end

    local sdtx = self.sdtx
    sdtx.Canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.Origin(0, 0)
    sdtx.Pos(40, 20)
    sdtx.Color3b(255, 255, 0)
    sdtx.Puts(string.format("COMBO: %d", combo))
end

--- Draw song info
---@param title string
---@param artist string
---@param bpm number
function UIRenderer:draw_song_info(title, artist, bpm)
    local sdtx = self.sdtx
    sdtx.Canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.Origin(0, 0)
    sdtx.Pos(2, 2)
    sdtx.Color3b(200, 200, 200)
    sdtx.Puts(title)
    sdtx.Pos(2, 3)
    sdtx.Color3b(150, 150, 150)
    sdtx.Puts(artist)
    sdtx.Pos(2, 4)
    sdtx.Color3b(100, 100, 100)
    sdtx.Puts(string.format("BPM: %.1f", bpm))
end

--- Draw state indicator
---@param state string
function UIRenderer:draw_state(state)
    local sdtx = self.sdtx
    sdtx.Canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.Origin(0, 0)
    sdtx.Pos(2, 70)

    if state == "loading" then
        sdtx.Color3b(255, 255, 0)
        sdtx.Puts("LOADING...")
    elseif state == "finished" then
        sdtx.Color3b(0, 255, 0)
        sdtx.Puts("COMPLETE!")
    elseif state == "paused" then
        sdtx.Color3b(255, 128, 0)
        sdtx.Puts("PAUSED")
    end
end

--- Draw timing debug info
---@param current_beat number
---@param current_time_us integer
---@param bpm number
---@param hispeed number|nil
function UIRenderer:draw_debug(current_beat, current_time_us, bpm, hispeed)
    local sdtx = self.sdtx
    sdtx.Canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.Origin(0, 0)
    sdtx.Pos(70, 2)
    sdtx.Color3b(100, 100, 100)
    sdtx.Puts(string.format("Beat: %.2f", current_beat))
    sdtx.Pos(70, 3)
    sdtx.Puts(string.format("Time: %.2fs", current_time_us / 1000000))
    sdtx.Pos(70, 4)
    sdtx.Puts(string.format("BPM: %.1f", bpm))

    -- Hi-Speed display
    if hispeed then
        sdtx.Pos(70, 6)
        sdtx.Color3b(0, 255, 255)
        sdtx.Puts(string.format("HS: %.2f (1/2)", hispeed))
    end
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
    local sdtx = self.sdtx
    sdtx.Canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.Origin(0, 0)

    -- EX Score
    sdtx.Pos(2, 8)
    sdtx.Color3b(255, 255, 255)
    sdtx.Puts(string.format("EX: %d / %d", ex_score, max_ex_score))

    -- Score rate
    local rate = 0
    if max_ex_score > 0 then
        rate = (ex_score / max_ex_score) * 100
    end
    sdtx.Pos(2, 9)
    sdtx.Color3b(200, 200, 200)
    sdtx.Puts(string.format("%.2f%%", rate))

    -- Judgment counts (compact)
    sdtx.Pos(2, 11)
    sdtx.Color3b(255, 255, 100)
    sdtx.Puts(string.format("PG:%d G:%d", stats.pgreat, stats.great))
    sdtx.Pos(2, 12)
    sdtx.Color3b(100, 255, 100)
    sdtx.Puts(string.format("GD:%d BD:%d", stats.good, stats.bad))
    sdtx.Pos(2, 13)
    sdtx.Color3b(255, 100, 100)
    sdtx.Puts(string.format("PR:%d MS:%d", stats.empty_poor, stats.miss))

    -- FAST/SLOW
    sdtx.Pos(2, 15)
    sdtx.Color3b(100, 200, 255)
    sdtx.Puts(string.format("FAST:%d", stats.fast))
    sdtx.Pos(10, 15)
    sdtx.Color3b(255, 150, 100)
    sdtx.Puts(string.format("SLOW:%d", stats.slow))
end

return UIRenderer
