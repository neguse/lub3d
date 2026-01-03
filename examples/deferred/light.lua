-- examples/deferred/light.lua
-- Light module for deferred rendering
local glm = require("glm")

---@class deferred.Light
---@field pos vec3 Light position in world space
---@field color vec3 Light color (RGB)
---@field ambient vec3 Ambient color (RGB)
---@field view_pos fun(view_matrix: mat4): vec4
---@field pack_uniforms fun(view_matrix: mat4): string
local M = {}

M.pos = glm.vec3(10, -10, 20)
M.color = glm.vec3(1.0, 0.9, 0.8)
M.ambient = glm.vec3(0.2, 0.2, 0.3)

---Transform light position to view space
---@param view_matrix mat4
---@return vec4
function M.view_pos(view_matrix)
    local v = view_matrix * glm.vec4(M.pos.x, M.pos.y, M.pos.z, 1.0)
    return v
end

---Pack uniforms for lighting shader (3x vec4)
---@param view_matrix mat4
---@return string Packed uniform data
function M.pack_uniforms(view_matrix)
    local lv = M.view_pos(view_matrix)
    return string.pack("ffff ffff ffff",
        lv.x, lv.y, lv.z, 1.0,
        M.color.x, M.color.y, M.color.z, 1.0,
        M.ambient.x, M.ambient.y, M.ambient.z, 1.0
    )
end

return M
