-- sleep_test.lua - Headless test for body_def.enable_sleep
-- Verifies that enable_sleep=false prevents bodies from sleeping.
--
-- Usage: build\win-dummy-debug\lub3d-test.exe examples.sleep_test 600

local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local b2d = require("b2d")

local M = {}
M.width = 800
M.height = 600
M.window_title = "Sleep Test"

local world_id
local body_a -- control: default (enable_sleep=true)
local body_b -- bodydef: enable_sleep=false
local body_c -- runtime: body_enable_sleep(body, false) after creation

local frame_count = 0
local a_ever_slept = false
local b_ever_slept = false
local c_ever_slept = false

function M:init()
    gfx.setup(gfx.Desc({ environment = glue.environment() }))

    local world_def = b2d.default_world_def()
    world_def.gravity = { 0, -10 }
    world_id = b2d.create_world(world_def)

    -- Ground
    local ground_def = b2d.default_body_def()
    ground_def.position = { 0, -10 }
    local ground = b2d.create_body(world_id, ground_def)
    local shape_def = b2d.default_shape_def()
    b2d.create_polygon_shape(ground, shape_def, b2d.make_box(50, 10))

    -- Shared shape config
    local function make_shape()
        local sd = b2d.default_shape_def()
        sd.density = 1.0
        local mat = b2d.default_surface_material()
        mat.friction = 0.3
        sd.material = mat
        return sd
    end

    -- Body A: control (default enable_sleep=true)
    local def_a = b2d.default_body_def()
    def_a.type = b2d.BodyType.DYNAMIC_BODY
    def_a.position = { -5, 4 }
    body_a = b2d.create_body(world_id, def_a)
    b2d.create_polygon_shape(body_a, make_shape(), b2d.make_box(1, 1))

    -- Body B: bodydef enable_sleep=false
    local def_b = b2d.default_body_def()
    def_b.type = b2d.BodyType.DYNAMIC_BODY
    def_b.position = { 0, 4 }
    def_b.enable_sleep = false
    body_b = b2d.create_body(world_id, def_b)
    b2d.create_polygon_shape(body_b, make_shape(), b2d.make_box(1, 1))

    -- Body C: runtime disable sleep
    local def_c = b2d.default_body_def()
    def_c.type = b2d.BodyType.DYNAMIC_BODY
    def_c.position = { 5, 4 }
    body_c = b2d.create_body(world_id, def_c)
    b2d.create_polygon_shape(body_c, make_shape(), b2d.make_box(1, 1))
    b2d.body_enable_sleep(body_c, false)

    print("sleep_test: init done")
    print("  A: control (enable_sleep=true)")
    print("  B: body_def.enable_sleep=false")
    print("  C: runtime body_enable_sleep(body, false)")
    print(string.format("  A sleep_enabled=%s", tostring(b2d.body_is_sleep_enabled(body_a))))
    print(string.format("  B sleep_enabled=%s", tostring(b2d.body_is_sleep_enabled(body_b))))
    print(string.format("  C sleep_enabled=%s", tostring(b2d.body_is_sleep_enabled(body_c))))
end

function M:frame()
    b2d.world_step(world_id, 1.0 / 60.0, 4)
    frame_count = frame_count + 1

    local a_awake = b2d.body_is_awake(body_a)
    local b_awake = b2d.body_is_awake(body_b)
    local c_awake = b2d.body_is_awake(body_c)

    if not a_awake then a_ever_slept = true end
    if not b_awake then b_ever_slept = true end
    if not c_awake then c_ever_slept = true end

    -- Progress report every 100 frames
    if frame_count % 100 == 0 then
        print(string.format("  frame %d: A_awake=%s B_awake=%s C_awake=%s",
            frame_count, tostring(a_awake), tostring(b_awake), tostring(c_awake)))
    end

    -- Render (minimal, required for headless loop)
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = 0, g = 0, b = 0, a = 1 }),
                }),
            },
        }),
        swapchain = glue.swapchain(),
    }))
    gfx.end_pass()
    gfx.commit()
end

function M:cleanup()
    print(string.format("\nsleep_test results (after %d frames):", frame_count))
    print(string.format("  A (control, enable_sleep=true):  ever_slept=%s", tostring(a_ever_slept)))
    print(string.format("  B (bodydef, enable_sleep=false): ever_slept=%s", tostring(b_ever_slept)))
    print(string.format("  C (runtime, enable_sleep=false): ever_slept=%s", tostring(c_ever_slept)))

    -- Assertions
    assert(a_ever_slept, "FAIL: A (control) should have slept but didn't")
    assert(not b_ever_slept, "FAIL: B (bodydef enable_sleep=false) slept unexpectedly")
    assert(not c_ever_slept, "FAIL: C (runtime enable_sleep=false) slept unexpectedly")

    print("\nAll assertions passed!")

    b2d.destroy_world(world_id)
    gfx.shutdown()
end

return M
