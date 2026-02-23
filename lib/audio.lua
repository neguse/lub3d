local fs = require("lub3d.fs")
local ma = require("miniaudio")

---@class audio
local M = {}

--- VFS 付き ma_engine を生成して返す (WASM 対応)
--- @return miniaudio.Engine engine
--- @return lightuserdata? vfs vfs は GC 防止のため呼び出し元で保持すること
function M.create_engine()
    local vfs = ma.vfs_new({
        onOpen = function(path)
            local data = fs.read(path)
            if not data then
                return nil
            end
            return { data = data, pos = 1 }
        end,
        onRead = function(handle, size)
            local chunk = handle.data:sub(handle.pos, handle.pos + size - 1)
            handle.pos = handle.pos + #chunk
            return chunk
        end,
        onInfo = function(handle)
            return #handle.data
        end,
        onClose = function(_handle) end,
    })

    local config = ma.EngineConfig({ p_resource_manager_vfs = vfs })
    return ma.engine_init(config), vfs
end

return M
