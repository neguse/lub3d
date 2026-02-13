/*
 * glm_lua.c - Lua bindings for HandmadeMath (vec2/vec3/vec4/mat3/mat4)
 * Full userdata with metatables for operator overloading.
 */
#include <lua.h>
#include <lauxlib.h>
#include <string.h>
#include <math.h>

#define HANDMADE_MATH_IMPLEMENTATION
#include "HandmadeMath.h"

/* Metatable names */
#define GLM_VEC2 "glm.vec2"
#define GLM_VEC3 "glm.vec3"
#define GLM_VEC4 "glm.vec4"
#define GLM_MAT3 "glm.mat3"
#define GLM_MAT4 "glm.mat4"
#define GLM_QUAT "glm.quat"

/* ================================================================
 * Helpers
 * ================================================================ */

static HMM_Vec3 *glm_checkvec3(lua_State *L, int idx) {
    return (HMM_Vec3 *)luaL_checkudata(L, idx, GLM_VEC3);
}

static HMM_Vec4 *glm_checkvec4(lua_State *L, int idx) {
    return (HMM_Vec4 *)luaL_checkudata(L, idx, GLM_VEC4);
}

static HMM_Vec2 *glm_checkvec2(lua_State *L, int idx) {
    return (HMM_Vec2 *)luaL_checkudata(L, idx, GLM_VEC2);
}

static HMM_Mat3 *glm_checkmat3(lua_State *L, int idx) {
    return (HMM_Mat3 *)luaL_checkudata(L, idx, GLM_MAT3);
}

static HMM_Mat4 *glm_checkmat4(lua_State *L, int idx) {
    return (HMM_Mat4 *)luaL_checkudata(L, idx, GLM_MAT4);
}

static void glm_pushvec2(lua_State *L, HMM_Vec2 v) {
    HMM_Vec2 *ud = (HMM_Vec2 *)lua_newuserdatauv(L, sizeof(HMM_Vec2), 0);
    *ud = v;
    luaL_setmetatable(L, GLM_VEC2);
}

static void glm_pushvec3(lua_State *L, HMM_Vec3 v) {
    HMM_Vec3 *ud = (HMM_Vec3 *)lua_newuserdatauv(L, sizeof(HMM_Vec3), 0);
    *ud = v;
    luaL_setmetatable(L, GLM_VEC3);
}

static void glm_pushvec4(lua_State *L, HMM_Vec4 v) {
    HMM_Vec4 *ud = (HMM_Vec4 *)lua_newuserdatauv(L, sizeof(HMM_Vec4), 0);
    *ud = v;
    luaL_setmetatable(L, GLM_VEC4);
}

static void glm_pushmat3(lua_State *L, HMM_Mat3 m) {
    HMM_Mat3 *ud = (HMM_Mat3 *)lua_newuserdatauv(L, sizeof(HMM_Mat3), 0);
    *ud = m;
    luaL_setmetatable(L, GLM_MAT3);
}

static void glm_pushmat4(lua_State *L, HMM_Mat4 m) {
    HMM_Mat4 *ud = (HMM_Mat4 *)lua_newuserdatauv(L, sizeof(HMM_Mat4), 0);
    *ud = m;
    luaL_setmetatable(L, GLM_MAT4);
}

/* ================================================================
 * vec2
 * ================================================================ */

static int l_vec2_new(lua_State *L) {
    float x = (float)luaL_optnumber(L, 1, 0);
    float y = (float)luaL_optnumber(L, 2, 0);
    glm_pushvec2(L, HMM_V2(x, y));
    return 1;
}

static int l_vec2_index(lua_State *L) {
    HMM_Vec2 *v = glm_checkvec2(L, 1);
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *key = lua_tostring(L, 2);
        if (key[0] == 'x' && key[1] == '\0') { lua_pushnumber(L, v->X); return 1; }
        if (key[0] == 'y' && key[1] == '\0') { lua_pushnumber(L, v->Y); return 1; }
        /* method lookup from upvalue table */
        lua_pushvalue(L, 2);
        lua_rawget(L, lua_upvalueindex(1));
        return 1;
    }
    return 0;
}

static int l_vec2_newindex(lua_State *L) {
    HMM_Vec2 *v = glm_checkvec2(L, 1);
    const char *key = luaL_checkstring(L, 2);
    float val = (float)luaL_checknumber(L, 3);
    if (key[0] == 'x' && key[1] == '\0') { v->X = val; return 0; }
    if (key[0] == 'y' && key[1] == '\0') { v->Y = val; return 0; }
    return luaL_error(L, "vec2: unknown field '%s'", key);
}

