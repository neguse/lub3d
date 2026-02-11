-- hakonotaiatari enemy classes and generator
-- NormalEnemy, DashEnemy, and EnemyGenerator

local glm = require("lib.glm")
local const = require("examples.hakonotaiatari.const")
local Cube = require("examples.hakonotaiatari.cube")
local particle = require("examples.hakonotaiatari.particle")

-- Helper functions
local function pcs(radius, angle)
    return glm.vec2(math.cos(angle) * radius, math.sin(angle) * radius)
end

local function sub_rad(a, b)
    local f = a - b
    while f >= const.PI do f = f - const.PI * 2 end
    while f < -const.PI do f = f + const.PI * 2 end
    return f
end

local function rand_range(min, max)
    return min + math.random() * (max - min)
end

local function rand_range_mid(center, range)
    return center + (math.random() * 2 - 1) * range
end

--------------------------------------------------------------------------------
-- Base Enemy class
--------------------------------------------------------------------------------

---@class Enemy : Cube
---@field tick integer
local Enemy = setmetatable({}, { __index = Cube })
Enemy.__index = Enemy

function Enemy.new()
    local self = setmetatable(Cube.new(), Enemy)
    self.tick = 0
    return self
end

function Enemy:init(pos, angle, life, length, combo)
    Cube.init(self, const.C_TYPE_NORMAL_ENEMY, pos, 0, angle, const.E_COL_NORMAL, length, combo)
    self.stat = const.E_ST_APPEAR
    self.tick = 0
    self.life = life
    self.coll_enable = false
end

function Enemy:do_futtobasare(other_cube)
    -- Called when hit by player dash
    Cube.collide(self, other_cube)
    self.life = self.life - 1
    self.stat = const.E_ST_FUTTOBI
    self.color = const.E_COL_FUTTOBI
    self.tick = 0
    self.coll_enable = true
    local dv = self.pos - other_cube.pos
    self.angle = math.atan(dv.y, dv.x)
end

function Enemy:coll_stat()
    if self.stat == const.E_ST_APPEAR then
        return const.C_COL_ST_NONE
    elseif self.stat == const.E_ST_MUTEKI then
        return const.C_COL_ST_NONE
    elseif self.stat == const.E_ST_NORMAL then
        return const.C_COL_ST_NORMAL
    elseif self.stat == const.E_ST_DASH then
        return const.C_COL_ST_DASH
    elseif self.stat == const.E_ST_FUTTOBI then
        return const.C_COL_ST_FUTTOBI
    elseif self.stat == const.E_ST_FADEOUT then
        return const.C_COL_ST_NONE
    elseif self.stat == const.E_ST_DEAD then
        return const.C_COL_ST_NONE
    end
    return const.C_COL_ST_NONE
end

function Enemy:is_dead()
    return self.stat == const.E_ST_DEAD
end

--------------------------------------------------------------------------------
-- NormalEnemy class
--------------------------------------------------------------------------------

---@class NormalEnemy : Enemy
---@field velo_max number
local NormalEnemy = setmetatable({}, { __index = Enemy })
NormalEnemy.__index = NormalEnemy

function NormalEnemy.new()
    local self = setmetatable(Enemy.new(), NormalEnemy)
    self.velo_max = const.E_NORMAL_V
    return self
end

function NormalEnemy:init(pos, angle, life, velo_max, length, combo)
    Enemy.init(self, pos, angle, life, length, combo)
    self.type = const.C_TYPE_NORMAL_ENEMY
    self.velo_max = velo_max or const.E_NORMAL_V
end

