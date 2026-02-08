--- Gauge engine for rhythm game
--- Handles GROOVE, HARD, and EX-HARD gauge systems

---@class GaugeEngine
---@field gauge_type string "groove"|"hard"|"exhard"
---@field value number current gauge value (0-100)
---@field total number TOTAL value for gauge calculation
---@field notes integer total number of notes
---@field increase_per_note number gauge increase per PGREAT
local GaugeEngine = {}
GaugeEngine.__index = GaugeEngine

-- Gauge type configurations
local GAUGE_CONFIG = {
    groove = {
        initial = 20,
        floor = 2,
        clear_threshold = 80,
        -- Increase multipliers (of increase_per_note)
        increase = {
            pgreat = 1.0,
            great = 0.8,
            good = 0.4,
        },
        -- Decrease amounts (absolute %)
        decrease = {
            bad = 2,
            empty_poor = 6,
            miss = 6,
        },
    },
    hard = {
        initial = 100,
        floor = 0,
        clear_threshold = 0, -- any value > 0 is clear
        increase = {
            pgreat = 0.1,  -- minimal increase
            great = 0.08,
            good = 0.04,
        },
        decrease = {
            bad = 4,
            empty_poor = 10,
            miss = 10,
        },
    },
    exhard = {
        initial = 100,
        floor = 0,
        clear_threshold = 0,
        increase = {
            pgreat = 0.1,
            great = 0.08,
            good = 0.0, -- no increase on GOOD
        },
        decrease = {
            bad = 6,
            empty_poor = 18,
            miss = 18,
        },
    },
}

--- Calculate default TOTAL value for a chart
--- Formula from BMS spec: 7.605 * notes / (0.01 * notes + 6.5)
---@param notes integer
---@return number
local function calc_default_total(notes)
    if notes <= 0 then
        return 160 -- default fallback
    end
    return 7.605 * notes / (0.01 * notes + 6.5)
end

--- Create a new GaugeEngine
---@param gauge_type string "groove"|"hard"|"exhard"
---@param notes integer total number of notes in chart
---@param total number|nil TOTAL value from BMS (or nil for default)
---@return GaugeEngine
function GaugeEngine.new(gauge_type, notes, total)
    local self = setmetatable({}, GaugeEngine)

    self.gauge_type = gauge_type or "groove"
    self.notes = notes or 0
    self.total = total or calc_default_total(notes)

    local config = GAUGE_CONFIG[self.gauge_type] or GAUGE_CONFIG.groove
    self.value = config.initial

    -- Calculate increase per note (TOTAL / notes)
    if self.notes > 0 then
        self.increase_per_note = self.total / self.notes
    else
        self.increase_per_note = 0
    end

    return self
end

--- Process a judgment and update gauge
---@param judgment string
function GaugeEngine:on_judgment(judgment)
    local config = GAUGE_CONFIG[self.gauge_type] or GAUGE_CONFIG.groove

    -- Check for increase
    local increase_mult = config.increase[judgment]
    if increase_mult then
        self.value = self.value + self.increase_per_note * increase_mult
    end

    -- Check for decrease
    local decrease = config.decrease[judgment]
    if decrease then
        self.value = self.value - decrease
    end

    -- Clamp to valid range
    if self.value > 100 then
        self.value = 100
    elseif self.value < config.floor then
        self.value = config.floor
    end
end

--- Check if the gauge is in cleared state
---@return boolean
function GaugeEngine:is_cleared()
    local config = GAUGE_CONFIG[self.gauge_type] or GAUGE_CONFIG.groove

    if self.gauge_type == "hard" or self.gauge_type == "exhard" then
        -- HARD/EX-HARD: survive = clear (value > 0)
        return self.value > 0
    else
        -- GROOVE: need to reach threshold
        return self.value >= config.clear_threshold
    end
end

--- Check if the gauge has failed (HARD/EX-HARD only)
---@return boolean
function GaugeEngine:is_failed()
    if self.gauge_type == "hard" or self.gauge_type == "exhard" then
        return self.value <= 0
    end
    return false
end

--- Reset the gauge to initial state
function GaugeEngine:reset()
    local config = GAUGE_CONFIG[self.gauge_type] or GAUGE_CONFIG.groove
    self.value = config.initial
end

--- Get gauge color based on current value
---@return number, number, number RGB values (0-1)
function GaugeEngine:get_color()
    if self.gauge_type == "hard" or self.gauge_type == "exhard" then
        -- HARD: red
        return 1.0, 0.3, 0.3
    end

    -- GROOVE: red -> yellow -> green based on value
    if self.value < 80 then
        -- Red to yellow (0-80%)
        local t = self.value / 80
        return 1.0, t, 0.0
    else
        -- Yellow to green (80-100%)
        local t = (self.value - 80) / 20
        return 1.0 - t, 1.0, 0.0
    end
end

return GaugeEngine
