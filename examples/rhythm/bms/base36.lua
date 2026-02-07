--- Base36 encoder/decoder for BMS IDs (00-ZZ → 0-1295)
---@class base36
local M = {}

local char_to_value = {}
local value_to_char = {}

-- Initialize lookup tables
for i = 0, 9 do
    local c = string.char(0x30 + i) -- '0'-'9'
    char_to_value[c] = i
    char_to_value[c:lower()] = i
    value_to_char[i] = c
end
for i = 0, 25 do
    local c = string.char(0x41 + i) -- 'A'-'Z'
    char_to_value[c] = 10 + i
    char_to_value[c:lower()] = 10 + i
    value_to_char[10 + i] = c
end

--- Decode a single base36 character to integer (0-35)
---@param c string single character
---@return integer|nil value nil if invalid
function M.decode_char(c)
    return char_to_value[c]
end

--- Encode a value (0-35) to base36 character
---@param v integer value 0-35
---@return string|nil char nil if out of range
function M.encode_char(v)
    return value_to_char[v]
end

--- Decode 2-character base36 string to integer (0-1295)
---@param s string 2-character string like "00", "ZZ", "0A"
---@return integer|nil value nil if invalid
function M.decode(s)
    if type(s) ~= "string" or #s ~= 2 then
        return nil
    end
    local hi = char_to_value[s:sub(1, 1)]
    local lo = char_to_value[s:sub(2, 2)]
    if not hi or not lo then
        return nil
    end
    return hi * 36 + lo
end

--- Encode integer (0-1295) to 2-character base36 string
---@param n integer value 0-1295
---@return string|nil str nil if out of range
function M.encode(n)
    if type(n) ~= "number" or n < 0 or n > 1295 or n ~= math.floor(n) then
        return nil
    end
    local hi = n // 36
    local lo = n % 36
    return value_to_char[hi] .. value_to_char[lo]
end

--- Check if a string is a valid 2-character base36 ID
---@param s string
---@return boolean
function M.is_valid(s)
    return M.decode(s) ~= nil
end

return M
