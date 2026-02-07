--- Tests for JudgeEngine module
local JudgeEngine = require("examples.rhythm.core.judge")
local const = require("examples.rhythm.const")

-- Helper: create a mock note
local function make_note(lane, time_us, note_type)
    return {
        lane = lane,
        time_us = time_us,
        beat = time_us / 500000, -- dummy beat at BPM 120
        wav_id = 1,
        judged = false,
        note_type = note_type or "normal",
    }
end

-- Test: judgment window boundaries
local function test_evaluate_windows()
    local engine = JudgeEngine.new()

    -- PGREAT: ±18ms
    assert(engine:evaluate(0) == "pgreat", "diff 0 should be PGREAT")
    assert(engine:evaluate(17999) == "pgreat", "diff 17999 should be PGREAT")
    assert(engine:evaluate(-17999) == "pgreat", "diff -17999 should be PGREAT")

    -- GREAT: ±40ms
    assert(engine:evaluate(18001) == "great", "diff 18001 should be GREAT")
    assert(engine:evaluate(39999) == "great", "diff 39999 should be GREAT")
    assert(engine:evaluate(-39999) == "great", "diff -39999 should be GREAT")

    -- GOOD: ±100ms
    assert(engine:evaluate(40001) == "good", "diff 40001 should be GOOD")
    assert(engine:evaluate(99999) == "good", "diff 99999 should be GOOD")
    assert(engine:evaluate(-99999) == "good", "diff -99999 should be GOOD")

    -- BAD: ±200ms
    assert(engine:evaluate(100001) == "bad", "diff 100001 should be BAD")
    assert(engine:evaluate(199999) == "bad", "diff 199999 should be BAD")
    assert(engine:evaluate(-199999) == "bad", "diff -199999 should be BAD")

    -- Outside all windows (200001+)
    assert(engine:evaluate(200001) == nil, "diff 200001 should be nil")
    assert(engine:evaluate(-200001) == nil, "diff -200001 should be nil")

    print("  evaluate_windows: OK")
end

-- Test: FAST/SLOW detection
local function test_fast_slow()
    local engine = JudgeEngine.new()

    -- Negative diff = pressed before note time = FAST
    local result, timing = engine:evaluate_with_timing(-50000)
    assert(result == "good", "result should be GOOD")
    assert(timing == "fast", "negative diff should be FAST")

    -- Positive diff = pressed after note time = SLOW
    result, timing = engine:evaluate_with_timing(50000)
    assert(result == "good", "result should be GOOD")
    assert(timing == "slow", "positive diff should be SLOW")

    -- Zero = exact timing
    result, timing = engine:evaluate_with_timing(0)
    assert(result == "pgreat", "result should be PGREAT")
    assert(timing == nil, "zero diff should have no fast/slow")

    print("  fast_slow: OK")
end

-- Test: candidate selection - nearest note
local function test_find_candidate()
    local notes = {
        make_note(1, 1000000, "normal"), -- beat ~2
        make_note(1, 2000000, "normal"), -- beat ~4
        make_note(1, 3000000, "normal"), -- beat ~6
        make_note(2, 1500000, "normal"), -- different lane
    }

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- Find note in lane 1 at time 1050000 (50ms after first note)
    local note, diff = engine:find_candidate(1, 1050000)
    assert(note == notes[1], "should find first note")
    assert(diff == 50000, "diff should be 50000")

    -- Find note in lane 1 at time 1900000 (100ms before second note)
    note, diff = engine:find_candidate(1, 1900000)
    assert(note == notes[2], "should find second note")
    assert(diff == -100000, "diff should be -100000")

    -- Find note in lane 2
    note, diff = engine:find_candidate(2, 1500000)
    assert(note == notes[4], "should find lane 2 note")
    assert(diff == 0, "diff should be 0")

    -- No note in lane 3
    note, diff = engine:find_candidate(3, 1000000)
    assert(note == nil, "should find nothing in lane 3")
    assert(diff == nil, "diff should be nil")

    print("  find_candidate: OK")
end

-- Test: candidate selection skips judged notes
local function test_skip_judged_notes()
    local notes = {
        make_note(1, 1000000, "normal"),
        make_note(1, 1100000, "normal"), -- 100ms later, within BAD window
    }
    notes[1].judged = true -- first note already judged

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- Search at time 1000000, first note is judged, should find second
    local note, diff = engine:find_candidate(1, 1000000)
    assert(note == notes[2], "should skip judged note and find second")
    assert(diff == -100000, "diff should be -100000")

    print("  skip_judged_notes: OK")
end

