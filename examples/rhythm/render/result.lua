--- Result screen rendering
local const = require("examples.rhythm.const")

---@class ResultData
---@field title string
---@field artist string
---@field ex_score integer
---@field max_ex_score integer
---@field dj_level string
---@field cleared boolean
---@field gauge_type string
---@field final_gauge number
---@field stats JudgeStats
---@field max_combo integer
---@field total_notes integer

---@class ResultRenderer
---@field sdtx any sokol.debugtext module
---@field sgl any|nil sokol.gl module
local ResultRenderer = {}
ResultRenderer.__index = ResultRenderer

--- Create a new ResultRenderer
---@param sdtx any sokol.debugtext module
---@param sgl any|nil sokol.gl module
---@return ResultRenderer
function ResultRenderer.new(sdtx, sgl)
    local self = setmetatable({}, ResultRenderer)
    self.sdtx = sdtx
    self.sgl = sgl
    return self
end

--- Draw the result screen
---@param data ResultData
function ResultRenderer:draw(data)
    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)

    -- Title
    sdtx.pos(30, 5)
    sdtx.color3b(255, 255, 255)
    sdtx.puts("=== RESULT ===")

    -- Clear status
    sdtx.pos(35, 8)
    if data.cleared then
        sdtx.color3b(0, 255, 100)
        sdtx.puts("CLEAR!")
    else
        sdtx.color3b(255, 50, 50)
        sdtx.puts("FAILED")
    end

    -- Song info
    sdtx.pos(20, 12)
    sdtx.color3b(200, 200, 200)
    sdtx.puts(data.title)
    sdtx.pos(20, 13)
    sdtx.color3b(150, 150, 150)
    sdtx.puts(data.artist)

    -- DJ LEVEL (big)
    sdtx.pos(35, 17)
    local level_color = self:get_level_color(data.dj_level)
    sdtx.color3b(level_color[1], level_color[2], level_color[3])
    sdtx.puts(string.format("DJ LEVEL: %s", data.dj_level))

    -- EX Score
    sdtx.pos(25, 21)
    sdtx.color3b(255, 255, 100)
    sdtx.puts(string.format("EX SCORE: %d / %d", data.ex_score, data.max_ex_score))

    -- Score rate
    local rate = 0
    if data.max_ex_score > 0 then
        rate = (data.ex_score / data.max_ex_score) * 100
    end
    sdtx.pos(30, 22)
    sdtx.color3b(200, 200, 200)
    sdtx.puts(string.format("(%.2f%%)", rate))

    -- Max combo
    sdtx.pos(30, 24)
    sdtx.color3b(255, 200, 100)
    sdtx.puts(string.format("MAX COMBO: %d", data.max_combo))

    -- Judgment breakdown
    sdtx.pos(20, 28)
    sdtx.color3b(150, 150, 150)
    sdtx.puts("--- JUDGMENT ---")

    local stats = data.stats
    local y = 30

    -- PGREAT
    sdtx.pos(25, y)
    sdtx.color3b(255, 255, 100)
    sdtx.puts(string.format("PGREAT: %4d", stats.pgreat))
    y = y + 1

    -- GREAT
    sdtx.pos(25, y)
    sdtx.color3b(255, 200, 50)
    sdtx.puts(string.format("GREAT:  %4d", stats.great))
    y = y + 1

    -- GOOD
    sdtx.pos(25, y)
    sdtx.color3b(100, 255, 100)
    sdtx.puts(string.format("GOOD:   %4d", stats.good))
    y = y + 1

    -- BAD
    sdtx.pos(25, y)
    sdtx.color3b(100, 100, 255)
    sdtx.puts(string.format("BAD:    %4d", stats.bad))
    y = y + 1

    -- POOR (empty)
    sdtx.pos(25, y)
    sdtx.color3b(150, 100, 100)
    sdtx.puts(string.format("POOR:   %4d", stats.empty_poor))
    y = y + 1

    -- MISS
    sdtx.pos(25, y)
    sdtx.color3b(255, 100, 100)
    sdtx.puts(string.format("MISS:   %4d", stats.miss))
    y = y + 2

    -- FAST/SLOW
    sdtx.pos(25, y)
    sdtx.color3b(100, 200, 255)
    sdtx.puts(string.format("FAST: %d", stats.fast))
    sdtx.pos(40, y)
    sdtx.color3b(255, 150, 100)
    sdtx.puts(string.format("SLOW: %d", stats.slow))
    y = y + 2

    -- Gauge info
    sdtx.pos(25, y)
    sdtx.color3b(150, 150, 150)
    sdtx.puts(string.format("GAUGE: %s %.1f%%", data.gauge_type:upper(), data.final_gauge))
    y = y + 3

    -- Instructions
    sdtx.pos(25, y)
    sdtx.color3b(100, 100, 100)
    sdtx.puts("Press ENTER or ESC to exit")
end

--- Get color for DJ LEVEL
---@param level string
---@return integer[]
function ResultRenderer:get_level_color(level)
    if level == "AAA" then
        return { 255, 215, 0 }   -- Gold
    elseif level == "AA" then
        return { 255, 255, 100 } -- Yellow
    elseif level == "A" then
        return { 100, 255, 100 } -- Green
    elseif level == "B" then
        return { 100, 200, 255 } -- Light blue
    elseif level == "C" then
        return { 150, 150, 255 } -- Blue
    elseif level == "D" then
        return { 200, 150, 255 } -- Purple
    elseif level == "E" then
        return { 200, 200, 200 } -- Gray
    else -- F
        return { 150, 100, 100 } -- Dark gray
    end
end

return ResultRenderer