static int l_vec2_add(lua_State *L) {
    glm_pushvec2(L, HMM_AddV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    return 1;
}

static int l_vec2_sub(lua_State *L) {
    glm_pushvec2(L, HMM_SubV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    return 1;
}

static int l_vec2_mul(lua_State *L) {
    if (lua_isnumber(L, 1)) {
        float s = (float)lua_tonumber(L, 1);
        glm_pushvec2(L, HMM_MulV2F(*glm_checkvec2(L, 2), s));
    } else if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec2(L, HMM_MulV2F(*glm_checkvec2(L, 1), s));
    } else {
        glm_pushvec2(L, HMM_MulV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    }
    return 1;
}

static int l_vec2_div(lua_State *L) {
    if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec2(L, HMM_DivV2F(*glm_checkvec2(L, 1), s));
    } else {
        glm_pushvec2(L, HMM_DivV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    }
    return 1;
}

static int l_vec2_unm(lua_State *L) {
    HMM_Vec2 *v = glm_checkvec2(L, 1);
    glm_pushvec2(L, HMM_V2(-v->X, -v->Y));
    return 1;
}

static int l_vec2_eq(lua_State *L) {
    lua_pushboolean(L, HMM_EqV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    return 1;
}

static int l_vec2_tostring(lua_State *L) {
    HMM_Vec2 *v = glm_checkvec2(L, 1);
    lua_pushfstring(L, "vec2(%.4f, %.4f)", (double)v->X, (double)v->Y);
    return 1;
}

static int l_vec2_length(lua_State *L) {
    lua_pushnumber(L, HMM_LenV2(*glm_checkvec2(L, 1)));
    return 1;
}

static int l_vec2_length2(lua_State *L) {
    lua_pushnumber(L, HMM_LenSqrV2(*glm_checkvec2(L, 1)));
    return 1;
}

static int l_vec2_normalize(lua_State *L) {
    glm_pushvec2(L, HMM_NormV2(*glm_checkvec2(L, 1)));
    return 1;
}

static int l_vec2_dot(lua_State *L) {
    lua_pushnumber(L, HMM_DotV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    return 1;
}

/* ================================================================
 * vec3
 * ================================================================ */

static int l_vec3_new(lua_State *L) {
    float x = (float)luaL_optnumber(L, 1, 0);
    float y = (float)luaL_optnumber(L, 2, 0);
    float z = (float)luaL_optnumber(L, 3, 0);
    glm_pushvec3(L, HMM_V3(x, y, z));
    return 1;
}

static int l_vec3_index(lua_State *L) {
    HMM_Vec3 *v = glm_checkvec3(L, 1);
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *key = lua_tostring(L, 2);
        if (key[0] == 'x' && key[1] == '\0') { lua_pushnumber(L, v->X); return 1; }
        if (key[0] == 'y' && key[1] == '\0') { lua_pushnumber(L, v->Y); return 1; }
        if (key[0] == 'z' && key[1] == '\0') { lua_pushnumber(L, v->Z); return 1; }
        lua_pushvalue(L, 2);
        lua_rawget(L, lua_upvalueindex(1));
        return 1;
    }
    return 0;
}

static int l_vec3_newindex(lua_State *L) {
    HMM_Vec3 *v = glm_checkvec3(L, 1);
    const char *key = luaL_checkstring(L, 2);
    float val = (float)luaL_checknumber(L, 3);
    if (key[0] == 'x' && key[1] == '\0') { v->X = val; return 0; }
    if (key[0] == 'y' && key[1] == '\0') { v->Y = val; return 0; }
    if (key[0] == 'z' && key[1] == '\0') { v->Z = val; return 0; }
    return luaL_error(L, "vec3: unknown field '%s'", key);
}

static int l_vec3_add(lua_State *L) {
    glm_pushvec3(L, HMM_AddV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

static int l_vec3_sub(lua_State *L) {
    glm_pushvec3(L, HMM_SubV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

static int l_vec3_mul(lua_State *L) {
    if (lua_isnumber(L, 1)) {
        float s = (float)lua_tonumber(L, 1);
        glm_pushvec3(L, HMM_MulV3F(*glm_checkvec3(L, 2), s));
    } else if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec3(L, HMM_MulV3F(*glm_checkvec3(L, 1), s));
    } else {
        glm_pushvec3(L, HMM_MulV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    }
    return 1;
}

static int l_vec3_div(lua_State *L) {
    if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec3(L, HMM_DivV3F(*glm_checkvec3(L, 1), s));
    } else {
        glm_pushvec3(L, HMM_DivV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    }
    return 1;
}

static int l_vec3_unm(lua_State *L) {
    HMM_Vec3 *v = glm_checkvec3(L, 1);
    glm_pushvec3(L, HMM_V3(-v->X, -v->Y, -v->Z));
    return 1;
}

static int l_vec3_eq(lua_State *L) {
    lua_pushboolean(L, HMM_EqV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

static int l_vec3_tostring(lua_State *L) {
    HMM_Vec3 *v = glm_checkvec3(L, 1);
    lua_pushfstring(L, "vec3(%.4f, %.4f, %.4f)", (double)v->X, (double)v->Y, (double)v->Z);
    return 1;
}

static int l_vec3_length(lua_State *L) {
    lua_pushnumber(L, HMM_LenV3(*glm_checkvec3(L, 1)));
    return 1;
}

static int l_vec3_length2(lua_State *L) {
    lua_pushnumber(L, HMM_LenSqrV3(*glm_checkvec3(L, 1)));
    return 1;
}

static int l_vec3_normalize(lua_State *L) {
    glm_pushvec3(L, HMM_NormV3(*glm_checkvec3(L, 1)));
    return 1;
}

static int l_vec3_dot(lua_State *L) {
    lua_pushnumber(L, HMM_DotV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

static int l_vec3_cross(lua_State *L) {
    glm_pushvec3(L, HMM_Cross(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

/* ================================================================
 * vec4
 * ================================================================ */

static int l_vec4_new(lua_State *L) {
    float x = (float)luaL_optnumber(L, 1, 0);
    float y = (float)luaL_optnumber(L, 2, 0);
    float z = (float)luaL_optnumber(L, 3, 0);
    float w = (float)luaL_optnumber(L, 4, 0);
    glm_pushvec4(L, HMM_V4(x, y, z, w));
    return 1;
}

static int l_vec4_index(lua_State *L) {
    HMM_Vec4 *v = glm_checkvec4(L, 1);
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *key = lua_tostring(L, 2);
        if (key[0] == 'x' && key[1] == '\0') { lua_pushnumber(L, v->X); return 1; }
        if (key[0] == 'y' && key[1] == '\0') { lua_pushnumber(L, v->Y); return 1; }
        if (key[0] == 'z' && key[1] == '\0') { lua_pushnumber(L, v->Z); return 1; }
        if (key[0] == 'w' && key[1] == '\0') { lua_pushnumber(L, v->W); return 1; }
        lua_pushvalue(L, 2);
        lua_rawget(L, lua_upvalueindex(1));
        return 1;
    }
    return 0;
}

static int l_vec4_newindex(lua_State *L) {
    HMM_Vec4 *v = glm_checkvec4(L, 1);
    const char *key = luaL_checkstring(L, 2);
    float val = (float)luaL_checknumber(L, 3);
    if (key[0] == 'x' && key[1] == '\0') { v->X = val; return 0; }
    if (key[0] == 'y' && key[1] == '\0') { v->Y = val; return 0; }
    if (key[0] == 'z' && key[1] == '\0') { v->Z = val; return 0; }
    if (key[0] == 'w' && key[1] == '\0') { v->W = val; return 0; }
    return luaL_error(L, "vec4: unknown field '%s'", key);
}

static int l_vec4_add(lua_State *L) {
    glm_pushvec4(L, HMM_AddV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    return 1;
}

static int l_vec4_sub(lua_State *L) {
    glm_pushvec4(L, HMM_SubV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    return 1;
}

static int l_vec4_mul(lua_State *L) {
    if (lua_isnumber(L, 1)) {
        float s = (float)lua_tonumber(L, 1);
        glm_pushvec4(L, HMM_MulV4F(*glm_checkvec4(L, 2), s));
    } else if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec4(L, HMM_MulV4F(*glm_checkvec4(L, 1), s));
    } else {
        glm_pushvec4(L, HMM_MulV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    }
    return 1;
}

static int l_vec4_div(lua_State *L) {
    if (lua_isnumber(L, 2)) {
        float s = (float)lua_tonumber(L, 2);
        glm_pushvec4(L, HMM_DivV4F(*glm_checkvec4(L, 1), s));
    } else {
        glm_pushvec4(L, HMM_DivV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    }
    return 1;
}

static int l_vec4_unm(lua_State *L) {
    HMM_Vec4 *v = glm_checkvec4(L, 1);
    glm_pushvec4(L, HMM_V4(-v->X, -v->Y, -v->Z, -v->W));
    return 1;
}

static int l_vec4_eq(lua_State *L) {
    lua_pushboolean(L, HMM_EqV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    return 1;
}

static int l_vec4_tostring(lua_State *L) {
    HMM_Vec4 *v = glm_checkvec4(L, 1);
    lua_pushfstring(L, "vec4(%.4f, %.4f, %.4f, %.4f)", (double)v->X, (double)v->Y, (double)v->Z, (double)v->W);
    return 1;
}

static int l_vec4_length(lua_State *L) {
    lua_pushnumber(L, HMM_LenV4(*glm_checkvec4(L, 1)));
    return 1;
}

static int l_vec4_length2(lua_State *L) {
    lua_pushnumber(L, HMM_LenSqrV4(*glm_checkvec4(L, 1)));
    return 1;
}

static int l_vec4_normalize(lua_State *L) {
    glm_pushvec4(L, HMM_NormV4(*glm_checkvec4(L, 1)));
    return 1;
}

static int l_vec4_dot(lua_State *L) {
    lua_pushnumber(L, HMM_DotV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    return 1;
}

/* ================================================================
 * mat3
 * ================================================================ */

static int l_mat3_new(lua_State *L) {
    int n = lua_gettop(L);
    HMM_Mat3 m;
    if (n == 0) {
        memset(&m, 0, sizeof(m));
        m.Elements[0][0] = 1; m.Elements[1][1] = 1; m.Elements[2][2] = 1;
    } else if (n == 9) {
        /* Column-major: args are col0.row0, col0.row1, col0.row2, col1.row0, ... */
        for (int col = 0; col < 3; col++)
            for (int row = 0; row < 3; row++)
                m.Elements[col][row] = (float)luaL_checknumber(L, col * 3 + row + 1);
    } else {
        return luaL_error(L, "mat3: expected 0 or 9 arguments");
    }
    glm_pushmat3(L, m);
    return 1;
}

static int l_mat3_index(lua_State *L) {
    HMM_Mat3 *m = glm_checkmat3(L, 1);
    if (lua_type(L, 2) == LUA_TNUMBER) {
        int idx = (int)lua_tointeger(L, 2) - 1; /* 1-based */
        if (idx < 0 || idx >= 9) return luaL_error(L, "mat3: index out of range");
        lua_pushnumber(L, m->Elements[idx / 3][idx % 3]);
        return 1;
    }
    /* string -> method */
    lua_pushvalue(L, 2);
    lua_rawget(L, lua_upvalueindex(1));
    return 1;
}

static int l_mat3_newindex(lua_State *L) {
    HMM_Mat3 *m = glm_checkmat3(L, 1);
    int idx = (int)luaL_checkinteger(L, 2) - 1;
    if (idx < 0 || idx >= 9) return luaL_error(L, "mat3: index out of range");
    m->Elements[idx / 3][idx % 3] = (float)luaL_checknumber(L, 3);
    return 0;
}

static int l_mat3_mul(lua_State *L) {
    HMM_Mat3 *a = glm_checkmat3(L, 1);
    if (luaL_testudata(L, 2, GLM_MAT3)) {
        glm_pushmat3(L, HMM_MulM3(*a, *glm_checkmat3(L, 2)));
    } else if (luaL_testudata(L, 2, GLM_VEC3)) {
        glm_pushvec3(L, HMM_MulM3V3(*a, *glm_checkvec3(L, 2)));
    } else {
        return luaL_error(L, "mat3 mul: unsupported operand");
    }
    return 1;
}

static int l_mat3_tostring(lua_State *L) {
    HMM_Mat3 *m = glm_checkmat3(L, 1);
    char buf[512];
    int off = 0;
    off += snprintf(buf + off, sizeof(buf) - off, "mat3(\n");
    for (int row = 0; row < 3; row++) {
        off += snprintf(buf + off, sizeof(buf) - off, "  ");
        for (int col = 0; col < 3; col++)
            off += snprintf(buf + off, sizeof(buf) - off, "%8.4f ", (double)m->Elements[col][row]);
        off += snprintf(buf + off, sizeof(buf) - off, "\n");
    }
    off += snprintf(buf + off, sizeof(buf) - off, ")");
    lua_pushstring(L, buf);
    return 1;
}

static int l_mat3_pack(lua_State *L) {
    HMM_Mat3 *m = glm_checkmat3(L, 1);
    /* Column-major float[9] */
    float buf[9];
    for (int col = 0; col < 3; col++)
        for (int row = 0; row < 3; row++)
            buf[col * 3 + row] = m->Elements[col][row];
    lua_pushlstring(L, (const char *)buf, sizeof(buf));
    return 1;
}

static int l_mat3_transpose(lua_State *L) {
    glm_pushmat3(L, HMM_TransposeM3(*glm_checkmat3(L, 1)));
    return 1;
}

/* mat3 inverse (manual, HMM doesn't provide one) */
static int l_mat3_inverse(lua_State *L) {
    HMM_Mat3 *m = glm_checkmat3(L, 1);
    float (*e)[3] = m->Elements;
    float det = e[0][0] * (e[1][1] * e[2][2] - e[2][1] * e[1][2])
              - e[1][0] * (e[0][1] * e[2][2] - e[2][1] * e[0][2])
              + e[2][0] * (e[0][1] * e[1][2] - e[1][1] * e[0][2]);
    if (fabsf(det) < 1e-10f) {
        /* Return identity */
        HMM_Mat3 id;
        memset(&id, 0, sizeof(id));
        id.Elements[0][0] = 1; id.Elements[1][1] = 1; id.Elements[2][2] = 1;
        glm_pushmat3(L, id);
        return 1;
    }
    float inv = 1.0f / det;
    HMM_Mat3 r;
    r.Elements[0][0] = (e[1][1] * e[2][2] - e[2][1] * e[1][2]) * inv;
    r.Elements[0][1] = (e[0][2] * e[2][1] - e[0][1] * e[2][2]) * inv;
    r.Elements[0][2] = (e[0][1] * e[1][2] - e[0][2] * e[1][1]) * inv;
    r.Elements[1][0] = (e[1][2] * e[2][0] - e[1][0] * e[2][2]) * inv;
    r.Elements[1][1] = (e[0][0] * e[2][2] - e[0][2] * e[2][0]) * inv;
    r.Elements[1][2] = (e[1][0] * e[0][2] - e[0][0] * e[1][2]) * inv;
    r.Elements[2][0] = (e[1][0] * e[2][1] - e[2][0] * e[1][1]) * inv;
    r.Elements[2][1] = (e[2][0] * e[0][1] - e[0][0] * e[2][1]) * inv;
    r.Elements[2][2] = (e[0][0] * e[1][1] - e[1][0] * e[0][1]) * inv;
    glm_pushmat3(L, r);
    return 1;
}

/* ================================================================
 * mat4
 * ================================================================ */

static int l_mat4_new(lua_State *L) {
    int n = lua_gettop(L);
    HMM_Mat4 m;
    if (n == 0) {
        m = HMM_M4D(1.0f);
    } else if (n == 1 && lua_isnumber(L, 1)) {
        m = HMM_M4D((float)lua_tonumber(L, 1));
    } else if (n == 16) {
        for (int col = 0; col < 4; col++)
            for (int row = 0; row < 4; row++)
                m.Elements[col][row] = (float)luaL_checknumber(L, col * 4 + row + 1);
    } else {
        return luaL_error(L, "mat4: expected 0, 1, or 16 arguments");
    }
    glm_pushmat4(L, m);
    return 1;
}

static int l_mat4_index(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    if (lua_type(L, 2) == LUA_TNUMBER) {
        int idx = (int)lua_tointeger(L, 2) - 1;
        if (idx < 0 || idx >= 16) return luaL_error(L, "mat4: index out of range");
        lua_pushnumber(L, m->Elements[idx / 4][idx % 4]);
        return 1;
    }
    lua_pushvalue(L, 2);
    lua_rawget(L, lua_upvalueindex(1));
    return 1;
}

static int l_mat4_newindex(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    int idx = (int)luaL_checkinteger(L, 2) - 1;
    if (idx < 0 || idx >= 16) return luaL_error(L, "mat4: index out of range");
    m->Elements[idx / 4][idx % 4] = (float)luaL_checknumber(L, 3);
    return 0;
}

static int l_mat4_mul(lua_State *L) {
    HMM_Mat4 *a = glm_checkmat4(L, 1);
    if (luaL_testudata(L, 2, GLM_MAT4)) {
        glm_pushmat4(L, HMM_MulM4(*a, *glm_checkmat4(L, 2)));
    } else if (luaL_testudata(L, 2, GLM_VEC4)) {
        glm_pushvec4(L, HMM_MulM4V4(*a, *glm_checkvec4(L, 2)));
    } else if (luaL_testudata(L, 2, GLM_VEC3)) {
        /* mat4 * vec3: assume w=1, perspective divide */
        HMM_Vec3 *v = glm_checkvec3(L, 2);
        HMM_Vec4 v4 = HMM_V4(v->X, v->Y, v->Z, 1.0f);
        HMM_Vec4 r = HMM_MulM4V4(*a, v4);
        if (r.W != 0.0f && r.W != 1.0f) {
            r.X /= r.W; r.Y /= r.W; r.Z /= r.W;
        }
        glm_pushvec3(L, HMM_V3(r.X, r.Y, r.Z));
    } else {
        return luaL_error(L, "mat4 mul: unsupported operand");
    }
    return 1;
}

static int l_mat4_tostring(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    char buf[1024];
    int off = 0;
    off += snprintf(buf + off, sizeof(buf) - off, "mat4(\n");
    for (int row = 0; row < 4; row++) {
        off += snprintf(buf + off, sizeof(buf) - off, "  ");
        for (int col = 0; col < 4; col++)
            off += snprintf(buf + off, sizeof(buf) - off, "%8.4f ", (double)m->Elements[col][row]);
        off += snprintf(buf + off, sizeof(buf) - off, "\n");
    }
    off += snprintf(buf + off, sizeof(buf) - off, ")");
    lua_pushstring(L, buf);
    return 1;
}

static int l_mat4_pack(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    lua_pushlstring(L, (const char *)m->Elements, 64);
    return 1;
}

static int l_mat4_unpack(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    lua_createtable(L, 16, 0);
    for (int i = 0; i < 16; i++) {
        lua_pushnumber(L, ((float *)m->Elements)[i]);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

static int l_mat4_inverse(lua_State *L) {
    glm_pushmat4(L, HMM_InvGeneralM4(*glm_checkmat4(L, 1)));
    return 1;
}

static int l_mat4_transpose(lua_State *L) {
    glm_pushmat4(L, HMM_TransposeM4(*glm_checkmat4(L, 1)));
    return 1;
}

static int l_mat4_toMat3(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    HMM_Mat3 r;
    for (int col = 0; col < 3; col++)
        for (int row = 0; row < 3; row++)
            r.Elements[col][row] = m->Elements[col][row];
    glm_pushmat3(L, r);
    return 1;
}

static int l_mat4_normalMatrix(lua_State *L) {
    HMM_Mat4 *m = glm_checkmat4(L, 1);
    /* Extract upper-left 3x3 */
    HMM_Mat3 m3;
    for (int col = 0; col < 3; col++)
        for (int row = 0; row < 3; row++)
            m3.Elements[col][row] = m->Elements[col][row];
    /* Inverse */
    float (*e)[3] = m3.Elements;
    float det = e[0][0] * (e[1][1] * e[2][2] - e[2][1] * e[1][2])
              - e[1][0] * (e[0][1] * e[2][2] - e[2][1] * e[0][2])
              + e[2][0] * (e[0][1] * e[1][2] - e[1][1] * e[0][2]);
    if (fabsf(det) < 1e-10f) {
        HMM_Mat3 id;
        memset(&id, 0, sizeof(id));
        id.Elements[0][0] = 1; id.Elements[1][1] = 1; id.Elements[2][2] = 1;
        glm_pushmat3(L, id);
        return 1;
    }
    float inv = 1.0f / det;
    HMM_Mat3 r;
    r.Elements[0][0] = (e[1][1] * e[2][2] - e[2][1] * e[1][2]) * inv;
    r.Elements[0][1] = (e[0][2] * e[2][1] - e[0][1] * e[2][2]) * inv;
    r.Elements[0][2] = (e[0][1] * e[1][2] - e[0][2] * e[1][1]) * inv;
    r.Elements[1][0] = (e[1][2] * e[2][0] - e[1][0] * e[2][2]) * inv;
    r.Elements[1][1] = (e[0][0] * e[2][2] - e[0][2] * e[2][0]) * inv;
    r.Elements[1][2] = (e[1][0] * e[0][2] - e[0][0] * e[1][2]) * inv;
    r.Elements[2][0] = (e[1][0] * e[2][1] - e[2][0] * e[1][1]) * inv;
    r.Elements[2][1] = (e[2][0] * e[0][1] - e[0][0] * e[2][1]) * inv;
    r.Elements[2][2] = (e[0][0] * e[1][1] - e[1][0] * e[0][1]) * inv;
    /* Transpose */
    glm_pushmat3(L, HMM_TransposeM3(r));
    return 1;
}

/* ================================================================
 * quat
 * ================================================================ */

static HMM_Quat *glm_checkquat(lua_State *L, int idx) {
    return (HMM_Quat *)luaL_checkudata(L, idx, GLM_QUAT);
}

static void glm_pushquat(lua_State *L, HMM_Quat q) {
    HMM_Quat *ud = (HMM_Quat *)lua_newuserdatauv(L, sizeof(HMM_Quat), 0);
    *ud = q;
    luaL_setmetatable(L, GLM_QUAT);
}

static int l_quat_new(lua_State *L) {
    int n = lua_gettop(L);
    if (n == 0) {
        glm_pushquat(L, HMM_Q(0, 0, 0, 1));
    } else if (n == 4) {
        float x = (float)luaL_checknumber(L, 1);
        float y = (float)luaL_checknumber(L, 2);
        float z = (float)luaL_checknumber(L, 3);
        float w = (float)luaL_checknumber(L, 4);
        glm_pushquat(L, HMM_Q(x, y, z, w));
    } else {
        return luaL_error(L, "quat: expected 0 or 4 arguments");
    }
    return 1;
}

static int l_quat_index(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *key = lua_tostring(L, 2);
        if (key[0] == 'x' && key[1] == '\0') { lua_pushnumber(L, q->X); return 1; }
        if (key[0] == 'y' && key[1] == '\0') { lua_pushnumber(L, q->Y); return 1; }
        if (key[0] == 'z' && key[1] == '\0') { lua_pushnumber(L, q->Z); return 1; }
        if (key[0] == 'w' && key[1] == '\0') { lua_pushnumber(L, q->W); return 1; }
        lua_pushvalue(L, 2);
        lua_rawget(L, lua_upvalueindex(1));
        return 1;
    }
    return 0;
}

static int l_quat_newindex(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    const char *key = luaL_checkstring(L, 2);
    float val = (float)luaL_checknumber(L, 3);
    if (key[0] == 'x' && key[1] == '\0') { q->X = val; return 0; }
    if (key[0] == 'y' && key[1] == '\0') { q->Y = val; return 0; }
    if (key[0] == 'z' && key[1] == '\0') { q->Z = val; return 0; }
    if (key[0] == 'w' && key[1] == '\0') { q->W = val; return 0; }
    return luaL_error(L, "quat: unknown field '%s'", key);
}

static int l_quat_mul(lua_State *L) {
    HMM_Quat *a = glm_checkquat(L, 1);
    if (luaL_testudata(L, 2, GLM_QUAT)) {
        glm_pushquat(L, HMM_MulQ(*a, *glm_checkquat(L, 2)));
    } else if (luaL_testudata(L, 2, GLM_VEC3)) {
        glm_pushvec3(L, HMM_RotateV3Q(*glm_checkvec3(L, 2), *a));
    } else {
        return luaL_error(L, "quat mul: unsupported operand");
    }
    return 1;
}

static int l_quat_unm(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    glm_pushquat(L, HMM_Q(-q->X, -q->Y, -q->Z, -q->W));
    return 1;
}

static int l_quat_eq(lua_State *L) {
    HMM_Quat *a = glm_checkquat(L, 1);
    HMM_Quat *b = glm_checkquat(L, 2);
    lua_pushboolean(L, a->X == b->X && a->Y == b->Y && a->Z == b->Z && a->W == b->W);
    return 1;
}

static int l_quat_tostring(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    lua_pushfstring(L, "quat(%.4f, %.4f, %.4f, %.4f)", (double)q->X, (double)q->Y, (double)q->Z, (double)q->W);
    return 1;
}

static int l_quat_length(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    float dot = q->X * q->X + q->Y * q->Y + q->Z * q->Z + q->W * q->W;
    lua_pushnumber(L, sqrtf(dot));
    return 1;
}

static int l_quat_normalize(lua_State *L) {
    glm_pushquat(L, HMM_NormQ(*glm_checkquat(L, 1)));
    return 1;
}

static int l_quat_conjugate(lua_State *L) {
    HMM_Quat *q = glm_checkquat(L, 1);
    glm_pushquat(L, HMM_Q(-q->X, -q->Y, -q->Z, q->W));
    return 1;
}

static int l_quat_inverse(lua_State *L) {
    glm_pushquat(L, HMM_InvQ(*glm_checkquat(L, 1)));
    return 1;
}

static int l_quat_toMat4(lua_State *L) {
    glm_pushmat4(L, HMM_QToM4(*glm_checkquat(L, 1)));
    return 1;
}

static int l_glm_quatAxisAngle(lua_State *L) {
    HMM_Vec3 axis = *glm_checkvec3(L, 1);
    float angle = (float)luaL_checknumber(L, 2);
    glm_pushquat(L, HMM_QFromAxisAngle_RH(axis, angle));
    return 1;
}

static int l_glm_quatEuler(lua_State *L) {
    float pitch = (float)luaL_checknumber(L, 1);
    float yaw = (float)luaL_checknumber(L, 2);
    float roll = (float)luaL_checknumber(L, 3);
    /* Compose as: yaw(Y) * pitch(X) * roll(Z) */
    HMM_Quat qy = HMM_QFromAxisAngle_RH(HMM_V3(0, 1, 0), yaw);
    HMM_Quat qp = HMM_QFromAxisAngle_RH(HMM_V3(1, 0, 0), pitch);
    HMM_Quat qr = HMM_QFromAxisAngle_RH(HMM_V3(0, 0, 1), roll);
    glm_pushquat(L, HMM_MulQ(HMM_MulQ(qy, qp), qr));
    return 1;
}

static int l_glm_slerp(lua_State *L) {
    HMM_Quat a = *glm_checkquat(L, 1);
    HMM_Quat b = *glm_checkquat(L, 2);
    float t = (float)luaL_checknumber(L, 3);
    glm_pushquat(L, HMM_SLerp(a, t, b));
    return 1;
}

/* ================================================================
 * Free functions
 * ================================================================ */

static int l_glm_identity(lua_State *L) {
    glm_pushmat4(L, HMM_M4D(1.0f));
    return 1;
}

static int l_glm_translate(lua_State *L) {
    glm_pushmat4(L, HMM_Translate(*glm_checkvec3(L, 1)));
    return 1;
}

static int l_glm_rotate(lua_State *L) {
    float angle = (float)luaL_checknumber(L, 1);
    HMM_Vec3 axis = *glm_checkvec3(L, 2);
    glm_pushmat4(L, HMM_Rotate_RH(angle, axis));
    return 1;
}

static int l_glm_rotateX(lua_State *L) {
    float angle = (float)luaL_checknumber(L, 1);
    glm_pushmat4(L, HMM_Rotate_RH(angle, HMM_V3(1, 0, 0)));
    return 1;
}

static int l_glm_rotateY(lua_State *L) {
    float angle = (float)luaL_checknumber(L, 1);
    glm_pushmat4(L, HMM_Rotate_RH(angle, HMM_V3(0, 1, 0)));
    return 1;
}

static int l_glm_rotateZ(lua_State *L) {
    float angle = (float)luaL_checknumber(L, 1);
    glm_pushmat4(L, HMM_Rotate_RH(angle, HMM_V3(0, 0, 1)));
    return 1;
}

static int l_glm_scale(lua_State *L) {
    if (lua_isnumber(L, 1)) {
        float s = (float)lua_tonumber(L, 1);
        glm_pushmat4(L, HMM_Scale(HMM_V3(s, s, s)));
    } else {
        glm_pushmat4(L, HMM_Scale(*glm_checkvec3(L, 1)));
    }
    return 1;
}

static int l_glm_perspective(lua_State *L) {
    float fovy = (float)luaL_checknumber(L, 1);
    float aspect = (float)luaL_checknumber(L, 2);
    float near = (float)luaL_checknumber(L, 3);
    float far = (float)luaL_checknumber(L, 4);
    glm_pushmat4(L, HMM_Perspective_RH_NO(fovy, aspect, near, far));
    return 1;
}

static int l_glm_ortho(lua_State *L) {
    float left = (float)luaL_checknumber(L, 1);
    float right = (float)luaL_checknumber(L, 2);
    float bottom = (float)luaL_checknumber(L, 3);
    float top = (float)luaL_checknumber(L, 4);
    float near = (float)luaL_checknumber(L, 5);
    float far = (float)luaL_checknumber(L, 6);
    glm_pushmat4(L, HMM_Orthographic_RH_NO(left, right, bottom, top, near, far));
    return 1;
}

static int l_glm_lookat(lua_State *L) {
    glm_pushmat4(L, HMM_LookAt_RH(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2), *glm_checkvec3(L, 3)));
    return 1;
}

static int l_glm_radians(lua_State *L) {
    lua_pushnumber(L, HMM_ToRad((float)luaL_checknumber(L, 1)));
    return 1;
}

static int l_glm_degrees(lua_State *L) {
    lua_pushnumber(L, HMM_ToDeg((float)luaL_checknumber(L, 1)));
    return 1;
}

static int l_glm_clamp(lua_State *L) {
    float x = (float)luaL_checknumber(L, 1);
    float lo = (float)luaL_checknumber(L, 2);
    float hi = (float)luaL_checknumber(L, 3);
    lua_pushnumber(L, HMM_Clamp(lo, x, hi));
    return 1;
}

static int l_glm_mix(lua_State *L) {
    float t = (float)luaL_checknumber(L, 3);
    if (lua_isnumber(L, 1)) {
        float a = (float)lua_tonumber(L, 1);
        float b = (float)luaL_checknumber(L, 2);
        lua_pushnumber(L, HMM_Lerp(a, t, b));
    } else if (luaL_testudata(L, 1, GLM_VEC2)) {
        glm_pushvec2(L, HMM_LerpV2(*glm_checkvec2(L, 1), t, *glm_checkvec2(L, 2)));
    } else if (luaL_testudata(L, 1, GLM_VEC3)) {
        glm_pushvec3(L, HMM_LerpV3(*glm_checkvec3(L, 1), t, *glm_checkvec3(L, 2)));
    } else if (luaL_testudata(L, 1, GLM_VEC4)) {
        glm_pushvec4(L, HMM_LerpV4(*glm_checkvec4(L, 1), t, *glm_checkvec4(L, 2)));
    } else {
        return luaL_error(L, "mix: unsupported type");
    }
    return 1;
}

static int l_glm_length(lua_State *L) {
    if (luaL_testudata(L, 1, GLM_VEC2)) {
        lua_pushnumber(L, HMM_LenV2(*glm_checkvec2(L, 1)));
    } else if (luaL_testudata(L, 1, GLM_VEC3)) {
        lua_pushnumber(L, HMM_LenV3(*glm_checkvec3(L, 1)));
    } else if (luaL_testudata(L, 1, GLM_VEC4)) {
        lua_pushnumber(L, HMM_LenV4(*glm_checkvec4(L, 1)));
    } else {
        return luaL_error(L, "length: expected vec2/vec3/vec4");
    }
    return 1;
}

static int l_glm_normalize(lua_State *L) {
    if (luaL_testudata(L, 1, GLM_VEC2)) {
        glm_pushvec2(L, HMM_NormV2(*glm_checkvec2(L, 1)));
    } else if (luaL_testudata(L, 1, GLM_VEC3)) {
        glm_pushvec3(L, HMM_NormV3(*glm_checkvec3(L, 1)));
    } else if (luaL_testudata(L, 1, GLM_VEC4)) {
        glm_pushvec4(L, HMM_NormV4(*glm_checkvec4(L, 1)));
    } else {
        return luaL_error(L, "normalize: expected vec2/vec3/vec4");
    }
    return 1;
}

static int l_glm_dot(lua_State *L) {
    if (luaL_testudata(L, 1, GLM_VEC2)) {
        lua_pushnumber(L, HMM_DotV2(*glm_checkvec2(L, 1), *glm_checkvec2(L, 2)));
    } else if (luaL_testudata(L, 1, GLM_VEC3)) {
        lua_pushnumber(L, HMM_DotV3(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    } else if (luaL_testudata(L, 1, GLM_VEC4)) {
        lua_pushnumber(L, HMM_DotV4(*glm_checkvec4(L, 1), *glm_checkvec4(L, 2)));
    } else {
        return luaL_error(L, "dot: expected vec2/vec3/vec4");
    }
    return 1;
}

static int l_glm_cross(lua_State *L) {
    glm_pushvec3(L, HMM_Cross(*glm_checkvec3(L, 1), *glm_checkvec3(L, 2)));
    return 1;
}

/* ================================================================
 * Registration helper: create metatable with __index = upvalue closure
 * ================================================================ */

static void register_vec_type(lua_State *L, const char *tname,
    const luaL_Reg methods[], const luaL_Reg metamethods[],
    lua_CFunction index_fn)
{
    luaL_newmetatable(L, tname);

    /* Build method table as upvalue for __index */
    lua_newtable(L);
    luaL_setfuncs(L, methods, 0);
    /* __index closure with method table as upvalue */
    lua_pushcclosure(L, index_fn, 1);
    lua_setfield(L, -2, "__index");

    /* Set remaining metamethods */
    luaL_setfuncs(L, metamethods, 0);

    lua_pop(L, 1); /* pop metatable */
}

static void register_mat_type(lua_State *L, const char *tname,
    const luaL_Reg methods[], const luaL_Reg metamethods[],
    lua_CFunction index_fn)
{
    luaL_newmetatable(L, tname);

    lua_newtable(L);
    luaL_setfuncs(L, methods, 0);
    lua_pushcclosure(L, index_fn, 1);
    lua_setfield(L, -2, "__index");

    luaL_setfuncs(L, metamethods, 0);

    lua_pop(L, 1);
}

/* ================================================================
 * Module open
 * ================================================================ */

int luaopen_lib_glm(lua_State *L) {
    /* vec2 methods / metamethods */
    static const luaL_Reg vec2_methods[] = {
        {"length", l_vec2_length}, {"length2", l_vec2_length2},
        {"normalize", l_vec2_normalize}, {"dot", l_vec2_dot},
        {NULL, NULL}
    };
    static const luaL_Reg vec2_meta[] = {
        {"__add", l_vec2_add}, {"__sub", l_vec2_sub},
        {"__mul", l_vec2_mul}, {"__div", l_vec2_div},
        {"__unm", l_vec2_unm}, {"__eq", l_vec2_eq},
        {"__tostring", l_vec2_tostring}, {"__newindex", l_vec2_newindex},
        {NULL, NULL}
    };
    register_vec_type(L, GLM_VEC2, vec2_methods, vec2_meta, l_vec2_index);

    /* vec3 methods / metamethods */
    static const luaL_Reg vec3_methods[] = {
        {"length", l_vec3_length}, {"length2", l_vec3_length2},
        {"normalize", l_vec3_normalize}, {"dot", l_vec3_dot},
        {"cross", l_vec3_cross},
        {NULL, NULL}
    };
    static const luaL_Reg vec3_meta[] = {
        {"__add", l_vec3_add}, {"__sub", l_vec3_sub},
        {"__mul", l_vec3_mul}, {"__div", l_vec3_div},
        {"__unm", l_vec3_unm}, {"__eq", l_vec3_eq},
        {"__tostring", l_vec3_tostring}, {"__newindex", l_vec3_newindex},
        {NULL, NULL}
    };
    register_vec_type(L, GLM_VEC3, vec3_methods, vec3_meta, l_vec3_index);

    /* vec4 methods / metamethods */
    static const luaL_Reg vec4_methods[] = {
        {"length", l_vec4_length}, {"length2", l_vec4_length2},
        {"normalize", l_vec4_normalize}, {"dot", l_vec4_dot},
        {NULL, NULL}
    };
    static const luaL_Reg vec4_meta[] = {
        {"__add", l_vec4_add}, {"__sub", l_vec4_sub},
        {"__mul", l_vec4_mul}, {"__div", l_vec4_div},
        {"__unm", l_vec4_unm}, {"__eq", l_vec4_eq},
        {"__tostring", l_vec4_tostring}, {"__newindex", l_vec4_newindex},
        {NULL, NULL}
    };
    register_vec_type(L, GLM_VEC4, vec4_methods, vec4_meta, l_vec4_index);

    /* mat3 methods / metamethods */
    static const luaL_Reg mat3_methods[] = {
        {"pack", l_mat3_pack}, {"transpose", l_mat3_transpose},
        {"inverse", l_mat3_inverse},
        {NULL, NULL}
    };
    static const luaL_Reg mat3_meta[] = {
        {"__mul", l_mat3_mul}, {"__tostring", l_mat3_tostring},
        {"__newindex", l_mat3_newindex},
        {NULL, NULL}
    };
    register_mat_type(L, GLM_MAT3, mat3_methods, mat3_meta, l_mat3_index);

    /* mat4 methods / metamethods */
    static const luaL_Reg mat4_methods[] = {
        {"pack", l_mat4_pack}, {"unpack", l_mat4_unpack},
        {"inverse", l_mat4_inverse}, {"transpose", l_mat4_transpose},
        {"toMat3", l_mat4_toMat3}, {"normalMatrix", l_mat4_normalMatrix},
        {NULL, NULL}
    };
    static const luaL_Reg mat4_meta[] = {
        {"__mul", l_mat4_mul}, {"__tostring", l_mat4_tostring},
        {"__newindex", l_mat4_newindex},
        {NULL, NULL}
    };
    register_mat_type(L, GLM_MAT4, mat4_methods, mat4_meta, l_mat4_index);

    /* quat methods / metamethods */
    static const luaL_Reg quat_methods[] = {
        {"length", l_quat_length}, {"normalize", l_quat_normalize},
        {"conjugate", l_quat_conjugate}, {"inverse", l_quat_inverse},
        {"toMat4", l_quat_toMat4},
        {NULL, NULL}
    };
    static const luaL_Reg quat_meta[] = {
        {"__mul", l_quat_mul}, {"__unm", l_quat_unm},
        {"__eq", l_quat_eq}, {"__tostring", l_quat_tostring},
        {"__newindex", l_quat_newindex},
        {NULL, NULL}
    };
    register_vec_type(L, GLM_QUAT, quat_methods, quat_meta, l_quat_index);

    /* Module table */
    static const luaL_Reg funcs[] = {
        {"vec2", l_vec2_new}, {"vec3", l_vec3_new},
        {"vec4", l_vec4_new}, {"mat3", l_mat3_new}, {"mat4", l_mat4_new},
        {"quat", l_quat_new},
        {"quatAxisAngle", l_glm_quatAxisAngle},
        {"quatEuler", l_glm_quatEuler},
        {"slerp", l_glm_slerp},
        {"identity", l_glm_identity},
        {"translate", l_glm_translate}, {"rotate", l_glm_rotate},
        {"rotateX", l_glm_rotateX}, {"rotateY", l_glm_rotateY},
        {"rotateZ", l_glm_rotateZ}, {"scale", l_glm_scale},
        {"perspective", l_glm_perspective}, {"ortho", l_glm_ortho},
        {"lookat", l_glm_lookat},
        {"radians", l_glm_radians}, {"degrees", l_glm_degrees},
        {"clamp", l_glm_clamp}, {"mix", l_glm_mix},
        {"length", l_glm_length}, {"normalize", l_glm_normalize},
        {"dot", l_glm_dot}, {"cross", l_glm_cross},
        {NULL, NULL}
    };
    luaL_newlib(L, funcs);
    return 1;
}
