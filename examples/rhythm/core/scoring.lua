--- Scoring engine for rhythm game
--- Handles EX score calculation, combo tracking, and DJ LEVEL

---@class ScoringEngine
---@field total_notes integer total number of notes in chart
---@field ex_score integer current EX score
---@field combo integer current combo
---@field max_combo integer maximum combo achieved
local ScoringEngine = {}
ScoringEngine.__index = ScoringEngine

-- EX score values per judgment
local EX_SCORE = {
    pgreat = 2,
    great = 1,
    good = 0,
    bad = 0,
    miss = 0,
    empty_poor = 0,
}

-- Judgments that continue combo
local COMBO_CONTINUE = {
    pgreat = true,
    great = true,
    good = true,
}

-- DJ LEVEL thresholds (percentage of max EX score)
-- Based on IIDX DJ LEVEL system (9/9, 8/9, 7/9, 6/9, 5/9, 4/9, 3/9, 2/9)
local DJ_LEVEL_THRESHOLDS = {
    { threshold = 8/9,  level = "AAA" },  -- 88.89%
    { threshold = 7/9,  level = "AA" },   -- 77.78%
    { threshold = 6/9,  level = "A" },    -- 66.67%
    { threshold = 5/9,  level = "B" },    -- 55.56%
    { threshold = 4/9,  level = "C" },    -- 44.44%
    { threshold = 3/9,  level = "D" },    -- 33.33%
    { threshold = 2/9,  level = "E" },    -- 22.22%
}

--- Create a new ScoringEngine
---@param total_notes integer total number of notes in chart
---@return ScoringEngine
function ScoringEngine.new(total_notes)
    local self = setmetatable({}, ScoringEngine)
    self.total_notes = total_notes or 0
    self.ex_score = 0
    self.combo = 0
    self.max_combo = 0
    return self
end

--- Process a judgment and update score/combo
---@param judgment string
function ScoringEngine:on_judgment(judgment)
    -- Update EX score
    local score = EX_SCORE[judgment] or 0
    self.ex_score = self.ex_score + score

    -- Update combo
    if COMBO_CONTINUE[judgment] then
        self.combo = self.combo + 1
        if self.combo > self.max_combo then
            self.max_combo = self.combo
        end
    else
        self.combo = 0
    end
end

--- Get the maximum possible EX score
---@return integer
function ScoringEngine:get_max_ex_score()
    return self.total_notes * 2
end

--- Get the current score rate (0-100)
---@return number
function ScoringEngine:get_score_rate()
    local max = self:get_max_ex_score()
    if max == 0 then
        return 0
    end
    return (self.ex_score / max) * 100
end

--- Get the DJ LEVEL based on current score
---@return string
function ScoringEngine:get_dj_level()
    local max = self:get_max_ex_score()
    if max == 0 then
        return "F"
    end

    local rate = self.ex_score / max

    for _, entry in ipairs(DJ_LEVEL_THRESHOLDS) do
        if rate >= entry.threshold then
            return entry.level
        end
    end

    return "F"
end

--- Reset the engine
function ScoringEngine:reset()
    self.ex_score = 0
    self.combo = 0
    self.max_combo = 0
end

return ScoringEngine
