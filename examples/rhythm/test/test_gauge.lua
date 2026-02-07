--- Tests for GaugeEngine module
local GaugeEngine = require("examples.rhythm.core.gauge")

-- Helper: approximately equal for floating point
local function approx_eq(a, b, eps)
    eps = eps or 0.01
    return math.abs(a - b) < eps
end

-- Test: GROOVE gauge initial state
local function test_groove_initial()
    local engine = GaugeEngine.new("groove", 100, 200) -- 100 notes, TOTAL=200

    assert(engine.value == 20, "GROOVE should start at 20%")
    assert(engine.gauge_type == "groove", "type should be groove")

    print("  groove_initial: OK")
end

-- Test: GROOVE gauge increase on good judgments
local function test_groove_increase()
    -- TOTAL = 200, notes = 100
    -- increase per PGREAT = 200/100 = 2%
    local engine = GaugeEngine.new("groove", 100, 200)

    -- PGREAT: +TOTAL/notes = +2%
    engine:on_judgment("pgreat")
    assert(approx_eq(engine.value, 22), "PGREAT should add 2%")

    -- GREAT: +TOTAL/notes * 0.8 = +1.6%
    engine:on_judgment("great")
    assert(approx_eq(engine.value, 23.6), "GREAT should add 1.6%")

    -- GOOD: +TOTAL/notes * 0.4 = +0.8%
    engine:on_judgment("good")
    assert(approx_eq(engine.value, 24.4), "GOOD should add 0.8%")

    print("  groove_increase: OK")
end

-- Test: GROOVE gauge decrease on bad judgments
local function test_groove_decrease()
    local engine = GaugeEngine.new("groove", 100, 200)
    engine.value = 50 -- start at 50%

    -- BAD: -2%
    engine:on_judgment("bad")
    assert(approx_eq(engine.value, 48), "BAD should subtract 2%")

    -- POOR (empty): -6%
    engine:on_judgment("empty_poor")
    assert(approx_eq(engine.value, 42), "empty_poor should subtract 6%")

    -- MISS: -6%
    engine:on_judgment("miss")
    assert(approx_eq(engine.value, 36), "MISS should subtract 6%")

    print("  groove_decrease: OK")
end

-- Test: GROOVE gauge floor at 2%
local function test_groove_floor()
    local engine = GaugeEngine.new("groove", 100, 200)
    engine.value = 5

    -- Multiple misses should not go below 2%
    engine:on_judgment("miss")
    engine:on_judgment("miss")
    engine:on_judgment("miss")
    assert(engine.value == 2, "GROOVE should not go below 2%")

    print("  groove_floor: OK")
end

-- Test: GROOVE gauge cap at 100%
local function test_groove_cap()
    local engine = GaugeEngine.new("groove", 100, 200)
    engine.value = 99

    -- Multiple PGREATs should not exceed 100%
    engine:on_judgment("pgreat")
    engine:on_judgment("pgreat")
    assert(engine.value == 100, "GROOVE should not exceed 100%")

    print("  groove_cap: OK")
end

-- Test: GROOVE clear condition (80%+)
local function test_groove_clear()
    local engine = GaugeEngine.new("groove", 100, 200)

    engine.value = 79
    assert(engine:is_cleared() == false, "79% should not be cleared")

    engine.value = 80
    assert(engine:is_cleared() == true, "80% should be cleared")

    engine.value = 100
    assert(engine:is_cleared() == true, "100% should be cleared")

    print("  groove_clear: OK")
end

-- Test: HARD gauge initial state
local function test_hard_initial()
    local engine = GaugeEngine.new("hard", 100, 200)

    assert(engine.value == 100, "HARD should start at 100%")
    assert(engine.gauge_type == "hard", "type should be hard")

    print("  hard_initial: OK")
end

-- Test: HARD gauge decrease (harsher penalties)
local function test_hard_decrease()
    local engine = GaugeEngine.new("hard", 100, 200)

    -- BAD: -4%
    engine:on_judgment("bad")
    assert(approx_eq(engine.value, 96), "BAD should subtract 4%")

    -- MISS: -10%
    engine:on_judgment("miss")
    assert(approx_eq(engine.value, 86), "MISS should subtract 10%")

    print("  hard_decrease: OK")
end

-- Test: HARD gauge floor at 0% (fail)
local function test_hard_fail()
    local engine = GaugeEngine.new("hard", 100, 200)
    engine.value = 5

    engine:on_judgment("miss")
    assert(engine.value == 0, "HARD should go to 0%")
    assert(engine:is_failed() == true, "should be failed at 0%")

    print("  hard_fail: OK")
end

-- Test: HARD clear condition (survive = any value > 0)
local function test_hard_clear()
    local engine = GaugeEngine.new("hard", 100, 200)

    engine.value = 1
    assert(engine:is_cleared() == true, "1% should be cleared for HARD")

    engine.value = 0
    assert(engine:is_cleared() == false, "0% should not be cleared for HARD")

    print("  hard_clear: OK")
end

-- Test: default TOTAL calculation
local function test_default_total()
    -- When TOTAL is not specified, use default formula: 7.605 * notes / (0.01 * notes + 6.5)
    local engine = GaugeEngine.new("groove", 100)

    -- For 100 notes: 7.605 * 100 / (0.01 * 100 + 6.5) = 760.5 / 7.5 = 101.4
    local expected_total = 7.605 * 100 / (0.01 * 100 + 6.5)
    assert(approx_eq(engine.total, expected_total, 0.1), "default TOTAL calculation")

    print("  default_total: OK")
end

-- Run all tests
print("test_gauge:")
test_groove_initial()
test_groove_increase()
test_groove_decrease()
test_groove_floor()
test_groove_cap()
test_groove_clear()
test_hard_initial()
test_hard_decrease()
test_hard_fail()
test_hard_clear()
test_default_total()
print("All GaugeEngine tests passed!")

return true
