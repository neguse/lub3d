--- Note rendering
local const = require("examples.rhythm.const")

---@class NoteRenderer
---@field sgl any sokol.gl module
---@field lane_renderer LaneRenderer
local NoteRenderer = {}
NoteRenderer.__index = NoteRenderer

--- Create a new NoteRenderer
---@param sgl any sokol.gl module
---@param lane_renderer LaneRenderer
---@return NoteRenderer
function NoteRenderer.new(sgl, lane_renderer)
    local self = setmetatable({}, NoteRenderer)
    self.sgl = sgl
    self.lane_renderer = lane_renderer
    return self
end

--- Calculate Y position for a note based on beat
---@param note_beat number
---@param current_beat number
---@param scroll_speed number
---@return number y screen Y position
function NoteRenderer:calc_note_y(note_beat, current_beat, scroll_speed)
    local relative_beat = note_beat - current_beat
    local y = const.JUDGMENT_LINE_Y - relative_beat * const.PIXELS_PER_BEAT * scroll_speed
    return y
end

--- Draw a single note
---@param note Note
---@param current_beat number
---@param scroll_speed number
function NoteRenderer:draw_note(note, current_beat, scroll_speed)
    local sgl = self.sgl

    local x = self.lane_renderer:get_lane_x(note.lane)
    local y = self:calc_note_y(note.beat, current_beat, scroll_speed)

    -- Cull notes outside visible area
    local top_y = const.JUDGMENT_LINE_Y - const.LANE_HEIGHT - const.NOTE_HEIGHT
    local bottom_y = const.JUDGMENT_LINE_Y + const.NOTE_HEIGHT
    if y < top_y or y > bottom_y then
        return
    end

    local half_width = (const.LANE_WIDTH - 4) / 2
    local half_height = const.NOTE_HEIGHT / 2

    local color = const.LANE_COLORS[note.lane]

    -- Black background (larger)
    sgl.c4f(0.0, 0.0, 0.0, 1.0)
    sgl.begin_quads()
    sgl.v2f(x - half_width - 2, y - half_height - 2)
    sgl.v2f(x + half_width + 2, y - half_height - 2)
    sgl.v2f(x + half_width + 2, y + half_height + 2)
    sgl.v2f(x - half_width - 2, y + half_height + 2)
    sgl.end_()

    -- Note body (colored fill)
    sgl.c4f(color[1], color[2], color[3], 1.0)
    sgl.begin_quads()
    sgl.v2f(x - half_width, y - half_height)
    sgl.v2f(x + half_width, y - half_height)
    sgl.v2f(x + half_width, y + half_height)
    sgl.v2f(x - half_width, y + half_height)
    sgl.end_()

    -- White border
    sgl.c4f(1.0, 1.0, 1.0, 1.0)
    sgl.begin_line_strip()
    sgl.v2f(x - half_width - 2, y - half_height - 2)
    sgl.v2f(x + half_width + 2, y - half_height - 2)
    sgl.v2f(x + half_width + 2, y + half_height + 2)
    sgl.v2f(x - half_width - 2, y + half_height + 2)
    sgl.v2f(x - half_width - 2, y - half_height - 2)
    sgl.end_()
end

--- Draw all visible notes
---@param notes Note[]
---@param current_beat number
---@param scroll_speed number
function NoteRenderer:draw_notes(notes, current_beat, scroll_speed)
    for _, note in ipairs(notes) do
        self:draw_note(note, current_beat, scroll_speed)
    end
end

return NoteRenderer