function NormalEnemy:update(dt, player_pos, audio)
    self.tick = self.tick + 1

    local dv = player_pos - self.pos
    local dva = math.atan(dv.y, dv.x)
    local prev_stat = self.stat

    if self.stat == const.E_ST_APPEAR then
        if self.tick > const.E_APPEAR_F then
            self.stat = const.E_ST_NORMAL
            self.coll_enable = true
        end
    elseif self.stat == const.E_ST_MUTEKI then
        if self.tick > const.E_MUTEKI_F then
            self.velo = 0
            self.stat = const.E_ST_NORMAL
            self.coll_enable = true
        end
    elseif self.stat == const.E_ST_NORMAL then
        -- Turn towards player
        self.angle = self.angle + sub_rad(dva, self.angle) * 0.02
        -- Accelerate towards max velocity
        self.velo = self.velo + (self.velo_max - self.velo) * 0.03
    elseif self.stat == const.E_ST_FUTTOBI then
        self.velo = const.E_FUTTOBI_V
        -- Emit smog particles (original: amount=3, velo=50, tick=50, acc=(40,20,40))
        if self.tick % 3 == 0 then
            local pos3d = glm.vec3(self.pos.x, self.length, self.pos.y)
            particle.emit_cone(3, pos3d, const.PI - self.angle, 0.4,
                0, 0.4, 50, 50, 50, 50,
                glm.vec3(0, 0, 0), glm.vec3(40, 20, 40), 0xff404040)
        end

        if self:is_out_of_area() then
            self.velo = 0
            if self.life > 0 then
                self.stat = const.E_ST_MUTEKI
                self.color = const.E_COL_NORMAL
                self.coll_enable = false
                if audio then audio.play(const.WAVE_REVIRTH_INDEX) end
            else
                self.stat = const.E_ST_FADEOUT
                self.coll_enable = false
                if audio then audio.play(const.WAVE_FIRE_INDEX) end
            end
        end
    elseif self.stat == const.E_ST_FADEOUT then
        self.length = self.length + (-self.length * 0.03)
        -- Emit fire particles (original: amount=2+t/20, velo=100, tick=50, acc=(0,-100,0)+(150,0,150))
        if self.tick % 2 == 0 then
            local pos3d = glm.vec3(self.pos.x, 0, self.pos.y)
            particle.emit_cone(2 + math.floor(self.tick / 20), pos3d, 0, 0.2,
                const.PI * 0.5, 0.2, 100, 100, 50, 50,
                glm.vec3(0, -100, 0), glm.vec3(150, 0, 150), 0xffff0000)
        end
        if self.tick > const.E_FADEOUT_F then
            self.stat = const.E_ST_DEAD
        end
    end

    if self.stat ~= prev_stat then
        self.tick = 0
    end

    self:clamp_position()
    Cube.update(self, dt)
end

function NormalEnemy:render(proj, view)
    -- Blink during MUTEKI or APPEAR
    if (self.stat == const.E_ST_MUTEKI or self.stat == const.E_ST_APPEAR)
        and math.floor(self.tick / 2) % 2 == 0 then
        return
    end
    Cube.render(self, proj, view)
end

--------------------------------------------------------------------------------
-- DashEnemy class
--------------------------------------------------------------------------------

---@class DashEnemy : Enemy
---@field init_len number
---@field dash_v number
---@field dash_len number
local DashEnemy = setmetatable({}, { __index = Enemy })
DashEnemy.__index = DashEnemy

function DashEnemy.new()
    local self = setmetatable(Enemy.new(), DashEnemy)
    self.init_len = const.E_LEN
    self.dash_v = const.E_DASH_V
    self.dash_len = 0
    return self
end

function DashEnemy:init(pos, angle, life, dash_v, length, combo)
    Enemy.init(self, pos, angle, life, length, combo + 50)
    self.type = const.C_TYPE_DASH_ENEMY
    self.init_len = length
    self.dash_v = dash_v or const.E_DASH_V
end

