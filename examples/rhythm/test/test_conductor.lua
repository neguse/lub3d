--- Tests for Conductor module
local TimingMap = require("examples.rhythm.core.timing_map")
local Conductor = require("examples.rhythm.core.conductor")

local function approx_eq(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) < eps
end

local function test_basic_playback()
    local tm = TimingMap.new(120) -- 500000 μs/beat
    local conductor = Conductor.new(tm)

    -- Start at real_time 1000000 (1 second)
    conductor:start(1000000)
    assert(conductor:is_playing())
    assert(conductor:get_chart_time_us() == 0)
    assert(approx_eq(conductor:get_current_beat(), 0))

    -- After 500ms (real_time 1500000)
    conductor:update(1500000)
    assert(conductor:get_chart_time_us() == 500000)
    assert(approx_eq(conductor:get_current_beat(), 1), "should be beat 1")

    -- After 1 second (real_time 2000000)
    conductor:update(2000000)
    assert(conductor:get_chart_time_us() == 1000000)
    assert(approx_eq(conductor:get_current_beat(), 2), "should be beat 2")

    print("  basic_playback: OK")
end

local function test_start_from_position()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm)

    -- Start at chart time 1000000 (beat 2)
    conductor:start(5000000, 1000000)
    assert(conductor:get_chart_time_us() == 1000000)
    assert(approx_eq(conductor:get_current_beat(), 2))

    -- After 500ms
    conductor:update(5500000)
    assert(conductor:get_chart_time_us() == 1500000)
    assert(approx_eq(conductor:get_current_beat(), 3))

    print("  start_from_position: OK")
end

local function test_pause_resume()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm)

    conductor:start(0)
    conductor:update(500000)
    assert(conductor:get_chart_time_us() == 500000)

    -- Pause
    conductor:pause()
    assert(not conductor:is_playing())

    -- Time passes but position doesn't change
    conductor:update(1000000)
    assert(conductor:get_chart_time_us() == 500000, "should stay at paused position")

    -- Resume at new real time
    conductor:resume(2000000)
    assert(conductor:is_playing())

    -- After 500ms from resume
    conductor:update(2500000)
    assert(conductor:get_chart_time_us() == 1000000, "should be 500ms after pause position")

    print("  pause_resume: OK")
end

local function test_seek()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm)

    conductor:start(0)
    conductor:update(1000000)

    -- Seek to chart time 2000000
    conductor:seek(1000000, 2000000)
    assert(conductor:get_chart_time_us() == 2000000)
    assert(approx_eq(conductor:get_current_beat(), 4))

    -- Continue playback
    conductor:update(1500000)
    assert(conductor:get_chart_time_us() == 2500000)

    print("  seek: OK")
end

local function test_seek_beat()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm)

    conductor:start(0)

    -- Seek to beat 8
    conductor:seek_beat(1000000, 8)
    assert(approx_eq(conductor:get_current_beat(), 8))
    assert(conductor:get_chart_time_us() == 4000000) -- 8 beats * 500000

    print("  seek_beat: OK")
end

local function test_bpm_change()
    -- BPM 120 -> 240 at beat 4
    local tm = TimingMap.new(120, { [4] = 240 })
    local conductor = Conductor.new(tm)

    conductor:start(0)

    -- At beat 0, BPM is 120
    assert(conductor:get_current_bpm() == 120)

    -- Move to beat 4 (2000000 μs)
    conductor:update(2000000)
    assert(approx_eq(conductor:get_current_beat(), 4))
    assert(conductor:get_current_bpm() == 240)

    -- At BPM 240, 1 beat = 250000 μs
    -- beat 5 should be at 2250000
    conductor:update(2250000)
    assert(approx_eq(conductor:get_current_beat(), 5))

    print("  bpm_change: OK")
end

local function test_audio_offset()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm, 50000) -- 50ms offset

    conductor:start(0)
    conductor:update(500000)

    assert(conductor:get_chart_time_us() == 500000)
    assert(conductor:get_audio_time_us() == 450000, "audio time should be offset")

    print("  audio_offset: OK")
end

local function test_negative_time_clamp()
    local tm = TimingMap.new(120)
    local conductor = Conductor.new(tm)

    -- Start at real_time 1000000
    conductor:start(1000000)

    -- Query before start (real_time 500000)
    conductor:update(500000)
    assert(conductor:get_chart_time_us() == 0, "should clamp to 0")
    assert(approx_eq(conductor:get_current_beat(), 0))

    print("  negative_time_clamp: OK")
end

print("test_conductor:")
test_basic_playback()
test_start_from_position()
test_pause_resume()
test_seek()
test_seek_beat()
test_bpm_change()
test_audio_offset()
test_negative_time_clamp()
print("All Conductor tests passed!")

return true
