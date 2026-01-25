--- Test runner for rhythm game modules
--- Usage: mane3d-test examples/rhythm/test/run_tests.lua 1

local test_modules = {
    "examples.rhythm.test.test_base36",
    "examples.rhythm.test.test_timing_map",
    "examples.rhythm.test.test_conductor",
    "examples.rhythm.test.test_encoding",
    "examples.rhythm.test.test_parser",
    "examples.rhythm.test.test_converter",
    "examples.rhythm.test.test_judge",
    "examples.rhythm.test.test_scoring",
    "examples.rhythm.test.test_gauge",
    "examples.rhythm.test.test_integration",
}

local passed = 0
local failed = 0

for _, mod_name in ipairs(test_modules) do
    print(string.format("\n=== Running %s ===", mod_name))
    local ok, err = pcall(function()
        require(mod_name)
    end)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAILED: %s", err))
    end
end

print(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    error("Some tests failed")
end

-- Required callbacks for mane3d-test
function init() end
function frame() end
function cleanup() end