function DashEnemy:update(dt, player_pos, audio)
    self.tick = self.tick + 1

    local dv = player_pos - self.pos
    local dva = math.atan(dv.y, dv.x)
    local prev_stat = self.stat

    if self.stat == const.E_ST_APPEAR then
        if self.tick > const.E_APPEAR_F then
            self.stat = const.E_ST_NORMAL
            self.coll_enable = true
        end
    elseif self.stat == const.E_ST_MUTEKI then
        self.length = self.length + (self.init_len - self.length) * 0.05

        if self.tick > const.E_MUTEKI_F then
            self.velo = 0
            self.stat = const.E_ST_NORMAL
            self.coll_enable = true
        end
    elseif self.stat == const.E_ST_NORMAL then
        self.length = self.length + (self.init_len - self.length) * 0.05

        -- Turn rate changes over time
        local dav = self.tick < 45 and 0.01 or 0.09
        self.angle = self.angle + sub_rad(dva, self.angle) * dav

        -- Start dash when facing player
        if self.tick > 45 and math.abs(sub_rad(dva, self.angle)) < 0.1 then
            self.stat = const.E_ST_DASH
            self.velo = const.E_DASH_V
            self.color = const.E_COL_DASH
            self.coll_enable = true
            self.dash_len = self.length + const.E_DASH_LEN
            if audio then audio.play(const.WAVE_SUBERIE_INDEX) end
        else
            self.velo = self.velo + (const.E_NORMAL_V - self.velo) * 0.03
        end
    elseif self.stat == const.E_ST_DASH then
        self.length = self.length + (self.dash_len - self.length) * 0.1

        if self.tick > const.E_DASH_F then
            self.stat = const.E_ST_NORMAL
            self.color = const.E_COL_NORMAL
            self.coll_enable = true
        end
        -- Emit dash particles (original: velo=300,70, tick=50,10, acc=(0,-100,0)+(5,0,5))
        local px = self.pos.x - math.cos(self.angle) * self.length
        local py = self.pos.y - math.sin(self.angle) * self.length
        local pos3d = glm.vec3(px, self.length, py)
        particle.emit_cone(1, pos3d, const.PI + self.angle, const.PI,
            const.PI * 0.25, const.PI, 300, 70, 50, 10,
            glm.vec3(0, -100, 0), glm.vec3(5, 0, 5), const.E_COL_DASH_PARTICLE)
    elseif self.stat == const.E_ST_FUTTOBI then
        self.velo = const.E_FUTTOBI_V
        -- Emit smog particles (original: amount=3, velo=50, tick=50, acc=(40,20,40))
        if self.tick % 3 == 0 then
            local pos3d = glm.vec3(self.pos.x, self.length, self.pos.y)
            particle.emit_cone(3, pos3d, const.PI - self.angle, 0.4,
                0, 0.4, 50, 50, 50, 50,
                glm.vec3(0, 0, 0), glm.vec3(40, 20, 40), 0xff404040)
        end

        if self:is_out_of_area() then
            self.velo = 0
            if self.life > 0 then
                self.stat = const.E_ST_MUTEKI
                self.color = const.E_COL_NORMAL
                self.coll_enable = false
                if audio then audio.play(const.WAVE_REVIRTH_INDEX) end
            else
                self.stat = const.E_ST_FADEOUT
                self.coll_enable = false
                if audio then audio.play(const.WAVE_FIRE_INDEX) end
            end
        end
    elseif self.stat == const.E_ST_FADEOUT then
        self.length = self.length + (-self.length * 0.05)
        -- Emit fire particles (original: amount=2+t/20, velo=100, tick=50, acc=(0,-100,0)+(150,0,150))
        if self.tick % 2 == 0 then
            local pos3d = glm.vec3(self.pos.x, 0, self.pos.y)
            particle.emit_cone(2 + math.floor(self.tick / 20), pos3d, 0, 0.2,
                const.PI * 0.5, 0.2, 100, 100, 50, 50,
                glm.vec3(0, -100, 0), glm.vec3(150, 0, 150), 0xffff0000)
        end
        if self.tick > const.E_FADEOUT_F then
            self.stat = const.E_ST_DEAD
        end
    end

    if self.stat ~= prev_stat then
        self.tick = 0
    end

    self:clamp_position()
    Cube.update(self, dt)
