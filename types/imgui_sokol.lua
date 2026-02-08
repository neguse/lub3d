---@meta
-- LuaCATS type definitions for imgui sokol integration (simgui)
-- These functions are manually implemented in src/imgui_sokol.cpp

---@class imgui
local imgui = {}

---@class imgui.SetupOpts
---@field max_vertices? integer
---@field no_default_font? boolean
---@field japanese_font? string
---@field font_size? number

---Setup imgui with sokol integration
---@param opts? imgui.SetupOpts
function imgui.Setup(opts) end

---Shutdown imgui
function imgui.Shutdown() end

---Begin a new imgui frame
function imgui.NewFrame() end

---Render imgui draw data
function imgui.Render() end

---Handle a sokol app event
---@param event table sokol_app event
---@return boolean handled Whether the event was handled by imgui
function imgui.HandleEvent(event) end

return imgui
