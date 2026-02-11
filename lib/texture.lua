-- Texture loading utilities for lub3d
local gfx = require("sokol.gfx")
local gpu = require("lib.gpu")
local log = require("lib.log")
local stb = require("stb.image")
local fs = require("lub3d.fs")

-- Optional bc7enc module
local bc7enc_ok, bc7enc = pcall(require, "bc7enc")
if not bc7enc_ok then
    bc7enc = nil
end

local M = {}

-- Resolve path relative to script directory
-- Absolute paths (starting with / or X:) are returned as-is
---@param path string
---@return string
local function resolve_path(path)
    if path:match("^/") or path:match("^%a:") then
        return path
    end
    return path
end

---@class texture.ImageData
---@field w integer
---@field h integer
---@field ch integer
---@field pixels string

---@class texture.LoadResult
---@field img gpu.Image
---@field view gpu.View
---@field smp gpu.Sampler

-- Load raw image data from file
---@param filename string path to image file
---@return texture.ImageData?
---@return string? err
function M.load_image_data(filename)
    local resolved = resolve_path(filename)
    local data = fs.read(resolved)
    if not data then
        return nil, "Failed to read: " .. resolved
    end
    local w, h, ch, pixels = stb.load_from_memory(data, 4)
    if not w then
        return nil, "Failed to load: " .. resolved .. " (stb error: " .. tostring(h) .. ")"
    end
    return { w = w, h = h, ch = ch, pixels = pixels }, nil
end

-- Load texture from file using gpu wrappers (GC-safe)
---@param filename string path to image file (PNG, JPG, etc.)
---@param opts? table optional settings { filter_min, filter_mag, wrap_u, wrap_v }
---@return texture.LoadResult?
---@return string? err
function M.load(filename, opts)
    opts = opts or {}

    local data, err = M.load_image_data(filename)
    if not data then
        return nil, err or "Failed to load image"
    end

    log.info("Loaded texture: " .. filename .. " (" .. data.w .. "x" .. data.h .. ")")

    -- Create image with gpu wrapper (GC-safe)
    local img = gpu.image(gfx.ImageDesc({
        width = data.w,
        height = data.h,
        pixel_format = gfx.PixelFormat.RGBA8,
        data = { mip_levels = { data.pixels } },
    }))

    if gfx.QueryImageState(img.handle) ~= gfx.ResourceState.VALID then
        return nil, "Failed to create image"
    end

    -- Create view from image (required for binding)
    local view = gpu.view(gfx.ViewDesc({
        texture = { image = img.handle },
    }))

    -- Create sampler
    local smp = gpu.sampler(gfx.SamplerDesc({
        min_filter = opts.filter_min or gfx.Filter.LINEAR,
        mag_filter = opts.filter_mag or gfx.Filter.LINEAR,
        wrap_u = opts.wrap_u or gfx.Wrap.REPEAT,
        wrap_v = opts.wrap_v or gfx.Wrap.REPEAT,
    }))

    return { img = img, view = view, smp = smp }, nil
end

-- Load texture with BC7 compression support
-- If .bc7 file exists, use it directly. Otherwise, load PNG and convert to BC7.
---@param filename string path to image file (PNG, JPG, etc.)
---@param opts? table optional settings { filter_min, filter_mag, wrap_u, wrap_v, srgb, rdo_quality }
---@return texture.LoadResult?
---@return string? err
function M.load_bc7(filename, opts)
    opts = opts or {}

    -- If bc7enc not available, fall back to regular load
    if not bc7enc then
        return M.load(filename, opts)
    end

    -- Generate BC7 cache path
    local bc7_path = filename:gsub("%.[^.]+$", ".bc7")
    local resolved = resolve_path(filename)
    local resolved_bc7 = resolve_path(bc7_path)

    local w, h, compressed

    -- Check timestamps: use BC7 cache only if it's newer than source
    local src_mtime = fs.mtime(resolved)
    local bc7_mtime = fs.mtime(resolved_bc7)
    local use_cache = bc7_mtime and src_mtime and bc7_mtime >= src_mtime

    -- Try to load existing BC7 file if cache is valid
    if use_cache then
        local cache_data = fs.read(resolved_bc7)
        if cache_data and #cache_data >= 8 then
            -- BC7 file format: 4 bytes width, 4 bytes height, then compressed data
            w, h = string.unpack("<I4I4", cache_data)
            compressed = cache_data:sub(9)
            log.info("Loaded BC7 cache: " .. bc7_path .. " (" .. w .. "x" .. h .. ")")
        end
    end

    -- If no valid cache, load source and encode to BC7
    if not compressed then
        local img_data, err = M.load_image_data(filename)
        if not img_data then
            return nil, err or "Failed to load image"
        end
        w, h = img_data.w, img_data.h

        compressed = bc7enc.encode(img_data.pixels, w, h, {
            quality = 5,
            srgb = opts.srgb or false,
            rdo_quality = opts.rdo_quality or 0,
        })

        if not compressed then
            return nil, "BC7 encoding failed"
        end

        -- Save BC7 cache file
        local header = string.pack("<I4I4", w, h)
        fs.write(resolved_bc7, header .. compressed)
        log.info("Saved BC7 cache: " .. bc7_path .. " (" .. w .. "x" .. h .. ")")
    end

    if not w or not h or not compressed then
        return nil, "Invalid image data"
    end

    -- Upload BC7 to GPU
    local pixel_format = opts.srgb and gfx.PixelFormat.BC7_SRGBA or gfx.PixelFormat.BC7_RGBA
    local img = gpu.image(gfx.ImageDesc({
        width = w,
        height = h,
        pixel_format = pixel_format,
        data = { mip_levels = { compressed } },
    }))

    if gfx.QueryImageState(img.handle) ~= gfx.ResourceState.VALID then
        return nil, "Failed to create BC7 image"
    end

    local view = gpu.view(gfx.ViewDesc({
        texture = { image = img.handle },
    }))

    local smp = gpu.sampler(gfx.SamplerDesc({
        min_filter = opts.filter_min or gfx.Filter.LINEAR,
        mag_filter = opts.filter_mag or gfx.Filter.LINEAR,
        wrap_u = opts.wrap_u or gfx.Wrap.REPEAT,
        wrap_v = opts.wrap_v or gfx.Wrap.REPEAT,
    }))

    return { img = img, view = view, smp = smp }, nil
end

return M