end

function DashEnemy:render(proj, view)
    -- Blink during MUTEKI or APPEAR
    if (self.stat == const.E_ST_MUTEKI or self.stat == const.E_ST_APPEAR)
        and math.floor(self.tick / 2) % 2 == 0 then
        return
    end
    Cube.render(self, proj, view)

    -- Draw rotating decoration cube (original: 500ms per rotation)
    local renderer = require("examples.hakonotaiatari.renderer")
    local time_ms = os.clock() * 1000
    local rot_angle = (time_ms % 500) * 2.0 * const.PI / 500.0
    local deco_size = self.length * (1.0 / math.sqrt(2))
    local r, g, b = const.argb_to_rgb(self.color)
    renderer.draw_cube(
        glm.vec3(self.pos.x, 0, self.pos.y),
        glm.vec3(deco_size, deco_size * 2, deco_size),
        rot_angle,
        r, g, b,
        proj, view
    )
end

--------------------------------------------------------------------------------
-- EnemyGenerator class
--------------------------------------------------------------------------------

---@class EnemyGenerator
---@field level integer
---@field level_tick integer
---@field commands table
---@field command_index integer
local EnemyGenerator = {}
EnemyGenerator.__index = EnemyGenerator

function EnemyGenerator.new()
    local self = setmetatable({}, EnemyGenerator)
    self.level = 0
    self.level_tick = 0
    self.commands = {}
    self.command_index = 1
    return self
end

function EnemyGenerator:reset()
    self.level = 0
    self.level_tick = 0
    self.commands = {}
    self.command_index = 1
    self:next_level()
end

function EnemyGenerator:update(dt, enemies, player_pos)
    self.level_tick = self.level_tick + 1

    -- Count living enemies
    local enemy_count = 0
    for _, enemy in ipairs(enemies) do
        if not enemy:is_dead() then
            enemy_count = enemy_count + 1
        end
    end

    -- Process commands
    if self.command_index <= #self.commands then
        local cmd = self.commands[self.command_index]

        if cmd.type == "sleep" then
            cmd.tick = cmd.tick - 1
            if cmd.tick <= 0 then
                self.command_index = self.command_index + 1
            end
        elseif cmd.type == "spawn_normal" then
            for i = 1, cmd.count do
                local enemy = NormalEnemy.new()
                local angle = rand_range(0, const.PI * 2)
                enemy:init(cmd.pos, angle, cmd.life, cmd.velo_max, cmd.length, 0)
                table.insert(enemies, enemy)
            end
            self.command_index = self.command_index + 1
        elseif cmd.type == "spawn_normal_near" then
            for i = 1, cmd.count do
                local angle = rand_range(0, const.PI * 2)
                local pos = player_pos + pcs(cmd.distance, angle)
                local enemy = NormalEnemy.new()
                enemy:init(pos, angle, cmd.life, cmd.velo_max, cmd.length, 0)
                table.insert(enemies, enemy)
            end
            self.command_index = self.command_index + 1
        elseif cmd.type == "spawn_dash" then
            for i = 1, cmd.count do
                local enemy = DashEnemy.new()
                local angle = rand_range(0, const.PI * 2)
                enemy:init(cmd.pos, angle, cmd.life, const.E_DASH_V, cmd.length, 0)
                table.insert(enemies, enemy)
            end
            self.command_index = self.command_index + 1
        end
    elseif enemy_count == 0 then
        -- All enemies dead and no more commands, advance level
        self:next_level()
    end
end

function EnemyGenerator:next_level()
    self.level = self.level + 1
    self.level_tick = 0
    self.commands = {}
    self.command_index = 1

    -- Rest period every 4 levels
    if (self.level % 4) == 1 then
        table.insert(self.commands, { type = "sleep", tick = const.FPS * 3 })
    end

    -- Create level based on current level
    self:create_level(self.level)
