-- Smoke test: exercise all sokol.time bindings
local app = require("sokol.app")
local log = require("sokol.log")
local time = require("sokol.time")
local tested = false

local function info(msg)
    log.func("lua", 3, 0, msg, 0, "", nil)
end

local function smoke_test()
    local results = {}
    local function test(name, fn)
        local ok, err = pcall(fn)
        results[#results + 1] = (ok and "OK" or "FAIL") .. "  " .. name
        if not ok then results[#results] = results[#results] .. "  " .. tostring(err) end
    end

    test("setup", function() time.setup() end)
    test("now", function() assert(type(time.now()) == "number") end)
    test("diff", function()
        local t1 = time.now()
        local t2 = time.now()
        assert(type(time.diff(t2, t1)) == "number")
    end)
    test("since", function()
        local t = time.now()
        assert(type(time.since(t)) == "number")
    end)
    test("round_to_common_refresh_rate", function()
        local t = time.now()
        assert(type(time.round_to_common_refresh_rate(t)) == "number")
    end)
    test("sec", function()
        local t = time.now()
        assert(type(time.sec(t)) == "number")
    end)
    test("ms", function()
        local t = time.now()
        assert(type(time.ms(t)) == "number")
    end)
    test("us", function()
        local t = time.now()
        assert(type(time.us(t)) == "number")
    end)
    test("ns", function()
        local t = time.now()
        assert(type(time.ns(t)) == "number")
    end)

    info("=== sokol.time smoke test ===")
    local ok_count, fail_count = 0, 0
    for _, r in ipairs(results) do
        info(r)
        if r:sub(1, 2) == "OK" then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    end
    info(string.format("=== %d OK, %d FAIL ===", ok_count, fail_count))
    if fail_count > 0 then error(string.format("%d tests failed", fail_count)) end
end

local M = {}
M.width = 400
M.height = 300
M.window_title = "sokol.time smoke test"

function M:init()
    info("init")
end

function M:frame()
    if not tested then
        tested = true
        smoke_test()
        app.request_quit()
    end
end

function M:cleanup()
    info("cleanup")
end

return M
