-- lib/headless_app.lua
-- sokol.app compatible Lua module for headless testing
local M = {}

-- Configuration (can be set from C via _headless_frames global)
M._frames = _headless_frames or 10
M._width = 640
M._height = 480
M._sample_count = 1
M._frame_count = 0

-- Callbacks stored from Desc
local callbacks = {}

-- app.Desc() compatible constructor
function M.Desc(desc)
    callbacks = desc or {}
    if desc.width then M._width = desc.width end
    if desc.height then M._height = desc.height end
    if desc.sample_count then M._sample_count = desc.sample_count end
    return desc
end

-- app.run() compatible function
function M.run(desc)
    local stm = require("sokol.time")
    stm.setup()

    -- init_cb
    if callbacks.init_cb then callbacks.init_cb() end

    -- frame loop
    for i = 1, M._frames do
        M._frame_count = i
        if callbacks.frame_cb then callbacks.frame_cb() end
    end

    -- cleanup_cb
    if callbacks.cleanup_cb then callbacks.cleanup_cb() end
end

-- app.width() / app.height() compatible functions
function M.width() return M._width end
function M.height() return M._height end
function M.widthf() return M._width end
function M.heightf() return M._height end
function M.sample_count() return M._sample_count end
function M.frame_duration() return 1/60 end
function M.frame_count() return M._frame_count end
function M.dpi_scale() return 1.0 end
function M.high_dpi() return false end
function M.isvalid() return true end
function M.is_fullscreen() return false end

-- PixelFormat enum (same values as sokol.gfx)
M.PixelFormat = {
    DEFAULT = 0,
    NONE = 1,
    RGBA8 = 2,
    SRGB8A8 = 3,
    BGRA8 = 4,
    SBGRA8 = 5,
    DEPTH = 6,
    DEPTH_STENCIL = 7,
}

function M.color_format() return M.PixelFormat.RGBA8 end
function M.depth_format() return M.PixelFormat.DEPTH_STENCIL end

-- EventType enum
M.EventType = {
    INVALID = 0,
    KEY_DOWN = 1,
    KEY_UP = 2,
    CHAR = 3,
    MOUSE_DOWN = 4,
    MOUSE_UP = 5,
    MOUSE_SCROLL = 6,
    MOUSE_MOVE = 7,
    MOUSE_ENTER = 8,
    MOUSE_LEAVE = 9,
    TOUCHES_BEGAN = 10,
    TOUCHES_MOVED = 11,
    TOUCHES_ENDED = 12,
    TOUCHES_CANCELLED = 13,
    RESIZED = 14,
    ICONIFIED = 15,
    RESTORED = 16,
    FOCUSED = 17,
    UNFOCUSED = 18,
    SUSPENDED = 19,
    RESUMED = 20,
    QUIT_REQUESTED = 21,
    CLIPBOARD_PASTED = 22,
    FILES_DROPPED = 23,
    NUM = 24,
}

-- Keycode enum
M.Keycode = {
    INVALID = 0,
    SPACE = 32,
    APOSTROPHE = 39,
    COMMA = 44,
    MINUS = 45,
    PERIOD = 46,
    SLASH = 47,
    ["0"] = 48, ["1"] = 49, ["2"] = 50, ["3"] = 51, ["4"] = 52,
    ["5"] = 53, ["6"] = 54, ["7"] = 55, ["8"] = 56, ["9"] = 57,
    SEMICOLON = 59,
    EQUAL = 61,
    A = 65, B = 66, C = 67, D = 68, E = 69, F = 70, G = 71, H = 72,
    I = 73, J = 74, K = 75, L = 76, M = 77, N = 78, O = 79, P = 80,
    Q = 81, R = 82, S = 83, T = 84, U = 85, V = 86, W = 87, X = 88,
    Y = 89, Z = 90,
    LEFT_BRACKET = 91,
    BACKSLASH = 92,
    RIGHT_BRACKET = 93,
    GRAVE_ACCENT = 96,
    WORLD_1 = 161,
    WORLD_2 = 162,
    ESCAPE = 256,
    ENTER = 257,
    TAB = 258,
    BACKSPACE = 259,
    INSERT = 260,
    DELETE = 261,
    RIGHT = 262,
    LEFT = 263,
    DOWN = 264,
    UP = 265,
    PAGE_UP = 266,
    PAGE_DOWN = 267,
    HOME = 268,
    END = 269,
    CAPS_LOCK = 280,
    SCROLL_LOCK = 281,
    NUM_LOCK = 282,
    PRINT_SCREEN = 283,
    PAUSE = 284,
    F1 = 290, F2 = 291, F3 = 292, F4 = 293, F5 = 294, F6 = 295,
    F7 = 296, F8 = 297, F9 = 298, F10 = 299, F11 = 300, F12 = 301,
    F13 = 302, F14 = 303, F15 = 304, F16 = 305, F17 = 306, F18 = 307,
    F19 = 308, F20 = 309, F21 = 310, F22 = 311, F23 = 312, F24 = 313,
    F25 = 314,
    KP_0 = 320, KP_1 = 321, KP_2 = 322, KP_3 = 323, KP_4 = 324,
    KP_5 = 325, KP_6 = 326, KP_7 = 327, KP_8 = 328, KP_9 = 329,
    KP_DECIMAL = 330,
    KP_DIVIDE = 331,
    KP_MULTIPLY = 332,
    KP_SUBTRACT = 333,
    KP_ADD = 334,
    KP_ENTER = 335,
    KP_EQUAL = 336,
    LEFT_SHIFT = 340,
    LEFT_CONTROL = 341,
    LEFT_ALT = 342,
    LEFT_SUPER = 343,
    RIGHT_SHIFT = 344,
    RIGHT_CONTROL = 345,
    RIGHT_ALT = 346,
    RIGHT_SUPER = 347,
    MENU = 348,
}

