--- Integration tests for rhythm game
local converter = require("examples.rhythm.bms.converter")
local Conductor = require("examples.rhythm.core.conductor")
local InputHandler = require("examples.rhythm.input.handler")
local GameState = require("examples.rhythm.game.state")
local Playfield = require("examples.rhythm.game.playfield")
local const = require("examples.rhythm.const")

local function test_full_chart_load()
    local chart, err = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart, "Failed to load: " .. (err or ""))

    -- Create game components
    local conductor = Conductor.new(chart.timing_map)
    local state = GameState.new()
    local input_handler = InputHandler.new()

    state:load_chart(chart, conductor)
    local playfield = Playfield.new(state, input_handler)
    playfield:init_with_chart(chart)

    -- Verify initial state
    assert(state.current == GameState.LOADING)
    assert(#chart.notes == 8, "Expected 8 notes, got " .. #chart.notes)

    print("  full_chart_load: OK")
end

local function test_game_flow()
    local chart, _ = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart)

    local conductor = Conductor.new(chart.timing_map)
    local state = GameState.new()
    local input_handler = InputHandler.new()

    state:load_chart(chart, conductor)
    local playfield = Playfield.new(state, input_handler)
    playfield:init_with_chart(chart)

    -- Start the game
    state:start()
    assert(state:is(GameState.PLAYING))

    -- Simulate time passing (real_time = 0)
    conductor:start(0)

    -- At time 0, beat should be 0
    conductor:update(0)
    assert(math.abs(conductor:get_current_beat()) < 0.01)

    -- At time 500000 (0.5 sec), beat should be 1 (BPM 120)
    conductor:update(500000)
    assert(math.abs(conductor:get_current_beat() - 1) < 0.01)

    print("  game_flow: OK")
end

local function test_note_hit()
    local chart, _ = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart)

    local conductor = Conductor.new(chart.timing_map)
    local state = GameState.new()
    local input_handler = InputHandler.new()

    state:load_chart(chart, conductor)
    local playfield = Playfield.new(state, input_handler)
    playfield:init_with_chart(chart)

    state:start()
    conductor:start(0)

    -- Move to beat 4 (where first notes are, at 2000000 us with BPM 120)
    conductor:update(2000000)

    -- Check initial combo
    assert(state.combo == 0)

    -- Simulate key press on lane 1 (scratch) at beat 4
    input_handler:on_key(83, true, 2000000) -- S key

    -- Update playfield
    playfield:update(2000000, 4)

    -- Should have hit the note on lane 1
    local hits = 0
    for _, note in ipairs(chart.notes) do
        if note.judged and note.lane == 1 then
            hits = hits + 1
        end
    end
    assert(hits == 1, "Should hit exactly 1 note on lane 1")
    assert(state.combo == 1, "Combo should be 1")

    print("  note_hit: OK")
end

local function test_visible_notes()
    local chart, _ = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart)

    local conductor = Conductor.new(chart.timing_map)
    local state = GameState.new()

    state:load_chart(chart, conductor)

    -- Notes are at beats 4,5,6,7,8,9,10,11
    -- At beat 0, visible_beats=8 means max_beat=8, min_beat=-2
    -- Visible notes: beat 4,5,6,7,8 (5 notes)
    local visible = state:get_visible_notes(0, 8)
    assert(#visible == 5, "Expected 5 visible notes at beat 0, got " .. #visible)

    -- At beat 4, visible_beats=8 means max_beat=12, min_beat=2
    -- All 8 notes should be visible
    visible = state:get_visible_notes(4, 8)
    assert(#visible == 8, "All 8 notes should be visible at beat 4")

    -- Judge all notes
    for _, note in ipairs(chart.notes) do
        note.judged = true
    end

    visible = state:get_visible_notes(10, 8)
    assert(#visible == 0, "No notes should be visible when all judged")

    print("  visible_notes: OK")
end

local function test_input_handler()
    local input_handler = InputHandler.new()

    -- Initial state
    assert(not input_handler:is_pressed(1))

    -- Press S key (lane 1)
    input_handler:on_key(83, true, 1000)
    assert(input_handler:is_pressed(1))

    -- Consume events
    local events = input_handler:consume_events(1)
    assert(#events == 1)
    assert(events[1].pressed == true)
    assert(events[1].time_us == 1000)

    -- Events should be consumed
    events = input_handler:consume_events(1)
    assert(#events == 0)

    -- Release key
    input_handler:on_key(83, false, 2000)
    assert(not input_handler:is_pressed(1))

    print("  input_handler: OK")
end

local function test_pause_resume()
    local chart, _ = converter.load("examples/rhythm/test/fixtures/simple.bms")
    assert(chart)

    local conductor = Conductor.new(chart.timing_map)
    local state = GameState.new()

    state:load_chart(chart, conductor)
    state:start()
    conductor:start(0)

    -- Advance to beat 2
    conductor:update(1000000) -- 1 sec = beat 2 at BPM 120
    local beat_before_pause = conductor:get_current_beat()

    -- Pause
    state:pause()
    assert(state:is(GameState.PAUSED))

    -- Time passes but beat stays same
    conductor:update(2000000)
    assert(math.abs(conductor:get_current_beat() - beat_before_pause) < 0.01)

    -- Resume at new time
    state:resume(3000000)
    assert(state:is(GameState.PLAYING))

    -- After resume, beat should advance from pause position
    conductor:update(3500000)
    local expected_beat = beat_before_pause + 1 -- 0.5 sec = 1 beat
    assert(math.abs(conductor:get_current_beat() - expected_beat) < 0.01)

    print("  pause_resume: OK")
end

print("test_integration:")
test_full_chart_load()
test_game_flow()
test_note_hit()
test_visible_notes()
test_input_handler()
test_pause_resume()
print("All integration tests passed!")

return true
