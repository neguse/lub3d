--- BMS Song Scanner
--- Scans directories for BMS files and extracts metadata
local lfs = require("lfs")
local parser = require("examples.rhythm.bms.parser")

---@class SongEntry
---@field path string BMS file path
---@field title string Song title
---@field artist string Artist name
---@field genre string Genre
---@field bpm number BPM
---@field playlevel integer Play level
---@field difficulty integer Difficulty category

---@class SongScanner
---@field songs SongEntry[] Scanned songs
---@field base_path string Base search path
local SongScanner = {}
SongScanner.__index = SongScanner

local BMS_EXTENSIONS = {
    [".bms"] = true,
    [".bml"] = true,
    [".pms"] = true,
    [".bme"] = true,
}

--- Create a new SongScanner
---@param base_path string Base directory to scan
---@return SongScanner
function SongScanner.new(base_path)
    local self = setmetatable({}, SongScanner)
    self.base_path = base_path
    self.songs = {}
    return self
end

--- Check if a file has a BMS extension
---@param path string
---@return boolean
local function is_bms_file(path)
    local ext = path:match("%.%w+$")
    if ext then
        return BMS_EXTENSIONS[ext:lower()] or false
    end
    return false
end

--- Recursively walk directory and call callback for each file
---@param path string
---@param callback fun(full_path: string)
local function walk(path, callback)
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then
        return
    end

    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local full = path .. "/" .. entry
            local attr = lfs.attributes(full)
            if attr then
                if attr.mode == "directory" then
                    walk(full, callback)
                elseif attr.mode == "file" then
                    callback(full)
                end
            end
        end
    end
end

--- Load metadata from a BMS file (header only, fast)
---@param path string
---@return SongEntry|nil
---@return string|nil error
local function load_meta(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end

    -- Read only first 8KB for header parsing (enough for metadata)
    local content = file:read(8192) or ""
    file:close()

    -- Quick parse for header fields only
    local header = {
        title = "",
        artist = "",
        genre = "",
        bpm = 130,
        playlevel = 0,
        difficulty = 0,
    }

    -- Convert encoding if needed
    local encoding = require("examples.rhythm.bms.encoding")
    content = encoding.to_utf8(content)

    for raw_line in content:gmatch("[^\r\n]+") do
        local line = raw_line:match("^%s*(.-)%s*$")
        if line:sub(1, 1) == "#" then
            local cmd, value = line:match("^#([A-Z]+)%s+(.+)$")
            if cmd and value then
                if cmd == "TITLE" then
                    header.title = value
                elseif cmd == "ARTIST" then
                    header.artist = value
                elseif cmd == "GENRE" then
                    header.genre = value
                elseif cmd == "BPM" then
                    header.bpm = tonumber(value) or 130
                elseif cmd == "PLAYLEVEL" then
                    header.playlevel = tonumber(value) or 0
                elseif cmd == "DIFFICULTY" then
                    header.difficulty = tonumber(value) or 0
                end
            end
        end
    end

    ---@type SongEntry
    local entry = {
        path = path,
        title = header.title ~= "" and header.title or path:match("([^/\\]+)%.%w+$") or "Unknown",
        artist = header.artist ~= "" and header.artist or "Unknown",
        genre = header.genre,
        bpm = header.bpm,
        playlevel = header.playlevel,
        difficulty = header.difficulty,
    }

    return entry
end

--- Scan for BMS files
---@param progress_callback fun(current: integer, path: string)|nil Optional progress callback
---@return integer count Number of songs found
function SongScanner:scan(progress_callback)
    self.songs = {}
    local paths = {}

    -- First pass: collect all BMS file paths
    walk(self.base_path, function(full_path)
        if is_bms_file(full_path) then
            paths[#paths + 1] = full_path
        end
    end)

    -- Second pass: load metadata
    for i, path in ipairs(paths) do
        if progress_callback then
            progress_callback(i, path)
        end

        local entry, err = load_meta(path)
        if entry then
            self.songs[#self.songs + 1] = entry
        else
            print(string.format("[scanner] Failed to load %s: %s", path, err or "unknown"))
        end
    end

    -- Sort by title
    table.sort(self.songs, function(a, b)
        return a.title:lower() < b.title:lower()
    end)

    return #self.songs
end

--- Get all scanned songs
---@return SongEntry[]
function SongScanner:get_songs()
    return self.songs
end

--- Get song count
---@return integer
function SongScanner:count()
    return #self.songs
end

--- Escape a string for Lua literal
---@param s string
---@return string
local function escape_string(s)
    return s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r")
end

--- Save songs to cache file
---@param cache_path string Path to cache file
---@return boolean success
---@return string|nil error
function SongScanner:save_cache(cache_path)
    local file, err = io.open(cache_path, "w")
    if not file then
        return false, err
    end

    file:write("-- BMS song cache (auto-generated)\n")
    file:write("return {\n")

    for _, song in ipairs(self.songs) do
        file:write("  {\n")
        file:write(string.format("    path = \"%s\",\n", escape_string(song.path)))
        file:write(string.format("    title = \"%s\",\n", escape_string(song.title)))
        file:write(string.format("    artist = \"%s\",\n", escape_string(song.artist)))
        file:write(string.format("    genre = \"%s\",\n", escape_string(song.genre)))
        file:write(string.format("    bpm = %s,\n", tostring(song.bpm)))
        file:write(string.format("    playlevel = %d,\n", song.playlevel))
        file:write(string.format("    difficulty = %d,\n", song.difficulty))
        file:write("  },\n")
    end

    file:write("}\n")
    file:close()

    return true
end

--- Load songs from cache file
---@param cache_path string Path to cache file
---@return boolean success
---@return string|nil error
function SongScanner:load_cache(cache_path)
    local chunk, err = loadfile(cache_path)
    if not chunk then
        return false, err
    end

    local ok, result = pcall(chunk)
    if not ok then
        return false, result
    end

    if type(result) ~= "table" then
        return false, "cache file did not return a table"
    end

    self.songs = result
    return true
end

--- Check if cache file exists
---@param cache_path string
---@return boolean
function SongScanner.cache_exists(cache_path)
    local attr = lfs.attributes(cache_path)
    return attr ~= nil and attr.mode == "file"
end

return SongScanner
