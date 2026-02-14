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

    imgui.set_next_window_pos({ 0, 0 }, Cond_Always)
    imgui.set_next_window_size({ const.SCREEN_WIDTH, const.SCREEN_HEIGHT }, Cond_Always)

    if imgui.begin_window("Result", nil, window_flags) then
        imgui.spacing()

        -- Title
        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 1.0, 1.0, 1.0 })
        imgui.text_unformatted("=== RESULT ===")
        imgui.pop_style_color(1)

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        -- Clear status
        if data.cleared then
            imgui.push_style_color_x_vec4(Col_Text, { 0.0, 1.0, 0.39, 1.0 })
            imgui.text_unformatted("CLEAR!")
        else
            imgui.push_style_color_x_vec4(Col_Text, { 1.0, 0.2, 0.2, 1.0 })
            imgui.text_unformatted("FAILED")
        end
        imgui.pop_style_color(1)

        imgui.spacing()

        -- Song info
        imgui.push_style_color_x_vec4(Col_Text, { 0.78, 0.78, 0.78, 1.0 })
        imgui.text_unformatted(data.title)
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.text_unformatted(data.artist)
        imgui.pop_style_color(1)

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        -- DJ LEVEL
        local level_color = get_level_color(data.dj_level)
        imgui.push_style_color_x_vec4(Col_Text, level_color)
        imgui.text_unformatted(string.format("DJ LEVEL: %s", data.dj_level))
        imgui.pop_style_color(1)

        imgui.spacing()

        -- EX Score
        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 1.0, 0.39, 1.0 })
        imgui.text_unformatted(string.format("EX SCORE: %d / %d", data.ex_score, data.max_ex_score))
        imgui.pop_style_color(1)

        -- Score rate
        local rate = 0
        if data.max_ex_score > 0 then
            rate = (data.ex_score / data.max_ex_score) * 100
        end
        imgui.push_style_color_x_vec4(Col_Text, { 0.78, 0.78, 0.78, 1.0 })
        imgui.text_unformatted(string.format("(%.2f%%)", rate))
        imgui.pop_style_color(1)

        imgui.spacing()

        -- Max combo
        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 0.78, 0.39, 1.0 })
        imgui.text_unformatted(string.format("MAX COMBO: %d", data.max_combo))
        imgui.pop_style_color(1)

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        -- Judgment breakdown
        imgui.push_style_color_x_vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.text_unformatted("--- JUDGMENT ---")
        imgui.pop_style_color(1)

        imgui.spacing()

        local stats = data.stats

        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 1.0, 0.39, 1.0 })
        imgui.text_unformatted(string.format("PGREAT: %4d", stats.pgreat))
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 0.78, 0.2, 1.0 })
        imgui.text_unformatted(string.format("GREAT:  %4d", stats.great))
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 0.39, 1.0, 0.39, 1.0 })
        imgui.text_unformatted(string.format("GOOD:   %4d", stats.good))
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 0.39, 0.39, 1.0, 1.0 })
        imgui.text_unformatted(string.format("BAD:    %4d", stats.bad))
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 0.59, 0.39, 0.39, 1.0 })
        imgui.text_unformatted(string.format("POOR:   %4d", stats.empty_poor))
        imgui.pop_style_color(1)

        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 0.39, 0.39, 1.0 })
        imgui.text_unformatted(string.format("MISS:   %4d", stats.miss))
        imgui.pop_style_color(1)

        imgui.spacing()

        -- FAST/SLOW
        imgui.push_style_color_x_vec4(Col_Text, { 0.39, 0.78, 1.0, 1.0 })
        imgui.text_unformatted(string.format("FAST: %d", stats.fast))
        imgui.pop_style_color(1)

        imgui.same_line(0, 20)

        imgui.push_style_color_x_vec4(Col_Text, { 1.0, 0.59, 0.39, 1.0 })
        imgui.text_unformatted(string.format("SLOW: %d", stats.slow))
        imgui.pop_style_color(1)

        imgui.spacing()

        -- Gauge info
        imgui.push_style_color_x_vec4(Col_Text, { 0.59, 0.59, 0.59, 1.0 })
        imgui.text_unformatted(string.format("GAUGE: %s %.1f%%", data.gauge_type:upper(), data.final_gauge))
        imgui.pop_style_color(1)

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        -- Instructions
        imgui.push_style_color_x_vec4(Col_Text, { 0.39, 0.39, 0.39, 1.0 })
        imgui.text_unformatted("Press ENTER or ESC to exit")
        imgui.pop_style_color(1)
    end
    imgui.end_window()
end

return ResultRenderer
