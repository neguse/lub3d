-- Benchmark: glm Lua (table) vs C (HandmadeMath userdata)
-- Measures per-operation cost side-by-side

local stm = require("sokol.time")
local util = require("lib.util")
-- Note: glm_c (C userdata) still uses PascalCase API (Pack, Vec3, etc.)
-- glm_lua (lib/glm.lua) uses snake_case API (pack, vec3, etc.)

local M = {}
M.window_title = "bench_glm"

local ITERATIONS <const> = 100000
local WARMUP <const> = 1000

local function bench(label, n, fn)
    for _ = 1, WARMUP do fn() end
    local t0 = stm.now()
    for _ = 1, n do fn() end
    local elapsed = stm.ms(stm.diff(stm.now(), t0))
    local per_iter = elapsed / n * 1000
    return per_iter, elapsed
end

local function bench_pair(label, n, fn_lua, fn_c)
    local lua_us, lua_ms = bench(label, n, fn_lua)
    local c_us, c_ms = bench(label, n, fn_c)
    local speedup = lua_us / c_us
    print(string.format("  %-20s  Lua %7.1f us  C %7.1f us  (%.1fx)", label, lua_us, c_us, speedup))
end

-- pack_uniforms for Lua table-based glm
local function pack_uniforms_lua(glm, mvp, model, r, g, b, a)
    local data = {}
    for i = 1, 16 do data[i] = mvp[i] end
    for i = 1, 16 do data[16 + i] = model[i] end
    data[33] = r
    data[34] = g
    data[35] = b
    data[36] = a or 1.0
    data[37] = 0
    data[38] = 0
    data[39] = 800
    data[40] = 800
    return util.pack_floats(data)
end

-- pack_uniforms for C userdata glm (uses mat4:pack())
local function pack_uniforms_c(glm, mvp, model, r, g, b, a)
    local mvp_bin = mvp:pack()
    local model_bin = model:pack()
    local extra = string.pack("ffffffff", r, g, b, a or 1.0, 0, 0, 800, 800)
    return mvp_bin .. model_bin .. extra
end

