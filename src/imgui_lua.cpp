// ImGui Lua bindings for mane3d
#include "imgui.h"
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_imgui.h"

#include <string>

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

// Forward declarations
static int l_imgui_setup(lua_State* L);
static int l_imgui_shutdown(lua_State* L);
static int l_imgui_new_frame(lua_State* L);
static int l_imgui_render(lua_State* L);
static int l_imgui_handle_event(lua_State* L);

// Window functions
static int l_imgui_begin(lua_State* L);
static int l_imgui_end(lua_State* L);

// Widgets
static int l_imgui_text(lua_State* L);
static int l_imgui_text_colored(lua_State* L);
static int l_imgui_button(lua_State* L);
static int l_imgui_checkbox(lua_State* L);
static int l_imgui_slider_float(lua_State* L);
static int l_imgui_slider_int(lua_State* L);
static int l_imgui_color_edit3(lua_State* L);
static int l_imgui_color_edit4(lua_State* L);
static int l_imgui_input_float(lua_State* L);
static int l_imgui_input_float3(lua_State* L);
static int l_imgui_combo(lua_State* L);
static int l_imgui_separator(lua_State* L);
static int l_imgui_same_line(lua_State* L);
static int l_imgui_spacing(lua_State* L);
static int l_imgui_tree_node(lua_State* L);
static int l_imgui_tree_pop(lua_State* L);
static int l_imgui_collapsing_header(lua_State* L);

// Demo
static int l_imgui_show_demo_window(lua_State* L);

// Implementation

static int l_imgui_setup(lua_State* L) {
    simgui_desc_t desc = {};
    // Optional: parse table argument for configuration
    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "max_vertices");
        if (!lua_isnil(L, -1)) desc.max_vertices = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, 1, "no_default_font");
        if (!lua_isnil(L, -1)) desc.no_default_font = lua_toboolean(L, -1);
        lua_pop(L, 1);
    }
    simgui_setup(&desc);
    return 0;
}

static int l_imgui_shutdown(lua_State* L) {
    (void)L;
    simgui_shutdown();
    return 0;
}

static int l_imgui_new_frame(lua_State* L) {
    simgui_frame_desc_t desc = {};
    desc.width = sapp_width();
    desc.height = sapp_height();
    desc.delta_time = sapp_frame_duration();
    desc.dpi_scale = sapp_dpi_scale();
    simgui_new_frame(&desc);
    return 0;
}

static int l_imgui_render(lua_State* L) {
    (void)L;
    simgui_render();
    return 0;
}

