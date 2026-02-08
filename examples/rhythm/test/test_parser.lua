--- Tests for BMS parser module
local parser = require("examples.rhythm.bms.parser")

local function test_parse_header()
    local content = [[
#PLAYER 1
#GENRE Test Genre
#TITLE Test Title
#ARTIST Test Artist
#BPM 150
#PLAYLEVEL 5
#RANK 2
]]
    local chart = parser.parse(content)

    assert(chart.header.player == 1)
    assert(chart.header.genre == "Test Genre")
    assert(chart.header.title == "Test Title")
    assert(chart.header.artist == "Test Artist")
    assert(chart.header.bpm == 150)
    assert(chart.header.playlevel == 5)
    assert(chart.header.rank == 2)

    print("  parse_header: OK")
end

local function test_parse_wav()
    local content = [[
#WAV01 kick.wav
#WAV0A snare.wav
#WAVZZ last.wav
]]
    local chart = parser.parse(content)

    assert(chart.wavs[1] == "kick.wav")
    assert(chart.wavs[10] == "snare.wav")
    assert(chart.wavs[1295] == "last.wav")

    print("  parse_wav: OK")
end

local function test_parse_bmp()
    local content = [[
#BMP01 image1.bmp
#BMP0F image2.png
]]
    local chart = parser.parse(content)

    assert(chart.bmps[1] == "image1.bmp")
    assert(chart.bmps[15] == "image2.png")

    print("  parse_bmp: OK")
end

local function test_parse_bpm_def()
    local content = [[
#BPM01 180.5
#BPMFF 200
]]
    local chart = parser.parse(content)

    assert(chart.bpm_defs[1] == 180.5)
    assert(chart.bpm_defs[555] == 200) -- FF = 15*36+15 = 555

    print("  parse_bpm_def: OK")
end

local function test_parse_stop_def()
    local content = [[
#STOP01 48
#STOP02 192
]]
    local chart = parser.parse(content)

    assert(chart.stop_defs[1] == 48)
    assert(chart.stop_defs[2] == 192)

    print("  parse_stop_def: OK")
end

local function test_parse_measure_length()
    local content = [[
#00002:0.75
#00102:1.5
]]
    local chart = parser.parse(content)

    assert(chart.measure_lengths[0] == 0.75)
    assert(chart.measure_lengths[1] == 1.5)

    print("  parse_measure_length: OK")
end

local function test_parse_channel()
    local content = [[
#00011:01020300
#00101:0102
#00108:01
]]
    local chart = parser.parse(content)

    assert(#chart.channels == 3)

    -- First channel
    assert(chart.channels[1].measure == 0)
    assert(chart.channels[1].channel == 11)
    assert(chart.channels[1].data == "01020300")

    -- Second channel (BGM)
    assert(chart.channels[2].measure == 1)
    assert(chart.channels[2].channel == 1)
    assert(chart.channels[2].data == "0102")

    -- Third channel (BPM change)
    assert(chart.channels[3].measure == 1)
    assert(chart.channels[3].channel == 8)
    assert(chart.channels[3].data == "01")

    print("  parse_channel: OK")
end

local function test_parse_objects()
    -- Test basic parsing
    local ids, positions = parser.parse_objects("01020304")
    assert(#ids == 4)
    assert(ids[1] == 1)
    assert(ids[2] == 2)
    assert(ids[3] == 3)
    assert(ids[4] == 4)
    assert(positions[1] == 0)
    assert(positions[2] == 0.25)
    assert(positions[3] == 0.5)
    assert(positions[4] == 0.75)

    -- Test filtering 00
    ids, positions = parser.parse_objects("01000200")
    assert(#ids == 2)
    assert(ids[1] == 1)
    assert(ids[2] == 2)
    assert(positions[1] == 0)
    assert(positions[2] == 0.5)

    -- Test empty data
    ids, positions = parser.parse_objects("00")
    assert(#ids == 0)

    -- Test all zeros
    ids, positions = parser.parse_objects("00000000")
    assert(#ids == 0)

    print("  parse_objects: OK")
end

local function test_skip_ln_channels()
    local content = [[
#00051:01020304
#00061:01020304
#00011:01020304
]]
    local chart = parser.parse(content)

    -- LN channels (51, 61) should be skipped
    assert(#chart.channels == 1)
    assert(chart.channels[1].channel == 11)

    print("  skip_ln_channels: OK")
end

local function test_skip_comments()
    local content = [[
* This is a comment
#TITLE Test
*Another comment
#BPM 120
]]
    local chart = parser.parse(content)

    assert(chart.header.title == "Test")
    assert(chart.header.bpm == 120)

    print("  skip_comments: OK")
end

local function test_load_fixture()
    local chart, err = parser.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart, "Failed to load simple.bms: " .. (err or ""))

    assert(chart.header.title == "Simple Test")
    assert(chart.header.artist == "mane3d")
    assert(chart.header.bpm == 120)
    assert(chart.wavs[1] == "test_kick.wav")
    assert(chart.wavs[2] == "test_snare.wav")

    print("  load_fixture: OK")
end

local function test_load_bpm_change()
    local chart, err = parser.load("examples/rhythm/test/fixtures/bpm_change.bms")
    assert(chart, "Failed to load bpm_change.bms: " .. (err or ""))

    assert(chart.header.bpm == 120)
    assert(chart.bpm_defs[1] == 180)

    print("  load_bpm_change: OK")
end

local function test_load_measure_length()
    local chart, err = parser.load("examples/rhythm/test/fixtures/measure_length.bms")
    assert(chart, "Failed to load measure_length.bms: " .. (err or ""))

    assert(chart.measure_lengths[0] == 0.75)

    print("  load_measure_length: OK")
end

print("test_parser:")
test_parse_header()
test_parse_wav()
test_parse_bmp()
test_parse_bpm_def()
test_parse_stop_def()
test_parse_measure_length()
test_parse_channel()
test_parse_objects()
test_skip_ln_channels()
test_skip_comments()
test_load_fixture()
test_load_bpm_change()
test_load_measure_length()
print("All parser tests passed!")

return true
