-- lib/sprite.lua
-- 2D sprite batch renderer built on sokol.gfx
-- Provides Ebiten-like DrawImage abstraction over gfx pipeline
local gfx = require("sokol.gfx")
local glue = require("sokol.glue")
local gpu = require("lib.gpu")
local shaderMod = require("lib.shader")
local util = require("lib.util")
local log = require("lib.log")

local M = {}

local MAX_QUADS = 4096
local VERTS_PER_QUAD = 4
local INDICES_PER_QUAD = 6
local FLOATS_PER_VERT = 8 -- x, y, u, v, r, g, b, a

local shader_source = [[
@vs vs
in vec2 pos;
in vec2 uv;
in vec4 color;

out vec2 v_uv;
out vec4 v_color;

layout(binding=0) uniform vs_params {
    vec4 screen_size; // xy = screen size, zw = unused
};

void main() {
    // Convert pixel coords to clip space: [0,w] -> [-1,1], [0,h] -> [1,-1]
    vec2 ndc = vec2(
        pos.x / screen_size.x * 2.0 - 1.0,
        1.0 - pos.y / screen_size.y * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_uv = uv;
    v_color = color;
}
@end

@fs fs
in vec2 v_uv;
in vec4 v_color;

out vec4 frag_color;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

void main() {
    frag_color = texture(sampler2D(tex, smp), v_uv) * v_color;
}
@end

@program sprite vs fs
]]

---@class sprite.Batch
---@field tex_view gpu.View
---@field tex_smp gpu.Sampler
---@field tex_w number atlas width in pixels
---@field tex_h number atlas height in pixels
---@field verts number[] vertex data accumulator
---@field quad_count number quads queued this frame
---@field vbuf gpu.Buffer
---@field ibuf gpu.Buffer
---@field screen_w number logical screen width
---@field screen_h number logical screen height

-- Shared index buffer data (generated once)
local shared_ibuf_data = nil

local function get_ibuf_data()
    if shared_ibuf_data then
        return shared_ibuf_data
    end
    local indices = {}
    for i = 0, MAX_QUADS - 1 do
        local base = i * VERTS_PER_QUAD
        indices[#indices + 1] = base + 0
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 0
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 3
    end
    shared_ibuf_data = util.pack_u32(indices)
    return shared_ibuf_data
end

-- Shared resources (lazily created, shared across batches)
-- Keep gpu-wrapped refs to prevent GC
local shared_shader_ref = nil -- gpu.Shader (prevents GC)
local shared_pipeline_ref = nil -- gpu.Pipeline (prevents GC)
local shared_shader = nil -- raw handle for pipeline creation
local shared_pipeline = nil -- raw handle for draw calls

local function ensure_shared_resources()
    if shared_pipeline then
        return
    end

    local shd = shaderMod.compile_full(shader_source, "sprite", {
        uniform_blocks = {
            {
                stage = gfx.ShaderStage.VERTEX,
                size = 16,
                glsl_uniforms = {
                    { type = gfx.UniformType.FLOAT4, glsl_name = "screen_size" },
                },
            },
        },
        views = {
            {
                texture = {
                    stage = gfx.ShaderStage.FRAGMENT,
                    image_type = gfx.ImageType["2D"],
                    sample_type = gfx.ImageSampleType.FLOAT,
                    hlsl_register_t_n = 0,
                    wgsl_group1_binding_n = 0,
                },
            },
        },
        samplers = {
            {
                stage = gfx.ShaderStage.FRAGMENT,
                sampler_type = gfx.SamplerType.FILTERING,
                hlsl_register_s_n = 0,
                wgsl_group1_binding_n = 32,
            },
        },
        texture_sampler_pairs = {
            { stage = gfx.ShaderStage.FRAGMENT, view_slot = 0, sampler_slot = 0, glsl_name = "tex_smp" },
        },
        attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 2 },
        },
    })
    if not shd then
        log.error("sprite: failed to compile shader")
        return
    end
    shared_shader = shd

    local pip = gfx.MakePipeline(gfx.PipelineDesc({
        shader = shd,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT2 }, -- pos
                { format = gfx.VertexFormat.FLOAT2 }, -- uv
                { format = gfx.VertexFormat.FLOAT4 }, -- color
            },
        },
        index_type = gfx.IndexType.UINT32,
        colors = {
            {
                blend = {
                    enabled = true,
                    src_factor_rgb = gfx.BlendFactor.SRC_ALPHA,
                    dst_factor_rgb = gfx.BlendFactor.ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = gfx.BlendFactor.ONE,
                    dst_factor_alpha = gfx.BlendFactor.ONE_MINUS_SRC_ALPHA,
                },
            },
        },
        depth = {
            write_enabled = false,
        },
    }))
    if gfx.QueryPipelineState(pip) ~= gfx.ResourceState.VALID then
        log.error("sprite: failed to create pipeline")
        gfx.DestroyShader(shd)
        shared_shader = nil
        return
    end
    shared_pipeline = pip
end

--- Create a new sprite batch for a given texture atlas
---@param tex_result texture.LoadResult from lib.texture.load()
---@param tex_w number atlas width in pixels
---@param tex_h number atlas height in pixels
---@param screen_w number logical screen width (for orthographic projection)
---@param screen_h number logical screen height
---@return sprite.Batch
function M.new_batch(tex_result, tex_w, tex_h, screen_w, screen_h)
    ensure_shared_resources()

    local vbuf = gpu.buffer(gfx.BufferDesc({
        usage = { vertex_buffer = true, dynamic_update = true },
        size = MAX_QUADS * VERTS_PER_QUAD * FLOATS_PER_VERT * 4,
    }))

    local ibuf = gpu.buffer(gfx.BufferDesc({
        usage = { index_buffer = true },
        data = gfx.Range(get_ibuf_data()),
    }))

    ---@type sprite.Batch
    local batch = {
        tex_view = tex_result.view,
        tex_smp = tex_result.smp,
        tex_w = tex_w,
        tex_h = tex_h,
        verts = {},
        quad_count = 0,
        vbuf = vbuf,
        ibuf = ibuf,
        screen_w = screen_w,
        screen_h = screen_h,
    }

    return batch
