local app = require("sokol.app")
local log = require("sokol.log")
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

    -- Query functions (read-only, safe to call anytime after init)
    test("isvalid", function() assert(type(app.isvalid()) == "boolean") end)
    test("width", function() assert(type(app.width()) == "number") end)
    test("widthf", function() assert(type(app.widthf()) == "number") end)
    test("height", function() assert(type(app.height()) == "number") end)
    test("heightf", function() assert(type(app.heightf()) == "number") end)
    test("color_format", function() assert(type(app.color_format()) == "number") end)
    test("depth_format", function() assert(type(app.depth_format()) == "number") end)
    test("sample_count", function() assert(type(app.sample_count()) == "number") end)
    test("high_dpi", function() assert(type(app.high_dpi()) == "boolean") end)
    test("dpi_scale", function() assert(type(app.dpi_scale()) == "number") end)
    test("frame_count", function() assert(type(app.frame_count()) == "number") end)
    test("frame_duration", function() assert(type(app.frame_duration()) == "number") end)

    -- Keyboard
    test("keyboard_shown", function() assert(type(app.keyboard_shown()) == "boolean") end)
    test("show_keyboard", function() app.show_keyboard(false) end)

    -- Fullscreen
    test("is_fullscreen", function() assert(type(app.is_fullscreen()) == "boolean") end)

    -- Mouse
    test("mouse_shown", function() assert(type(app.mouse_shown()) == "boolean") end)
    test("show_mouse", function() app.show_mouse(true) end)
    test("mouse_locked", function() assert(type(app.mouse_locked()) == "boolean") end)
    test("lock_mouse", function() app.lock_mouse(false) end)
    test("get_mouse_cursor", function() assert(type(app.get_mouse_cursor()) == "number") end)
    test("set_mouse_cursor", function() app.set_mouse_cursor(app.get_mouse_cursor()) end)

    -- Window
    test("set_window_title", function() app.set_window_title("smoke test") end)

    -- Clipboard
    test("get_clipboard_string", function() app.get_clipboard_string() end)

    -- Userdata
    test("userdata", function() app.userdata() end)

    -- Struct return
    test("query_desc", function()
        local desc = app.query_desc()
        assert(type(desc) == "userdata" or type(desc) == "table")
    end)

    -- Platform-specific (may fail on some platforms, that's expected)
    test("d3d11_get_swap_chain", function() app.d3d11_get_swap_chain() end)
    test("win32_get_hwnd", function() app.win32_get_hwnd() end)

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

function M:event(ev)
    -- Exercise event struct metamethods
    if ev then
        local _ = ev.type
        local _ = ev.mouse_x
        for k, v in pairs(ev) do end
    end
end

return M
