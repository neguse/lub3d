--- Constants for rhythm game
local M = {}

-- Time units
M.US_PER_MS = 1000
M.US_PER_SEC = 1000000

-- Display
M.SCREEN_WIDTH = 800
M.SCREEN_HEIGHT = 600

-- Lane layout
M.NUM_LANES = 8
M.LANE_WIDTH = 50
M.LANE_HEIGHT = 400
M.JUDGMENT_LINE_Y = 500
M.NOTE_HEIGHT = 20

-- Lane colors (grouped by hand position)
-- S/D/F=left hand, Space=center, J/K/L/;=right hand
M.LANE_COLORS = {
    [1] = { 0.3, 0.5, 1.0, 1.0 }, -- S: left (blue)
    [2] = { 0.5, 0.7, 1.0, 1.0 }, -- D: left index (light blue)
    [3] = { 0.3, 0.5, 1.0, 1.0 }, -- F: left middle (blue)
    [4] = { 1.0, 1.0, 0.3, 1.0 }, -- Space: center (yellow)
    [5] = { 0.3, 1.0, 0.5, 1.0 }, -- J: right index (green)
    [6] = { 0.6, 1.0, 0.7, 1.0 }, -- K: right middle (light green)
    [7] = { 0.3, 1.0, 0.5, 1.0 }, -- L: right ring (green)
    [8] = { 1.0, 0.0, 0.0, 1.0 }, -- ;: right pinky (red)
}

-- Scroll / Hi-Speed
M.PIXELS_PER_BEAT = 100
M.DEFAULT_SCROLL_SPEED = 1.0
M.VISIBLE_BEATS_ABOVE = 8 -- beats visible above judgment line
M.HISPEED_MIN = 0.5
M.HISPEED_MAX = 4.0
M.HISPEED_STEP = 0.25

-- Timing
M.LEAD_TIME_US = 3000000 -- 3 seconds lead time before chart starts

-- Input (default key mapping for 7key + scratch)
M.KEY_MAPPING = {
    -- Keycode -> lane
    [83] = 1,   -- S -> scratch (lane 1)
    [68] = 2,   -- D -> key 1 (lane 2)
    [70] = 3,   -- F -> key 2 (lane 3)
    [32] = 4,   -- Space -> key 3 (lane 4)
    [74] = 5,   -- J -> key 4 (lane 5)
    [75] = 6,   -- K -> key 5 (lane 6)
    [76] = 7,   -- L -> key 6 (lane 7)
    [59] = 8,   -- ; -> key 7 (lane 8)
}

-- Judgment windows (μs)
M.JUDGE_WINDOWS = {
    pgreat = 18000,   -- ±18ms
    great  = 40000,   -- ±40ms
    good   = 100000,  -- ±100ms
    bad    = 200000,  -- ±200ms
}

-- #RANK window multipliers
M.RANK_MULTIPLIER = {
    [0] = 0.5,   -- VERY HARD
    [1] = 0.75,  -- HARD
    [2] = 1.0,   -- NORMAL
    [3] = 1.25,  -- EASY
}

-- Judgment display colors (RGBA)
M.JUDGMENT_COLORS = {
    pgreat = { 1.0, 1.0, 0.2, 1.0 },     -- yellow
    great = { 1.0, 0.8, 0.0, 1.0 },       -- orange
    good = { 0.2, 1.0, 0.2, 1.0 },        -- green
    bad = { 0.5, 0.5, 1.0, 1.0 },         -- blue
    miss = { 1.0, 0.2, 0.2, 1.0 },        -- red
    empty_poor = { 0.5, 0.2, 0.2, 1.0 },  -- dark red
}

-- Judgment display text
M.JUDGMENT_TEXT = {
    pgreat = "PGREAT",
    great = "GREAT",
    good = "GOOD",
    bad = "BAD",
    miss = "MISS",
    empty_poor = "POOR",
}

-- Fast/Slow colors
M.TIMING_COLORS = {
    fast = { 0.3, 0.7, 1.0, 1.0 }, -- light blue
    slow = { 1.0, 0.5, 0.3, 1.0 }, -- orange
}

-- Gauge layout
M.GAUGE_X = 750
M.GAUGE_Y = 100
M.GAUGE_WIDTH = 30
M.GAUGE_HEIGHT = 400

return M
