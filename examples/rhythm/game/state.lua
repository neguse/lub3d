--- Game state manager
---@class GameState
---@field current string current state name
---@field chart UniversalChart|nil loaded chart
---@field conductor Conductor|nil playback manager
---@field combo integer current combo
---@field score integer current score
---@field next_note_index integer index of next unprocessed note
---@field next_bgm_index integer index of next unprocessed BGM event
local GameState = {}
GameState.__index = GameState

-- State names
GameState.SELECT = "select"
GameState.LOADING = "loading"
GameState.PLAYING = "playing"
GameState.FINISHED = "finished"
GameState.PAUSED = "paused"

--- Create a new GameState
---@return GameState
function GameState.new()
    local self = setmetatable({}, GameState)
    self.current = GameState.LOADING
    self.chart = nil
    self.conductor = nil
    self.combo = 0
    self.score = 0
    self.next_note_index = 1
    self.next_bgm_index = 1
    return self
end

--- Load a chart
---@param chart UniversalChart
---@param conductor Conductor
function GameState:load_chart(chart, conductor)
    self.chart = chart
    self.conductor = conductor
    self.combo = 0
    self.score = 0
    self.next_note_index = 1
    self.next_bgm_index = 1
    self.current = GameState.LOADING
end

--- Start playing
function GameState:start()
    self.current = GameState.PLAYING
end

--- Pause the game
function GameState:pause()
    if self.current == GameState.PLAYING then
        self.current = GameState.PAUSED
        if self.conductor then
            self.conductor:pause()
        end
    end
end

--- Resume from pause
---@param real_time_us integer
function GameState:resume(real_time_us)
    if self.current == GameState.PAUSED then
        self.current = GameState.PLAYING
        if self.conductor then
            self.conductor:resume(real_time_us)
        end
    end
end

--- Finish the game
function GameState:finish()
    self.current = GameState.FINISHED
end

--- Check if game is in a specific state
---@param state string
---@return boolean
function GameState:is(state)
    return self.current == state
end

--- Add to combo
function GameState:add_combo()
    self.combo = self.combo + 1
end

--- Break combo
function GameState:break_combo()
    self.combo = 0
end

--- Add score
---@param points integer
function GameState:add_score(points)
    self.score = self.score + points
end

--- Get notes that should be visible at current time
---@param current_beat number
---@param visible_beats number beats visible above judgment line
---@return Note[]
function GameState:get_visible_notes(current_beat, visible_beats)
    if not self.chart then
        return {}
    end

    local result = {}
    local max_beat = current_beat + visible_beats
    local min_beat = current_beat - 2 -- Show notes slightly below judgment line

    for _, note in ipairs(self.chart.notes) do
        if not note.judged and note.beat >= min_beat and note.beat <= max_beat then
            result[#result + 1] = note
        end
    end

    return result
end

--- Mark a note as judged
---@param note Note
function GameState:judge_note(note)
    note.judged = true
end

--- Check if all notes are processed
---@return boolean
function GameState:is_chart_complete()
    if not self.chart then
        return true
    end

    for _, note in ipairs(self.chart.notes) do
        if not note.judged then
            return false
        end
    end

    return true
end

return GameState
