/* Stub implementations of sokol_app functions for headless/dummy builds.
   sokol_app.h requires a real windowing backend, but imgui_impl/imgui_sokol
   reference sapp_* symbols. These stubs satisfy the linker. */
#include "sokol_app.h"

int sapp_width(void) { return 800; }
int sapp_height(void) { return 600; }
float sapp_dpi_scale(void) { return 1.0f; }
double sapp_frame_duration(void) { return 1.0 / 60.0; }
void sapp_show_keyboard(bool show) { (void)show; }
bool sapp_keyboard_shown(void) { return false; }
void sapp_set_mouse_cursor(sapp_mouse_cursor cursor) { (void)cursor; }
sapp_mouse_cursor sapp_get_mouse_cursor(void) { return SAPP_MOUSECURSOR_DEFAULT; }
void sapp_consume_event(void) {}
void sapp_set_clipboard_string(const char* str) { (void)str; }
const char* sapp_get_clipboard_string(void) { return ""; }
