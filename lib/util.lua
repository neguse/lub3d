-- Utility functions for mane3d examples
local stm = require("sokol.time")
local log = require("lib.log")

-- Initialize sokol_time (once)
if not _G._stm_initialized then
    stm.Setup()
    _G._stm_initialized = true
end

local M = {}

-- Profiling support: log slow operations immediately
M.profile = {
    enabled = true,
    threshold_ms = 10,  -- Log if exceeds this
    pending = {},       -- { key = start_time }
}

--- Start a profiling measurement
---@param category string category (e.g., "shader", "texture")
---@param name string specific item name
function M.profile_begin(category, name)
    if not M.profile.enabled then return end
    local key = category .. ":" .. name
    M.profile.pending[key] = stm.Now()
end

--- End a profiling measurement, log if slow
---@param category string category (e.g., "shader", "texture")
---@param name string specific item name
function M.profile_end(category, name)
    if not M.profile.enabled then return end
    local key = category .. ":" .. name
    local start = M.profile.pending[key]
    if not start then return end

    local elapsed_ms = stm.Ms(stm.Since(start))
    M.profile.pending[key] = nil

    if elapsed_ms >= M.profile.threshold_ms then
        log.warn(string.format("[%s] %.1fms - %s", category, elapsed_ms, name))
    end
end

-- Resolve path relative to script directory
-- Absolute paths (starting with / or X:) are returned as-is
---@param path string
---@return string
function M.resolve_path(path)
    if path:match("^/") or path:match("^%a:") then
        return path
    end
    return path
end

-- Helper to pack vertex data as floats (handles large arrays)
function M.pack_floats(floats)
    local CHUNK_SIZE = 200  -- Lua unpack limit is around 200-1000
    local result = {}
    for i = 1, #floats, CHUNK_SIZE do
        local chunk_end = math.min(i + CHUNK_SIZE - 1, #floats)
        local chunk = {}
        for j = i, chunk_end do
            chunk[#chunk + 1] = floats[j]
        end
        result[#result + 1] = string.pack(string.rep("f", #chunk), table.unpack(chunk))
    end
    return table.concat(result)
end

-- Helper to pack index data as u32 (handles large arrays)
function M.pack_u32(ints)
    local CHUNK_SIZE = 200
    local result = {}
    for i = 1, #ints, CHUNK_SIZE do
        local chunk_end = math.min(i + CHUNK_SIZE - 1, #ints)
        local chunk = {}
        for j = i, chunk_end do
            chunk[#chunk + 1] = ints[j]
        end
        result[#result + 1] = string.pack(string.rep("I4", #chunk), table.unpack(chunk))
    end
    return table.concat(result)
end

return M
