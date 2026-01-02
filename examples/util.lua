-- Utility functions for mane3d examples
local gfx = require("sokol.gfx")
local slog = require("sokol.log")

local M = {}

-- Resolve path relative to script directory
-- Absolute paths (starting with / or X:) are returned as-is
---@param path string
---@return string
function M.resolve_path(path)
    -- Check if absolute path
    if path:match("^/") or path:match("^%a:") then
        return path
    end
    -- Use SCRIPT_DIR if available
    local script_dir = _G["SCRIPT_DIR"]
    if script_dir and script_dir ~= "." then
        return script_dir .. "/" .. path
    end
    return path
end

-- Logging (uses sokol_log, OutputDebugString on Windows)
function M.info(msg)
    slog.func("lua", 3, 0, msg, 0, "", nil)
end

function M.warn(msg)
    slog.func("lua", 2, 0, msg, 0, "", nil)
end

function M.error(msg)
    slog.func("lua", 1, 0, msg, 0, "", nil)
end

-- Alias for backward compatibility
M.log = M.info

-- Get shader language for current backend
function M.get_shader_lang()
    local backend = gfx.query_backend()
    if backend == gfx.Backend.D3D11 then
        return "hlsl5"
    elseif backend == gfx.Backend.METAL_MACOS or backend == gfx.Backend.METAL_IOS or backend == gfx.Backend.METAL_SIMULATOR then
        return "metal_macos"
    elseif backend == gfx.Backend.WGPU then
        return "wgsl"
    elseif backend == gfx.Backend.GLCORE then
        return "glsl430"
    elseif backend == gfx.Backend.GLES3 then
        return "glsl300es"
    else
        return "glsl430"
    end
end

