-- hakonotaiatari tutorial screen

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local renderer = require("examples.hakonotaiatari.renderer")

local M = {}

-- State
local tick = 0

-- Initialize tutorial screen
function M.init(camera, audio)
    tick = 0

    if camera then
        camera:set_enable_rotate(false)
        camera:set_behind(const.CAM_BEHIND_HIGH, const.CAM_BEHIND_BACK)
        camera:set_lookat(glm.vec3(0, 0, 0))
    end

    -- Set gakugaku (wobble) effect
    renderer.set_gakugaku(1.0)
end

-- Update tutorial screen
function M.update(dt, camera)
    tick = tick + 1

    if camera then
        camera:update(dt)
    end
end

-- Render tutorial screen
function M.render()
    -- Title
    font.draw_text_centered("HOW TO PLAY", 0, 0.45, 0.06, 1, 1, 0.5)

    -- Goal
    font.draw_text("DASH INTO ENEMIES", -0.8, 0.3, 0.035, 1, 1, 1)
    font.draw_text("TO KNOCK THEM OUT", -0.8, 0.22, 0.035, 1, 1, 1)

    -- Controls
    font.draw_text("CONTROLS", -0.8, 0.08, 0.04, 0.8, 0.8, 1)
    font.draw_text("MOUSE MOVE PLAYER", -0.8, 0.0, 0.03, 0.9, 0.9, 0.9)
    font.draw_text("LEFT CLICK DASH", -0.8, -0.08, 0.03, 0.9, 0.9, 0.9)

    -- Rules
    font.draw_text("RULES", -0.8, -0.22, 0.04, 0.8, 0.8, 1)
    font.draw_text("DASH HIT KNOCKS ENEMY", -0.8, -0.30, 0.03, 0.9, 0.9, 0.9)
    font.draw_text("NORMAL HIT KNOCKS YOU", -0.8, -0.38, 0.03, 0.9, 0.9, 0.9)

    -- Game over condition
    font.draw_text("3 HITS", -0.8, -0.52, 0.04, 1, 0.3, 0.3)
    font.draw_text("GAME OVER", -0.4, -0.52, 0.04, 1, 0.3, 0.3)

    -- Power gauge hint
    font.draw_text("POWER GAUGE FILLS OVER TIME", -0.8, -0.66, 0.025, 0.7, 0.7, 0.7)
    font.draw_text("NEED POWER TO DASH", -0.8, -0.72, 0.025, 0.7, 0.7, 0.7)

    -- Blinking start prompt
    if math.floor(tick / 40) % 2 == 0 then
        font.draw_text_centered("CLICK TO START", 0, -0.88, 0.045, 1, 1, 1)
    end
end

-- Check for state transition
function M.next_state()
    if input.is_button_pressed() then
        return const.GAME_STATE_GAME
    end
    return nil
end

-- Cleanup
function M.cleanup(audio)
    -- Nothing to clean up
end

return M
