--- Judgment engine for rhythm game
--- Handles candidate selection, timing evaluation, and miss detection
local const = require("examples.rhythm.const")

---@class JudgeStats
---@field pgreat integer
---@field great integer
---@field good integer
---@field bad integer
---@field miss integer
---@field empty_poor integer
---@field fast integer
---@field slow integer

---@class JudgeResult
---@field judgment string "pgreat"|"great"|"good"|"bad"|"empty_poor"
---@field note Note|nil
---@field diff integer|nil timing difference in microseconds
---@field timing string|nil "fast"|"slow"|nil

---@class JudgeEngine
---@field windows table<string, integer> judgment windows in microseconds
---@field note_queues table<integer, Note[]> notes per lane, sorted by time
---@field queue_heads table<integer, integer> index of next candidate per lane
---@field active_lns table<integer, Note> currently held LN per lane
---@field stats JudgeStats judgment statistics
---@field rank_multiplier number #RANK window multiplier
local JudgeEngine = {}
JudgeEngine.__index = JudgeEngine

-- #RANK multipliers
local RANK_MULTIPLIER = {
    [0] = 0.5,  -- VERY HARD
    [1] = 0.75, -- HARD
    [2] = 1.0,  -- NORMAL
    [3] = 1.25, -- EASY
}

--- Create a new JudgeEngine
---@param rank integer|nil #RANK value (0-3, default 2)
---@return JudgeEngine
function JudgeEngine.new(rank)
    local self = setmetatable({}, JudgeEngine)

    -- Apply rank multiplier to windows
    self.rank_multiplier = RANK_MULTIPLIER[rank or 2] or 1.0
    self.windows = {}
    for name, base_us in pairs(const.JUDGE_WINDOWS) do
        self.windows[name] = math.floor(base_us * self.rank_multiplier)
    end

    -- Initialize state
    self.note_queues = {}
    self.queue_heads = {}
    self.active_lns = {}

    for lane = 1, const.NUM_LANES do
        self.note_queues[lane] = {}
        self.queue_heads[lane] = 1
        self.active_lns[lane] = nil
    end

    -- Statistics
    self.stats = {
        pgreat = 0,
        great = 0,
        good = 0,
        bad = 0,
        miss = 0,
        empty_poor = 0,
        fast = 0,
        slow = 0,
    }

    return self
end

--- Load notes into the engine
---@param notes Note[]
function JudgeEngine:load_notes(notes)
    -- Clear existing queues
    for lane = 1, const.NUM_LANES do
        self.note_queues[lane] = {}
        self.queue_heads[lane] = 1
    end

    -- Sort notes into per-lane queues
    for _, note in ipairs(notes) do
        local lane = note.lane
        if lane >= 1 and lane <= const.NUM_LANES then
            table.insert(self.note_queues[lane], note)
        end
    end

    -- Sort each queue by time
    for lane = 1, const.NUM_LANES do
        table.sort(self.note_queues[lane], function(a, b)
            return a.time_us < b.time_us
        end)
    end
end

--- Evaluate timing difference and return judgment
---@param diff_us integer timing difference (press_time - note_time)
---@return string|nil judgment type or nil if outside all windows
function JudgeEngine:evaluate(diff_us)
    local abs_diff = math.abs(diff_us)

    if abs_diff <= self.windows.pgreat then
        return "pgreat"
    elseif abs_diff <= self.windows.great then
        return "great"
    elseif abs_diff <= self.windows.good then
        return "good"
    elseif abs_diff <= self.windows.bad then
        return "bad"
    end

    return nil
end

--- Evaluate timing with FAST/SLOW indication
---@param diff_us integer timing difference (press_time - note_time)
---@return string|nil judgment type
---@return string|nil timing "fast"|"slow"|nil
function JudgeEngine:evaluate_with_timing(diff_us)
    local judgment = self:evaluate(diff_us)
    if not judgment then
        return nil, nil
    end

    local timing = nil
    if diff_us < 0 then
        timing = "fast"
    elseif diff_us > 0 then
        timing = "slow"
    end

    return judgment, timing
end

--- Find the nearest candidate note for a given lane and time
---@param lane integer
---@param time_us integer current time in microseconds
---@return Note|nil note the candidate note
---@return integer|nil diff timing difference
function JudgeEngine:find_candidate(lane, time_us)
    local queue = self.note_queues[lane]
    if not queue or #queue == 0 then
        return nil, nil
    end

    local head = self.queue_heads[lane]
    local best_note = nil
    local best_diff = nil
    local best_abs_diff = math.huge

    -- Search from head onwards for nearest note within BAD window
    -- (notes before head are already judged or missed)
    for i = head, #queue do
        local note = queue[i]

        -- Skip already judged notes
        if not note.judged then
            local diff = time_us - note.time_us
            local abs_diff = math.abs(diff)

            -- If we've gone past BAD window into the future, stop searching
            if diff < -self.windows.bad then
                break
            end

            -- Check if within BAD window and closer than best
            if abs_diff <= self.windows.bad and abs_diff < best_abs_diff then
                best_note = note
                best_diff = diff
                best_abs_diff = abs_diff
            end
        end
    end

    return best_note, best_diff
end

