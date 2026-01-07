-- Rendering Pipeline

local hotreload = require("lib.hotreload")
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local app = require("sokol.app")
local util = require("lib.util")
local glm = require("lib.glm")
local imgui = require("imgui")
local gpu = require("lib.gpu")
local pipeline = require("lib.render_pipeline")
local notify = require("lib.notify")

-- Pipeline modules
local ctx = require("examples.rendering.ctx")
local camera = require("examples.rendering.camera")
local light = require("examples.rendering.light")
local geometry_pass = require("examples.rendering.geometry")
local lighting_pass = require("examples.rendering.lighting")

-- Scene data
local meshes = {}
local textures_cache = {}
local default_diffuse = nil
local default_normal = nil
local default_specular = nil

-- ImGui pass (renders UI overlay)
local imgui_pass = {
    name = "imgui",
    get_pass_desc = function()
        return gfx.Pass({
            action = gfx.PassAction({
                colors = { { load_action = gfx.LoadAction.LOAD } },
            }),
            swapchain = glue.swapchain(),
        })
    end,
    execute = function()
        notify.draw(app.width(), app.height())
        imgui.render()
    end,
}

-- Update UI (called before pipeline.execute)
local function update_ui()
    if imgui.Begin("Rendering") then
        imgui.Text("Modular Rendering Pipeline")
        imgui.Separator()
        imgui.Text(string.format("Camera: %.1f, %.1f, %.1f", camera.pos.x, camera.pos.y, camera.pos.z))
        imgui.Text("WASD: Move, Mouse: Look (right-click to capture)")
        imgui.Separator()

        -- Global ambient
        local ar, ag, ab, achanged = imgui.ColorEdit3("Global Ambient",
            light.light_model_ambient.x, light.light_model_ambient.y, light.light_model_ambient.z)
        if achanged then
            light.light_model_ambient = glm.vec4(ar, ag, ab, 1.0)
        end

        imgui.Text(string.format("Active Lights: %d / %d", #light.sources, light.NUMBER_OF_LIGHTS))

        -- Animation controls
        if imgui.TreeNode("Day/Night Cycle") then
            local anim_changed
            light.animate_enabled, anim_changed = imgui.Checkbox("Animate", light.animate_enabled)

            local pitch, pitch_changed = imgui.SliderFloat("Sun Angle", light.sun_pitch, 0, 360)
            if pitch_changed then
                light.sun_pitch = pitch
                light.animate(0)
            end

            local speed, speed_changed = imgui.SliderFloat("Speed", light.animation_speed, 0, 100)
            if speed_changed then
                light.animation_speed = speed
            end

            if imgui.Button("Midday") then light.set_time("midday") end
            imgui.SameLine()
            if imgui.Button("Midnight") then light.set_time("midnight") end

            imgui.TreePop()
        end

        -- Edit each light
        for i, src in ipairs(light.sources) do
            if imgui.TreeNode("Light " .. i) then
                local is_directional = src.position.w == 0
                local is_spot = src.spot_params.y > -1.0

                if is_directional then
                    imgui.Text("Type: Directional")
                    -- Direction (stored negated in position.xyz)
                    local dx, dy, dz, dchanged = imgui.InputFloat3("Direction",
                        -src.position.x, -src.position.y, -src.position.z)
                    if dchanged then
                        local dir = glm.vec3(dx, dy, dz):normalize()
                        src.position = glm.vec4(-dir.x, -dir.y, -dir.z, 0)
                    end
                else
                    imgui.Text(is_spot and "Type: Spotlight" or "Type: Point")
                    local px, py, pz, pchanged = imgui.InputFloat3("Position",
                        src.position.x, src.position.y, src.position.z)
                    if pchanged then
                        src.position = glm.vec4(px, py, pz, src.position.w)
                    end

                    if is_spot then
                        local sdx, sdy, sdz, sdchanged = imgui.InputFloat3("Spot Dir",
                            src.spot_direction.x, src.spot_direction.y, src.spot_direction.z)
                        if sdchanged then
                            local dir = glm.vec3(sdx, sdy, sdz):normalize()
                            src.spot_direction = glm.vec4(dir.x, dir.y, dir.z, src.spot_direction.w)
                        end

                        local exp, expchanged = imgui.SliderFloat("Exponent", src.spot_direction.w, 0, 20)
                        if expchanged then
                            src.spot_direction = glm.vec4(src.spot_direction.x, src.spot_direction.y, src.spot_direction.z, exp)
                        end
                    end

                    -- Attenuation
                    local ac, al, aq, atchanged = imgui.InputFloat3("Atten (c,l,q)",
                        src.attenuation.x, src.attenuation.y, src.attenuation.z)
                    if atchanged then
                        src.attenuation = glm.vec4(ac, al, aq, 0)
                    end
                end

                -- Color (diffuse)
                local cr, cg, cb, cchanged = imgui.ColorEdit3("Color",
                    src.diffuse.x, src.diffuse.y, src.diffuse.z)
                if cchanged then
                    src.color = glm.vec4(cr, cg, cb, 1.0)
                    src.diffuse = glm.vec4(cr, cg, cb, 1.0)
                    src.specular = glm.vec4(cr, cg, cb, 1.0)
                end

                imgui.TreePop()
            end
        end
    end
    imgui.End()
end

local function load_model()
    local t0 = os.clock()

    -- Try to load precompiled bytecode if newer than source
    local model
    local model_name = "mill-scene"
    local base_path = "assets/" .. model_name .. "/" .. model_name
    local lua_path = base_path .. ".lua"
    local luac_path = base_path .. ".luac"
    local texture_base = "assets/" .. model_name .. "/tex/"
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

        -- Load textures (diffuse, normal, specular)
        t1 = os.clock()

        -- Helper to load or get cached texture
        local function load_texture_slot(slot_index)
            if not mesh_data.textures or slot_index > #mesh_data.textures then
                return nil, nil
            end
            local tex_name = mesh_data.textures[slot_index]
            if not tex_name then return nil, nil end

            local tex_info = model.textures[tex_name]
            if not tex_info then return nil, nil end

            local path = texture_base .. tex_info.path
            if not textures_cache[path] then
                local img, view, smp = util.load_texture(path)
                if img then
                    textures_cache[path] = { img = img, view = view, smp = smp }
                end
            end
            if textures_cache[path] then
                return textures_cache[path].view.handle, textures_cache[path].smp.handle
            end
            return nil, nil
        end

        local diffuse_view, diffuse_smp = load_texture_slot(1)
        local normal_view, normal_smp = load_texture_slot(2)
        local specular_view, specular_smp = load_texture_slot(3)
        t_texture = t_texture + (os.clock() - t1)

        -- Create default textures if needed
        if not default_diffuse then
            local white = string.pack("BBBB", 255, 255, 255, 255)
            local img = gpu.image(gfx.ImageDesc({
                width = 1, height = 1,
                pixel_format = gfx.PixelFormat.RGBA8,
                data = { mip_levels = { white } },
            }))
            local view = gpu.view(gfx.ViewDesc({ texture = { image = img.handle } }))
            local smp = gpu.sampler(gfx.SamplerDesc({
                min_filter = gfx.Filter.NEAREST, mag_filter = gfx.Filter.NEAREST,
            }))
            default_diffuse = { img = img, view = view, smp = smp }
        end
        if not default_normal then
            -- Flat normal: (0.5, 0.5, 1.0) = pointing up in tangent space
            local flat = string.pack("BBBB", 128, 128, 255, 255)
            local img = gpu.image(gfx.ImageDesc({
                width = 1, height = 1,
                pixel_format = gfx.PixelFormat.RGBA8,
                data = { mip_levels = { flat } },
            }))
            local view = gpu.view(gfx.ViewDesc({ texture = { image = img.handle } }))
            local smp = gpu.sampler(gfx.SamplerDesc({
                min_filter = gfx.Filter.NEAREST, mag_filter = gfx.Filter.NEAREST,
            }))
            default_normal = { img = img, view = view, smp = smp }
        end
        if not default_specular then
            -- Default specular: R=0.5 (intensity), G=0.25 (shininess=32), B=0 (no fresnel)
            local spec = string.pack("BBBB", 128, 64, 0, 255)
            local img = gpu.image(gfx.ImageDesc({
                width = 1, height = 1,
                pixel_format = gfx.PixelFormat.RGBA8,
                data = { mip_levels = { spec } },
            }))
            local view = gpu.view(gfx.ViewDesc({ texture = { image = img.handle } }))
            local smp = gpu.sampler(gfx.SamplerDesc({
                min_filter = gfx.Filter.NEAREST, mag_filter = gfx.Filter.NEAREST,
            }))
            default_specular = { img = img, view = view, smp = smp }
        end

        -- Use defaults if textures not loaded
        if not diffuse_view then
            diffuse_view = default_diffuse.view.handle
            diffuse_smp = default_diffuse.smp.handle
        end
        if not normal_view then
            normal_view = default_normal.view.handle
            normal_smp = default_normal.smp.handle
        end
        if not specular_view then
            specular_view = default_specular.view.handle
            specular_smp = default_specular.smp.handle
        end

        -- Skip water meshes
        if not mat_name:find("water") and not mat_name:find("Water") then
            table.insert(meshes, {
                vbuf = vbuf,
                ibuf = ibuf,
                num_indices = #indices,
                diffuse_view = diffuse_view,
                diffuse_smp = diffuse_smp,
                normal_view = normal_view,
                normal_smp = normal_smp,
                specular_view = specular_view,
                specular_smp = specular_smp,
            })
        end
    end

    util.info(string.format("tangent: %.3fs, vbuf: %.3fs, texture: %.3fs", t_tangent, t_vbuf, t_texture))
    util.info("Loaded " .. #meshes .. " meshes")
end

function init()
    util.info("Rendering Pipeline init")
    imgui.setup()
    notify.setup()

    ctx.init()

    local width, height = app.width(), app.height()
    ctx.ensure_size(width, height)

    -- Register passes
    pipeline.register(geometry_pass)
    pipeline.register(lighting_pass)
    pipeline.register(imgui_pass)

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

    -- Animate lights (uses app.frame_duration for delta time)
    local dt = app.frame_duration()
    light.animate(dt)

    imgui.new_frame()
    update_ui()

    -- Reset outputs
    ctx.outputs = {}

    -- Frame data for passes
    local frame_data = {
        meshes = meshes,
        view = view,
        proj = proj,
        model = model_mat,
        light_uniforms = light.pack_uniforms(view),
    }

    -- Execute all passes
    pipeline.execute(ctx, frame_data)
end

function cleanup()
    imgui.shutdown()
    notify.shutdown()

    -- Destroy pipeline and passes
    pipeline.destroy()
    ctx.destroy()

    -- Destroy mesh resources
    for _, mesh in ipairs(meshes) do
        mesh.vbuf:destroy()
        mesh.ibuf:destroy()
    end
    meshes = {}

    -- Destroy cached textures
    for path, tex in pairs(textures_cache) do
        tex.smp:destroy()
        tex.view:destroy()
        tex.img:destroy()
    end
    textures_cache = {}

    -- Destroy default textures
    for _, tex in ipairs({ default_diffuse, default_normal, default_specular }) do
        if tex then
            tex.smp:destroy()
            tex.view:destroy()
            tex.img:destroy()
        end
    end
    default_diffuse = nil
    default_normal = nil
    default_specular = nil

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
