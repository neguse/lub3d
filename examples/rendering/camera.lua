-- Camera module for simple deferred rendering
local glm = require("glm")
local app = require("sokol.app")

local M = {}

-- Camera state
M.pos = glm.vec3(0, -20, 10)
M.yaw = 0
M.pitch = 0.3
M.move_speed = 0.5
M.mouse_sensitivity = 0.003
M.mouse_captured = false

-- Key states
local keys_down = {}

-- Get forward vector
function M.forward()
    return glm.vec3(
        math.sin(M.yaw) * math.cos(M.pitch),
        math.cos(M.yaw) * math.cos(M.pitch),
        math.sin(M.pitch)
    )
end

-- Get right vector
function M.right()
    return M.forward():cross(glm.vec3(0, 0, 1)):normalize()
end

-- Get up vector
function M.up()
    return glm.vec3(0, 0, 1)
end

-- Update camera position based on input
function M.update()
    local fwd = M.forward()
    local right = M.right()
    local up = M.up()
    local speed = M.move_speed

    if keys_down["W"] then M.pos = M.pos + fwd * speed end
    if keys_down["S"] then M.pos = M.pos - fwd * speed end
    if keys_down["A"] then M.pos = M.pos - right * speed end
    if keys_down["D"] then M.pos = M.pos + right * speed end
    if keys_down["E"] or keys_down["SPACE"] then M.pos = M.pos + up * speed end
    if keys_down["Q"] or keys_down["LEFT_SHIFT"] then M.pos = M.pos - up * speed end
end

-- Get view matrix
function M.view_matrix()
    local target = M.pos + M.forward()
    return glm.lookat(M.pos, target, M.up())
end

-- Get projection matrix
function M.projection_matrix(width, height, fov, near, far)
    fov = fov or 60
    near = near or 0.1
    far = far or 1000.0
    return glm.perspective(glm.radians(fov), width / height, near, far)
end

-- Handle input event
function M.handle_event(ev)
    local evtype = ev.type
    local key = ev.key_code

    if evtype == app.EventType.KEY_DOWN then
        if key == app.Keycode.W then keys_down["W"] = true
        elseif key == app.Keycode.S then keys_down["S"] = true
        elseif key == app.Keycode.A then keys_down["A"] = true
        elseif key == app.Keycode.D then keys_down["D"] = true
        elseif key == app.Keycode.Q then keys_down["Q"] = true
        elseif key == app.Keycode.E then keys_down["E"] = true
        elseif key == app.Keycode.SPACE then keys_down["SPACE"] = true
        elseif key == app.Keycode.LEFT_SHIFT then keys_down["LEFT_SHIFT"] = true
        elseif key == app.Keycode.ESCAPE then
            if M.mouse_captured then
                app.show_mouse(true)
                app.lock_mouse(false)
                M.mouse_captured = false
                return true  -- handled
            end
        end
    elseif evtype == app.EventType.KEY_UP then
        if key == app.Keycode.W then keys_down["W"] = false
        elseif key == app.Keycode.S then keys_down["S"] = false
        elseif key == app.Keycode.A then keys_down["A"] = false
        elseif key == app.Keycode.D then keys_down["D"] = false
        elseif key == app.Keycode.Q then keys_down["Q"] = false
        elseif key == app.Keycode.E then keys_down["E"] = false
        elseif key == app.Keycode.SPACE then keys_down["SPACE"] = false
        elseif key == app.Keycode.LEFT_SHIFT then keys_down["LEFT_SHIFT"] = false
        end
    elseif evtype == app.EventType.MOUSE_DOWN then
        if ev.mouse_button == app.Mousebutton.RIGHT then
            app.show_mouse(false)
            app.lock_mouse(true)
            M.mouse_captured = true
        end
    elseif evtype == app.EventType.MOUSE_MOVE then
        if M.mouse_captured then
            M.yaw = M.yaw + ev.mouse_dx * M.mouse_sensitivity
            M.pitch = M.pitch - ev.mouse_dy * M.mouse_sensitivity
            M.pitch = math.max(-1.5, math.min(1.5, M.pitch))
        end
    end

    return false
end

return M
