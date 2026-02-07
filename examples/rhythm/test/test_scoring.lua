--- Tests for ScoringEngine module
local ScoringEngine = require("examples.rhythm.core.scoring")

-- Test: EX score calculation
local function test_ex_score()
    local engine = ScoringEngine.new(100) -- 100 notes

    -- PGREAT = 2 points
    engine:on_judgment("pgreat")
    assert(engine.ex_score == 2, "PGREAT should add 2 to EX score")

    -- GREAT = 1 point
    engine:on_judgment("great")
    assert(engine.ex_score == 3, "GREAT should add 1 to EX score")

    -- GOOD = 0 points
    engine:on_judgment("good")
    assert(engine.ex_score == 3, "GOOD should add 0 to EX score")

    -- BAD = 0 points
    engine:on_judgment("bad")
    assert(engine.ex_score == 3, "BAD should add 0 to EX score")

    -- MISS = 0 points
    engine:on_judgment("miss")
    assert(engine.ex_score == 3, "MISS should add 0 to EX score")

    -- empty_poor = 0 points
    engine:on_judgment("empty_poor")
    assert(engine.ex_score == 3, "empty_poor should add 0 to EX score")

    print("  ex_score: OK")
end

-- Test: max EX score calculation
local function test_max_ex_score()
    local engine = ScoringEngine.new(100)
    assert(engine:get_max_ex_score() == 200, "max EX score should be notes * 2")

    engine = ScoringEngine.new(50)
    assert(engine:get_max_ex_score() == 100, "max EX score should be notes * 2")

    print("  max_ex_score: OK")
end

-- Test: DJ LEVEL calculation
local function test_dj_level()
    -- DJ LEVEL thresholds (of max EX score):
    -- AAA: 88.89%+
    -- AA:  77.78%+
    -- A:   66.67%+
    -- B:   55.56%+
    -- C:   44.44%+
    -- D:   33.33%+
    -- E:   22.22%+
    -- F:   < 22.22%

    local engine = ScoringEngine.new(100) -- max = 200

    -- 0% = F
    assert(engine:get_dj_level() == "F", "0% should be F")

    -- 22% = F (< 22.22%)
    engine.ex_score = 44
    assert(engine:get_dj_level() == "F", "22% should be F")

    -- 23% = E
    engine.ex_score = 46
    assert(engine:get_dj_level() == "E", "23% should be E")

    -- 34% = D
    engine.ex_score = 68
    assert(engine:get_dj_level() == "D", "34% should be D")

    -- 45% = C
    engine.ex_score = 90
    assert(engine:get_dj_level() == "C", "45% should be C")

    -- 56% = B
    engine.ex_score = 112
    assert(engine:get_dj_level() == "B", "56% should be B")

    -- 67% = A
    engine.ex_score = 134
    assert(engine:get_dj_level() == "A", "67% should be A")

    -- 78% = AA
    engine.ex_score = 156
    assert(engine:get_dj_level() == "AA", "78% should be AA")

    -- 89% = AAA
    engine.ex_score = 178
    assert(engine:get_dj_level() == "AAA", "89% should be AAA")

    -- 100% = AAA
    engine.ex_score = 200
    assert(engine:get_dj_level() == "AAA", "100% should be AAA")

    print("  dj_level: OK")
end

-- Test: score rate calculation
local function test_score_rate()
    local engine = ScoringEngine.new(100) -- max = 200

    engine.ex_score = 100
    local rate = engine:get_score_rate()
    assert(math.abs(rate - 50.0) < 0.01, "50% rate expected")

    engine.ex_score = 178
    rate = engine:get_score_rate()
    assert(math.abs(rate - 89.0) < 0.01, "89% rate expected")

    print("  score_rate: OK")
end

-- Test: combo tracking
local function test_combo()
    local engine = ScoringEngine.new(100)

    -- PGREAT/GREAT/GOOD continue combo
    engine:on_judgment("pgreat")
    assert(engine.combo == 1, "PGREAT should increment combo")

    engine:on_judgment("great")
    assert(engine.combo == 2, "GREAT should increment combo")

    engine:on_judgment("good")
    assert(engine.combo == 3, "GOOD should increment combo")

    -- BAD/MISS/empty_poor break combo
    engine:on_judgment("bad")
    assert(engine.combo == 0, "BAD should break combo")

    engine:on_judgment("pgreat")
    engine:on_judgment("miss")
    assert(engine.combo == 0, "MISS should break combo")

    engine:on_judgment("pgreat")
    engine:on_judgment("empty_poor")
    assert(engine.combo == 0, "empty_poor should break combo")

    print("  combo: OK")
end

-- Test: max combo tracking
local function test_max_combo()
    local engine = ScoringEngine.new(100)

    engine:on_judgment("pgreat")
    engine:on_judgment("pgreat")
    engine:on_judgment("pgreat")
    assert(engine.max_combo == 3, "max combo should be 3")

    engine:on_judgment("bad") -- break combo
    assert(engine.max_combo == 3, "max combo should still be 3 after break")

    engine:on_judgment("pgreat")
    engine:on_judgment("pgreat")
    assert(engine.max_combo == 3, "max combo should still be 3")

    engine:on_judgment("pgreat")
    engine:on_judgment("pgreat")
    assert(engine.max_combo == 4, "max combo should be 4")

    print("  max_combo: OK")
end

-- Run all tests
print("test_scoring:")
test_ex_score()
test_max_ex_score()
test_dj_level()
test_score_rate()
test_combo()
test_max_combo()
print("All ScoringEngine tests passed!")

return true
