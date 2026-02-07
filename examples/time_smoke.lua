-- Smoke test: exercise all sokol.time bindings
local app = require("sokol.app")
local log = require("sokol.log")
local time = require("sokol.time")
local tested = false

local function info(msg)
    log.Func("lua", 3, 0, msg, 0, "", nil)
end

local function smoke_test()
    local results = {}
    local function test(name, fn)
        local ok, err = pcall(fn)
        results[#results + 1] = (ok and "OK" or "FAIL") .. "  " .. name
        if not ok then results[#results] = results[#results] .. "  " .. tostring(err) end
    end

    test("Setup", function() time.Setup() end)
    test("Now", function() assert(type(time.Now()) == "number") end)
    test("Diff", function()
        local t1 = time.Now()
        local t2 = time.Now()
        assert(type(time.Diff(t2, t1)) == "number")
    end)
    test("Since", function()
        local t = time.Now()
        assert(type(time.Since(t)) == "number")
    end)
    test("RoundToCommonRefreshRate", function()
        local t = time.Now()
        assert(type(time.RoundToCommonRefreshRate(t)) == "number")
    end)
    test("Sec", function()
        local t = time.Now()
        assert(type(time.Sec(t)) == "number")
    end)
    test("Ms", function()
        local t = time.Now()
        assert(type(time.Ms(t)) == "number")
    end)
    test("Us", function()
        local t = time.Now()
        assert(type(time.Us(t)) == "number")
    end)
    test("Ns", function()
        local t = time.Now()
        assert(type(time.Ns(t)) == "number")
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

function M.init()
    info("init")
end

function M.frame()
    if not tested then
        tested = true
        smoke_test()
        app.RequestQuit()
    end
end

function M.cleanup()
    info("cleanup")
end

return M
