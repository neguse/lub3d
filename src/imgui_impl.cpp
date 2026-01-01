// Dear ImGui implementation with sokol_imgui
// This file implements sokol_imgui and the imgui library

#define IMGUI_DEFINE_MATH_OPERATORS
#include "imgui.h"
#include "imgui.cpp"
#include "imgui_draw.cpp"
#include "imgui_tables.cpp"
#include "imgui_widgets.cpp"
#include "imgui_demo.cpp"

#include "sokol_app.h"
#include "sokol_gfx.h"
#define SOKOL_IMGUI_IMPL
#include "sokol_imgui.h"
