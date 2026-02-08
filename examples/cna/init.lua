-- cut'n'align - match-3 puzzle game
-- Ported from neguse/ld44 (Go/Ebiten) to lub3d
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local texture = require("lib.texture")
local sprite = require("lib.sprite")
local log = require("lib.log")
local ma = require("miniaudio")

-- === Constants ===

local SCREEN_W = 200
local SCREEN_H = 300
local BOARD_W = 8
local BOARD_H = 16
local STONE_W = 16
local STONE_H = 16
local PICK_MAX = 6
local RESERVE_NUM = 6
local JAMMER_TURN = 5
local WAIT_ERASE_FRAME = 15
local NUMBER_W = 16
local NUMBER_H = 32
local ALPHA_W = 16
local ALPHA_H = 16
local ORIGIN_X = 10
local ORIGIN_Y = -10 + SCREEN_H - STONE_H * BOARD_H

-- Special number tile indices
local NUM_CROSS  = 10
local NUM_EQUAL  = 11
local NUM_PERIOD = 12
local NUM_E      = 13
local NUM_N      = 14
local NUM_D      = 15

-- Color enum
local Color = {
    None = 0,
    Red = 1,
    Blue = 2,
    Green = 3,
    Yellow = 4,
    Pink = 5,
    Orange = 6,
    Dummy3 = 7,
    Limit = 8,
    Wall = 9,
    Cursor = 10,
    Jammer = 11,
}

local function is_colored(c)
    return c >= Color.Red and c < Color.Limit
end

-- Step enum (game states)
local Step = {
    Title = 0,
    Move = 1,
    FallStone = 2,
    WaitErase = 3,
    CauseJammer = 4,
    GameOver = 5,
}

-- === Pure helpers (no state) ===

local function stone_uv(color_idx)
    local x = (color_idx % 8) * STONE_W
    local y = math.floor(color_idx / 8) * STONE_H
    return x, y, STONE_W, STONE_H
end

local function number_uv(digit)
    local x = (digit % 8) * NUMBER_W
    local y = 32 + math.floor(digit / 8) * NUMBER_H
    return x, y, NUMBER_W, NUMBER_H
end

local alpha_map = { c = 0, u = 1, t = 2, n = 3, a = 4, l = 5, i = 6, g = 7, k = 8, o = 9, ["@"] = 10, e = 11, s = 12 }
local function alpha_uv(ch)
    local idx = alpha_map[ch] or 0
    local x = (idx % 8) * ALPHA_W
    local y = 96 + math.floor(idx / 8) * ALPHA_H
    return x, y, ALPHA_W, ALPHA_H
end

local function calc_score(sequent, num)
    local mult = math.floor(2 ^ sequent)
    local s = mult * num
    local eq = tostring(mult) .. "x" .. tostring(num) .. "=" .. tostring(s) .. "."
    return s, eq
end

local function screen_to_board(sx, sy)
    local bx = math.floor((sx - ORIGIN_X) / STONE_W) + 1
    local by = math.floor((sy - ORIGIN_Y) / STONE_H) + 1
    return bx, by
end

-- === Module ===

local TICK_DT = 1 / 30

local M = {}
M.width = 400
M.height = 600
M.window_title = "cut'n'align"

-- === Board ===

function M:board_init()
    self.board = {}
    for x = 1, BOARD_W do
        self.board[x] = {}
        for y = 1, BOARD_H do
            self.board[x][y] = nil
        end
    end
    for x = 1, BOARD_W do
        self.board[x][BOARD_H] = { color = Color.Wall, erased = false }
    end
    for y = 1, BOARD_H do
        self.board[1][y] = { color = Color.Wall, erased = false }
        self.board[BOARD_W][y] = { color = Color.Wall, erased = false }
    end
end

function M:board_get(x, y)
    if x < 1 or x > BOARD_W or y < 1 or y > BOARD_H then return nil end
    return self.board[x][y]
end

function M:board_set(x, y, stone)
    if x >= 1 and x <= BOARD_W and y >= 1 and y <= BOARD_H then
        self.board[x][y] = stone
    end
end

function M:board_height_at(x)
    for y = 1, BOARD_H do
        if self.board[x][y] then return BOARD_H - y end
    end
    return 0
end

function M:board_is_full()
    for x = 2, BOARD_W - 1 do
        if self:board_height_at(x) < BOARD_H - 2 then return false end
    end
    return true
