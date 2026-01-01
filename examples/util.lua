-- Utility functions for mane3d examples
local gfx = require("sokol.gfx")
local slog = require("sokol.log")

local M = {}

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
-- @return shader handle or nil on failure
function M.compile_shader(source, program_name, uniform_blocks, attrs)
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

-- Helper to pack vertex data as floats
function M.pack_floats(floats)
    return string.pack(string.rep("f", #floats), table.unpack(floats))
end

return M
