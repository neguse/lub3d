-- License Information Display
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local imgui = require("imgui")
local licenses = require("lub3d.licenses")

local license_text = ""

local M = {}
M.width = 1024
M.height = 768
M.window_title = "Lub3d - Licenses"

function M.init()
    -- Initialize sokol.gfx
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    imgui.Setup()

    -- Build license text
    local parts = { "=== Lub3d Third-Party Licenses ===\n\n" }

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

function M.frame()
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
    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoCollapse
    if imgui.Begin("Lub3d Licenses", nil, flags) then
        imgui.TextUnformatted(license_text)
    end
    imgui.End()

    imgui.Render()
    gfx.EndPass()
    gfx.Commit()
end

function M.cleanup()
    imgui.Shutdown()
    gfx.Shutdown()
end

function M.event(ev)
    imgui.HandleEvent(ev)
end

return M
