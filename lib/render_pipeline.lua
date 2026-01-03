-- lib/render_pipeline.lua
-- Simple render pipeline with pass management and error handling
local gfx = require("sokol.gfx")
local util = require("lib.util")

---@class RenderPass
---@field name string Pass identifier
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

---Execute all registered passes
---@param ctx any Render context
---@param frame_data any Frame-specific data (view/proj matrices, etc.)
function M.execute(ctx, frame_data)
    for _, pass in ipairs(M.passes) do
        local ok_desc, desc = pcall(pass.get_pass_desc, ctx)
        if not ok_desc then
            util.warn("[" .. pass.name .. "] get_pass_desc error: " .. tostring(desc))
            desc = nil
        end

        if desc then
            gfx.begin_pass(desc)
            local ok, err = pcall(pass.execute, ctx, frame_data)
            if not ok then
                util.warn("[" .. pass.name .. "] execute error: " .. tostring(err))
            end
            gfx.end_pass()
        end
    end
    gfx.commit()
end

---Destroy all passes and clear the pipeline
function M.destroy()
    for _, pass in ipairs(M.passes) do
        if pass.destroy then
            local ok, err = pcall(pass.destroy)
            if not ok then
                util.warn("[" .. pass.name .. "] destroy error: " .. tostring(err))
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
