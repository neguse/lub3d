-- hakonotaiatari main game state

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local font = require("examples.hakonotaiatari.font")
local input = require("examples.hakonotaiatari.input")
local renderer = require("examples.hakonotaiatari.renderer")
local Player = require("examples.hakonotaiatari.player")
local enemy_module = require("examples.hakonotaiatari.enemy")
local particle = require("examples.hakonotaiatari.particle")
local Cube = require("examples.hakonotaiatari.cube")

local M = {}

-- Game state
---@type Player
local player
local enemies = {}
---@type EnemyGenerator
local generator
local score = 0
local tick = 0

-- Initialize game state
function M.init(camera, audio)
    tick = 0
    score = 0
    enemies = {}

    -- Initialize player
    player = Player.new()
    player:init()

    -- Initialize enemy generator
    generator = enemy_module.EnemyGenerator.new()
    generator:reset()

    -- Initialize particles
    particle.init()

    -- Setup camera
    if camera then
        camera:set_enable_rotate(false)
        camera:set_behind(const.CAM_BEHIND_HIGH, const.CAM_BEHIND_BACK)
        camera:set_lookat(glm.vec3(0, 0, 0))
    end

    -- Play random BGM
    if audio then
        local bgm_list = { const.WAVE_BGM1_INDEX, const.WAVE_BGM2_INDEX, const.WAVE_BGM3_INDEX }
        local bgm = bgm_list[math.random(1, #bgm_list)]
        audio.play_bgm(bgm)
    end

    -- Initialize gakugaku (wobble) to 0
    renderer.set_gakugaku(0.0)
end

-- Update game state
function M.update(dt, camera, audio)
    tick = tick + 1

    -- Update gakugaku based on player state (like original)
    if not player:is_dead() then
        -- While alive: gakugaku based on remaining life
        renderer.set_gakugaku(math.max(5 - player.life, 0) * 0.2)
    else
        -- After death: gradually increase gakugaku
        renderer.set_gakugaku(renderer.get_gakugaku() + 0.001)
    end

    -- Get mouse position in world space
    local target_pos = glm.vec2(0, 0)
    if camera then
        local world_pos = input.screen_to_world(camera:get_proj(), camera:get_view(), camera:get_eye())
        if world_pos then
            target_pos = world_pos
        end
    end

    -- Update player
    player:update(dt, target_pos, camera, audio)

    -- Update enemy generator
    generator:update(dt, enemies, player.pos)

    -- Update enemies
    for _, enemy in ipairs(enemies) do
        enemy:update(dt, player.pos, audio)
    end

    -- Player-enemy collision
    if player.coll_enable then
        for _, enemy in ipairs(enemies) do
            if enemy.coll_enable then
                if Cube.is_cube_collide(player, enemy) then
                    local player_stat = player:coll_stat()
                    local enemy_stat = enemy:coll_stat()

                    if player_stat == const.C_COL_ST_DASH then
                        -- Player dashing into enemy
                        if enemy_stat == const.C_COL_ST_NORMAL then
                            enemy:do_futtobasare(player)
                            M.add_score(enemy.combo)
                            if audio then audio.play(const.WAVE_NAGU_INDEX) end
                        elseif enemy_stat == const.C_COL_ST_DASH then
                            -- Both dashing - player gets knocked back, enemy continues dash
                            player:on_collide(enemy, audio)
                        end
                    elseif player_stat == const.C_COL_ST_NORMAL then
                        -- Player not dashing
                        player:on_collide(enemy, audio)
                    end
                end
            end
        end
    end

    -- Clamp player position
    player:clamp_position()

    -- Enemy-enemy collision
    for i = 1, #enemies do
        local e1 = enemies[i]
        if e1.coll_enable then
            for j = i + 1, #enemies do
                local e2 = enemies[j]
                if e2.coll_enable then
                    if Cube.is_cube_collide(e1, e2) then
                        Cube.collide(e1, e2)
                    end
                end
            end
        end
    end

    -- Remove dead enemies
    local alive_enemies = {}
    for _, enemy in ipairs(enemies) do
        if not enemy:is_dead() then
            table.insert(alive_enemies, enemy)
        end
    end
    enemies = alive_enemies

    -- Update particles
    particle.update(dt)

    -- Update camera
    if camera then
        camera:update(dt)
    end
end

-- Render game
function M.render(proj, view)
    -- Render player
    player:render(proj, view)

    -- Render enemies
    for _, enemy in ipairs(enemies) do
        enemy:render(proj, view)
    end

    -- Render particles
    particle.render()
end

-- Render UI
function M.render_ui()
    -- Score
    font.draw_text("SCORE", -0.95, 0.9, 0.03, 0.8, 0.8, 0.8)
    font.draw_number(score, -0.95, 0.82, 0.04, 1, 1, 1)

    -- Life
    font.draw_text("LIFE", 0.6, 0.9, 0.03, 0.8, 0.8, 0.8)
    local life_str = ""
    for i = 1, math.min(player.life, 8) do
        life_str = life_str .. "O"
    end
    font.draw_text(life_str, 0.6, 0.82, 0.04, 1, 0.3, 0.3)

    -- Power gauge
    local power_ratio = player.power / const.P_POW_MAX
    local can_dash = player.power > const.P_DASH_MIN_POW
    local gauge_color_r = can_dash and 1 or 0.4
    local gauge_color_g = can_dash and 0.8 or 0.4
    local gauge_color_b = can_dash and 0.2 or 0.4

    font.draw_text("POWER", -0.95, -0.85, 0.025, 0.6, 0.6, 0.6)

    -- Draw gauge background
    local gauge_width = 0.4
    local gauge_height = 0.03
    local gauge_x = -0.95
    local gauge_y = -0.92

    -- Gauge filled portion (drawn as text characters)
    local filled_chars = math.floor(power_ratio * 10)
    local gauge_str = string.rep("=", filled_chars) .. string.rep("-", 10 - filled_chars)
    font.draw_text(gauge_str, gauge_x, gauge_y, 0.025, gauge_color_r, gauge_color_g, gauge_color_b)

    -- Level indicator
    local level = generator:get_level()
    font.draw_text("LEVEL", 0.6, -0.85, 0.025, 0.6, 0.6, 0.6)
    font.draw_number(level, 0.6, -0.92, 0.03, 1, 1, 1)

    -- Game over message
    if player:is_dead() then
        font.draw_text_centered("GAME OVER", 0, 0.1, 0.08, 1, 0.3, 0.3)
        if math.floor(tick / 30) % 2 == 0 then
            font.draw_text_centered("CLICK TO CONTINUE", 0, -0.05, 0.04, 1, 1, 1)
        end
    end
end

-- Add score with combo bonus
function M.add_score(combo)
    score = score + combo
end

-- Check for state transition
function M.next_state()
    if player:is_dead() and input.is_button_pressed() then
        return const.GAME_STATE_RECORD, score
    end
    return nil
end

-- Cleanup
function M.cleanup(audio)
    if audio then
        audio.stop_bgm()
    end
    particle.clear()
    renderer.set_gakugaku(0.0)
end

-- Get current score (for external access)
function M.get_score()
    return score
end

-- Get player (for external access)
function M.get_player()
    return player
end

return M
