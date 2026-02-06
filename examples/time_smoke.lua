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
end

app.Run(app.Desc({
    width = 400,
    height = 300,
    window_title = "sokol.time smoke test",

    init = function()
        info("init")
    end,

    frame = function()
        if not tested then
            tested = true
            smoke_test()
            app.RequestQuit()
        end
    end,

    cleanup = function()
        info("cleanup")
    end,
}))
