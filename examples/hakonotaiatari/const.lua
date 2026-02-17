-- hakonotaiatari constants
-- Ported from deps/hakonotaiatari/src/const.h and variable.h

local M = {}

-- Math constants
M.PI = 3.1415926535897932384626433832795
M.SQRT2 = 1.4142135623730950488

-- Frame rate
M.FPS = 60
M.DELTA_T = 1.0 / M.FPS

-- Window/render target size
M.WIN_W = 240
M.WIN_H = 240
M.RT_W = 240
M.RT_H = 240

-- Field size
M.FIELD_L = 300
M.FIELD_LF = 300.0

-- Cube types
M.C_TYPE_PLAYER = 0x00000001
M.C_TYPE_ENEMY_MASK = 0x10000000
M.C_TYPE_NORMAL_ENEMY = 0x10000001 -- C_TYPE_ENEMY_MASK | 0x01
M.C_TYPE_DASH_ENEMY = 0x10000002   -- C_TYPE_ENEMY_MASK | 0x02

-- Collision states
M.C_COL_ST_NONE = 0
M.C_COL_ST_NORMAL = 1
M.C_COL_ST_DASH = 2
M.C_COL_ST_FUTTOBI = 3

-- Player states
M.P_ST_MUTEKI = 1           -- Invulnerable
M.P_ST_NORMAL = 2           -- Normal
M.P_ST_DASH = 3             -- Dashing
M.P_ST_FUTTOBI = 4          -- Knocked back
M.P_ST_FUTTOBI_NOMUTEKI = 5 -- Knocked back (no invulnerability after)
M.P_ST_FADEOUT = 6          -- Fading out
M.P_ST_DEAD = 7             -- Dead

-- Enemy states
M.E_ST_APPEAR = 11  -- Appearing
M.E_ST_MUTEKI = 12  -- Invulnerable
M.E_ST_NORMAL = 13  -- Normal
M.E_ST_DASH = 14    -- Dashing
M.E_ST_FUTTOBI = 15 -- Knocked back
M.E_ST_FADEOUT = 16 -- Fading out
M.E_ST_DEAD = 17    -- Dead

-- Player colors (ARGB format, convert to RGB for sokol)
M.P_COL_NORMAL = 0xffffffff
M.P_COL_DASH = 0xffff3040
M.P_COL_FUTTOBI = 0xffa0a0a0
M.P_COL_DASH_PARTICLE = 0xfff89880
M.P_COL_DASH_GUIDE = 0xfff0f0f0
M.P_COL_DASH_GUIDE_DISABLE = 0xff404040
M.P_COL_DASH_PT = 0xffffffa0  -- Bright yellow-white for PT emission during dash

-- Player timing (frames)
M.P_MUTEKI_F = 180  -- Invulnerability duration
M.P_NOMUTEKI_F = 10 -- Short invulnerability after dash knockback
M.P_FUTTOBI_F = 75  -- Knockback duration
M.P_FADEOUT_F = 150 -- Fadeout duration

-- Player physics
M.P_LEN = 10.0        -- Player cube size
M.P_DASH_LEN = 20.0   -- Size increase during dash
M.P_VR = 3.0          -- Velocity ratio (mouse following)
M.P_VL = 70.0         -- Max velocity (normal)
M.P_DASH_V = 250.0    -- Dash velocity
M.P_FUTTOBI_V = 200.0 -- Knockback velocity

-- Player power system
M.P_DASH_MIN_POW = 30  -- Min power to dash
M.P_DASH_USE_POW = 80  -- Power consumed per dash
M.P_POW_MAX = 120      -- Max power
M.P_POW_COEFF = 0.2    -- Power coefficient for dash duration
M.P_POW_GETA = 15      -- Base dash frames
M.P_POW_HIT_BONUS = 15 -- Power gained when hit

-- Player life
M.P_LIFE_INIT = 3 -- Initial lives

