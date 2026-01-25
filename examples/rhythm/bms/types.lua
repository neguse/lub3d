--- BMS data types
---@class bms_types
local M = {}

---@class BMSHeader
---@field player integer 1=single, 2=couple, 3=double
---@field genre string
---@field title string
---@field subtitle string
---@field artist string
---@field subartist string
---@field bpm number initial BPM
---@field playlevel integer difficulty level
---@field rank integer judge difficulty (0=very hard, 1=hard, 2=normal, 3=easy)
---@field total number gauge total
---@field stagefile string loading screen image
---@field banner string banner image
---@field difficulty integer 1-5 difficulty category
---@field lntype integer LN type (1=RDM, 2=MGQ)

---@class BMSWav
---@field id integer 0-1295 (base36 decoded)
---@field path string relative path to audio file

---@class BMSBmp
---@field id integer 0-1295
---@field path string relative path to image file

---@class BMSBpmDef
---@field id integer 0-1295
---@field bpm number BPM value

---@class BMSStopDef
---@field id integer 0-1295
---@field duration integer duration in 1/192 notes

---@class BMSChannel
---@field measure integer measure number (0-999)
---@field channel integer channel number
---@field data string raw channel data (e.g., "01020304")

---@class BMSChart
---@field header BMSHeader
---@field wavs table<integer, string> id -> path
---@field bmps table<integer, string> id -> path
---@field bpm_defs table<integer, number> id -> bpm
---@field stop_defs table<integer, integer> id -> duration (1/192 notes)
---@field measure_lengths table<integer, number> measure -> length multiplier
---@field channels BMSChannel[] raw channel data

-- Channel number definitions
M.CHANNELS = {
    -- Special channels
    BGM = 1,           -- 01: BGM
    MEASURE_LENGTH = 2, -- 02: Measure length (special: value, not objects)
    BPM_CHANGE = 3,    -- 03: BPM change (integer BPM)
    BGA_BASE = 4,      -- 04: BGA base
    BGA_POOR = 6,      -- 06: BGA poor
    BGA_LAYER = 7,     -- 07: BGA layer
    BPM_EXTENDED = 8,  -- 08: Extended BPM (references #BPMxx)
    STOP = 9,          -- 09: STOP (references #STOPxx)

    -- 1P visible notes (11-19)
    P1_KEY1 = 11,      -- 1P key 1 (scratch for 7key)
    P1_KEY2 = 12,      -- 1P key 2
    P1_KEY3 = 13,      -- 1P key 3
    P1_KEY4 = 14,      -- 1P key 4
    P1_KEY5 = 15,      -- 1P key 5
    P1_KEY6 = 16,      -- 1P key 6 (for 7key: key 6)
    P1_KEY7 = 18,      -- 1P key 7 (for 7key: key 7)
    P1_KEY8 = 19,      -- 1P key 8 (for 7key: key 8/scratch?)

    -- 1P invisible notes (31-39)
    P1_INV_KEY1 = 31,

    -- 1P LN notes (51-59) - Phase 1: ignored
    P1_LN_KEY1 = 51,

    -- 2P visible notes (21-29)
    P2_KEY1 = 21,

    -- 2P invisible notes (41-49)
    P2_INV_KEY1 = 41,

    -- 2P LN notes (61-69) - Phase 1: ignored
    P2_LN_KEY1 = 61,
}

-- Lane mapping: BMS channel -> logical lane (1-8 for 7key+scratch)
-- For 7key+scratch: lane 1 = scratch, lanes 2-8 = keys
M.CHANNEL_TO_LANE = {
    [11] = 1,  -- scratch
    [12] = 2,  -- key 1
    [13] = 3,  -- key 2
    [14] = 4,  -- key 3
    [15] = 5,  -- key 4
    [18] = 6,  -- key 5
    [19] = 7,  -- key 6
    [16] = 8,  -- key 7
}

-- LN channel mapping: BMS channel -> logical lane (same as regular notes)
M.LN_CHANNEL_TO_LANE = {
    [51] = 1,  -- scratch LN
    [52] = 2,  -- key 1 LN
    [53] = 3,  -- key 2 LN
    [54] = 4,  -- key 3 LN
    [55] = 5,  -- key 4 LN
    [56] = 8,  -- key 7 LN (mapped same as channel 16)
    [58] = 6,  -- key 5 LN (mapped same as channel 18)
    [59] = 7,  -- key 6 LN (mapped same as channel 19)
}

-- LN channels
M.LN_CHANNELS = {
    51, 52, 53, 54, 55, 56, 57, 58, 59, -- 1P LN
    61, 62, 63, 64, 65, 66, 67, 68, 69, -- 2P LN
}

--- Check if channel is a note channel (playable)
---@param channel integer
---@return boolean
function M.is_note_channel(channel)
    return (channel >= 11 and channel <= 19) or (channel >= 21 and channel <= 29)
end

--- Check if channel is a BGM channel
---@param channel integer
---@return boolean
function M.is_bgm_channel(channel)
    return channel == 1
end

--- Check if channel is an LN channel (to be ignored in Phase 1)
---@param channel integer
---@return boolean
function M.is_ln_channel(channel)
    for _, ln in ipairs(M.LN_CHANNELS) do
        if channel == ln then return true end
    end
    return false
end

--- Check if channel is invisible note channel
---@param channel integer
---@return boolean
function M.is_invisible_channel(channel)
    return (channel >= 31 and channel <= 39) or (channel >= 41 and channel <= 49)
end

--- Get lane number for note channel
---@param channel integer
---@return integer|nil lane number or nil if not a mapped channel
function M.get_lane(channel)
    return M.CHANNEL_TO_LANE[channel]
end

--- Get lane number for LN channel
---@param channel integer
---@return integer|nil lane number or nil if not a mapped channel
function M.get_ln_lane(channel)
    return M.LN_CHANNEL_TO_LANE[channel]
end

return M
