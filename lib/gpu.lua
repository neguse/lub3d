-- lib/gpu.lua
-- GPU resource wrappers with GC support
local gfx = require("sokol.gfx")
local util = require("lib.util")

---@class gpu
local M = {}

-- Verify table __gc support at load time (requires Lua 5.2+)
local gc_supported = (function()
    local test_flag = { called = false }
    local _ = setmetatable({}, {
        __gc = function() test_flag.called = true end
    })
    _ = nil  ---@diagnostic disable-line: cast-local-type
    collectgarbage("collect")
    if not test_flag.called then
        util.warn("[gpu] Table __gc not supported - GPU resources may leak if not explicitly destroyed")
    end
    return test_flag.called
end)()

---@class gpu.Resource
---@field handle any
---@field destroy fun(self: gpu.Resource)

---@class gpu.Image: gpu.Resource
---@class gpu.View: gpu.Resource
---@class gpu.Buffer: gpu.Resource
---@class gpu.Sampler: gpu.Resource
---@class gpu.Shader: gpu.Resource
---@class gpu.Pipeline: gpu.Resource

-- Shared metatable for GC support
local gc_mt = {
    __gc = function(self)
        if self.handle and self._destroy_fn then
            self._destroy_fn(self.handle)
            self.handle = nil
        end
    end
}

---Generic wrapper with __gc
---@param handle any
---@param destroy_fn function
---@return gpu.Resource
local function wrap(handle, destroy_fn)
    local obj = {
        handle = handle,
        _destroy_fn = destroy_fn,
    }
    function obj:destroy()
        if self.handle then
            self._destroy_fn(self.handle)
            self.handle = nil
        end
    end
    return setmetatable(obj, gc_mt)
end

---Create an image resource
---@param desc gfx.ImageDesc
---@return gpu.Image
function M.image(desc)
    return wrap(gfx.make_image(desc), gfx.destroy_image) --[[@as gpu.Image]]
end

---Create a view resource
---@param desc gfx.ViewDesc
---@return gpu.View
function M.view(desc)
    return wrap(gfx.make_view(desc), gfx.destroy_view) --[[@as gpu.View]]
end

---Create a buffer resource
---@param desc gfx.BufferDesc
---@return gpu.Buffer
function M.buffer(desc)
    return wrap(gfx.make_buffer(desc), gfx.destroy_buffer) --[[@as gpu.Buffer]]
end

---Create a sampler resource
---@param desc gfx.SamplerDesc
---@return gpu.Sampler
function M.sampler(desc)
    return wrap(gfx.make_sampler(desc), gfx.destroy_sampler) --[[@as gpu.Sampler]]
end

---Compile and create a shader resource
---@param source string Shader source code
---@param name string Program name
---@param desc table Shader descriptor
---@return gpu.Shader?
function M.shader(source, name, desc)
    local handle = util.compile_shader_full(source, name, desc)
    if not handle then
        util.error("Failed to compile shader: " .. name)
        return nil
    end
    return wrap(handle, gfx.destroy_shader) --[[@as gpu.Shader]]
end

---Create a pipeline resource
---@param desc gfx.PipelineDesc
---@return gpu.Pipeline
function M.pipeline(desc)
    return wrap(gfx.make_pipeline(desc), gfx.destroy_pipeline) --[[@as gpu.Pipeline]]
end

return M
