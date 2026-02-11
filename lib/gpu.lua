-- lib/gpu.lua
-- GPU resource wrappers with GC support
local gfx = require("sokol.gfx")
local slog = require("sokol.log")
local log = require("lib.log")
local shader = require("lib.shader")

---@class gpu
local M = {}

-- Verify table __gc support at load time (requires Lua 5.2+)
local gc_supported = (function()
    local test_flag = { called = false }
    local _ = setmetatable({}, {
        __gc = function() test_flag.called = true end
    })
    _ = nil ---@diagnostic disable-line: cast-local-type
    collectgarbage("collect")
    if not test_flag.called then
        slog.Func("lua", 2, 0, "[gpu] Table __gc not supported - GPU resources may leak if not explicitly destroyed", 0,
            "", nil)
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
---@param desc sokol.gfx.ImageDesc
---@return gpu.Image
function M.image(desc)
    return wrap(gfx.MakeImage(desc), gfx.DestroyImage) --[[@as gpu.Image]]
end

---Create a view resource
---@param desc sokol.gfx.ViewDesc
---@return gpu.View
function M.view(desc)
    return wrap(gfx.MakeView(desc), gfx.DestroyView) --[[@as gpu.View]]
end

---Create a buffer resource
---@param desc sokol.gfx.BufferDesc
---@return gpu.Buffer
function M.buffer(desc)
    return wrap(gfx.MakeBuffer(desc), gfx.DestroyBuffer) --[[@as gpu.Buffer]]
end

---Create a sampler resource
---@param desc sokol.gfx.SamplerDesc
---@return gpu.Sampler
function M.sampler(desc)
    return wrap(gfx.MakeSampler(desc), gfx.DestroySampler) --[[@as gpu.Sampler]]
end

---Compile and create a shader resource
---@param source string Shader source code
---@param name string Program name
---@param desc table Shader descriptor
---@return gpu.Shader?
function M.shader(source, name, desc)
    local handle = shader.compile_full(source, name, desc)
    if not handle then
        log.error("Failed to compile shader: " .. name)
        return nil
    end
    return wrap(handle, gfx.DestroyShader) --[[@as gpu.Shader]]
end

---Create a pipeline resource
---@param desc sokol.gfx.PipelineDesc
---@return gpu.Pipeline
function M.pipeline(desc)
    return wrap(gfx.MakePipeline(desc), gfx.DestroyPipeline) --[[@as gpu.Pipeline]]
end

return M
