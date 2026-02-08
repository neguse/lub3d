--- Shift_JIS to UTF-8 encoding conversion
--- Uses Windows API for accurate conversion
---@class encoding
local M = {}

-- Try to load C encoding module
local c_encoding
local ok, mod = pcall(require, "mane3d.encoding")
if ok then
    c_encoding = mod
end

-- Common Shift_JIS to UTF-8 mappings (subset for BMS files)
-- Full conversion would require a complete mapping table
local SJIS_TO_UTF8 = {
    -- Half-width katakana (0xA1-0xDF)
    [0xA1] = "\xEF\xBD\xA1", -- ｡
    [0xA2] = "\xEF\xBD\xA2", -- ｢
    [0xA3] = "\xEF\xBD\xA3", -- ｣
    [0xA4] = "\xEF\xBD\xA4", -- ､
    [0xA5] = "\xEF\xBD\xA5", -- ･
    [0xA6] = "\xEF\xBD\xB6", -- ｶ (should be ｦ but mapped to common usage)
    -- ... more half-width katakana would go here
}

-- Check if byte is ASCII (0x00-0x7F)
local function is_ascii(b)
    return b >= 0x00 and b <= 0x7F
end

-- Check if byte is Shift_JIS lead byte
local function is_sjis_lead(b)
    return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC)
end

-- Check if byte is Shift_JIS half-width katakana (0xA1-0xDF)
local function is_sjis_halfwidth_kana(b)
    return b >= 0xA1 and b <= 0xDF
end

-- Convert Shift_JIS double-byte character to UTF-8
-- This is a simplified conversion that may not handle all edge cases
local function sjis_to_utf8_char(lead, trail)
    -- Convert Shift_JIS to JIS X 0208 code point
    local adjust = (trail < 0x9F) and 1 or 0
    local row = (lead - (lead < 0xA0 and 0x70 or 0xB0)) * 2 - adjust
    local col = trail - (trail < 0x9F and (trail > 0x7F and 0x20 or 0x1F) or 0x7E)

    -- Convert JIS X 0208 to Unicode (simplified mapping)
    -- This would need a full mapping table for complete accuracy
    local unicode = 0x3000 + (row - 1) * 94 + (col - 1)

    -- For now, return a placeholder for unmapped characters
    -- Full implementation would use a complete SJIS->Unicode table
    if unicode >= 0x3000 and unicode <= 0xFFFF then
        -- Encode as UTF-8
        if unicode < 0x800 then
            return string.char(
                0xC0 + math.floor(unicode / 64),
                0x80 + (unicode % 64)
            )
        else
            return string.char(
                0xE0 + math.floor(unicode / 4096),
                0x80 + math.floor((unicode % 4096) / 64),
                0x80 + (unicode % 64)
            )
        end
    end

    -- Fallback: return original bytes as-is (will be garbled)
    return string.char(lead, trail)
end

--- Detect encoding from BOM or content analysis
---@param data string raw file data
---@return string encoding "utf8", "utf16le", "utf16be", or "sjis"
function M.detect_encoding(data)
    if #data < 2 then
        return "sjis" -- Default assumption for BMS
    end

    local b1, b2, b3 = data:byte(1, 3)

    -- UTF-8 BOM
    if b1 == 0xEF and b2 == 0xBB and b3 == 0xFE then
        return "utf8"
    end

    -- UTF-16 LE BOM
    if b1 == 0xFF and b2 == 0xFE then
        return "utf16le"
    end

    -- UTF-16 BE BOM
    if b1 == 0xFE and b2 == 0xFF then
        return "utf16be"
    end

    -- Check for valid UTF-8 sequences
    local valid_utf8 = true
    local i = 1
    local has_high_bytes = false
    while i <= #data and i <= 1000 do -- Check first 1000 bytes
        local b = data:byte(i)
        if b > 0x7F then
            has_high_bytes = true
            if b >= 0xC0 and b <= 0xDF then
                -- 2-byte UTF-8
                if i + 1 > #data then
                    valid_utf8 = false
                    break
                end
                local b2 = data:byte(i + 1)
                if b2 < 0x80 or b2 > 0xBF then
                    valid_utf8 = false
                    break
                end
                i = i + 2
            elseif b >= 0xE0 and b <= 0xEF then
                -- 3-byte UTF-8
                if i + 2 > #data then
                    valid_utf8 = false
                    break
                end
                local b2, b3 = data:byte(i + 1, i + 2)
                if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then
                    valid_utf8 = false
                    break
                end
                i = i + 3
            elseif b >= 0xF0 and b <= 0xF7 then
                -- 4-byte UTF-8
                if i + 3 > #data then
                    valid_utf8 = false
                    break
                end
                local b2, b3, b4 = data:byte(i + 1, i + 3)
                if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF or b4 < 0x80 or b4 > 0xBF then
                    valid_utf8 = false
                    break
                end
                i = i + 4
            else
                valid_utf8 = false
                break
            end
        else
            i = i + 1
        end
    end

    if valid_utf8 and has_high_bytes then
        return "utf8"
    end

    -- Default to Shift_JIS for Japanese BMS files
    return "sjis"
