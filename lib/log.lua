-- Logging utilities for lub3d
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

--- Convert a table or pairs-iterable userdata to a short string
---@param t any
---@return string
function M.dump(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Alias for backward compatibility
M.log = M.info

return M
