/* Sokol implementation - compiled once */
#ifdef SOKOL_DUMMY_BACKEND
/* Override SOKOL_ASSERT to log via sokol logger and exit cleanly (no dialog) */
#include <stdio.h>
#include <stdlib.h>
#ifdef __unix__
#include <unistd.h>
#endif
/* Forward-declare slog_func (defined in sokol_log.h implementation) */
void slog_func(const char* tag, unsigned int log_level, unsigned int log_item,
               const char* message, unsigned int line_nr,
               const char* filename, void* user_data);
static void _lub3d_assert_fail(const char* expr, const char* file, int line) {
    char msg[512];
    snprintf(msg, sizeof(msg), "SOKOL_ASSERT(%s) failed", expr);
    slog_func("assert", 0 /*panic*/, 0, msg, (unsigned int)line, file, 0);
    _exit(42);
}
#define SOKOL_ASSERT(c) do { if (!(c)) _lub3d_assert_fail(#c, __FILE__, __LINE__); } while(0)
#define SOKOL_ABORT() do { _lub3d_assert_fail("ABORT", __FILE__, __LINE__); } while(0)
#endif
#define SOKOL_IMPL
#include "sokol_log.h"
#include "sokol_gfx.h"
#ifndef SOKOL_DUMMY_BACKEND
/* sokol_app requires a real windowing backend - skip for headless testing */
/* SOKOL_NO_ENTRY: Use sapp_run() instead of sokol_main() - Lua controls entry point */
#define SOKOL_NO_ENTRY
#include "sokol_app.h"
#include "sokol_glue.h"
#endif
#include "sokol_time.h"
#include "sokol_audio.h"
#include "sokol_gl.h"
#include "sokol_debugtext.h"
#include "sokol_shape.h"
