-- miniaudio_test.lua - miniaudio Engine/Sound API test
-- Generates a sine wave WAV file and plays it back

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")
local ma = require("miniaudio")

local engine ---@type miniaudio.Engine?
local sound ---@type miniaudio.Sound?
local wav_path = "test_sine.wav"

-- Generate a simple WAV file with a sine wave
local function generate_wav(path, freq, duration, sample_rate)
    sample_rate = sample_rate or 44100
    local num_samples = math.floor(sample_rate * duration)
    local f = io.open(path, "wb")
    if not f then error("cannot open " .. path) end

    local function write_u16(v) f:write(string.char(v % 256, math.floor(v / 256) % 256)) end
    local function write_u32(v)
        f:write(string.char(v % 256, math.floor(v / 256) % 256,
            math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256))
    end

    local data_size = num_samples * 2 -- 16-bit mono
    -- RIFF header
    f:write("RIFF")
    write_u32(36 + data_size)
    f:write("WAVE")
    -- fmt chunk
    f:write("fmt ")
    write_u32(16)              -- chunk size
    write_u16(1)               -- PCM
    write_u16(1)               -- mono
    write_u32(sample_rate)
    write_u32(sample_rate * 2) -- byte rate
    write_u16(2)               -- block align
    write_u16(16)              -- bits per sample
    -- data chunk
    f:write("data")
    write_u32(data_size)
    for i = 0, num_samples - 1 do
        local t = i / sample_rate
        local sample = math.sin(2 * math.pi * freq * t) * 0.3
        local v = math.floor(sample * 32767)
        if v < 0 then v = v + 65536 end
        write_u16(v)
    end

    f:close()
end

local frame_count = 0

local M = {}
M.width = 640
M.height = 480
M.window_title = "miniaudio test"

function M:init()
    gfx.setup(gfx.desc({
        environment = glue.environment(),
    }))
    gl.setup(gl.desc({}))

    -- Generate test WAV
    generate_wav(wav_path, 440, 2.0)

    -- Init engine & play sound
    engine = ma.engine_init()
    engine:start()
    engine:set_volume(0.5)
    print("engine channels: " .. engine:get_channels())
    print("engine sample rate: " .. engine:get_sample_rate())

    sound = ma.sound_init_from_file(engine, wav_path, 0)
    sound:set_looping(true)
    sound:set_volume(0.8)
    sound:start()

    print("miniaudio: playing sine wave (440Hz)")
end

function M:frame()
    frame_count = frame_count + 1
    local t = frame_count / 60.0

    -- Oscillate volume
    local vol = 0.3 + 0.5 * (math.sin(t * 0.5) + 1) / 2
    if sound then
        sound:set_volume(vol)
    end

    gfx.begin_pass(gfx.pass({
        action = gfx.pass_action({
            colors = {
                gfx.color_attachment_action({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.color({ r = 0.1, g = 0.1, b = 0.15, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.swapchain(),
    }))

    -- Draw volume indicator
    gl.defaults()
    gl.matrix_mode_projection()
    gl.ortho(-1, 1, -1, 1, -1, 1)

    -- Volume bar
    local bar_w = vol * 1.5
    gl.begin_quads()
    gl.v2f_c3f(-0.75, -0.1, 0.2, 0.8, 0.3)
    gl.v2f_c3f(-0.75, 0.1, 0.2, 0.8, 0.3)
    gl.v2f_c3f(-0.75 + bar_w, 0.1, 0.3, 1.0, 0.4)
    gl.v2f_c3f(-0.75 + bar_w, -0.1, 0.3, 1.0, 0.4)
    gl["end"]()

    gl.draw()
    gfx.end_pass()
    gfx.commit()
end

function M:cleanup()
    -- sound/engine are freed by GC (__gc metamethod)
    sound = nil
    engine = nil
    collectgarbage()
    gl.shutdown()
    gfx.shutdown()
    os.remove(wav_path)
end

function M:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.quit()
        end
    end
end

return M