-- Compile shader using sokol-shdc library
-- @param source string: shader source code
-- @param program_name string: program name in shader
-- @param uniform_blocks table|nil: optional uniform block descriptors
-- @param attrs table|nil: optional vertex attribute semantics for D3D11
-- @param texture_sampler_pairs table|nil: optional texture-sampler pair descriptors
-- @return shader handle or nil on failure
function M.compile_shader(source, program_name, uniform_blocks, attrs, texture_sampler_pairs)
    local shdc = require("shdc")
    local lang = M.get_shader_lang()

    M.info("Compiling shader: " .. program_name .. " for " .. lang)

    -- Compile using library
    local result = shdc.compile(source, program_name, lang)
    if not result.success then
        M.error("Shader compile error: " .. (result.error or "unknown"))
        return nil
    end

    M.info("Shader compiled: vs=" .. tostring(result.vs_source and #result.vs_source or "nil") .. " fs=" .. tostring(result.fs_source and #result.fs_source or "nil"))

    -- Create shader using generated bindings
    local backend = gfx.query_backend()
    local is_source = (backend == gfx.Backend.GLCORE or backend == gfx.Backend.GLES3 or backend == gfx.Backend.WGPU)

    local vs_data, fs_data
    if is_source then
        vs_data = result.vs_source
        fs_data = result.fs_source
    else
        -- Use bytecode for HLSL/Metal
        vs_data = result.vs_bytecode or result.vs_source
        fs_data = result.fs_bytecode or result.fs_source
    end

    if not vs_data or not fs_data then
        M.error("Missing shader data: vs=" .. tostring(vs_data) .. " fs=" .. tostring(fs_data))
        return nil
    end

    local desc_table = {
        vertex_func = is_source and { source = vs_data } or { bytecode = vs_data },
        fragment_func = is_source and { source = fs_data } or { bytecode = fs_data },
    }

    -- Add uniform blocks if specified
    if uniform_blocks then
        desc_table.uniform_blocks = uniform_blocks
    end

    -- Add texture-sampler pairs if specified
    if texture_sampler_pairs then
        desc_table.texture_sampler_pairs = texture_sampler_pairs
    end

    -- D3D11 needs attribute semantics
    if backend == gfx.Backend.D3D11 then
        desc_table.attrs = attrs or {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        }
    end

    local shd = gfx.make_shader(gfx.ShaderDesc(desc_table))
    if gfx.query_shader_state(shd) ~= gfx.ResourceState.VALID then
        M.error("Failed to create shader")
        return nil
    end

    return shd
end

-- Compile shader with full descriptor control
-- @param source string: shader source code
-- @param program_name string: program name in shader
-- @param shader_desc table: full shader descriptor (uniform_blocks, views, samplers, texture_sampler_pairs, attrs)
-- @return shader handle or nil on failure
function M.compile_shader_full(source, program_name, shader_desc)
    local shdc = require("shdc")
    local lang = M.get_shader_lang()

    M.info("Compiling shader: " .. program_name .. " for " .. lang)

    local result = shdc.compile(source, program_name, lang)
    if not result.success then
        M.error("Shader compile error: " .. (result.error or "unknown"))
        return nil
    end

    M.info("Shader compiled: vs=" .. tostring(result.vs_source and #result.vs_source or "nil") .. " fs=" .. tostring(result.fs_source and #result.fs_source or "nil"))

    local backend = gfx.query_backend()
    local is_source = (backend == gfx.Backend.GLCORE or backend == gfx.Backend.GLES3 or backend == gfx.Backend.WGPU)

    local vs_data, fs_data
    if is_source then
        vs_data = result.vs_source
        fs_data = result.fs_source
    else
        vs_data = result.vs_bytecode or result.vs_source
        fs_data = result.fs_bytecode or result.fs_source
    end

    if not vs_data or not fs_data then
        M.error("Missing shader data")
        return nil
    end

    local desc_table = {
        vertex_func = is_source and { source = vs_data } or { bytecode = vs_data },
        fragment_func = is_source and { source = fs_data } or { bytecode = fs_data },
    }

    -- Copy all fields from shader_desc
    if shader_desc.uniform_blocks then desc_table.uniform_blocks = shader_desc.uniform_blocks end
    if shader_desc.views then desc_table.views = shader_desc.views end
    if shader_desc.samplers then desc_table.samplers = shader_desc.samplers end
    if shader_desc.texture_sampler_pairs then desc_table.texture_sampler_pairs = shader_desc.texture_sampler_pairs end
    if backend == gfx.Backend.D3D11 and shader_desc.attrs then
        desc_table.attrs = shader_desc.attrs
    end

    local shd = gfx.make_shader(gfx.ShaderDesc(desc_table))
    if gfx.query_shader_state(shd) ~= gfx.ResourceState.VALID then
        M.error("Failed to create shader")
        return nil
    end

    return shd
end

-- Helper to pack vertex data as floats (handles large arrays)
function M.pack_floats(floats)
    local CHUNK_SIZE = 200  -- Lua unpack limit is around 200-1000
    local result = {}
    for i = 1, #floats, CHUNK_SIZE do
        local chunk_end = math.min(i + CHUNK_SIZE - 1, #floats)
        local chunk = {}
        for j = i, chunk_end do
            chunk[#chunk + 1] = floats[j]
        end
        result[#result + 1] = string.pack(string.rep("f", #chunk), table.unpack(chunk))
    end
    return table.concat(result)
end

-- Load raw image data from file (handles WASM fetch)
-- @param filename string: path to image file
-- @return width, height, channels, pixels or nil, error_message
function M.load_image_data(filename)
    local stb = require("stb.image")
    local resolved = M.resolve_path(filename)

    -- Check if running in WASM (fetch_file is defined in main.c for Emscripten)
    ---@type fun(filename: string): string?
    local fetch_file = _G["fetch_file"]
    if fetch_file then
        local data = fetch_file(resolved)
        if not data then
            return nil, "Failed to fetch: " .. resolved
        end
        return stb.load_from_memory(data, 4)
    else
        -- Native: load directly from filesystem
        return stb.load(resolved, 4)
    end
end

-- Load texture from file
---@param filename string path to image file (PNG, JPG, etc.)
---@param opts? table optional settings { filter_min, filter_mag, wrap_u, wrap_v }
---@return gfx.View? view
---@return gfx.Sampler|string smp_or_error sampler on success, error message on failure
function M.load_texture(filename, opts)
    opts = opts or {}

    local w, h, ch, pixels = M.load_image_data(filename)
    if not w then
        return nil, h -- h contains error message
    end

    M.info("Loaded texture: " .. filename .. " (" .. w .. "x" .. h .. ")")

    -- Create image
    local img = gfx.make_image(gfx.ImageDesc({
        width = w,
        height = h,
        pixel_format = gfx.PixelFormat.RGBA8,
        data = { mip_levels = { pixels } },
    }))

    if gfx.query_image_state(img) ~= gfx.ResourceState.VALID then
        return nil, "Failed to create image"
    end

    -- Create view from image (required for binding)
    local view = gfx.make_view(gfx.ViewDesc({
        texture = { image = img },
    }))

    -- Create sampler
    local smp = gfx.make_sampler(gfx.SamplerDesc({
        min_filter = opts.filter_min or gfx.Filter.LINEAR,
        mag_filter = opts.filter_mag or gfx.Filter.LINEAR,
        wrap_u = opts.wrap_u or gfx.Wrap.REPEAT,
        wrap_v = opts.wrap_v or gfx.Wrap.REPEAT,
    }))

    return view, smp
end

return M
