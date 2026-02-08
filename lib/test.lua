-- Pure Lua test runner
local log = require("lib.log")

local M = {}

--- Run a named test suite.
--- Each entry in tests is {name = function}.
--- Logs OK/FAIL per test; calls error() if any test fails.
---@param suite string
---@param tests table<string, function>
function M.run(suite, tests)
    local ok_count, fail_count = 0, 0
    local results = {}
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        local line = (ok and "OK" or "FAIL") .. "  " .. name
        if not ok then line = line .. "  " .. tostring(err) end
        results[#results + 1] = line
        if ok then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    end
    log.info("=== " .. suite .. " ===")
    for _, r in ipairs(results) do
        log.info(r)
    end
    log.info(string.format("=== %d OK, %d FAIL ===", ok_count, fail_count))
    if fail_count > 0 then
        error(string.format("%s: %d tests failed", suite, fail_count))
    end
end

return M
