-- hotreload.lua
-- Hot reload module using rxi/lume hotswap
-- Tracks require'd files and reloads them when modified

---@type string?
SCRIPT_DIR = SCRIPT_DIR

---@type fun(path: string): number?
get_mtime = get_mtime

local M = {}

-- deps/lume is in package.path set by caller
local lume = require("lume")

-- Configuration
M.interval = 0.5  -- seconds between checks
M.enabled = true

-- Internal state
local watched = {}      -- { [filepath] = mtime }
local mod_to_path = {}  -- { [modname] = filepath }
local last_check = 0

-- Resolve module name to file path
local function resolve_path(modname)
    local path = package.path
    local name = modname:gsub("%.", "/")
    for pattern in path:gmatch("[^;]+") do
        local filepath = pattern:gsub("%?", name)
        local mtime = get_mtime(filepath)
        if mtime > 0 then
            return filepath
        end
    end
    return nil
end

-- Watch a module for changes
function M.watch(modname)
    local filepath = mod_to_path[modname] or resolve_path(modname)
    if filepath then
        mod_to_path[modname] = filepath
        watched[filepath] = get_mtime(filepath)
    end
end

-- Hook require to auto-watch modules
local original_require = require
function require(modname)
    local mod = original_require(modname)
    -- Only watch if not a C module
    if package.loaded[modname] ~= nil then
        M.watch(modname)
    end
    return mod
end

-- Check for changes and reload
function M.update()
    if not M.enabled then return end

    local now = os.clock()
    if now - last_check < M.interval then return end
    last_check = now

    for filepath, old_mtime in pairs(watched) do
        local new_mtime = get_mtime(filepath)
        if new_mtime > 0 and new_mtime ~= old_mtime then
            -- Find module name for this file
            for modname, path in pairs(mod_to_path) do
                if path == filepath then
                    print(string.format("[hotreload] Reloading: %s", modname))
                    local _, err = lume.hotswap(modname)
                    if err then
                        print(string.format("[hotreload] Error: %s", err))
                    end
                    break
                end
            end
            watched[filepath] = new_mtime
        end
    end
end

-- Get list of watched files (for debugging)
function M.list()
    local files = {}
    for filepath, mtime in pairs(watched) do
        table.insert(files, { path = filepath, mtime = mtime })
    end
    return files
end

-- Clear all watches
function M.clear()
    watched = {}
    mod_to_path = {}
end

return M
