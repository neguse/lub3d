--- Judgment effect rendering
local const = require("examples.rhythm.const")

---@class JudgmentEffect
---@field judgment string
---@field timing string|nil
---@field start_time_us integer
---@field duration_us integer
---@field lane integer|nil

---@class EffectRenderer
---@field sdtx any sokol.debugtext module
---@field sgl any sokol.gl module
---@field effects JudgmentEffect[] active effects
---@field judgment_display JudgmentEffect|nil current judgment to display
local EffectRenderer = {}
EffectRenderer.__index = EffectRenderer

local JUDGMENT_DURATION_US = 500000 -- 500ms display duration

--- Create a new EffectRenderer
---@param sdtx any sokol.debugtext module
---@param sgl any|nil sokol.gl module (optional, for graphics effects)
---@return EffectRenderer
function EffectRenderer.new(sdtx, sgl)
    local self = setmetatable({}, EffectRenderer)
    self.sdtx = sdtx
    self.sgl = sgl
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
    -- Update the main judgment display
    self.judgment_display = {
        judgment = judgment,
        timing = timing,
        start_time_us = time_us,
        duration_us = JUDGMENT_DURATION_US,
        lane = lane,
    }

    -- Also add to effects list for per-lane effects
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
    -- Update main judgment display
    if self.judgment_display then
        local elapsed = current_time_us - self.judgment_display.start_time_us
        if elapsed > self.judgment_display.duration_us then
            self.judgment_display = nil
        end
    end

    -- Update per-lane effects
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

--- Draw the judgment text at center
---@param current_time_us integer
function EffectRenderer:draw_judgment(current_time_us)
    if not self.judgment_display then
        return
    end

    local display = self.judgment_display
    local elapsed = current_time_us - display.start_time_us
    local progress = elapsed / display.duration_us

    -- Fade out effect
    local alpha = 1.0 - progress

    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)

    -- Get judgment text and color
    local text = const.JUDGMENT_TEXT[display.judgment] or display.judgment
    local color = const.JUDGMENT_COLORS[display.judgment] or { 1, 1, 1, 1 }

    -- Apply alpha
    local r = math.floor(color[1] * 255 * alpha)
    local g = math.floor(color[2] * 255 * alpha)
    local b = math.floor(color[3] * 255 * alpha)

    -- Center position
    local text_len = #text
    local x = 40 - math.floor(text_len / 2)
    local y = 35

    sdtx.pos(x, y)
    sdtx.color3b(r, g, b)
    sdtx.puts(text)
end

--- Draw FAST/SLOW indicator
---@param current_time_us integer
function EffectRenderer:draw_timing_indicator(current_time_us)
    if not self.judgment_display then
        return
    end

    local display = self.judgment_display
    if not display.timing then
        return
    end

    local elapsed = current_time_us - display.start_time_us
    local progress = elapsed / display.duration_us
    local alpha = 1.0 - progress

    local sdtx = self.sdtx
    sdtx.canvas(const.SCREEN_WIDTH / 2, const.SCREEN_HEIGHT / 2)
    sdtx.origin(0, 0)

    local text = display.timing:upper()
    local color = const.TIMING_COLORS[display.timing] or { 1, 1, 1, 1 }

    local r = math.floor(color[1] * 255 * alpha)
    local g = math.floor(color[2] * 255 * alpha)
    local b = math.floor(color[3] * 255 * alpha)

    -- Position below judgment
    local text_len = #text
    local x = 40 - math.floor(text_len / 2)
    local y = 37

    sdtx.pos(x, y)
    sdtx.color3b(r, g, b)
    sdtx.puts(text)
end

--- Draw all effects
---@param current_time_us integer
function EffectRenderer:draw(current_time_us)
    self:draw_judgment(current_time_us)
    self:draw_timing_indicator(current_time_us)
end

--- Clear all effects
function EffectRenderer:clear()
    self.effects = {}
    self.judgment_display = nil
end

return EffectRenderer
