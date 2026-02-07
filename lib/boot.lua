-- boot.lua
-- Module bootloader: sets up hotreload, requires the entry script, and launches app.Run()
--
-- Two modes:
--   _lub3d_script  (string)  → require the module by name (hotreload works)
--   _lub3d_module  (table)   → use directly (playground, no hotreload)

---@type string?
local _lub3d_script = _lub3d_script ---@diagnostic disable-line: undefined-global
---@type table?
local _lub3d_module = _lub3d_module ---@diagnostic disable-line: undefined-global

local app = require("sokol.app")

-- Set up hotreload BEFORE requiring the entry script,
-- so the require hook watches all dependencies automatically.
-- Skip in playground mode (_lub3d_module): no filesystem to watch.
local hotreload
if _lub3d_script then
    pcall(function() hotreload = require("lib.hotreload") end)
end

-- Load the module
local M
if _lub3d_script then
    -- Normal path: require by module name → entry + deps all auto-watched
    M = require(_lub3d_script)
elseif _lub3d_module then
    -- Playground path: module table already provided
    M = _lub3d_module
end
assert(type(M) == "table", "boot: module must return a table")

-- Build desc table from module fields
local desc = {}

local desc_fields = {
    "width", "height", "sample_count", "swap_interval",
    "high_dpi", "fullscreen", "alpha", "enable_clipboard",
    "clipboard_size", "enable_dragndrop", "max_dropped_files",
    "max_dropped_file_path_length", "window_title", "icon",
    "html5_canvas_name", "html5_canvas_resize",
    "html5_preserve_drawing_buffer", "html5_premultiplied_alpha",
    "html5_ask_leave_site",
}
for _, k in ipairs(desc_fields) do
    if M[k] ~= nil then
        desc[k] = M[k]
    end
end

-- Delegate callbacks via method call (M:xxx) so that `self` always
-- points to the canonical M table held by boot.lua. After lume.hotswap
-- replaces functions in M, the new functions' upvalue `M` points to a
-- fresh table (from re-executing the file), but `self` from the colon
-- call still points to the original M where runtime state lives.
-- Modules that want hot-reload-safe state should use self.xxx.
desc.init = function()
    if M.init then M:init() end
end

desc.frame = function()
    if hotreload then
        pcall(hotreload.update)
    end
    if M.frame then M:frame() end
end

desc.cleanup = function()
    if M.cleanup then M:cleanup() end
end

desc.event = function(ev)
    if M.event then M:event(ev) end
end

app.Run(app.Desc(desc))
