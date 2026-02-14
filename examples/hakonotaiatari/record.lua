-- hakonotaiatari result/record screen

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local renderer = require("examples.hakonotaiatari.renderer")

local M = {}

-- High score table (in-memory only, session-based)
local high_scores = {}
local MAX_HIGH_SCORES <const> = 5

-- Current game result
local current_score = 0
local current_rank = 0
local is_high_score = false

-- State
local tick = 0

-- Add score to high score table and return rank (1-based, 0 if not in top 5)
local function add_score(score)
    -- Insert score
    local entry = { score = score, new = true }
    table.insert(high_scores, entry)

    -- Sort by score descending
    table.sort(high_scores, function(a, b) return a.score > b.score end)

    -- Find rank of new entry
    local rank = 0
    for i, e in ipairs(high_scores) do
        if e.new then
            rank = i
            break
        end
    end

    -- Trim to max entries
    while #high_scores > MAX_HIGH_SCORES do
        table.remove(high_scores)
    end

    -- Mark all as not new for next game
    for _, e in ipairs(high_scores) do
        e.new = false
    end

    -- Check if still in list
    if rank > MAX_HIGH_SCORES then
        rank = 0
    end

    return rank
end

-- Initialize record screen with game result
function M.init(score, camera, audio)
    tick = 0
    current_score = score

    -- Add to high scores and get rank
    current_rank = add_score(score)
    is_high_score = (current_rank == 1 and score > 0)

    if camera then
        camera:set_enable_rotate(true)
    end

    if audio then
        if is_high_score then
            audio.play_bgm(const.WAVE_RESULT_HIGH_INDEX)
        else
            audio.play_bgm(const.WAVE_RESULT_INDEX)
        end
    end

    -- Set gakugaku (wobble) effect
    renderer.set_gakugaku(1.0)
end

-- Update record screen
function M.update(dt, camera)
    tick = tick + 1

    if camera then
        camera:update(dt)
    end
end

-- Render record screen
function M.render()
    -- Title
    if is_high_score then
        font.draw_text_centered("NEW HIGH SCORE", 0, 0.45, 0.06, 1, 1, 0.2)
    else
        font.draw_text_centered("GAME OVER", 0, 0.45, 0.06, 1, 0.3, 0.3)
    end

    -- Current score
    font.draw_text_centered("YOUR SCORE", 0, 0.28, 0.04, 0.8, 0.8, 0.8)
    font.draw_number_centered(current_score, 0, 0.18, 0.06, 1, 1, 1)

    -- High scores
    font.draw_text_centered("RANKING", 0, 0.0, 0.04, 0.8, 0.8, 1)

    local y = -0.12
    for i, entry in ipairs(high_scores) do
        local r, g, b = 0.9, 0.9, 0.9

        -- Highlight current score with blinking effect
        if i == current_rank then
            if math.floor(tick / 4) % 2 == 0 then
                r = 1
                g = 0.5 + math.random() * 0.5
                b = 0.5 + math.random() * 0.5
            else
                r, g, b = 0.2, 0.2, 0.2
            end
        end

        -- Rank number
        font.draw_number(i, -0.6, y, 0.035, r, g, b)
        font.draw_text(".", -0.5, y, 0.035, r, g, b)

        -- Score
        font.draw_number(entry.score, -0.3, y, 0.035, r, g, b)

        y = y - 0.12
    end

    -- Empty slots
    for i = #high_scores + 1, MAX_HIGH_SCORES do
        font.draw_number(i, -0.6, y, 0.035, 0.4, 0.4, 0.4)
        font.draw_text(". -----", -0.5, y, 0.035, 0.4, 0.4, 0.4)
        y = y - 0.12
    end

    -- Click to continue
    if math.floor(tick / 30) % 2 == 0 then
        font.draw_text_centered("CLICK TO CONTINUE", 0, -0.85, 0.04, 1, 1, 1)
    end
end

-- Check for state transition
function M.next_state()
    if input.is_button_pressed() then
        return const.GAME_STATE_TITLE
    end
    return nil
end

-- Cleanup
function M.cleanup(audio)
    if audio then
        audio.stop_bgm()
    end
end

-- Get high scores (for external access)
function M.get_high_scores()
    return high_scores
end

-- Reset high scores
function M.reset_high_scores()
    high_scores = {}
end

return M