end

--- Draw a sprite from the atlas
---@param batch sprite.Batch
---@param sx number source X in atlas (pixels)
---@param sy number source Y in atlas (pixels)
---@param sw number source width (pixels)
---@param sh number source height (pixels)
---@param dx number destination X on screen (pixels)
---@param dy number destination Y on screen (pixels)
---@param opts? table { rotate, scale_x, scale_y, origin_x, origin_y, color }
function M.draw(batch, sx, sy, sw, sh, dx, dy, opts)
    if batch.quad_count >= MAX_QUADS then
        M.flush(batch)
    end

    local r, g, b, a = 1.0, 1.0, 1.0, 1.0
    local rotate = 0
    local scale_x, scale_y = 1.0, 1.0
    local origin_x, origin_y = 0, 0

    if opts then
        if opts.color then
            r = opts.color[1] or 1.0
            g = opts.color[2] or 1.0
            b = opts.color[3] or 1.0
            a = opts.color[4] or 1.0
        end
        rotate = opts.rotate or 0
        scale_x = opts.scale_x or 1.0
        scale_y = opts.scale_y or 1.0
        origin_x = opts.origin_x or 0
        origin_y = opts.origin_y or 0
    end

    -- UV coordinates
    local u0 = sx / batch.tex_w
    local v0 = sy / batch.tex_h
    local u1 = (sx + sw) / batch.tex_w
    local v1 = (sy + sh) / batch.tex_h

    -- Local quad corners relative to origin
    local x0 = -origin_x * scale_x
    local y0 = -origin_y * scale_y
    local x1 = (sw - origin_x) * scale_x
    local y1 = (sh - origin_y) * scale_y

    -- Apply rotation and translate to destination
    local cos_r, sin_r = math.cos(rotate), math.sin(rotate)
    local function transform(lx, ly)
        return dx + origin_x + lx * cos_r - ly * sin_r, dy + origin_y + lx * sin_r + ly * cos_r
    end

    local ax, ay = transform(x0, y0)
    local bx, by = transform(x1, y0)
    local cx, cy = transform(x1, y1)
    local ddx, ddy = transform(x0, y1)

    -- Append 4 vertices (top-left, top-right, bottom-right, bottom-left)
    local v = batch.verts
    local n = #v
    -- top-left
    v[n + 1] = ax
    v[n + 2] = ay
    v[n + 3] = u0
    v[n + 4] = v0
    v[n + 5] = r
    v[n + 6] = g
    v[n + 7] = b
    v[n + 8] = a
    -- top-right
    v[n + 9] = bx
    v[n + 10] = by
    v[n + 11] = u1
    v[n + 12] = v0
    v[n + 13] = r
    v[n + 14] = g
    v[n + 15] = b
    v[n + 16] = a
    -- bottom-right
    v[n + 17] = cx
    v[n + 18] = cy
    v[n + 19] = u1
    v[n + 20] = v1
    v[n + 21] = r
    v[n + 22] = g
    v[n + 23] = b
    v[n + 24] = a
    -- bottom-left
    v[n + 25] = ddx
    v[n + 26] = ddy
    v[n + 27] = u0
    v[n + 28] = v1
    v[n + 29] = r
    v[n + 30] = g
    v[n + 31] = b
    v[n + 32] = a

    batch.quad_count = batch.quad_count + 1
end

--- Flush queued sprites: upload vertex data and issue draw call
--- Must be called between gfx.BeginPass and gfx.EndPass
---@param batch sprite.Batch
function M.flush(batch)
    if batch.quad_count == 0 then
        return
    end

    -- Upload vertex data
    local packed = util.pack_floats(batch.verts)
    gfx.UpdateBuffer(batch.vbuf.handle, gfx.Range(packed))

    -- Apply pipeline and bindings
    gfx.ApplyPipeline(shared_pipeline)
    gfx.ApplyBindings(gfx.Bindings({
        vertex_buffers = { batch.vbuf.handle },
        index_buffer = batch.ibuf.handle,
        views = { batch.tex_view.handle },
        samplers = { batch.tex_smp.handle },
    }))

    -- Set screen size uniform
    local params = util.pack_floats({ batch.screen_w, batch.screen_h, 0, 0 })
    gfx.ApplyUniforms(0, gfx.Range(params))

    -- Draw
    gfx.Draw(0, batch.quad_count * INDICES_PER_QUAD, 1)

    -- Reset
    batch.verts = {}
    batch.quad_count = 0
end

--- Destroy a batch's GPU resources (call before gfx.Shutdown)
---@param batch sprite.Batch
function M.destroy_batch(batch)
    if batch.vbuf then
        batch.vbuf:destroy()
        batch.vbuf = nil
    end
    if batch.ibuf then
        batch.ibuf:destroy()
        batch.ibuf = nil
    end
end

--- Shutdown shared resources (call before gfx.Shutdown)
function M.shutdown()
    if shared_pipeline then
        gfx.DestroyPipeline(shared_pipeline)
        shared_pipeline = nil
    end
    if shared_shader then
        gfx.DestroyShader(shared_shader)
        shared_shader = nil
    end
end

return M
