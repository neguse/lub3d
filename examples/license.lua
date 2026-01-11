-- License Information Display
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local imgui = require("imgui")
local licenses = require("mane3d.licenses")

local license_text = ""

function init()
    imgui.setup()

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

function frame()
    local w = app.width()
    local h = app.height()

    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {{
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1 }
            }}
        }),
        swapchain = glue.swapchain()
    }))

    imgui.new_frame()

    imgui.set_next_window_pos({w * 0.1, h * 0.05})
    imgui.set_next_window_size({w * 0.8, h * 0.9})
    -- flags: NoResize(2) + NoMove(4) + NoCollapse(32) = 38
    if imgui.begin("Mane3D Licenses", nil, 38) then
        imgui.text_unformatted(license_text)
    end
    imgui.end_()

    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function cleanup()
    imgui.shutdown()
end

function event(ev)
    imgui.handle_event(ev)
end
