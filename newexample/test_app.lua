local app = require("sokol.app")

local frame_count = 0

app.Run(app.Desc({
    width = 640,
    height = 480,
    window_title = "Generator Test",
    init = function()
        slog("init: width=" .. app.Width() .. " height=" .. app.Height())
    end,
    frame = function()
        frame_count = frame_count + 1
        if frame_count % 60 == 0 then
            slog("frame: " .. frame_count)
        end
    end,
    cleanup = function()
        slog("cleanup: " .. frame_count .. " frames")
    end,
    event = function(ev)
    end,
}))
