-- hakonotaiatari audio module
-- Sound effects and BGM using sokol.audio

---@type fun(path: string): string?
---@diagnostic disable-next-line: undefined-global
local fetch_file = fetch_file

local log = require("lib.log")

local M = {}

-- Try to load sokol.audio (try both naming conventions)
local audio_ok, audio = pcall(require, "sokol.audio")
if not audio_ok then
    audio_ok, audio = pcall(require, "sokol_audio")
end
if not audio_ok then
    log.warn("sokol.audio not available, audio disabled")
    ---@diagnostic disable-next-line: cast-local-type
    audio = nil
end

-- Audio state
local initialized = false
local sounds = {}        -- Loaded sound data (index -> {samples, sample_count, channels, sample_rate})
local playing = {}       -- Currently playing sounds {sound_index, position, volume, loop}
local bgm_index = nil
local bgm_position = 0
local bgm_playing = false

-- Sound file mapping (matches original app.cc order)
local SOUND_FILES = {
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

-- Audio parameters (must match main.c saudio_setup)
local SAMPLE_RATE = 44100
local NUM_CHANNELS = 1
local BUFFER_FRAMES = 2048
local PACKET_FRAMES = 512  -- Max frames per push
local MAX_PLAYING = 8

-- Read file contents (supports both native io.open and WASM fetch_file)
local function read_file(filepath)
    -- WASM environment: use fetch_file global
    if fetch_file then
        return fetch_file(filepath)
    end
    -- Native environment: use io.open
    local file = io.open(filepath, "rb")
    if not file then
        return nil
    end
    local data = file:read("*a")
    file:close()
    return data
end

-- Simple WAV loader (mono/stereo, 16-bit PCM only)
local function load_wav(filepath)
    local data = read_file(filepath)
    if not data then
        log.warn("Failed to open WAV file: " .. filepath)
        return nil
    end

    if #data < 44 then
        log.warn("WAV file too small: " .. filepath)
        return nil
    end

    -- Check RIFF header
    if data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WAVE" then
        log.warn("Invalid WAV header: " .. filepath)
        return nil
    end

    -- Find fmt chunk
    local pos = 13
    local channels, sample_rate, bits_per_sample
    while pos < #data - 8 do
        local chunk_id = data:sub(pos, pos + 3)
        local chunk_size = string.unpack("<I4", data, pos + 4)

        if chunk_id == "fmt " then
            local audio_format = string.unpack("<I2", data, pos + 8)
            channels = string.unpack("<I2", data, pos + 10)
            sample_rate = string.unpack("<I4", data, pos + 12)
            bits_per_sample = string.unpack("<I2", data, pos + 22)

            if audio_format ~= 1 then
                log.warn("Only PCM WAV supported: " .. filepath)
                return nil
            end
        elseif chunk_id == "data" then
            if not channels then
                log.warn("No fmt chunk before data: " .. filepath)
                return nil
            end

            local audio_data = data:sub(pos + 8, pos + 7 + chunk_size)
            local samples = {}

            if bits_per_sample == 16 then
                for i = 1, #audio_data - 1, 2 do
                    local sample = string.unpack("<i2", audio_data, i)
                    table.insert(samples, sample / 32768.0)  -- Normalize to -1..1
                end
            elseif bits_per_sample == 8 then
                for i = 1, #audio_data do
                    local sample = string.unpack("B", audio_data, i)
                    table.insert(samples, (sample - 128) / 128.0)
                end
            else
                log.warn("Unsupported bits per sample: " .. bits_per_sample)
                return nil
            end

            -- Convert stereo to mono if needed
            if channels == 2 then
                local mono = {}
                for i = 1, #samples - 1, 2 do
                    table.insert(mono, (samples[i] + samples[i + 1]) / 2)
                end
                samples = mono
            end

            return {
                samples = samples,
                sample_count = #samples,
                channels = 1,  -- Always mono after conversion
                sample_rate = sample_rate,
            }
        end

        pos = pos + 8 + chunk_size
        if chunk_size % 2 == 1 then pos = pos + 1 end  -- Padding
    end

    log.warn("No data chunk found: " .. filepath)
    return nil
end

-- Audio buffer for mixing
local mix_buffer = {}

-- Audio callback (called by sokol.audio)
local function audio_callback()
    if not initialized or not audio then return end

    local num_frames = audio.expect()
    if num_frames <= 0 then return end
    -- Limit to packet size to avoid overflow
    if num_frames > PACKET_FRAMES then
        num_frames = PACKET_FRAMES
    end

    -- Clear mix buffer
    for i = 1, num_frames do
        mix_buffer[i] = 0
    end

    -- Mix BGM
    if bgm_playing and bgm_index and sounds[bgm_index] then
        local snd = sounds[bgm_index]
        local rate_ratio = snd.sample_rate / SAMPLE_RATE

        for i = 1, num_frames do
            local src_pos = math.floor(bgm_position) + 1
            if src_pos <= snd.sample_count then
                mix_buffer[i] = mix_buffer[i] + (snd.samples[src_pos] or 0) * 0.5
            end
            bgm_position = bgm_position + rate_ratio

            -- Loop BGM
            if bgm_position >= snd.sample_count then
                bgm_position = 0
            end
        end
    end

    -- Mix playing sounds
    local still_playing = {}
    for _, p in ipairs(playing) do
        local snd = sounds[p.index]
        if snd then
            local rate_ratio = snd.sample_rate / SAMPLE_RATE

            for i = 1, num_frames do
                local src_pos = math.floor(p.position) + 1
                if src_pos <= snd.sample_count then
                    mix_buffer[i] = mix_buffer[i] + (snd.samples[src_pos] or 0) * p.volume
                end
                p.position = p.position + rate_ratio
            end

            if p.position < snd.sample_count then
                table.insert(still_playing, p)
            end
        end
    end
    playing = still_playing

    -- Clamp and push to audio device
    local frames = {}
    for i = 1, num_frames do
        local sample = mix_buffer[i]
        if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
        table.insert(frames, sample)
    end

    if #frames > 0 then
        audio.push(frames, #frames)
    end
end

-- Initialize audio system
function M.init()
    -- Disable audio on WASM (fetch_file exists in WASM environment)
    if fetch_file then
        initialized = false
        log.info("Audio system disabled (WASM)")
        return false
    end

    if not audio then
        initialized = false
        log.info("Audio system disabled (sokol.audio not available)")
        return false
    end

    -- Audio is already set up in C (main.c)
    if not audio.isvalid() then
        log.error("Failed to initialize audio")
        return false
    end

    -- Load sound files
    local base_path = "examples/hakonotaiatari/assets/sounds/"
    local loaded_count = 0
    for index, filename in pairs(SOUND_FILES) do
        local filepath = base_path .. filename
        local snd = load_wav(filepath)
        if snd then
            sounds[index] = snd
            log.info(string.format("Loaded sound %d: %s (%d samples)", index, filename, snd.sample_count))
            loaded_count = loaded_count + 1
        end
    end

    -- If no sounds loaded (e.g., WASM without preloaded files), disable audio
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
    -- Audio shutdown is handled in C (main.c)
    initialized = false
    sounds = {}
    playing = {}
end

-- Update audio (call each frame)
function M.update()
    if initialized then
        audio_callback()
    end
end

-- Play a sound effect
function M.play(index, volume)
    if not initialized then return end
    if not sounds[index] then return end

    volume = volume or 0.7

    -- Limit concurrent sounds
    if #playing >= MAX_PLAYING then
        table.remove(playing, 1)
    end

    table.insert(playing, {
        index = index,
        position = 0,
        volume = volume,
    })
end

-- Play BGM
function M.play_bgm(index)
    if not initialized then return end

    if bgm_index == index and bgm_playing then
        return -- Already playing
    end

    bgm_index = index
    bgm_position = 0
    bgm_playing = true
end

-- Stop BGM
function M.stop_bgm()
    bgm_playing = false
end

-- Stop all sounds
function M.stop_all()
    M.stop_bgm()
    playing = {}
end

-- Check if audio is available
function M.is_available()
    return initialized
end

return M