function M:init()
    stm.setup()

    -- Load both implementations
    -- Force-reload lib.glm as pure Lua by clearing the C module from package.loaded
    local glm_c = require("lib.glm") -- This is the C module (registered by lub3d_lua.c)
    package.loaded["lib.glm"] = nil
    -- Load pure Lua implementation by running the file directly
    local glm_lua = dofile("lib/glm.lua")

    print(string.format("=== Lua vs C benchmark (%d iterations) ===\n", ITERATIONS))

    -- Setup test data for each implementation
    -- Both use snake_case API
    local function setup_lua(g)
        local pos = g.vec3(100, 0, 200)
        local size = g.vec3(30, 30, 30)
        local angle = 1.57
        local axis = g.vec3(0, 1, 0)
        local proj = g.perspective(math.rad(45), 1.0, 1.0, 5000.0)
        local view = g.lookat(g.vec3(0, 500, 500), g.vec3(0, 0, 0), g.vec3(0, 1, 0))
        local model = g.translate(pos) * g.rotate(angle, axis) * g.scale(size)
        local mvp = proj * view * model
        return {
            pos = pos,
            size = size,
            angle = angle,
            axis = axis,
            proj = proj,
            view = view,
            model = model,
            mvp = mvp,
        }
    end

    local function setup_c(g)
        local pos = g.vec3(100, 0, 200)
        local size = g.vec3(30, 30, 30)
        local angle = 1.57
        local axis = g.vec3(0, 1, 0)
        local proj = g.perspective(math.rad(45), 1.0, 1.0, 5000.0)
        local view = g.lookat(g.vec3(0, 500, 500), g.vec3(0, 0, 0), g.vec3(0, 1, 0))
        local model = g.translate(pos) * g.rotate(angle, axis) * g.scale(size)
        local mvp = proj * view * model
        return {
            pos = pos,
            size = size,
            angle = angle,
            axis = axis,
            proj = proj,
            view = view,
            model = model,
            mvp = mvp,
        }
    end

    local dl = setup_lua(glm_lua)
    local dc = setup_c(glm_c)

    collectgarbage("restart")
    collectgarbage("collect")

    print("--- GC enabled ---")

    bench_pair("alloc vec3()", ITERATIONS,
        function() local _ = glm_lua.vec3(1, 2, 3) end,
        function() local _ = glm_c.vec3(1, 2, 3) end)

    bench_pair("alloc mat4()", ITERATIONS,
        function() local _ = glm_lua.mat4() end,
        function() local _ = glm_c.mat4() end)

    bench_pair("translate", ITERATIONS,
        function() glm_lua.translate(dl.pos) end,
        function() glm_c.translate(dc.pos) end)

    bench_pair("rotate", ITERATIONS,
        function() glm_lua.rotate(dl.angle, dl.axis) end,
        function() glm_c.rotate(dc.angle, dc.axis) end)

    bench_pair("mat4*mat4", ITERATIONS,
        function() local _ = dl.proj * dl.view end,
        function() local _ = dc.proj * dc.view end)

    bench_pair("model (T*R*S)", ITERATIONS,
        function() local _ = glm_lua.translate(dl.pos) * glm_lua.rotate(dl.angle, dl.axis) * glm_lua.scale(dl.size) end,
        function() local _ = glm_c.translate(dc.pos) * glm_c.rotate(dc.angle, dc.axis) * glm_c.scale(dc.size) end)

    bench_pair("full pipeline", ITERATIONS,
        function()
            local m = glm_lua.translate(dl.pos) * glm_lua.rotate(dl.angle, dl.axis) * glm_lua.scale(dl.size)
            local mv = dl.proj * dl.view * m
            pack_uniforms_lua(glm_lua, mv, m, 1.0, 0.5, 0.2, 1.0)
        end,
        function()
            local m = glm_c.translate(dc.pos) * glm_c.rotate(dc.angle, dc.axis) * glm_c.scale(dc.size)
            local mv = dc.proj * dc.view * m
            pack_uniforms_c(glm_c, mv, m, 1.0, 0.5, 0.2, 1.0)
        end)

    print("\n--- GC stopped ---")
    collectgarbage("collect")
    collectgarbage("stop")

    bench_pair("alloc vec3()", ITERATIONS,
        function() local _ = glm_lua.vec3(1, 2, 3) end,
        function() local _ = glm_c.vec3(1, 2, 3) end)

    bench_pair("alloc mat4()", ITERATIONS,
        function() local _ = glm_lua.mat4() end,
        function() local _ = glm_c.mat4() end)

    bench_pair("model (T*R*S)", ITERATIONS,
        function() local _ = glm_lua.translate(dl.pos) * glm_lua.rotate(dl.angle, dl.axis) * glm_lua.scale(dl.size) end,
        function() local _ = glm_c.translate(dc.pos) * glm_c.rotate(dc.angle, dc.axis) * glm_c.scale(dc.size) end)

    bench_pair("full pipeline", ITERATIONS,
        function()
            local m = glm_lua.translate(dl.pos) * glm_lua.rotate(dl.angle, dl.axis) * glm_lua.scale(dl.size)
            local mv = dl.proj * dl.view * m
            pack_uniforms_lua(glm_lua, mv, m, 1.0, 0.5, 0.2, 1.0)
        end,
        function()
            local m = glm_c.translate(dc.pos) * glm_c.rotate(dc.angle, dc.axis) * glm_c.scale(dc.size)
            local mv = dc.proj * dc.view * m
            pack_uniforms_c(glm_c, mv, m, 1.0, 0.5, 0.2, 1.0)
        end)

    collectgarbage("restart")

    print("\n=== done ===")
end

function M:frame()
end

function M:cleanup()
end

return M
