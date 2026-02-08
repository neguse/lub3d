-- b2d_hello.lua - Minimal Box2D example
-- A dynamic box falls onto a static ground, rendered with sokol.gl

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")
local b2d = require("b2d")

local M = {}
M.width = 800
M.height = 600
M.window_title = "Box2D Hello"

local world_id
local ground_id
local body_id

-- Camera: meters to screen mapping
local cam_x, cam_y, cam_zoom = 0, 5, 20

local function draw_box(cx, cy, hw, hh, angle, r, g, b)
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    -- 4 corners relative to center
    local dx = { -hw, hw, hw, -hw }
    local dy = { -hh, -hh, hh, hh }
    gl.BeginQuads()
    gl.C3f(r, g, b)
    for i = 1, 4 do
        local rx = dx[i] * cos_a - dy[i] * sin_a
        local ry = dx[i] * sin_a + dy[i] * cos_a
        gl.V2f(cx + rx, cy + ry)
    end
    gl.End()
end

function M:init()
    gfx.Setup(gfx.Desc({ environment = glue.Environment() }))
    gl.Setup(gl.Desc({}))

    -- Create world
    local world_def = b2d.default_world_def()
    world_def.gravity = { 0, -10 }
    world_id = b2d.create_world(world_def)

    -- Ground (static body)
    local body_def = b2d.default_body_def()
    body_def.position = { 0, -10 }
    ground_id = b2d.create_body(world_id, body_def)

    local shape_def = b2d.default_shape_def()
    local ground_box = b2d.make_box(50, 10)
    b2d.create_polygon_shape(ground_id, shape_def, ground_box)

    -- Dynamic body
    body_def = b2d.default_body_def()
    body_def.type = b2d.BodyType.DYNAMICBODY
    body_def.position = { 0, 8 }
    body_id = b2d.create_body(world_id, body_def)

    shape_def = b2d.default_shape_def()
    shape_def.density = 1.0
    local mat = b2d.default_surface_material()
    mat.friction = 0.3
    shape_def.material = mat
    local dynamic_box = b2d.make_box(1, 1)
    b2d.create_polygon_shape(body_id, shape_def, dynamic_box)
end

function M:frame()
    -- Step physics
    b2d.world_step(world_id, 1.0 / 60.0, 4)

    -- Render
    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = 0.2, g = 0.2, b = 0.3, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.Swapchain(),
    }))

    gl.Defaults()
    gl.MatrixModeProjection()
    gl.Ortho(
        cam_x - cam_zoom, cam_x + cam_zoom,
        cam_y - cam_zoom * 0.75, cam_y + cam_zoom * 0.75,
        -1, 1
    )

    -- Ground
    draw_box(0, -10, 50, 10, 0, 0.4, 0.6, 0.4)

    -- Dynamic body
    local pos = b2d.body_get_position(body_id)
    local rot = b2d.body_get_rotation(body_id)
    local angle = b2d.rot_get_angle(rot)
    local awake = b2d.body_is_awake(body_id)
    if awake then
        draw_box(pos[1], pos[2], 1, 1, angle, 0.9, 0.5, 0.2)
    else
        draw_box(pos[1], pos[2], 1, 1, angle, 0.5, 0.5, 0.5)
    end

    gl.Draw()
    gfx.EndPass()
    gfx.Commit()
end

function M:cleanup()
    b2d.destroy_world(world_id)
    gl.Shutdown()
    gfx.Shutdown()
end

function M:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.Quit()
        end
    end
end

return M
