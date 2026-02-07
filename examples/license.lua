-- License Information Display
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local imgui = require("imgui")
local licenses = require("mane3d.licenses")

local license_text = ""

local function init_game()
    -- Initialize sokol.gfx
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    imgui.Setup()

    -- Build license text
    local parts = { "=== Mane3D Third-Party Licenses ===\n\n" }

    for _, lib in ipairs(licenses.libraries()) do
        table.insert(parts, string.format(">> %s (%s)\n", lib.name, lib.type))
        if lib.url and lib.url ~= "" then
            table.insert(parts, "   " .. lib.url .. "\n")
        end
        table.insert(parts, "\n")
        if lib.text then
            table.insert(parts, lib.text .. "\n")
        end
        table.insert(parts, "\n" .. string.rep("-", 60) .. "\n\n")
    end

    license_text = table.concat(parts)
end

local function update_frame()
    local w = app.Width()
    local h = app.Height()

    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1 }
            } }
        }),
        swapchain = glue.Swapchain()
    }))

    imgui.NewFrame()

    imgui.SetNextWindowPos({ w * 0.1, h * 0.05 })
    imgui.SetNextWindowSize({ w * 0.8, h * 0.9 })
    -- flags: NoResize(2) + NoMove(4) + NoCollapse(32) = 38
    if imgui.Begin("Mane3D Licenses", nil, 38) then
        imgui.TextUnformatted(license_text)
    end
    imgui.End()

    imgui.Render()
    gfx.EndPass()
    gfx.Commit()
end

local function cleanup_game()
    imgui.Shutdown()
    gfx.Shutdown()
end

local function handle_event(ev)
    imgui.HandleEvent(ev)
end

-- Run the application
app.Run(app.Desc({
    width = 1024,
    height = 768,
    window_title = "Mane3D - Licenses",
    init = init_game,
    frame = update_frame,
    cleanup = cleanup_game,
    event = handle_event,
}))
