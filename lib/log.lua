-- Logging utilities for mane3d
local slog = require("sokol.log")

local M = {}

function M.info(msg)
    slog.Func("lua", 3, 0, msg, 0, "", nil)
end

function M.warn(msg)
    slog.Func("lua", 2, 0, msg, 0, "", nil)
end

function M.error(msg)
    slog.Func("lua", 1, 0, msg, 0, "", nil)
end

-- Alias for backward compatibility
M.log = M.info

return M
