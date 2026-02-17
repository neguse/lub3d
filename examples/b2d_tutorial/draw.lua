local gl = require("sokol.gl")
local b2d = require("b2d")

local draw = {}
local CIRCLE_SEGMENTS <const> = 24

local function transform_point(lx, ly, pos, cos_a, sin_a)
    return pos[1] + lx * cos_a - ly * sin_a,
        pos[2] + lx * sin_a + ly * cos_a
end

function draw.circle_outline(cx, cy, radius, angle, r, g, b)
    gl.begin_line_strip()
    gl.c3f(r, g, b)
    for i = 0, CIRCLE_SEGMENTS do
        local a = (i / CIRCLE_SEGMENTS) * math.pi * 2
        gl.v2f(cx + math.cos(a) * radius, cy + math.sin(a) * radius)
    end
    gl["end"]()
    gl.begin_lines()
    gl.c3f(r, g, b)
    gl.v2f(cx, cy)
    gl.v2f(cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)
    gl["end"]()
end

function draw.filled_polygon(verts, r, g, b)
    if #verts < 3 then return end
    gl.begin_triangles()
    gl.c3f(r, g, b)
    for i = 2, #verts - 1 do
        gl.v2f(verts[1][1], verts[1][2])
        gl.v2f(verts[i][1], verts[i][2])
        gl.v2f(verts[i + 1][1], verts[i + 1][2])
    end
    gl["end"]()
end

function draw.polygon_outline(verts, r, g, b)
    if #verts < 2 then return end
    gl.begin_line_strip()
    gl.c3f(r, g, b)
    for _, v in ipairs(verts) do
        gl.v2f(v[1], v[2])
    end
    gl.v2f(verts[1][1], verts[1][2])
    gl["end"]()
end

function draw.line(x1, y1, x2, y2, r, g, b)
    gl.begin_lines()
    gl.c3f(r, g, b)
    gl.v2f(x1, y1)
    gl.v2f(x2, y2)
    gl["end"]()
end

function draw.point(x, y, size, r, g, b)
    local hs = size / 2
    gl.begin_quads()
    gl.c3f(r, g, b)
    gl.v2f(x - hs, y - hs)
    gl.v2f(x + hs, y - hs)
    gl.v2f(x + hs, y + hs)
    gl.v2f(x - hs, y + hs)
    gl["end"]()
end

local function draw_shape(shape_id, pos, cos_a, sin_a, angle, r, g, b)
    local st = b2d.shape_get_type(shape_id)

    if st == b2d.ShapeType.POLYGON_SHAPE then
        local poly = b2d.shape_get_polygon(shape_id)
        local tverts = {}
        for i = 1, poly.count do
            local lx, ly = poly.vertices[i][1], poly.vertices[i][2]
            local wx, wy = transform_point(lx, ly, pos, cos_a, sin_a)
            tverts[i] = { wx, wy }
        end
        draw.filled_polygon(tverts, r * 0.6, g * 0.6, b * 0.6)
        draw.polygon_outline(tverts, r, g, b)

    elseif st == b2d.ShapeType.CIRCLE_SHAPE then
        local circle = b2d.shape_get_circle(shape_id)
        local cx, cy = transform_point(
            circle.center[1], circle.center[2], pos, cos_a, sin_a)
        draw.circle_outline(cx, cy, circle.radius, angle, r, g, b)

    elseif st == b2d.ShapeType.CAPSULE_SHAPE then
        local cap = b2d.shape_get_capsule(shape_id)
        local x1, y1 = transform_point(cap.center1[1], cap.center1[2], pos, cos_a, sin_a)
        local x2, y2 = transform_point(cap.center2[1], cap.center2[2], pos, cos_a, sin_a)
        draw.circle_outline(x1, y1, cap.radius, 0, r, g, b)
        draw.circle_outline(x2, y2, cap.radius, 0, r, g, b)
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            local nx, ny = -dy / len * cap.radius, dx / len * cap.radius
            draw.line(x1 + nx, y1 + ny, x2 + nx, y2 + ny, r, g, b)
            draw.line(x1 - nx, y1 - ny, x2 - nx, y2 - ny, r, g, b)
        end

    elseif st == b2d.ShapeType.SEGMENT_SHAPE then
        local seg = b2d.shape_get_segment(shape_id)
        local x1, y1 = transform_point(seg.point1[1], seg.point1[2], pos, cos_a, sin_a)
        local x2, y2 = transform_point(seg.point2[1], seg.point2[2], pos, cos_a, sin_a)
        draw.line(x1, y1, x2, y2, r, g, b)
    end
end

function draw.bodies(entries)
    for _, entry in ipairs(entries) do
        local body_id = entry.body_id
        if not b2d.body_is_valid(body_id) then goto continue end

        local pos = b2d.body_get_position(body_id)
        local rot = b2d.body_get_rotation(body_id)
        local cos_a, sin_a = rot[1], rot[2]
        local angle = b2d.rot_get_angle(rot)
        local r, g, b_col = entry.color[1], entry.color[2], entry.color[3]

        if not b2d.body_is_awake(body_id) then
            r, g, b_col = r * 0.5, g * 0.5, b_col * 0.5
        end

        local shapes = b2d.body_get_shapes(body_id)
        for _, shape_id in ipairs(shapes) do
            draw_shape(shape_id, pos, cos_a, sin_a, angle, r, g, b_col)
        end

        ::continue::
    end
end

function draw.filled_circle(cx, cy, radius, r, g, b)
    gl.begin_triangles()
    gl.c3f(r, g, b)
    for i = 0, CIRCLE_SEGMENTS - 1 do
        local a1 = (i / CIRCLE_SEGMENTS) * math.pi * 2
        local a2 = ((i + 1) / CIRCLE_SEGMENTS) * math.pi * 2
        gl.v2f(cx, cy)
        gl.v2f(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius)
        gl.v2f(cx + math.cos(a2) * radius, cy + math.sin(a2) * radius)
    end
    gl["end"]()
end

function draw.smiley(cx, cy, radius, angle, r, g, b)
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    local function local_to_world(lx, ly)
        return cx + lx * cos_a - ly * sin_a,
            cy + lx * sin_a + ly * cos_a
    end

    -- Circle outline
    draw.circle_outline(cx, cy, radius, angle, r, g, b)

    -- Eyes (two dots)
    local eye_r = radius * 0.12
    local ex1, ey1 = local_to_world(-radius * 0.3, radius * 0.3)
    local ex2, ey2 = local_to_world(radius * 0.3, radius * 0.3)
    draw.filled_circle(ex1, ey1, eye_r, r, g, b)
    draw.filled_circle(ex2, ey2, eye_r, r, g, b)

    -- Mouth (arc)
    local mouth_segs = 8
    gl.begin_line_strip()
    gl.c3f(r, g, b)
    for i = 0, mouth_segs do
        local t = i / mouth_segs
        local a = math.pi * 0.2 + t * math.pi * 0.6  -- arc from ~36° to ~144°
        local lx = math.cos(a) * radius * 0.5
        local ly = -math.sin(a) * radius * 0.4 - radius * 0.1
        local wx, wy = local_to_world(lx, ly)
        gl.v2f(wx, wy)
    end
    gl["end"]()
end

function draw.rect_outline(x1, y1, x2, y2, r, g, b)
    draw.polygon_outline({
        { x1, y1 }, { x2, y1 }, { x2, y2 }, { x1, y2 },
    }, r, g, b)
end

function draw.ground(ground_id)
    draw.bodies({ { body_id = ground_id, color = { 0.3, 0.5, 0.3 } } })
end

return draw
