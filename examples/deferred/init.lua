-- examples/deferred/init.lua
-- Simple Deferred Rendering Pipeline

---@type string?
SCRIPT_DIR = SCRIPT_DIR

---@type fun(path: string): number
get_mtime = get_mtime

-- Add lib/ and deps/ to path (CWD is project root)
package.path = "lib/?.lua;deps/lume/?.lua;examples/deferred/?.lua;" .. package.path

local hotreload = require("hotreload")
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local util = require("util")
local glm = require("glm")
local imgui = require("imgui")
local gpu = require("gpu")

-- Pipeline modules (relative to this directory)
local ctx = require("ctx")
local camera = require("camera")
local light = require("light")
local geometry_pass = require("geometry")
local lighting_pass = require("lighting")

-- Scene data
local meshes = {}
local textures_cache = {}
local default_texture = nil

local function compute_tangent(p1, p2, p3, uv1, uv2, uv3)
    local e1 = { p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3] }
    local e2 = { p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3] }
    local duv1 = { uv2[1] - uv1[1], uv2[2] - uv1[2] }
    local duv2 = { uv3[1] - uv1[1], uv3[2] - uv1[2] }
    local f = duv1[1] * duv2[2] - duv2[1] * duv1[2]
    if math.abs(f) < 0.0001 then f = 1 end
    f = 1.0 / f
    return f * (duv2[2] * e1[1] - duv1[2] * e2[1]),
        f * (duv2[2] * e1[2] - duv1[2] * e2[2]),
        f * (duv2[2] * e1[3] - duv1[2] * e2[3])
end

