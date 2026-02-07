--- Tests for TimingMap module
local TimingMap = require("examples.rhythm.core.timing_map")

local US_PER_MINUTE = 60000000

-- Helper: approximately equal for floating point
local function approx_eq(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) < eps
end

local function test_constant_bpm()
    -- BPM 120 = 2 beats per second = 500000 μs per beat
    local tm = TimingMap.new(120)

    -- beat 0 -> time 0
    assert(tm:beat_to_time_us(0) == 0, "beat 0 should be time 0")

    -- beat 1 -> time 500000μs (0.5 sec)
    assert(tm:beat_to_time_us(1) == 500000, "beat 1 should be 500000μs")

    -- beat 4 -> time 2000000μs (2 sec)
    assert(tm:beat_to_time_us(4) == 2000000, "beat 4 should be 2000000μs")

    -- Reverse: time -> beat
    assert(approx_eq(tm:time_us_to_beat(0), 0), "time 0 should be beat 0")
    assert(approx_eq(tm:time_us_to_beat(500000), 1), "time 500000μs should be beat 1")
    assert(approx_eq(tm:time_us_to_beat(2000000), 4), "time 2000000μs should be beat 4")

    print("  constant_bpm: OK")
end

local function test_bpm_change()
    -- Start BPM 120, change to 180 at beat 4
    -- BPM 120: 500000 μs/beat
    -- BPM 180: 333333 μs/beat
    local tm = TimingMap.new(120, { [4] = 180 })

    -- beat 0-4 at BPM 120
    assert(tm:beat_to_time_us(0) == 0)
    assert(tm:beat_to_time_us(2) == 1000000) -- 2 beats * 500000
    assert(tm:beat_to_time_us(4) == 2000000) -- 4 beats * 500000

    -- beat 4+ at BPM 180
    -- beat 5 = 2000000 + 1 * (60000000/180) = 2000000 + 333333 = 2333333
    local expected_beat5 = 2000000 + math.floor(US_PER_MINUTE / 180)
    assert(tm:beat_to_time_us(5) == expected_beat5,
        string.format("beat 5 expected %d, got %d", expected_beat5, tm:beat_to_time_us(5)))

    -- BPM at different positions
    assert(tm:get_bpm_at_beat(0) == 120)
    assert(tm:get_bpm_at_beat(3) == 120)
    assert(tm:get_bpm_at_beat(4) == 180)
    assert(tm:get_bpm_at_beat(5) == 180)

    print("  bpm_change: OK")
end

local function test_stop()
    -- BPM 120, STOP at beat 2 for 1 second (1000000 μs)
    local tm = TimingMap.new(120, nil, { [2] = 1000000 })

    -- beat 0-2 normal
    assert(tm:beat_to_time_us(0) == 0)
    assert(tm:beat_to_time_us(1) == 500000)
    assert(tm:beat_to_time_us(2) == 1000000)

    -- beat 3 = time at beat 2 + STOP + 1 beat
    -- = 1000000 + 1000000 + 500000 = 2500000
    assert(tm:beat_to_time_us(3) == 2500000,
        string.format("beat 3 expected 2500000, got %d", tm:beat_to_time_us(3)))

    -- During STOP period, beat stays at 2
    assert(approx_eq(tm:time_us_to_beat(1000000), 2), "time 1000000 should be beat 2 (STOP start)")
    assert(approx_eq(tm:time_us_to_beat(1500000), 2), "time 1500000 should be beat 2 (during STOP)")
    assert(approx_eq(tm:time_us_to_beat(1999999), 2), "time 1999999 should be beat 2 (STOP end)")

    -- After STOP
    assert(approx_eq(tm:time_us_to_beat(2000000), 2), "time 2000000 should be beat 2 (just after STOP)")
    assert(approx_eq(tm:time_us_to_beat(2500000), 3), "time 2500000 should be beat 3")

    print("  stop: OK")
end

local function test_multiple_bpm_changes()
    -- BPM 120 -> 60 at beat 4 -> 240 at beat 8
    local tm = TimingMap.new(120, { [4] = 60, [8] = 240 })

    -- beat 0-4: BPM 120 (500000 μs/beat)
    assert(tm:beat_to_time_us(4) == 2000000)

    -- beat 4-8: BPM 60 (1000000 μs/beat)
    -- beat 8 = 2000000 + 4 * 1000000 = 6000000
    assert(tm:beat_to_time_us(8) == 6000000,
        string.format("beat 8 expected 6000000, got %d", tm:beat_to_time_us(8)))

    -- beat 8+: BPM 240 (250000 μs/beat)
    -- beat 9 = 6000000 + 250000 = 6250000
    assert(tm:beat_to_time_us(9) == 6250000,
        string.format("beat 9 expected 6250000, got %d", tm:beat_to_time_us(9)))

    print("  multiple_bpm_changes: OK")
end

local function test_roundtrip()
    -- Various BPM changes and stops
    local tm = TimingMap.new(150, { [4] = 200, [8] = 100 }, { [6] = 500000 })

    -- Test roundtrip at various beats
    local test_beats = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16 }
    for _, beat in ipairs(test_beats) do
        local time_us = tm:beat_to_time_us(beat)
        local recovered_beat = tm:time_us_to_beat(time_us)
        assert(approx_eq(recovered_beat, beat, 0.01),
            string.format("roundtrip failed: beat %g -> time %d -> beat %g",
                beat, time_us, recovered_beat))
    end

    print("  roundtrip: OK")
end

local function test_fractional_beats()
    local tm = TimingMap.new(120)

    -- beat 0.5 -> 250000 μs
    assert(tm:beat_to_time_us(0.5) == 250000)

    -- beat 1.25 -> 625000 μs
    assert(tm:beat_to_time_us(1.25) == 625000)

    -- Reverse
    assert(approx_eq(tm:time_us_to_beat(250000), 0.5))
    assert(approx_eq(tm:time_us_to_beat(625000), 1.25))

    print("  fractional_beats: OK")
end

print("test_timing_map:")
test_constant_bpm()
test_bpm_change()
test_stop()
test_multiple_bpm_changes()
test_roundtrip()
test_fractional_beats()
print("All TimingMap tests passed!")

return true
