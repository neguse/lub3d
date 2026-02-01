-- ImGui test example (using auto-generated snake_case API)
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local imgui = require("imgui")

-- State
local show_demo = false
local slider_val = 0.5
local checkbox_val = true
local color = { 0.4, 0.7, 1.0 }

local function init_game()
    -- Initialize sokol.gfx
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    imgui.Setup()
end

local function update_frame()
    imgui.NewFrame()

    -- Main debug window
    if imgui.begin("Debug Menu") then
        imgui.text_unformatted("Mane3D ImGui Test")
        imgui.Separator()

        local clicked, new_val = imgui.Checkbox("Enable Feature", checkbox_val)
        if clicked then checkbox_val = new_val end

        local changed, new_slider = imgui.SliderFloat("Value", slider_val, 0.0, 1.0)
        if changed then slider_val = new_slider end

        local col_changed, new_col = imgui.color_edit3("Color", color)
        if col_changed then color = new_col end

        imgui.Separator()
        if imgui.Button("Show Demo Window") then
            show_demo = not show_demo
        end
    end
    imgui.End_()

    if show_demo then
        local open = imgui.ShowDemoWindow(show_demo)
        show_demo = open
    end

    -- Render
    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = color[1], g = color[2], b = color[3], a = 1.0 }
            }}
        }),
        swapchain = glue.Swapchain()
    }))
    imgui.Render()
    gfx.EndPass()
    gfx.Commit()
end

local function handle_event(ev)
    imgui.handle_event(ev)
end

local function cleanup_game()
    imgui.Shutdown()
    gfx.Shutdown()
end

-- Run the application
app.Run(app.Desc({
    width = 800,
    height = 600,
    window_title = "Mane3D - ImGui Test",
    init_cb = init_game,
    frame_cb = update_frame,
    cleanup_cb = cleanup_game,
    event_cb = handle_event,
}))
