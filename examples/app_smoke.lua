-- Smoke test: exercise all sokol.app bindings
local app = require("sokol.app")
local log = require("sokol.log")
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

    -- Query functions (read-only, safe to call anytime after init)
    test("Isvalid", function() assert(type(app.Isvalid()) == "boolean") end)
    test("Width", function() assert(type(app.Width()) == "number") end)
    test("Widthf", function() assert(type(app.Widthf()) == "number") end)
    test("Height", function() assert(type(app.Height()) == "number") end)
    test("Heightf", function() assert(type(app.Heightf()) == "number") end)
    test("ColorFormat", function() assert(type(app.ColorFormat()) == "number") end)
    test("DepthFormat", function() assert(type(app.DepthFormat()) == "number") end)
    test("SampleCount", function() assert(type(app.SampleCount()) == "number") end)
    test("HighDpi", function() assert(type(app.HighDpi()) == "boolean") end)
    test("DpiScale", function() assert(type(app.DpiScale()) == "number") end)
    test("FrameCount", function() assert(type(app.FrameCount()) == "number") end)
    test("FrameDuration", function() assert(type(app.FrameDuration()) == "number") end)

    -- Keyboard
    test("KeyboardShown", function() assert(type(app.KeyboardShown()) == "boolean") end)
    test("ShowKeyboard", function() app.ShowKeyboard(false) end)

    -- Fullscreen
    test("IsFullscreen", function() assert(type(app.IsFullscreen()) == "boolean") end)

    -- Mouse
    test("MouseShown", function() assert(type(app.MouseShown()) == "boolean") end)
    test("ShowMouse", function() app.ShowMouse(true) end)
    test("MouseLocked", function() assert(type(app.MouseLocked()) == "boolean") end)
    test("LockMouse", function() app.LockMouse(false) end)
    test("GetMouseCursor", function() assert(type(app.GetMouseCursor()) == "number") end)
    test("SetMouseCursor", function() app.SetMouseCursor(app.GetMouseCursor()) end)

    -- Window
    test("SetWindowTitle", function() app.SetWindowTitle("smoke test") end)

    -- Clipboard
    test("GetClipboardString", function() app.GetClipboardString() end)

    -- Userdata
    test("Userdata", function() app.Userdata() end)

    -- Struct return
    test("QueryDesc", function()
        local desc = app.QueryDesc()
        assert(type(desc) == "userdata" or type(desc) == "table")
    end)

    -- Platform-specific (may fail on some platforms, that's expected)
    test("D3d11GetSwapChain", function() app.D3d11GetSwapChain() end)
    test("Win32GetHwnd", function() app.Win32GetHwnd() end)

    -- Print results via sokol.log
    info("=== sokol.app smoke test ===")
    local ok_count, fail_count = 0, 0
    for _, r in ipairs(results) do
        info(r)
        if r:sub(1, 2) == "OK" then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    end
    info(string.format("=== %d OK, %d FAIL ===", ok_count, fail_count))
    if fail_count > 0 then error(string.format("%d tests failed", fail_count)) end
end

local M = {}
M.width = 800
M.height = 600
M.window_title = "sokol.app smoke test"
M.enable_clipboard = true

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

function M.event(ev)
    -- Exercise event struct metamethods
    if ev then
        local _ = ev.type
        local _ = ev.mouse_x
        for k, v in pairs(ev) do end
    end
end

return M
