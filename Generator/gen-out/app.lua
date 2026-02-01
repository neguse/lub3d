---@meta
-- LuaCATS type definitions for app
-- Auto-generated, do not edit
---@class app.Desc
---@field init_cb? fun()
---@field frame_cb? fun()
---@field cleanup_cb? fun()
---@field event_cb? fun(arg0: app.Event)
---@field width? integer
---@field height? integer
---@field window_title? string
---@field high_dpi? boolean
---@field fullscreen? boolean
---@class app.Event
---@field frame_count? integer
---@field type? app.EventType
---@field mouse_x? number
---@field mouse_y? number
---@class app
---@field Desc fun(t?: app.Desc): app.Desc
---@field Event fun(t?: app.Event): app.Event
---@field Run fun(desc: app.Desc)
---@field Width fun(): integer
---@field Height fun(): integer
local app = {}
---@enum app.EventType
app.EventType = {
    INVALID = 0,
    KEY_DOWN = 1,
    KEY_UP = 2,
    MOUSE_DOWN = 3,
    QUIT_REQUESTED = 4,
}
return app
