--- Conductor: Playback position manager
--- Tracks chart time and current beat using TimingMap
---@class Conductor
---@field timing_map TimingMap
---@field start_real_time_us integer real time when playback started (μs)
---@field chart_time_us integer current position in chart (μs)
---@field current_beat number current beat position
---@field playing boolean whether playback is active
---@field offset_us integer audio offset in μs (positive = audio plays earlier)
local Conductor = {}
Conductor.__index = Conductor

--- Create a new Conductor
---@param timing_map TimingMap
---@param offset_us integer? audio offset in μs (default 0)
---@return Conductor
function Conductor.new(timing_map, offset_us)
    local self = setmetatable({}, Conductor)
    self.timing_map = timing_map
    self.start_real_time_us = 0
    self.chart_time_us = 0
    self.current_beat = 0
    self.playing = false
    self.offset_us = offset_us or 0
    return self
end

--- Start playback at given real time
---@param real_time_us integer current real time in μs
---@param start_chart_time_us integer? chart time to start from (default 0)
function Conductor:start(real_time_us, start_chart_time_us)
    start_chart_time_us = start_chart_time_us or 0
    self.start_real_time_us = real_time_us - start_chart_time_us
    self.chart_time_us = start_chart_time_us
    self.current_beat = self.timing_map:time_us_to_beat(start_chart_time_us)
    self.playing = true
end

--- Stop playback
function Conductor:stop()
    self.playing = false
end

--- Pause playback (keeps current position)
function Conductor:pause()
    self.playing = false
end

--- Resume playback from current position
---@param real_time_us integer current real time in μs
function Conductor:resume(real_time_us)
    self.start_real_time_us = real_time_us - self.chart_time_us
    self.playing = true
end

--- Update conductor with current real time
---@param real_time_us integer current real time in μs
function Conductor:update(real_time_us)
    if not self.playing then
        return
    end

    -- Calculate chart time from real time
    self.chart_time_us = real_time_us - self.start_real_time_us

    -- Clamp to non-negative
    if self.chart_time_us < 0 then
        self.chart_time_us = 0
    end

    -- Update current beat from timing map
    self.current_beat = self.timing_map:time_us_to_beat(self.chart_time_us)
end

--- Get chart time in μs
---@return integer
function Conductor:get_chart_time_us()
    return self.chart_time_us
end

--- Get current beat
---@return number
function Conductor:get_current_beat()
    return self.current_beat
end

--- Get audio time (chart time adjusted by offset)
--- Use this for scheduling audio playback
---@return integer audio_time_us
function Conductor:get_audio_time_us()
    return self.chart_time_us - self.offset_us
end

--- Get chart time at given beat
---@param beat number
---@return integer time_us
function Conductor:beat_to_time_us(beat)
    return self.timing_map:beat_to_time_us(beat)
end

--- Get beat at given chart time
---@param time_us integer
---@return number beat
function Conductor:time_us_to_beat(time_us)
    return self.timing_map:time_us_to_beat(time_us)
end

--- Get current BPM
---@return number
function Conductor:get_current_bpm()
    return self.timing_map:get_bpm_at_beat(self.current_beat)
end

--- Check if playback is active
---@return boolean
function Conductor:is_playing()
    return self.playing
end

--- Seek to specific chart time
---@param real_time_us integer current real time
---@param target_chart_time_us integer target chart time
function Conductor:seek(real_time_us, target_chart_time_us)
    self.start_real_time_us = real_time_us - target_chart_time_us
    self.chart_time_us = target_chart_time_us
    self.current_beat = self.timing_map:time_us_to_beat(target_chart_time_us)
end

--- Seek to specific beat
---@param real_time_us integer current real time
---@param target_beat number target beat
function Conductor:seek_beat(real_time_us, target_beat)
    local target_time_us = self.timing_map:beat_to_time_us(target_beat)
    self:seek(real_time_us, target_time_us)
end

return Conductor
