-- examples/rendering/ctx.lua
-- Shared context for rendering pipeline
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local gpu = require("lib.gpu")
local rt = require("lib.render_target")

---@class rendering.TextureBundle
---@field image gpu.Image
---@field view gpu.View
---@field sampler gpu.Sampler

---@class rendering.Targets
---@field gbuf_position render_target.ColorTarget?
---@field gbuf_normal render_target.ColorTarget?
---@field gbuf_albedo render_target.ColorTarget?
---@field gbuf_specular render_target.ColorTarget?
---@field depth render_target.DepthTarget?

---@class rendering.Outputs
---@field gbuf_position gpu.View?
---@field gbuf_normal gpu.View?
---@field gbuf_albedo gpu.View?
---@field gbuf_specular gpu.View?

---@class rendering.Context
---@field width integer Screen width
---@field height integer Screen height
---@field targets rendering.Targets G-Buffer render targets
---@field quad_vbuf gpu.Buffer? Full-screen quad vertex buffer
---@field gbuf_sampler gpu.Sampler? Sampler for reading G-Buffer
---@field outputs rendering.Outputs Output views from passes
---@field textures table<string, rendering.TextureBundle> Fallback textures
local M = {}

M.width = 0
M.height = 0
M.targets = {}
M.quad_vbuf = nil
M.gbuf_sampler = nil
M.outputs = {}
M.textures = {}

---Initialize context resources
function M.init()
    -- Create full-screen quad
    local quad_vertices = {
        -1, -1, 0, 0,
        1, -1, 1, 0,
        1, 1, 1, 1,
        -1, -1, 0, 0,
        1, 1, 1, 1,
        -1, 1, 0, 1,
    }
    local quad_data = string.pack(string.rep("f", #quad_vertices), table.unpack(quad_vertices))
    M.quad_vbuf = gpu.buffer(gfx.BufferDesc({ data = gfx.Range(quad_data) }))

    -- Create sampler for reading G-Buffer
    M.gbuf_sampler = gpu.sampler(gfx.SamplerDesc({
        min_filter = gfx.Filter.NEAREST,
        mag_filter = gfx.Filter.NEAREST,
        wrap_u = gfx.Wrap.CLAMP_TO_EDGE,
        wrap_v = gfx.Wrap.CLAMP_TO_EDGE,
    }))

    -- Create white texture for fallback
    local white_data = string.pack("BBBB", 255, 255, 255, 255)
    local white_img = gpu.image(gfx.ImageDesc({
        width = 1,
        height = 1,
        pixel_format = gfx.PixelFormat.RGBA8,
        data = { mip_levels = { gfx.Range(white_data) } },
    }))
    local white_view = gpu.view(gfx.ViewDesc({
        texture = { image = white_img.handle },
    }))
    local white_smp = gpu.sampler(gfx.SamplerDesc({
        min_filter = gfx.Filter.NEAREST,
        mag_filter = gfx.Filter.NEAREST,
    }))
    M.textures.white = { image = white_img, view = white_view, sampler = white_smp }
end

---Ensure G-Buffer is correct size, recreate if needed
---@param w integer Width
---@param h integer Height
---@return boolean resized True if targets were recreated
function M.ensure_size(w, h)
    if M.width == w and M.height == h then
        return false
    end

    M.width = w
    M.height = h

    -- Destroy old targets explicitly before creating new ones
    for _, target in pairs(M.targets) do
        target:destroy()
    end

    -- Recreate G-Buffer targets
    M.targets.gbuf_position = rt.color(w, h, gfx.PixelFormat.RGBA32F)
    M.targets.gbuf_normal = rt.color(w, h, gfx.PixelFormat.RGBA16F)
    M.targets.gbuf_albedo = rt.color(w, h, gfx.PixelFormat.RGBA8)
    M.targets.gbuf_specular = rt.color(w, h, gfx.PixelFormat.RGBA8)
    M.targets.depth = rt.depth(w, h)

    return true
end

---Destroy all context resources
function M.destroy()
    -- Destroy G-Buffer targets
    for _, target in pairs(M.targets) do
        target:destroy()
    end
    M.targets = {}

    -- Destroy shared resources
    if M.quad_vbuf then M.quad_vbuf:destroy() end
    if M.gbuf_sampler then M.gbuf_sampler:destroy() end

    -- Destroy fallback textures
    if M.textures.white then
        M.textures.white.image:destroy()
        M.textures.white.view:destroy()
        M.textures.white.sampler:destroy()
    end
    M.textures = {}
end

return M
