-- lib/render_pass.lua
-- Helper for render passes with common resource management
local gfx = require("sokol.gfx")
local gpu = require("lib.gpu")

-- Optional notify module
local notify = nil
pcall(function() notify = require("lib.notify") end)

local M = {}

---Setup common resource management on a pass module
---@param pass table The pass module table
---@param opts {shader_name: string, pipeline_desc: fun(shader_handle: any): gfx.PipelineDesc}
function M.setup(pass, opts)
    -- Preserve across hotreload
    pass.resources = pass.resources
    pass._compile_attempted = pass._compile_attempted or false

    ---Ensure shader/pipeline resources are initialized
    ---@return boolean success
    function pass.ensure_resources()
        if pass.resources then return true end
        if pass._compile_attempted then return false end
        pass._compile_attempted = true

        local shader = gpu.shader(pass.shader_source, opts.shader_name, pass.shader_desc)
        if not shader then
            if notify then notify.error("[shader] " .. pass.name .. " FAILED") end
            return false
        end

        local pip_desc = opts.pipeline_desc(shader.handle)
        local pipeline = gpu.pipeline(pip_desc)

        pass.resources = { shader = shader, pipeline = pipeline }
        if notify then notify.ok("[shader] " .. pass.name .. " OK") end
        return true
    end

    ---Called by hotreload when this module is reloaded
    function pass.on_reload()
        if pass.resources then
            pass.resources.pipeline:destroy()
            pass.resources.shader:destroy()
            pass.resources = nil
        end
        pass._compile_attempted = false
    end

    ---Destroy pass resources
    function pass.destroy()
        if pass.resources then
            pass.resources.pipeline:destroy()
            pass.resources.shader:destroy()
            pass.resources = nil
        end
        pass._compile_attempted = false
    end
end

return M
