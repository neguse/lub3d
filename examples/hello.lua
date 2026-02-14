-- hello.lua - Minimal example
-- Animated triangle using sokol.app + sokol.gl

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")

local frame_count = 0

local M = {}
M.width = 800
M.height = 600
M.window_title = "Hello Lub3d (Lua Entry Point)"

function M:init()
    gfx.setup(gfx.Desc({
        environment = glue.environment(),
    }))
    gl.setup(gl.Desc({}))
end

function M:frame()
    frame_count = frame_count + 1

    -- Clear with animated color
    local t = frame_count / 60.0
    local r = (math.sin(t) + 1) / 2
    local g = (math.sin(t + 2) + 1) / 2
    local b = (math.sin(t + 4) + 1) / 2

    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = r, g = g, b = b, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.swapchain(),
    }))

    -- Draw a simple triangle using sokol.gl
    gl.defaults()
    gl.matrix_mode_projection()
    gl.ortho(-1, 1, -1, 1, -1, 1)

    gl.begin_triangles()
    gl.v2f_c3f(0.0, 0.5, 1.0, 0.0, 0.0)
    gl.v2f_c3f(-0.5, -0.5, 0.0, 1.0, 0.0)
    gl.v2f_c3f(0.5, -0.5, 0.0, 0.0, 1.0)
    gl["end"]()

    gl.draw()
    gfx.end_pass()
    gfx.commit()
end

function M:cleanup()
    gl.shutdown()
    gfx.shutdown()
end

function M:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.quit()
        end
    end
end

return M
