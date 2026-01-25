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
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)
    sdtx.pos(40, 20)
    sdtx.color3b(255, 255, 0)
    sdtx.puts(string.format("COMBO: %d", combo))
end

--- Draw song info
---@param title string
---@param artist string
---@param bpm number
function UIRenderer:draw_song_info(title, artist, bpm)
    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)
    sdtx.pos(2, 2)
    sdtx.color3b(200, 200, 200)
    sdtx.puts(title)
    sdtx.pos(2, 3)
    sdtx.color3b(150, 150, 150)
    sdtx.puts(artist)
    sdtx.pos(2, 4)
    sdtx.color3b(100, 100, 100)
    sdtx.puts(string.format("BPM: %.1f", bpm))
end

--- Draw state indicator
---@param state string
function UIRenderer:draw_state(state)
    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)
    sdtx.pos(2, 70)

    if state == "loading" then
        sdtx.color3b(255, 255, 0)
        sdtx.puts("LOADING...")
    elseif state == "finished" then
        sdtx.color3b(0, 255, 0)
        sdtx.puts("COMPLETE!")
    elseif state == "paused" then
        sdtx.color3b(255, 128, 0)
        sdtx.puts("PAUSED")
    end
end

--- Draw timing debug info
---@param current_beat number
---@param current_time_us integer
---@param bpm number
---@param hispeed number|nil
function UIRenderer:draw_debug(current_beat, current_time_us, bpm, hispeed)
    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)
    sdtx.pos(70, 2)
    sdtx.color3b(100, 100, 100)
    sdtx.puts(string.format("Beat: %.2f", current_beat))
    sdtx.pos(70, 3)
    sdtx.puts(string.format("Time: %.2fs", current_time_us / 1000000))
    sdtx.pos(70, 4)
    sdtx.puts(string.format("BPM: %.1f", bpm))

    -- Hi-Speed display
    if hispeed then
        sdtx.pos(70, 6)
        sdtx.color3b(0, 255, 255)
        sdtx.puts(string.format("HS: %.2f (1/2)", hispeed))
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
    sgl.begin_quads()
    sgl.c3f(0.2, 0.2, 0.2)
    sgl.v2f(x, y)
    sgl.v2f(x + width, y)
    sgl.v2f(x + width, y + height)
    sgl.v2f(x, y + height)
    sgl.end_()

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
    sgl.end_()

    -- Clear threshold line (80% for GROOVE)
    if gauge_type == "groove" then
        local threshold_y = y + height * 0.2 -- 80% from bottom = 20% from top
        sgl.begin_lines()
        sgl.c3f(1.0, 1.0, 1.0)
        sgl.v2f(x, threshold_y)
        sgl.v2f(x + width, threshold_y)
        sgl.end_()
    end

    -- Border
    sgl.begin_line_strip()
    sgl.c3f(0.5, 0.5, 0.5)
    sgl.v2f(x, y)
    sgl.v2f(x + width, y)
    sgl.v2f(x + width, y + height)
    sgl.v2f(x, y + height)
    sgl.v2f(x, y)
    sgl.end_()
end

--- Draw score and stats
---@param ex_score integer
---@param max_ex_score integer
---@param stats JudgeStats
function UIRenderer:draw_score(ex_score, max_ex_score, stats)
    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)

    -- EX Score
    sdtx.pos(2, 8)
    sdtx.color3b(255, 255, 255)
    sdtx.puts(string.format("EX: %d / %d", ex_score, max_ex_score))

    -- Score rate
    local rate = 0
    if max_ex_score > 0 then
        rate = (ex_score / max_ex_score) * 100
    end
    sdtx.pos(2, 9)
    sdtx.color3b(200, 200, 200)
    sdtx.puts(string.format("%.2f%%", rate))

    -- Judgment counts (compact)
    sdtx.pos(2, 11)
    sdtx.color3b(255, 255, 100)
    sdtx.puts(string.format("PG:%d G:%d", stats.pgreat, stats.great))
    sdtx.pos(2, 12)
    sdtx.color3b(100, 255, 100)
    sdtx.puts(string.format("GD:%d BD:%d", stats.good, stats.bad))
    sdtx.pos(2, 13)
    sdtx.color3b(255, 100, 100)
    sdtx.puts(string.format("PR:%d MS:%d", stats.empty_poor, stats.miss))

    -- FAST/SLOW
    sdtx.pos(2, 15)
    sdtx.color3b(100, 200, 255)
    sdtx.puts(string.format("FAST:%d", stats.fast))
    sdtx.pos(10, 15)
    sdtx.color3b(255, 150, 100)
    sdtx.puts(string.format("SLOW:%d", stats.slow))
end

return UIRenderer
