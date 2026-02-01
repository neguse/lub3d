---@meta
-- LuaCATS type definitions for imgui sokol integration (simgui)
-- These functions are manually implemented in src/imgui_sokol.cpp

---@class imgui
local imgui = {}

---Setup imgui with sokol integration
function imgui.Setup() end

---Shutdown imgui
function imgui.Shutdown() end

---Begin a new imgui frame
function imgui.NewFrame() end

---Render imgui draw data
function imgui.Render() end

---Handle a sokol app event
---@param event table sokol_app event
---@return boolean handled Whether the event was handled by imgui
function imgui.handle_event(event) end

return imgui
