--- BMS file parser
local base36 = require("examples.rhythm.bms.base36")
local encoding = require("examples.rhythm.bms.encoding")
local types = require("examples.rhythm.bms.types")

---@class bms_parser
local M = {}

--- Parse a BMS file and return BMSChart
---@param content string raw file content
---@return BMSChart
function M.parse(content)
    -- Convert to UTF-8 if needed
    content = encoding.to_utf8(content)

    ---@type BMSChart
    local chart = {
        header = {
            player = 1,
            genre = "",
            title = "",
            subtitle = "",
            artist = "",
            subartist = "",
            bpm = 130, -- default BPM
            playlevel = 0,
            rank = 3,
            total = 100,
            stagefile = "",
            banner = "",
            difficulty = 0,
            lntype = 1,
        },
        wavs = {},
        bmps = {},
        bpm_defs = {},
        stop_defs = {},
        measure_lengths = {},
        channels = {},
    }

    -- Parse line by line
    for line in content:gmatch("[^\r\n]+") do
        M.parse_line(line, chart)
    end

    return chart
end

--- Parse a single line of BMS file
---@param line string
---@param chart BMSChart
function M.parse_line(line, chart)
    -- Skip empty lines and comments
    line = line:match("^%s*(.-)%s*$") -- trim whitespace
    if line == "" or line:sub(1, 1) == "*" then
        return
    end

    -- Must start with #
    if line:sub(1, 1) ~= "#" then
        return
    end

    -- Try header commands first
    if M.parse_header(line, chart) then
        return
    end

    -- Try resource definitions (#WAVxx, #BMPxx, #BPMxx, #STOPxx)
    if M.parse_resource(line, chart) then
        return
    end

    -- Try channel data (#xxxCC:data)
    if M.parse_channel(line, chart) then
        return
    end
end

--- Parse header command
---@param line string
---@param chart BMSChart
---@return boolean true if parsed
function M.parse_header(line, chart)
    local cmd, value = line:match("^#([A-Z]+)%s+(.+)$")
    if not cmd then
        -- Try commands without value
        cmd = line:match("^#([A-Z]+)$")
        value = ""
    end

    if not cmd then
        return false
    end

    local handlers = {
        PLAYER = function() chart.header.player = tonumber(value) or 1 end,
        GENRE = function() chart.header.genre = value end,
        TITLE = function() chart.header.title = value end,
        SUBTITLE = function() chart.header.subtitle = value end,
        ARTIST = function() chart.header.artist = value end,
        SUBARTIST = function() chart.header.subartist = value end,
        BPM = function() chart.header.bpm = tonumber(value) or 130 end,
        PLAYLEVEL = function() chart.header.playlevel = tonumber(value) or 0 end,
        RANK = function() chart.header.rank = tonumber(value) or 3 end,
        TOTAL = function() chart.header.total = tonumber(value) or 100 end,
        STAGEFILE = function() chart.header.stagefile = value end,
        BANNER = function() chart.header.banner = value end,
        DIFFICULTY = function() chart.header.difficulty = tonumber(value) or 0 end,
        LNTYPE = function() chart.header.lntype = tonumber(value) or 1 end,
    }

    local handler = handlers[cmd]
    if handler then
        handler()
        return true
    end

    return false
end

--- Parse resource definition (#WAVxx, #BMPxx, #BPMxx, #STOPxx)
---@param line string
---@param chart BMSChart
---@return boolean true if parsed
function M.parse_resource(line, chart)
    -- #WAVxx filename
    local id_str, path = line:match("^#WAV([0-9A-Za-z][0-9A-Za-z])%s+(.+)$")
    if id_str and path then
        local id = base36.decode(id_str)
        if id then
            chart.wavs[id] = path
        end
        return true
    end

    -- #BMPxx filename
    id_str, path = line:match("^#BMP([0-9A-Za-z][0-9A-Za-z])%s+(.+)$")
    if id_str and path then
        local id = base36.decode(id_str)
        if id then
            chart.bmps[id] = path
        end
        return true
    end

    -- #BPMxx value (extended BPM definition)
    local bpm_value
    id_str, bpm_value = line:match("^#BPM([0-9A-Za-z][0-9A-Za-z])%s+([%d%.]+)$")
    if id_str and bpm_value then
        local id = base36.decode(id_str)
        if id then
            chart.bpm_defs[id] = tonumber(bpm_value)
        end
        return true
    end

    -- #STOPxx value (stop definition, value is in 1/192 notes)
    local stop_value
    id_str, stop_value = line:match("^#STOP([0-9A-Za-z][0-9A-Za-z])%s+(%d+)$")
    if id_str and stop_value then
        local id = base36.decode(id_str)
        if id then
            chart.stop_defs[id] = tonumber(stop_value)
        end
        return true
    end

    return false
end

--- Parse channel data (#xxxCC:data or #xxx02:value for measure length)
---@param line string
---@param chart BMSChart
---@return boolean true if parsed
function M.parse_channel(line, chart)
    -- Match #xxxCC:data pattern
    -- Channel numbers in BMS are typically 2 decimal digits (00-99)
    local measure_str, channel_str, data = line:match("^#(%d%d%d)(%d%d):(.+)$")

    if not measure_str then
        return false
    end

    local measure = tonumber(measure_str)
    -- Channel numbers are decimal (00-99)
    local channel = tonumber(channel_str)

    if not measure or not channel then
        return false
    end

    -- Special case: channel 02 is measure length (value, not object data)
    if channel == 2 then
        local length = tonumber(data)
        if length then
            chart.measure_lengths[measure] = length
        end
        return true
    end

    -- Skip LN channels in Phase 1
    if types.is_ln_channel(channel) then
        return true
    end

    -- Store channel data
    chart.channels[#chart.channels + 1] = {
        measure = measure,
        channel = channel,
        data = data,
    }

    return true
end

--- Parse channel data string into array of object IDs
--- "01020304" -> { 1, 2, 3, 4 }
--- "00" entries are filtered out (no object)
---@param data string
---@return integer[] ids base36-decoded IDs (filtered, no 00s)
---@return number[] positions position within measure (0.0-1.0)
function M.parse_objects(data)
    local ids = {}
    local positions = {}

    -- Data must be even length (pairs of base36 chars)
    if #data % 2 ~= 0 then
        return ids, positions
    end

    local num_objects = #data // 2
    for i = 1, num_objects do
        local id_str = data:sub(i * 2 - 1, i * 2)
        local id = base36.decode(id_str)

        -- Skip 00 (no object)
        if id and id > 0 then
            ids[#ids + 1] = id
            -- Position is (i-1) / num_objects
            positions[#positions + 1] = (i - 1) / num_objects
        end
    end

    return ids, positions
end

--- Load and parse BMS file from path
---@param path string file path
---@return BMSChart|nil chart
---@return string|nil error message
function M.load(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, "Cannot open file: " .. (err or path)
    end

    local content = file:read("*a")
    file:close()

    if not content then
        return nil, "Cannot read file: " .. path
    end

    local ok, result = pcall(M.parse, content)
    if not ok then
        return nil, "Parse error: " .. tostring(result)
    end

    return result, nil
end

return M
