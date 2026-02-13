-- glm.lua: OpenGL Mathematics for Lua
-- Inspired by GLM (OpenGL Mathematics) C++ library

---@class glm
local glm = {}

--------------------------------------------------------------------------------
-- Base vector class (for type annotations only)
--------------------------------------------------------------------------------

---@class vec_base
---@field length fun(self): number
---@field length2 fun(self): number
---@field normalize fun(self): vec_base
---@field dot fun(self, other: vec_base): number

--------------------------------------------------------------------------------
-- vec2
--------------------------------------------------------------------------------

---@class vec2: vec_base
---@field x number
---@field y number
---@field length fun(self: vec2): number
---@field length2 fun(self: vec2): number
---@field normalize fun(self: vec2): vec2
---@field dot fun(self: vec2, other: vec2): number
---@operator add(vec2): vec2
---@operator sub(vec2): vec2
---@operator mul(vec2|number): vec2
---@operator div(vec2|number): vec2
---@operator unm: vec2
local vec2 = {}
vec2.__index = vec2

---Create a 2D vector
---@param x number?
---@param y number?
---@return vec2
function glm.vec2(x, y)
    return setmetatable({ x = x or 0, y = y or 0 }, vec2)
end

---@param a vec2
---@param b vec2
---@return vec2
function vec2.__add(a, b)
    return glm.vec2(a.x + b.x, a.y + b.y)
end

---@param a vec2
---@param b vec2
---@return vec2
function vec2.__sub(a, b)
    return glm.vec2(a.x - b.x, a.y - b.y)
end

---@param a vec2|number
---@param b vec2|number
---@return vec2
function vec2.__mul(a, b)
    if type(a) == "number" then
        ---@cast b vec2
        return glm.vec2(a * b.x, a * b.y)
    elseif type(b) == "number" then
        ---@cast a vec2
        return glm.vec2(a.x * b, a.y * b)
    else
        ---@cast a vec2
        ---@cast b vec2
        return glm.vec2(a.x * b.x, a.y * b.y)
    end
end

---@param a vec2
---@param b vec2|number
---@return vec2
function vec2.__div(a, b)
    if type(b) == "number" then
        return glm.vec2(a.x / b, a.y / b)
    else
        ---@cast b vec2
        return glm.vec2(a.x / b.x, a.y / b.y)
    end
end

---@param a vec2
---@return vec2
function vec2.__unm(a)
    return glm.vec2(-a.x, -a.y)
end

---@param a vec2
---@param b vec2
---@return boolean
function vec2.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

---@param v vec2
---@return string
function vec2.__tostring(v)
    return string.format("vec2(%.4f, %.4f)", v.x, v.y)
end

---Get the length of the vector
---@return number
function vec2:length()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

---Get the squared length of the vector
---@return number
function vec2:length2()
    return self.x * self.x + self.y * self.y
end

---Get the normalized vector
---@return vec2
function vec2:normalize()
    local len = self:length()
    if len > 0 then
        return glm.vec2(self.x / len, self.y / len)
    end
    return glm.vec2(0, 0)
end

---Dot product
---@param other vec2
---@return number
function vec2:dot(other)
    return self.x * other.x + self.y * other.y
end

--------------------------------------------------------------------------------
-- vec3
--------------------------------------------------------------------------------

---@class vec3: vec_base
---@field x number
---@field y number
---@field z number
---@field length fun(self: vec3): number
---@field length2 fun(self: vec3): number
---@field normalize fun(self: vec3): vec3
---@field dot fun(self: vec3, other: vec3): number
---@field cross fun(self: vec3, other: vec3): vec3
---@operator add(vec3): vec3
---@operator sub(vec3): vec3
---@operator mul(vec3|number): vec3
---@operator div(vec3|number): vec3
---@operator unm: vec3
local vec3 = {}
vec3.__index = vec3

---Create a 3D vector
---@param x number?
---@param y number?
---@param z number?
---@return vec3
function glm.vec3(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vec3)
end

---@param a vec3
---@param b vec3
---@return vec3
function vec3.__add(a, b)
    return glm.vec3(a.x + b.x, a.y + b.y, a.z + b.z)