-- Test: key press processing
local function test_on_key_press()
    local notes = {
        make_note(1, 1000000, "normal"),
        make_note(1, 2000000, "normal"),
    }

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- Press at exact timing
    local result = engine:on_key_press(1, 1000000)
    assert(result ~= nil, "should have result")
    assert(result.judgment == "pgreat", "judgment should be PGREAT")
    assert(result.note == notes[1], "note should be first")
    assert(notes[1].judged == true, "note should be marked judged")

    -- Stats should be updated
    assert(engine.stats.pgreat == 1, "stats.pgreat should be 1")

    print("  on_key_press: OK")
end

-- Test: empty press (空押し) detection
local function test_empty_press()
    local notes = {
        make_note(1, 1000000, "normal"), -- far away note
    }

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- Press lane 1 at time 0 (1 second before note - outside window)
    local result = engine:on_key_press(1, 0)
    assert(result ~= nil, "should have result")
    assert(result.judgment == "empty_poor", "judgment should be empty_poor")
    assert(result.note == nil, "no note hit")
    assert(engine.stats.empty_poor == 1, "stats.empty_poor should be 1")

    -- Press lane with no notes
    result = engine:on_key_press(2, 500000)
    assert(result.judgment == "empty_poor", "judgment should be empty_poor for empty lane")

    print("  empty_press: OK")
end

-- Test: miss detection
local function test_process_misses()
    local notes = {
        make_note(1, 1000000, "normal"),
        make_note(1, 2000000, "normal"),
        make_note(1, 5000000, "normal"), -- far future note
    }

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- At time 1300000, first note is past BAD window (200ms)
    local misses = engine:process_misses(1300000)
    assert(#misses == 1, "should have 1 miss")
    assert(misses[1] == notes[1], "first note should be missed")
    assert(notes[1].judged == true, "missed note should be judged")
    assert(engine.stats.miss == 1, "stats.miss should be 1")

    -- Second note not yet missed
    assert(notes[2].judged == false, "second note not judged yet")

    print("  process_misses: OK")
end

-- Test: statistics accumulation
local function test_stats()
    -- Notes spaced far apart so each press only has one candidate within window
    local notes = {
        make_note(1, 1000000, "normal"),  -- 1s
        make_note(1, 2000000, "normal"),  -- 2s
        make_note(1, 3000000, "normal"),  -- 3s
        make_note(1, 4000000, "normal"),  -- 4s
    }

    local engine = JudgeEngine.new()
    engine:load_notes(notes)

    -- Hit notes with various timings
    -- diff = press_time - note_time
    -- negative diff = FAST (pressed before note), positive diff = SLOW (pressed after note)

    -- Before each press, process misses to clear past notes
    engine:process_misses(1000000)
    engine:on_key_press(1, 1000000) -- PGREAT (diff=0, no fast/slow)

    engine:process_misses(1970000)
    engine:on_key_press(1, 1970000) -- GREAT (diff=-30000, FAST - pressed 30ms before note2@2000000)

    engine:process_misses(3080000)
    engine:on_key_press(1, 3080000) -- GOOD (diff=80000, SLOW - pressed 80ms after note3@3000000)

    engine:process_misses(4200000)
    engine:on_key_press(1, 4200000) -- BAD (diff=200000, SLOW - pressed 200ms after note4@4000000)

    assert(engine.stats.pgreat == 1, "pgreat count")
    assert(engine.stats.great == 1, "great count")
    assert(engine.stats.good == 1, "good count")
    assert(engine.stats.bad == 1, "bad count")
    assert(engine.stats.fast == 1, "fast count (note 2 pressed early)")
    assert(engine.stats.slow == 2, "slow count (notes 3,4 pressed late)")

    print("  stats: OK")
end

-- Test: #RANK window multiplier
local function test_rank_multiplier()
    -- VERY HARD (RANK 0) = 0.5x windows
    local engine = JudgeEngine.new(0)

    -- PGREAT window is now ±9ms
    assert(engine:evaluate(9000) == "pgreat", "9ms should be PGREAT with RANK 0")
    assert(engine:evaluate(10000) == "great", "10ms should be GREAT with RANK 0")

    -- EASY (RANK 3) = 1.25x windows
    engine = JudgeEngine.new(3)

    -- PGREAT window is now ±22.5ms
    assert(engine:evaluate(22000) == "pgreat", "22ms should be PGREAT with RANK 3")
    assert(engine:evaluate(23000) == "great", "23ms should be GREAT with RANK 3")

    print("  rank_multiplier: OK")
end

-- Run all tests
print("test_judge:")
test_evaluate_windows()
test_fast_slow()
test_find_candidate()
test_skip_judged_notes()
test_on_key_press()
test_empty_press()
test_process_misses()
test_stats()
test_rank_multiplier()
print("All JudgeEngine tests passed!")

return true
