--- Result screen rendering (ImGui-based)
local imgui = require("imgui")
local const = require("examples.rhythm.const")

-- ImGui constants
local WindowFlags_NoResize = 2
local WindowFlags_NoMove = 4
local WindowFlags_NoCollapse = 32
local Cond_Always = 1
local Col_Text = 0

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
local ResultRenderer = {}
ResultRenderer.__index = ResultRenderer

--- Create a new ResultRenderer
---@return ResultRenderer
function ResultRenderer.new()
    local self = setmetatable({}, ResultRenderer)
    return self
end

--- Get color for DJ LEVEL (returns normalized RGBA)
---@param level string
---@return number[]
local function get_level_color(level)
    if level == "AAA" then
        return { 1.0, 0.84, 0.0, 1.0 }   -- Gold
    elseif level == "AA" then
        return { 1.0, 1.0, 0.39, 1.0 }   -- Yellow
    elseif level == "A" then
        return { 0.39, 1.0, 0.39, 1.0 }  -- Green
    elseif level == "B" then
        return { 0.39, 0.78, 1.0, 1.0 }  -- Light blue
    elseif level == "C" then
        return { 0.59, 0.59, 1.0, 1.0 }  -- Blue
    elseif level == "D" then
        return { 0.78, 0.59, 1.0, 1.0 }  -- Purple
    elseif level == "E" then
        return { 0.78, 0.78, 0.78, 1.0 } -- Gray
    else                                 -- F
        return { 0.59, 0.39, 0.39, 1.0 } -- Dark gray
    end
end

--- Draw the result screen
---@param data ResultData
function ResultRenderer:draw(data)
    local window_flags = WindowFlags_NoResize + WindowFlags_NoMove + WindowFlags_NoCollapse

    imgui.SetNextWindowPos({ 0, 0 }, Cond_Always)
    imgui.SetNextWindowSize({ const.SCREEN_WIDTH, const.SCREEN_HEIGHT }, Cond_Always)

    if imgui.Begin("Result", nil, window_flags) then
        imgui.Spacing()

        -- Title
        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 1.0, 1.0, 1.0 })
        imgui.TextUnformatted("=== RESULT ===")
        imgui.PopStyleColor(1)

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Clear status
        if data.cleared then
            imgui.PushStyleColor_X_Vec4(Col_Text, { 0.0, 1.0, 0.39, 1.0 })
            imgui.TextUnformatted("CLEAR!")
        else
            imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 0.2, 0.2, 1.0 })
            imgui.TextUnformatted("FAILED")
        end
        imgui.PopStyleColor(1)

        imgui.Spacing()

        -- Song info
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.78, 0.78, 0.78, 1.0 })
        imgui.TextUnformatted(data.title)
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.TextUnformatted(data.artist)
        imgui.PopStyleColor(1)

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- DJ LEVEL
        local level_color = get_level_color(data.dj_level)
        imgui.PushStyleColor_X_Vec4(Col_Text, level_color)
        imgui.TextUnformatted(string.format("DJ LEVEL: %s", data.dj_level))
        imgui.PopStyleColor(1)

        imgui.Spacing()

        -- EX Score
        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 1.0, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("EX SCORE: %d / %d", data.ex_score, data.max_ex_score))
        imgui.PopStyleColor(1)

        -- Score rate
        local rate = 0
        if data.max_ex_score > 0 then
            rate = (data.ex_score / data.max_ex_score) * 100
        end
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.78, 0.78, 0.78, 1.0 })
        imgui.TextUnformatted(string.format("(%.2f%%)", rate))
        imgui.PopStyleColor(1)

        imgui.Spacing()

        -- Max combo
        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 0.78, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("MAX COMBO: %d", data.max_combo))
        imgui.PopStyleColor(1)

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Judgment breakdown
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.TextUnformatted("--- JUDGMENT ---")
        imgui.PopStyleColor(1)

        imgui.Spacing()

        local stats = data.stats

        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 1.0, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("PGREAT: %4d", stats.pgreat))
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 0.78, 0.2, 1.0 })
        imgui.TextUnformatted(string.format("GREAT:  %4d", stats.great))
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.39, 1.0, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("GOOD:   %4d", stats.good))
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.39, 0.39, 1.0, 1.0 })
        imgui.TextUnformatted(string.format("BAD:    %4d", stats.bad))
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.59, 0.39, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("POOR:   %4d", stats.empty_poor))
        imgui.PopStyleColor(1)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 0.39, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("MISS:   %4d", stats.miss))
        imgui.PopStyleColor(1)

        imgui.Spacing()

        -- FAST/SLOW
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.39, 0.78, 1.0, 1.0 })
        imgui.TextUnformatted(string.format("FAST: %d", stats.fast))
        imgui.PopStyleColor(1)

        imgui.SameLine(0, 20)

        imgui.PushStyleColor_X_Vec4(Col_Text, { 1.0, 0.59, 0.39, 1.0 })
        imgui.TextUnformatted(string.format("SLOW: %d", stats.slow))
        imgui.PopStyleColor(1)

        imgui.Spacing()

        -- Gauge info
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.TextUnformatted(string.format("GAUGE: %s %.1f%%", data.gauge_type:upper(), data.final_gauge))
        imgui.PopStyleColor(1)

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Instructions
        imgui.PushStyleColor_X_Vec4(Col_Text, { 0.39, 0.39, 0.39, 1.0 })
        imgui.TextUnformatted("Press ENTER or ESC to exit")
        imgui.PopStyleColor(1)
    end
    imgui.End()
end

return ResultRenderer
