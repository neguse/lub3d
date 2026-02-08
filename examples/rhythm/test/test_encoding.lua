--- Tests for encoding module
local encoding = require("examples.rhythm.bms.encoding")

local function test_detect_encoding_ascii()
    local data = "Hello World\n#TITLE Test"
    assert(encoding.detect_encoding(data) == "sjis", "ASCII-only should default to sjis")
    print("  detect_encoding_ascii: OK")
end

local function test_detect_encoding_utf8_bom()
    local data = "\xEF\xBB\xBFHello"
    assert(encoding.detect_encoding(data) == "utf8")
    print("  detect_encoding_utf8_bom: OK")
end

local function test_detect_encoding_utf8_content()
    -- Japanese text in UTF-8: "テスト"
    local data = "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88"
    assert(encoding.detect_encoding(data) == "utf8")
    print("  detect_encoding_utf8_content: OK")
end

local function test_strip_bom_utf8()
    local data = "\xEF\xBB\xBFHello"
    local result = encoding.strip_bom(data)
    assert(result == "Hello", "UTF-8 BOM should be stripped")
    print("  strip_bom_utf8: OK")
end

local function test_strip_bom_utf16le()
    local data = "\xFF\xFEHello"
    local result = encoding.strip_bom(data)
    assert(result == "Hello", "UTF-16 LE BOM should be stripped")
    print("  strip_bom_utf16le: OK")
end

local function test_strip_bom_none()
    local data = "Hello"
    local result = encoding.strip_bom(data)
    assert(result == "Hello", "Data without BOM should be unchanged")
    print("  strip_bom_none: OK")
end

local function test_sjis_to_utf8_ascii()
    local data = "Hello World 123"
    local result = encoding.sjis_to_utf8(data)
    assert(result == "Hello World 123", "ASCII should pass through unchanged")
    print("  sjis_to_utf8_ascii: OK")
end

local function test_to_utf8_already_utf8()
    -- UTF-8 Japanese: "テスト"
    local data = "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88"
    local result = encoding.to_utf8(data)
    assert(result == data, "UTF-8 should pass through unchanged")
    print("  to_utf8_already_utf8: OK")
end

local function test_to_utf8_with_bom()
    local data = "\xEF\xBB\xBFHello"
    local result = encoding.to_utf8(data)
    assert(result == "Hello", "BOM should be stripped")
    print("  to_utf8_with_bom: OK")
end

print("test_encoding:")
test_detect_encoding_ascii()
test_detect_encoding_utf8_bom()
test_detect_encoding_utf8_content()
test_strip_bom_utf8()
test_strip_bom_utf16le()
test_strip_bom_none()
test_sjis_to_utf8_ascii()
test_to_utf8_already_utf8()
test_to_utf8_with_bom()
print("All encoding tests passed!")

return true
