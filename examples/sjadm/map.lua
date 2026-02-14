local b2d = require("b2d")
local gl = require("sokol.gl")
local font = require("examples.hakonotaiatari.font")
local item_mod = require("examples.sjadm.item")
local checkpoint_mod = require("examples.sjadm.checkpoint")
local mapdata = require("examples.sjadm.mapdata")

local map = {}
map.__index = map

local function rotated(x, y, angle)
    local nx = x * math.cos(angle) - y * math.sin(angle)
    local ny = x * math.sin(angle) + y * math.cos(angle)
    return nx, ny
end

function map.new(world_id, registry)
    local bodies = {}
    local kills = {}
    local items = {}
    local orig_items = {}
    local checkpoints = {}
    local texts = {}
    local start_point = nil

    for _, layer in ipairs(mapdata.layers) do
        if layer.name == "platform" then
            for _, obj in ipairs(layer.objects) do
                if obj.shape == "rectangle" then
                    local angle = -math.rad(obj.rotation)
                    local offx, offy = rotated(obj.width / 2, -obj.height / 2, angle)
                    local cx, cy = obj.x + offx, -obj.y + offy

                    local body_def = b2d.default_body_def()
                    body_def.position = { cx, cy }
                    body_def.rotation = { math.cos(angle), math.sin(angle) }
                    local body_id = b2d.create_body(world_id, body_def)

                    local shape_def = b2d.default_shape_def()
                    local box = b2d.make_box(obj.width / 2, obj.height / 2)

                    if obj.type == "kill" then
                        shape_def.enable_contact_events = true
                        local shape_id = b2d.create_polygon_shape(body_id, shape_def, box)
                        local entity = { get_type = function() return "K" end }
                        registry[tostring(shape_id)] = entity
                        table.insert(kills,
                            { body_id = body_id, cx = cx, cy = cy, hw = obj.width / 2, hh = obj.height / 2, angle = angle })
                    elseif obj.type == "start" then
                        shape_def.is_sensor = true
                        shape_def.enable_sensor_events = true
                        local shape_id = b2d.create_polygon_shape(body_id, shape_def, box)
                        local entity = { get_type = function() return "S" end }
                        registry[tostring(shape_id)] = entity
                    elseif obj.type == "goal" then
                        shape_def.is_sensor = true
                        shape_def.enable_sensor_events = true
                        local shape_id = b2d.create_polygon_shape(body_id, shape_def, box)
                        local entity = { get_type = function() return "G" end }
                        registry[tostring(shape_id)] = entity
                    else
                        -- normal platform wall (no entity needed, contact with nil entity = wall)
                        shape_def.enable_contact_events = true
                        b2d.create_polygon_shape(body_id, shape_def, box)
                        table.insert(bodies,
                            { body_id = body_id, cx = cx, cy = cy, hw = obj.width / 2, hh = obj.height / 2, angle = angle })
                    end
                elseif obj.shape == "point" and obj.type == "entry" then
                    start_point = { x = obj.x, y = -obj.y }
                elseif obj.shape == "point" and (obj.type == "itemJump" or obj.type == "itemDash") then
                    table.insert(orig_items, obj)
                elseif obj.shape == "point" and obj.type == "checkpoint" then
                    table.insert(checkpoints, checkpoint_mod.new(world_id, obj.x, -obj.y, registry))
                elseif obj.shape == "text" then
                    table.insert(texts, obj)
                end
            end
        end
    end

    return setmetatable({
        world_id = world_id,
        registry = registry,
        bodies = bodies,
        kills = kills,
        items = items,
        orig_items = orig_items,
        checkpoints = checkpoints,
        texts = texts,
        start_point = start_point,
        reset_required = true,
    }, map)
end

function map:get_start_point()
    return self.start_point.x, self.start_point.y
end

function map:update()
    if self.reset_required then
        self.reset_required = false
        -- destroy old items
        for _, it in ipairs(self.items) do
            it:destroy(self.registry)
        end
        self.items = {}
        -- create new items
        for _, obj in ipairs(self.orig_items) do
            local type = nil
            if obj.type == "itemJump" then
                type = "J"
            elseif obj.type == "itemDash" then
                type = "D"
            end
            if type then
                table.insert(self.items, item_mod.new(self.world_id, obj.x, -obj.y, type, self.registry))
            end
        end
    end

    -- remove consumed items
    local i = 1
    while i <= #self.items do
        if self.items[i]:is_consumed() then
            self.items[i]:destroy(self.registry)
            table.remove(self.items, i)
        else
            i = i + 1
        end
    end
end

function map:reset_items()
    self.reset_required = true
end

local function draw_rotated_box(cx, cy, hw, hh, angle, r, g, b, mode)
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    local dx = { -hw, hw, hw, -hw }
    local dy = { -hh, -hh, hh, hh }
    local vx, vy = {}, {}
    for i = 1, 4 do
        vx[i] = cx + dx[i] * cos_a - dy[i] * sin_a
        vy[i] = cy + dx[i] * sin_a + dy[i] * cos_a
    end
    if mode == "fill" then
        gl.begin_quads()
        gl.c3f(r, g, b)
        for i = 1, 4 do
            gl.v2f(vx[i], vy[i])
        end
        gl["end"]()
    else
        gl.begin_lines()
        gl.c3f(r, g, b)
        for i = 1, 4 do
            local j = (i % 4) + 1
            gl.v2f(vx[i], vy[i])
            gl.v2f(vx[j], vy[j])
        end
        gl["end"]()
    end
end

function map:render()
    -- platforms
    for _, b in ipairs(self.bodies) do
        draw_rotated_box(b.cx, b.cy, b.hw, b.hh, b.angle, 1, 1, 1, "fill")
    end
    -- kill zones (red)
    for _, k in ipairs(self.kills) do
        draw_rotated_box(k.cx, k.cy, k.hw, k.hh, k.angle, 1, 0, 0, "fill")
    end
    -- items
    for _, it in ipairs(self.items) do
        it:render()
    end
    -- checkpoints
    for _, cp in ipairs(self.checkpoints) do
        cp:render()
    end
    -- texts (rendered in world space using KST32B vector font)
    -- Original LOVE2D: love.graphics.print(text.text, text.x, -text.y, 0, 4, -4)
    -- LOVE2D Vera Sans 12px, sx=4,sy=-4 → height 48px, char width ~28px.
    -- KST32B: height≈0.78, pitch=1.0. scale=60 for height, sx=0.42 for width.
    local text_scale = 60
    local text_sx = 0.42
    local text_ox = 0.5 * text_scale * text_sx
    local text_oy = -0.375 * text_scale
    for _, text in ipairs(self.texts) do
        gl.push_matrix()
        gl.translate(text.x + text_ox, -text.y + text_oy, 0)
        gl.scale(text_sx, 1, 1)
        font.draw_text(text.text, 0, 0, text_scale, 1, 1, 1)
        gl.pop_matrix()
    end
end

return map
