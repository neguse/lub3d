---@meta
-- LuaCATS type definitions for shdc (shader compiler)

---@class shdc
local shdc = {}

---Initialize the shader compiler
function shdc.init() end

---Shutdown the shader compiler
function shdc.shutdown() end

---@class shdc.CompileResult
---@field success boolean
---@field error? string
---@field vs_source? string
---@field fs_source? string
---@field vs_bytecode? string
---@field fs_bytecode? string

---Compile a shader from source
---@param source string Shader source code
---@param module_name string Module name for the shader
---@param target_lang string Target language (hlsl5, metal_macos, wgsl, glsl430, glsl300es)
---@return shdc.CompileResult
function shdc.compile(source, module_name, target_lang) end

return shdc
