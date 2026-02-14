-- lib/render_target.lua
-- RenderTarget: image + view (attach + tex) bundle
local gfx = require("sokol.gfx")
local gpu = require("lib.gpu")

---@class render_target
local M = {}

---@class render_target.ColorTarget
---@field image gpu.Image
---@field attach gpu.View Attachment view for rendering
---@field tex gpu.View Texture view for sampling
---@field width integer
---@field height integer
---@field format sokol.gfx.PixelFormat
---@field destroy fun(self: render_target.ColorTarget)

---@class render_target.DepthTarget
---@field image gpu.Image
---@field attach gpu.View Attachment view for rendering
---@field width integer
---@field height integer
---@field format sokol.gfx.PixelFormat
---@field destroy fun(self: render_target.DepthTarget)

---Create a color render target
---@param w integer Width
---@param h integer Height
---@param format sokol.gfx.PixelFormat? (default: RGBA8)
---@return render_target.ColorTarget
function M.color(w, h, format)
    format = format or gfx.PixelFormat.RGBA8

    local image = gpu.image(gfx.ImageDesc({
        usage = { color_attachment = true },
        width = w,
        height = h,
        pixel_format = format,
    }))

    local attach = gpu.view(gfx.ViewDesc({
        color_attachment = { image = image.handle },
    }))

    local tex = gpu.view(gfx.ViewDesc({
        texture = { image = image.handle },
    }))

    return {
        image = image,
        attach = attach,
        tex = tex,
        width = w,
        height = h,
        format = format,
        destroy = function(self)
            self.tex:destroy()
            self.attach:destroy()
            self.image:destroy()
        end
    }
end

---Create a depth render target
---@param w integer Width
---@param h integer Height
---@param format sokol.gfx.PixelFormat? (default: DEPTH)
---@return render_target.DepthTarget
function M.depth(w, h, format)
    format = format or gfx.PixelFormat.DEPTH

    local image = gpu.image(gfx.ImageDesc({
        usage = { depth_stencil_attachment = true },
        width = w,
        height = h,
        pixel_format = format,
    }))

    local attach = gpu.view(gfx.ViewDesc({
        depth_stencil_attachment = { image = image.handle },
    }))

    return {
        image = image,
        attach = attach,
        width = w,
        height = h,
        format = format,
        destroy = function(self)
            self.attach:destroy()
            self.image:destroy()
        end
    }
end

return M
