-- hakonotaiatari field rendering
-- Ground plane with grid pattern

local gl = require("sokol.gl")
local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local renderer = require("examples.hakonotaiatari.renderer")

local M = {}

-- Field color (gray)
local FIELD_COLOR = 0xff606060
local GRID_DIVISIONS = 10

-- Initialize field
function M.init()
    -- No special initialization needed
end

-- Render the field
function M.render()
    local r, g, b = const.argb_to_rgb(FIELD_COLOR)
    local L = const.FIELD_Lf

    -- Draw grid lines on XZ plane (y = 0)
    for i = 0, GRID_DIVISIONS do
        local x = -L + (2 * L * i / GRID_DIVISIONS)
        renderer.draw_line(glm.vec3(x, 0, -L), glm.vec3(x, 0, L), r, g, b)
    end

    for i = 0, GRID_DIVISIONS do
        local z = -L + (2 * L * i / GRID_DIVISIONS)
        renderer.draw_line(glm.vec3(-L, 0, z), glm.vec3(L, 0, z), r, g, b)
    end

    -- Draw boundary box (slightly raised for visibility)
    local y = 1
    renderer.draw_line(glm.vec3(-L, y, -L), glm.vec3(L, y, -L), r, g, b)
    renderer.draw_line(glm.vec3(L, y, -L), glm.vec3(L, y, L), r, g, b)
    renderer.draw_line(glm.vec3(L, y, L), glm.vec3(-L, y, L), r, g, b)
    renderer.draw_line(glm.vec3(-L, y, L), glm.vec3(-L, y, -L), r, g, b)
end

-- Render field for title screen (with rotation)
function M.render_title(angle)
    local r, g, b = const.argb_to_rgb(FIELD_COLOR)
    local L = const.FIELD_Lf * 0.5

    -- Draw smaller grid for title
    local divisions = 5
    for i = 0, divisions do
        local x = -L + (2 * L * i / divisions)
        renderer.draw_line(glm.vec3(x, 0, -L), glm.vec3(x, 0, L), r, g, b)
    end

    for i = 0, divisions do
        local z = -L + (2 * L * i / divisions)
        renderer.draw_line(glm.vec3(-L, 0, z), glm.vec3(L, 0, z), r, g, b)
    end
end

return M
