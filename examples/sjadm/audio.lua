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
local sounds = {}

local SOUND_PATH <const> = "examples/sjadm/assets/sounds/"

function M.init()
    if not ma or not audio_lib then
        return
    end
    engine, vfs_ref = audio_lib.create_engine()
    if not engine then
        log.warn("Failed to init miniaudio engine")
        return
    end
    engine:start()
    engine:set_volume(0.5)

    local files = {
        bgm = "bgm.wav",
        jump = "jump.wav",
        dash = "dash.wav",
        ground = "ground.wav",
        death = "death.wav",
        item = "item.wav",
        checkpoint = "checkpoint.wav",
        goal = "goal.wav",
        walk = "walk.wav",
        friction = "friction.wav",
    }
    for name, file in pairs(files) do
        local path = SOUND_PATH .. file
        local ok, snd = pcall(ma.sound_init_from_file, engine, path, 0)
        if ok and snd then
            sounds[name] = snd
            log.info("Loaded sound: " .. name)
        else
            log.warn("Failed to load sound: " .. path)
        end
    end

    if sounds.bgm then
        sounds.bgm:set_looping(true)
    end
    if sounds.friction then
        sounds.friction:set_looping(true)
    end
    if sounds.walk then
        sounds.walk:set_looping(true)
    end
end

-- Play a one-shot SE (restarts from beginning)
function M.play(name)
    local snd = sounds[name]
    if not snd then
        return
    end
    snd:stop()
    snd:seek_to_pcm_frame(0)
    snd:start()
end

-- Start a looping sound (only if not already playing)
function M.start_loop(name)
    local snd = sounds[name]
    if not snd then
        return
    end
    if not snd:is_playing() then
        snd:start()
    end
end

-- Stop a sound
function M.stop(name)
    local snd = sounds[name]
    if not snd then
        return
    end
    if snd:is_playing() then
        snd:stop()
    end
end

function M.play_bgm()
    local snd = sounds.bgm
    if not snd then
        return
    end
    snd:stop()
    snd:seek_to_pcm_frame(0)
    snd:start()
end

function M.stop_bgm()
    local snd = sounds.bgm
    if not snd then
        return
    end
    snd:stop()
end

function M.cleanup()
    for _, snd in pairs(sounds) do
        snd:stop()
    end
    sounds = {}
    engine = nil
    collectgarbage()
end

return M