end

---@param a vec3
---@param b vec3
---@return vec3
function vec3.__sub(a, b)
    return glm.vec3(a.x - b.x, a.y - b.y, a.z - b.z)
end

---@param a vec3|number
---@param b vec3|number
---@return vec3
function vec3.__mul(a, b)
    if type(a) == "number" then
        ---@cast b vec3
        return glm.vec3(a * b.x, a * b.y, a * b.z)
    elseif type(b) == "number" then
        ---@cast a vec3
        return glm.vec3(a.x * b, a.y * b, a.z * b)
    else
        ---@cast a vec3
        ---@cast b vec3
        return glm.vec3(a.x * b.x, a.y * b.y, a.z * b.z)
    end
end

---@param a vec3
---@param b vec3|number
---@return vec3
function vec3.__div(a, b)
    if type(b) == "number" then
        return glm.vec3(a.x / b, a.y / b, a.z / b)
    else
        ---@cast b vec3
        return glm.vec3(a.x / b.x, a.y / b.y, a.z / b.z)
    end
end

---@param a vec3
---@return vec3
function vec3.__unm(a)
    return glm.vec3(-a.x, -a.y, -a.z)
end

---@param a vec3
---@param b vec3
---@return boolean
function vec3.__eq(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

---@param v vec3
---@return string
function vec3.__tostring(v)
    return string.format("vec3(%.4f, %.4f, %.4f)", v.x, v.y, v.z)
end

---Get the length of the vector
---@return number
function vec3:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

---Get the squared length of the vector
---@return number
function vec3:length2()
    return self.x * self.x + self.y * self.y + self.z * self.z
end

---Get the normalized vector
---@return vec3
function vec3:normalize()
    local len = self:length()
    if len > 0 then
        return glm.vec3(self.x / len, self.y / len, self.z / len)
    end
    return glm.vec3(0, 0, 0)
end

---Dot product
---@param other vec3
---@return number
function vec3:dot(other)
    return self.x * other.x + self.y * other.y + self.z * other.z
end

---Cross product
---@param other vec3
---@return vec3
function vec3:cross(other)
    return glm.vec3(
        self.y * other.z - self.z * other.y,
        self.z * other.x - self.x * other.z,
        self.x * other.y - self.y * other.x
    )
end

--------------------------------------------------------------------------------
-- vec4
--------------------------------------------------------------------------------

---@class vec4: vec_base
---@field x number
---@field y number
---@field z number
---@field w number
---@field length fun(self: vec4): number
---@field length2 fun(self: vec4): number
---@field normalize fun(self: vec4): vec4
---@field dot fun(self: vec4, other: vec4): number
---@operator add(vec4): vec4
---@operator sub(vec4): vec4
---@operator mul(vec4|number): vec4
---@operator div(vec4|number): vec4
---@operator unm: vec4
local vec4 = {}
vec4.__index = vec4

---Create a 4D vector
---@param x number?
---@param y number?
---@param z number?
---@param w number?
---@return vec4
function glm.vec4(x, y, z, w)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w or 0 }, vec4)
end

---@param a vec4
---@param b vec4
---@return vec4
function vec4.__add(a, b)
    return glm.vec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
end

---@param a vec4
---@param b vec4
---@return vec4
function vec4.__sub(a, b)
    return glm.vec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
end

---@param a vec4|number
---@param b vec4|number
---@return vec4
function vec4.__mul(a, b)
    if type(a) == "number" then
        ---@cast b vec4
        return glm.vec4(a * b.x, a * b.y, a * b.z, a * b.w)
    elseif type(b) == "number" then
        ---@cast a vec4
        return glm.vec4(a.x * b, a.y * b, a.z * b, a.w * b)
    else
        ---@cast a vec4
        ---@cast b vec4
        return glm.vec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w)
    end
end

---@param a vec4
---@param b vec4|number
---@return vec4
function vec4.__div(a, b)
    if type(b) == "number" then
        return glm.vec4(a.x / b, a.y / b, a.z / b, a.w / b)
    else
        ---@cast b vec4
        return glm.vec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w)
    end
end

