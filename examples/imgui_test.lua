-- ImGui test example (using auto-generated snake_case API)
local gfx = require("sokol.gfx")
require("sokol.app")
local glue = require("sokol.glue")
local imgui = require("imgui")

-- State
local show_demo = false
local slider_val = 0.5
local checkbox_val = true
local color = { 0.4, 0.7, 1.0 }

local M = {}
M.width = 800
M.height = 600
M.window_title = "Lub3d - ImGui Test"

function M:init()
    -- Initialize sokol.gfx
    gfx.setup(gfx.Desc({
        environment = glue.environment(),
    }))

    imgui.setup()
end

function M:frame()
    imgui.new_frame()

    -- Main debug window
    if imgui.begin_window("Debug Menu") then
        imgui.text_unformatted("Lub3d ImGui Test")
        imgui.separator()

        local clicked, new_val = imgui.checkbox("Enable Feature", checkbox_val)
        if clicked then checkbox_val = new_val end

        local changed, new_slider = imgui.slider_float("Value", slider_val, 0.0, 1.0)
        if changed then slider_val = new_slider end

        local col_changed, new_col = imgui.color_edit3("Color", color)
        if col_changed then color = new_col end

        imgui.separator()
        if imgui.button("Show Demo Window") then
            show_demo = not show_demo
        end
    end
    imgui.end_window()

    if show_demo then
        local open = imgui.show_demo_window(show_demo)
        show_demo = open
    end

    -- Render
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = color[1], g = color[2], b = color[3], a = 1.0 }
            } }
        }),
        swapchain = glue.swapchain()
    }))
    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function M:event(ev)
    imgui.handle_event(ev)
end

function M:cleanup()
    imgui.shutdown()
    gfx.shutdown()
end

return M
