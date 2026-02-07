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

function M.init()
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))
    gl.Setup(gl.Desc({}))
end

function M.frame()
    frame_count = frame_count + 1

    -- Clear with animated color
    local t = frame_count / 60.0
    local r = (math.sin(t) + 1) / 2
    local g = (math.sin(t + 2) + 1) / 2
    local b = (math.sin(t + 4) + 1) / 2

    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = r, g = g, b = b, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.Swapchain(),
    }))

    -- Draw a simple triangle using sokol.gl
    gl.Defaults()
    gl.MatrixModeProjection()
    gl.Ortho(-1, 1, -1, 1, -1, 1)

    gl.BeginTriangles()
    gl.V2fC3f(0.0, 0.5, 1.0, 0.0, 0.0)
    gl.V2fC3f(-0.5, -0.5, 0.0, 1.0, 0.0)
    gl.V2fC3f(0.5, -0.5, 0.0, 0.0, 1.0)
    gl.End()

    gl.Draw()
    gfx.EndPass()
    gfx.Commit()
end

function M.cleanup()
    gl.Shutdown()
    gfx.Shutdown()
end

function M.event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
            app.Quit()
        end
    end
end

return M
