-- hakonotaiatari audio module
-- Sound effects and BGM using miniaudio

local log = require("lib.log")

local M = {}

local ma        --- @type miniaudio?
local audio_lib --- @type table?
do
    local ok, mod = pcall(require, "miniaudio")
    if ok then
        ma = mod
        audio_lib = require("lib.audio")
    else
        log.warn("miniaudio not available, audio disabled")
    end
end

local engine = nil
local vfs_ref = nil
local sounds = {} -- index -> ma_sound
local bgm_index = nil

-- Sound file mapping (matches original app.cc order)
local SOUND_FILES <const> = {
    [0] = "hakotai.wav",      -- Title SE
    [1] = "ne4.wav",          -- BGM1
    [2] = "sakura.wav",       -- BGM2
    [3] = "tt.wav",           -- BGM3
    [4] = "hit1.wav",         -- Hit1
    [5] = "suberi.wav",       -- Dash
    [6] = "hit4.wav",         -- Hit4
    [7] = "fire.wav",         -- Fire/death
    [8] = "fall.wav",         -- Fall
    [9] = "powerfull.wav",    -- Power charged
    [10] = "result.wav",      -- Result
    [11] = "result_high.wav", -- High score
    [12] = "kaki.wav",        -- Hit enemy
    [13] = "revirth.wav",     -- Enemy revive
    [14] = "suberie.wav",     -- Enemy dash
}

local initialized = false

local SOUND_PATH <const> = "examples/hakonotaiatari/assets/sounds/"

-- Initialize audio system
function M.init()
    if not ma or not audio_lib then
        initialized = false
        log.info("Audio system disabled (miniaudio not available)")
        return false
    end

    engine, vfs_ref = audio_lib.create_engine()
    if not engine then
        log.warn("Failed to init miniaudio engine")
        initialized = false
        return false
    end
    engine:start()
    engine:set_volume(0.5)

    local loaded_count = 0
    for index, filename in pairs(SOUND_FILES) do
        local path = SOUND_PATH .. filename
        local ok, snd = pcall(ma.sound_init_from_file, engine, path, 0)
        if ok and snd then
            sounds[index] = snd
            log.info(string.format("Loaded sound %d: %s", index, filename))
            loaded_count = loaded_count + 1
        else
            log.warn("Failed to load sound: " .. path)
        end
    end

    if loaded_count == 0 then
        log.warn("No sound files loaded, audio disabled")
        initialized = false
        return false
    end

    initialized = true
    log.info("Audio system initialized")
    return true
end

-- Cleanup audio system
function M.cleanup()
    for _, snd in pairs(sounds) do
        snd:stop()
    end
    sounds = {}
    bgm_index = nil
    engine = nil
    vfs_ref = nil
    initialized = false
    collectgarbage()
end

-- Update audio (call each frame) - no-op with miniaudio
function M.update() end

-- Play a sound effect
function M.play(index, volume)
    if not initialized then
        return
    end
    local snd = sounds[index]
    if not snd then
        return
    end
    snd:stop()
    snd:seek_to_pcm_frame(0)
    if volume then
        snd:set_volume(volume)
    end
    snd:start()
end

-- Play BGM (looping)
function M.play_bgm(index)
    if not initialized then
        return
    end
    if bgm_index == index then
        return
    end

    -- Stop previous BGM
    if bgm_index and sounds[bgm_index] then
        sounds[bgm_index]:stop()
        sounds[bgm_index]:set_looping(false)
    end

    local snd = sounds[index]
    if not snd then
        return
    end
    bgm_index = index
    snd:set_looping(true)
    snd:stop()
    snd:seek_to_pcm_frame(0)
    snd:start()
end

-- Stop BGM
function M.stop_bgm()
    if bgm_index and sounds[bgm_index] then
        sounds[bgm_index]:stop()
        sounds[bgm_index]:set_looping(false)
    end
    bgm_index = nil
end

-- Stop all sounds
function M.stop_all()
    M.stop_bgm()
    for _, snd in pairs(sounds) do
        snd:stop()
    end
end

-- Check if audio is available
function M.is_available()
    return initialized
end

return M
