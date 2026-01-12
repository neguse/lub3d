-- Shader compilation utilities for mane3d
local gfx = require("sokol.gfx")
local log = require("lib.log")

-- Optional shdc module (requires MANE3D_BUILD_SHDC=ON)
---@type shdc?
local shdc
local shdc_ok, shdc_mod = pcall(require, "shdc")
if shdc_ok then shdc = shdc_mod end

local M = {}

-- Simple string hash for cache keys (djb2 algorithm)
---@param str string
---@return integer
local function hash_string(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) & 0xFFFFFFFF
    end
    return hash
end

-- Ensure directory exists (platform-independent)
---@param path string directory path
---@return boolean success
local function ensure_dir(path)
    local sep = package.config:sub(1, 1)
    local cmd
    if sep == "\\" then
        cmd = 'mkdir "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'mkdir -p "' .. path .. '" 2>/dev/null'
    end
    os.execute(cmd)
    return true
end

-- Read entire file as binary
---@param path string file path
---@return string|nil data
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

-- Write binary data to file
---@param path string file path
---@param data string binary data
---@return boolean success
local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

-- Shader cache configuration
M.cache = {
    enabled = true,
    dir = "assets/shader_cache",
    version = 1,  -- Bump to invalidate all caches
}

-- Get shader cache file path
---@param source string shader source
---@param program_name string program name
---@param lang string shader language
---@return string path
local function get_cache_path(source, program_name, lang)
    local hash = hash_string(source)
    local filename = string.format("%s_%s_%08x.cache", program_name, lang, hash)
    return M.cache.dir .. "/" .. filename
end

-- Save compiled shader to cache
---@param cache_path string cache file path
---@param result table compile result from shdc
---@return boolean success
local function save_cache(cache_path, result)
    ensure_dir(M.cache.dir)

    local vs_src = result.vs_source or ""
    local fs_src = result.fs_source or ""

    -- Cache format:
    -- version (u8)
    -- has_bytecode (u8): 1 if bytecode, 0 if source only
    -- vs_bytecode_len (u32) + vs_bytecode
    -- fs_bytecode_len (u32) + fs_bytecode
    -- vs_source_len (u32) + vs_source
    -- fs_source_len (u32) + fs_source
    local has_bytecode = (result.vs_bytecode and result.fs_bytecode) and 1 or 0
    local data = string.pack("<BB I4 I4 I4 I4",
        M.cache.version,
        has_bytecode,
        #(result.vs_bytecode or ""),
        #(result.fs_bytecode or ""),
        #vs_src,
        #fs_src
    )
    data = data .. (result.vs_bytecode or "") .. (result.fs_bytecode or "") .. vs_src .. fs_src

    return write_file(cache_path, data)
end

-- Load compiled shader from cache
---@param cache_path string cache file path
---@return table|nil result compile result or nil if invalid
local function load_cache(cache_path)
    local data = read_file(cache_path)
    if not data or #data < 18 then return nil end

    local version, has_bytecode, vs_bc_len, fs_bc_len, vs_src_len, fs_src_len =
        string.unpack("<BB I4 I4 I4 I4", data)

    if version ~= M.cache.version then
        return nil  -- Version mismatch, invalidate cache
    end

    local offset = 18
    local vs_bytecode = nil
    local fs_bytecode = nil
    if has_bytecode == 1 and vs_bc_len > 0 and fs_bc_len > 0 then
        vs_bytecode = data:sub(offset + 1, offset + vs_bc_len)
        offset = offset + vs_bc_len
        fs_bytecode = data:sub(offset + 1, offset + fs_bc_len)
        offset = offset + fs_bc_len
    else
        offset = offset + vs_bc_len + fs_bc_len
    end

    local vs_source = nil
    local fs_source = nil
    if vs_src_len > 0 then
        vs_source = data:sub(offset + 1, offset + vs_src_len)
        offset = offset + vs_src_len
    end
    if fs_src_len > 0 then
        fs_source = data:sub(offset + 1, offset + fs_src_len)
    end

    return {
        success = true,
        vs_bytecode = vs_bytecode,
        fs_bytecode = fs_bytecode,
        vs_source = vs_source,
        fs_source = fs_source,
    }
end

-- Get shader language for current backend
function M.get_lang()
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
---@param source string shader source code
---@param program_name string program name in shader
---@param uniform_blocks? table uniform block descriptors
---@param attrs? table vertex attribute semantics for D3D11
---@param texture_sampler_pairs? table texture-sampler pair descriptors
---@return gfx.Shader? shader shader handle or nil on failure
function M.compile(source, program_name, uniform_blocks, attrs, texture_sampler_pairs)
    if not shdc then
        log.error("shdc module not available (requires MANE3D_BUILD_SHDC=ON)")
        return nil
    end
    local lang = M.get_lang()

    -- Try to load from cache first
    local cache_path = get_cache_path(source, program_name, lang)
    local result = nil

    if M.cache.enabled then
        result = load_cache(cache_path)
        if result then
            log.info("Loaded shader from cache: " .. program_name)
        end
    end

    -- Compile if not cached
    if not result then
        log.info("Compiling shader: " .. program_name .. " for " .. lang)

        result = shdc.compile(source, program_name, lang)
        if not result.success then
            log.error("Shader compile error: " .. (result.error or "unknown"))
            return nil
        end

        -- Save to cache
        if M.cache.enabled then
            if save_cache(cache_path, result) then
                log.info("Saved shader cache: " .. program_name)
            end
        end
    end

    log.info("Shader compiled: vs=" .. tostring(result.vs_source and #result.vs_source or "nil") .. " fs=" .. tostring(result.fs_source and #result.fs_source or "nil"))

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
        log.error("Missing shader data: vs=" .. tostring(vs_data) .. " fs=" .. tostring(fs_data))
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
        log.error("Failed to create shader")
        return nil
    end

    return shd
end

-- Compile shader with full descriptor control
---@param source string shader source code
---@param program_name string program name in shader
---@param shader_desc table full shader descriptor (uniform_blocks, views, samplers, texture_sampler_pairs, attrs)
---@return gfx.Shader? shader shader handle or nil on failure
function M.compile_full(source, program_name, shader_desc)
    if not shdc then
        log.error("shdc module not available (requires MANE3D_BUILD_SHDC=ON)")
        return nil
    end
    local lang = M.get_lang()

    -- Try to load from cache first
    local cache_path = get_cache_path(source, program_name, lang)
    local result = nil

    if M.cache.enabled then
        result = load_cache(cache_path)
        if result then
            log.info("Loaded shader from cache: " .. program_name)
        end
    end

    -- Compile if not cached
    if not result then
        log.info("Compiling shader: " .. program_name .. " for " .. lang)

        result = shdc.compile(source, program_name, lang)
        if not result.success then
            log.error("Shader compile error: " .. (result.error or "unknown"))
            return nil
        end

        -- Save to cache
        if M.cache.enabled then
            if save_cache(cache_path, result) then
                log.info("Saved shader cache: " .. program_name)
            end
        end
    end

    log.info("Shader compiled: vs=" .. tostring(result.vs_source and #result.vs_source or "nil") .. " fs=" .. tostring(result.fs_source and #result.fs_source or "nil"))

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
        log.error("Missing shader data")
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
        log.error("Failed to create shader")
        return nil
    end

    return shd
end

return M
