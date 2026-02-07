--- Tests for base36 module
local base36 = require("examples.rhythm.bms.base36")

local function test_decode_char()
    assert(base36.decode_char("0") == 0)
    assert(base36.decode_char("9") == 9)
    assert(base36.decode_char("A") == 10)
    assert(base36.decode_char("Z") == 35)
    assert(base36.decode_char("a") == 10, "lowercase should work")
    assert(base36.decode_char("z") == 35, "lowercase should work")
    assert(base36.decode_char("!") == nil, "invalid char")
    print("  decode_char: OK")
end

local function test_encode_char()
    assert(base36.encode_char(0) == "0")
    assert(base36.encode_char(9) == "9")
    assert(base36.encode_char(10) == "A")
    assert(base36.encode_char(35) == "Z")
    assert(base36.encode_char(-1) == nil, "negative")
    assert(base36.encode_char(36) == nil, "too large")
    print("  encode_char: OK")
end

local function test_decode()
    assert(base36.decode("00") == 0)
    assert(base36.decode("01") == 1)
    assert(base36.decode("0Z") == 35)
    assert(base36.decode("10") == 36)
    assert(base36.decode("ZZ") == 1295)
    assert(base36.decode("0a") == 10, "lowercase")
    assert(base36.decode("zz") == 1295, "lowercase")
    -- Invalid cases
    assert(base36.decode("") == nil, "empty")
    assert(base36.decode("0") == nil, "too short")
    assert(base36.decode("000") == nil, "too long")
    assert(base36.decode("!!") == nil, "invalid chars")
    print("  decode: OK")
end

local function test_encode()
    assert(base36.encode(0) == "00")
    assert(base36.encode(1) == "01")
    assert(base36.encode(35) == "0Z")
    assert(base36.encode(36) == "10")
    assert(base36.encode(1295) == "ZZ")
    -- Invalid cases
    assert(base36.encode(-1) == nil, "negative")
    assert(base36.encode(1296) == nil, "too large")
    assert(base36.encode(1.5) == nil, "not integer")
    print("  encode: OK")
end

local function test_roundtrip()
    for i = 0, 1295 do
        local encoded = base36.encode(i)
        local decoded = base36.decode(encoded)
        assert(decoded == i, string.format("roundtrip failed for %d", i))
    end
    print("  roundtrip (0-1295): OK")
end

local function test_is_valid()
    assert(base36.is_valid("00") == true)
    assert(base36.is_valid("ZZ") == true)
    assert(base36.is_valid("0a") == true)
    assert(base36.is_valid("") == false)
    assert(base36.is_valid("0") == false)
    assert(base36.is_valid("!!") == false)
    print("  is_valid: OK")
end

print("test_base36:")
test_decode_char()
test_encode_char()
test_decode()
test_encode()
test_roundtrip()
test_is_valid()
print("All base36 tests passed!")

return true
