-- ImGui test example
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local imgui = require("imgui")

-- State
local show_demo = false
local slider_val = 0.5
local checkbox_val = true
local color = { 0.4, 0.7, 1.0 }

function init()
    imgui.setup()
end

function frame()
    imgui.new_frame()

    -- Main debug window
    if imgui.Begin("Debug Menu") then
        imgui.Text("Mane3D ImGui Test")
        imgui.Separator()

        checkbox_val = imgui.Checkbox("Enable Feature", checkbox_val)
        slider_val = imgui.SliderFloat("Value", slider_val, 0.0, 1.0)

        local r, g, b, changed = imgui.ColorEdit3("Color", color[1], color[2], color[3])
        if changed then
            color = { r, g, b }
        end

        imgui.Separator()
        if imgui.Button("Show Demo Window") then
            show_demo = not show_demo
        end
    end
    imgui.End()

    if show_demo then
        show_demo = imgui.ShowDemoWindow(show_demo)
    end

    -- Render
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = color[1], g = color[2], b = color[3], a = 1.0 }
            }}
        }),
        swapchain = glue.swapchain()
    }))
    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function event(ev)
    imgui.handle_event(ev)
end

function cleanup()
    imgui.shutdown()
end
