local app = require("sokol.app")

local M = {}

local keys_down = {}
local jump_pressed = false
local dash_pressed = false

function M.init()
    keys_down = {}
    jump_pressed = false
    dash_pressed = false
end

function M.handle_event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if not ev.key_repeat then
            if ev.key_code == app.Keycode.X or ev.key_code == app.Keycode.SPACE then
                jump_pressed = true
            end
            if ev.key_code == app.Keycode.Z then
                dash_pressed = true
            end
        end
        keys_down[ev.key_code] = true
    elseif ev.type == app.EventType.KEY_UP then
        keys_down[ev.key_code] = false
    end
end

function M.update()
    -- nothing needed per-tick
end

function M.end_frame()
    jump_pressed = false
    dash_pressed = false
end

function M.get_axis()
    local x, y = 0, 0
    if keys_down[app.Keycode.LEFT] then x = x - 1 end
    if keys_down[app.Keycode.RIGHT] then x = x + 1 end
    if keys_down[app.Keycode.UP] then y = y + 1 end
    if keys_down[app.Keycode.DOWN] then y = y - 1 end
    local len = math.sqrt(x * x + y * y)
    if len > 1 then
        x, y = x / len, y / len
    end
    return x, y
end

function M.get_jump()
    if jump_pressed then
        jump_pressed = false
        return true
    end
    return false
end

function M.get_dash()
    if dash_pressed then
        local ix = M.get_axis()
        if math.abs(ix) > 0.02 then
            dash_pressed = false
            return true
        end
    end
    return false
end

return M
