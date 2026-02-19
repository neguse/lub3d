local app = require("sokol.app")
local gl = require("sokol.gl")

local cam = {}
cam.x = 0
cam.y = 8
cam.zoom = 20
local dragging = false
local drag_start_x, drag_start_y = 0, 0
local cam_start_x, cam_start_y = 0, 0

function cam.reset()
    cam.x, cam.y, cam.zoom = 0, 8, 20
end

function cam.apply()
    local w = app.widthf()
    local h = app.heightf()
    local aspect = w / h
    gl.matrix_mode_projection()
    gl.ortho(
        cam.x - cam.zoom * aspect, cam.x + cam.zoom * aspect,
        cam.y - cam.zoom, cam.y + cam.zoom,
        -1, 1)
end

function cam.screen_to_world(sx, sy)
    local w = app.widthf()
    local h = app.heightf()
    local aspect = w / h
    local ndc_x = (sx / w) * 2 - 1
    local ndc_y = 1 - (sy / h) * 2
    return cam.x + ndc_x * cam.zoom * aspect,
        cam.y + ndc_y * cam.zoom
end

function cam.event(ev)
    if ev.type == app.EventType.MOUSE_DOWN and ev.mouse_button == app.Mousebutton.MIDDLE then
        dragging = true
        drag_start_x, drag_start_y = ev.mouse_x, ev.mouse_y
        cam_start_x, cam_start_y = cam.x, cam.y
    elseif ev.type == app.EventType.MOUSE_UP and ev.mouse_button == app.Mousebutton.MIDDLE then
        dragging = false
    elseif ev.type == app.EventType.MOUSE_MOVE and dragging then
        local w = app.widthf()
        local h = app.heightf()
        local aspect = w / h
        local dx = (ev.mouse_x - drag_start_x) / w * cam.zoom * aspect * 2
        local dy = (ev.mouse_y - drag_start_y) / h * cam.zoom * 2
        cam.x = cam_start_x - dx
        cam.y = cam_start_y + dy
    end
    if ev.type == app.EventType.MOUSE_SCROLL then
        cam.zoom = cam.zoom * (1 - ev.scroll_y * 0.1)
        if cam.zoom < 1 then cam.zoom = 1 end
        if cam.zoom > 500 then cam.zoom = 500 end
    end
end

return cam