static int l_imgui_handle_event(lua_State* L) {
    // Get the event userdata from Lua
    // This expects the sokol_app event to be passed
    const sapp_event* ev = (const sapp_event*)lua_touserdata(L, 1);
    if (ev) {
        bool handled = simgui_handle_event(ev);
        lua_pushboolean(L, handled);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

static int l_imgui_begin(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    bool* p_open = nullptr;
    bool open_val = true;

    // Check for optional p_open boolean
    if (lua_isboolean(L, 2)) {
        open_val = lua_toboolean(L, 2);
        p_open = &open_val;
    }

    ImGuiWindowFlags flags = 0;
    if (lua_istable(L, 3)) {
        lua_getfield(L, 3, "no_titlebar");
        if (lua_toboolean(L, -1)) flags |= ImGuiWindowFlags_NoTitleBar;
        lua_pop(L, 1);

        lua_getfield(L, 3, "no_resize");
        if (lua_toboolean(L, -1)) flags |= ImGuiWindowFlags_NoResize;
        lua_pop(L, 1);

        lua_getfield(L, 3, "no_move");
        if (lua_toboolean(L, -1)) flags |= ImGuiWindowFlags_NoMove;
        lua_pop(L, 1);

        lua_getfield(L, 3, "no_collapse");
        if (lua_toboolean(L, -1)) flags |= ImGuiWindowFlags_NoCollapse;
        lua_pop(L, 1);

        lua_getfield(L, 3, "always_auto_resize");
        if (lua_toboolean(L, -1)) flags |= ImGuiWindowFlags_AlwaysAutoResize;
        lua_pop(L, 1);
    }

    bool result = ImGui::Begin(name, p_open, flags);
    lua_pushboolean(L, result);
    if (p_open) {
        lua_pushboolean(L, open_val);
        return 2;
    }
    return 1;
}

static int l_imgui_end(lua_State* L) {
    (void)L;
    ImGui::End();
    return 0;
}

static int l_imgui_text(lua_State* L) {
    const char* text = luaL_checkstring(L, 1);
    ImGui::TextUnformatted(text);
    return 0;
}

static int l_imgui_text_colored(lua_State* L) {
    float r = (float)luaL_checknumber(L, 1);
    float g = (float)luaL_checknumber(L, 2);
    float b = (float)luaL_checknumber(L, 3);
    float a = (float)luaL_optnumber(L, 4, 1.0);
    const char* text = luaL_checkstring(L, 5);
    ImGui::TextColored(ImVec4(r, g, b, a), "%s", text);
    return 0;
}

static int l_imgui_button(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float w = (float)luaL_optnumber(L, 2, 0);
    float h = (float)luaL_optnumber(L, 3, 0);
    bool result = ImGui::Button(label, ImVec2(w, h));
    lua_pushboolean(L, result);
    return 1;
}

static int l_imgui_checkbox(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool v = lua_toboolean(L, 2);
    bool changed = ImGui::Checkbox(label, &v);
    lua_pushboolean(L, v);
    lua_pushboolean(L, changed);
    return 2;
}

static int l_imgui_slider_float(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float v = (float)luaL_checknumber(L, 2);
    float v_min = (float)luaL_checknumber(L, 3);
    float v_max = (float)luaL_checknumber(L, 4);
    const char* format = luaL_optstring(L, 5, "%.3f");
    bool changed = ImGui::SliderFloat(label, &v, v_min, v_max, format);
    lua_pushnumber(L, v);
    lua_pushboolean(L, changed);
    return 2;
}

static int l_imgui_slider_int(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    int v = (int)luaL_checkinteger(L, 2);
    int v_min = (int)luaL_checkinteger(L, 3);
    int v_max = (int)luaL_checkinteger(L, 4);
    bool changed = ImGui::SliderInt(label, &v, v_min, v_max);
    lua_pushinteger(L, v);
    lua_pushboolean(L, changed);
    return 2;
}

static int l_imgui_color_edit3(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float col[3];
    col[0] = (float)luaL_checknumber(L, 2);
    col[1] = (float)luaL_checknumber(L, 3);
    col[2] = (float)luaL_checknumber(L, 4);
    bool changed = ImGui::ColorEdit3(label, col);
    lua_pushnumber(L, col[0]);
    lua_pushnumber(L, col[1]);
    lua_pushnumber(L, col[2]);
    lua_pushboolean(L, changed);
    return 4;
}

static int l_imgui_color_edit4(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float col[4];
    col[0] = (float)luaL_checknumber(L, 2);
    col[1] = (float)luaL_checknumber(L, 3);
    col[2] = (float)luaL_checknumber(L, 4);
    col[3] = (float)luaL_checknumber(L, 5);
    bool changed = ImGui::ColorEdit4(label, col);
    lua_pushnumber(L, col[0]);
    lua_pushnumber(L, col[1]);
    lua_pushnumber(L, col[2]);
    lua_pushnumber(L, col[3]);
    lua_pushboolean(L, changed);
    return 5;
}

static int l_imgui_input_float(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float v = (float)luaL_checknumber(L, 2);
    float step = (float)luaL_optnumber(L, 3, 0.0f);
    float step_fast = (float)luaL_optnumber(L, 4, 0.0f);
    const char* format = luaL_optstring(L, 5, "%.3f");
    bool changed = ImGui::InputFloat(label, &v, step, step_fast, format);
    lua_pushnumber(L, v);
    lua_pushboolean(L, changed);
    return 2;
}

static int l_imgui_input_float3(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float v[3];
    v[0] = (float)luaL_checknumber(L, 2);
    v[1] = (float)luaL_checknumber(L, 3);
    v[2] = (float)luaL_checknumber(L, 4);
    bool changed = ImGui::InputFloat3(label, v);
    lua_pushnumber(L, v[0]);
    lua_pushnumber(L, v[1]);
    lua_pushnumber(L, v[2]);
    lua_pushboolean(L, changed);
    return 4;
}

static int l_imgui_combo(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    int current = (int)luaL_checkinteger(L, 2) - 1;  // Lua 1-indexed to C 0-indexed

    luaL_checktype(L, 3, LUA_TTABLE);
    int count = (int)lua_rawlen(L, 3);

    // Build items string (null-separated, double-null terminated)
    std::string items_str;
    for (int i = 1; i <= count; i++) {
        lua_rawgeti(L, 3, i);
        const char* item = lua_tostring(L, -1);
        if (item) items_str += item;
        items_str += '\0';
        lua_pop(L, 1);
    }
    items_str += '\0';

    bool changed = ImGui::Combo(label, &current, items_str.c_str());
    lua_pushinteger(L, current + 1);  // Back to Lua 1-indexed
    lua_pushboolean(L, changed);
    return 2;
}

static int l_imgui_separator(lua_State* L) {
    (void)L;
    ImGui::Separator();
    return 0;
}

static int l_imgui_same_line(lua_State* L) {
    float offset = (float)luaL_optnumber(L, 1, 0.0f);
    float spacing = (float)luaL_optnumber(L, 2, -1.0f);
    ImGui::SameLine(offset, spacing);
    return 0;
}

static int l_imgui_spacing(lua_State* L) {
    (void)L;
    ImGui::Spacing();
    return 0;
}

static int l_imgui_tree_node(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool result = ImGui::TreeNode(label);
    lua_pushboolean(L, result);
    return 1;
}

static int l_imgui_tree_pop(lua_State* L) {
    (void)L;
    ImGui::TreePop();
    return 0;
}

static int l_imgui_collapsing_header(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool result = ImGui::CollapsingHeader(label);
    lua_pushboolean(L, result);
    return 1;
}

static int l_imgui_show_demo_window(lua_State* L) {
    bool open = true;
    if (lua_isboolean(L, 1)) {
        open = lua_toboolean(L, 1);
    }
    ImGui::ShowDemoWindow(&open);
    lua_pushboolean(L, open);
    return 1;
}

// Module registration
static const luaL_Reg imgui_funcs[] = {
    {"setup", l_imgui_setup},
    {"shutdown", l_imgui_shutdown},
    {"new_frame", l_imgui_new_frame},
    {"render", l_imgui_render},
    {"handle_event", l_imgui_handle_event},
    {"Begin", l_imgui_begin},
    {"End", l_imgui_end},
    {"Text", l_imgui_text},
    {"TextColored", l_imgui_text_colored},
    {"Button", l_imgui_button},
    {"Checkbox", l_imgui_checkbox},
    {"SliderFloat", l_imgui_slider_float},
    {"SliderInt", l_imgui_slider_int},
    {"ColorEdit3", l_imgui_color_edit3},
    {"ColorEdit4", l_imgui_color_edit4},
    {"InputFloat", l_imgui_input_float},
    {"InputFloat3", l_imgui_input_float3},
    {"Combo", l_imgui_combo},
    {"Separator", l_imgui_separator},
    {"SameLine", l_imgui_same_line},
    {"Spacing", l_imgui_spacing},
    {"TreeNode", l_imgui_tree_node},
    {"TreePop", l_imgui_tree_pop},
    {"CollapsingHeader", l_imgui_collapsing_header},
    {"ShowDemoWindow", l_imgui_show_demo_window},
    {NULL, NULL}
};

extern "C" int luaopen_imgui(lua_State* L) {
    luaL_newlib(L, imgui_funcs);
    return 1;
}
