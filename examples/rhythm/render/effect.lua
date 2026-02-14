--- Judgment effect rendering (ImGui-based)
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

local shadow_offsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- Draw text with outline
---@param text string
---@param color number[] RGBA
local function outlined_text(text, color)
    local pos = imgui.get_cursor_pos()
    -- Shadow
    imgui.push_style_color_x_vec4(COL_TEXT, { 0.0, 0.0, 0.0, color[4] })
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

---@class JudgmentEffect
---@field judgment string
---@field timing string|nil
---@field start_time_us integer
---@field duration_us integer
---@field lane integer|nil

---@class EffectRenderer
---@field effects JudgmentEffect[] active effects
---@field judgment_display JudgmentEffect|nil current judgment to display
local EffectRenderer = {}
EffectRenderer.__index = EffectRenderer

local JUDGMENT_DURATION_US <const> = 500000 -- 500ms display duration

--- Create a new EffectRenderer
---@return EffectRenderer
function EffectRenderer.new()
    local self = setmetatable({}, EffectRenderer)
    self.effects = {}
    self.judgment_display = nil
    return self
end

--- Add a judgment effect
---@param judgment string
---@param timing string|nil
---@param time_us integer
---@param lane integer|nil
function EffectRenderer:add_judgment(judgment, timing, time_us, lane)
    self.judgment_display = {
        judgment = judgment,
        timing = timing,
        start_time_us = time_us,
        duration_us = JUDGMENT_DURATION_US,
        lane = lane,
    }

    if lane then
        table.insert(self.effects, {
            judgment = judgment,
            timing = timing,
            start_time_us = time_us,
            duration_us = JUDGMENT_DURATION_US,
            lane = lane,
        })
    end
end

--- Update effects (remove expired ones)
---@param current_time_us integer
function EffectRenderer:update(current_time_us)
    if self.judgment_display then
        local elapsed = current_time_us - self.judgment_display.start_time_us
        if elapsed > self.judgment_display.duration_us then
            self.judgment_display = nil
        end
    end

    local i = 1
    while i <= #self.effects do
        local effect = self.effects[i]
        local elapsed = current_time_us - effect.start_time_us
        if elapsed > effect.duration_us then
            table.remove(self.effects, i)
        else
            i = i + 1
        end
    end
end

--- Draw all effects
---@param current_time_us integer
function EffectRenderer:draw(current_time_us)
    if not self.judgment_display then
        return
    end

    local display = self.judgment_display --[[@as JudgmentEffect]]
    local elapsed = current_time_us - display.start_time_us
    local progress = elapsed / display.duration_us
    local alpha = 1.0 - progress

    -- Judgment text
    local text = const.JUDGMENT_TEXT[display.judgment] or display.judgment
    local color = const.JUDGMENT_COLORS[display.judgment] or { 1, 1, 1, 1 }

    imgui.set_next_window_pos({ const.SCREEN_WIDTH * 0.5, const.SCREEN_HEIGHT * 0.55 }, COND_ALWAYS, { 0.5, 0.5 })
    imgui.begin_window("##hud_judgment", nil, hud_flags)
    outlined_text(text, { color[1], color[2], color[3], alpha })

    -- Timing indicator (FAST/SLOW)
    if display.timing then
        local timing_text = display.timing:upper()
        local timing_color = const.TIMING_COLORS[display.timing] or { 1, 1, 1, 1 }
        outlined_text(timing_text, { timing_color[1], timing_color[2], timing_color[3], alpha })
    end

    imgui.end_window()
end

--- Clear all effects
function EffectRenderer:clear()
    self.effects = {}
    self.judgment_display = nil
end

return EffectRenderer
