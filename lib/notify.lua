-- lib/notify.lua
-- Simple toast notification system using sokol_debugtext
local sdtx = require("sokol.debugtext")

---@class notify
local M = {}

-- Configuration
M.duration = 3.0  -- seconds to show
M.max_items = 5   -- max visible notifications
M.fade_time = 0.5 -- fade out duration

-- Notification queue
local notifications = {}
local initialized = false

---@class Notification
---@field text string
---@field time number os.clock() when added
---@field level string "info" | "warn" | "error" | "ok"

-- Colors for each level
local colors = {
    info  = { 0.8, 0.8, 0.8 },
    ok    = { 0.3, 1.0, 0.3 },
    warn  = { 1.0, 0.8, 0.2 },
    error = { 1.0, 0.3, 0.3 },
}

---Initialize debugtext (call once in init)
function M.setup()
    if initialized then return end
    sdtx.setup(sdtx.Desc({
        fonts = { sdtx.font_oric() },
    }))
    initialized = true
end

---Shutdown debugtext
function M.shutdown()
    if not initialized then return end
    sdtx.shutdown()
    initialized = false
end

---Add a notification
---@param text string
---@param level? string "info" | "warn" | "error" | "ok"
function M.add(text, level)
    level = level or "info"
    table.insert(notifications, 1, {
        text = text,
        time = os.clock(),
        level = level,
    })
    -- Trim old ones
    while #notifications > M.max_items * 2 do
        table.remove(notifications)
    end
end

-- Convenience functions
function M.info(text) M.add(text, "info") end

function M.ok(text) M.add(text, "ok") end

function M.warn(text) M.add(text, "warn") end

function M.error(text) M.add(text, "error") end

---Draw notifications (call during a swapchain render pass)
---@param width number screen width
---@param height number screen height
function M.draw(width, height)
    if not initialized then return end

    local now = os.clock()
    local y = 1.0                      -- Start from top

    sdtx.canvas(width / 4, height / 4) -- smaller text (more chars = smaller font)
    sdtx.origin(0, 0)

    local visible = 0
    for i, n in ipairs(notifications) do
        if visible >= M.max_items then break end

        local age = now - n.time
        if age < M.duration then
            visible = visible + 1

            -- Calculate alpha for fade out
            local alpha = 1.0
            local fade_start = M.duration - M.fade_time
            if age > fade_start then
                alpha = 1.0 - (age - fade_start) / M.fade_time
            end

            local c = colors[n.level] or colors.info
            sdtx.color4f(c[1], c[2], c[3], alpha)
            sdtx.pos(1, y)
            sdtx.puts(n.text)
            y = y + 1
        end
    end

    sdtx.draw()

    -- Cleanup old notifications
    for i = #notifications, 1, -1 do
        if now - notifications[i].time > M.duration + 1 then
            table.remove(notifications, i)
        end
    end
end

return M
