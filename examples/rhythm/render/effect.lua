--- Judgment effect rendering (ImGui-based)
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

local shadow_offsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- Draw text with outline
---@param text string
---@param color number[] RGBA
local function outlined_text(text, color)
    local pos = imgui.GetCursorPos()
    -- Shadow
    imgui.PushStyleColor_X_Vec4(Col_Text, { 0.0, 0.0, 0.0, color[4] })
    for _, off in ipairs(shadow_offsets) do
        imgui.SetCursorPos({ pos[1] + off[1], pos[2] + off[2] })
        imgui.TextUnformatted(text)
    end
    imgui.PopStyleColor(1)
    -- Foreground
    imgui.SetCursorPos(pos)
    imgui.PushStyleColor_X_Vec4(Col_Text, color)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor(1)
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

local JUDGMENT_DURATION_US = 500000 -- 500ms display duration

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

    imgui.SetNextWindowPos({ const.SCREEN_WIDTH * 0.5, const.SCREEN_HEIGHT * 0.55 }, Cond_Always, { 0.5, 0.5 })
    imgui.Begin("##hud_judgment", nil, hud_flags)
    outlined_text(text, { color[1], color[2], color[3], alpha })

    -- Timing indicator (FAST/SLOW)
    if display.timing then
        local timing_text = display.timing:upper()
        local timing_color = const.TIMING_COLORS[display.timing] or { 1, 1, 1, 1 }
        outlined_text(timing_text, { timing_color[1], timing_color[2], timing_color[3], alpha })
    end

    imgui.End()
end

--- Clear all effects
function EffectRenderer:clear()
    self.effects = {}
    self.judgment_display = nil
end

return EffectRenderer