-- Enemy colors
M.E_COL_NORMAL = 0xffffffff
M.E_COL_FUTTOBI = 0xffa0a0a0
M.E_COL_DASH = 0xfff0f040
M.E_COL_DASH_PARTICLE = 0xfff0f040

-- Enemy size
M.E_LEN = 10.0 -- Enemy cube size

-- Enemy timing (frames)
M.E_APPEAR_F = 60  -- Appear duration
M.E_MUTEKI_F = 120 -- Invulnerability after revive
M.E_FUTTOBI_F = 60 -- Knockback duration
M.E_FADEOUT_F = 90 -- Fadeout duration

-- Enemy physics
M.E_FUTTOBI_V = 300.0 -- Knockback velocity
M.E_NORMAL_V = 75.0   -- Normal enemy velocity
M.E_DASH_V = 180.0    -- Dash enemy dash velocity
M.E_DASH_LEN = 20.0   -- Dash enemy size increase during dash
M.E_DASH_F = 90       -- Dash enemy dash duration (frames)

-- Camera constants
M.CAM_BEHIND_HIGH = 600.0        -- Normal camera height
M.CAM_BEHIND_BACK = 400.0        -- Normal camera distance
M.CAM_BEHIND_HIGH_DASH = 550.0   -- Camera height during dash
M.CAM_BEHIND_BACK_DASH = 350.0   -- Camera distance during dash
M.CAM_BEHIND_HIGH_DEAD = 600.0   -- Camera height when dead
M.CAM_BEHIND_BACK_DEAD = 1200.0  -- Camera distance when dead
M.CAM_BEHIND_HIGH_TITLE = 1000.0 -- Title screen camera height
M.CAM_BEHIND_BACK_TITLE = 1000.0 -- Title screen camera distance
M.CAM_ROT_SPEED = 0.011          -- Camera rotation speed
M.CAM_BEHIND_COEFF = 0.08        -- Camera interpolation coefficient

-- Wave/Sound indices
M.WAVE_TITLE_INDEX = 0
M.WAVE_BGM1_INDEX = 1
M.WAVE_BGM2_INDEX = 2
M.WAVE_BGM3_INDEX = 3
M.WAVE_HIT1_INDEX = 4
M.WAVE_SUBERI_INDEX = 5       -- Dash sound
M.WAVE_HIT4_INDEX = 6
M.WAVE_FIRE_INDEX = 7         -- Enemy death
M.WAVE_FALL_INDEX = 8         -- Player death
M.WAVE_POWERFULL_INDEX = 9    -- Power charged
M.WAVE_RESULT_INDEX = 10      -- Result screen
M.WAVE_RESULT_HIGH_INDEX = 11 -- High score
M.WAVE_NAGU_INDEX = 12        -- Hit enemy
M.WAVE_REVIRTH_INDEX = 13     -- Enemy revive
M.WAVE_SUBERIE_INDEX = 14     -- Enemy dash
M.WAVE_FILE_MAX = 15

-- Game states
M.GAME_STATE_TITLE = 1
M.GAME_STATE_TUTORIAL = 2
M.GAME_STATE_GAME = 3
M.GAME_STATE_RECORD = 4

-- Helper function: convert ARGB color to RGB vec3 (0-1 range)
function M.argb_to_rgb(argb)
    local r = ((argb >> 16) & 0xFF) / 255.0
    local g = ((argb >> 8) & 0xFF) / 255.0
    local b = (argb & 0xFF) / 255.0
    return r, g, b
end

-- Helper function: convert ARGB color to RGBA vec4 (0-1 range)
function M.argb_to_rgba(argb)
    local a = ((argb >> 24) & 0xFF) / 255.0
    local r = ((argb >> 16) & 0xFF) / 255.0
    local g = ((argb >> 8) & 0xFF) / 255.0
    local b = (argb & 0xFF) / 255.0
    return r, g, b, a
end

return M
