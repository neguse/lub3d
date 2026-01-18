-- hello.lua - Minimal example demonstrating Lua entry point architecture
-- Lua script calls app.run() directly - no C callbacks needed

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")

local frame_count = 0

app.run(app.Desc({
    width = 800,
    height = 600,
    window_title = "Hello Mane3D (Lua Entry Point)",

    init_cb = function()
        -- Initialize graphics in init_cb (window is ready here)
        gfx.setup(gfx.Desc({
            environment = glue.environment(),
        }))
        gl.setup(gl.Desc({}))
        print("init_cb: graphics initialized")
    end,

    frame_cb = function()
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
        gl.end_()

        gl.draw()
        gfx.end_pass()
        gfx.commit()
    end,

    cleanup_cb = function()
        print("cleanup_cb: shutting down")
        gl.shutdown()
        gfx.shutdown()
    end,

    event_cb = function(ev)
        if ev.type == app.EventType.KEY_DOWN then
            if ev.key_code == app.Keycode.ESCAPE or ev.key_code == app.Keycode.Q then
                app.quit()
            end
        end
    end,
}))