local function load_model()
    local t0 = os.clock()

    -- Try to load precompiled bytecode if newer than source
    local model
    local base_path = "examples/mill-scene"
    local lua_path = base_path .. ".lua"
    local luac_path = base_path .. ".luac"
    local lua_mtime = get_mtime(lua_path)
    local luac_mtime = get_mtime(luac_path)

    if luac_mtime > 0 and luac_mtime >= lua_mtime then
        -- Load from cache
        util.info("Loading cached bytecode...")
        local chunk, err = loadfile(luac_path)
        if chunk then
            model = chunk()
        else
            util.warn("Failed to load luac: " .. tostring(err))
        end
    end

    if not model then
        -- Load source and cache bytecode
        util.info("Loading source and caching bytecode...")
        local chunk, err = loadfile(lua_path)
        if chunk then
            model = chunk()
            -- Save bytecode cache
            local bytecode = string.dump(chunk)
            local f = io.open(luac_path, "wb")
            if f then
                f:write(bytecode)
                f:close()
                util.info("Saved bytecode cache: " .. luac_path)
            end
        else
            util.error("Failed to load model: " .. tostring(err))
        end
    end
    util.info(string.format("load model: %.3fs", os.clock() - t0))

    local t_tangent, t_vbuf, t_texture = 0, 0, 0

    for mat_name, mesh_data in pairs(model.meshes) do
        local vertices = mesh_data.vertices
        local indices = mesh_data.indices

        -- Compute tangents
        local t1 = os.clock()
        local in_stride = 8
        local vertex_count = #vertices / in_stride
        local tangents = {}
        for i = 0, vertex_count - 1 do
            tangents[i] = { 0, 0, 0 }
        end

        for i = 1, #indices, 3 do
            local i1, i2, i3 = indices[i], indices[i + 1], indices[i + 2]
            local base1, base2, base3 = i1 * in_stride, i2 * in_stride, i3 * in_stride
            -- Inline tangent computation to avoid table allocation
            local p1x, p1y, p1z = vertices[base1 + 1], vertices[base1 + 2], vertices[base1 + 3]
            local p2x, p2y, p2z = vertices[base2 + 1], vertices[base2 + 2], vertices[base2 + 3]
            local p3x, p3y, p3z = vertices[base3 + 1], vertices[base3 + 2], vertices[base3 + 3]
            local uv1u, uv1v = vertices[base1 + 7], vertices[base1 + 8]
            local uv2u, uv2v = vertices[base2 + 7], vertices[base2 + 8]
            local uv3u, uv3v = vertices[base3 + 7], vertices[base3 + 8]
            local e1x, e1y, e1z = p2x - p1x, p2y - p1y, p2z - p1z
            local e2x, e2y, e2z = p3x - p1x, p3y - p1y, p3z - p1z
            local duv1u, duv1v = uv2u - uv1u, uv2v - uv1v
            local duv2u, duv2v = uv3u - uv1u, uv3v - uv1v
            local f = duv1u * duv2v - duv2u * duv1v
            if math.abs(f) < 0.0001 then f = 1 end
            f = 1.0 / f
            local tx = f * (duv2v * e1x - duv1v * e2x)
            local ty = f * (duv2v * e1y - duv1v * e2y)
            local tz = f * (duv2v * e1z - duv1v * e2z)
            local t1, t2, t3 = tangents[i1], tangents[i2], tangents[i3]
            t1[1], t1[2], t1[3] = t1[1] + tx, t1[2] + ty, t1[3] + tz
            t2[1], t2[2], t2[3] = t2[1] + tx, t2[2] + ty, t2[3] + tz
            t3[1], t3[2], t3[3] = t3[1] + tx, t3[2] + ty, t3[3] + tz
        end
        t_tangent = t_tangent + (os.clock() - t1)

        -- Build vertex buffer with tangents
        t1 = os.clock()
        local vparts = {}
        for i = 0, vertex_count - 1 do
            local base = i * in_stride
            local t = tangents[i]
            local len = math.sqrt(t[1] * t[1] + t[2] * t[2] + t[3] * t[3])
            local tx, ty, tz
            if len > 0.0001 then
                tx, ty, tz = t[1] / len, t[2] / len, t[3] / len
            else
                tx, ty, tz = 1, 0, 0
            end
            -- pos(3) + normal(3) + uv(2) + tangent(3) = 11 floats
            vparts[i + 1] = string.pack("fffffffffff",
                vertices[base + 1], vertices[base + 2], vertices[base + 3],
                vertices[base + 4], vertices[base + 5], vertices[base + 6],
                vertices[base + 7], vertices[base + 8],
                tx, ty, tz)
        end
        local vdata = table.concat(vparts)
        local vbuf = gpu.buffer(gfx.BufferDesc({ data = gfx.Range(vdata) }))

        local idata = util.pack_u32(indices)
        local ibuf = gpu.buffer(gfx.BufferDesc({
            usage = { index_buffer = true },
            data = gfx.Range(idata),
        }))
        t_vbuf = t_vbuf + (os.clock() - t1)

        -- Load texture
        t1 = os.clock()
        local tex_view, tex_smp
        local texture_base = "assets/3d-shaders/textures/"
        if mesh_data.textures and #mesh_data.textures > 0 then
            local tex_name = mesh_data.textures[1]
            local tex_info = model.textures[tex_name]
            if tex_info then
                local path = texture_base .. tex_info.path
                if not textures_cache[path] then
                    util.info("Loading texture: " .. path)
                    local view, smp = util.load_texture(path)
                    if view then
                        textures_cache[path] = { view = view, smp = smp }
                    else
                        util.warn("Failed to load: " .. path)
                    end
                end
                if textures_cache[path] then
                    tex_view = textures_cache[path].view
                    tex_smp = textures_cache[path].smp
                end
            end
        end
        t_texture = t_texture + (os.clock() - t1)

        -- Create default white texture if needed
        if not tex_view then
            if not default_texture then
                local white = string.pack("BBBB", 255, 255, 255, 255)
                local img = gpu.image(gfx.ImageDesc({
                    width = 1,
                    height = 1,
                    pixel_format = gfx.PixelFormat.RGBA8,
                    data = { mip_levels = { white } },
                }))
                local view = gpu.view(gfx.ViewDesc({
                    texture = { image = img.handle },
                }))
                local smp = gpu.sampler(gfx.SamplerDesc({
                    min_filter = gfx.Filter.NEAREST,
                    mag_filter = gfx.Filter.NEAREST,
                }))
                default_texture = { img = img, view = view, smp = smp }
            end
            tex_view = default_texture.view.handle
            tex_smp = default_texture.smp.handle
        end

        -- Skip water meshes
        if not mat_name:find("water") and not mat_name:find("Water") then
            table.insert(meshes, {
                vbuf = vbuf,
                ibuf = ibuf,
                num_indices = #indices,
                tex_view = tex_view,
                tex_smp = tex_smp,
            })
        end
    end

    util.info(string.format("tangent: %.3fs, vbuf: %.3fs, texture: %.3fs", t_tangent, t_vbuf, t_texture))
    util.info("Loaded " .. #meshes .. " meshes")
end

function init()
    util.info("Deferred Rendering Pipeline init")
    imgui.setup()

    ctx.init()

    local width, height = app.width(), app.height()
    ctx.ensure_size(width, height)

    load_model()
end

function frame()
    hotreload.update()

    local width, height = app.width(), app.height()
    ctx.ensure_size(width, height)

    -- Camera update
    camera.update()
    local view = camera.view_matrix()
    local proj = camera.projection_matrix(width, height)
    local model_mat = glm.mat4()

    imgui.new_frame()

    -- Reset outputs
    ctx.outputs = {}

    -- Geometry Pass
    geometry_pass.on_pass(ctx, meshes, view, proj, model_mat)

    -- Lighting Pass
    local light_uniforms = light.pack_uniforms(view)
    lighting_pass.on_pass(ctx, light_uniforms)

    -- ImGui (still in lighting pass)
    if imgui.Begin("Deferred Rendering") then
        imgui.Text("Modular Deferred Rendering Pipeline")
        imgui.Separator()
        imgui.Text(string.format("Camera: %.1f, %.1f, %.1f", camera.pos.x, camera.pos.y, camera.pos.z))
        imgui.Text("WASD: Move, Mouse: Look (right-click to capture)")
        imgui.Separator()

        local lx, ly, lz, lchanged = imgui.InputFloat3("Light Pos", light.pos.x, light.pos.y, light.pos.z)
        if lchanged then light.pos = glm.vec3(lx, ly, lz) end

        local lr, lg, lb, lcchanged = imgui.ColorEdit3("Light Color", light.color.x, light.color.y, light.color.z)
        if lcchanged then light.color = glm.vec3(lr, lg, lb) end

        local ar, ag, ab, achanged = imgui.ColorEdit3("Ambient", light.ambient.x, light.ambient.y, light.ambient.z)
        if achanged then light.ambient = glm.vec3(ar, ag, ab) end
    end
    imgui.End()

    imgui.render()
    gfx.end_pass()
    gfx.commit()
end

function cleanup()
    imgui.shutdown()

    -- Destroy pass resources
    lighting_pass.destroy()
    geometry_pass.destroy()
    ctx.destroy()

    -- Destroy mesh resources
    for _, mesh in ipairs(meshes) do
        mesh.vbuf:destroy()
        mesh.ibuf:destroy()
    end
    meshes = {}

    -- Destroy default texture
    if default_texture then
        default_texture.smp:destroy()
        default_texture.view:destroy()
        default_texture.img:destroy()
        default_texture = nil
    end

    util.info("cleanup")
end

function event(ev)
    if imgui.handle_event(ev) then
        return
    end

    if camera.handle_event(ev) then
        return
    end

    if ev.type == app.EventType.KEY_DOWN and ev.key_code == app.Keycode.ESCAPE then
        app.request_quit()
    end
end