-- Mousebutton enum
M.Mousebutton = {
    LEFT = 0,
    RIGHT = 1,
    MIDDLE = 2,
    INVALID = 256,
}

-- AndroidTooltype enum
M.AndroidTooltype = {
    UNKNOWN = 0,
    FINGER = 1,
    STYLUS = 2,
    MOUSE = 3,
}

-- MouseCursor enum
M.MouseCursor = {
    DEFAULT = 0,
    ARROW = 1,
    IBEAM = 2,
    CROSSHAIR = 3,
    POINTING_HAND = 4,
    RESIZE_EW = 5,
    RESIZE_NS = 6,
    RESIZE_NWSE = 7,
    RESIZE_NESW = 8,
    RESIZE_ALL = 9,
    NOT_ALLOWED = 10,
    NUM = 27,
}

-- Struct constructors (just return the table)
function M.Touchpoint(t) return t or {} end
function M.Event(t) return t or {} end
function M.Range(t) return t or {} end
function M.ImageDesc(t) return t or {} end
function M.IconDesc(t) return t or {} end
function M.Allocator(t) return t or {} end
function M.EnvironmentDefaults(t) return t or {} end
function M.MetalEnvironment(t) return t or {} end
function M.D3d11Environment(t) return t or {} end
function M.WgpuEnvironment(t) return t or {} end
function M.VulkanEnvironment(t) return t or {} end
function M.Environment(t) return t or {} end
function M.MetalSwapchain(t) return t or {} end
function M.D3d11Swapchain(t) return t or {} end
function M.WgpuSwapchain(t) return t or {} end
function M.VulkanSwapchain(t) return t or {} end
function M.GlSwapchain(t) return t or {} end
function M.Swapchain(t) return t or {} end
function M.Logger(t) return t or {} end
function M.GlDesc(t) return t or {} end
function M.Win32Desc(t) return t or {} end
function M.Html5Desc(t) return t or {} end
function M.IosDesc(t) return t or {} end
function M.Html5FetchResponse(t) return t or {} end
function M.Html5FetchRequest(t) return t or {} end

-- Stub functions (no-op in headless mode)
function M.quit() end
function M.request_quit() end
function M.cancel_quit() end
function M.consume_event() end
function M.show_mouse(show) end
function M.lock_mouse(lock) end
function M.mouse_shown() return true end
function M.mouse_locked() return false end
function M.set_mouse_cursor(cursor) end
function M.get_mouse_cursor() return M.MouseCursor.DEFAULT end
function M.bind_mouse_cursor_image(cursor, desc) return cursor end
function M.unbind_mouse_cursor_image(cursor) end
function M.show_keyboard(show) end
function M.keyboard_shown() return false end
function M.toggle_fullscreen() end
function M.userdata() return nil end
function M.query_desc() return callbacks end
function M.set_clipboard_string(str) end
function M.get_clipboard_string() return "" end
function M.set_window_title(str) end
function M.set_icon(icon_desc) end
function M.get_num_dropped_files() return 0 end
function M.get_dropped_file_path(index) return "" end

-- Environment/Swapchain functions (return dummy values)
function M.get_environment()
    return {
        defaults = {
            color_format = M.PixelFormat.RGBA8,
            depth_format = M.PixelFormat.DEPTH_STENCIL,
            sample_count = M._sample_count,
        },
    }
end

function M.get_swapchain()
    return {
        width = M._width,
        height = M._height,
        sample_count = M._sample_count,
        color_format = M.PixelFormat.RGBA8,
        depth_format = M.PixelFormat.DEPTH_STENCIL,
    }
end

-- Platform-specific stubs (return nil)
function M.egl_get_display() return nil end
function M.egl_get_context() return nil end
function M.html5_ask_leave_site(ask) end
function M.html5_get_dropped_file_size(index) return 0 end
function M.html5_fetch_dropped_file(request) end
function M.macos_get_window() return nil end
function M.ios_get_window() return nil end
function M.d3d11_get_swap_chain() return nil end
function M.win32_get_hwnd() return nil end
function M.gl_get_major_version() return 0 end
function M.gl_get_minor_version() return 0 end
function M.gl_is_gles() return false end
function M.x11_get_window() return nil end
function M.x11_get_display() return nil end
function M.android_get_native_activity() return nil end

return M
