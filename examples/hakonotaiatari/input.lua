-- hakonotaiatari input handling
-- Mouse position to world coordinate conversion

local app = require("sokol.app")
local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local renderer = require("examples.hakonotaiatari.renderer")

local M = {}

-- Input state
local mouse_x = 0
local mouse_y = 0
local mouse_button_down = false
local mouse_button_pressed = false  -- True only on the frame the button was pressed
local prev_mouse_button_down = false

-- Initialize input
function M.init()
    mouse_x = 0
    mouse_y = 0
    mouse_button_down = false
    mouse_button_pressed = false
    prev_mouse_button_down = false
end

-- Update input state (call at start of frame)
function M.update()
    mouse_button_pressed = mouse_button_down and not prev_mouse_button_down
    prev_mouse_button_down = mouse_button_down
end

-- Handle mouse events
function M.handle_event(ev)
    if ev.type == app.EventType.MOUSE_MOVE then
        mouse_x = ev.mouse_x
        mouse_y = ev.mouse_y
    elseif ev.type == app.EventType.MOUSE_DOWN then
        if ev.mouse_button == app.Mousebutton.LEFT then
            mouse_button_down = true
        end
    elseif ev.type == app.EventType.MOUSE_UP then
        if ev.mouse_button == app.Mousebutton.LEFT then
            mouse_button_down = false
        end
    end
end

-- Get raw mouse position in screen coordinates
function M.get_mouse_screen()
    return mouse_x, mouse_y
end

-- Check if left mouse button is currently held
function M.is_button_down()
    return mouse_button_down
end

-- Check if left mouse button was just pressed this frame
function M.is_button_pressed()
    return mouse_button_pressed
end

-- Convert screen position to world position on the ground plane (Y=0)
-- proj: projection matrix
-- view: view matrix
-- Returns glm.vec2 on XZ plane
function M.screen_to_world(proj, view, cam_eye)
    -- Get viewport (square, centered in window)
    local vx, vy, vw, vh = renderer.get_viewport()

    -- Map mouse coordinates to viewport-relative coordinates
    local viewport_mouse_x = mouse_x - vx
    local viewport_mouse_y = mouse_y - vy

    -- Normalize viewport coordinates to [-1, 1]
    local ndc_x = (2.0 * viewport_mouse_x / vw) - 1.0
    local ndc_y = 1.0 - (2.0 * viewport_mouse_y / vh)

    -- Inverse projection and view matrices
    local inv_proj = proj:inverse()
    local inv_view = view:inverse()

    -- Ray in clip space
    local ray_clip = glm.vec4(ndc_x, ndc_y, -1.0, 1.0)

    -- Ray in eye space
    local ray_eye = inv_proj * ray_clip
    ray_eye = glm.vec4(ray_eye.x, ray_eye.y, -1.0, 0.0)

    -- Ray in world space
    local ray_world = inv_view * ray_eye
    local ray_dir = glm.normalize(glm.vec3(ray_world.x, ray_world.y, ray_world.z))

    -- Intersect with ground plane (Y = 0)
    -- eye + t * dir = point on plane where point.y = 0
    -- eye.y + t * dir.y = 0
    -- t = -eye.y / dir.y
    if math.abs(ray_dir.y) < 0.0001 then
        -- Ray is parallel to ground, return position directly below camera
        return glm.vec2(cam_eye.x, cam_eye.z)
    end

    local t = -cam_eye.y / ray_dir.y
    if t < 0 then
        -- Ray points away from ground, use far intersection
        t = 1000
    end

    local world_pos = cam_eye + ray_dir * t

    -- Clamp to field boundaries
    local x = glm.clamp(world_pos.x, -const.FIELD_Lf, const.FIELD_Lf)
    local z = glm.clamp(world_pos.z, -const.FIELD_Lf, const.FIELD_Lf)

    return glm.vec2(x, z)
end

-- Get target position for player (world coordinates)
function M.get_target_position(proj, view, cam_eye)
    return M.screen_to_world(proj, view, cam_eye)
end

-- End of frame (reset pressed state)
function M.end_frame()
    -- Nothing needed - pressed state is handled in update()
end

return M
