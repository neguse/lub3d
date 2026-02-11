---@meta
-- LuaCATS type definitions for lub3d.fs (unified file system module)

---@class lub3d.fs
local fs = {}

---Read entire file contents.
---Native: fopen, WASM: synchronous XHR GET.
---@param path string file path
---@return string? data file contents or nil on failure
function fs.read(path) end

---Write data to file.
---Native: fopen, WASM: always returns false.
---@param path string file path
---@param data string binary data to write
---@return boolean success
function fs.write(path, data) end

---Get file modification time as Unix timestamp.
---Native: stat, WASM: HEAD Last-Modified header.
---@param path string file path
---@return integer? mtime Unix timestamp or nil
function fs.mtime(path) end

---Check if file exists.
---Native: stat, WASM: HEAD status 200.
---@param path string file path
---@return boolean
function fs.exists(path) end

---Iterate directory entries.
---Native: opendir/readdir (Win32: FindFirstFile), WASM: returns nil.
---Returns iterator yielding entry names (including "." and "..").
---@param path string directory path
---@return (fun(): string?)? iter iterator function or nil
function fs.dir(path) end

return fs
