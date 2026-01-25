// ImGui Lua bindings for mane3d
// Sokol integration functions only
// All ImGui functions are auto-generated in gen/bindings/imgui_gen.cpp

#include "imgui.h"
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_imgui.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

// Sokol integration functions

static int l_imgui_setup(lua_State* L) {
    simgui_desc_t desc = {};
    const char* font_path = NULL;
    float font_size = 18.0f;

    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "max_vertices");
        if (!lua_isnil(L, -1)) desc.max_vertices = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, 1, "no_default_font");
        if (!lua_isnil(L, -1)) desc.no_default_font = lua_toboolean(L, -1);
        lua_pop(L, 1);

        // Japanese font support
        lua_getfield(L, 1, "japanese_font");
        if (!lua_isnil(L, -1)) {
            font_path = lua_tostring(L, -1);
            desc.no_default_font = true;
        }
        lua_pop(L, 1);

        lua_getfield(L, 1, "font_size");
        if (!lua_isnil(L, -1)) font_size = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }

    simgui_setup(&desc);

    // Load Japanese font after simgui_setup
    // Since ImGui 1.92.0, font atlas is automatically handled by sokol_imgui
    if (font_path) {
        ImGuiIO& io = ImGui::GetIO();
        io.Fonts->AddFontFromFileTTF(font_path, font_size, NULL,
            io.Fonts->GetGlyphRangesJapanese());
    }

    return 0;
}

static int l_imgui_shutdown(lua_State* L) {
    (void)L;
    simgui_shutdown();
    return 0;
}

static int l_imgui_new_frame(lua_State* L) {
    (void)L;
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
    const sapp_event* ev = (const sapp_event*)lua_touserdata(L, 1);
    if (ev) {
        bool handled = simgui_handle_event(ev);
        lua_pushboolean(L, handled);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

// Module registration
static const luaL_Reg imgui_sokol_funcs[] = {
    {"setup", l_imgui_setup},
    {"shutdown", l_imgui_shutdown},
    {"new_frame", l_imgui_new_frame},
    {"render", l_imgui_render},
    {"handle_event", l_imgui_handle_event},
    {NULL, NULL}
};

// Auto-generated bindings
extern "C" void luaopen_imgui_gen(lua_State* L, int table_idx);

extern "C" int luaopen_imgui(lua_State* L) {
    luaL_newlib(L, imgui_sokol_funcs);

    // Register auto-generated ImGui functions
    luaopen_imgui_gen(L, lua_gettop(L));

    return 1;
}