---@param a vec4
---@return vec4
function vec4.__unm(a)
    return glm.vec4(-a.x, -a.y, -a.z, -a.w)
end

---@param a vec4
---@param b vec4
---@return boolean
function vec4.__eq(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
end

---@param v vec4
---@return string
function vec4.__tostring(v)
    return string.format("vec4(%.4f, %.4f, %.4f, %.4f)", v.x, v.y, v.z, v.w)
end

---Get the length of the vector
---@return number
function vec4:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w)
end

---Get the squared length of the vector
---@return number
function vec4:length2()
    return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w
end

---Get the normalized vector
---@return vec4
function vec4:normalize()
    local len = self:length()
    if len > 0 then
        return glm.vec4(self.x / len, self.y / len, self.z / len, self.w / len)
    end
    return glm.vec4(0, 0, 0, 0)
end

---Dot product
---@param other vec4
---@return number
function vec4:dot(other)
    return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w
end

--------------------------------------------------------------------------------
-- mat3 (column-major, for normal matrix)
--------------------------------------------------------------------------------

---@class mat3
---@field [integer] number Column-major matrix elements (1-9)
---@field pack fun(self: mat3): string
---@operator mul(mat3): mat3
---@operator mul(vec3): vec3
local mat3 = {}
mat3.__index = mat3

---Create a 3x3 matrix
---@overload fun(): mat3 Identity matrix
---@overload fun(m1: number, m2: number, m3: number, m4: number, m5: number, m6: number, m7: number, m8: number, m9: number): mat3
---@return mat3
function glm.mat3(...)
    local args = { ... }
    local m = {}
    if #args == 0 then
        m = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
    elseif #args == 9 then
        m = args
    else
        error("mat3: expected 0 or 9 arguments")
    end
    return setmetatable(m, mat3)
end

