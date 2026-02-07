--- Input handler for rhythm game
local const = require("examples.rhythm.const")

---@class InputHandler
---@field key_states table<integer, boolean> lane -> pressed
---@field key_events table<integer, {pressed: boolean, time_us: integer}[]> lane -> event queue
---@field key_mapping table<integer, integer> keycode -> lane
local InputHandler = {}
InputHandler.__index = InputHandler

--- Create a new InputHandler
---@param key_mapping table<integer, integer>? custom keycode -> lane mapping
---@return InputHandler
function InputHandler.new(key_mapping)
    local self = setmetatable({}, InputHandler)
    self.key_mapping = key_mapping or const.KEY_MAPPING
    self.key_states = {}
    self.key_events = {}

    -- Initialize all lanes
    for lane = 1, const.NUM_LANES do
        self.key_states[lane] = false
        self.key_events[lane] = {}
    end

    return self
end

--- Process a key event
---@param keycode integer sokol app keycode
---@param pressed boolean true if key down, false if key up
---@param time_us integer event time in μs
function InputHandler:on_key(keycode, pressed, time_us)
    local lane = self.key_mapping[keycode]
    if not lane then
        return
    end

    self.key_states[lane] = pressed

    -- Record event
    local events = self.key_events[lane]
    events[#events + 1] = {
        pressed = pressed,
        time_us = time_us,
    }
end

--- Check if a lane is currently pressed
---@param lane integer
---@return boolean
function InputHandler:is_pressed(lane)
    return self.key_states[lane] or false
end

--- Get all key down events for a lane and clear them
---@param lane integer
---@return table[] events {pressed: boolean, time_us: integer}
function InputHandler:consume_events(lane)
    local events = self.key_events[lane]
    self.key_events[lane] = {}
    return events
end

--- Clear all events
function InputHandler:clear_events()
    for lane = 1, const.NUM_LANES do
        self.key_events[lane] = {}
    end
end

--- Get all current key states
---@return table<integer, boolean>
function InputHandler:get_states()
    return self.key_states
end

return InputHandler