end

function M:board_fall_stone()
    local fell = false
    for x = 1, BOARD_W do
        for y = BOARD_H - 1, 1, -1 do
            if self.board[x][y] and not self.board[x][y + 1] then
                self.board[x][y + 1] = self.board[x][y]
                self.board[x][y] = nil
                fell = true
            end
        end
    end
    return fell
end

function M:board_mark_erase()
    local count = 0

    local function check_line(cells)
        local i = 1
        while i <= #cells do
            local cx, cy = cells[i][1], cells[i][2]
            local s = self:board_get(cx, cy)
            if s and is_colored(s.color) then
                local run_start = i
                local c = s.color
                i = i + 1
                while i <= #cells do
                    local nx, ny = cells[i][1], cells[i][2]
                    local ns = self:board_get(nx, ny)
                    if ns and ns.color == c then
                        i = i + 1
                    else
                        break
                    end
                end
                if i - run_start >= 3 then
                    for j = run_start, i - 1 do
                        local jx, jy = cells[j][1], cells[j][2]
                        local js = self:board_get(jx, jy)
                        if js then
                            js.erased = true
                            count = count + 1
                        end
                    end
                end
            else
                i = i + 1
            end
        end
    end

    for y = 1, BOARD_H do
        local line = {}
        for x = 1, BOARD_W do line[#line + 1] = { x, y } end
        check_line(line)
    end

    for x = 1, BOARD_W do
        local line = {}
        for y = 1, BOARD_H do line[#line + 1] = { x, y } end
        check_line(line)
    end

    for start_x = 1, BOARD_W do
        local line = {}
        local x, y = start_x, 1
        while x <= BOARD_W and y <= BOARD_H do
            line[#line + 1] = { x, y }
            x = x + 1; y = y + 1
        end
        check_line(line)
    end
    for start_y = 2, BOARD_H do
        local line = {}
        local x, y = 1, start_y
        while x <= BOARD_W and y <= BOARD_H do
            line[#line + 1] = { x, y }
            x = x + 1; y = y + 1
        end
        check_line(line)
    end

    for start_x = 1, BOARD_W do
        local line = {}
        local x, y = start_x, BOARD_H
        while x <= BOARD_W and y >= 1 do
            line[#line + 1] = { x, y }
            x = x + 1; y = y - 1
        end
        check_line(line)
    end
    for start_y = BOARD_H - 1, 1, -1 do
        local line = {}
        local x, y = 1, start_y
        while x <= BOARD_W and y >= 1 do
            line[#line + 1] = { x, y }
            x = x + 1; y = y - 1
        end
        check_line(line)
    end

    for x = 1, BOARD_W do
        for y = 1, BOARD_H do
            local s = self:board_get(x, y)
            if s and s.erased and is_colored(s.color) then
                local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
                for _, d in ipairs(dirs) do
                    local ns = self:board_get(x + d[1], y + d[2])
                    if ns and ns.color == Color.Jammer then
                        ns.erased = true
                    end
                end
            end
        end
    end

    return count
end

function M:board_erase()
    local erased = false
    for x = 1, BOARD_W do
        for y = 1, BOARD_H do
            local s = self.board[x][y]
            if s and s.erased then
                self.board[x][y] = nil
                erased = true
            end
        end
    end
    return erased
end

-- === Game State ===

function M:color_count()
    local level = 3
    if self.game.turn > 24 then level = level + 1 end
    if self.game.turn > 48 then level = level + 1 end
    if self.game.turn > 72 then level = level + 1 end
    return level
end

function M:next_color()
    if #self.game.buffer == 0 then
        local n = self:color_count()
        for i = 1, n do
            self.game.buffer[i] = i
        end
        for i = n, 2, -1 do
            local j = math.random(1, i)
            self.game.buffer[i], self.game.buffer[j] = self.game.buffer[j], self.game.buffer[i]
        end
    end
    return table.remove(self.game.buffer, 1)
end

function M:fill_pick()
    while #self.game.pick < PICK_MAX do
        self.game.pick[#self.game.pick + 1] = { color = self:next_color(), erased = false }
    end
end

function M:game_init()
    self:board_init()
    local hs = self.game and self.game.high_score or 0
    self.game = {
        step = Step.Title,
        pick = {},
        pick_x = 4,
        pick_y = 1,
        pick_len = 0,
        buffer = {},
        turn = 0,
        score = 0,
        high_score = hs,
        sequent_erase = 0,
        erase_num = 0,
        wait = 0,
        score_equation = "",
        ticks = 0,
        mouse_x = 0,
        mouse_y = 0,
        clicked = false,
    }
    self:fill_pick()
end

function M:adjust_pick(cx, cy)
    local cx0 = math.max(1, math.min(cx - 1, BOARD_W - 2))
    local cy0 = cy - 1
    self.game.pick_x = cx0 + 1

    local height = BOARD_H
    for y = 1, BOARD_H do
        if self.board[self.game.pick_x][y] then
            height = y - 1
            break
        end
    end

    local pick_y0 = PICK_MAX - 1 + math.min(height - PICK_MAX - 1, 0)
    local pick_len = math.max(0, math.min((pick_y0 - math.max(cy0, 0)) + 1, PICK_MAX))
    pick_len = math.min(pick_len, #self.game.pick)

    self.game.pick_y = pick_y0 + 1
    self.game.pick_len = pick_len
end

function M:fix_pick()
    if self.game.pick_len <= 0 then return false end

    local x = self.game.pick_x
    for i = 1, self.game.pick_len do
        local py = self.game.pick_y - (i - 1)
        self:board_set(x, py, self.game.pick[i])
    end

    local new_pick = {}
    for i = self.game.pick_len + 1, #self.game.pick do
        new_pick[#new_pick + 1] = self.game.pick[i]
    end
    self.game.pick_y = self.game.pick_y - self.game.pick_len
    self.game.pick = new_pick
    self.game.pick_len = 1
    return true
end

function M:cause_jammer()
    local num = (math.floor(self.game.turn / JAMMER_TURN) + 2) % 3 + 1
    if self.game.turn > 50 then num = num + 1 end
    for _ = 1, num do
        local x = math.random(2, BOARD_W - 1)
        local y = BOARD_H - self:board_height_at(x)
        if y > 3 and self:board_get(x, y) then
            self:board_set(x, y - 1, { color = Color.Jammer, erased = false })
        end
    end
end

-- === Audio ===

function M:audio_init()
    self.audio = {}
    self.audio.engine = ma.EngineInit()
    self.audio.engine:Start()
    self.audio.engine:SetVolume(0.4)

    self.audio.bgm = ma.SoundInitFromFile(self.audio.engine, "examples/cna/asset/bgm.ogg", 0)
    self.audio.bgm:SetLooping(true)

    self.audio.bgm_off = ma.SoundInitFromFile(self.audio.engine, "examples/cna/asset/bgm_off.ogg", 0)
    self.audio.bgm_off:SetLooping(true)

    self.audio.sfx = {}
    for i = 1, 4 do
        self.audio.sfx[i] = ma.SoundInitFromFile(self.audio.engine, "examples/cna/asset/S" .. i .. ".ogg", 0)
    end

    if self.audio.bgm_off then
        self.audio.bgm_off:Start()
    end
end

function M:audio_play_music(on)
    if not self.audio or not self.audio.bgm or not self.audio.bgm_off then return end
    if on then
        local frame = self.audio.bgm_off:GetTimeInPcmFrames()
        self.audio.bgm:SeekToPcmFrame(frame)
        self.audio.bgm:Start()
        self.audio.bgm_off:Stop()
    else
        local frame = self.audio.bgm:GetTimeInPcmFrames()
        self.audio.bgm_off:SeekToPcmFrame(frame)
        self.audio.bgm_off:Start()
        self.audio.bgm:Stop()
    end
end

function M:audio_play_sfx(idx)
    if not self.audio then return end
    local s = self.audio.sfx[idx]
    if s then
        s:SeekToPcmFrame(0)
        s:Start()
    end
end

function M:audio_cleanup()
    if not self.audio then return end
    self.audio.sfx = {}
    self.audio.bgm = nil
    self.audio.bgm_off = nil
    self.audio.engine = nil
    self.audio = nil
    collectgarbage()
end

-- === Game Update (30 TPS) ===

function M:game_update()
    self.game.ticks = self.game.ticks + 1

    if self.game.step == Step.Title then
        if self.game.clicked then
            self.game.clicked = false
            self.game.step = Step.Move
            self:audio_play_music(true)
        end
    elseif self.game.step == Step.Move then
        local cx, cy = screen_to_board(self.game.mouse_x, self.game.mouse_y)
        self:adjust_pick(cx, cy)
        if self.game.clicked then
            self.game.clicked = false
            if self:fix_pick() then
                self.game.step = Step.FallStone
            end
        end
    elseif self.game.step == Step.FallStone then
        self.game.clicked = false
        if not self:board_fall_stone() then
            local erased = self:board_mark_erase()
            if erased > 0 then
                self.game.sequent_erase = self.game.sequent_erase + 1
                self.game.erase_num = erased
                local s, eq = calc_score(self.game.sequent_erase, erased)
                self.game.score = self.game.score + s
                self.game.score_equation = eq
                if self.game.score > self.game.high_score then
                    self.game.high_score = self.game.score
                end
                local sfx_idx = ((self.game.sequent_erase - 1) % 4) + 1
                self:audio_play_sfx(sfx_idx)
            end
            self.game.wait = (erased > 0) and WAIT_ERASE_FRAME or 1
            self.game.step = Step.WaitErase
        end
    elseif self.game.step == Step.WaitErase then
        self.game.clicked = false
        self.game.wait = self.game.wait - 1
        if self.game.wait <= 0 then
            if self:board_erase() then
                self.game.step = Step.FallStone
            else
                self.game.step = Step.CauseJammer
            end
        end
    elseif self.game.step == Step.CauseJammer then
        self.game.clicked = false
        self.game.turn = self.game.turn + 1
        if self.game.turn % JAMMER_TURN == 0 then
            self:cause_jammer()
        end
        self:fill_pick()
        if self:board_is_full() then
            self.game.step = Step.GameOver
            self:audio_play_music(false)
        else
            self.game.step = Step.Move
            self.game.sequent_erase = 0
            self.game.score_equation = ""
        end
    elseif self.game.step == Step.GameOver then
        if self.game.clicked then
            self.game.clicked = false
            self:game_init()
        end
    end
end

-- === Rendering ===

function M:render_stone(sx, sy, color_idx, erased, wait)
    local u, v, w, h = stone_uv(color_idx)
    local opts = nil

    if erased and wait > 0 then
        local s = (wait / WAIT_ERASE_FRAME)
        s = s * s * s
        opts = {
            rotate = wait,
            scale_x = s,
            scale_y = s,
            origin_x = 5,
            origin_y = 8,
        }
    end

    sprite.draw(self.batch, u, v, w, h, sx, sy, opts)
end

function M:height_average()
    local sum = 0
    for x = 2, BOARD_W - 1 do
        sum = sum + self:board_height_at(x)
    end
    return sum / (BOARD_W - 2)
end

function M:render_board()
    local avg = self:height_average()
    local noise = math.max((avg - 7.0) * 0.2, 0.0)
    for x = 1, BOARD_W do
        for y = 1, BOARD_H do
            local nx = (math.random() - 0.5) * noise
            local ny = (math.random() - 0.5) * noise
            local sx = ORIGIN_X + (x - 1) * STONE_W + nx
            local sy = ORIGIN_Y + (y - 1) * STONE_H + ny
            local bg_color = (y == 1) and Color.Limit or Color.None
            local bu, bv, bw, bh = stone_uv(bg_color)
            sprite.draw(self.batch, bu, bv, bw, bh, sx, sy)
            local s = self.board[x][y]
            if s then
                self:render_stone(sx, sy, s.color, s.erased, self.game.wait)
            end
        end
    end
end

function M:render_pick()
    local avg = self:height_average()
    local noise = math.max((avg - 7.0) * 0.2, 0.0)
    for i = 1, #self.game.pick do
        local s = self.game.pick[i]
        local py = self.game.pick_y - (i - 1)
        if py >= 1 and s then
            local nx = (math.random() - 0.5) * noise
            local ny = (math.random() - 0.5) * noise
            local sx = ORIGIN_X + (self.game.pick_x - 1) * STONE_W + nx
            local sy = ORIGIN_Y + (py - 1) * STONE_H + ny
            self:render_stone(sx, sy, s.color, false, 0)
            if i == self.game.pick_len and self.game.step == Step.Move then
                local cu, cv, cw, ch = stone_uv(Color.Cursor)
                sprite.draw(self.batch, cu, cv, cw, ch, sx, sy)
            end
        end
    end
end

function M:render_number(n, x, y, rot)
    local u, v, w, h = number_uv(n % 10)
    if rot then
        sprite.draw(self.batch, u, v, w, h, x - NUMBER_W, y, { rotate = math.pi / 2 })
    else
        sprite.draw(self.batch, u, v, w, h, x - NUMBER_W, y)
    end
    if n >= 10 then
        self:render_number(math.floor(n / 10), x, y - NUMBER_W, rot)
    end
end

function M:render_equation(equation, x, y, rot)
    local char_to_idx = {
        ["x"] = NUM_CROSS, ["="] = NUM_EQUAL, ["."] = NUM_PERIOD,
    }
    local len = #equation
    for i = 1, len do
        local ch = equation:sub(i, i)
        local idx = char_to_idx[ch] or (string.byte(ch) - string.byte("0"))
        local u, v, w, h = number_uv(idx)
        local dy = y + (-len + i) * NUMBER_W
        if rot then
            sprite.draw(self.batch, u, v, w, h, x - NUMBER_W, dy, { rotate = math.pi / 2 })
        else
            sprite.draw(self.batch, u, v, w, h, x - NUMBER_W, dy)
        end
    end
end

function M:render_alpha(text, x, y)
    for i = 1, #text do
        local ch = text:sub(i, i)
        local u, v, w, h = alpha_uv(ch)
        sprite.draw(self.batch, u, v, w, h, x, y)
        x = x + ALPHA_W
    end
end

function M:render_score()
    if self.game.sequent_erase > 0 then
        local f = self.game.wait / WAIT_ERASE_FRAME
        local dx = f * f * f * NUMBER_W
        self:render_number(self.game.sequent_erase, BOARD_W * STONE_W / 2 + NUMBER_W + dx, 0, false)
        self:render_equation(self.game.score_equation, SCREEN_W, SCREEN_H - 32, true)
    else
        self:render_number(self.game.score, SCREEN_W, SCREEN_H - 32, true)
    end
end

function M:render_title()
    self:render_alpha("cutn", STONE_W * 1.5, STONE_H * 3)
    self:render_alpha("align", STONE_W * 2.5, STONE_H * 4)
    self:render_alpha("click", STONE_W * 1.5, STONE_H * 6)
    self:render_alpha("to", STONE_W * 3.5, STONE_H * 7)
    self:render_alpha("cut", STONE_W * 2.5, STONE_H * 8)
    self:render_alpha("neguse", STONE_W * 1.5, STONE_H * 13 + 1)
end

function M:render_game_over()
    local bx = BOARD_W * STONE_W / 2 - NUMBER_W
    local by = STONE_H * 3
    local end_indices = { NUM_E, NUM_N, NUM_D }
    for i = 1, 3 do
        local ny = (math.cos((self.game.ticks + (i - 1)) * 0.1) + 1.0) * BOARD_H * STONE_H * 0.25
        local u, v, w, h = number_uv(end_indices[i])
        sprite.draw(self.batch, u, v, w, h, bx + NUMBER_W * (i - 1), by + ny)
    end
end

-- === Callbacks ===

function M:init()
    gfx.Setup(gfx.Desc({
        environment = glue.Environment(),
    }))

    self.tex_result = texture.load("examples/cna/asset/texture.png", {
        filter_min = gfx.Filter.NEAREST,
        filter_mag = gfx.Filter.NEAREST,
        wrap_u = gfx.Wrap.CLAMP_TO_EDGE,
        wrap_v = gfx.Wrap.CLAMP_TO_EDGE,
    })
    if not self.tex_result then
        log.error("Failed to load texture atlas")
        return
    end

    self.tex_w = 128
    self.tex_h = 128
    self.batch = sprite.new_batch(self.tex_result, self.tex_w, self.tex_h, SCREEN_W, SCREEN_H)

    local ok, err = pcall(self.audio_init, self)
    if not ok then
        log.warn("audio init skipped: " .. tostring(err))
    end

    self:game_init()
    self.time_acc = 0

    log.info("cut'n'align init complete (" .. self.tex_w .. "x" .. self.tex_h .. " atlas)")
end

function M:frame()
    if not self.batch then return end

    local frame_dt = app.FrameDuration()
    self.time_acc = (self.time_acc or 0) + frame_dt
    while self.time_acc >= TICK_DT do
        self.time_acc = self.time_acc - TICK_DT
        self:game_update()
    end

    gfx.BeginPass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = 0.502, g = 0.502, b = 0.502, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.Swapchain(),
    }))

    self:render_board()
    if self.game.step ~= Step.Title then
        self:render_pick()
        self:render_score()
    end
    if self.game.step == Step.GameOver then
        self:render_game_over()
    end
    if self.game.step == Step.Title then
        self:render_title()
        self:render_number(self.game.high_score, SCREEN_W, SCREEN_H - 32, true)
    end

    sprite.flush(self.batch)

    gfx.EndPass()
    gfx.Commit()
end

function M:event(ev)
    local scale_x = SCREEN_W / app.Widthf()
    local scale_y = SCREEN_H / app.Heightf()

    if ev.type == app.EventType.MOUSE_MOVE then
        self.game.mouse_x = ev.mouse_x * scale_x
        self.game.mouse_y = ev.mouse_y * scale_y
    elseif ev.type == app.EventType.MOUSE_DOWN then
        self.game.mouse_x = ev.mouse_x * scale_x
        self.game.mouse_y = ev.mouse_y * scale_y
        self.game.clicked = true
    elseif ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.Q or ev.key_code == app.Keycode.ESCAPE then
            app.Quit()
        end
    end
end

function M:cleanup()
    self:audio_cleanup()
    if self.batch then sprite.destroy_batch(self.batch); self.batch = nil end
    sprite.shutdown()
    if self.tex_result then
        self.tex_result.img:destroy()
        self.tex_result.view:destroy()
        self.tex_result.smp:destroy()
        self.tex_result = nil
    end
    gfx.Shutdown()
    log.info("cut'n'align cleanup")
end

-- === Unit Tests ===

local test = require("lib.test")

local function new_test_instance()
    return setmetatable({}, { __index = M })
end

test.run("cna", {
    calc_score = function()
        local s, eq = calc_score(1, 3)
        assert(s == 6, "score: expected 6, got " .. tostring(s))
        assert(eq == "2x3=6.", "eq: expected '2x3=6.', got " .. tostring(eq))
    end,

    board_height = function()
        local g = new_test_instance()
        g:board_init()
        assert(g:board_height_at(2) == 0, "empty column should be 0")
        g:board_set(2, 2, { color = Color.Red, erased = false })
        assert(g:board_height_at(2) == 14, "height with stone at y=2: expected 14, got " .. tostring(g:board_height_at(2)))
    end,

    board_mark_erase = function()
        -- Go coords (0-based) → Lua coords (1-based): +1
        local cases = {
            { name = "horizontal", cells = {
                { 2, 2, Color.Red, true },
                { 3, 2, Color.Red, true },
                { 4, 2, Color.Red, true },
                { 5, 2, Color.Green, false },
            }},
            { name = "horizontal not", cells = {
                { 2, 2, Color.Red, false },
                { 3, 2, Color.Red, false },
                { 4, 2, Color.Green, false },
                { 5, 2, Color.Red, false },
            }},
            { name = "vertical", cells = {
                { 2, 2, Color.Red, true },
                { 2, 3, Color.Red, true },
                { 2, 4, Color.Red, true },
                { 2, 5, Color.Green, false },
            }},
            { name = "vertical not", cells = {
                { 2, 2, Color.Red, false },
                { 2, 3, Color.Red, false },
                { 2, 4, Color.Green, false },
                { 2, 5, Color.Red, false },
            }},
            { name = "cross right down", cells = {
                { 2, 2, Color.Red, true },
                { 3, 3, Color.Red, true },
                { 4, 4, Color.Red, true },
                { 5, 5, Color.Green, false },
            }},
            { name = "cross right down 2", cells = {
                { 4, 2, Color.Red, true },
                { 5, 3, Color.Red, true },
                { 6, 4, Color.Red, true },
            }},
            { name = "cross right up", cells = {
                { 2, 5, Color.Red, true },
                { 3, 4, Color.Red, true },
                { 4, 3, Color.Red, true },
                { 5, 2, Color.Green, false },
            }},
            { name = "cross right up 2", cells = {
                { 4, 10, Color.Red, true },
                { 5, 9, Color.Red, true },
                { 6, 8, Color.Red, true },
            }},
            { name = "jammer", cells = {
                { 2, 4, Color.Red, true },
                { 3, 4, Color.Red, true },
                { 4, 4, Color.Red, true },
                { 5, 4, Color.Jammer, true },
            }},
        }
        for _, cs in ipairs(cases) do
            local g = new_test_instance()
            g:board_init()
            for _, c in ipairs(cs.cells) do
                g:board_set(c[1], c[2], { color = c[3], erased = false })
            end
            g:board_mark_erase()
            for _, c in ipairs(cs.cells) do
                local s = g:board_get(c[1], c[2])
                assert(s, cs.name .. ": stone missing at " .. c[1] .. "," .. c[2])
                assert(s.erased == c[4],
                    cs.name .. ": erased mismatch at " .. c[1] .. "," .. c[2]
                    .. " expected " .. tostring(c[4]) .. " got " .. tostring(s.erased))
            end
        end
    end,

    adjust_pick = function()
        -- Go test cases with 1 cell, converted to Lua 1-based coords
        -- Go (x,y) → Lua (x+1, y+1); Go PickX/PickY → Lua pick_x/pick_y = Go+1
        local cases = {
            { name = "just+1", cell = { 2, PICK_MAX + 2, Color.Red },
              picks = {
                { cx = 2, cy = PICK_MAX + 1, px = 2, py = PICK_MAX, pl = 0 },
                { cx = 2, cy = PICK_MAX,     px = 2, py = PICK_MAX, pl = 1 },
                { cx = 2, cy = PICK_MAX - 1, px = 2, py = PICK_MAX, pl = 2 },
            }},
            { name = "just", cell = { 2, PICK_MAX + 1, Color.Red },
              picks = {
                { cx = 2, cy = PICK_MAX + 1, px = 2, py = PICK_MAX - 1, pl = 0 },
                { cx = 2, cy = PICK_MAX,     px = 2, py = PICK_MAX - 1, pl = 0 },
                { cx = 2, cy = PICK_MAX - 1, px = 2, py = PICK_MAX - 1, pl = 1 },
                { cx = 2, cy = PICK_MAX - 2, px = 2, py = PICK_MAX - 1, pl = 2 },
            }},
            { name = "just-1", cell = { 2, PICK_MAX, Color.Red },
              picks = {
                { cx = 2, cy = PICK_MAX + 1, px = 2, py = PICK_MAX - 2, pl = 0 },
                { cx = 2, cy = PICK_MAX,     px = 2, py = PICK_MAX - 2, pl = 0 },
                { cx = 2, cy = PICK_MAX - 1, px = 2, py = PICK_MAX - 2, pl = 0 },
                { cx = 2, cy = PICK_MAX - 2, px = 2, py = PICK_MAX - 2, pl = 1 },
                { cx = 2, cy = PICK_MAX - 3, px = 2, py = PICK_MAX - 2, pl = 2 },
            }},
            { name = "full+1", cell = { 2, 3, Color.Red },
              picks = {
                { cx = 2, cy = 3, px = 2, py = 1, pl = 0 },
                { cx = 2, cy = 2, px = 2, py = 1, pl = 0 },
                { cx = 2, cy = 1, px = 2, py = 1, pl = 1 },
            }},
            { name = "full", cell = { 2, 2, Color.Red },
              picks = {
                { cx = 2, cy = 2, px = 2, py = 0, pl = 0 },
                { cx = 2, cy = 1, px = 2, py = 0, pl = 0 },
                { cx = 2, cy = 0, px = 2, py = 0, pl = 0 },
            }},
        }
        for _, cs in ipairs(cases) do
            for _, p in ipairs(cs.picks) do
                local g = new_test_instance()
                g:board_init()
                g.game = { pick = {}, pick_x = 0, pick_y = 0, pick_len = 0 }
                for i = 1, PICK_MAX do
                    g.game.pick[i] = { color = Color.Red, erased = false }
                end
                g:board_set(cs.cell[1], cs.cell[2], { color = cs.cell[3], erased = false })
                g:adjust_pick(p.cx, p.cy)
                assert(g.game.pick_x == p.px,
                    cs.name .. " pick_x: expected " .. p.px .. " got " .. g.game.pick_x)
                assert(g.game.pick_y == p.py,
                    cs.name .. " pick_y: expected " .. p.py .. " got " .. g.game.pick_y)
                assert(g.game.pick_len == p.pl,
                    cs.name .. " pick_len: expected " .. p.pl .. " got " .. g.game.pick_len)
            end
        end
    end,
})

return M