---@param a mat3
---@param b mat3|vec3
---@return mat3|vec3
function mat3.__mul(a, b)
    if getmetatable(b) == mat3 then
        ---@cast b mat3
        local r = {}
        for col = 0, 2 do
            for row = 0, 2 do
                local sum = 0
                for k = 0, 2 do
                    sum = sum + a[k * 3 + row + 1] * b[col * 3 + k + 1]
                end
                r[#r + 1] = sum
            end
        end
        return setmetatable(r, mat3)
    elseif getmetatable(b) == vec3 then
        ---@cast b vec3
        return glm.vec3(
            a[1] * b.x + a[4] * b.y + a[7] * b.z,
            a[2] * b.x + a[5] * b.y + a[8] * b.z,
            a[3] * b.x + a[6] * b.y + a[9] * b.z
        )
    else
        error("mat3 multiplication: unsupported operand")
    end
end

---@param m mat3
---@return string
function mat3.__tostring(m)
    local rows = {}
    for row = 0, 2 do
        local cols = {}
        for col = 0, 2 do
            cols[#cols + 1] = string.format("%8.4f", m[col * 3 + row + 1])
        end
        rows[#rows + 1] = table.concat(cols, " ")
    end
    return "mat3(\n  " .. table.concat(rows, "\n  ") .. "\n)"
end

---Pack mat3 to binary string for uniforms
---@return string
function mat3:pack()
    return string.pack(string.rep("f", 9), table.unpack(self))
end

---Transpose the matrix
---@return mat3
function mat3:transpose()
    local m = self
    return glm.mat3(
        m[1], m[4], m[7],
        m[2], m[5], m[8],
        m[3], m[6], m[9]
    )
end

---Calculate the inverse of the matrix
---@return mat3
function mat3:inverse()
    local m = self
    local det = m[1] * (m[5] * m[9] - m[8] * m[6])
        - m[4] * (m[2] * m[9] - m[8] * m[3])
        + m[7] * (m[2] * m[6] - m[5] * m[3])
    if math.abs(det) < 1e-10 then
        return glm.mat3()
    end
    local invDet = 1.0 / det
    return glm.mat3(
        (m[5] * m[9] - m[8] * m[6]) * invDet,
        (m[3] * m[8] - m[2] * m[9]) * invDet,
        (m[2] * m[6] - m[3] * m[5]) * invDet,
        (m[6] * m[7] - m[4] * m[9]) * invDet,
        (m[1] * m[9] - m[3] * m[7]) * invDet,
        (m[3] * m[4] - m[1] * m[6]) * invDet,
        (m[4] * m[8] - m[5] * m[7]) * invDet,
        (m[2] * m[7] - m[1] * m[8]) * invDet,
        (m[1] * m[5] - m[2] * m[4]) * invDet
    )
end

--------------------------------------------------------------------------------
-- mat4 (column-major, like OpenGL/GLM)
--------------------------------------------------------------------------------

---@class mat4
---@field [integer] number Column-major matrix elements (1-16)
---@field pack fun(self: mat4): string
---@field unpack fun(self: mat4): number[]
---@operator mul(mat4): mat4
---@operator mul(vec4): vec4
---@operator mul(vec3): vec3
local mat4 = {}
mat4.__index = mat4

---Create a 4x4 matrix
---@overload fun(): mat4 Identity matrix
---@overload fun(diagonal: number): mat4 Diagonal matrix
---@overload fun(m1: number, m2: number, m3: number, m4: number, m5: number, m6: number, m7: number, m8: number, m9: number, m10: number, m11: number, m12: number, m13: number, m14: number, m15: number, m16: number): mat4
---@return mat4
function glm.mat4(...)
    local args = { ... }
    local m = {}
    if #args == 0 then
        -- Identity matrix
        m = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
    elseif #args == 1 and type(args[1]) == "number" then
        -- Diagonal matrix
        local d = args[1]
        m = { d, 0, 0, 0, 0, d, 0, 0, 0, 0, d, 0, 0, 0, 0, d }
    elseif #args == 16 then
        m = args
    else
        error("mat4: expected 0, 1, or 16 arguments")
    end
    return setmetatable(m, mat4)
end

---@param a mat4
---@param b mat4|vec4|vec3
---@return mat4|vec4|vec3
function mat4.__mul(a, b)
    if getmetatable(b) == mat4 then
        ---@cast b mat4
        -- mat4 * mat4
        local r = {}
        for col = 0, 3 do
            for row = 0, 3 do
                local sum = 0
                for k = 0, 3 do
                    sum = sum + a[k * 4 + row + 1] * b[col * 4 + k + 1]
                end
                r[#r + 1] = sum
            end
        end
        return setmetatable(r, mat4)
    elseif getmetatable(b) == vec4 then
        ---@cast b vec4
        -- mat4 * vec4
        return glm.vec4(
            a[1] * b.x + a[5] * b.y + a[9] * b.z + a[13] * b.w,
            a[2] * b.x + a[6] * b.y + a[10] * b.z + a[14] * b.w,
            a[3] * b.x + a[7] * b.y + a[11] * b.z + a[15] * b.w,
            a[4] * b.x + a[8] * b.y + a[12] * b.z + a[16] * b.w
        )
    elseif getmetatable(b) == vec3 then
        ---@cast b vec3
        -- mat4 * vec3 (assume w=1)
        local w = a[4] * b.x + a[8] * b.y + a[12] * b.z + a[16]
        return glm.vec3(
            (a[1] * b.x + a[5] * b.y + a[9] * b.z + a[13]) / w,
            (a[2] * b.x + a[6] * b.y + a[10] * b.z + a[14]) / w,
            (a[3] * b.x + a[7] * b.y + a[11] * b.z + a[15]) / w
        )
    else
        error("mat4 multiplication: unsupported operand")
    end
end

---@param m mat4
---@return string
function mat4.__tostring(m)
    local rows = {}
    for row = 0, 3 do
        local cols = {}
        for col = 0, 3 do
            cols[#cols + 1] = string.format("%8.4f", m[col * 4 + row + 1])
        end
        rows[#rows + 1] = table.concat(cols, " ")
    end
    return "mat4(\n  " .. table.concat(rows, "\n  ") .. "\n)"
end

---Pack mat4 to binary string for uniforms
---@return string
function mat4:pack()
    return string.pack(string.rep("f", 16), table.unpack(self))
end

---Unpack to table of floats
---@return number[]
function mat4:unpack()
    local t = {}
    for i = 1, 16 do
        t[i] = self[i]
    end
    return t
end

---Transpose the matrix
---@return mat4
function mat4:transpose()
    local m = self
    return glm.mat4(
        m[1], m[5], m[9], m[13],
        m[2], m[6], m[10], m[14],
        m[3], m[7], m[11], m[15],
        m[4], m[8], m[12], m[16]
    )
end

---Extract upper-left 3x3 matrix
---@return mat3
function mat4:toMat3()
    local m = self
    return glm.mat3(
        m[1], m[2], m[3],
        m[5], m[6], m[7],
        m[9], m[10], m[11]
    )
end

---Get normal matrix (inverse transpose of upper-left 3x3)
---@return mat3
function mat4:normalMatrix()
    return self:toMat3():inverse():transpose()
end

---Calculate the inverse of the matrix
---@return mat4
function mat4:inverse()
    local m = self
    -- Calculate cofactors
    local c00 = m[6] * m[11] * m[16] - m[6] * m[12] * m[15] - m[10] * m[7] * m[16] + m[10] * m[8] * m[15] +
        m[14] * m[7] * m[12] - m[14] * m[8] * m[11]
    local c01 = -m[5] * m[11] * m[16] + m[5] * m[12] * m[15] + m[9] * m[7] * m[16] - m[9] * m[8] * m[15] -
        m[13] * m[7] * m[12] + m[13] * m[8] * m[11]
    local c02 = m[5] * m[10] * m[16] - m[5] * m[12] * m[14] - m[9] * m[6] * m[16] + m[9] * m[8] * m[14] +
        m[13] * m[6] * m[12] - m[13] * m[8] * m[10]
    local c03 = -m[5] * m[10] * m[15] + m[5] * m[11] * m[14] + m[9] * m[6] * m[15] - m[9] * m[7] * m[14] -
        m[13] * m[6] * m[11] + m[13] * m[7] * m[10]

    local c10 = -m[2] * m[11] * m[16] + m[2] * m[12] * m[15] + m[10] * m[3] * m[16] - m[10] * m[4] * m[15] -
        m[14] * m[3] * m[12] + m[14] * m[4] * m[11]
    local c11 = m[1] * m[11] * m[16] - m[1] * m[12] * m[15] - m[9] * m[3] * m[16] + m[9] * m[4] * m[15] +
        m[13] * m[3] * m[12] - m[13] * m[4] * m[11]
    local c12 = -m[1] * m[10] * m[16] + m[1] * m[12] * m[14] + m[9] * m[2] * m[16] - m[9] * m[4] * m[14] -
        m[13] * m[2] * m[12] + m[13] * m[4] * m[10]
    local c13 = m[1] * m[10] * m[15] - m[1] * m[11] * m[14] - m[9] * m[2] * m[15] + m[9] * m[3] * m[14] +
        m[13] * m[2] * m[11] - m[13] * m[3] * m[10]

    local c20 = m[2] * m[7] * m[16] - m[2] * m[8] * m[15] - m[6] * m[3] * m[16] + m[6] * m[4] * m[15] + m[14] * m[3] *
        m[8] - m[14] * m[4] * m[7]
    local c21 = -m[1] * m[7] * m[16] + m[1] * m[8] * m[15] + m[5] * m[3] * m[16] - m[5] * m[4] * m[15] - m[13] * m[3] *
        m[8] + m[13] * m[4] * m[7]
    local c22 = m[1] * m[6] * m[16] - m[1] * m[8] * m[14] - m[5] * m[2] * m[16] + m[5] * m[4] * m[14] + m[13] * m[2] *
        m[8] - m[13] * m[4] * m[6]
    local c23 = -m[1] * m[6] * m[15] + m[1] * m[7] * m[14] + m[5] * m[2] * m[15] - m[5] * m[3] * m[14] - m[13] * m[2] *
        m[7] + m[13] * m[3] * m[6]

    local c30 = -m[2] * m[7] * m[12] + m[2] * m[8] * m[11] + m[6] * m[3] * m[12] - m[6] * m[4] * m[11] - m[10] * m[3] *
        m[8] + m[10] * m[4] * m[7]
    local c31 = m[1] * m[7] * m[12] - m[1] * m[8] * m[11] - m[5] * m[3] * m[12] + m[5] * m[4] * m[11] + m[9] * m[3] *
        m[8] - m[9] * m[4] * m[7]
    local c32 = -m[1] * m[6] * m[12] + m[1] * m[8] * m[10] + m[5] * m[2] * m[12] - m[5] * m[4] * m[10] - m[9] * m[2] *
        m[8] + m[9] * m[4] * m[6]
    local c33 = m[1] * m[6] * m[11] - m[1] * m[7] * m[10] - m[5] * m[2] * m[11] + m[5] * m[3] * m[10] + m[9] * m[2] *
        m[7] - m[9] * m[3] * m[6]

    -- Determinant
    local det = m[1] * c00 + m[2] * c01 + m[3] * c02 + m[4] * c03
    if math.abs(det) < 1e-10 then
        return glm.mat4() -- Return identity if singular
    end

    local invDet = 1.0 / det
    return glm.mat4(
        c00 * invDet, c10 * invDet, c20 * invDet, c30 * invDet,
        c01 * invDet, c11 * invDet, c21 * invDet, c31 * invDet,
        c02 * invDet, c12 * invDet, c22 * invDet, c32 * invDet,
        c03 * invDet, c13 * invDet, c23 * invDet, c33 * invDet
    )
end

--------------------------------------------------------------------------------
-- quat (quaternion, x, y, z, w order like GLM C++)
--------------------------------------------------------------------------------

---@class quat
---@field x number
---@field y number
---@field z number
---@field w number
---@operator mul(quat): quat
---@operator mul(vec3): vec3
---@operator unm: quat
local quat = {}
quat.__index = quat

---Create a quaternion
---@overload fun(): quat Identity quaternion (0,0,0,1)
---@overload fun(x: number, y: number, z: number, w: number): quat
---@return quat
function glm.quat(x, y, z, w)
    if x == nil then
        return setmetatable({ x = 0, y = 0, z = 0, w = 1 }, quat)
    end
    return setmetatable({ x = x, y = y, z = z, w = w }, quat)
end

---Create a quaternion from axis-angle
---@param axis vec3 Rotation axis (will be normalized)
---@param angle number Angle in radians
---@return quat
function glm.quatAxisAngle(axis, angle)
    local half = angle * 0.5
    local s = math.sin(half)
    local n = axis:normalize()
    return setmetatable({ x = n.x * s, y = n.y * s, z = n.z * s, w = math.cos(half) }, quat)
end

---Create a quaternion from euler angles (pitch, yaw, roll)
---@param pitch number Rotation around X axis in radians
---@param yaw number Rotation around Y axis in radians
---@param roll number Rotation around Z axis in radians
---@return quat
function glm.quatEuler(pitch, yaw, roll)
    local hp = pitch * 0.5
    local hy = yaw * 0.5
    local hr = roll * 0.5
    local cp, sp = math.cos(hp), math.sin(hp)
    local cy, sy = math.cos(hy), math.sin(hy)
    local cr, sr = math.cos(hr), math.sin(hr)
    return setmetatable({
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy,
        w = cr * cp * cy + sr * sp * sy,
    }, quat)
end

---Quaternion multiplication (Hamilton product)
---@param a quat|vec3
---@param b quat|vec3
---@return quat|vec3
function quat.__mul(a, b)
    if getmetatable(a) == quat and getmetatable(b) == quat then
        ---@cast a quat
        ---@cast b quat
        return setmetatable({
            x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        }, quat)
    elseif getmetatable(a) == quat and getmetatable(b) == vec3 then
        ---@cast a quat
        ---@cast b vec3
        -- Optimized q*v*q^-1: t = 2 * cross(q.xyz, v); result = v + q.w*t + cross(q.xyz, t)
        local qx, qy, qz, qw = a.x, a.y, a.z, a.w
        local tx = 2 * (qy * b.z - qz * b.y)
        local ty = 2 * (qz * b.x - qx * b.z)
        local tz = 2 * (qx * b.y - qy * b.x)
        return glm.vec3(
            b.x + qw * tx + (qy * tz - qz * ty),
            b.y + qw * ty + (qz * tx - qx * tz),
            b.z + qw * tz + (qx * ty - qy * tx)
        )
    else
        error("quat multiplication: unsupported operand")
    end
end

---@param a quat
---@return quat
function quat.__unm(a)
    return setmetatable({ x = -a.x, y = -a.y, z = -a.z, w = -a.w }, quat)
end

---@param a quat
---@param b quat
---@return boolean
function quat.__eq(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
end

---@param q quat
---@return string
function quat.__tostring(q)
    return string.format("quat(%.4f, %.4f, %.4f, %.4f)", q.x, q.y, q.z, q.w)
end

---Get the length of the quaternion
---@return number
function quat:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w)
end

---Get the normalized quaternion
---@return quat
function quat:normalize()
    local len = self:length()
    if len > 0 then
        local inv = 1 / len
        return setmetatable({ x = self.x * inv, y = self.y * inv, z = self.z * inv, w = self.w * inv }, quat)
    end
    return glm.quat()
end

---Get the conjugate of the quaternion
---@return quat
function quat:conjugate()
    return setmetatable({ x = -self.x, y = -self.y, z = -self.z, w = self.w }, quat)
end

---Get the inverse of the quaternion
---@return quat
function quat:inverse()
    local len2 = self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w
    if len2 > 0 then
        local inv = 1 / len2
        return setmetatable({ x = -self.x * inv, y = -self.y * inv, z = -self.z * inv, w = self.w * inv }, quat)
    end
    return glm.quat()
end

---Convert quaternion to rotation matrix
---@return mat4
function quat:toMat4()
    local x, y, z, w = self.x, self.y, self.z, self.w
    local x2 = x + x
    local y2 = y + y
    local z2 = z + z
    local xx = x * x2
    local xy = x * y2
    local xz = x * z2
    local yy = y * y2
    local yz = y * z2
    local zz = z * z2
    local wx = w * x2
    local wy = w * y2
    local wz = w * z2
    return glm.mat4(
        1 - (yy + zz), xy + wz, xz - wy, 0,
        xy - wz, 1 - (xx + zz), yz + wx, 0,
        xz + wy, yz - wx, 1 - (xx + yy), 0,
        0, 0, 0, 1
    )
end

---Spherical linear interpolation between two quaternions
---@param a quat
---@param b quat
---@param t number Interpolation factor (0 to 1)
---@return quat
function glm.slerp(a, b, t)
    local dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
    -- Take shortest path
    local bx, by, bz, bw = b.x, b.y, b.z, b.w
    if dot < 0 then
        dot = -dot
        bx, by, bz, bw = -bx, -by, -bz, -bw
    end
    local s0, s1
    if dot > 0.9995 then
        -- Linear interpolation for very close quaternions
        s0 = 1 - t
        s1 = t
    else
        local theta = math.acos(dot)
        local sin_theta = math.sin(theta)
        s0 = math.sin((1 - t) * theta) / sin_theta
        s1 = math.sin(t * theta) / sin_theta
    end
    return setmetatable({
        x = s0 * a.x + s1 * bx,
        y = s0 * a.y + s1 * by,
        z = s0 * a.z + s1 * bz,
        w = s0 * a.w + s1 * bw,
    }, quat)
end

--------------------------------------------------------------------------------
-- Matrix construction functions
--------------------------------------------------------------------------------

---Create an identity matrix
---@return mat4
function glm.identity()
    return glm.mat4()
end

---Create a translation matrix
---@param v vec3
---@return mat4
function glm.translate(v)
    return glm.mat4(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        v.x, v.y, v.z, 1
    )
end

---Create a scale matrix
---@param v vec3|number
---@return mat4
function glm.scale(v)
    if type(v) == "number" then
        return glm.mat4(
            v, 0, 0, 0,
            0, v, 0, 0,
            0, 0, v, 0,
            0, 0, 0, 1
        )
    else
        ---@cast v vec3
        return glm.mat4(
            v.x, 0, 0, 0,
            0, v.y, 0, 0,
            0, 0, v.z, 0,
            0, 0, 0, 1
        )
    end
end

---Create a rotation matrix around an arbitrary axis
---@param angle number Angle in radians
---@param axis vec3 Rotation axis (will be normalized)
---@return mat4
function glm.rotate(angle, axis)
    local c = math.cos(angle)
    local s = math.sin(angle)
    local t = 1 - c
    local n = axis:normalize()
    local x, y, z = n.x, n.y, n.z

    return glm.mat4(
        t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0,
        t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
        t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0,
        0, 0, 0, 1
    )
end

---Create a rotation matrix around the X axis
---@param angle number Angle in radians
---@return mat4
function glm.rotateX(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return glm.mat4(
        1, 0, 0, 0,
        0, c, s, 0,
        0, -s, c, 0,
        0, 0, 0, 1
    )
end

---Create a rotation matrix around the Y axis
---@param angle number Angle in radians
---@return mat4
function glm.rotateY(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return glm.mat4(
        c, 0, -s, 0,
        0, 1, 0, 0,
        s, 0, c, 0,
        0, 0, 0, 1
    )
end

---Create a rotation matrix around the Z axis
---@param angle number Angle in radians
---@return mat4
function glm.rotateZ(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return glm.mat4(
        c, s, 0, 0,
        -s, c, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    )
end

---Create a perspective projection matrix
---@param fovy number Field of view in radians
---@param aspect number Aspect ratio (width/height)
---@param near number Near clipping plane
---@param far number Far clipping plane
---@return mat4
function glm.perspective(fovy, aspect, near, far)
    local f = 1.0 / math.tan(fovy / 2.0)
    return glm.mat4(
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far + near) / (near - far), -1,
        0, 0, (2 * far * near) / (near - far), 0
    )
end

---Create an orthographic projection matrix
---@param left number
---@param right number
---@param bottom number
---@param top number
---@param near number
---@param far number
---@return mat4
function glm.ortho(left, right, bottom, top, near, far)
    return glm.mat4(
        2 / (right - left), 0, 0, 0,
        0, 2 / (top - bottom), 0, 0,
        0, 0, -2 / (far - near), 0,
        -(right + left) / (right - left),
        -(top + bottom) / (top - bottom),
        -(far + near) / (far - near),
        1
    )
end

---Create a look-at view matrix
---@param eye vec3 Camera position
---@param center vec3 Target position
---@param up vec3 Up vector
---@return mat4
function glm.lookat(eye, center, up)
    local f = (center - eye):normalize()
    local s = f:cross(up):normalize()
    local u = s:cross(f)

    return glm.mat4(
        s.x, u.x, -f.x, 0,
        s.y, u.y, -f.y, 0,
        s.z, u.z, -f.z, 0,
        -s:dot(eye), -u:dot(eye), f:dot(eye), 1
    )
end

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

---Convert degrees to radians
---@param degrees number
---@return number
function glm.radians(degrees)
    return degrees * math.pi / 180
end

---Convert radians to degrees
---@param radians number
---@return number
function glm.degrees(radians)
    return radians * 180 / math.pi
end

---Clamp a value between min and max
---@param x number
---@param min number
---@param max number
---@return number
function glm.clamp(x, min, max)
    if x < min then return min end
    if x > max then return max end
    return x
end

---Linear interpolation
---@generic T: number|vec2|vec3|vec4
---@param a T
---@param b T
---@param t number
---@return T
function glm.mix(a, b, t)
    return a + (b - a) * t
end

---Get the length of a vector
---@param v vec_base
---@return number
function glm.length(v)
    return v:length()
end

---Normalize a vector
---@param v vec2
---@return vec2
---@overload fun(v: vec3): vec3
---@overload fun(v: vec4): vec4
function glm.normalize(v)
    return v:normalize()
end

---Dot product of two vectors
---@param a vec_base
---@param b vec_base
---@return number
function glm.dot(a, b)
    return a:dot(b)
end

---Cross product of two vec3
---@param a vec3
---@param b vec3
---@return vec3
function glm.cross(a, b)
    return a:cross(b)
end

return glm
