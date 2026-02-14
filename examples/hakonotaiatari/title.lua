-- hakonotaiatari title screen

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local renderer = require("examples.hakonotaiatari.renderer")

local M = {}

-- Subtitles (English versions)
local SUBTITLES = {
    "-DASH AND CRASH-",
    "-BOX BATTLE BEGIN-",
    "-CUBE COMBAT-",
    "-SQUARE SHOWDOWN-",
    "-BLOCK BRAWLER-",
    "-GEOMETRIC WARFARE-",
    "-PIXEL PUSHER-",
    "-HIT AND RUN-",
    "-SMASH OR BE SMASHED-",
    "-POWER OF THE BOX-",
}

-- State
local tick = 0
local subtitle_id = 1

-- Initialize title screen
function M.init(camera, audio)
    tick = 0
    subtitle_id = math.random(1, #SUBTITLES)

    if camera then
        camera:set_behind(const.CAM_BEHIND_HIGH_TITLE, const.CAM_BEHIND_BACK_TITLE)
        camera:set_lookat(glm.vec3(0, 0, 0))
        camera:set_enable_rotate(true)
    end

    if audio then
        audio.play(const.WAVE_TITLE_INDEX) -- One-shot SE, not looping BGM
    end

    -- Set gakugaku (wobble) effect
    renderer.set_gakugaku(1.0)
end

-- Update title screen
function M.update(dt, camera)
    tick = tick + 1

    if camera then
        camera:update(dt)
    end
end

-- Render title screen
function M.render()
    -- Title
    font.draw_text_centered("HAKONOTAIATARI", 0, 0.3, 0.08, 1, 1, 1)

    -- Subtitle
    local subtitle = SUBTITLES[subtitle_id]
    font.draw_text_centered(subtitle, 0, 0.15, 0.03, 0.8, 0.8, 0.8)

    -- Blinking instruction
    if math.floor(tick / 30) % 4 < 3 then
        font.draw_text_centered("CLICK TO START", 0, -0.1, 0.04, 1, 1, 1)
        font.draw_text_centered("TAB KEY FOR RENDER MODE", 0, -0.2, 0.025, 0.7, 0.7, 0.7)
    end

    -- Copyright
    font.draw_text_centered("NEGUSE 2012-2025", 0, -0.4, 0.025, 0.6, 0.6, 0.6)
end

-- Check for state transition
function M.next_state()
    if input.is_button_pressed() then
        return const.GAME_STATE_TUTORIAL
    end
    return nil
end

-- Cleanup
function M.cleanup(audio)
    -- Nothing to clean up (title SE is one-shot)
end

return M