--- Record a judgment in statistics
---@param judgment string
---@param timing string|nil
function JudgeEngine:record_judgment(judgment, timing)
    if judgment == "pgreat" then
        self.stats.pgreat = self.stats.pgreat + 1
    elseif judgment == "great" then
        self.stats.great = self.stats.great + 1
    elseif judgment == "good" then
        self.stats.good = self.stats.good + 1
    elseif judgment == "bad" then
        self.stats.bad = self.stats.bad + 1
    elseif judgment == "miss" then
        self.stats.miss = self.stats.miss + 1
    elseif judgment == "empty_poor" then
        self.stats.empty_poor = self.stats.empty_poor + 1
    end

    if timing == "fast" then
        self.stats.fast = self.stats.fast + 1
    elseif timing == "slow" then
        self.stats.slow = self.stats.slow + 1
    end
end

--- Process a key press event
---@param lane integer
---@param time_us integer
---@return JudgeResult result
function JudgeEngine:on_key_press(lane, time_us)
    local note, diff = self:find_candidate(lane, time_us)

    if not note then
        -- Empty press - no note to hit
        self:record_judgment("empty_poor", nil)
        return {
            judgment = "empty_poor",
            note = nil,
            diff = nil,
            timing = nil,
        }
    end

    -- Evaluate timing
    local judgment, timing = self:evaluate_with_timing(diff)

    if not judgment then
        -- Outside all windows - treat as empty press
        self:record_judgment("empty_poor", nil)
        return {
            judgment = "empty_poor",
            note = nil,
            diff = nil,
            timing = nil,
        }
    end

    -- Mark note as judged (for start timing)
    note.judged = true
    note.judgment = judgment
    note.timing = timing

    -- Record stats for start judgment
    self:record_judgment(judgment, timing)

    -- If this is an LN, track it for end judgment
    if note.note_type == "long" and note.end_time_us then
        self.active_lns[lane] = note
    end

    -- Advance queue head if we judged the head note
    self:advance_queue_head(lane)

    return {
        judgment = judgment,
        note = note,
        diff = diff,
        timing = timing,
    }
end

--- Advance the queue head past judged notes
---@param lane integer
function JudgeEngine:advance_queue_head(lane)
    local queue = self.note_queues[lane]
    local head = self.queue_heads[lane]

    while head <= #queue and queue[head].judged do
        head = head + 1
    end

    self.queue_heads[lane] = head
end

--- Process missed notes (notes that passed the window without being hit)
---@param current_time_us integer
---@return Note[] missed notes
function JudgeEngine:process_misses(current_time_us)
    local missed = {}

    for lane = 1, const.NUM_LANES do
        local queue = self.note_queues[lane]
        local head = self.queue_heads[lane]

        while head <= #queue do
            local note = queue[head]

            if note.judged then
                -- Already judged, skip
                head = head + 1
            else
                local diff = current_time_us - note.time_us

                -- Note is past BAD window
                if diff > self.windows.bad then
                    note.judged = true
                    note.judgment = "miss"
                    self:record_judgment("miss", nil)
                    table.insert(missed, note)
                    head = head + 1
                else
                    -- Still within window or in future, stop checking this lane
                    break
                end
            end
        end

        self.queue_heads[lane] = head
    end

    return missed
end

--- Process a key release event (for LN)
---@param lane integer
---@param time_us integer
---@return JudgeResult|nil result
function JudgeEngine:on_key_release(lane, time_us)
    local active_ln = self.active_lns[lane]
    if not active_ln then
        return nil
    end

    -- Check if released within the LN end window
    local end_time = active_ln.end_time_us
    local diff = time_us - end_time
    local judgment, timing = self:evaluate_with_timing(diff)

    -- Clear active LN
    self.active_lns[lane] = nil

    if not judgment then
        -- Released too early or too late
        judgment = "miss"
        self:record_judgment("miss", nil)
    else
        self:record_judgment(judgment, timing)
    end

    return {
        judgment = judgment,
        note = active_ln,
        diff = diff,
        timing = timing,
    }
end

--- Check for LN releases that are too late (held past window)
---@param current_time_us integer
---@return Note[] missed LN ends
function JudgeEngine:check_ln_releases(current_time_us)
    local missed = {}

    for lane = 1, const.NUM_LANES do
        local active_ln = self.active_lns[lane]
        if active_ln then
            local end_time = active_ln.end_time_us
            local diff = current_time_us - end_time

            -- Past BAD window - missed the release
            if diff > self.windows.bad then
                self.active_lns[lane] = nil
                self:record_judgment("miss", nil)
                table.insert(missed, active_ln)
            end
        end
    end

    return missed
end

--- Get total note count for scoring calculations
---@return integer
function JudgeEngine:get_total_judged()
    local stats = self.stats
    return stats.pgreat + stats.great + stats.good + stats.bad + stats.miss
end

--- Reset engine state (keep notes but reset judgments)
function JudgeEngine:reset()
    for lane = 1, const.NUM_LANES do
        self.queue_heads[lane] = 1
        self.active_lns[lane] = nil

        for _, note in ipairs(self.note_queues[lane]) do
            note.judged = false
            note.judgment = nil
            note.timing = nil
        end
    end

    self.stats = {
        pgreat = 0,
        great = 0,
        good = 0,
        bad = 0,
        miss = 0,
        empty_poor = 0,
        fast = 0,
        slow = 0,
    }
end

return JudgeEngine
