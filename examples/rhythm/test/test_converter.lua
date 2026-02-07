--- Tests for BMS converter module
local converter = require("examples.rhythm.bms.converter")

local function approx_eq(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) < eps
end

local function test_load_simple()
    local chart, err = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart, "Failed to load: " .. (err or ""))

    -- Check meta
    assert(chart.meta.title == "Simple Test")
    assert(chart.meta.artist == "mane3d")
    assert(chart.meta.bpm == 120)

    -- Check wavs
    assert(chart.wavs[1] == "test_kick.wav")
    assert(chart.wavs[2] == "test_snare.wav")

    -- Check timing map
    assert(chart.timing_map)
    assert(chart.timing_map.initial_bpm == 120)

    print("  load_simple: OK")
end

local function test_notes_extraction()
    local chart, err = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart, "Failed to load: " .. (err or ""))

    -- simple.bms has 8 notes (1小節待ってから1拍おき):
    -- measure 1, ch 11: 01000100 -> beat 4, 6 (scratch)
    -- measure 1, ch 13: 00010001 -> beat 5, 7 (key 2)
    -- measure 2, ch 11: 01000100 -> beat 8, 10 (scratch)
    -- measure 2, ch 13: 00010001 -> beat 9, 11 (key 2)

    assert(#chart.notes == 8, "Expected 8 notes, got " .. #chart.notes)

    -- Notes should be sorted by beat
    -- First note at beat 4
    assert(approx_eq(chart.notes[1].beat, 4), "First note at beat 4")

    -- Check first note is scratch (lane 1)
    assert(chart.notes[1].lane == 1, "First note should be scratch")

    -- Check wav_ids
    assert(chart.notes[1].wav_id == 1, "Scratch uses wav 01")

    -- Check time_us (BPM 120 = 500000 μs/beat)
    -- beat 4 = 4 * 500000 = 2000000
    assert(chart.notes[1].time_us == 2000000, "beat 4 = 2000000 us")

    print("  notes_extraction: OK")
end

local function test_bpm_change()
    local chart, err = converter.load("examples/rhythm/test/fixtures/bpm_change.bms")
    assert(chart, "Failed to load: " .. (err or ""))

    -- bpm_change.bms:
    -- Initial BPM 120
    -- #00011:01     -> beat 0
    -- #00108:01     -> BPM change to 180 at beat 0 (references #BPM01)
    -- #00111:02     -> beat 4
    -- #00211:01     -> beat 8

    -- Check timing map handles BPM change
    -- beat 0-4: BPM 120 (but note: BPM change at beat 0 to 180)
    -- Actually, #00108:01 means BPM change at position 0 of measure 0 → beat 0

    -- Let's check the notes have correct times
    -- With BPM 180: 1 beat = 333333 μs

    -- Note at beat 0 should be at time 0
    local note0 = nil
    for _, n in ipairs(chart.notes) do
        if approx_eq(n.beat, 0) then
            note0 = n
            break
        end
    end
    assert(note0 and note0.time_us == 0, "Note at beat 0 should be at time 0")

    print("  bpm_change: OK")
end

local function test_measure_length()
    local chart, err = converter.load("examples/rhythm/test/fixtures/measure_length.bms")
    assert(chart, "Failed to load: " .. (err or ""))

    -- measure_length.bms:
    -- #00002:0.75   -> measure 0 is 3/4 (0.75 * 4 = 3 beats)
    -- #00011:010101 -> 3 notes at positions 0, 1/3, 2/3 in measure 0
    -- #00111:01     -> 1 note at position 0 in measure 1

    -- Measure 0: 3 beats (0.75 * 4)
    -- Measure 1 starts at beat 3

    -- Notes in measure 0 at positions 0, 1/3, 2/3
    -- beat = 0, 1, 2
    -- Note in measure 1 at position 0
    -- beat = 3

    assert(#chart.notes == 4, "Expected 4 notes, got " .. #chart.notes)

    -- Check beats
    assert(approx_eq(chart.notes[1].beat, 0), "First note at beat 0")
    assert(approx_eq(chart.notes[2].beat, 1), "Second note at beat 1")
    assert(approx_eq(chart.notes[3].beat, 2), "Third note at beat 2")
    assert(approx_eq(chart.notes[4].beat, 3), "Fourth note at beat 3")

    print("  measure_length: OK")
end

local function test_bgm_extraction()
    -- Create a BMS with BGM
    local parser = require("examples.rhythm.bms.parser")
    local content = [[
#BPM 120
#WAV01 bgm.wav
#00001:01
#00101:01
]]
    local bms = parser.parse(content)
    local chart = converter.convert(bms)

    assert(#chart.bgm == 2, "Expected 2 BGM events")
    assert(chart.bgm[1].wav_id == 1)
    assert(approx_eq(chart.bgm[1].beat, 0))
    assert(approx_eq(chart.bgm[2].beat, 4))

    print("  bgm_extraction: OK")
end

local function test_time_calculation()
    local parser = require("examples.rhythm.bms.parser")
    local content = [[
#BPM 60
#WAV01 test.wav
#00011:01
#00111:01
#00211:01
]]
    local bms = parser.parse(content)
    local chart = converter.convert(bms)

    -- BPM 60 = 1 beat per second = 1000000 μs/beat
    -- Measure 0 = beats 0-4, Measure 1 = beats 4-8, Measure 2 = beats 8-12

    assert(#chart.notes == 3)
    assert(chart.notes[1].time_us == 0)
    assert(chart.notes[2].time_us == 4000000) -- beat 4 = 4 * 1000000
    assert(chart.notes[3].time_us == 8000000) -- beat 8 = 8 * 1000000

    print("  time_calculation: OK")
end

print("test_converter:")
test_load_simple()
test_notes_extraction()
test_bpm_change()
test_measure_length()
test_bgm_extraction()
test_time_calculation()
print("All converter tests passed!")

return true
