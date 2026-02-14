-- lib/render_pipeline.lua
-- Simple render pipeline with pass management and error handling
local gfx = require("sokol.gfx")
local log = require("lib.log")

---@class RenderPass
---@field name string Pass identifier
---@field requires string[]? Optional list of required ctx.outputs keys
---@field get_pass_desc fun(ctx: any): any? Returns gfx.Pass desc, nil to skip
---@field execute fun(ctx: any, frame_data: any) Draw commands (called inside begin/end pass)
---@field destroy fun()? Optional cleanup

---@class RenderPipeline
local M = {}

---@type RenderPass[]
M.passes = {}

---Register a pass to the pipeline
---@param pass RenderPass
function M.register(pass)
    table.insert(M.passes, pass)
end

---Check if all required outputs are available
---@param pass RenderPass
---@param ctx any
---@return boolean ok
---@return string? missing_key
local function check_requirements(pass, ctx)
    if not pass.requires then return true end
    for _, key in ipairs(pass.requires) do
        if not ctx.outputs[key] then
            return false, key
        end
    end
    return true
end

---Execute all registered passes
---@param ctx any Render context
---@param frame_data any Frame-specific data (view/proj matrices, etc.)
function M.execute(ctx, frame_data)
    for _, pass in ipairs(M.passes) do
        -- Check required outputs before calling get_pass_desc
        local req_ok, missing = check_requirements(pass, ctx)
        if not req_ok then
            -- Silently skip - dependency not available (e.g., previous pass failed)
            goto continue
        end

        local ok_desc, desc = pcall(pass.get_pass_desc, ctx)
        if not ok_desc then
            log.warn("[" .. pass.name .. "] get_pass_desc error: " .. tostring(desc))
            desc = nil
        end

        if desc then
            gfx.begin_pass(desc)
            local ok, err = pcall(pass.execute, ctx, frame_data)
            if not ok then
                log.warn("[" .. pass.name .. "] execute error: " .. tostring(err))
            end
            gfx.end_pass()
        end

        ::continue::
    end
    gfx.commit()
end

---Destroy all passes and clear the pipeline
function M.destroy()
    for _, pass in ipairs(M.passes) do
        if pass.destroy then
            local ok, err = pcall(pass.destroy)
            if not ok then
                log.warn("[" .. pass.name .. "] destroy error: " .. tostring(err))
            end
        end
    end
    M.passes = {}
end

---Clear all registered passes without destroying them
function M.clear()
    M.passes = {}
end

return M
