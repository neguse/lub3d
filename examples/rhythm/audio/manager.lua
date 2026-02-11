--- Audio manager for rhythm game
--- Uses Generator-based miniaudio bindings
local slog = require("sokol.log")

-- Log levels: 0=panic, 1=error, 2=warn, 3=info
local function log_info(msg)
    slog.Func("audio", 3, 0, msg, 0, "manager.lua", nil)
end

local function log_warn(msg)
    slog.Func("audio", 2, 0, msg, 0, "manager.lua", nil)
end

local function log_err(msg)
    slog.Func("audio", 1, 0, msg, 0, "manager.lua", nil)
end

---@class AudioManager
---@field sounds table<integer, any> wav_id -> sound object
---@field engine_initialized boolean
---@field engine any miniaudio.Engine object
local AudioManager = {}
AudioManager.__index = AudioManager

--- Create a new AudioManager
---@return AudioManager
function AudioManager.new()
    local self = setmetatable({}, AudioManager)
    self.sounds = {}
    self.engine_initialized = false
    self.engine = nil
    return self
end

--- Initialize the audio engine
---@return boolean success
---@return string|nil error
function AudioManager:init()
    local ok, ma = pcall(require, "miniaudio")
    if ok and ma then
        local engine = ma.EngineInit()
        if engine then
            engine:Start()
            self.engine_initialized = true
            self.engine = engine
            self._ma = ma
            return true
        else
            return false, "EngineInit failed"
        end
    end

    -- Fallback: no audio (silent mode)
    log_info("miniaudio not available, running in silent mode")
    self.engine_initialized = true
    return true
end

--- Shutdown the audio engine
function AudioManager:shutdown()
    if self.engine then
        self.engine:Stop()
    end
    self.sounds = {}
    self.engine = nil
    self.engine_initialized = false
end

local fs = require("lub3d.fs")

-- Check if file exists
local function file_exists(path)
    if fs.exists(path) then
        return true
    end
    -- Try with backslashes
    local win_path = path:gsub("/", "\\")
    return fs.exists(win_path)
end

-- Try loading with alternative extensions
local function try_load_sound(ma, engine, path)
    -- Try original path first
    if file_exists(path) then
        local ok, sound = pcall(ma.SoundInitFromFile, engine, path, 0)
        if ok and sound then
            return sound
        end
    end

    -- Try alternative extensions (BMS often uses .wav but actual file is .ogg)
    local base = path:match("(.+)%.[^.]+$")
    if base then
        local alternatives = { ".ogg", ".wav", ".mp3", ".flac" }
        for _, ext in ipairs(alternatives) do
            local alt_path = base .. ext
            local exists = file_exists(alt_path)
            if exists then
                local ok, sound = pcall(ma.SoundInitFromFile, engine, alt_path, 0)
                if ok and sound then
                    return sound
                else
                    log_err(string.format("file exists but load failed: %s err=%s", alt_path, tostring(sound)))
                end
            end
        end
    end

    return nil
end

--- Load a WAV file
---@param wav_id integer
---@param path string
---@return boolean success
function AudioManager:load_wav(wav_id, path)
    if not self.engine_initialized then
        log_err(string.format("Engine not initialized, cannot load %s", path))
        return false
    end

    if self._ma and self.engine then
        local sound = try_load_sound(self._ma, self.engine, path)
        if sound then
            self.sounds[wav_id] = sound
            return true
        else
            log_err(string.format("Failed to load wav_id=%d path=%s", wav_id, path))
            return false
        end
    end

    -- Silent mode: just mark as loaded
    log_info(string.format("Silent mode: wav_id=%d path=%s", wav_id, path))
    self.sounds[wav_id] = { path = path, dummy = true }
    return true
end

--- Play a sound by wav_id
---@param wav_id integer
function AudioManager:play(wav_id)
    local sound = self.sounds[wav_id]
    if not sound then
        return
    end

    if sound.dummy then
        return
    end

    -- Reset and start the sound
    if self._ma then
        pcall(function()
            sound:SeekToPcmFrame(0)
            sound:Start()
        end)
    end
end

--- Preload all WAVs from a chart
---@param wavs table<integer, string> wav_id -> relative path
---@param base_dir string directory containing the BMS file
function AudioManager:preload_chart(wavs, base_dir)
    for wav_id, relative_path in pairs(wavs) do
        -- Normalize path separators
        relative_path = relative_path:gsub("\\", "/")
        local full_path = base_dir .. "/" .. relative_path
        self:load_wav(wav_id, full_path)
    end
end

--- Stop all playing sounds
function AudioManager:stop_all()
    if self._ma then
        for _, sound in pairs(self.sounds) do
            if not sound.dummy then
                pcall(function()
                    sound:Stop()
                end)
            end
        end
    end
end

--- Check if audio is available
---@return boolean
function AudioManager:is_available()
    return self.engine_initialized and self._ma ~= nil
end

return AudioManager