end

function EnemyGenerator:create_level(level)
    local phase = level % 4

    if phase == 1 then
        -- Pop level: enemies spawn at random positions
        if level <= 4 then
            table.insert(self.commands,
                {
                    type = "spawn_normal_near",
                    distance = 200,
                    count = 1,
                    life = 1,
                    velo_max = const.E_NORMAL_V,
                    length =
                        const.E_LEN
                })
        else
            table.insert(self.commands,
                {
                    type = "spawn_normal_near",
                    distance = 200,
                    count = 1,
                    life = 1,
                    velo_max = const.E_NORMAL_V,
                    length =
                        const.E_LEN
                })
            for i = 1, math.min(level // 4, 5) do
                table.insert(self.commands,
                    {
                        type = "spawn_normal",
                        pos = glm.vec2(rand_range_mid(0, const.FIELD_Lf),
                            rand_range_mid(0, const.FIELD_Lf)),
                        count = 5,
                        life = 1,
                        velo_max = const.E_NORMAL_V,
                        length =
                            const.E_LEN
                    })
                table.insert(self.commands, { type = "sleep", tick = 20 })
            end
            table.insert(self.commands,
                {
                    type = "spawn_normal_near",
                    distance = 200,
                    count = 3,
                    life = 1,
                    velo_max = const.E_NORMAL_V,
                    length =
                        const.E_LEN
                })
        end
    elseif phase == 2 then
        -- Time level: enemies spawn over time
        local count = math.min(3 + level // 4, 8)
        for i = 1, count do
            table.insert(self.commands,
                {
                    type = "spawn_normal",
                    pos = glm.vec2(rand_range_mid(0, const.FIELD_Lf),
                        rand_range_mid(0, const.FIELD_Lf)),
                    count = math.min(1 + level // 8, 3),
                    life = 1,
                    velo_max = const
                        .E_NORMAL_V,
                    length = const.E_LEN
                })
            table.insert(self.commands, { type = "sleep", tick = 100 })
        end
    elseif phase == 3 then
        -- Special level: big enemies or swarm
        if level <= 4 then
            -- Big enemy
            table.insert(self.commands,
                {
                    type = "spawn_normal",
                    pos = glm.vec2(rand_range_mid(0, const.FIELD_Lf),
                        rand_range_mid(0, const.FIELD_Lf)),
                    count = 1,
                    life = 2,
                    velo_max = const.E_NORMAL_V * 0.8,
                    length =
                        const.E_LEN * 3
                })
        else
            -- Swarm
            for i = 1, 15 do
                table.insert(self.commands,
                    {
                        type = "spawn_normal",
                        pos = glm.vec2(rand_range_mid(0, const.FIELD_Lf * 2),
                            rand_range_mid(0, const.FIELD_Lf * 2)),
                        count = 3,
                        life = 1,
                        velo_max = const.E_NORMAL_V,
                        length =
                            const.E_LEN
                    })
                table.insert(self.commands, { type = "sleep", tick = 2 })
            end
        end
    elseif phase == 0 then
        -- Boss level: dash enemies
        local boss_count = math.min(1 + level // 8, 3)
        local boss_life = math.min(2 + level // 8, 4)
        for i = 1, boss_count do
            table.insert(self.commands,
                { type = "spawn_dash", pos = glm.vec2(0, 0), count = 1, life = boss_life, length = const.E_LEN * 1.5 })
            if i < boss_count then
                table.insert(self.commands, { type = "sleep", tick = 90 })
            end
        end
    end
end

function EnemyGenerator:get_level()
    return self.level
end

--------------------------------------------------------------------------------
-- Module exports
--------------------------------------------------------------------------------

return {
    Enemy = Enemy,
    NormalEnemy = NormalEnemy,
    DashEnemy = DashEnemy,
    EnemyGenerator = EnemyGenerator,
}