end

--- Remove BOM if present
---@param data string
---@return string data_without_bom
function M.strip_bom(data)
    if #data >= 3 then
        local b1, b2, b3 = data:byte(1, 3)
        -- UTF-8 BOM
        if b1 == 0xEF and b2 == 0xBB and b3 == 0xBF then
            return data:sub(4)
        end
    end
    if #data >= 2 then
        local b1, b2 = data:byte(1, 2)
        -- UTF-16 LE/BE BOM
        if (b1 == 0xFF and b2 == 0xFE) or (b1 == 0xFE and b2 == 0xFF) then
            return data:sub(3)
        end
    end
    return data
end

--- Convert Shift_JIS string to UTF-8
---@param data string Shift_JIS encoded string
---@return string utf8_string
function M.sjis_to_utf8(data)
    -- Use C module if available (Windows API, accurate)
    if c_encoding then
        return c_encoding.sjis_to_utf8(data)
    end

    -- Fallback: simplified Lua implementation (may be inaccurate)
    local result = {}
    local i = 1
    local len = #data

    while i <= len do
        local b = data:byte(i)

        if is_ascii(b) then
            -- ASCII character, pass through
            result[#result + 1] = string.char(b)
            i = i + 1
        elseif is_sjis_halfwidth_kana(b) then
            -- Half-width katakana
            local utf8 = SJIS_TO_UTF8[b]
            if utf8 then
                result[#result + 1] = utf8
            else
                -- Convert half-width katakana to UTF-8
                -- 0xA1-0xDF maps to U+FF61-U+FF9F
                local unicode = 0xFF61 + (b - 0xA1)
                result[#result + 1] = string.char(
                    0xEF,
                    0xBD + math.floor((unicode - 0xFF00) / 64),
                    0x80 + ((unicode - 0xFF00) % 64)
                )
            end
            i = i + 1
        elseif is_sjis_lead(b) then
            -- Double-byte character
            if i + 1 <= len then
                local trail = data:byte(i + 1)
                result[#result + 1] = sjis_to_utf8_char(b, trail)
                i = i + 2
            else
                -- Invalid: lead byte without trail byte
                result[#result + 1] = "?"
                i = i + 1
            end
        else
            -- Unknown byte, pass through (may result in garbled text)
            result[#result + 1] = string.char(b)
            i = i + 1
        end
    end

    return table.concat(result)
end

--- Convert file content to UTF-8, auto-detecting encoding
---@param data string raw file content
---@return string utf8_content
function M.to_utf8(data)
    local encoding = M.detect_encoding(data)
    data = M.strip_bom(data)

    if encoding == "utf8" then
        return data
    elseif encoding == "sjis" then
        return M.sjis_to_utf8(data)
    elseif encoding == "utf16le" or encoding == "utf16be" then
        -- UTF-16 conversion not implemented
        -- Most BMS files use Shift_JIS or UTF-8
        return data
    end

    return data
end

return M
