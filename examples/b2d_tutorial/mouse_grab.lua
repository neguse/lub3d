local app = require("sokol.app")
local b2d = require("b2d")
local draw = require("examples.b2d_tutorial.draw")

local grab = {}
local joint_id = nil
local target_x, target_y = 0, 0

function grab.reset()
    joint_id = nil
end

function grab.event(ev, world_id, ground_id, camera)
    if ev.type == app.EventType.MOUSE_DOWN and ev.mouse_button == app.Mousebutton.LEFT then
        local wx, wy = camera.screen_to_world(ev.mouse_x, ev.mouse_y)
        local half = 0.1
        local query_aabb = { { wx - half, wy - half }, { wx + half, wy + half } }
        local filter = b2d.default_query_filter()
        local found_body = nil
        b2d.world_overlap_aabb(world_id, query_aabb, filter, function(shape_id)
            local body = b2d.shape_get_body(shape_id)
            if b2d.body_get_type(body) == b2d.BodyType.DYNAMIC_BODY then
                found_body = body
                return false
            end
            return true
        end)
        if found_body then
            local def = b2d.default_mouse_joint_def()
            def.body_id_a = ground_id
            def.body_id_b = found_body
            def.target = { wx, wy }
            def.hertz = 5.0
            def.damping_ratio = 0.7
            def.max_force = 1000 * b2d.body_get_mass(found_body)
            joint_id = b2d.create_mouse_joint(world_id, def)
            b2d.body_set_awake(found_body, true)
            target_x, target_y = wx, wy
        end

    elseif ev.type == app.EventType.MOUSE_MOVE and joint_id then
        local wx, wy = camera.screen_to_world(ev.mouse_x, ev.mouse_y)
        b2d.mouse_joint_set_target(joint_id, { wx, wy })
        target_x, target_y = wx, wy

    elseif ev.type == app.EventType.MOUSE_UP and ev.mouse_button == app.Mousebutton.LEFT then
        if joint_id then
            b2d.destroy_joint(joint_id)
            joint_id = nil
        end
    end
end

function grab.render()
    if joint_id and b2d.joint_is_valid(joint_id) then
        local body_b = b2d.joint_get_body_b(joint_id)
        local pos = b2d.body_get_position(body_b)
        draw.line(pos[1], pos[2], target_x, target_y, 0.8, 0.8, 0.8)
    end
end

return grab
