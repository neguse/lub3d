local app = require("sokol.app")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gl = require("sokol.gl")
local stm = require("sokol.time")
local imgui = require("imgui")
local b2d = require("b2d")
local draw = require("examples.b2d_tutorial.draw")
local camera = require("examples.b2d_tutorial.camera")
local mouse_grab = require("examples.b2d_tutorial.mouse_grab")

local M = {}
M.width = 1280
M.height = 720
M.window_title = "Box2D Tutorial"

local scene_modules = {
    -- iforce2d advanced topics porting list:
    -- C++ source                                  -> Lua file(s)                          Status
    -- iforce2d_physicsDrivenParticles.h            -> particles.lua                        COMPLETE
    -- physicsDrivenParticles.cpp                   -> terrain_data.lua                     COMPLETE
    -- iforce2d_Trajectories.h                      -> projected_trajectory.lua             COMPLETE
    -- iforce2d_Buoyancy.h                          -> buoyancy.lua                         COMPLETE
    -- iforce2d_Buoyancy_functions.h                -> (inlined in buoyancy/buoyancy_boat)
    -- buoyancy.cpp                                 -> (inlined in buoyancy.lua)
    -- iforce2d_Buoyancy_boat.h                     -> buoyancy_boat.lua                    COMPLETE
    -- buoyancy2.cpp                                -> (inlined in buoyancy_boat.lua)
    -- iforce2d_StickyProjectiles.h                 -> sticky_projectiles.lua               COMPLETE
    -- iforce2d_OneWayWalls.h / _demo.h             -> one_way_walls.lua                    COMPLETE
    -- iforce2d_HovercarSuspension.h                -> suspension.lua                       COMPLETE
    -- iforce2d_TopdownCar.h                        -> top_down_car.lua                     COMPLETE
    -- iforce2d_TopdownCar_singleTire*.h            -> (skipped)
    -- iforce2d_TopdownCarRaceTrack.h / racetrack.json -> (not ported)
    require("examples.b2d_tutorial.scenes.particles"),
    require("examples.b2d_tutorial.scenes.projected_trajectory"),
    require("examples.b2d_tutorial.scenes.buoyancy"),
    require("examples.b2d_tutorial.scenes.buoyancy_boat"),
    require("examples.b2d_tutorial.scenes.sticky_projectiles"),
    require("examples.b2d_tutorial.scenes.one_way_walls"),
    require("examples.b2d_tutorial.scenes.suspension"),
    require("examples.b2d_tutorial.scenes.top_down_car"),
}

local world_id
local ground_id
local current_index = 1
local current_scene
local fps_text = "FPS: --"
local fps_accum = 0
local fps_frames = 0
local last_tick = 0

local function create_world()
    local world_def = b2d.default_world_def()
    world_def.gravity = { 0, -10 }
    world_id = b2d.create_world(world_def)

    local body_def = b2d.default_body_def()
    body_def.position = { 0, -1 }
    ground_id = b2d.create_body(world_id, body_def)
    local shape_def = b2d.default_shape_def()
    shape_def.enable_sensor_events = true
    b2d.create_polygon_shape(ground_id, shape_def, b2d.make_box(40, 1))
end

local function switch_scene(index)
    if current_scene then current_scene:cleanup() end
    if world_id then b2d.destroy_world(world_id) end
    create_world()
    mouse_grab.reset()
    current_index = index
    current_scene = scene_modules[index]
    -- Pass camera ref to scenes that need it
    if current_scene.set_camera then
        current_scene:set_camera(camera)
    end
    current_scene:setup(world_id, ground_id)
    camera.reset()
end

function M:init()
    gfx.setup(gfx.Desc({ environment = glue.environment() }))
    gl.setup(gl.Desc({}))
    stm.setup()
    imgui.setup()
    camera.reset()
    last_tick = stm.now()
    switch_scene(1)
end

function M:frame()
    local dt = app.frame_duration()
    b2d.world_step(world_id, dt, 4)
    current_scene:update(dt)

    imgui.new_frame()

    -- ImGui: Scene selection + controls
    local now = stm.now()
    local elapsed_ms = stm.ms(stm.diff(now, last_tick))
    last_tick = now
    fps_accum = fps_accum + elapsed_ms
    fps_frames = fps_frames + 1
    if fps_accum >= 500 then
        local avg_ms = fps_accum / fps_frames
        fps_text = string.format("FPS: %.1f (%.2f ms)", 1000 / avg_ms, avg_ms)
        fps_accum = 0
        fps_frames = 0
    end

    if imgui.begin_window("Tutorial") then
        imgui.text_unformatted(fps_text)
        imgui.separator()
        imgui.text_unformatted("Scene")
        imgui.begin_child_str_vec2_x_x("SceneList", { 0, 200 },
            imgui.ChildFlags.BORDERS, imgui.WindowFlags.NONE)
        for i, scene in ipairs(scene_modules) do
            local clicked = imgui.selectable_str_bool_x_vec2(
                scene.name .. "##" .. i,
                i == current_index,
                imgui.SelectableFlags.NONE, { 0, 0 })
            if clicked and i ~= current_index then
                switch_scene(i)
            end
        end
        imgui.end_child()

        imgui.separator()
        if imgui.button("Reset") then
            switch_scene(current_index)
        end

        imgui.separator()
        imgui.text_unformatted(current_scene.description)

        imgui.separator()
        current_scene:render_ui()
    end
    imgui.end_window()

    -- Pass 1: Physics world (CLEAR)
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = {
                gfx.ColorAttachmentAction({
                    load_action = gfx.LoadAction.CLEAR,
                    clear_value = gfx.Color({ r = 0.15, g = 0.15, b = 0.2, a = 1.0 }),
                }),
            },
        }),
        swapchain = glue.swapchain(),
    }))
    gl.defaults()
    camera.apply()
    draw.ground(ground_id)
    draw.bodies(current_scene:get_bodies())
    current_scene:render_extra()
    mouse_grab.render()
    gl.draw()
    gfx.end_pass()

    -- Pass 2: ImGui (LOAD)
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { { load_action = gfx.LoadAction.LOAD } },
        }),
        swapchain = glue.swapchain(),
    }))
    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function M:event(ev)
    local consumed = imgui.handle_event(ev)
    -- Always forward keyboard events to scenes (ImGui consumes SPACE, arrows, etc.)
    if consumed
        and ev.type ~= app.EventType.KEY_DOWN
        and ev.type ~= app.EventType.KEY_UP
    then
        return
    end
    camera.event(ev)
    mouse_grab.event(ev, world_id, ground_id, camera)
    current_scene:event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        if ev.key_code == app.Keycode.ESCAPE then app.request_quit() end
    end
end

function M:cleanup()
    if current_scene then current_scene:cleanup() end
    b2d.destroy_world(world_id)
    imgui.shutdown()
    gl.shutdown()
    gfx.shutdown()
end

return M
