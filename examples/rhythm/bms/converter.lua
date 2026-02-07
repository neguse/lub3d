--- BMS to UniversalChart converter
local parser = require("examples.rhythm.bms.parser")
local types = require("examples.rhythm.bms.types")
local TimingMap = require("examples.rhythm.core.timing_map")

---@class bms_converter
local M = {}

--- Calculate beat at given position within a measure
---@param measure integer measure number (0-based)
---@param position number position within measure (0.0-1.0)
---@param measure_lengths table<integer, number> measure length overrides
---@return number beat
local function calc_beat(measure, position, measure_lengths)
    local beat = 0
    -- Sum beats for all previous measures
    for m = 0, measure - 1 do
        local length = measure_lengths[m] or 1.0
        beat = beat + 4 * length -- 1 measure = 4 beats * length
    end
    -- Add position within current measure
    local current_length = measure_lengths[measure] or 1.0
    beat = beat + 4 * current_length * position
    return beat
end

--- Extract BPM changes from BMS chart
---@param bms BMSChart
---@return table<number, number> beat -> bpm
local function extract_bpm_changes(bms)
    local changes = {}

    for _, ch in ipairs(bms.channels) do
        -- Channel 03: Direct BPM value (hex)
        if ch.channel == 3 then
            local num_objects = #ch.data // 2
            for i = 1, num_objects do
                local hex_str = ch.data:sub(i * 2 - 1, i * 2)
                local bpm = tonumber(hex_str, 16)
                if bpm and bpm > 0 then
                    local position = (i - 1) / num_objects
                    local beat = calc_beat(ch.measure, position, bms.measure_lengths)
                    changes[beat] = bpm
                end
            end
        -- Channel 08: Extended BPM (references #BPMxx)
        elseif ch.channel == 8 then
            local ids, positions = parser.parse_objects(ch.data)
            for j, id in ipairs(ids) do
                local bpm = bms.bpm_defs[id]
                if bpm then
                    local beat = calc_beat(ch.measure, positions[j], bms.measure_lengths)
                    changes[beat] = bpm
                end
            end
        end
    end

    return changes
end

--- Extract STOPs from BMS chart
---@param bms BMSChart
---@return table<number, integer> beat -> stop duration in μs
local function extract_stops(bms)
    local stops = {}

    for _, ch in ipairs(bms.channels) do
        -- Channel 09: STOP (references #STOPxx)
        if ch.channel == 9 then
            local ids, positions = parser.parse_objects(ch.data)
            for j, id in ipairs(ids) do
                local duration_192 = bms.stop_defs[id]
                if duration_192 then
                    local beat = calc_beat(ch.measure, positions[j], bms.measure_lengths)
                    -- Convert 1/192 notes to μs at current BPM
                    -- For now, use initial BPM (proper implementation would need to
                    -- consider BPM at that point)
                    local us_per_beat = 60000000 / bms.header.bpm
                    local us_per_192 = us_per_beat / 192
                    local duration_us = math.floor(duration_192 * us_per_192)
                    stops[beat] = duration_us
                end
            end
        end
    end

    return stops
end

--- Extract notes from BMS chart (including LN)
---@param bms BMSChart
---@param timing_map TimingMap
---@return Note[]
local function extract_notes(bms, timing_map)
    local notes = {}

    -- First, collect all regular notes
    for _, ch in ipairs(bms.channels) do
        local lane = types.get_lane(ch.channel)
        if lane then
            local ids, positions = parser.parse_objects(ch.data)
            for j, wav_id in ipairs(ids) do
                local beat = calc_beat(ch.measure, positions[j], bms.measure_lengths)
                local time_us = timing_map:beat_to_time_us(beat)
                notes[#notes + 1] = {
                    beat = beat,
                    time_us = time_us,
                    lane = lane,
                    wav_id = wav_id,
                    judged = false,
                    note_type = "normal",
                }
            end
        end
    end

    -- Collect LN data per lane
    -- LN format: same wav_id marks start and end
    local ln_data = {} -- lane -> { {beat, time_us, wav_id}, ... }
    for lane = 1, 8 do
        ln_data[lane] = {}
    end

    for _, ch in ipairs(bms.channels) do
        local lane = types.get_ln_lane(ch.channel)
        if lane then
            local ids, positions = parser.parse_objects(ch.data)
            for j, wav_id in ipairs(ids) do
                local beat = calc_beat(ch.measure, positions[j], bms.measure_lengths)
                local time_us = timing_map:beat_to_time_us(beat)
                table.insert(ln_data[lane], {
                    beat = beat,
                    time_us = time_us,
                    wav_id = wav_id,
                })
            end
        end
    end

    -- Process LN pairs (sort by beat, pair consecutive entries)
    for lane = 1, 8 do
        local events = ln_data[lane]
        table.sort(events, function(a, b) return a.beat < b.beat end)

        -- Pair up consecutive LN events (start/end)
        local i = 1
        while i <= #events - 1 do
            local start_event = events[i]
            local end_event = events[i + 1]

            notes[#notes + 1] = {
                beat = start_event.beat,
                time_us = start_event.time_us,
                end_beat = end_event.beat,
                end_time_us = end_event.time_us,
                lane = lane,
                wav_id = start_event.wav_id,
                judged = false,
                note_type = "long",
            }

            i = i + 2
        end
    end

    -- Sort by beat
    table.sort(notes, function(a, b)
        if a.beat ~= b.beat then
            return a.beat < b.beat
        end
        return a.lane < b.lane
    end)

    return notes
end

--- Extract BGM events from BMS chart
---@param bms BMSChart
---@param timing_map TimingMap
---@return BgmEvent[]
local function extract_bgm(bms, timing_map)
    local bgm = {}

    for _, ch in ipairs(bms.channels) do
        -- Channel 01: BGM
        if ch.channel == 1 then
            local ids, positions = parser.parse_objects(ch.data)
            for j, wav_id in ipairs(ids) do
                local beat = calc_beat(ch.measure, positions[j], bms.measure_lengths)
                local time_us = timing_map:beat_to_time_us(beat)
                bgm[#bgm + 1] = {
                    beat = beat,
                    time_us = time_us,
                    wav_id = wav_id,
                }
            end
        end
    end

    -- Sort by beat
    table.sort(bgm, function(a, b)
        return a.beat < b.beat
    end)

    return bgm
end

---@class Note
---@field beat number
---@field time_us integer
---@field end_beat number|nil LN end beat (nil for normal notes)
---@field end_time_us integer|nil LN end time (nil for normal notes)
---@field lane integer 1-8
---@field wav_id integer 0-1295
---@field judged boolean
---@field note_type string "normal"|"long"

---@class BgmEvent
---@field beat number
---@field time_us integer
---@field wav_id integer 0-1295

---@class ChartMeta
---@field title string
---@field subtitle string
---@field artist string
---@field subartist string
---@field genre string
---@field bpm number initial BPM
---@field playlevel integer
---@field difficulty integer

---@class UniversalChart
---@field meta ChartMeta
---@field timing_map TimingMap
---@field notes Note[]
---@field bgm BgmEvent[]
---@field wavs table<integer, string> id -> path

--- Convert BMSChart to UniversalChart
---@param bms BMSChart
---@return UniversalChart
function M.convert(bms)
    -- Extract timing data
    local bpm_changes = extract_bpm_changes(bms)
    local stops = extract_stops(bms)

    -- Create timing map
    local timing_map = TimingMap.new(bms.header.bpm, bpm_changes, stops)

    -- Extract notes and BGM
    local notes = extract_notes(bms, timing_map)
    local bgm = extract_bgm(bms, timing_map)

    ---@type UniversalChart
    local chart = {
        meta = {
            title = bms.header.title,
            subtitle = bms.header.subtitle,
            artist = bms.header.artist,
            subartist = bms.header.subartist,
            genre = bms.header.genre,
            bpm = bms.header.bpm,
            playlevel = bms.header.playlevel,
            difficulty = bms.header.difficulty,
        },
        timing_map = timing_map,
        notes = notes,
        bgm = bgm,
        wavs = bms.wavs,
    }

    return chart
end

--- Load BMS file and convert to UniversalChart
---@param path string
---@return UniversalChart|nil chart
---@return string|nil error
function M.load(path)
    local bms, err = parser.load(path)
    if not bms then
        return nil, err
    end

    local ok, result = pcall(M.convert, bms)
    if not ok then
        return nil, "Conversion error: " .. tostring(result)
    end

    return result, nil
end

return M
