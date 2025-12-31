-- Utility functions for mane3d examples
local gfx = require("sokol.gfx")
local slog = require("sokol.log")

local M = {}

-- Log using sokol_log (OutputDebugString on Windows)
function M.log(msg)
    slog.func("lua", 1, 0, msg, 0, "", nil)
end

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

-- Find Windows SDK path for fxc.exe
function M.find_fxc_path()
    local sdk_base = "C:\\Program Files (x86)\\Windows Kits\\10\\bin"
    local handle = io.popen('dir "' .. sdk_base .. '" /b /ad 2>nul')
    if not handle then return nil end

    local latest = nil
    for line in handle:lines() do
        if line:match("^10%.") then latest = line end
    end
    handle:close()

    if latest then
        local path = sdk_base .. "\\" .. latest .. "\\x64"
        local f = io.open(path .. "\\fxc.exe", "rb")
        if f then
            f:close()
            return path
        end
    end
    return nil
end

-- Compile shader using sokol-shdc
-- @param source string: shader source code
-- @param program_name string: program name in shader
-- @param uniform_blocks table|nil: optional uniform block descriptors
-- @return shader handle or nil on failure
function M.compile_shader(source, program_name, uniform_blocks)
    local tmp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local tmp_glsl = tmp_dir .. "/shader_" .. os.time() .. ".glsl"
    local tmp_out = tmp_dir .. "/shader_" .. os.time()

    -- Write shader source
    local f = assert(io.open(tmp_glsl, "w"))
    f:write(source)
    f:close()

    local lang = M.get_shader_lang()
    local fxc_path = (lang == "hlsl5" or lang == "hlsl4") and M.find_fxc_path() or nil

    -- Run sokol-shdc
    local ok
    if fxc_path then
        local bat_file = tmp_dir .. "\\run_shdc.bat"
        local bat = assert(io.open(bat_file, "w"))
        bat:write('set PATH=%PATH%;' .. fxc_path .. '\r\n')
        bat:write('sokol-shdc -i "' ..
        tmp_glsl:gsub("/", "\\") .. '" -o "' .. tmp_out:gsub("/", "\\") .. '" -l ' .. lang .. ' -f bare -b\r\n')
        bat:close()
        ok = os.execute('cmd /c "' .. bat_file .. '"')
        os.remove(bat_file)
    else
        ok = os.execute(string.format('sokol-shdc -i "%s" -o "%s" -l %s -f bare -b', tmp_glsl, tmp_out, lang))
    end

    os.remove(tmp_glsl)

    if not ok then
        M.log("Failed to run sokol-shdc")
        return nil
    end

    -- Determine output file extensions
    local vs_file, fs_file
    if lang == "hlsl5" or lang == "hlsl4" then
        vs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_vertex.fxc"
        fs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_fragment.fxc"
    elseif lang:find("glsl") then
        vs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_vertex.glsl"
        fs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_fragment.glsl"
    elseif lang:find("metal") then
        vs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_vertex.metallib"
        fs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_fragment.metallib"
    elseif lang == "wgsl" then
        vs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_vertex.wgsl"
        fs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_fragment.wgsl"
    else
        vs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_vertex.bin"
        fs_file = tmp_out .. "_" .. program_name .. "_" .. lang .. "_fragment.bin"
    end

    -- Read shader files
    local vs_f = io.open(vs_file, "rb")
    if not vs_f then
        M.log("Failed to open VS file: " .. vs_file)
        return nil
    end
    local vs_data = vs_f:read("*a")
    vs_f:close()

    local fs_f = io.open(fs_file, "rb")
    if not fs_f then
        M.log("Failed to open FS file: " .. fs_file)
        return nil
    end
    local fs_data = fs_f:read("*a")
    fs_f:close()

    os.remove(vs_file)
    os.remove(fs_file)

    -- Create shader using generated bindings
    local backend = gfx.query_backend()
    local is_glsl = (backend == gfx.Backend.GLCORE or backend == gfx.Backend.GLES3)

    local desc_table = {
        vertex_func = is_glsl and { source = vs_data } or { bytecode = vs_data },
        fragment_func = is_glsl and { source = fs_data } or { bytecode = fs_data },
    }

    -- Add uniform blocks if specified
    if uniform_blocks then
        desc_table.uniform_blocks = uniform_blocks
    end

    -- D3D11 needs attribute semantics
    if backend == gfx.Backend.D3D11 then
        desc_table.attrs = {
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
            { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
        }
    end

    local shd = gfx.make_shader(gfx.ShaderDesc(desc_table))
    if gfx.query_shader_state(shd) ~= gfx.ResourceState.VALID then
        M.log("Failed to create shader")
        return nil
    end

    return shd
end

-- Helper to pack vertex data as floats
function M.pack_floats(floats)
    return string.pack(string.rep("f", #floats), table.unpack(floats))
end

return M
