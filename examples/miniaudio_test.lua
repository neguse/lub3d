-- miniaudio_test.lua - miniaudio Engine/Sound API test
-- Generates a sine wave WAV file and plays it back

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")
local ma = require("miniaudio")

local engine ---@type miniaudio.Engine
local sound ---@type miniaudio.Sound
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
    write_u32(16)       -- chunk size
    write_u16(1)        -- PCM
    write_u16(1)        -- mono
    write_u32(sample_rate)
    write_u32(sample_rate * 2) -- byte rate
    write_u16(2)        -- block align
    write_u16(16)       -- bits per sample
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

app.Run(app.Desc({
    width = 640,
    height = 480,
    window_title = "miniaudio test",

    init = function()
        gfx.Setup(gfx.Desc({
            environment = glue.Environment(),
        }))
        gl.Setup(gl.Desc({}))

        -- Generate test WAV
        generate_wav(wav_path, 440, 2.0)

        -- Init engine & play sound
        engine = ma.EngineInit()
        engine:Start()
        engine:SetVolume(0.5)
        print("engine channels: " .. engine:GetChannels())
        print("engine sample rate: " .. engine:GetSampleRate())

        sound = ma.SoundInitFromFile(engine, wav_path, 0)
        sound:SetLooping(true)
        sound:SetVolume(0.8)
        sound:Start()

        print("miniaudio: playing sine wave (440Hz)")
    end,

    frame = function()
        frame_count = frame_count + 1
        local t = frame_count / 60.0

        -- Oscillate volume
        local vol = 0.3 + 0.5 * (math.sin(t * 0.5) + 1) / 2
        if sound then
            sound:SetVolume(vol)
        end

        gfx.BeginPass(gfx.Pass({
            action = gfx.PassAction({
                colors = {
                    gfx.ColorAttachmentAction({
                        load_action = gfx.LoadAction.CLEAR,
                        clear_value = gfx.Color({ r = 0.1, g = 0.1, b = 0.15, a = 1.0 }),
                    }),
                },
            }),
            swapchain = glue.Swapchain(),
        }))

        -- Draw volume indicator
        gl.Defaults()
        gl.MatrixModeProjection()
        gl.Ortho(-1, 1, -1, 1, -1, 1)

        -- Volume bar
        local bar_w = vol * 1.5
        gl.BeginQuads()
        gl.V2fC3f(-0.75, -0.1, 0.2, 0.8, 0.3)
        gl.V2fC3f(-0.75, 0.1, 0.2, 0.8, 0.3)
        gl.V2fC3f(-0.75 + bar_w, 0.1, 0.3, 1.0, 0.4)
        gl.V2fC3f(-0.75 + bar_w, -0.1, 0.3, 1.0, 0.4)
        gl.End()

        gl.Draw()
        gfx.EndPass()
        gfx.Commit()
    end,

    cleanup = function()
        -- sound/engine are freed by GC (__gc metamethod)
        sound = nil
        engine = nil
        collectgarbage()
        gl.Shutdown()
        gfx.Shutdown()
        os.remove(wav_path)
    end,

    event = function(ev)
        if ev.type == app.EventType.KEY_DOWN then
            if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
                app.Quit()
            end
        end
    end,
}))
