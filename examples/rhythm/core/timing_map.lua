--- TimingMap: beat↔time bidirectional conversion
--- Core module for BMS/rhythm game timing
---@class TimingMap
---@field segments TimingSegment[] sorted by start_beat
---@field initial_bpm number
local TimingMap = {}
TimingMap.__index = TimingMap

---@class TimingSegment
---@field start_beat number start beat of this segment
---@field end_beat number end beat of this segment (math.huge for last segment)
---@field start_time_us integer start time in microseconds
---@field end_time_us integer end time in microseconds (math.huge for last segment)
---@field type "bpm"|"stop" segment type
---@field bpm number|nil BPM value (for type="bpm")
---@field stop_us integer|nil stop duration in μs (for type="stop")

local US_PER_MINUTE = 60000000 -- 60 seconds in microseconds

--- Create a new TimingMap from BPM changes and stops
---@param initial_bpm number starting BPM
---@param bpm_changes table<number, number>? beat -> bpm mapping
---@param stops table<number, integer>? beat -> stop duration in μs
---@return TimingMap
function TimingMap.new(initial_bpm, bpm_changes, stops)
    local self = setmetatable({}, TimingMap)
    self.initial_bpm = initial_bpm
    self.segments = {}

    -- Collect all timing events
    local events = {}

    -- Add initial BPM at beat 0
    events[#events + 1] = { beat = 0, type = "bpm", bpm = initial_bpm }

    -- Add BPM changes
    if bpm_changes then
        for beat, bpm in pairs(bpm_changes) do
            if beat > 0 then -- skip if at beat 0 (already added initial_bpm)
                events[#events + 1] = { beat = beat, type = "bpm", bpm = bpm }
            end
        end
    end

    -- Add stops
    if stops then
        for beat, stop_us in pairs(stops) do
            events[#events + 1] = { beat = beat, type = "stop", stop_us = stop_us }
        end
    end

    -- Sort by beat (stops come before BPM changes at the same beat)
    table.sort(events, function(a, b)
        if a.beat ~= b.beat then
            return a.beat < b.beat
        end
        -- STOP before BPM change at same beat
        if a.type == "stop" and b.type == "bpm" then return true end
        if a.type == "bpm" and b.type == "stop" then return false end
        return false
    end)

    -- Build segments
    local current_bpm = initial_bpm
    local current_time_us = 0
    local current_beat = 0

    for i, ev in ipairs(events) do
        -- Calculate time to reach this event's beat
        if ev.beat > current_beat then
            local delta_beat = ev.beat - current_beat
            local us_per_beat = US_PER_MINUTE / current_bpm
            local delta_time_us = math.floor(delta_beat * us_per_beat)

            -- Add BPM segment up to this event
            self.segments[#self.segments + 1] = {
                start_beat = current_beat,
                end_beat = ev.beat,
                start_time_us = current_time_us,
                end_time_us = current_time_us + delta_time_us,
                type = "bpm",
                bpm = current_bpm,
            }

            current_time_us = current_time_us + delta_time_us
            current_beat = ev.beat
        end

        -- Process the event
        if ev.type == "bpm" then
            current_bpm = ev.bpm
        elseif ev.type == "stop" then
            -- Add STOP segment (beat doesn't advance, only time)
            self.segments[#self.segments + 1] = {
                start_beat = current_beat,
                end_beat = current_beat, -- beat doesn't change during STOP
                start_time_us = current_time_us,
                end_time_us = current_time_us + ev.stop_us,
                type = "stop",
                stop_us = ev.stop_us,
            }
            current_time_us = current_time_us + ev.stop_us
        end
    end

    -- Add final segment (extends to infinity)
    self.segments[#self.segments + 1] = {
        start_beat = current_beat,
        end_beat = math.huge,
        start_time_us = current_time_us,
        end_time_us = math.huge,
        type = "bpm",
        bpm = current_bpm,
    }

    return self
end

--- Find segment containing the given beat
---@param beat number
---@return TimingSegment
function TimingMap:find_segment_by_beat(beat)
    for _, seg in ipairs(self.segments) do
        if beat >= seg.start_beat and beat < seg.end_beat then
            return seg
        end
        -- Handle STOP segment (start_beat == end_beat)
        if seg.type == "stop" and beat == seg.start_beat then
            return seg
        end
    end
    -- Return last segment if beat is beyond all segments
    return self.segments[#self.segments]
end

--- Find segment containing the given time
---@param time_us integer
---@return TimingSegment
function TimingMap:find_segment_by_time(time_us)
    for _, seg in ipairs(self.segments) do
        if time_us >= seg.start_time_us and time_us < seg.end_time_us then
            return seg
        end
    end
    -- Return last segment if time is beyond all segments
    return self.segments[#self.segments]
end

--- Convert beat to time (μs)
---@param beat number
---@return integer time_us
function TimingMap:beat_to_time_us(beat)
    local seg = self:find_segment_by_beat(beat)

    if seg.type == "stop" then
        -- During STOP, beat doesn't advance, return start time
        return seg.start_time_us
    end

    local beat_in_seg = beat - seg.start_beat
    local us_per_beat = US_PER_MINUTE / seg.bpm
    return seg.start_time_us + math.floor(beat_in_seg * us_per_beat)
end

--- Convert time (μs) to beat
---@param time_us integer
---@return number beat
function TimingMap:time_us_to_beat(time_us)
    local seg = self:find_segment_by_time(time_us)

    if seg.type == "stop" then
        -- During STOP, beat stays the same
        return seg.start_beat
    end

    local time_in_seg = time_us - seg.start_time_us
    local beats_per_us = seg.bpm / US_PER_MINUTE
    return seg.start_beat + time_in_seg * beats_per_us
end

--- Get BPM at given beat
---@param beat number
---@return number bpm
function TimingMap:get_bpm_at_beat(beat)
    local seg = self:find_segment_by_beat(beat)
    if seg.type == "stop" then
        -- Find the BPM segment before this STOP
        for i = #self.segments, 1, -1 do
            if self.segments[i].type == "bpm" and self.segments[i].start_beat <= beat then
                return self.segments[i].bpm
            end
        end
    end
    return seg.bpm or self.initial_bpm
end

--- Get BPM at given time
---@param time_us integer
---@return number bpm
function TimingMap:get_bpm_at_time(time_us)
    local beat = self:time_us_to_beat(time_us)
    return self:get_bpm_at_beat(beat)
end

return TimingMap
