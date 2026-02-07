--- Lane rendering
local const = require("examples.rhythm.const")

---@class LaneRenderer
---@field sgl any sokol.gl module
local LaneRenderer = {}
LaneRenderer.__index = LaneRenderer

--- Create a new LaneRenderer
---@param sgl any sokol.gl module
---@return LaneRenderer
function LaneRenderer.new(sgl)
    local self = setmetatable({}, LaneRenderer)
    self.sgl = sgl
    return self
end

--- Calculate lane X position
---@param lane integer 1-8
---@return number x center X position
function LaneRenderer:get_lane_x(lane)
    local total_width = const.NUM_LANES * const.LANE_WIDTH
    local start_x = (const.SCREEN_WIDTH - total_width) / 2
    return start_x + (lane - 0.5) * const.LANE_WIDTH
end

--- Draw all lanes background
---@param key_states table<integer, boolean> lane -> pressed
function LaneRenderer:draw_lanes(key_states)
    local sgl = self.sgl
    local total_width = const.NUM_LANES * const.LANE_WIDTH
    local start_x = (const.SCREEN_WIDTH - total_width) / 2
    local top_y = const.JUDGMENT_LINE_Y - const.LANE_HEIGHT

    for lane = 1, const.NUM_LANES do
        local x = start_x + (lane - 1) * const.LANE_WIDTH
        local color = const.LANE_COLORS[lane]
        local alpha = key_states[lane] and 0.4 or 0.2

        -- Lane background
        sgl.C4f(color[1], color[2], color[3], alpha)
        sgl.BeginQuads()
        sgl.V2f(x, top_y)
        sgl.V2f(x + const.LANE_WIDTH, top_y)
        sgl.V2f(x + const.LANE_WIDTH, const.JUDGMENT_LINE_Y)
        sgl.V2f(x, const.JUDGMENT_LINE_Y)
        sgl.End()

        -- Lane border
        sgl.C4f(0.5, 0.5, 0.5, 0.5)
        sgl.BeginLineStrip()
        sgl.V2f(x, top_y)
        sgl.V2f(x, const.JUDGMENT_LINE_Y)
        sgl.End()
    end

    -- Right border of last lane
    local right_x = start_x + const.NUM_LANES * const.LANE_WIDTH
    sgl.C4f(0.5, 0.5, 0.5, 0.5)
    sgl.BeginLineStrip()
    sgl.V2f(right_x, top_y)
    sgl.V2f(right_x, const.JUDGMENT_LINE_Y)
    sgl.End()
end

--- Draw key beams (bright gradient pillars on pressed lanes)
---@param key_states table<integer, boolean> lane -> pressed
function LaneRenderer:draw_key_beams(key_states)
    local sgl = self.sgl
    local total_width = const.NUM_LANES * const.LANE_WIDTH
    local start_x = (const.SCREEN_WIDTH - total_width) / 2
    local top_y = const.JUDGMENT_LINE_Y - const.LANE_HEIGHT
    local bottom_y = const.JUDGMENT_LINE_Y

    for lane = 1, const.NUM_LANES do
        if key_states[lane] then
            local x = start_x + (lane - 1) * const.LANE_WIDTH
            local color = const.LANE_COLORS[lane]
            -- Brighten: blend lane color toward white
            local r = math.min(1.0, color[1] + 0.3)
            local g = math.min(1.0, color[2] + 0.3)
            local b = math.min(1.0, color[3] + 0.3)

            sgl.BeginQuads()
            -- Top two vertices: transparent
            sgl.C4f(r, g, b, 0.0)
            sgl.V2f(x, top_y)
            sgl.C4f(r, g, b, 0.0)
            sgl.V2f(x + const.LANE_WIDTH, top_y)
            -- Bottom two vertices: bright
            sgl.C4f(r, g, b, 0.6)
            sgl.V2f(x + const.LANE_WIDTH, bottom_y)
            sgl.C4f(r, g, b, 0.6)
            sgl.V2f(x, bottom_y)
            sgl.End()
        end
    end
end

--- Draw judgment line
function LaneRenderer:draw_judgment_line()
    local sgl = self.sgl
    local total_width = const.NUM_LANES * const.LANE_WIDTH
    local start_x = (const.SCREEN_WIDTH - total_width) / 2

    sgl.C4f(1.0, 1.0, 0.0, 1.0) -- Yellow
    sgl.BeginLines()
    sgl.V2f(start_x, const.JUDGMENT_LINE_Y)
    sgl.V2f(start_x + total_width, const.JUDGMENT_LINE_Y)
    sgl.End()
end

return LaneRenderer
