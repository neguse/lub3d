--- Playfield logic - handles note-key matching and judgment
local const = require("examples.rhythm.const")
local JudgeEngine = require("examples.rhythm.core.judge")
local ScoringEngine = require("examples.rhythm.core.scoring")
local GaugeEngine = require("examples.rhythm.core.gauge")

---@class JudgmentEvent
---@field judgment string
---@field note Note|nil
---@field diff integer|nil
---@field timing string|nil
---@field time_us integer when it happened

---@class Playfield
---@field state GameState
---@field input_handler InputHandler
---@field judge JudgeEngine
---@field scoring ScoringEngine
---@field gauge GaugeEngine
---@field last_judgment JudgmentEvent|nil most recent judgment for display
---@field on_note_hit function|nil callback when note is hit
---@field on_note_miss function|nil callback when note is missed
---@field on_judgment function|nil callback when judgment occurs
local Playfield = {}
Playfield.__index = Playfield

--- Create a new Playfield
---@param state GameState
---@param input_handler InputHandler
---@param options table|nil optional settings { gauge_type, rank, total }
---@return Playfield
function Playfield.new(state, input_handler, options)
    local self = setmetatable({}, Playfield)
    options = options or {}

    self.state = state
    self.input_handler = input_handler
    self.on_note_hit = nil
    self.on_note_miss = nil
    self.on_judgment = nil
    self.last_judgment = nil

    -- Initialize engines (will be set up properly when chart is loaded)
    self.judge = JudgeEngine.new(options.rank)
    self.scoring = ScoringEngine.new(0)
    self.gauge = GaugeEngine.new(options.gauge_type or "groove", 0, options.total)

    return self
end

--- Initialize engines with chart data
---@param chart UniversalChart
function Playfield:init_with_chart(chart)
    local notes = chart.notes
    local total_notes = #notes

    -- Initialize JudgeEngine with notes
    self.judge:load_notes(notes)

    -- Initialize ScoringEngine
    self.scoring = ScoringEngine.new(total_notes)

    -- Initialize GaugeEngine (preserve gauge_type from constructor)
    local gauge_type = self.gauge.gauge_type
    local total = chart.meta and chart.meta.total or nil
    self.gauge = GaugeEngine.new(gauge_type, total_notes, total)
end

--- Update playfield logic
---@param current_time_us integer
---@param current_beat number
function Playfield:update(current_time_us, current_beat)
    if not self.state.chart then
        return
    end

    -- Process missed notes first (before input processing)
    self:check_missed_notes(current_time_us)

    -- Process input for each lane
    for lane = 1, const.NUM_LANES do
        local events = self.input_handler:consume_events(lane)

        for _, event in ipairs(events) do
            if event.pressed then
                -- Key was pressed - process through JudgeEngine
                self:process_key_press(lane, event.time_us)
            else
                -- Key was released - for LN support
                self:process_key_release(lane, event.time_us)
            end
        end
    end

    -- Check LN releases that are too late
    self:check_ln_releases(current_time_us)
end

--- Process a key press on a lane
---@param lane integer
---@param time_us integer
function Playfield:process_key_press(lane, time_us)
    local result = self.judge:on_key_press(lane, time_us)

    if result then
        -- Record judgment event for display
        self.last_judgment = {
            judgment = result.judgment,
            note = result.note,
            diff = result.diff,
            timing = result.timing,
            time_us = time_us,
        }

        -- Update scoring and gauge
        self.scoring:on_judgment(result.judgment)
        self.gauge:on_judgment(result.judgment)

        -- Update state combo (sync with scoring)
        self.state.combo = self.scoring.combo
        self.state.score = self.scoring.ex_score

        -- Call callbacks
        if result.note and self.on_note_hit then
            self.on_note_hit(result.note, result.judgment)
        end

        if self.on_judgment then
            self.on_judgment(result)
        end
    end
end

--- Process a key release on a lane (for LN)
---@param lane integer
---@param time_us integer
function Playfield:process_key_release(lane, time_us)
    local result = self.judge:on_key_release(lane, time_us)

    if result then
        self.last_judgment = {
            judgment = result.judgment,
            note = result.note,
            diff = result.diff,
            timing = result.timing,
            time_us = time_us,
        }

        self.scoring:on_judgment(result.judgment)
        self.gauge:on_judgment(result.judgment)

        self.state.combo = self.scoring.combo
        self.state.score = self.scoring.ex_score

        if self.on_judgment then
            self.on_judgment(result)
        end
    end
end

--- Check for notes that were missed
---@param current_time_us integer
function Playfield:check_missed_notes(current_time_us)
    local missed = self.judge:process_misses(current_time_us)

    for _, note in ipairs(missed) do
        -- Record as MISS judgment
        self.last_judgment = {
            judgment = "miss",
            note = note,
            diff = nil,
            timing = nil,
            time_us = current_time_us,
        }

        -- Update scoring and gauge
        self.scoring:on_judgment("miss")
        self.gauge:on_judgment("miss")

        self.state.combo = self.scoring.combo
        self.state.score = self.scoring.ex_score

        if self.on_note_miss then
            self.on_note_miss(note)
        end

        if self.on_judgment then
            self.on_judgment(self.last_judgment)
        end
    end
end

--- Check for LN releases that are too late
---@param current_time_us integer
function Playfield:check_ln_releases(current_time_us)
    local missed = self.judge:check_ln_releases(current_time_us)

    for _, note in ipairs(missed) do
        self.last_judgment = {
            judgment = "miss",
            note = note,
            diff = nil,
            timing = nil,
            time_us = current_time_us,
        }

        self.scoring:on_judgment("miss")
        self.gauge:on_judgment("miss")

        self.state.combo = self.scoring.combo
        self.state.score = self.scoring.ex_score

        if self.on_judgment then
            self.on_judgment(self.last_judgment)
        end
    end
end

--- Get notes that need to play keysound (auto-play BGM notes)
---@param current_time_us integer
---@return BgmEvent[] events that should play now
function Playfield:get_bgm_to_play(current_time_us)
    local chart = self.state.chart
    local state = self.state
    if not chart then
        return {}
    end

    local result = {}
    local index = state.next_bgm_index

    while index <= #chart.bgm do
        local bgm = chart.bgm[index]
        if bgm.time_us <= current_time_us then
            result[#result + 1] = bgm
            index = index + 1
        else
            break
        end
    end

    state.next_bgm_index = index
    return result
end

--- Get judgment statistics
---@return JudgeStats
function Playfield:get_stats()
    return self.judge.stats
end

--- Check if gauge has failed (for HARD/EX-HARD)
---@return boolean
function Playfield:is_failed()
    return self.gauge:is_failed()
end

--- Check if player has cleared
---@return boolean
function Playfield:is_cleared()
    return self.gauge:is_cleared()
end

return Playfield
