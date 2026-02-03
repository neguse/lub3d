#define SOKOL_IMPL
#define SOKOL_NO_ENTRY
#ifdef SOKOL_D3D11
/* D3D11 backend */
#elif defined(SOKOL_METAL)
/* Metal backend */
#elif defined(SOKOL_GLCORE)
/* OpenGL backend */
#endif
#include "sokol_log.h"
#include "sokol_app.h"
